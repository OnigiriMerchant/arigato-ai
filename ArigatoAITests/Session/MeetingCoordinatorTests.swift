//
//  MeetingCoordinatorTests.swift
//  ArigatoAITests
//
//  Created by Jose Castell on 2026/05/16.
//

@testable import ArigatoAI
import Foundation
import os
import SwiftData
import Testing

// MARK: - Test infrastructure

/// Records the ordered sequence of method calls into a
/// ``FakeAudioCapturing`` so tests can assert that, e.g.,
/// `capture.start` ran before `capture.frameStream`, or that
/// `capture.stop` did **not** run during pause.
///
/// `OSAllocatedUnfairLock` per CLAUDE.md Swift 6 fake-state rules. Used
/// to keep the recording surface available to both `nonisolated` and
/// `async` callers without an actor hop.
private final nonisolated class CaptureCallLog: @unchecked Sendable {
    enum Call: Equatable {
        case start
        case frameStream
        case levelStream
        case stop
    }

    private struct State {
        var calls: [Call] = []
        /// Monotonic stamp the surrounding fake bumps as it logs each
        /// call. Used by the ordering test to compare against the
        /// pipeline-stop stamp.
        var nextStamp: Int = 0
        var captureStopStamp: Int?
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    func append(_ call: Call) {
        state.withLock { snapshot in
            snapshot.calls.append(call)
            snapshot.nextStamp += 1
            if call == .stop {
                snapshot.captureStopStamp = snapshot.nextStamp
            }
        }
    }

    var calls: [Call] {
        state.withLock { $0.calls }
    }

    var captureStopStamp: Int? {
        state.withLock { $0.captureStopStamp }
    }

    func nextStampValue() -> Int {
        state.withLock { snapshot in
            snapshot.nextStamp += 1
            return snapshot.nextStamp
        }
    }
}

/// Test fake that conforms to ``AudioCapturing`` and records the
/// ordered sequence of `start` / `stop` / `frameStream` / `levelStream`
/// calls. Private to `MeetingCoordinatorTests.swift` per the absolute
/// file-scope rule (CLAUDE.md "swift-implementer scope-and-decision
/// discipline").
///
/// ## Scheduling assumption
///
/// The fake never blocks. `start()` and `stop()` return immediately
/// after logging. `frameStream()` returns an empty stream that finishes
/// on the next iteration so the pipeline's drive loop exits cleanly
/// without driving a long-running router task.
///
/// ## Throw configuration
///
/// `setThrowOnStart(_:)` configures the next `start()` call to throw a
/// supplied error. Used by tests that want to exercise a `capture.start`
/// failure path — none of the 8 tests in this file currently use that,
/// but the surface is kept so future tests in this suite can be added
/// without changing the fake.
private final nonisolated class FakeAudioCapturing: AudioCapturing, @unchecked Sendable {
    private struct ThrowState {
        var throwOnStart: (any Error)?
    }

    let log: CaptureCallLog
    private let throwState = OSAllocatedUnfairLock(initialState: ThrowState())

    init(log: CaptureCallLog) {
        self.log = log
    }

    func setThrowOnStart(_ error: (any Error)?) {
        throwState.withLock { $0.throwOnStart = error }
    }

    func start() async throws {
        log.append(.start)
        let thrown = throwState.withLock { snapshot -> (any Error)? in
            let err = snapshot.throwOnStart
            snapshot.throwOnStart = nil
            return err
        }
        if let thrown {
            throw thrown
        }
    }

    func stop() async {
        log.append(.stop)
    }

    func frameStream() async -> AsyncStream<AudioFrame> {
        log.append(.frameStream)
        // Empty stream that finishes immediately. The pipeline's drive
        // loop will subscribe, observe upstream finish, and exit
        // without dispatching any segment work to the router.
        return AsyncStream { continuation in
            continuation.finish()
        }
    }

    func levelStream() async -> AsyncStream<Float> {
        log.append(.levelStream)
        return AsyncStream { continuation in
            continuation.finish()
        }
    }
}

/// Fake `WhisperClient` that returns the supplied language for every
/// call with empty segments. The router does not need to emit any
/// segments for the coordinator's 8 tests — they all assert on call
/// ordering, not on translation content. Mirrors the minimal-shape
/// fakes in `MeetingPipelineTests.swift`; copied here rather than
/// promoted to a shared fixture (the brief forbids touching
/// `MeetingPipelineTests.swift`, and the canonical fake's recording
/// shape is more than this file needs).
private final nonisolated class SilentLanguageWhisperClient: WhisperClient, @unchecked Sendable {
    func prewarmModels() async throws {}

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

/// Minimal `Translating` fake — the coordinator's tests do not exercise
/// translation output; they assert call ordering on the audio /
/// session / pipeline edges. This fake records nothing and emits
/// nothing; `cancel()` is a no-op.
///
/// ## Why a parallel fake to `RecordingTranslator`
///
/// `MeetingPipelineTests.swift`'s `RecordingTranslator` is a recording
/// + scripting shape. The coordinator tests don't need scripting —
/// they need a `Translating` conformer that compiles and lets
/// `pipeline.start(frames:)` return. The brief forbids touching
/// `MeetingPipelineTests.swift` so promotion is out of scope; this
/// shape is the minimum needed here.
private actor InertTranslator: Translating {
    func warmup() async throws {}
    func warmupState() async -> TranslationWarmupState {
        .ready
    }

    func translate(
        segments _: AsyncStream<TranscriptSegment>,
        direction _: TranslationDirection
    ) async -> AsyncThrowingStream<TranslationEvent, any Error> {
        let (stream, cont) = AsyncThrowingStream<TranslationEvent, any Error>.makeStream()
        cont.finish()
        return stream
    }

    func cancel() async {}
}

/// Stamp recorder used by `coordinator_finalizeStop_awaitsPipelineStopBeforeStoppingCapture`
/// to prove the pipeline.stop ran before capture.stop. The pipeline
/// stop path is observed by hooking the translator's `cancel()` (which
/// `MeetingPipeline.stop()` `await`s as part of its teardown); the
/// capture stop is observed via the existing `CaptureCallLog`
/// monotonic stamp.
///
/// `OSAllocatedUnfairLock` so the actor-isolated translator and the
/// `nonisolated` capture log can both stamp without an awaited hop.
private final nonisolated class StampRecorder: @unchecked Sendable {
    private struct State {
        var nextStamp: Int = 0
        var pipelineStopStamp: Int?
        var captureStopStamp: Int?
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    func bumpPipelineStop() {
        state.withLock { snapshot in
            snapshot.nextStamp += 1
            snapshot.pipelineStopStamp = snapshot.nextStamp
        }
    }

    func bumpCaptureStop() {
        state.withLock { snapshot in
            snapshot.nextStamp += 1
            snapshot.captureStopStamp = snapshot.nextStamp
        }
    }

    var pipelineStopStamp: Int? {
        state.withLock { $0.pipelineStopStamp }
    }

    var captureStopStamp: Int? {
        state.withLock { $0.captureStopStamp }
    }
}

/// `Translating` fake that bumps the supplied ``StampRecorder``'s
/// pipeline-stop stamp on `cancel()`. The pipeline's `stop()` calls
/// `await translator.cancel()` as part of its teardown sequence
/// (see ``MeetingPipeline/stop()``), so observing `cancel()` is a
/// reliable proxy for "pipeline.stop ran here".
private actor StampingTranslator: Translating {
    private let recorder: StampRecorder

    init(recorder: StampRecorder) {
        self.recorder = recorder
    }

    func warmup() async throws {}
    func warmupState() async -> TranslationWarmupState {
        .ready
    }

    func translate(
        segments _: AsyncStream<TranscriptSegment>,
        direction _: TranslationDirection
    ) async -> AsyncThrowingStream<TranslationEvent, any Error> {
        let (stream, cont) = AsyncThrowingStream<TranslationEvent, any Error>.makeStream()
        cont.finish()
        return stream
    }

    func cancel() async {
        recorder.bumpPipelineStop()
    }
}

/// Stamp-bumping audio fake — variant of ``FakeAudioCapturing`` that
/// also bumps the ``StampRecorder``'s capture-stop stamp when
/// `stop()` runs. Used only by the drain-ordering test.
private final nonisolated class StampingAudioCapturing: AudioCapturing, @unchecked Sendable {
    let log: CaptureCallLog
    private let recorder: StampRecorder

    init(log: CaptureCallLog, recorder: StampRecorder) {
        self.log = log
        self.recorder = recorder
    }

    func start() async throws {
        log.append(.start)
    }

    func stop() async {
        log.append(.stop)
        recorder.bumpCaptureStop()
    }

    func frameStream() async -> AsyncStream<AudioFrame> {
        log.append(.frameStream)
        return AsyncStream { continuation in
            continuation.finish()
        }
    }

    func levelStream() async -> AsyncStream<Float> {
        log.append(.levelStream)
        return AsyncStream { continuation in
            continuation.finish()
        }
    }
}

// A `MeetingStore` that swaps its real `appendSentence` for a no-op
// is not needed here — the coordinator tests never drive translation
// events down to persistence. We use an in-memory `MeetingStore`
// directly (Option F3 — mirrors `MeetingPipelineTests.swift`).

// MARK: - Fixture

@MainActor
private struct CoordinatorFixture {
    let container: ModelContainer
    let store: MeetingStore
    let session: MeetingSession
    let captureLog: CaptureCallLog
    let capture: any AudioCapturing
    let captureViewModel: AudioCaptureViewModel
    let router: LanguageRouter
    let translator: any Translating
    let pipeline: MeetingPipeline
    let coordinator: MeetingCoordinator
}

@MainActor
private func makeFixture(
    audio: (any AudioCapturing)? = nil,
    captureLog: CaptureCallLog? = nil,
    translator: (any Translating)? = nil
) throws -> CoordinatorFixture {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(
        for: Meeting.self, Sentence.self,
        configurations: config
    )
    let store = MeetingStore(modelContainer: container)
    let session = MeetingSession(store: store)

    let log = captureLog ?? CaptureCallLog()
    let captureConformer: any AudioCapturing = audio ?? FakeAudioCapturing(log: log)

    // The view model is kept in scope for `permissionStatus` + `level`
    // bindings only (per the type-level "UI bindings" note on
    // MeetingCoordinator). It receives the same `AudioCapturing`
    // conformer so its `permissionStatus` / `level` paths have
    // something to talk to in tests, but the coordinator drives the
    // protocol handle directly — it never goes through the VM for
    // start/stop/frameStream.
    let captureViewModel = AudioCaptureViewModel(
        capture: captureConformer,
        router: nil
    )

    let whisperClient = SilentLanguageWhisperClient()
    let transcriber = TranscriptionActor(clientFactory: { whisperClient })
    let router = LanguageRouter(
        transcriber: transcriber,
        confirmationsRequired: LanguageRouter.defaultConfirmationsRequired
    )
    let pipelineTranslator: any Translating = translator ?? InertTranslator()
    let pipeline = MeetingPipeline(
        router: router,
        translator: pipelineTranslator,
        session: session
    )
    let coordinator = MeetingCoordinator(
        session: session,
        capture: captureConformer,
        captureViewModel: captureViewModel,
        pipeline: pipeline
    )
    return CoordinatorFixture(
        container: container,
        store: store,
        session: session,
        captureLog: log,
        capture: captureConformer,
        captureViewModel: captureViewModel,
        router: router,
        translator: pipelineTranslator,
        pipeline: pipeline,
        coordinator: coordinator
    )
}

// `MeetingStore` decorator that throws on `startMeeting`. Used by the
// rollback test to force `session.start(at:)` into its error path
// without subclassing `MeetingSession` (the brief forbids modifying
// `MeetingSession.swift`).
//
// Implementation strategy: instead of trying to replace the store
// behind the session, the rollback test uses `MeetingSession.start`'s
// own re-throw of `MeetingSessionError.invalidStateTransition` by
// putting the session in `.recording` first via an explicit
// `session.start(at:)` call, then driving `coordinator.startMeeting`
// — which re-enters `session.start` from the non-`.idle` phase and
// throws. This keeps every dependency real and respects the absolute
// file scope.
//
// See the rollback test for the full sequence.

// MARK: - Tests

@Suite("MeetingCoordinator")
@MainActor
struct MeetingCoordinatorTests {
    // MARK: - Happy path + delegation (4)

    /// `startMeeting(at:)` drives the four composite-start substeps in
    /// the order documented on ``MeetingCoordinator/startMeeting(at:)``:
    /// `capture.start` → `capture.frameStream` → `session.start` →
    /// `pipeline.start`. The audio and session edges are observed
    /// directly; pipeline.start is observed indirectly via the session
    /// transitioning out of `.idle` (which only happens after step 3,
    /// and step 4 cannot run before step 3).
    @Test func coordinator_startMeeting_happyPath_drivesAllFourSubstepsInOrder() async throws {
        let log = CaptureCallLog()
        let fixture = try makeFixture(captureLog: log)

        #expect(fixture.session.phase == .idle, "Precondition: session starts idle")

        try await fixture.coordinator.startMeeting(at: Date())

        // Substep 1 + 2: capture.start → capture.frameStream — strictly
        // ordered on the log.
        let calls = log.calls
        let startIndex = calls.firstIndex(of: .start)
        let frameStreamIndex = calls.firstIndex(of: .frameStream)
        #expect(startIndex != nil, "Substep 1: capture.start must have fired")
        #expect(frameStreamIndex != nil, "Substep 2: capture.frameStream must have fired")
        if let startIndex, let frameStreamIndex {
            #expect(startIndex < frameStreamIndex,
                    "Substep 1 (start) must precede substep 2 (frameStream)")
        }

        // Substep 3: session.start ran — phase transitioned out of .idle.
        if case .recording = fixture.session.phase {
            // good
        } else {
            Issue.record("Substep 3: session.phase should be .recording, was \(fixture.session.phase)")
        }

        // Substep 4: pipeline.start ran. Observed by inspecting that
        // capture.stop was NOT called (rollback didn't fire) — the
        // composite-start happy path leaves capture running, so
        // .stop must be absent.
        #expect(!calls.contains(.stop),
                "Substep 4 (pipeline.start) reached without rollback: capture.stop must NOT have fired")
    }

    /// Pause and resume delegate to the session only — audio engine
    /// keeps running through pause (per the type-level "Pause/resume
    /// contract" note, locked by pre-flight Disposition #3). Renamed
    /// from the original `..._audioEngineQuiescesAndRestarts` because
    /// the locked decision is "engine keeps running".
    @Test func coordinator_pauseAndResume_delegatesToSession_audioEngineKeepsRunning() async throws {
        let log = CaptureCallLog()
        let fixture = try makeFixture(captureLog: log)

        let started = Date()
        try await fixture.coordinator.startMeeting(at: started)

        let startupStopCount = log.calls.filter { $0 == .stop }.count
        let startupStartCount = log.calls.filter { $0 == .start }.count
        #expect(startupStopCount == 0, "Precondition: no capture.stop during startup")
        #expect(startupStartCount == 1, "Precondition: capture.start fired exactly once")

        // Pause — should not call capture.stop.
        try await fixture.coordinator.pauseMeeting(at: started.addingTimeInterval(1))
        if case .paused = fixture.session.phase {
            // good
        } else {
            Issue.record("After pause, session.phase should be .paused, was \(fixture.session.phase)")
        }
        let postPauseStopCount = log.calls.filter { $0 == .stop }.count
        #expect(postPauseStopCount == 0,
                "Disposition #3: capture.stop must NOT fire during pauseMeeting")

        // Resume — should not call capture.start again.
        try await fixture.coordinator.resumeMeeting(at: started.addingTimeInterval(2))
        if case .recording = fixture.session.phase {
            // good
        } else {
            Issue.record("After resume, session.phase should be .recording, was \(fixture.session.phase)")
        }
        let postResumeStartCount = log.calls.filter { $0 == .start }.count
        #expect(postResumeStartCount == 1,
                "Disposition #3: capture.start must NOT fire again on resumeMeeting (engine already running)")
    }

    /// `requestStop(at:)` arms the undo window on the session but does
    /// NOT stop the audio engine — UI decision #5 keeps the engine
    /// running through the undo window so an undo returns instantly to
    /// recording.
    @Test func coordinator_requestStop_doesNotStopAudioCapture() async throws {
        let log = CaptureCallLog()
        let fixture = try makeFixture(captureLog: log)

        let started = Date()
        try await fixture.coordinator.startMeeting(at: started)

        let preCount = log.calls.filter { $0 == .stop }.count
        try await fixture.coordinator.requestStop(at: started.addingTimeInterval(1))

        if case .stoppingWithUndoWindow = fixture.session.phase {
            // good
        } else {
            Issue.record("After requestStop, session.phase should be .stoppingWithUndoWindow, was \(fixture.session.phase)")
        }
        let postCount = log.calls.filter { $0 == .stop }.count
        #expect(postCount == preCount,
                "UI decision #5: capture.stop must NOT fire on requestStop")
    }

    /// `undoStop()` returns the session to `.recording` and leaves
    /// the audio engine running (it was never stopped by requestStop).
    @Test func coordinator_undoStop_returnsToRecording_audioCaptureStillRunning() async throws {
        let log = CaptureCallLog()
        let fixture = try makeFixture(captureLog: log)

        let started = Date()
        try await fixture.coordinator.startMeeting(at: started)
        try await fixture.coordinator.requestStop(at: started.addingTimeInterval(1))
        try await fixture.coordinator.undoStop()

        if case .recording = fixture.session.phase {
            // good
        } else {
            Issue.record("After undoStop, session.phase should be .recording, was \(fixture.session.phase)")
        }
        let stopCount = log.calls.filter { $0 == .stop }.count
        #expect(stopCount == 0,
                "Audio engine must still be running: capture.stop never fired during request/undo")
    }

    // MARK: - Violation tests (3)

    /// **Rollback contract test.** If `session.start(at:)` throws after
    /// `capture.start()` has succeeded, the coordinator must roll back
    /// the audio engine by calling `capture.stop()` before re-raising.
    /// Documented on ``MeetingCoordinator/startMeeting(at:)``.
    ///
    /// Setup: put the session in `.recording` first via an explicit
    /// `session.start(at:)`. The coordinator's subsequent
    /// `startMeeting(at:)` re-enters `session.start` from a non-`.idle`
    /// phase, which throws ``MeetingSessionError/invalidStateTransition(from:attempted:)``.
    /// The coordinator's audio engine has already booted at that point,
    /// so its rollback path must fire: assert `capture.stop` was logged
    /// before the throw propagates out.
    @Test func coordinator_startMeeting_whenSessionStartFails_rollsBackAudioCapture() async throws {
        let log = CaptureCallLog()
        let fixture = try makeFixture(captureLog: log)

        // Force session.start to throw on the coordinator's call by
        // pre-transitioning the session into .recording. The session
        // will then refuse the next start() with .invalidStateTransition.
        try await fixture.session.start(at: Date())
        if case .recording = fixture.session.phase {
            // good — precondition for the rollback test
        } else {
            Issue.record("Precondition failed: session should be .recording")
            return
        }

        let preStopCount = log.calls.filter { $0 == .stop }.count

        var didThrow = false
        do {
            try await fixture.coordinator.startMeeting(at: Date().addingTimeInterval(1))
        } catch let sessionError as MeetingSessionError {
            didThrow = true
            switch sessionError {
            case let .invalidStateTransition(_, attempted):
                #expect(attempted == "start",
                        "Rollback should be triggered by the session's start-transition refusal")
            default:
                Issue.record("Unexpected MeetingSessionError: \(sessionError)")
            }
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
        #expect(didThrow, "coordinator.startMeeting must re-raise after rollback")

        let postStopCount = log.calls.filter { $0 == .stop }.count
        #expect(postStopCount == preStopCount + 1,
                "Rollback contract: capture.stop must have fired exactly once after the session.start throw")

        // Final shape: the call log shows capture.start → frameStream
        // → capture.stop (rollback) ordering for the coordinator's
        // invocation.
        let coordinatorCalls = log.calls
        // We expect, in order: .start, .frameStream, .stop (the
        // pre-fixture session.start() did not touch the audio fake).
        let lastThree = Array(coordinatorCalls.suffix(3))
        #expect(lastThree == [.start, .frameStream, .stop],
                "Expected last-three call sequence to be start → frameStream → stop (rollback), was \(lastThree)")
    }

    /// **Concurrency scheduling-assumption violation test** (per
    /// CLAUDE.md "Concurrency design discipline"). The coordinator
    /// supports sequential invocation only; a second concurrent
    /// `startMeeting(at:)` re-enters `session.start` from
    /// `.recording`, which throws
    /// ``MeetingSessionError/invalidStateTransition(from:attempted:)``.
    /// Named in the type-level scheduling-assumption doc-comment.
    @Test func coordinator_concurrentStartMeeting_secondCallThrowsInvalidStateTransition() async throws {
        let log = CaptureCallLog()
        let fixture = try makeFixture(captureLog: log)

        try await fixture.coordinator.startMeeting(at: Date())
        if case .recording = fixture.session.phase {
            // good
        } else {
            Issue.record("Precondition failed: session should be .recording after first call")
            return
        }

        // Second invocation — must throw .invalidStateTransition.
        var didThrow = false
        do {
            try await fixture.coordinator.startMeeting(at: Date().addingTimeInterval(1))
        } catch let err as MeetingSessionError {
            didThrow = true
            switch err {
            case let .invalidStateTransition(from, attempted):
                #expect(from == "recording",
                        "Second startMeeting should observe .recording phase, was \(from)")
                #expect(attempted == "start",
                        "Should throw against the start transition")
            default:
                Issue.record("Unexpected MeetingSessionError: \(err)")
            }
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
        #expect(didThrow,
                "Sequential-only assumption: second concurrent startMeeting must throw")
    }

    /// **Drain-ordering contract test.** `finalizeStop(at:)` must
    /// `await pipeline.stop()` before calling `capture.stop()` so the
    /// pipeline drains in-flight translations against a still-live
    /// audio engine. Documented on
    /// ``MeetingCoordinator/finalizeStop(at:)``.
    ///
    /// `StampRecorder` records a pipeline-stop stamp when the
    /// `StampingTranslator.cancel()` runs (driven by
    /// `MeetingPipeline.stop()`'s teardown) and a capture-stop stamp
    /// when the `StampingAudioCapturing.stop()` runs. Assert
    /// pipelineStopStamp < captureStopStamp.
    @Test func coordinator_finalizeStop_awaitsPipelineStopBeforeStoppingCapture() async throws {
        let recorder = StampRecorder()
        let log = CaptureCallLog()
        let audio = StampingAudioCapturing(log: log, recorder: recorder)
        let translator = StampingTranslator(recorder: recorder)
        let fixture = try makeFixture(
            audio: audio,
            captureLog: log,
            translator: translator
        )

        let started = Date()
        try await fixture.coordinator.startMeeting(at: started)
        try await fixture.coordinator.requestStop(at: started.addingTimeInterval(1))

        try await fixture.coordinator.finalizeStop(at: started.addingTimeInterval(2))

        // Phase final-state sanity.
        if case .ended = fixture.session.phase {
            // good
        } else {
            Issue.record("After finalizeStop, session.phase should be .ended, was \(fixture.session.phase)")
        }

        // The contract under test.
        let pipelineStamp = recorder.pipelineStopStamp
        let captureStamp = recorder.captureStopStamp
        #expect(pipelineStamp != nil,
                "pipeline.stop must have run (translator.cancel observed)")
        #expect(captureStamp != nil, "capture.stop must have run")
        if let pipelineStamp, let captureStamp {
            #expect(pipelineStamp < captureStamp,
                    "Drain-ordering contract: pipeline.stop must precede capture.stop, was pipeline=\(pipelineStamp), capture=\(captureStamp)")
        }
    }

    // MARK: - Lifecycle (1)

    /// `newTranscript()` resets the session back to `.idle` after a
    /// finalized meeting, and the pipeline is **not** restarted —
    /// it stays stopped until the next `startMeeting(at:)`.
    /// Observed by inspecting that no further `capture.start` or
    /// `capture.frameStream` calls fire on the audio log after
    /// newTranscript runs.
    @Test func coordinator_newTranscript_resetsToIdle_pipelineNotRestarted() async throws {
        let log = CaptureCallLog()
        let fixture = try makeFixture(captureLog: log)

        let started = Date()
        try await fixture.coordinator.startMeeting(at: started)
        try await fixture.coordinator.requestStop(at: started.addingTimeInterval(1))
        try await fixture.coordinator.finalizeStop(at: started.addingTimeInterval(2))

        let callsBeforeNewTranscript = log.calls

        try await fixture.coordinator.newTranscript()
        #expect(fixture.session.phase == .idle,
                "After newTranscript, session.phase should be .idle, was \(fixture.session.phase)")

        let callsAfterNewTranscript = log.calls
        #expect(callsAfterNewTranscript == callsBeforeNewTranscript,
                "newTranscript must NOT re-fire any AudioCapturing calls; pipeline stays stopped until next startMeeting")
    }
}
