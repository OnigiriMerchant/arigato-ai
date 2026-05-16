//
//  MeetingSession.swift
//  ArigatoAI
//
//  Created by Jose Castell on 2026/05/16.
//

import Foundation
import SwiftData

/// The active-meeting orchestrator.
///
/// `MeetingSession` owns the lifecycle of one in-progress (or recently
/// ended) meeting. SwiftUI binds to this type via `@Observable` and
/// drives button morphing (Group D UI decision #4), status badge
/// (decision #3), undo toast (decision #8), and split-screen scroll
/// behaviour (decision #2) off the published ``phase`` and ``liveChunks``
/// properties.
///
/// ## Persistence pattern (D3-A option 2)
/// Per UI decision #6, transcripts auto-save continuously. The
/// `consumeTranslationEvents(_:)` pump persists each translated
/// sentence on ``TranslationEvent/completed(_:)`` only — never on
/// ``TranslationEvent/partialChunk(sourceSegmentID:delta:)``. In-flight
/// partial chunks accumulate in the in-memory ``liveChunks`` dictionary
/// so SwiftUI can render token-by-token streaming output without
/// touching SwiftData on every token. Once the matching `.completed`
/// event fires, the persistence path runs and the corresponding
/// `liveChunks` entry is cleared.
///
/// ## Return-type contract (D3-B option 1)
/// All mutating APIs return `Void`. UI reads the ``phase`` property to
/// observe the resulting state; this keeps the contract symmetric with
/// the @Observable property model and avoids forcing callers to thread
/// return values through the view layer.
///
/// ## Amendment 3 compatibility
/// All `MeetingStore` calls are `await`ed and the orchestrator makes
/// no assumption that the store is `@MainActor`-isolated. Step 8 will
/// initialise the store via `Task.detached { ... }` per
/// FB13399899; this orchestrator's API remains unchanged across that
/// transition.
///
/// ## Title generation (decision #12, MVP 1)
/// At ``start(at:)``, the meeting's title is set to a bare-timestamp
/// placeholder via ``MeetingTitleGenerator``. The first English
/// sentence observed in the event stream is captured into
/// ``firstEnglishSentence`` and used at ``finalizeStop(at:)`` to
/// rewrite the title via `MeetingStore.updateTitle`. Subsequent
/// English sentences do not overwrite the captured value.
@MainActor
@Observable
final class MeetingSession {
    // MARK: - Public observed state

    /// The current lifecycle phase. SwiftUI reads this to drive the
    /// button morphing pattern (decision #4) and the recording-indicator
    /// badge (decision #3).
    private(set) var phase: MeetingSessionPhase = .idle

    /// Token-by-token streaming output for any in-flight translation,
    /// keyed by upstream `sourceSegmentID`. Updated on every
    /// ``TranslationEvent/partialChunk(sourceSegmentID:delta:)`` event
    /// by appending the incremental delta to the existing value. Cleared
    /// on the matching ``TranslationEvent/completed(_:)`` event.
    ///
    /// Per inspection of `TranslationActor.swift:619-627`, `delta` is an
    /// incremental token chunk — not a cumulative snapshot — so the
    /// pump appends rather than replaces.
    private(set) var liveChunks: [UUID: String] = [:]

