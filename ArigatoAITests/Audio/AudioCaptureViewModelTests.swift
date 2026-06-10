//
//  AudioCaptureViewModelTests.swift
//  ArigatoAITests
//
//  Created by Jose Castell on 2026/05/09.
//

@testable import ArigatoAI
import Darwin.Mach
import Foundation
import os
import Testing

/// Permission-service fake whose `requestAccess()` suspends until the test
/// releases it — modelling the production suspension window where the
/// system permission dialog is on screen. This is what lets the
/// re-entrancy violation tests drive a second `requestPermission()` call
/// through a *real* suspension point (the synchronous lock-based
/// `FakePermissionService` resolves inline and can never overlap).
///
/// `@MainActor` is spelled out: the test target does not set
/// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` (only the app target does),
/// so the isolation the app module infers for
/// `MicrophonePermissionServicing` conformers must be explicit here.
///
/// Deadlock-free by construction: every suspension (the test on
/// ``waitUntilRequestPending()``, a requester on the gate) frees the main
/// actor, and continuation registration is synchronous inside
/// `withCheckedContinuation` before suspending. The `released` latch makes
/// late requesters return immediately, converting any ordering surprise
/// into a clean call-count assertion failure instead of a hang.
@MainActor
final class SuspendingPermissionService: MicrophonePermissionServicing {
    private(set) var requestCallCount = 0
    private var current: MicrophonePermissionStatus
    private var pendingRequests: [CheckedContinuation<Void, Never>] = []
    private var requestWaiters: [CheckedContinuation<Void, Never>] = []
    private var released = false

    init(initial: MicrophonePermissionStatus) {
        current = initial
    }

    func currentStatus() async -> MicrophonePermissionStatus {
        current
    }

    func requestAccess() async -> MicrophonePermissionStatus {
        requestCallCount += 1
        if !released {
            // Signal any test suspended on `waitUntilRequestPending()` …
            requestWaiters.forEach { $0.resume() }
            requestWaiters.removeAll()
            // … then hold the request open until the "dialog" resolves.
            await withCheckedContinuation { pendingRequests.append($0) }
        }
        return current
    }

    /// Suspends until at least one `requestAccess()` call is held open on
    /// the gate. Returns immediately if one already is, or if the gate has
    /// already been released.
    func waitUntilRequestPending() async {
        if !pendingRequests.isEmpty || released { return }
        await withCheckedContinuation { requestWaiters.append($0) }
    }

    /// Resolves the simulated dialog: publishes `status` and resumes every
    /// held-open `requestAccess()` caller.
    func release(returning status: MicrophonePermissionStatus) {
        current = status
        released = true
        pendingRequests.forEach { $0.resume() }
        pendingRequests.removeAll()
    }
}

/// Fake capture that records calls and exposes controllable streams.
final class FakeCapture: AudioCapturing, @unchecked Sendable {
    private struct State {
        var startCount: Int = 0
        var stopCount: Int = 0
        var shouldThrowOnStart: Bool = false
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    func setShouldThrowOnStart(_ value: Bool) {
        state.withLock { $0.shouldThrowOnStart = value }
    }

    var startCount: Int {
        state.withLock { $0.startCount }
    }

    var stopCount: Int {
        state.withLock { $0.stopCount }
    }

    func start() async throws {
        let shouldThrow = state.withLock { inner -> Bool in
            inner.startCount += 1
            return inner.shouldThrowOnStart
        }
        if shouldThrow {
            throw AudioCaptureError.engineStartFailed("fake")
        }
    }

    func stop() async {
        state.withLock { $0.stopCount += 1 }
    }

    func frameStream() async -> AsyncStream<AudioFrame> {
        AsyncStream { continuation in
            // Leave open until cancelled by the consumer task.
            continuation.onTermination = { _ in }
        }
    }

