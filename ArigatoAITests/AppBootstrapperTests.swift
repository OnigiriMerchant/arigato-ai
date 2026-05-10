//
//  AppBootstrapperTests.swift
//  ArigatoAITests
//
//  Created by Jose Castell on 2026/05/10.
//

@testable import ArigatoAI
import Foundation
import os
import Testing

/// Test-local fake conformer to ``WhisperClient``. Stateless; the
/// bootstrapper tests only care about lifecycle transitions, not engine
/// behaviour. The transcription stub is trivial because no bootstrapper
/// test exercises ``WhisperClient/transcribe(audio:anchorHostTime:)``;
/// it exists solely so the fake can satisfy the wider
/// ``WhisperClient`` protocol the loader now requires.
private final nonisolated class FakeWhisperClient: WhisperClient, @unchecked Sendable {
    func prewarmModels() async throws {
        // Intentionally empty.
    }

    func transcribe(
        audio _: [Float],
        anchorHostTime: UInt64
    ) async throws -> WhisperWindowResult {
        WhisperWindowResult(
            language: "ja",
            windowAnchorHostTime: anchorHostTime,
            segments: []
        )
    }
}

/// Stub error used to drive the failure paths.
private struct StubError: Error {}

/// Counts factory invocations under a lock so concurrent callers can
/// assert "factory called exactly once" without data races. Uses
/// `OSAllocatedUnfairLock` per the CLAUDE.md Swift 6 rule that bans
/// `NSLock` from async contexts.
private final class CallCounter: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: 0)

    func increment() {
        lock.withLock { $0 += 1 }
    }

    var value: Int {
        lock.withLock { $0 }
    }
}

/// Helper to assert the loader-state pattern without leaking
/// `if case` repetition through the test bodies.
private func isIdle(_ state: LoaderState) -> Bool {
    if case .idle = state { return true }
    return false
}

private func isLoaded(_ state: LoaderState) -> Bool {
    if case .loaded = state { return true }
    return false
}

private func isFailedWithModelLoadFailed(_ state: LoaderState) -> Bool {
    guard case let .failed(error) = state else { return false }
    if case .modelLoadFailed = error { return true }
    return false
}