    /// Optional callback invoked synchronously on the main actor after
    /// every successful ``appendSentence(...)`` call inside
    /// ``consumeTranslationEvents(_:)``'s `.completed` branch.
    ///
    /// ## Scheduling assumption (Concurrency design discipline)
    ///
    /// **Synchronous main-actor invocation. The receiver must not block.**
    /// The callback fires inline from the translate-consumer task's
    /// processing loop (a main-actor re-entrant context). Heavy work in
    /// the receiver should dispatch its own `Task` to avoid stalling the
    /// next iteration of the event pump. Setting this property to `nil`
    /// cleanly unsubscribes; the next `.completed` event will not invoke
    /// any callback.
    ///
    /// ## Violation of the assumption
    ///
    /// A blocking receiver (e.g., a `Thread.sleep` inside the callback or
    /// a synchronous busy loop) would stall `consumeTranslationEvents`'s
    /// next `for try await event in stream` iteration on the main actor.
    /// Subsequent events would queue up in the stream's internal buffer
    /// until the receiver returns. Production receivers should
    /// `requestReload`-style trampoline to another Task — see
    /// ``TranscriptSplitScreenViewModel/requestReload()`` for the
    /// canonical pattern.
    ///
    /// ## Failure semantics
    ///
    /// The callback is **NOT** invoked when `appendSentence` throws
    /// (transient store failure, stale `meetingID`, etc.). The contract
    /// is "fired after every successful persist", not "fired after every
    /// attempted persist."
    ///
    /// ## Named violation test
    ///
    /// `meetingSession_sentencesDidUpdateBlocks_doesNotStallEventPump`
    /// in `MeetingSessionTests` registers a callback that sleeps ~50ms
    /// per invocation and feeds the session a small burst; the test
    /// asserts every burst sentence still lands in the store, proving
    /// the consumer task is not deadlocked by the slow callback.
    ///
    /// ## Step 9a wiring
    ///
    /// ``ContentView`` constructs ``TranscriptSplitScreenViewModel`` and
    /// installs `coordinator.session.sentencesDidUpdate = { [weak vm] in
    /// vm?.requestReload() }`. The VM trampolines the reload into a
    /// `.task(id:)` modifier in the view body for last-query-wins
    /// semantics.
    @MainActor var sentencesDidUpdate: (@MainActor () -> Void)?

    // MARK: - Dependencies

    private let store: MeetingStore
    private let clock: any Clock<Duration>
    private let undoWindow: Duration

    // MARK: - Internal task state

    /// The translate-consumer task. Cancelled and replaced on a second
    /// call to ``consumeTranslationEvents(_:)``.
    private var translateTask: Task<Void, Never>?

    /// The undo-window deadline timer task. Cancelled by
    /// ``undoStop()`` or by a subsequent ``requestStop(at:)``.
    private var undoTask: Task<Void, Never>?

    /// The first English sentence observed via a
    /// ``TranslationEvent/completed(_:)`` event for the current meeting.
    /// Set once per meeting; reset to `nil` in ``newTranscript()``.
    private var firstEnglishSentence: String?

    // MARK: - Init

    /// Creates a new session orchestrator.
    ///
    /// - Parameters:
    ///   - store: The persistence actor that owns the SwiftData writes.
    ///   - clock: Clock used for the undo-window deadline. Defaults to
    ///     `ContinuousClock()`; tests inject a fake.
    ///   - undoWindow: How long the undo toast is offered after STOP.
    ///     Defaults to 5 seconds per decision #8.
    init(
        store: MeetingStore,
        clock: any Clock<Duration> = ContinuousClock(),
        undoWindow: Duration = .seconds(5)
    ) {
        self.store = store
        self.clock = clock
        self.undoWindow = undoWindow
    }

    // MARK: - Lifecycle API

    /// Starts a new meeting and transitions to
    /// ``MeetingSessionPhase/recording(meetingID:startedAt:)``.
    ///
    /// Persists a new `Meeting` row via `MeetingStore.startMeeting` and
    /// stores a placeholder timestamp-only title (the title is rewritten
    /// at ``finalizeStop(at:)`` once the first English sentence is
    /// known — see type-level "Title generation" section).
    ///
    /// - Parameter startedAt: Wall-clock start time. The same value is
    ///   used as both the SwiftData row's `startedAt` and the title's
    ///   timestamp portion.
    /// - Throws: ``MeetingSessionError/invalidStateTransition(from:attempted:)``
    ///   if called from any phase other than ``MeetingSessionPhase/idle``.
    ///   Re-throws as ``MeetingSessionError/storeFailure(underlying:)`` any
    ///   error raised by the underlying store.
    func start(at startedAt: Date) async throws {
        guard case .idle = phase else {
            throw MeetingSessionError.invalidStateTransition(
                from: phase.label,
                attempted: "start"
            )
        }
        let placeholderTitle = MeetingTitleGenerator.makeTitle(
            startedAt: startedAt,
            firstEnglishSentence: nil
        )
        let meetingID: PersistentIdentifier
        do {
            meetingID = try await store.startMeeting(
                startedAt: startedAt,
                title: placeholderTitle
            )
        } catch {
            throw MeetingSessionError.storeFailure(underlying: error.localizedDescription)
        }
        phase = .recording(meetingID: meetingID, startedAt: startedAt)
    }