    func levelStream() async -> AsyncStream<Float> {
        AsyncStream { continuation in
            continuation.onTermination = { _ in }
        }
    }
}

// MARK: - D3 router-pipeline test infrastructure

/// Fake capture whose ``frameStream()`` continuation is exposed for the
/// test to drive. ``yieldFrames(_:)`` lets a test push synthetic
/// ``AudioFrame`` values into the stream synchronously; ``stop()``
/// finishes the continuation so downstream consumers exit cleanly.
///
/// Mirrors ``FakeCapture`` for ergonomic parity with the existing
/// Phase-3 tests but adds the frame-driving side door needed by D3-T1,
/// D3-T2, and D3-T3.
private final class FrameDrivingFakeCapture: AudioCapturing, @unchecked Sendable {
    private struct State {
        var startCount: Int = 0
        var stopCount: Int = 0
        var frameContinuation: AsyncStream<AudioFrame>.Continuation?
        var levelContinuation: AsyncStream<Float>.Continuation?
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    var startCount: Int {
        state.withLock { $0.startCount }
    }

    var stopCount: Int {
        state.withLock { $0.stopCount }
    }

    func start() async throws {
        state.withLock { $0.startCount += 1 }
    }

    func stop() async {
        let (frames, levels) = state.withLock { snapshot -> (
            AsyncStream<AudioFrame>.Continuation?,
            AsyncStream<Float>.Continuation?
        ) in
            snapshot.stopCount += 1
            let frames = snapshot.frameContinuation
            let levels = snapshot.levelContinuation
            snapshot.frameContinuation = nil
            snapshot.levelContinuation = nil
            return (frames, levels)
        }
        frames?.finish()
        levels?.finish()
    }

    func frameStream() async -> AsyncStream<AudioFrame> {
        AsyncStream { continuation in
            self.state.withLock { $0.frameContinuation = continuation }
            continuation.onTermination = { [weak self] _ in
                self?.state.withLock { $0.frameContinuation = nil }
            }
        }
    }

    func levelStream() async -> AsyncStream<Float> {
        AsyncStream { continuation in
            self.state.withLock { $0.levelContinuation = continuation }
            continuation.onTermination = { [weak self] _ in
                self?.state.withLock { $0.levelContinuation = nil }
            }
        }
    }

    /// Yields the supplied frames into the captured frame stream. No-op
    /// if ``frameStream()`` has not been called yet or the stream is
    /// already finished.
    func yieldFrames(_ frames: [AudioFrame]) {
        let continuation = state.withLock { $0.frameContinuation }
        guard let continuation else { return }
        for frame in frames {
            continuation.yield(frame)
        }
    }

