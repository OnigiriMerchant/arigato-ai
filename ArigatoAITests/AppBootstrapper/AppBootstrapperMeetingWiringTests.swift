//
//  AppBootstrapperMeetingWiringTests.swift
//  ArigatoAITests
//
//  Created by Jose Castell on 2026/05/16.
//

@testable import ArigatoAI
import Foundation
import os
import SwiftData
import Testing

/// Tests for ``AppBootstrapper``'s Step 8 meeting-wiring extension — the
/// ``MeetingStore`` + ``MeetingCoordinator`` publication chain landed in
/// Group D Step 8.
///
/// Five tests:
///
/// 1. `meetingStoreWrites_doNotBlockMainThread_under100SentenceBurst` —
///    Amendment 3 violation test. Asserts that the off-main
///    `MeetingStore.init` path (FB13399899 / Apple Developer Forums
///    736226 workaround) actually delivers a non-blocking executor:
///    100 sequential `appendSentence` calls do not starve a main-actor
///    `Task.yield()` heartbeat.
/// 2. `startPrewarm_constructsCoordinatorOnceWarmupCompletes` — happy
///    path. Drives warmup to ready, asserts both `meetingStore` and
///    `coordinator` are published with a coordinator session in
///    `.idle` and the shared `captureViewModel` object identity is
///    preserved between bootstrapper and coordinator.
/// 3. `startPrewarm_whenContainerIsNil_neverConstructsCoordinator` —
///    short-circuit gate. With `container: nil`, neither
///    `meetingStore` nor `coordinator` is published.
/// 4. `startPrewarm_whenWhisperFails_neverConstructsCoordinator` —
///    early-termination gate. If Whisper fails, the detached task
///    returns before reaching the meeting-wiring section.
/// 5. `startPrewarm_secondInvocation_doesNotOverwriteLiveCoordinator` —
///    Assumption 3 violation test. A second `startPrewarm()` call after
///    the first has published `coordinator` MUST NOT overwrite the
///    live instance.
///
/// All five tests construct the bootstrapper with injected fake loaders
/// (no real Whisper / LFM2 / LEAP SDK dependency) and an in-memory
/// `ModelContainer` registering the `Meeting` / `Sentence` schema.
private final class WiringFakeWhisperClient: WhisperClient, @unchecked Sendable {
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

/// Test-local fake LFM2 engine that satisfies the warmup canary and the
/// translate protocol shape. Mirrors the pattern in
/// ``AppBootstrapperTests`` but kept private so this file does not
/// depend on cross-file visibility.
private final class WiringFakeLFM2Engine: LFM2Engine, @unchecked Sendable {
    func warmupCanary(direction _: TranslationDirection) async throws {
        // Intentionally empty.
    }

    func translate(
        userText _: String,
        direction _: TranslationDirection
    ) -> AsyncThrowingStream<TranslationEngineEvent, any Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }
}

/// Fake `AudioCapturing` for the wiring tests. Production wiring uses
/// `AudioCaptureActor`; the wiring tests don't exercise capture, but
/// `AppBootstrapper.init` constructs an `AudioCaptureViewModel(capture:)`
/// eagerly so we inject a fake to avoid touching the real microphone
/// setup.
private final actor WiringFakeAudioCapture: AudioCapturing {
    func start() async throws {}
    func stop() async {}
    func frameStream() async -> AsyncStream<AudioFrame> {
        AsyncStream { $0.finish() }
    }

    func levelStream() async -> AsyncStream<Float> {
        AsyncStream { $0.finish() }
    }
}

private struct WiringStubError: Error {}