    /// Pauses an active meeting (decision #7 — UI-only state, no
    /// persistence side-effect).
    ///
    /// - Parameter pausedAt: Wall-clock time of the pause action.
    /// - Throws: ``MeetingSessionError/invalidStateTransition(from:attempted:)``
    ///   if called from any phase other than
    ///   ``MeetingSessionPhase/recording(meetingID:startedAt:)``.
    func pause(at pausedAt: Date) async throws {
        guard case let .recording(meetingID, startedAt) = phase else {
            throw MeetingSessionError.invalidStateTransition(
                from: phase.label,
                attempted: "pause"
            )
        }
        phase = .paused(meetingID: meetingID, startedAt: startedAt, pausedAt: pausedAt)
    }

    /// Resumes a paused meeting. UI-only; no persistence side-effect.
    ///
    /// - Parameter resumedAt: Wall-clock time of the resume action.
    ///   The current implementation does not persist resume events;
    ///   the parameter is retained for symmetry with the other lifecycle
    ///   methods and for future extension.
    /// - Throws: ``MeetingSessionError/invalidStateTransition(from:attempted:)``
    ///   if called from any phase other than
    ///   ``MeetingSessionPhase/paused(meetingID:startedAt:pausedAt:)``.
    func resume(at resumedAt: Date) async throws {
        _ = resumedAt
        guard case let .paused(meetingID, startedAt, _) = phase else {
            throw MeetingSessionError.invalidStateTransition(
                from: phase.label,
                attempted: "resume"
            )
        }
        phase = .recording(meetingID: meetingID, startedAt: startedAt)
    }

    /// Requests stop and arms the undo-window deadline timer.
    ///
    /// ## Scheduling assumption
    /// This method may be called repeatedly: a user who taps STOP →
    /// Undo → STOP again must end up with a **fresh** undo window
    /// counting from the **second** STOP, not from the first. The
    /// implementation cancels any in-flight `undoTask` before spawning
    /// a replacement, so at most one timer is armed at any moment.
    ///
    /// ## Violation of the assumption
    /// If two timers were allowed to coexist, an early deadline from
    /// the first call could fire after the user thought they had armed
    /// a fresh window with the second call, causing a surprise
    /// transition to ``MeetingSessionPhase/ended``. The cancel-and-replace
    /// idiom prevents that.
    ///
    /// ## Named violation test
    /// `requestStop_thenImmediateUndoStop_thenImmediateRequestStop_correctlyArmsFreshDeadline`
    /// in `MeetingSessionTests` drives this exact sequence and asserts
    /// the second window fires from the second `requestStop`.
    ///
    /// - Parameter stopRequestedAt: Wall-clock time of the STOP action.
    ///   The undo deadline is `stopRequestedAt + undoWindow`.
    /// - Throws: ``MeetingSessionError/invalidStateTransition(from:attempted:)``
    ///   if called from any phase other than ``MeetingSessionPhase/recording``
    ///   or ``MeetingSessionPhase/paused``.
    func requestStop(at stopRequestedAt: Date) async throws {
        let meetingID: PersistentIdentifier
        let startedAt: Date
        switch phase {
        case let .recording(id, started):
            meetingID = id
            startedAt = started
        case let .paused(id, started, _):
            meetingID = id
            startedAt = started
        default:
            throw MeetingSessionError.invalidStateTransition(
                from: phase.label,
                attempted: "requestStop"
            )
        }
        let deadline = stopRequestedAt.addingTimeInterval(undoWindow.seconds)
        phase = .stoppingWithUndoWindow(
            meetingID: meetingID,
            startedAt: startedAt,
            deadline: deadline
        )
        // Cancel-and-replace: at most one undoTask in flight.
        undoTask?.cancel()
        let captureClock = clock
        let sleepDuration = undoWindow
        undoTask = Task { [weak self] in
            do {
                // `sleep(for:)` is a defaulted protocol extension on
                // `Clock` that delegates to `sleep(until:tolerance:)`
                // internally. We use the `for:` form here so it
                // dispatches cleanly through the `any Clock<Duration>`
                // existential without forcing a generic constraint at
                // the call site.
                try await captureClock.sleep(for: sleepDuration)
            } catch is CancellationError {
                // undoStop() or a subsequent requestStop cancelled us.
                return
            } catch {
                // Clock sleep errors are not part of any documented
                // contract; treat as cancellation for safety — do not
                // silently transition to .ended.
                return
            }
            await self?.fireDeadline(at: deadline)
        }
    }