    /// Finishes the frame stream without going through ``stop()``. Used
    /// in tests that need to observe the drain task's natural completion
    /// while still asserting on capture lifecycle.
    func finishFrameStream() {
        let continuation = state.withLock { snapshot -> AsyncStream<AudioFrame>.Continuation? in
            let captured = snapshot.frameContinuation
            snapshot.frameContinuation = nil
            return captured
        }
        continuation?.finish()
    }
}

/// Minimal scripted ``WhisperClient`` fake duplicated locally per the
/// Step 3 brief's recommendation: extracting the equivalent fake from
/// ``LanguageRouterTests`` would require modifying that test file
/// (out-of-scope for Step 3). Local duplication keeps the scope clean
/// and isolates this file's test surface.
private final nonisolated class ScriptedLanguageWhisperClient: WhisperClient, @unchecked Sendable {
    private struct State {
        var languages: [String]
        var nextIndex: Int = 0
        var callCount: Int = 0
    }

    private let state: OSAllocatedUnfairLock<State>

    init(languages: [String]) {
        state = OSAllocatedUnfairLock(initialState: State(languages: languages))
    }

    var callCount: Int {
        state.withLock { $0.callCount }
    }

    func prewarmModels() async throws {
        // No-op; warmup is exercised in TranscriptionActorTests.
    }

    func transcribe(
        audio _: [Float],
        anchorHostTime: UInt64
    ) async throws -> WhisperWindowResult {
        let code = state.withLock { snapshot -> String in
            snapshot.callCount += 1
            let index = min(snapshot.nextIndex, snapshot.languages.count - 1)
            let language: String
            if snapshot.languages.isEmpty {
                language = ""
            } else {
                language = snapshot.languages[index]
            }
            snapshot.nextIndex += 1
            return language
        }
        return WhisperWindowResult(
            language: code,
            windowAnchorHostTime: anchorHostTime,
            segments: []
        )
    }
}

/// Builds a synthetic 16 kHz audio frame sequence sized to the
/// ``TranscriptionActor`` prefill / hop math (5 s prefill, 1 s hops).
/// Mirrors ``LanguageRouterTests``'s helper without importing it.
private func makeFrameSequence(
    totalSeconds: Double,
    framesPerSecond: Int = 10,
    startHostTime: UInt64 = 0,
    sampleRate: Double = 16000
) -> [AudioFrame] {
    let frameCount = Int((totalSeconds * Double(framesPerSecond)).rounded())
    let samplesPerFrame = Int(sampleRate / Double(framesPerSecond))
    let nanosPerFrame = 1_000_000_000.0 / Double(framesPerSecond)
    let ticksPerFrame = machTicks(forNanoseconds: nanosPerFrame)
    var frames: [AudioFrame] = []
    frames.reserveCapacity(frameCount)
    for index in 0 ..< frameCount {
        let hostTime = startHostTime &+ (UInt64(index) &* ticksPerFrame)
        let samples = [Float](repeating: 0.0, count: samplesPerFrame)
        frames.append(
            AudioFrame(samples: samples, hostTime: hostTime, frameCount: samplesPerFrame)
        )
    }
    return frames
}

private func machTicks(forNanoseconds nanos: Double) -> UInt64 {
    var info = mach_timebase_info_data_t()
    mach_timebase_info(&info)
    let numer = Double(info.numer)
    let denom = Double(info.denom)
    guard numer > 0 else { return UInt64(nanos.rounded()) }
    let ticks = (nanos * denom / numer).rounded()
    guard ticks >= 0 else { return 0 }
    return UInt64(ticks)
}

/// Polls a MainActor-isolated predicate with a bounded retry budget.
/// Returns `true` if the predicate becomes `true` within `maxAttempts`
/// short sleeps, `false` otherwise. Used by D3-T1/T2/T3 to wait for
/// drain-task progress without coupling to internal scheduling
/// timing. The 50ms cadence matches the project's other wait-and-poll
/// helpers (see ``TranscriptionActorTests``).
@MainActor
private func waitUntil(
    maxAttempts: Int = 60,
    sleepMillis: Int = 50,
    _ predicate: @MainActor () -> Bool
) async -> Bool {
    for _ in 0 ..< maxAttempts {
        if predicate() { return true }
        try? await Task.sleep(for: .milliseconds(sleepMillis))
    }
    return predicate()
}

@Suite("AudioCaptureViewModel state machine")
@MainActor
struct AudioCaptureViewModelTests {
    @Test("onAppear refreshes the cached permission status")
    func onAppearLoadsStatus() async {
        let permissions = FakePermissionService(initial: .granted)
        let capture = FakeCapture()
        let vm = AudioCaptureViewModel(capture: capture, permissionService: permissions)
        await vm.onAppear()
        #expect(vm.permissionStatus == .granted)
        #expect(vm.isRecording == false)
    }

    @Test("toggle when undetermined prompts and starts on grant")
    func toggleUndeterminedPromptsAndStarts() async {
        let permissions = FakePermissionService(initial: .notDetermined, grantOnRequest: true)
        let capture = FakeCapture()
        let vm = AudioCaptureViewModel(capture: capture, permissionService: permissions)
        await vm.onAppear()
        await vm.toggleRecording()
        #expect(vm.permissionStatus == .granted)
        #expect(permissions.requestCallCount == 1)
        #expect(capture.startCount == 1)
        #expect(vm.isRecording == true)
        await vm.toggleRecording()
        #expect(vm.isRecording == false)
        #expect(capture.stopCount == 1)
    }

