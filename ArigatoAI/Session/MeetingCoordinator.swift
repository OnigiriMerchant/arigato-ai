//
//  MeetingCoordinator.swift
//  ArigatoAI
//
//  Created by Jose Castell on 2026/05/16.
//

import Foundation
import os

/// The outer wiring layer that binds ``MeetingSession``, an
/// ``AudioCapturing`` conformer, and ``MeetingPipeline`` into a single
/// observable surface for the UI.
///
/// `MeetingCoordinator` is the type the SwiftUI shell talks to during a
/// meeting's lifecycle. It owns no state of its own — each public
/// method delegates to either the session, the capture protocol, or the
/// pipeline in a documented order. The coordinator's job is to enforce
/// that order; the dependencies enforce their own contracts.
///
/// ## Composite-start ordering (`startMeeting(at:)`)
///
/// 1. `try await capture.start()` — boots the audio engine. Throwing
///    here exits cleanly; no rollback is needed because nothing else
///    has run yet.
/// 2. `let frames = await capture.frameStream()` — grabs the producer
///    side of the audio stream. The call is `async` (per
///    ``AudioCapturing/frameStream()``); this method `await`s it.
/// 3. `try await session.start(at:)` — writes the new `Meeting` row.
///    If this step throws, the engine is already running, so we
///    **roll back** by calling `await capture.stop()` before
///    re-raising. The roll-back contract is enforced by the named
///    test `coordinator_startMeeting_whenSessionStartFails_rollsBackAudioCapture`.
/// 4. `await pipeline.start(frames:)` — wires the frame stream
///    through the router + translator into the session. Returns once
///    the pipeline task is spawned.
///
/// ## Composite-stop ordering (`finalizeStop(at:)`)
///
/// 1. `await pipeline.stop()` — drains in-flight translations and
///    awaits router + translator cancellation. Must complete **before**
///    the audio engine stops so the pipeline does not race the upstream
///    teardown.
/// 2. `await capture.stop()` — stops the audio engine via the protocol.
/// 3. `try await session.finalizeStop(at:)` — writes `endedAt` and
///    rewrites the title from the first English sentence (decision #12).
///
/// The drain-then-engine-stop order is enforced by the named test
/// `coordinator_finalizeStop_awaitsPipelineStopBeforeStoppingCapture`.
///
/// ## Scheduling assumption (Concurrency design discipline)
///
/// All composite methods are **sequential** — the coordinator spawns
/// no `Task`, no `AsyncStream`, no actor, no `CheckedContinuation`. It
/// only `await`s its dependencies. Concurrent invocation of
/// `startMeeting(at:)` is therefore **not supported**: the first call
/// puts the session in `.recording`, and a second concurrent call
/// re-enters `session.start(at:)` from the non-`.idle` phase and
/// throws ``MeetingSessionError/invalidStateTransition(from:attempted:)``.
/// The first call has by then already booted the audio engine, so its
/// rollback path does not fire (the throw came from the second call,
/// not the first). The state machine on `MeetingSession.phase` is the
/// canonical single source of truth here.
///
/// Named violation test:
/// `coordinator_concurrentStartMeeting_secondCallThrowsInvalidStateTransition`.
///
/// ## Pause/resume contract
///
/// `pauseMeeting`/`resumeMeeting` are session-state-only. Audio engine
/// keeps running through pause; the session ignores incoming events
/// while paused. Battery optimization via
/// ``AudioCapturing``'s would-be `pause()`/`resume()` primitives is
/// deferred to V3 (see "AudioCapturing pause/resume primitives" entry).
///
/// ## UI bindings
///
/// - Recording state → `session.phase` (canonical source of truth).
/// - Mic permission → `captureViewModel.permissionStatus`.
/// - Audio level meter → `captureViewModel.level`.
///
/// `captureViewModel.isRecording` is **NOT** a UI binding under
/// Group D's wiring — it remains `private(set)` on the VM and is never
/// flipped by the coordinator (which drives `capture.start()/stop()`
/// directly on the ``AudioCapturing`` protocol, bypassing the VM).
/// The VM's `isRecording` is dormant in this configuration and tracked
/// under the V3 entry "Remove dead router-drain path from
/// AudioCaptureViewModel" for removal alongside the
/// router-optional→required cleanup.
@MainActor
@Observable
final class MeetingCoordinator {
    // MARK: - Dependencies

    /// The session orchestrator. UI binds to ``MeetingSession/phase``
    /// for the canonical recording-state source of truth.
    let session: MeetingSession

    /// The ``AudioCapturing`` conformer the coordinator drives directly
    /// for `start()`, `stop()`, and `frameStream()`. Production wires
    /// this to ``AudioCaptureActor`` via ``AppBootstrapper`` in Step 8.
    let capture: any AudioCapturing