    /// Cancels an armed undo window and returns to
    /// ``MeetingSessionPhase/recording``.
    ///
    /// ## Scheduling assumption
    /// Undo cancels the undo-window timer via cooperative cancellation
    /// (`Task.cancel()` interrupts `clock.sleep(until:)` with a
    /// `CancellationError`). The undoTask catches the cancel and
    /// returns without firing the deadline.
    ///
    /// ## Race semantics
    /// If `undoStop()` is dispatched **before** the clock crosses the
    /// deadline, undo wins: the phase returns to recording and no
    /// `endMeeting` call is made. If the deadline fires first, the
    /// phase becomes ``MeetingSessionPhase/ended`` and a subsequent
    /// `undoStop()` throws
    /// ``MeetingSessionError/invalidStateTransition(from:attempted:)``.
    /// The race is resolved at the phase-check site — see
    /// `MeetingSessionTests.undoStop_racesWithDeadlineExpiry_undoWinsIfDispatchedBeforeFire`.
    ///
    /// - Throws: ``MeetingSessionError/invalidStateTransition(from:attempted:)``
    ///   if called from any phase other than
    ///   ``MeetingSessionPhase/stoppingWithUndoWindow``.
    func undoStop() async throws {
        guard case let .stoppingWithUndoWindow(meetingID, startedAt, _) = phase else {
            throw MeetingSessionError.invalidStateTransition(
                from: phase.label,
                attempted: "undoStop"
            )
        }
        undoTask?.cancel()
        undoTask = nil
        phase = .recording(meetingID: meetingID, startedAt: startedAt)
    }

    /// Finalizes the meeting: writes `endedAt` to the SwiftData row,
    /// rewrites the title using the first English sentence if one was
    /// captured, and transitions to ``MeetingSessionPhase/ended``.
    ///
    /// ## Idempotency / race safety
    /// `finalizeStop(at:)` re-checks ``phase`` on entry. If we have
    /// **already** transitioned out of ``MeetingSessionPhase/stoppingWithUndoWindow``
    /// (because `undoStop()` ran or a previous deadline call already
    /// finalized), this method is a no-op rather than a throw — the
    /// deadline timer firing after an undo is an expected race, not an
    /// error condition.
    ///
    /// ## Scheduling assumption
    /// The undo-window timer task calls this method on its way out. The
    /// timer task does not hold any internal lock other than the
    /// `@MainActor` re-entrancy of this `MeetingSession`, so the
    /// re-check-then-act sequence here is safe under main-actor
    /// serialisation.
    ///
    /// ## Named violation test
    /// `undoStop_racesWithDeadlineExpiry_undoWinsIfDispatchedBeforeFire`
    /// drives the race; `deadlineExpiry_fromStoppingWithUndoWindow_transitionsToEnded_andCallsStoreEndMeeting`
    /// drives the happy path.
    ///
    /// - Parameter endedAt: Wall-clock end time. Persisted as
    ///   `Meeting.endedAt`.
    /// - Throws: ``MeetingSessionError/storeFailure(underlying:)`` if the
    ///   underlying store call fails. Does **not** throw when called
    ///   from a non-`stoppingWithUndoWindow` phase — the call is a no-op.
    func finalizeStop(at endedAt: Date) async throws {
        guard case let .stoppingWithUndoWindow(meetingID, startedAt, _) = phase else {
            // Race: undoStop() or a prior finalize beat us here.
            return
        }
        undoTask?.cancel()
        undoTask = nil
        do {
            let finalTitle = MeetingTitleGenerator.makeTitle(
                startedAt: startedAt,
                firstEnglishSentence: firstEnglishSentence
            )
            try await store.updateTitle(meetingID: meetingID, title: finalTitle)
            try await store.endMeeting(meetingID: meetingID, endedAt: endedAt)
        } catch {
            throw MeetingSessionError.storeFailure(underlying: error.localizedDescription)
        }
        phase = .ended(meetingID: meetingID, startedAt: startedAt, endedAt: endedAt)
    }