    @Test("toggle when undetermined and user denies does not start capture")
    func toggleUndeterminedDeniedDoesNotStart() async {
        let permissions = FakePermissionService(initial: .notDetermined, grantOnRequest: false)
        let capture = FakeCapture()
        let vm = AudioCaptureViewModel(capture: capture, permissionService: permissions)
        await vm.onAppear()
        await vm.toggleRecording()
        #expect(vm.permissionStatus == .denied)
        #expect(capture.startCount == 0)
        #expect(vm.isRecording == false)
    }

    @Test("requestPermission prompts when undetermined and publishes granted")
    func requestPermissionPublishesGranted() async {
        let permissions = FakePermissionService(initial: .notDetermined, grantOnRequest: true)
        let vm = AudioCaptureViewModel(capture: FakeCapture(), permissionService: permissions)
        await vm.requestPermission()
        #expect(vm.permissionStatus == .granted)
        #expect(permissions.requestCallCount == 1)
    }

    @Test("requestPermission when undetermined and user denies publishes denied")
    func requestPermissionPublishesDenied() async {
        let permissions = FakePermissionService(initial: .notDetermined, grantOnRequest: false)
        let vm = AudioCaptureViewModel(capture: FakeCapture(), permissionService: permissions)
        await vm.requestPermission()
        #expect(vm.permissionStatus == .denied)
        #expect(permissions.requestCallCount == 1)
    }

    /// Concurrency-design-discipline **violation test** for
    /// ``AudioCaptureViewModel/requestPermission()`` (named in its
    /// doc-comment). Drives the scheduling assumption to its breaking
    /// point: the service suspends mid-request — modelling the system
    /// permission dialog staying on screen — and a second call re-enters
    /// through that suspension window. This is real main-actor
    /// *reentrancy* (serialisation applies between suspension points, not
    /// across whole calls), not the serialised no-overlap case a
    /// synchronous fake produces. The single-flight contract requires the
    /// overlap to coalesce: exactly ONE service request, both calls
    /// complete, and both publish the released status.
    @Test("requestPermission re-entrant call during the system prompt coalesces to one request")
    func requestPermission_reentrantCallDuringSystemPrompt_coalescesToOneRequest() async {
        let permissions = SuspendingPermissionService(initial: .notDetermined)
        let vm = AudioCaptureViewModel(capture: FakeCapture(), permissionService: permissions)
        // Spawn BOTH calls before observing the gate: whichever runs first
        // registers the single-flight slot; the other re-enters during the
        // suspension and must coalesce onto the same in-flight request.
        async let first: Void = vm.requestPermission()
        async let second: Void = vm.requestPermission()
        await permissions.waitUntilRequestPending()
        permissions.release(returning: .granted)
        _ = await (first, second)
        #expect(vm.permissionStatus == .granted)
        #expect(permissions.requestCallCount == 1)
    }

    /// Denied-path variant of the re-entrancy violation test: both
    /// coalesced callers must publish the *denied* resolution — the second
    /// caller may not return early without observing the real decision.
    @Test("requestPermission re-entrant overlap publishes denied to both callers")
    func requestPermission_reentrantOverlap_publishesDeniedToBothCallers() async {
        let permissions = SuspendingPermissionService(initial: .notDetermined)
        let vm = AudioCaptureViewModel(capture: FakeCapture(), permissionService: permissions)
        async let first: Void = vm.requestPermission()
        async let second: Void = vm.requestPermission()
        await permissions.waitUntilRequestPending()
        permissions.release(returning: .denied)
        _ = await (first, second)
        #expect(vm.permissionStatus == .denied)
        #expect(permissions.requestCallCount == 1)
    }