/// Polls `predicate` against the bootstrapper's `loaderState` on the main
/// actor every 10 ms up to a one-second deadline. Returns `true` if the
/// predicate ever held, `false` if the deadline expired first.
@MainActor
private func waitForLoaderState(
    on bootstrapper: AppBootstrapper,
    matches predicate: (LoaderState) -> Bool,
    timeout: Duration = .seconds(1)
) async -> Bool {
    let start = ContinuousClock().now
    while ContinuousClock().now - start < timeout {
        if predicate(bootstrapper.loaderState) {
            return true
        }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return predicate(bootstrapper.loaderState)
}

@Suite("AppBootstrapper")
@MainActor
struct AppBootstrapperTests {
    @Test("init starts in idle state with no container error")
    func init_startsInIdleStateWithNoContainerError() {
        let bootstrapper = AppBootstrapper()

        #expect(isIdle(bootstrapper.loaderState))
        #expect(bootstrapper.containerError == nil)
    }

    @Test("recordContainerFailure stores the supplied error")
    func recordContainerFailure_setsContainerError() {
        let bootstrapper = AppBootstrapper()

        bootstrapper.recordContainerFailure(StubError())

        #expect(bootstrapper.containerError != nil)
        #expect((bootstrapper.containerError as? StubError) != nil)
    }

    @Test("startPrewarm invokes the loader and advances state to .loaded")
    func startPrewarm_invokesLoaderAndAdvancesStateToLoaded() async {
        let engine = FakeWhisperClient()
        let loader = WhisperModelLoader(factory: { _ in engine })
        let bootstrapper = AppBootstrapper(loader: loader)

        bootstrapper.startPrewarm()

        let reachedLoaded = await waitForLoaderState(
            on: bootstrapper,
            matches: isLoaded
        )
        #expect(reachedLoaded, "Expected loaderState to become .loaded within timeout")
    }

    @Test("startPrewarm advances state to .failed wrapping the loader's TranscriptionError when the factory throws")
    func startPrewarm_factoryFailure_advancesStateToFailedWithTranscriptionError() async {
        let loader = WhisperModelLoader(factory: { _ in
            throw StubError()
        })
        let bootstrapper = AppBootstrapper(loader: loader)

        bootstrapper.startPrewarm()

        let reachedFailed = await waitForLoaderState(
            on: bootstrapper,
            matches: isFailedWithModelLoadFailed
        )
        #expect(reachedFailed, "Expected loaderState to become .failed(.modelLoadFailed) within timeout")
    }

    @Test("startPrewarm called twice does not double-load — coalesced by the loader")
    func startPrewarm_calledTwice_doesNotDoubleLoad() async {
        let counter = CallCounter()
        let engine = FakeWhisperClient()
        let loader = WhisperModelLoader(factory: { _ in
            counter.increment()
            return engine
        })
        let bootstrapper = AppBootstrapper(loader: loader)

        bootstrapper.startPrewarm()
        bootstrapper.startPrewarm()

        let reachedLoaded = await waitForLoaderState(
            on: bootstrapper,
            matches: isLoaded
        )
        #expect(reachedLoaded, "Expected loaderState to become .loaded within timeout")

        // Give any in-flight second call a moment to either coalesce or
        // (incorrectly) trigger a duplicate factory invocation. 50 ms is
        // an order of magnitude beyond any realistic main-actor hop.
        try? await Task.sleep(for: .milliseconds(50))

        #expect(counter.value == 1, "Expected factory to be invoked exactly once; got \(counter.value)")
    }

    /// **D2-T1.** Locks the contract that ``AppBootstrapper`` constructs
    /// the shared ``TranscriptionActor`` and ``LanguageRouter`` during
    /// `init`, before the first ``startPrewarm(variant:)`` call. The
    /// transcriber's warmup state is `.cold` initially because the loader
    /// has not been driven; the router's transcriber reference is the same
    /// actor instance held by the bootstrapper.
    @Test("init constructs the shared transcriber and router")
    func init_constructsTranscriberAndRouter() async {
        let engine = FakeWhisperClient()
        let loader = WhisperModelLoader(factory: { _ in engine })
        let bootstrapper = AppBootstrapper(loader: loader)

        // Transcriber is freshly constructed — its loader-derived warmup
        // state is `.idle`-mirrored-as-`.cold` until startPrewarm runs.
        let warmupState = await bootstrapper.transcriber.warmupState()
        #expect(
            isCold(warmupState),
            "Expected freshly-constructed transcriber to report warmupState == .cold; got \(warmupState)"
        )

        // Router was wired to the same transcriber. We verify presence
        // indirectly via the router's observable surface — see D2-T2 for
        // the initial-state contract.
        #expect(bootstrapper.router.routedHistory.isEmpty)
    }

    /// **D2-T2.** Locks the contract that a freshly-constructed router
    /// exposes a clean initial state — ``LanguageRouter/currentLanguage``
    /// is `nil` and ``LanguageRouter/routedHistory`` is empty. UI bindings
    /// rely on this so the transcript log renders empty before any audio
    /// arrives.
    @Test("router.currentLanguage and routedHistory are nil/empty initially")
    func router_currentLanguage_initiallyNil() {
        let engine = FakeWhisperClient()
        let loader = WhisperModelLoader(factory: { _ in engine })
        let bootstrapper = AppBootstrapper(loader: loader)

        #expect(bootstrapper.router.currentLanguage == nil)
        #expect(bootstrapper.router.routedHistory.isEmpty)
    }
}

/// Helper to assert ``WarmupState/cold`` without leaking pattern-match
/// noise into the test bodies. Mirrors the `isIdle/isLoaded/...`
/// helpers above.
private func isCold(_ state: WarmupState) -> Bool {
    if case .cold = state { return true }
    return false
}
