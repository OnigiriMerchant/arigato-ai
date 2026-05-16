//
//  MeetingControlsViewTests.swift
//  ArigatoAITests
//
//  Created by Jose Castell on 2026/05/16.
//

@testable import ArigatoAI
import Foundation
import os
import SwiftData
import Testing

/// Tests for ``MeetingControlsView`` — covering the pure-value
/// ``MeetingControlsFormatter`` (badge + button derivation) and the
/// ``MeetingControlsViewModel`` (tap dispatch + last-error capture +
/// in-flight tracking + the special force-commit `tapNewTranscript`
/// branch).
///
/// ViewInspector is not a project dependency (per Step 6's pattern); the
/// view body is exercised indirectly by asserting the formatter outputs
/// the view renders, plus the VM's tap-method behaviour. Build success
/// is the smoke check for the view body itself — the original 17th
/// `transcriptLiveView_meetingControlsViewIsPresent` signature-only
/// test was dropped from the canonical count for that reason.
///
/// All tests `@MainActor` because ``MeetingControlsViewModel`` is
/// `@MainActor`-isolated. The formatter helpers are `nonisolated` and
/// the tests call them inside the main-actor context without any hop.
@Suite("MeetingControlsView")
@MainActor
struct MeetingControlsViewTests {
    // MARK: - Shared helpers