    /// The ``AudioCaptureViewModel`` kept alongside for UI bindings
    /// only — ``AudioCaptureViewModel/permissionStatus`` and
    /// ``AudioCaptureViewModel/level``. Constructed with
    /// `router: nil` so the VM's internal router-drain code path stays
    /// dormant under Group D's wiring (see type-level "UI bindings"
    /// note).
    let captureViewModel: AudioCaptureViewModel

    /// The realtime pipeline coordinator that bridges
    /// ``LanguageRouter`` → ``Translating`` → ``MeetingSession``.
    private let pipeline: MeetingPipeline

    // MARK: - Init

    /// Creates a new coordinator.
    ///
    /// - Parameters:
    ///   - session: The session orchestrator.
    ///   - capture: The audio-capture conformer the coordinator drives
    ///     directly. Typically ``AudioCaptureActor`` in production; a
    ///     fake in tests.
    ///   - captureViewModel: The view model kept for UI bindings only.
    ///     Construct with `router: nil` per the type-level "UI bindings"
    ///     note.
    ///   - pipeline: The pipeline bridge.
    init(
        session: MeetingSession,
        capture: any AudioCapturing,
        captureViewModel: AudioCaptureViewModel,
        pipeline: MeetingPipeline
    ) {
        self.session = session
        self.capture = capture
        self.captureViewModel = captureViewModel
        self.pipeline = pipeline

        // Route the undo-deadline auto-finalize through the coordinator's
        // FULL stop chain. Without this, the session's clock-driven
        // finalize is phase-only: the meeting ends but the pipeline and
        // microphone keep running (the 2026-06-10 on-device zombie — mic
        // held until process death, next START rejected with
        // `alreadyRunning`). `[weak self]` breaks the cycle: the
        // coordinator owns the session.
        session.setAutoFinalizeHandler { [weak self] endedAt in
            await self?.finalizeFromDeadline(at: endedAt)
        }
    }

    /// Clock-driven finalize for the expired undo window — the deadline
    /// counterpart of ``finalizeStop(at:)``, with deliberately INVERTED
    /// order: phase FIRST, teardown second.
    ///
    /// ## Why phase-first (Concurrency design discipline)
    /// `session.finalizeStop(at:)`'s phase re-check is the authority on the
    /// undo-vs-deadline race, with one honestly-stated limit. AFTER its
    /// phase flip succeeds, a late "Tap to restore" throws and cannot
    /// resurrect the meeting, so the teardown below cannot strand a live
    /// recording. If the flip THROWS (an undo won during the
    /// timer-to-handler hop), nothing is torn down — capture keeps running
    /// for the restored meeting. The KNOWN GAP: `finalizeStop` awaits the
    /// store BEFORE flipping the phase, so an undo landing inside that
    /// store-await window succeeds and is then clobbered back to `.ended`
    /// when the finalize resumes — a PRE-EXISTING race shared with the
    /// user-driven finalize path (this fix adds capture teardown to that
    /// already-lost undo, not a new race). Untested; logged as the V3 entry
    /// "undo clobbered by in-flight finalize store-await" with a concrete
    /// trigger, per the concurrency-design-discipline rule.
    /// The UI path (``finalizeStop(at:)``) keeps its pipeline-first order:
    /// its caller owns the phase timing and drains the pipeline before the
    /// transition.
    ///
    /// Violation tests:
    /// `coordinator_undoDeadlineExpiry_runsFullStopChain_releasesCapture`,
    /// `coordinator_undoBeforeDeadline_timerCancelled_captureKeepsRunning`.
    func finalizeFromDeadline(at endedAt: Date) async {
        do {
            try await session.finalizeStop(at: endedAt)
        } catch {
            // Undo won the race — the meeting is recording again; capture
            // and pipeline must stay up. Logged because no UI frame is in
            // this call's stack to surface it.
            Self.log.notice("Deadline finalize lost the undo race; capture stays up: \(String(describing: error), privacy: .public)")
            return
        }
        await pipeline.stop()
        await capture.stop()
        Self.log.notice("Deadline finalize complete: pipeline + capture released")
    }

    /// Coordinator-lifecycle logging at persisted levels (survives into
    /// `log collect` on device). Added 2026-06-10 with the deadline
    /// auto-finalize fix.
    private static let log = Logger(
        subsystem: "com.jose.ArigatoAI",
        category: "Coordinator"
    )

    // MARK: - Composite lifecycle API