    /// Returns to ``MeetingSessionPhase/idle`` after an ended meeting,
    /// clearing all in-memory streaming state.
    ///
    /// Driven by the NEW TRANSCRIPT button (decision #5). Does NOT
    /// delete the meeting row — it remains in history.
    ///
    /// - Throws: ``MeetingSessionError/invalidStateTransition(from:attempted:)``
    ///   if called from any phase other than ``MeetingSessionPhase/ended``.
    func newTranscript() async throws {
        guard case .ended = phase else {
            throw MeetingSessionError.invalidStateTransition(
                from: phase.label,
                attempted: "newTranscript"
            )
        }
        // Cancel any leftover tasks and clear streaming state.
        translateTask?.cancel()
        translateTask = nil
        undoTask?.cancel()
        undoTask = nil
        liveChunks = [:]
        firstEnglishSentence = nil
        phase = .idle
    }

    // MARK: - Event consumption

    /// Pumps translation events into the persistence layer and the
    /// `liveChunks` observed dictionary.
    ///
    /// ## Persistence contract (D3-A option 2)
    /// On ``TranslationEvent/partialChunk(sourceSegmentID:delta:)``,
    /// only `liveChunks[sourceSegmentID]` is mutated (delta appended) —
    /// no SwiftData write. On ``TranslationEvent/completed(_:)``,
    /// `MeetingStore.appendSentence` is called and the corresponding
    /// `liveChunks` entry is removed.
    ///
    /// ## Scheduling assumption
    /// Single producer, single consumer. The upstream
    /// `AsyncThrowingStream<TranslationEvent, any Error>` is iterated
    /// exactly once. The consumer is the orchestrator's main-actor
    /// re-entrant loop. The producer (Group C `TranslationActor`) may
    /// emit a burst of events without yielding (a "greedy producer");
    /// this method must not deadlock or drop events under greedy
    /// emission.
    ///
    /// A second call to `consumeTranslationEvents(_:)` cancels the
    /// previously running task and replaces it — at most one consumer
    /// is in flight at any moment.
    ///
    /// ## Violation of the assumption
    /// `consumeTranslationEvents_greedyProducer_doesNotDeadlockOrLoseEvents`
    /// in `MeetingSessionTests` floods the stream with 100 partials +
    /// 50 completes without yielding between yields and asserts every
    /// event is processed.
    /// `consumeTranslationEvents_secondCall_cancelsFirst` asserts the
    /// second call replaces the first cleanly.
    ///
    /// ## Delta semantics
    /// Per inspection of `TranslationActor.swift:619-627`, `delta` is
    /// the incremental token chunk emitted by LEAP's `.chunk` event —
    /// **not** a cumulative snapshot. We therefore append rather than
    /// replace. If the upstream contract ever changes to cumulative,
    /// this method must be updated.
    ///
    /// - Parameter stream: The upstream translation event stream. The
    ///   method returns immediately and consumes the stream on a
    ///   spawned task.
    func consumeTranslationEvents(
        _ stream: AsyncThrowingStream<TranslationEvent, any Error>
    ) async {
        translateTask?.cancel()
        translateTask = Task { [weak self] in
            do {
                for try await event in stream {
                    if Task.isCancelled { return }
                    await self?.process(event: event)
                }
            } catch is CancellationError {
                return
            } catch {
                // The Translating contract specifies upstream errors are
                // `TranslationError` values; for now they are not
                // surfaced through the session — UI surfaces them via
                // the inline marker pattern (decision #15) in a later
                // step. Step 3's scope is the persistence path.
                return
            }
        }
    }

    // MARK: - Internals