    @Test("toggle when denied is a no-op")
    func toggleWhenDeniedIsNoop() async {
        let permissions = FakePermissionService(initial: .denied)
        let capture = FakeCapture()
        let vm = AudioCaptureViewModel(capture: capture, permissionService: permissions)
        await vm.onAppear()
        await vm.toggleRecording()
        #expect(capture.startCount == 0)
        #expect(vm.isRecording == false)
    }

    @Test("error from start populates errorMessage and leaves isRecording false")
    func startErrorIsSurfaced() async {
        let permissions = FakePermissionService(initial: .granted)
        let capture = FakeCapture()
        capture.setShouldThrowOnStart(true)
        let vm = AudioCaptureViewModel(capture: capture, permissionService: permissions)
        await vm.onAppear()
        await vm.toggleRecording()
        #expect(vm.isRecording == false)
        #expect(vm.errorMessage != nil)
    }

    // MARK: - D3 router-pipeline tests

    /// **D3-T1.** When a router is injected, the view model's drain task
    /// pulls frames through ``LanguageRouter/transcribe(frames:)``.
    /// Confirms one window scripted as `[ja]` lands in
    /// ``LanguageRouter/routedHistory`` with the expected detected and
    /// authoritative language. Locks the contract that
    /// ``AudioCaptureViewModel`` now drives the Phase-4 pipeline rather
    /// than no-op draining frames.
    @Test("D3-T1: startRecording with router drains segment stream")
    func startRecording_withRouter_drainsSegmentStream() async {
        let permissions = FakePermissionService(initial: .granted)
        let capture = FrameDrivingFakeCapture()
        let client = ScriptedLanguageWhisperClient(languages: ["ja"])
        let transcriber = TranscriptionActor(clientFactory: { client })
        let router = LanguageRouter(transcriber: transcriber)

        let vm = AudioCaptureViewModel(
            capture: capture,
            permissionService: permissions,
            router: router
        )
        await vm.onAppear()
        await vm.toggleRecording()
        #expect(vm.isRecording == true)

        // Drive 5 s of audio into the capture stream — exactly one
        // window's worth of prefill, so the actor emits one
        // TranscriptionWindow that the router routes into routedHistory.
        capture.yieldFrames(makeFrameSequence(totalSeconds: 5.0))

        let arrived = await waitUntil { router.routedHistory.count == 1 }
        #expect(arrived)
        #expect(router.routedHistory.count == 1)
        if let only = router.routedHistory.first {
            #expect(only.detectedLanguage == .ja)
            #expect(only.authoritativeLanguage == .ja)
        } else {
            Issue.record("Expected exactly one entry in routedHistory")
        }
        #expect(router.currentLanguage == .ja)

        await vm.toggleRecording()
        #expect(vm.isRecording == false)
        #expect(vm.errorMessage == nil)
        #expect(capture.stopCount == 1)
    }

    /// **D3-T2.** ``stopRecording()`` must cancel the router BEFORE
    /// stopping the capture engine so the C29 cancellation contract
    /// applies cleanly: the router's segment stream finishes without
    /// throwing, the drain task exits cooperatively, no
    /// ``errorMessage`` is published. Drives one window of frames,
    /// waits for the routed entry to land (proves the drain task is
    /// alive and in the for-await loop), then stops and asserts clean
    /// teardown.
    @Test("D3-T2: stopRecording with router cancels router first")
    func stopRecording_withRouter_cancelsRouterFirst() async {
        let permissions = FakePermissionService(initial: .granted)
        let capture = FrameDrivingFakeCapture()
        let client = ScriptedLanguageWhisperClient(languages: ["ja"])
        let transcriber = TranscriptionActor(clientFactory: { client })
        let router = LanguageRouter(transcriber: transcriber)

        let vm = AudioCaptureViewModel(
            capture: capture,
            permissionService: permissions,
            router: router
        )
        await vm.onAppear()
        await vm.toggleRecording()
        #expect(vm.isRecording == true)

        // Drive one window so the drain task is actively iterating
        // through the router's segment stream when we stop.
        capture.yieldFrames(makeFrameSequence(totalSeconds: 5.0))
        let arrived = await waitUntil { router.routedHistory.count == 1 }
        #expect(arrived)

        await vm.toggleRecording()
        #expect(vm.isRecording == false)
        #expect(vm.errorMessage == nil)
        #expect(capture.stopCount == 1)

        // Drain task has been cancelled; an additional bounded wait
        // confirms no late errorMessage is published.
        let stayedClean = await waitUntil(maxAttempts: 4) {
            vm.errorMessage != nil
        }
        #expect(stayedClean == false)
    }