    /// Builds a transient in-memory ``ModelContainer`` so the tests can
    /// obtain a real `PersistentIdentifier` for the
    /// ``MeetingSessionPhase`` payloads. The identifier is opaque to the
    /// formatter (which never reads it) so a single shared container per
    /// test is sufficient.
    private static func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: Meeting.self, Sentence.self,
            configurations: config
        )
    }

    /// Constructs a real ``PersistentIdentifier`` by inserting a
    /// throwaway ``Meeting`` into an in-memory container.
    private static func makeID() throws -> PersistentIdentifier {
        let container = try makeContainer()
        let context = ModelContext(container)
        let meeting = Meeting(
            startedAt: Date(timeIntervalSince1970: 0),
            title: "test"
        )
        context.insert(meeting)
        try context.save()
        return meeting.persistentModelID
    }

    // MARK: - Formatter — badge

    /// **D7-T-1** — Idle phase yields no badge. The formatter contract
    /// states `badgeDisplay(for: .idle, now:)` returns `nil` so the view
    /// elides the badge slot entirely (UI #3 morphing table).
    @Test func formatter_badgeDisplay_idle_returnsNoBadge() {
        let display = MeetingControlsFormatter.badgeDisplay(
            for: .idle,
            now: Date(timeIntervalSince1970: 1_700_000_000)
        )
        #expect(display == nil)
    }

    /// **D7-T-2** — Recording phase renders a pulsing REC badge with
    /// the current elapsed `mm:ss` derived from `now - startedAt`.
    @Test func formatter_badgeDisplay_recording_returnsPulsingRecBadge_withCurrentElapsed() throws {
        let id = try Self.makeID()
        let started = Date(timeIntervalSince1970: 1_700_000_000)
        // 222 seconds = 03:42.
        let now = started.addingTimeInterval(222)

        let display = MeetingControlsFormatter.badgeDisplay(
            for: .recording(meetingID: id, startedAt: started),
            now: now
        )

        #expect(display?.kind == .recordingPulse)
        #expect(display?.text == "REC 03:42")
        #expect(display?.isPulsing == true)
    }

    /// **D7-T-3 (UI #3 freeze contract)** — Paused phase **freezes**
    /// the elapsed value at `pausedAt - startedAt` and ignores the
    /// `now` parameter. This is the freeze contract from UI decision #3.
    /// If a future scheduler change causes the badge to drift past the
    /// frozen time, this test must fail.
    @Test func formatter_badgeDisplay_paused_freezesAtPauseTime_evenIfNowIsLater() throws {
        let id = try Self.makeID()
        let started = Date(timeIntervalSince1970: 1_700_000_000)
        // Paused at 3 minutes 42 seconds elapsed.
        let paused = started.addingTimeInterval(222)
        // `now` is two minutes after pause — but the formatter must
        // ignore it and still report 03:42.
        let nowMuchLater = paused.addingTimeInterval(120)

        let display = MeetingControlsFormatter.badgeDisplay(
            for: .paused(meetingID: id, startedAt: started, pausedAt: paused),
            now: nowMuchLater
        )

        #expect(display?.kind == .paused)
        #expect(display?.text == "PAUSED 03:42")
        #expect(display?.isPulsing == false)
    }

    /// **D7-T-4** — `stoppingWithUndoWindow` badge **continues to
    /// pulse** during the undo window and continues to read `now` for
    /// the elapsed value (the meeting is "still recording" semantically
    /// until the deadline fires or undo lands).
    @Test func formatter_badgeDisplay_stoppingWithUndoWindow_continuesPulsing() throws {
        let id = try Self.makeID()
        let started = Date(timeIntervalSince1970: 1_700_000_000)
        let deadline = started.addingTimeInterval(227)
        // Elapsed at the moment the timer ticks during the undo window.
        let now = started.addingTimeInterval(224)

        let display = MeetingControlsFormatter.badgeDisplay(
            for: .stoppingWithUndoWindow(
                meetingID: id,
                startedAt: started,
                deadline: deadline
            ),
            now: now
        )

        #expect(display?.kind == .recordingPulse)
        #expect(display?.text == "REC 03:44")
        #expect(display?.isPulsing == true)
    }

    /// **D7-T-5** — Ended phase displays the final `endedAt -
    /// startedAt` duration with the stop glyph and **no pulse**. The
    /// `now` parameter must not influence the rendering.
    @Test func formatter_badgeDisplay_ended_displaysFinalDuration_noPulse() throws {
        let id = try Self.makeID()
        let started = Date(timeIntervalSince1970: 1_700_000_000)
        // 50:12 final duration.
        let ended = started.addingTimeInterval(3012)
        // `now` past the ended time — must be ignored.
        let nowPast = ended.addingTimeInterval(500)

        let display = MeetingControlsFormatter.badgeDisplay(
            for: .ended(meetingID: id, startedAt: started, endedAt: ended),
            now: nowPast
        )

        #expect(display?.kind == .ended)
        #expect(display?.text == "50:12")
        #expect(display?.isPulsing == false)
    }

    // MARK: - Formatter — primary button

    /// **D7-T-6** — Each phase yields the expected primary button per
    /// the UI #4 morphing table. Idle → START. Recording → PAUSE.
    /// Paused → RESUME. StoppingWithUndoWindow → NEW TRANSCRIPT
    /// (force-commit branch). Ended → NEW TRANSCRIPT.
    @Test func formatter_primaryButton_eachPhase_returnsExpectedSpec() throws {
        let id = try Self.makeID()
        let started = Date(timeIntervalSince1970: 1_700_000_000)
        let paused = started.addingTimeInterval(100)
        let deadline = started.addingTimeInterval(200)
        let ended = started.addingTimeInterval(300)

        let idleSpec = MeetingControlsFormatter.primaryButton(for: .idle)
        #expect(idleSpec?.label == "START")
        #expect(idleSpec?.kind == .start)

        let recSpec = MeetingControlsFormatter.primaryButton(
            for: .recording(meetingID: id, startedAt: started)
        )
        #expect(recSpec?.label == "PAUSE")
        #expect(recSpec?.kind == .pause)

        let pauseSpec = MeetingControlsFormatter.primaryButton(
            for: .paused(meetingID: id, startedAt: started, pausedAt: paused)
        )
        #expect(pauseSpec?.label == "RESUME")
        #expect(pauseSpec?.kind == .resume)

        let stopSpec = MeetingControlsFormatter.primaryButton(
            for: .stoppingWithUndoWindow(
                meetingID: id,
                startedAt: started,
                deadline: deadline
            )
        )
        #expect(stopSpec?.label == "NEW TRANSCRIPT")
        #expect(stopSpec?.kind == .newTranscript)

        let endedSpec = MeetingControlsFormatter.primaryButton(
            for: .ended(meetingID: id, startedAt: started, endedAt: ended)
        )
        #expect(endedSpec?.label == "NEW TRANSCRIPT")
        #expect(endedSpec?.kind == .newTranscript)
    }

    // MARK: - Formatter — secondary button

    /// **D7-T-7** — Each phase yields the expected secondary button (or
    /// nil) per the UI #4 morphing table. Idle → nil. Recording/Paused
    /// → STOP. StoppingWithUndoWindow → nil (toast handles recovery).
    /// Ended → Share.
    @Test func formatter_secondaryButton_eachPhase_returnsExpectedSpec() throws {
        let id = try Self.makeID()
        let started = Date(timeIntervalSince1970: 1_700_000_000)
        let paused = started.addingTimeInterval(100)
        let deadline = started.addingTimeInterval(200)
        let ended = started.addingTimeInterval(300)

        #expect(MeetingControlsFormatter.secondaryButton(for: .idle) == nil)

        let recSpec = MeetingControlsFormatter.secondaryButton(
            for: .recording(meetingID: id, startedAt: started)
        )
        #expect(recSpec?.label == "STOP")
        #expect(recSpec?.kind == .stop)

        let pauseSpec = MeetingControlsFormatter.secondaryButton(
            for: .paused(meetingID: id, startedAt: started, pausedAt: paused)
        )
        #expect(pauseSpec?.label == "STOP")
        #expect(pauseSpec?.kind == .stop)

        #expect(MeetingControlsFormatter.secondaryButton(
            for: .stoppingWithUndoWindow(
                meetingID: id,
                startedAt: started,
                deadline: deadline
            )
        ) == nil)

        let endedSpec = MeetingControlsFormatter.secondaryButton(
            for: .ended(meetingID: id, startedAt: started, endedAt: ended)
        )
        #expect(endedSpec?.label == "Share")
        #expect(endedSpec?.kind == .share)
    }

    // MARK: - VM — tap dispatch

    /// **D7-T-8** — `tapStart()` invokes the injected `onStart` closure
    /// exactly once and clears any prior `lastError` on success.
    @Test func vm_tapStart_invokesOnStartClosure_andClearsLastErrorOnSuccess() async {
        let recorder = CallRecorder()
        let model = MeetingControlsViewModel(
            phase: { .idle },
            permissionStatus: { .granted },
            level: { 0 },
            now: Date.init,
            onStart: { recorder.record("start") },
            onPause: {},
            onResume: {},
            onRequestStop: {},
            onUndoStop: {},
            onFinalizeStop: {},
            onNewTranscript: {},
            onOpenSettings: {}
        )

        await model.tapStart()

        #expect(recorder.calls == ["start"])
        #expect(model.lastError == nil)
        #expect(model.inFlightAction == nil)
    }

    /// **D7-T-9** — A throw inside `onStart` lands in `lastError`. The
    /// `inFlightAction` returns to `nil` via the `defer` in the tap
    /// method even on the throwing path.
    @Test func vm_tapStart_storesThrownErrorInLastError() async {
        struct Boom: Error, Equatable {}
        let model = MeetingControlsViewModel(
            phase: { .idle },
            permissionStatus: { .granted },
            level: { 0 },
            now: Date.init,
            onStart: { throw Boom() },
            onPause: {},
            onResume: {},
            onRequestStop: {},
            onUndoStop: {},
            onFinalizeStop: {},
            onNewTranscript: {},
            onOpenSettings: {}
        )

        await model.tapStart()

        #expect(model.lastError is Boom)
        #expect(model.inFlightAction == nil)
    }

    /// **D7-T-10** — `tapRequestStop()` invokes `onRequestStop` when
    /// called against a `recording` phase. The VM does not gate on
    /// phase — gating lives in ``MeetingCoordinator`` /
    /// ``MeetingSession`` — but the contract is that the closure is
    /// always invoked.
    @Test func vm_tapRequestStop_inRecordingPhase_invokesOnRequestStopClosure() async throws {
        let id = try Self.makeID()
        let recorder = CallRecorder()
        let phase: MeetingSessionPhase = .recording(
            meetingID: id,
            startedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let model = MeetingControlsViewModel(
            phase: { phase },
            permissionStatus: { .granted },
            level: { 0 },
            now: Date.init,
            onStart: {},
            onPause: {},
            onResume: {},
            onRequestStop: { recorder.record("requestStop") },
            onUndoStop: {},
            onFinalizeStop: {},
            onNewTranscript: {},
            onOpenSettings: {}
        )

        await model.tapRequestStop()

        #expect(recorder.calls == ["requestStop"])
        #expect(model.lastError == nil)
    }

    /// **D7-T-11** — `tapUndo()` invokes `onUndoStop` when called
    /// against a `stoppingWithUndoWindow` phase.
    @Test func vm_tapUndo_inStoppingWithUndoWindowPhase_invokesOnUndoStopClosure() async throws {
        let id = try Self.makeID()
        let recorder = CallRecorder()
        let phase: MeetingSessionPhase = .stoppingWithUndoWindow(
            meetingID: id,
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            deadline: Date(timeIntervalSince1970: 1_700_000_005)
        )
        let model = MeetingControlsViewModel(
            phase: { phase },
            permissionStatus: { .granted },
            level: { 0 },
            now: Date.init,
            onStart: {},
            onPause: {},
            onResume: {},
            onRequestStop: {},
            onUndoStop: { recorder.record("undoStop") },
            onFinalizeStop: {},
            onNewTranscript: {},
            onOpenSettings: {}
        )

        await model.tapUndo()

        #expect(recorder.calls == ["undoStop"])
        #expect(model.lastError == nil)
    }

    /// **D7-T-12** — `tapNewTranscript()` in the ended phase invokes
    /// only `onNewTranscript` (NOT `onFinalizeStop` — that's reserved
    /// for the force-commit branch in
    /// ``MeetingSessionPhase/stoppingWithUndoWindow``).
    @Test func vm_tapNewTranscript_inEndedPhase_invokesOnNewTranscriptClosure() async throws {
        let id = try Self.makeID()
        let recorder = CallRecorder()
        let started = Date(timeIntervalSince1970: 1_700_000_000)
        let phase: MeetingSessionPhase = .ended(
            meetingID: id,
            startedAt: started,
            endedAt: started.addingTimeInterval(60)
        )
        let model = MeetingControlsViewModel(
            phase: { phase },
            permissionStatus: { .granted },
            level: { 0 },
            now: Date.init,
            onStart: {},
            onPause: {},
            onResume: {},
            onRequestStop: {},
            onUndoStop: {},
            onFinalizeStop: { recorder.record("finalizeStop") },
            onNewTranscript: { recorder.record("newTranscript") },
            onOpenSettings: {}
        )

        await model.tapNewTranscript()

        // Only `newTranscript` — not `finalizeStop` — fires in the
        // ended-phase branch.
        #expect(recorder.calls == ["newTranscript"])
        #expect(model.lastError == nil)
    }

    /// **D7-T-13** — `tapNewTranscript()` in the
    /// `stoppingWithUndoWindow` phase is the **force-commit branch**:
    /// it must call `onFinalizeStop` **first**, then `onNewTranscript`.
    /// The order is asserted via the `CallRecorder`'s log.
    @Test func vm_tapNewTranscript_inStoppingWithUndoWindowPhase_callsFinalizeStopThenNewTranscript() async throws {
        let id = try Self.makeID()
        let recorder = CallRecorder()
        let started = Date(timeIntervalSince1970: 1_700_000_000)
        let phase: MeetingSessionPhase = .stoppingWithUndoWindow(
            meetingID: id,
            startedAt: started,
            deadline: started.addingTimeInterval(5)
        )
        let model = MeetingControlsViewModel(
            phase: { phase },
            permissionStatus: { .granted },
            level: { 0 },
            now: Date.init,
            onStart: {},
            onPause: {},
            onResume: {},
            onRequestStop: {},
            onUndoStop: {},
            onFinalizeStop: { recorder.record("finalizeStop") },
            onNewTranscript: { recorder.record("newTranscript") },
            onOpenSettings: {}
        )

        await model.tapNewTranscript()

        // Order is the force-commit contract: finalize fires first.
        #expect(recorder.calls == ["finalizeStop", "newTranscript"])
        #expect(model.lastError == nil)
    }

    // MARK: - VM — disabled factory

    /// **D7-T-14** — ``MeetingControlsViewModel/disabled()`` reports
    /// `.notDetermined` permission, `.idle` phase, and runs every
    /// action closure as a no-op without throwing.
    @Test func vm_disabled_factory_returnsVMWithNoOpClosuresAndIdlePhase() async {
        let model = MeetingControlsViewModel.disabled()

        #expect(model.phase() == .idle)
        #expect(model.permissionStatus() == .notDetermined)
        #expect(model.level() == 0)
        #expect(model.lastError == nil)
        #expect(model.inFlightAction == nil)
        #expect(model.onAppear == nil)

        // Every tap is a no-op — no throw, no lastError, in-flight
        // cleared on exit.
        await model.tapStart()
        await model.tapPause()
        await model.tapResume()
        await model.tapRequestStop()
        await model.tapUndo()
        await model.tapNewTranscript()
        model.onOpenSettings()
        #expect(model.lastError == nil)
        #expect(model.inFlightAction == nil)
    }

    // MARK: - VM — scheduling-assumption violation test

    /// **D7-T-15 (concurrency violation test)** —
    /// Tap methods are assumed mutually exclusive at the SwiftUI
    /// gesture call site. The VM does **not** internally serialize
    /// concurrent invocations. This test bypasses SwiftUI by spawning
    /// `tapStart` and `tapPause` concurrently and asserts:
    ///   1. Both closures execute (no dropped tap).
    ///   2. The last `inFlightAction` write to land is honoured
    ///      (deterministic last-write-wins, not a crash, not a stuck
    ///      state).
    ///
    /// The closure each tap awaits is an `OSAllocatedUnfairLock`-
    /// protected recorder so the two writes do not race on shared
    /// memory; what races is the VM's `inFlightAction` assignment,
    /// which is `@MainActor`-serialised at the language level. Both
    /// closures complete, the VM exits with `inFlightAction == nil`
    /// (the second `defer` cleared it), and the call recorder shows
    /// both calls. This is the documented scheduling assumption and
    /// the named violation test referenced by both ``MeetingControlsView``
    /// and ``MeetingControlsViewModel`` doc-comments.
    @Test func vm_concurrentTapStartAndTapPause_bothClosuresInvoked_lastInFlightActionWins() async {
        let recorder = CallRecorder()
        // Tiny sleeps inside the closures so the two taps overlap in
        // wall-clock terms; without the sleep the @MainActor would
        // serialize them strictly in spawn order with no observable
        // overlap. We want a genuine race shape.
        let model = MeetingControlsViewModel(
            phase: { .idle },
            permissionStatus: { .granted },
            level: { 0 },
            now: Date.init,
            onStart: {
                try? await Task.sleep(nanoseconds: 5_000_000)
                recorder.record("start")
            },
            onPause: {
                try? await Task.sleep(nanoseconds: 5_000_000)
                recorder.record("pause")
            },
            onResume: {},
            onRequestStop: {},
            onUndoStop: {},
            onFinalizeStop: {},
            onNewTranscript: {},
            onOpenSettings: {}
        )

        // Spawn both taps concurrently. `withTaskGroup` provides the
        // structured-concurrency vehicle.
        await withTaskGroup(of: Void.self) { group in
            group.addTask { @MainActor in await model.tapStart() }
            group.addTask { @MainActor in await model.tapPause() }
        }

        // Both closures executed.
        let calls = recorder.calls
        #expect(calls.count == 2)
        #expect(calls.contains("start"))
        #expect(calls.contains("pause"))
        // Both `defer` blocks ran — VM is back to a quiescent state.
        #expect(model.inFlightAction == nil)
    }
}

// MARK: - Test infrastructure

/// Records call-order across closures injected into the VM. Uses
/// `OSAllocatedUnfairLock` per the project's Swift 6 fake-state rules
/// (`NSLock` is forbidden from async contexts).
private final nonisolated class CallRecorder: @unchecked Sendable {
    private let state = OSAllocatedUnfairLock<[String]>(initialState: [])

    /// Append the given identifier to the call log.
    func record(_ name: String) {
        state.withLock { $0.append(name) }
    }

    /// Snapshot of the call log in invocation order.
    var calls: [String] {
        state.withLock { $0 }
    }
}