#if DEBUG
    /// Test-local fake LFM2 engine whose `warmupCanary` **throws**. Used by
    /// the DEBUG-seeder reachability test to reproduce the fresh-simulator
    /// path where the LFM2 model is absent: `LFM2ModelLoader.loadIfNeeded`
    /// succeeds (the engine loads) but `warmup()` fails, driving
    /// `startPrewarm`'s LFM2 `.failed` branch and its early return — so the
    /// real Step 8 meeting-wiring block never publishes `meetingStore`.
    private final class WiringFailingWarmupLFM2Engine: LFM2Engine, @unchecked Sendable {
        func warmupCanary(direction _: TranslationDirection) async throws {
            throw WiringStubError()
        }

        func translate(
            userText _: String,
            direction _: TranslationDirection
        ) -> AsyncThrowingStream<TranslationEngineEvent, any Error> {
            AsyncThrowingStream { continuation in
                continuation.finish()
            }
        }
    }

    /// Constructs an ``AppBootstrapper`` whose LFM2 **warmup fails** (the
    /// engine loads but `warmupCanary` throws), reproducing the
    /// fresh-simulator early-return in `startPrewarm`. Mirrors
    /// ``makeWiringBootstrapper(container:whisperFactory:)`` but swaps the
    /// LFM2 engine factory for one that returns a failing-warmup engine.
    @MainActor
    private func makeWarmupFailingBootstrapper(
        container: ModelContainer?,
        whisperFactory: @escaping @Sendable (WhisperModelVariant) async throws -> any WhisperClient = { _ in
            WiringFakeWhisperClient()
        }
    ) -> AppBootstrapper {
        let whisperLoader = WhisperModelLoader(factory: whisperFactory)
        let lfm2Loader = LFM2ModelLoader(factory: { _, _ in WiringFailingWarmupLFM2Engine() })
        return AppBootstrapper(
            loader: whisperLoader,
            lfm2Loader: lfm2Loader,
            container: container,
            capture: WiringFakeAudioCapture()
        )
    }

    /// Polls until ``AppBootstrapper/meetingStore`` is published or the
    /// timeout elapses. Mirrors ``waitForCoordinator(on:timeout:)`` but
    /// targets `meetingStore` — the DEBUG-seeder reachability path publishes
    /// the store *without* a coordinator, so the coordinator poller would
    /// never observe success.
    @MainActor
    private func waitForMeetingStore(
        on bootstrapper: AppBootstrapper,
        timeout: Duration = .seconds(2)
    ) async -> Bool {
        let start = ContinuousClock().now
        while ContinuousClock().now - start < timeout {
            if bootstrapper.meetingStore != nil { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return bootstrapper.meetingStore != nil
    }
#endif

/// Stop-when-coordinator-published polling helper. Mirrors
/// `waitForLoaderState` from ``AppBootstrapperTests``; isolated here so
/// the wiring suite stays self-contained.
@MainActor
private func waitForCoordinator(
    on bootstrapper: AppBootstrapper,
    timeout: Duration = .seconds(2)
) async -> Bool {
    let start = ContinuousClock().now
    while ContinuousClock().now - start < timeout {
        if bootstrapper.coordinator != nil { return true }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return bootstrapper.coordinator != nil
}

/// Builds an in-memory ``ModelContainer`` for ``Meeting`` + ``Sentence``.
/// Each test gets its own container so they leave no on-disk artifacts
/// and do not share state.
private func makeWiringContainer() throws -> ModelContainer {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    return try ModelContainer(
        for: Meeting.self, Sentence.self,
        configurations: config
    )
}

/// Constructs an ``AppBootstrapper`` wired with fakes for Whisper, LFM2,
/// and audio capture. Caller passes the container (or `nil` to exercise
/// the short-circuit gate) and the Whisper factory (so the failure-path
/// test can inject a throwing factory).
@MainActor
private func makeWiringBootstrapper(
    container: ModelContainer?,
    whisperFactory: @escaping @Sendable (WhisperModelVariant) async throws -> any WhisperClient = { _ in
        WiringFakeWhisperClient()
    }
) -> AppBootstrapper {
    let whisperLoader = WhisperModelLoader(factory: whisperFactory)
    let lfm2Loader = LFM2ModelLoader(factory: { _, _ in WiringFakeLFM2Engine() })
    return AppBootstrapper(
        loader: whisperLoader,
        lfm2Loader: lfm2Loader,
        container: container,
        capture: WiringFakeAudioCapture()
    )
}

@Suite("AppBootstrapper meeting wiring (Step 8)")
@MainActor
struct AppBootstrapperMeetingWiringTests {
    /// **Amendment 3 violation test — FB13399899 / Apple Developer
    /// Forums 736226.**
    ///
    /// Asserts that ``AppBootstrapper`` constructs ``MeetingStore`` on
    /// an off-main executor by demonstrating that 100 sequential
    /// `appendSentence` calls do not block a main-actor `Task.yield()`
    /// heartbeat. The heartbeat counter must reach at least 100 yields
    /// within a 250ms window during the burst — if the @ModelActor's
    /// synthesized `DefaultSerialModelExecutor` had inherited the main
    /// thread (the FB13399899 failure mode), each `appendSentence`
    /// would block the heartbeat task and the counter would barely
    /// move.
    ///
    /// **What this test would catch.** A regression that constructs
    /// `MeetingStore` inside `MainActor.run { ... }` instead of inline
    /// in the detached task. The contract is locked by
    /// ``AppBootstrapper/meetingStore``'s "Off-main initialization"
    /// doc-comment which cites FB13399899 verbatim.
    @Test("Amendment 3: 100-sentence burst does not block the main thread")
    func meetingStoreWrites_doNotBlockMainThread_under100SentenceBurst() async throws {
        let container = try makeWiringContainer()
        let bootstrapper = makeWiringBootstrapper(container: container)

        bootstrapper.startPrewarm()

        // Wait for coordinator publication (and hence MeetingStore
        // construction off the main actor).
        let published = await waitForCoordinator(on: bootstrapper)
        #expect(published, "Expected coordinator to be published within timeout")
        guard let store = bootstrapper.meetingStore else {
            Issue.record("meetingStore should be non-nil after coordinator published")
            return
        }

        // Seed a meeting so appendSentence calls have a valid parent.
        let meetingID = try await store.startMeeting(
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            title: "Burst test"
        )

        // Main-actor heartbeat. Increments on every Task.yield() —
        // if the store's executor inherits the main thread, this
        // counter stalls because the actor's writes are serialized
        // ahead of the heartbeat.
        let counter = OSAllocatedUnfairLock(initialState: 0)
        let heartbeat = Task { @MainActor in
            // Bound the heartbeat to ~250ms so the test completes.
            let deadline = ContinuousClock().now + .milliseconds(250)
            while ContinuousClock().now < deadline {
                counter.withLock { $0 += 1 }
                await Task.yield()
            }
        }

        // Fire the burst. Each appendSentence is a write that crosses
        // the @ModelActor boundary — if the executor is main-bound,
        // the heartbeat stalls.
        for index in 0 ..< 100 {
            try await store.appendSentence(
                meetingID: meetingID,
                timestamp: Date(timeIntervalSince1970: 1_700_000_000 + TimeInterval(index)),
                sourceLanguage: "ja",
                sourceText: "burst-\(index)",
                translatedText: "burst-\(index)",
                sourceSegmentID: UUID()
            )
        }

        await heartbeat.value

        let yields = counter.withLock { $0 }
        #expect(
            yields >= 100,
            "Expected main-actor heartbeat ≥100 yields under burst (off-main executor); got \(yields). Suggests MeetingStore.init bound to main thread per FB13399899."
        )
    }

    /// **Happy path / object-identity contract.** Asserts that once
    /// warmup completes, both ``AppBootstrapper/meetingStore`` and
    /// ``AppBootstrapper/coordinator`` are non-nil, the coordinator's
    /// session starts in ``MeetingSessionPhase/idle``, and the
    /// coordinator's `captureViewModel` is **the same instance** as the
    /// bootstrapper's `captureViewModel` (object identity via `===`).
    ///
    /// Object identity is load-bearing because the controls VM closure
    /// chain captures `coordinator.captureViewModel.permissionStatus`
    /// while the audio meter binds to `bootstrapper.captureViewModel.level`.
    /// If the two diverged, taps and UI bindings would be talking to
    /// different VMs.
    @Test("startPrewarm constructs coordinator with shared captureViewModel")
    func startPrewarm_constructsCoordinatorOnceWarmupCompletes() async throws {
        let container = try makeWiringContainer()
        let bootstrapper = makeWiringBootstrapper(container: container)

        bootstrapper.startPrewarm()

        let published = await waitForCoordinator(on: bootstrapper)
        #expect(published, "Expected coordinator to be published within timeout")

        #expect(bootstrapper.meetingStore != nil, "meetingStore should be non-nil after warmup")

        guard let coordinator = bootstrapper.coordinator else {
            Issue.record("coordinator should be non-nil after warmup")
            return
        }

        // Session starts idle.
        let phase = coordinator.session.phase
        if case .idle = phase {
            // Expected.
        } else {
            Issue.record("Expected coordinator.session.phase == .idle; got \(phase)")
        }

        // Object identity (load-bearing — see test doc-comment).
        #expect(
            coordinator.captureViewModel === bootstrapper.captureViewModel,
            "Expected coordinator.captureViewModel === bootstrapper.captureViewModel (object identity)"
        )
    }

    /// **Container short-circuit gate.** When ``AppBootstrapper`` is
    /// constructed with `container: nil`, the detached task's Step 9
    /// guard fires — neither `meetingStore` nor `coordinator` is
    /// published. The UI is expected to render `StartupErrorView` from
    /// `containerError` in this configuration.
    @Test("startPrewarm with nil container never constructs coordinator")
    func startPrewarm_whenContainerIsNil_neverConstructsCoordinator() async {
        let bootstrapper = makeWiringBootstrapper(container: nil)

        bootstrapper.startPrewarm()

        // Wait long enough for the full warmup chain to complete so we
        // know the Step 9 guard fired (rather than warmup still being
        // in flight).
        let start = ContinuousClock().now
        while ContinuousClock().now - start < .seconds(1) {
            if case .ready = bootstrapper.lfm2LoaderState {
                break
            }
            try? await Task.sleep(for: .milliseconds(10))
        }

        // LFM2 must have reached ready — otherwise the detached task is
        // still in warmup and we'd be asserting prematurely.
        if case .ready = bootstrapper.lfm2LoaderState {
            // Expected.
        } else {
            Issue.record("Expected LFM2 to reach .ready; got \(bootstrapper.lfm2LoaderState)")
        }

        // Give the detached task a beat to (incorrectly) construct the
        // coordinator if the short-circuit guard regressed.
        try? await Task.sleep(for: .milliseconds(100))

        #expect(bootstrapper.meetingStore == nil, "Expected meetingStore to remain nil when container is nil")
        #expect(bootstrapper.coordinator == nil, "Expected coordinator to remain nil when container is nil")
    }

    /// **Whisper-failure early-termination gate.** When Whisper warmup
    /// throws, the existing detached-task failure branch returns before
    /// the LFM2 chain even starts — meeting wiring is downstream of
    /// LFM2 ready, so neither `meetingStore` nor `coordinator` should
    /// be published.
    @Test("startPrewarm on Whisper failure never constructs coordinator")
    func startPrewarm_whenWhisperFails_neverConstructsCoordinator() async throws {
        let container = try makeWiringContainer()
        let bootstrapper = makeWiringBootstrapper(
            container: container,
            whisperFactory: { _ in throw WiringStubError() }
        )

        bootstrapper.startPrewarm()

        // Wait for the Whisper failure to publish.
        let start = ContinuousClock().now
        while ContinuousClock().now - start < .seconds(1) {
            if case .failed = bootstrapper.loaderState {
                break
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
        if case .failed = bootstrapper.loaderState {
            // Expected.
        } else {
            Issue.record("Expected Whisper loader to fail; got \(bootstrapper.loaderState)")
        }

        // Give the detached task a beat to (incorrectly) proceed past
        // the failure branch.
        try? await Task.sleep(for: .milliseconds(100))

        #expect(bootstrapper.meetingStore == nil, "Expected meetingStore to remain nil when Whisper fails")
        #expect(bootstrapper.coordinator == nil, "Expected coordinator to remain nil when Whisper fails")
    }

    /// **Assumption 3 violation test — single-instance invariant.**
    ///
    /// Drives `startPrewarm()` to ready. Captures the live coordinator.
    /// Calls `startPrewarm()` again. Drives to ready again. Asserts
    /// `bootstrapper.coordinator === firstCoordinator` — the second
    /// invocation MUST NOT overwrite the live coordinator instance.
    ///
    /// **What this test would catch.** A regression that removes the
    /// idempotency guard (`coordinator == nil`) from the detached
    /// task's tail — without that guard, a second `startPrewarm()`
    /// call would happily construct a fresh `MeetingStore` + fresh
    /// `MeetingCoordinator` and overwrite the published instances,
    /// orphaning any UI bindings or in-flight session state attached
    /// to the original.
    @Test("startPrewarm second invocation does not overwrite live coordinator")
    func startPrewarm_secondInvocation_doesNotOverwriteLiveCoordinator() async throws {
        let container = try makeWiringContainer()
        let bootstrapper = makeWiringBootstrapper(container: container)

        bootstrapper.startPrewarm()

        let firstPublished = await waitForCoordinator(on: bootstrapper)
        #expect(firstPublished, "Expected first invocation to publish coordinator")
        guard let firstCoordinator = bootstrapper.coordinator else {
            Issue.record("First coordinator should be non-nil")
            return
        }

        // Second invocation. Whisper + LFM2 loaders coalesce on their
        // in-flight load tasks (verified by AppBootstrapperTests T6.6)
        // so the second startPrewarm reaches the meeting-wiring tail
        // section without re-running warmup work — at which point the
        // idempotency guard should short-circuit.
        bootstrapper.startPrewarm()

        // Give the detached task time to (incorrectly) replace the
        // coordinator if the idempotency guard regressed.
        try? await Task.sleep(for: .milliseconds(100))

        guard let secondCoordinator = bootstrapper.coordinator else {
            Issue.record("coordinator should remain non-nil after second invocation")
            return
        }

        #expect(
            secondCoordinator === firstCoordinator,
            "Expected coordinator to be unchanged across second startPrewarm; got a different instance (idempotency guard regressed)"
        )
    }

    #if DEBUG
        /// **DEBUG-seeder reachability + store-only convergence (violation
        /// test for ``AppBootstrapper/debugPublishMeetingStoreIfNeeded()``).**
        ///
        /// Reproduces the fresh-simulator failure: LFM2 warmup throws
        /// (`WiringFailingWarmupLFM2Engine.warmupCanary`), so
        /// `startPrewarm`'s LFM2 `.failed` branch returns early — the real
        /// Step 8 block never publishes `meetingStore`. Then
        /// `debugPublishMeetingStoreIfNeeded()` publishes the store on its
        /// own.
        ///
        /// Both publishers are kicked off so the two detached tasks race;
        /// this is also the concurrency violation test for the new method's
        /// documented idempotency / convergence contract. The load-bearing
        /// assertion is **`meetingStore != nil` AND `coordinator == nil`** —
        /// the store-only outcome on the warmup-fail path. (The real path
        /// returns before its `coordinator == nil`-guarded publish, and the
        /// DEBUG method never touches `coordinator`, so a coordinator must
        /// never appear here.)
        ///
        /// A `seed` + `fetchAll` round-trip proves the published store is a
        /// live, writable/readable persistence actor (not a dead reference).
        ///
        /// **What this test would catch.** A regression where the DEBUG
        /// method (a) fails to publish on the warmup-fail path (seeder stays
        /// unreachable), or (b) constructs a coordinator (wiring a dead
        /// LFM2 translate path), or (c) publishes a store that is not
        /// actually backed by the container.
        @Test("debugPublishMeetingStore on warmup failure publishes store only")
        func debugPublishMeetingStore_onWarmupFailure_publishesStoreOnly() async throws {
            let container = try makeWiringContainer()
            let bootstrapper = makeWarmupFailingBootstrapper(container: container)

            // Race the two publishers: the real path (which will fail
            // warmup and never publish) and the DEBUG store-only path.
            bootstrapper.startPrewarm()
            bootstrapper.debugPublishMeetingStoreIfNeeded()

            // Confirm the real path actually took the warmup-fail early
            // return, so we know the store we observe came from the DEBUG
            // method, not from a (non-existent) successful Step 8 publish.
            let start = ContinuousClock().now
            while ContinuousClock().now - start < .seconds(1) {
                if case .failed = bootstrapper.lfm2LoaderState { break }
                try? await Task.sleep(for: .milliseconds(10))
            }
            if case .failed = bootstrapper.lfm2LoaderState {
                // Expected — fresh-simulator reproduction.
            } else {
                Issue.record(
                    "Expected LFM2 to reach .failed (warmup-fail reproduction); got \(bootstrapper.lfm2LoaderState)"
                )
            }

            let published = await waitForMeetingStore(on: bootstrapper)
            #expect(published, "Expected debugPublishMeetingStoreIfNeeded to publish meetingStore within timeout")

            // Give any racing detached task a beat to (incorrectly)
            // construct a coordinator.
            try? await Task.sleep(for: .milliseconds(100))

            // Load-bearing assertion: store-only on the warmup-fail path.
            guard let store = bootstrapper.meetingStore else {
                Issue.record("meetingStore should be non-nil after DEBUG publish")
                return
            }
            #expect(
                bootstrapper.coordinator == nil,
                "Expected coordinator to remain nil on the warmup-fail path (store-only publish)"
            )

            // Round-trip: prove the published store is writable + readable.
            try await DebugMeetingSeeder.seed(into: store)
            let summaries = try await store.fetchAll(searchText: "")
            #expect(
                summaries.count == DebugMeetingSeeder.samples.count,
                "Expected \(DebugMeetingSeeder.samples.count) seeded meetings; got \(summaries.count)"
            )
        }
    #endif
}