    /// Starts a new meeting by running the composite-start sequence
    /// documented at the type level:
    /// 1. `try await capture.start()`
    /// 2. `let frames = await capture.frameStream()` — `frameStream()`
    ///    is `async` per ``AudioCapturing/frameStream()``; this method
    ///    `await`s it.
    /// 3. `try await session.start(at:)` — on throw, the audio engine
    ///    is already running, so the coordinator **rolls back** with
    ///    `await capture.stop()` before re-raising. The rollback
    ///    contract is enforced by
    ///    `coordinator_startMeeting_whenSessionStartFails_rollsBackAudioCapture`.
    /// 4. `await pipeline.start(frames:)`
    ///
    /// - Parameter startedAt: Wall-clock start time, threaded to
    ///   `MeetingSession.start(at:)`.
    /// - Throws: Any error raised by ``AudioCapturing/start()`` (no
    ///   rollback needed — nothing else has run yet) or by
    ///   ``MeetingSession/start(at:)`` (rolled back).
    func startMeeting(at startedAt: Date) async throws {
        // Step 1 — boot the audio engine. Throws exit cleanly here.
        try await capture.start()

        // Step 2 — grab the producer side. Note: frameStream() is async.
        let frames = await capture.frameStream()

        // Step 3 — write the SwiftData row. On throw we must roll back
        // the audio engine that step 1 just booted.
        do {
            try await session.start(at: startedAt)
        } catch {
            await capture.stop()
            throw error
        }

        // Step 4 — wire the bridge.
        await pipeline.start(frames: frames)
    }

    /// Pauses the meeting. Delegates to ``MeetingSession/pause(at:)``
    /// only — the audio engine keeps running through pause (UI
    /// decision #7; battery-optimization deferred to V3).
    ///
    /// - Parameter pausedAt: Wall-clock pause time.
    /// - Throws: ``MeetingSessionError/invalidStateTransition(from:attempted:)``
    ///   if the session is not in ``MeetingSessionPhase/recording``.
    func pauseMeeting(at pausedAt: Date) async throws {
        try await session.pause(at: pausedAt)
    }

    /// Resumes the meeting. Delegates to ``MeetingSession/resume(at:)``
    /// only — audio engine never stopped, so nothing to restart on the
    /// capture side.
    ///
    /// - Parameter resumedAt: Wall-clock resume time.
    /// - Throws: ``MeetingSessionError/invalidStateTransition(from:attempted:)``
    ///   if the session is not in ``MeetingSessionPhase/paused``.
    func resumeMeeting(at resumedAt: Date) async throws {
        try await session.resume(at: resumedAt)
    }

    /// Requests stop and arms the undo-window deadline timer on the
    /// session. Does **not** touch capture — the audio engine keeps
    /// running through the undo window so an undo returns instantly to
    /// recording (UI decision #5).
    ///
    /// - Parameter stopRequestedAt: Wall-clock stop-request time.
    /// - Throws: ``MeetingSessionError/invalidStateTransition(from:attempted:)``
    ///   if the session is not in ``MeetingSessionPhase/recording`` or
    ///   ``MeetingSessionPhase/paused``.
    func requestStop(at stopRequestedAt: Date) async throws {
        try await session.requestStop(at: stopRequestedAt)
    }

    /// Cancels the armed undo window and returns to recording. Capture
    /// was never stopped, so nothing on the capture side resumes.
    ///
    /// - Throws: ``MeetingSessionError/invalidStateTransition(from:attempted:)``
    ///   if the session is not in
    ///   ``MeetingSessionPhase/stoppingWithUndoWindow``.
    func undoStop() async throws {
        try await session.undoStop()
    }

    /// Finalizes the meeting by running the composite-stop sequence
    /// documented at the type level:
    /// 1. `await pipeline.stop()` — drain in-flight translations.
    /// 2. `await capture.stop()` — stop the audio engine.
    /// 3. `try await session.finalizeStop(at:)` — write `endedAt` and
    ///    rewrite the title.
    ///
    /// The drain-then-engine-stop order is enforced by
    /// `coordinator_finalizeStop_awaitsPipelineStopBeforeStoppingCapture`.
    ///
    /// - Parameter endedAt: Wall-clock end time, threaded to
    ///   ``MeetingSession/finalizeStop(at:)``.
    /// - Throws: Re-raises ``MeetingSessionError/storeFailure(underlying:)``
    ///   from the session's persistence call.
    func finalizeStop(at endedAt: Date) async throws {
        await pipeline.stop()
        await capture.stop()
        try await session.finalizeStop(at: endedAt)
    }

    /// Returns the session to ``MeetingSessionPhase/idle`` after an
    /// ended meeting. The pipeline is not restarted here — it stays
    /// stopped until the next ``startMeeting(at:)`` re-wires it.
    ///
    /// - Throws: ``MeetingSessionError/invalidStateTransition(from:attempted:)``
    ///   if the session is not in ``MeetingSessionPhase/ended``.
    func newTranscript() async throws {
        try await session.newTranscript()
    }
}