    /// Processes a single translation event on the main actor. Split
    /// out so the consumer task can `await` back into main-actor
    /// isolation cleanly.
    private func process(event: TranslationEvent) async {
        switch event {
        case let .partialChunk(sourceSegmentID, delta):
            // Append-on-arrival: delta is incremental per
            // TranslationActor's `.chunk` handler.
            let existing = liveChunks[sourceSegmentID] ?? ""
            liveChunks[sourceSegmentID] = existing + delta

        case let .completed(translated):
            // Capture first English sentence for title rewrite.
            if firstEnglishSentence == nil,
               translated.direction.source == .en
            {
                let trimmed = translated.sourceText
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    firstEnglishSentence = translated.sourceText
                }
            }
            // Persist on completion only.
            guard case let .recording(meetingID, _) = phase else {
                // If we're paused or stopping, still persist — the
                // sentence completed before the state change. Pull the
                // meeting ID from any active-meeting phase.
                if let activeID = activeMeetingID() {
                    await persistCompleted(translated, meetingID: activeID)
                }
                liveChunks[translated.sourceSegmentID] = nil
                return
            }
            await persistCompleted(translated, meetingID: meetingID)
            liveChunks[translated.sourceSegmentID] = nil
        }
    }

    /// Returns the active meeting's identifier if any phase is in
    /// flight, otherwise `nil`. Used by ``process(event:)`` to keep
    /// persisting completions that arrive after a phase change.
    private func activeMeetingID() -> PersistentIdentifier? {
        switch phase {
        case let .recording(id, _): return id
        case let .paused(id, _, _): return id
        case let .stoppingWithUndoWindow(id, _, _): return id
        case .ended, .idle: return nil
        }
    }

    /// Calls `MeetingStore.appendSentence` for a completed translation.
    /// Errors are swallowed by design at this layer — sentence-level
    /// persistence failures are surfaced via the inline marker pattern
    /// (decision #15) in a later UI-focused step. Step 3's contract is
    /// "best-effort persist on .completed".
    ///
    /// On successful persist, fires the ``sentencesDidUpdate`` callback
    /// (Step 9a — `ContentView` wires this to
    /// ``TranscriptSplitScreenViewModel/requestReload()``). The callback
    /// is NOT invoked when the store call throws — see the
    /// ``sentencesDidUpdate`` doc-comment for the full contract and named
    /// violation test.
    private func persistCompleted(
        _ translated: TranslatedSegment,
        meetingID: PersistentIdentifier
    ) async {
        let sourceLanguage = translated.direction.source.rawValue
        do {
            try await store.appendSentence(
                meetingID: meetingID,
                timestamp: Date(),
                sourceLanguage: sourceLanguage,
                sourceText: translated.sourceText,
                translatedText: translated.translatedText,
                sourceSegmentID: translated.sourceSegmentID
            )
            // Synchronous main-actor callback. Receiver must not block —
            // see `sentencesDidUpdate` doc-comment + named violation test
            // `meetingSession_sentencesDidUpdateBlocks_doesNotStallEventPump`.
            sentencesDidUpdate?()
        } catch {
            // Intentionally swallowed at the orchestrator layer for
            // Step 3. Future inline-marker integration will route this
            // through the UI per decision #15.
            // Note: callback NOT fired on failure — see
            // `sentencesDidUpdate` doc-comment.
        }
    }

    /// Invoked by the undo-window timer task when the clock crosses
    /// the deadline. Re-checks the phase to guard against the
    /// undo-vs-deadline race.
    private func fireDeadline(at deadline: Date) async {
        guard case .stoppingWithUndoWindow = phase else { return }
        do {
            try await finalizeStop(at: deadline)
        } catch {
            // The clock-driven path cannot bubble — UI is not in this
            // call's stack frame. Future work can route this through
            // an observable error property if needed.
        }
    }
}

// MARK: - Helpers

private extension Duration {
    /// Approximate conversion to TimeInterval (seconds), used to build
    /// wall-clock deadlines as `Date` from `Duration`-typed offsets.
    /// `Duration.components` returns `(seconds:, attoseconds:)`.
    var seconds: TimeInterval {
        let comps = components
        return TimeInterval(comps.seconds) + TimeInterval(comps.attoseconds) / 1e18
    }
}
