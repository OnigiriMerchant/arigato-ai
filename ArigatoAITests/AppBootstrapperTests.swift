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

/// Test-local fake conformer to ``LFM2Engine``. Duplicates the
/// fileprivate fake declared in ``LFM2ModelLoaderTests.swift`` so this
/// suite does not need cross-file visibility. Records every
/// ``warmupCanary(direction:)`` invocation under a lock so concurrent
/// callers can assert exact canary counts and call ordering without
/// data races.
private final class FakeModelRunner: LFM2Engine, @unchecked Sendable {
    var warmupBehaviour: (@Sendable (TranslationDirection) -> Error?)?

    private struct State {
        var directionsCalled: [TranslationDirection] = []
    }

    private let lock = OSAllocatedUnfairLock(initialState: State())

    func warmupCanary(direction: TranslationDirection) async throws {
        lock.withLock { state in
            state.directionsCalled.append(direction)
        }
        if let warmupBehaviour, let error = warmupBehaviour(direction) {
            throw error
        }
    }

    var directionsCalled: [TranslationDirection] {
        lock.withLock { $0.directionsCalled }
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

// MARK: - LFM2 helpers and tests

private func isLFM2Idle(_ state: LFM2LoaderState) -> Bool {
    if case .idle = state { return true }
    return false
}

private func isLFM2Ready(_ state: LFM2LoaderState) -> Bool {
    if case .ready = state { return true }
    return false
}

private func isLFM2FailedWithModelLoadFailed(_ state: LFM2LoaderState) -> Bool {
    guard case let .failed(error) = state else { return false }
    if case .modelLoadFailed = error { return true }
    return false
}

private func isLFM2FailedWithWarmupFailed(_ state: LFM2LoaderState) -> Bool {
    guard case let .failed(error) = state else { return false }
    if case .warmupFailed = error { return true }
    return false
}

@MainActor
private func waitForLFM2LoaderState(
    on bootstrapper: AppBootstrapper,
    matches predicate: (LFM2LoaderState) -> Bool,
    timeout: Duration = .seconds(1)
) async -> Bool {
    let start = ContinuousClock().now
    while ContinuousClock().now - start < timeout {
        if predicate(bootstrapper.lfm2LoaderState) {
            return true
        }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return predicate(bootstrapper.lfm2LoaderState)
}

@MainActor
private func waitForLFM2Progress(
    on bootstrapper: AppBootstrapper,
    matches predicate: (Double?) -> Bool,
    timeout: Duration = .seconds(1)
) async -> Bool {
    let start = ContinuousClock().now
    while ContinuousClock().now - start < timeout {
        if predicate(bootstrapper.lfm2DownloadProgress) {
            return true
        }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return predicate(bootstrapper.lfm2DownloadProgress)
}

/// Holds a `CheckedContinuation` so a test can release a blocked task
/// at a chosen moment. Mirrors ``WhisperModelLoaderTests``' gate;
/// duplicated locally so this suite does not depend on cross-suite
/// visibility.
private final class LFM2ContinuationGate: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock<CheckedContinuation<Void, Never>?>(initialState: nil)

    func wait() async {
        await withCheckedContinuation { continuation in
            lock.withLock { stored in
                stored = continuation
            }
        }
    }

    func release() {
        let continuation = lock.withLock { stored -> CheckedContinuation<Void, Never>? in
            let captured = stored
            stored = nil
            return captured
        }
        continuation?.resume()
    }
}

@Suite("AppBootstrapper LFM2 integration")
@MainActor
struct AppBootstrapperLFM2Tests {
    /// **T6.1.** Asserts that Whisper reaches ``LoaderState/loaded``
    /// before the LFM2 loader's factory is invoked. Locks S6's strict
    /// pipeline ordering: parallel load is not used.
    @Test("T6.1 startPrewarm runs LFM2 after Whisper reaches .loaded")
    func startPrewarm_runsLFM2AfterWhisperReady() async {
        let whisperEngine = FakeWhisperClient()
        let whisperLoader = WhisperModelLoader(factory: { _ in whisperEngine })

        // The factory inspection requires reading the bootstrapper's
        // Whisper state from inside the LFM2 factory closure. We use
        // a deferred reference (box) so the bootstrapper can be
        // assigned before the factory ever runs — `startPrewarm()`
        // is the trigger.
        final class BootstrapperBox: @unchecked Sendable {
            private let lock = OSAllocatedUnfairLock<AppBootstrapper?>(initialState: nil)
            func set(_ value: AppBootstrapper) {
                lock.withLock { $0 = value }
            }

            func get() -> AppBootstrapper? {
                lock.withLock { $0 }
            }
        }
        let box = BootstrapperBox()

        let lfm2Engine = FakeModelRunner()
        let lfm2Gate = LFM2ContinuationGate()
        let lfm2InvokedAfterWhisperLoaded = OSAllocatedUnfairLock(initialState: false)

        let injected = LFM2ModelLoader(factory: { _, _ in
            let observed: Bool
            if let boot = box.get() {
                let whisperState = await boot.loaderState
                switch whisperState {
                case .loaded: observed = true
                default: observed = false
                }
            } else {
                observed = false
            }
            lfm2InvokedAfterWhisperLoaded.withLock { $0 = observed }
            await lfm2Gate.wait()
            return lfm2Engine
        })
        let bootstrapper = AppBootstrapper(loader: whisperLoader, lfm2Loader: injected)
        box.set(bootstrapper)

        bootstrapper.startPrewarm()

        // Let the factory observe Whisper state, then release.
        try? await Task.sleep(for: .milliseconds(150))
        lfm2Gate.release()

        let reachedReady = await waitForLFM2LoaderState(on: bootstrapper, matches: isLFM2Ready)
        #expect(reachedReady, "Expected LFM2 to reach .ready; final state was \(bootstrapper.lfm2LoaderState)")
        #expect(lfm2InvokedAfterWhisperLoaded.withLock { $0 }, "Expected LFM2 factory to be invoked after Whisper reached .loaded")
    }

    /// **T6.2.** When the Whisper loader fails, the bootstrapper must
    /// not attempt the LFM2 chain. The LFM2 loader state stays at
    /// ``LFM2LoaderState/idle``.
    @Test("T6.2 startPrewarm whisper failure does not attempt LFM2")
    func startPrewarm_whisperFails_doesNotAttemptLFM2() async {
        let whisperLoader = WhisperModelLoader(factory: { _ in throw StubError() })
        let lfm2InvokedCounter = CallCounter()
        let lfm2Loader = LFM2ModelLoader(factory: { _, _ in
            lfm2InvokedCounter.increment()
            return FakeModelRunner()
        })

        let bootstrapper = AppBootstrapper(
            loader: whisperLoader,
            lfm2Loader: lfm2Loader
        )

        bootstrapper.startPrewarm()

        // Wait for Whisper failure to propagate.
        let whisperFailed = await waitForLoaderState(
            on: bootstrapper,
            matches: isFailedWithModelLoadFailed
        )
        #expect(whisperFailed, "Expected Whisper failure to surface")

        // Give the detached task a beat to (incorrectly) start LFM2.
        try? await Task.sleep(for: .milliseconds(100))

        #expect(isLFM2Idle(bootstrapper.lfm2LoaderState), "Expected LFM2 to remain .idle when Whisper fails; got \(bootstrapper.lfm2LoaderState)")
        #expect(lfm2InvokedCounter.value == 0, "Expected LFM2 factory to never be invoked when Whisper fails")
    }

    /// **T6.3.** When the LFM2 load fails, the bootstrapper publishes
    /// ``LFM2LoaderState/failed(_:)`` carrying
    /// ``TranslationError/modelLoadFailed(_:)``.
    @Test("T6.3 startPrewarm LFM2 load failure advances to .failed(.modelLoadFailed)")
    func startPrewarm_lfm2LoadFails_advancesToFailedTranslationError() async {
        let whisperEngine = FakeWhisperClient()
        let whisperLoader = WhisperModelLoader(factory: { _ in whisperEngine })

        let lfm2Loader = LFM2ModelLoader(factory: { _, _ in
            throw StubError()
        })

        let bootstrapper = AppBootstrapper(
            loader: whisperLoader,
            lfm2Loader: lfm2Loader
        )

        bootstrapper.startPrewarm()

        let reachedFailed = await waitForLFM2LoaderState(on: bootstrapper, matches: isLFM2FailedWithModelLoadFailed)
        #expect(reachedFailed, "Expected LFM2 state to be .failed(.modelLoadFailed); got \(bootstrapper.lfm2LoaderState)")
    }

    /// **T6.4.** When the LFM2 warmup fails, the bootstrapper publishes
    /// ``LFM2LoaderState/failed(_:)`` carrying
    /// ``TranslationError/warmupFailed(_:)``.
    @Test("T6.4 startPrewarm LFM2 warmup failure advances to .failed(.warmupFailed)")
    func startPrewarm_lfm2WarmupFails_advancesToFailedTranslationError() async {
        let whisperEngine = FakeWhisperClient()
        let whisperLoader = WhisperModelLoader(factory: { _ in whisperEngine })

        let lfm2Engine = FakeModelRunner()
        lfm2Engine.warmupBehaviour = { _ in StubError() }

        let lfm2Loader = LFM2ModelLoader(factory: { _, _ in lfm2Engine })

        let bootstrapper = AppBootstrapper(
            loader: whisperLoader,
            lfm2Loader: lfm2Loader
        )

        bootstrapper.startPrewarm()

        let reachedFailed = await waitForLFM2LoaderState(on: bootstrapper, matches: isLFM2FailedWithWarmupFailed)
        #expect(reachedFailed, "Expected LFM2 state to be .failed(.warmupFailed); got \(bootstrapper.lfm2LoaderState)")
    }

    /// **T6.5.** Happy path — Whisper succeeds, LFM2 loads and warms
    /// up, terminal state is ``LFM2LoaderState/ready``.
    @Test("T6.5 startPrewarm LFM2 happy path advances to .ready")
    func startPrewarm_lfm2HappyPath_advancesToReady() async {
        let whisperEngine = FakeWhisperClient()
        let whisperLoader = WhisperModelLoader(factory: { _ in whisperEngine })

        let lfm2Engine = FakeModelRunner()
        let lfm2Loader = LFM2ModelLoader(factory: { _, _ in lfm2Engine })

        let bootstrapper = AppBootstrapper(
            loader: whisperLoader,
            lfm2Loader: lfm2Loader
        )

        bootstrapper.startPrewarm()

        let reachedReady = await waitForLFM2LoaderState(on: bootstrapper, matches: isLFM2Ready)
        #expect(reachedReady, "Expected LFM2 state to reach .ready; got \(bootstrapper.lfm2LoaderState)")
        #expect(lfm2Engine.directionsCalled == [.enToJa, .jaToEn])
    }

    /// **V7 — A4 violation test.** Uses the bootstrapper's
    /// **default-init trampoline path** (`lfm2Loader: nil`) with a
    /// test-supplied `lfm2Factory` override that fires progress from
    /// a `Task.detached` (non-main-actor context). Asserts the
    /// bootstrapper's
    /// ``AppBootstrapper/lfm2DownloadProgress`` mirror updates to the
    /// fired value, locking the contract that the trampoline hops to
    /// the main actor before mutating observable state.
    ///
    /// Violation pattern: progress callbacks from the LEAP SDK arrive
    /// on the SDK's callback thread; the trampoline must hop to the
    /// main actor first.
    @Test("V7 LFM2 download progress callback routes through main actor")
    func downloadProgress_callbackRoutesToMainActor() async {
        let whisperEngine = FakeWhisperClient()
        let whisperLoader = WhisperModelLoader(factory: { _ in whisperEngine })

        let bootstrapper = AppBootstrapper(
            loader: whisperLoader,
            lfm2Loader: nil,
            lfm2Factory: { _, handler in
                // Fire progress from a non-main-actor context to
                // exercise the trampoline's main-actor hop.
                await Task.detached {
                    handler?(0.42)
                }.value
                return FakeModelRunner()
            }
        )

        bootstrapper.startPrewarm()

        let updated = await waitForLFM2Progress(on: bootstrapper, matches: { $0 == 0.42 })
        #expect(updated, "Expected lfm2DownloadProgress to update to 0.42 via the trampoline's main-actor hop; got \(String(describing: bootstrapper.lfm2DownloadProgress))")
    }

    /// **T6.6.** Calling ``AppBootstrapper/startPrewarm(variant:)``
    /// twice must result in exactly one LFM2 factory invocation. The
    /// loader's A1 coalescing handles this; the bootstrapper must not
    /// race two parallel pipelines.
    @Test("T6.6 startPrewarm called twice — LFM2 coalesced by the loader")
    func startPrewarm_calledTwice_lfm2CoalescedByLoader() async {
        let whisperEngine = FakeWhisperClient()
        let whisperLoader = WhisperModelLoader(factory: { _ in whisperEngine })

        let lfm2Counter = CallCounter()
        let lfm2Engine = FakeModelRunner()
        let lfm2Loader = LFM2ModelLoader(factory: { _, _ in
            lfm2Counter.increment()
            return lfm2Engine
        })

        let bootstrapper = AppBootstrapper(
            loader: whisperLoader,
            lfm2Loader: lfm2Loader
        )

        bootstrapper.startPrewarm()
        bootstrapper.startPrewarm()

        let reachedReady = await waitForLFM2LoaderState(on: bootstrapper, matches: isLFM2Ready)
        #expect(reachedReady, "Expected LFM2 state to reach .ready; got \(bootstrapper.lfm2LoaderState)")

        // Give any in-flight second pipeline a moment to settle.
        try? await Task.sleep(for: .milliseconds(50))

        #expect(lfm2Counter.value == 1, "Expected LFM2 factory invoked exactly once; got \(lfm2Counter.value)")
    }
}