    /// **D3-T3 (concurrency-discipline violation test).** Drives a
    /// greedy upstream — yields ~100 frames synchronously into the
    /// frame stream before stopping — to violate the happy-path
    /// scheduling assumption that frames arrive one window at a time.
    /// 100 frames at 10 frames/s is 10 seconds of audio, which produces
    /// up to 6 hops behind a 5 s prefill. The
    /// ``TranscriptionActor``'s bounded queue (``maxPendingHops`` = 4,
    /// contract C30) and the router's MainActor-paced drain are now
    /// driven simultaneously.
    ///
    /// The contract under test (declared in
    /// ``AudioCaptureViewModel``'s "Scheduling assumption"
    /// doc-comment): under burst upstream, ``stopRecording()`` is
    /// bounded and clean — `isRecording` becomes `false`, no
    /// ``errorMessage`` is published, and the drain task exits within
    /// the bounded wait. ``LanguageRouter/routedHistory`` is allowed
    /// to contain 0..N entries; the count is non-deterministic under
    /// burst but the system MUST NOT hang or error.
    @Test("D3-T3: stopRecording with router under burst upstream finishes cleanly")
    func stopRecording_withRouter_underBurstUpstream_finishesCleanly() async {
        let permissions = FakePermissionService(initial: .granted)
        let capture = FrameDrivingFakeCapture()
        // Provide enough scripted languages that any number of windows
        // (up to a generous bound) reuses the trailing entry.
        let client = ScriptedLanguageWhisperClient(
            languages: ["ja", "ja", "ja", "ja", "ja", "ja", "ja", "ja"]
        )
        let transcriber = TranscriptionActor(clientFactory: { client })
        let router = LanguageRouter(transcriber: transcriber)

        let vm = AudioCaptureViewModel(
            capture: capture,
            permissionService: permissions,
            router: router
        )
        await vm.onAppear()
        await vm.toggleRecording()
        #expect(vm.isRecording == true)

        // Greedy burst: 100 frames at 10 fps = 10 s of audio,
        // synchronously enqueued into the AsyncStream's buffer. This
        // violates the implicit happy-path assumption that the
        // upstream paces frames — the router's drain task and the
        // transcriber's hop scheduler must both behave under
        // simultaneous pressure.
        capture.yieldFrames(makeFrameSequence(totalSeconds: 10.0))

        // Immediately stop without waiting for any windows to land.
        // The system must finish cleanly regardless of which hops
        // dropped, were inflight, or were pending.
        await vm.toggleRecording()
        #expect(vm.isRecording == false)
        #expect(vm.errorMessage == nil)
        #expect(capture.stopCount == 1)

        // routedHistory is allowed to be any non-negative size; the
        // contract is "clean shutdown", not a specific count.
        #expect(router.routedHistory.count >= 0)

        // Bounded wait to confirm no late errorMessage is published
        // by the cancelled drain task.
        let leakedError = await waitUntil(maxAttempts: 4) {
            vm.errorMessage != nil
        }
        #expect(leakedError == false)
    }
}
