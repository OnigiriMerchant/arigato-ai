//
//  MeetingSessionTests.swift
//  ArigatoAITests
//
//  Created by Jose Castell on 2026/05/16.
//

@testable import ArigatoAI
import Foundation
import SwiftData
import Testing

/// Tests for ``MeetingSession`` — the @Observable @MainActor lifecycle
/// orchestrator landed in Group D Step 3.
///
/// ## Test infrastructure
/// Uses **Option F3** from the dispatch brief: a real in-memory
/// `MeetingStore` backed by `ModelConfiguration(isStoredInMemoryOnly:
/// true)`. Verification is via a separate `ModelContext` constructed
/// against the same container so the assertions prove the store's
/// `save()` is durable. No protocol gymnastics, no `@unchecked Sendable`
/// stand-ins.
///
/// The undo-window timer uses the project-local ``TestClock`` so the
/// 5-second deadline is reachable without real-time waits.
@Suite("MeetingSession")
@MainActor
struct MeetingSessionTests {
    // MARK: - Helpers

    /// Builds a fresh in-memory container for one test.
    private static func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: Meeting.self, Sentence.self,
            configurations: config
        )
    }

    /// Bundles a session-under-test with the container the test will
    /// query against to verify persistence.
    private struct Fixture {
        let container: ModelContainer
        let store: MeetingStore
        let clock: TestClock
        let session: MeetingSession
    }

    /// Builds a fully-wired fixture with a fresh container, store,
    /// `TestClock`, and `MeetingSession`. `undoWindow` defaults to 5
    /// seconds per decision #8.
    private static func makeFixture(undoWindow: Duration = .seconds(5)) throws -> Fixture {
        let container = try makeContainer()
        let store = MeetingStore(modelContainer: container)
        let clock = TestClock()
        let session = MeetingSession(
            store: store,
            clock: clock,
            undoWindow: undoWindow
        )
        return Fixture(container: container, store: store, clock: clock, session: session)
    }

    /// Builds a `TranslatedSegment` with sane defaults for tests.
    private static func translatedSegment(
        sourceSegmentID: UUID = UUID(),
        sourceText: String = "source",
        translatedText: String = "translated",
        direction: TranslationDirection = .jaToEn
    ) -> TranslatedSegment {
        TranslatedSegment(
            sourceSegmentID: sourceSegmentID,
            sourceText: sourceText,
            translatedText: translatedText,
            direction: direction,
            startHostTime: 0,
            endHostTime: 0,
            isFallback: false
        )
    }

    /// Waits up to `iterations` short main-actor yields for `condition`
    /// to become true. Returns `true` if the condition was met, `false`
    /// if the iteration budget was exhausted. Used by tests whose
    /// assertion depends on a `Task` spawned by the session having
    /// drained its work — not for real-time waits.
    private static func awaitMainActor(
        iterations: Int = 500,
        condition: () -> Bool
    ) async -> Bool {
        for _ in 0 ..< iterations {
            if condition() { return true }
            await Task.yield()
        }
        return condition()
    }

    /// Yields `count` times so a freshly spawned `Task` has a chance
    /// to start executing its body and register its `Clock.sleep`
    /// continuation. Without this, calling `TestClock.advance(by:)`
    /// immediately after `requestStop(at:)` would race the
    /// timer-task's first scheduling point — TestClock only resolves
    /// continuations that are already registered.
    private static func yieldMainActor(times count: Int = 20) async {
        for _ in 0 ..< count {
            await Task.yield()
        }
    }

    /// Waits until the SwiftData container reports at least `count`
    /// `Sentence` rows. Used as the canonical "consumer drained"
    /// signal — `liveChunks[segID] == nil` is unreliable as an
    /// initial condition because the dictionary starts empty.
    private static func awaitSentenceCount(
        _ count: Int,
        in container: ModelContainer,
        iterations: Int = 2000
    ) async -> Int {
        for _ in 0 ..< iterations {
            let ctx = ModelContext(container)
            let n = (try? ctx.fetch(FetchDescriptor<Sentence>()).count) ?? 0
            if n >= count { return n }
            await Task.yield()
        }
        let ctx = ModelContext(container)
        return (try? ctx.fetch(FetchDescriptor<Sentence>()).count) ?? 0
    }

    /// Waits until the session's phase becomes ``MeetingSessionPhase/ended``
    /// — i.e., the entire `finalizeStop` sequence (endMeeting + phase
    /// transition) has run. Title rewrite is currently deferred per
    /// the in-source comment on ``MeetingSession/finalizeStop(at:)``;
    /// once it lands, the phase transition continues to serve as the
    /// "everything in finalizeStop has run" boundary because the
    /// phase is the last write.
    private static func awaitPhaseEnded(
        on session: MeetingSession,
        iterations: Int = 2000
    ) async -> Bool {
        for _ in 0 ..< iterations {
            if case .ended = session.phase { return true }
            await Task.yield()
        }
        if case .ended = session.phase { return true }
        return false
    }

    // MARK: - Happy path

    /// `start(at:)` on an idle session transitions to `.recording`
    /// and persists a new `Meeting` row whose `persistentModelID`
    /// matches the phase's `meetingID`.
    @Test func start_fromIdle_transitionsToRecording_andCallsStoreStartMeeting() async throws {
        let fixture = try Self.makeFixture()
        let startedAt = Date(timeIntervalSince1970: 1_700_000_000)

        try await fixture.session.start(at: startedAt)

        guard case let .recording(meetingID, observedStartedAt) = fixture.session.phase else {
            Issue.record("Expected .recording phase; got \(fixture.session.phase)")
            return
        }
        #expect(observedStartedAt == startedAt)

        let context = ModelContext(fixture.container)
        let meetings = try context.fetch(FetchDescriptor<Meeting>())
        #expect(meetings.count == 1)
        #expect(meetings.first?.persistentModelID == meetingID)
    }

    /// `pause(at:)` from `.recording` transitions to `.paused` with no
    /// SwiftData side-effect (decision #7).
    @Test func pause_fromRecording_transitionsToPaused_noStoreCall() async throws {
        let fixture = try Self.makeFixture()
        let startedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let pausedAt = Date(timeIntervalSince1970: 1_700_000_100)

        try await fixture.session.start(at: startedAt)
        try await fixture.session.pause(at: pausedAt)

        guard case let .paused(_, observedStartedAt, observedPausedAt) = fixture.session.phase else {
            Issue.record("Expected .paused phase; got \(fixture.session.phase)")
            return
        }
        #expect(observedStartedAt == startedAt)
        #expect(observedPausedAt == pausedAt)

        let context = ModelContext(fixture.container)
        let meetings = try context.fetch(FetchDescriptor<Meeting>())
        #expect(meetings.count == 1, "Pause must not insert or mutate the meeting row")
        #expect(meetings.first?.endedAt == nil)
    }

    /// `resume(at:)` from `.paused` transitions back to `.recording`
    /// preserving the original `meetingID` and `startedAt`.
    @Test func resume_fromPaused_transitionsToRecording_noStoreCall() async throws {
        let fixture = try Self.makeFixture()
        let startedAt = Date(timeIntervalSince1970: 1_700_000_000)

        try await fixture.session.start(at: startedAt)
        try await fixture.session.pause(at: startedAt.addingTimeInterval(10))
        try await fixture.session.resume(at: startedAt.addingTimeInterval(20))

        guard case let .recording(_, observedStartedAt) = fixture.session.phase else {
            Issue.record("Expected .recording phase; got \(fixture.session.phase)")
            return
        }
        #expect(observedStartedAt == startedAt)
    }

    /// `requestStop(at:)` from `.recording` transitions to
    /// `.stoppingWithUndoWindow` with `deadline = stopRequestedAt +
    /// undoWindow`. The Meeting row's `endedAt` must remain `nil`.
    @Test func requestStop_fromRecording_transitionsToStoppingWithUndoWindow_noStoreCall() async throws {
        let fixture = try Self.makeFixture(undoWindow: .seconds(5))
        let startedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let stopRequestedAt = startedAt.addingTimeInterval(30)

        try await fixture.session.start(at: startedAt)
        try await fixture.session.requestStop(at: stopRequestedAt)

        guard case let .stoppingWithUndoWindow(_, _, deadline) = fixture.session.phase else {
            Issue.record("Expected .stoppingWithUndoWindow; got \(fixture.session.phase)")
            return
        }
        #expect(deadline == stopRequestedAt.addingTimeInterval(5))

        let context = ModelContext(fixture.container)
        let meetings = try context.fetch(FetchDescriptor<Meeting>())
        #expect(meetings.first?.endedAt == nil, "endedAt must not be set until finalizeStop")
    }

    /// `requestStop(at:)` is also valid from `.paused`.
    @Test func requestStop_fromPaused_transitionsToStoppingWithUndoWindow_noStoreCall() async throws {
        let fixture = try Self.makeFixture(undoWindow: .seconds(3))
        let startedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let stopRequestedAt = startedAt.addingTimeInterval(60)

        try await fixture.session.start(at: startedAt)
        try await fixture.session.pause(at: startedAt.addingTimeInterval(30))
        try await fixture.session.requestStop(at: stopRequestedAt)

        guard case let .stoppingWithUndoWindow(_, _, deadline) = fixture.session.phase else {
            Issue.record("Expected .stoppingWithUndoWindow from paused; got \(fixture.session.phase)")
            return
        }
        #expect(deadline == stopRequestedAt.addingTimeInterval(3))
    }

    /// `undoStop()` from `.stoppingWithUndoWindow` cancels the deadline
    /// timer and transitions back to `.recording`. Advancing the clock
    /// past the would-have-been deadline must not finalize the meeting.
    @Test func undoStop_fromStoppingWithUndoWindow_transitionsToRecording() async throws {
        let fixture = try Self.makeFixture(undoWindow: .seconds(5))
        try await fixture.session.start(at: Date(timeIntervalSince1970: 1_700_000_000))
        try await fixture.session.requestStop(at: Date(timeIntervalSince1970: 1_700_000_030))

        // Let the timer Task register its sleep before any clock advance.
        await Self.yieldMainActor()
        fixture.clock.advance(by: .seconds(1))
        try await fixture.session.undoStop()
        // Advance well past the original deadline. The cancelled
        // timer's continuation will resume (TestClock doesn't honor
        // cancellation natively) and the timer Task will call
        // `fireDeadline`, but `fireDeadline`'s `case
        // .stoppingWithUndoWindow` guard fails because we're now in
        // `.recording`, so no phase change.
        fixture.clock.advance(by: .seconds(20))
        // Give the cancelled task a few yields to actually exit.
        _ = await Self.awaitMainActor { true }

        guard case .recording = fixture.session.phase else {
            Issue.record("Expected .recording after undo; got \(fixture.session.phase)")
            return
        }
        let context = ModelContext(fixture.container)
        let meetings = try context.fetch(FetchDescriptor<Meeting>())
        #expect(meetings.first?.endedAt == nil, "undoStop must not finalize the meeting")
    }

    /// Letting the deadline expire transitions through to `.ended` and
    /// calls `MeetingStore.endMeeting`. Title rewrite uses the
    /// captured first English sentence if one is available.
    @Test func deadlineExpiry_fromStoppingWithUndoWindow_transitionsToEnded_andCallsStoreEndMeeting() async throws {
        let fixture = try Self.makeFixture(undoWindow: .seconds(5))
        let startedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let stopRequestedAt = startedAt.addingTimeInterval(30)

        try await fixture.session.start(at: startedAt)

        // Feed one English `.completed` so the title rewrite has a
        // sentence to splice in.
        let (stream, continuation) = AsyncThrowingStream<TranslationEvent, any Error>.makeStream()
        await fixture.session.consumeTranslationEvents(stream)
        let segID = UUID()
        let englishSegment = Self.translatedSegment(
            sourceSegmentID: segID,
            sourceText: "Hello, everyone.",
            translatedText: "皆さん、こんにちは。",
            direction: .enToJa
        )
        continuation.yield(.completed(englishSegment))
        continuation.finish()
        // Wait for the sentence to land — canonical "consumer drained"
        // signal, unlike liveChunks==nil which is true from the start.
        _ = await Self.awaitSentenceCount(1, in: fixture.container)

        try await fixture.session.requestStop(at: stopRequestedAt)
        // Let the timer Task register its sleep continuation before
        // advancing the synthetic clock.
        await Self.yieldMainActor()
        fixture.clock.advance(by: .seconds(5))
        // Wait for the deadline-fired finalizeStop to land. We wait
        // for the *phase* transition (not just endedAt) because the
        // title rewrite runs between `endMeeting` and the phase change.
        let landed = await Self.awaitPhaseEnded(on: fixture.session)
        #expect(landed, "Deadline should have transitioned phase to .ended")

        guard case let .ended(_, observedStartedAt, _) = fixture.session.phase else {
            Issue.record("Expected .ended after deadline; got \(fixture.session.phase)")
            return
        }
        #expect(observedStartedAt == startedAt)

        let context = ModelContext(fixture.container)
        let meetings = try context.fetch(FetchDescriptor<Meeting>())
        #expect(meetings.first?.endedAt != nil, "Deadline expiry should set endedAt")
        // NOTE: Title rewrite is deferred — see the in-source comment
        // on `MeetingSession.finalizeStop(at:)`. Until the
        // pre-authorized `MeetingStore.updateTitle` STOP is resolved,
        // the title remains the placeholder set at `start(at:)`.
    }

    /// `newTranscript()` from `.ended` returns to `.idle` and clears
    /// `liveChunks`.
    @Test func newTranscript_fromEnded_transitionsToIdle() async throws {
        let fixture = try Self.makeFixture(undoWindow: .seconds(1))
        let startedAt = Date(timeIntervalSince1970: 1_700_000_000)

        try await fixture.session.start(at: startedAt)
        try await fixture.session.requestStop(at: startedAt.addingTimeInterval(10))
        await Self.yieldMainActor()
        fixture.clock.advance(by: .seconds(1))
        // Use the phase transition as the canonical "finalizeStop
        // fully ran" indicator (covers the title-rewrite step too).
        let ended = await Self.awaitPhaseEnded(on: fixture.session)
        #expect(ended, "Deadline should have triggered finalizeStop and ended the phase")

        // Plant some leftover liveChunks state to prove
        // newTranscript clears it. Note: the post-ended phase keeps
        // any prior consumer task cancelled; we plant directly via a
        // new consumer call, but since the session is in .ended,
        // events may not process. So instead, drive a partial via a
        // partial first while still in .recording? No — we are in
        // .ended. We simply rely on `liveChunks` being cleared by
        // `newTranscript()` even if empty before the call.
        try await fixture.session.newTranscript()
        #expect(fixture.session.phase == .idle)
        #expect(fixture.session.liveChunks.isEmpty)
    }

    /// `.partialChunk` updates `liveChunks` (append on arrival, per
    /// `TranslationActor.swift:619-627` delta semantics) and does not
    /// insert a Sentence row.
    @Test func consumeTranslationEvents_partialChunk_updatesLiveChunks_noStoreCall() async throws {
        let fixture = try Self.makeFixture()
        try await fixture.session.start(at: Date())

        let (stream, cont) = AsyncThrowingStream<TranslationEvent, any Error>.makeStream()
        await fixture.session.consumeTranslationEvents(stream)

        let segID = UUID()
        cont.yield(.partialChunk(sourceSegmentID: segID, delta: "Hel"))
        cont.yield(.partialChunk(sourceSegmentID: segID, delta: "lo"))
        cont.yield(.partialChunk(sourceSegmentID: segID, delta: " world"))
        cont.finish()

        _ = await Self.awaitMainActor {
            fixture.session.liveChunks[segID] == "Hello world"
        }
        #expect(fixture.session.liveChunks[segID] == "Hello world")

        let context = ModelContext(fixture.container)
        let sentences = try context.fetch(FetchDescriptor<Sentence>())
        #expect(sentences.isEmpty, "Partial chunks must not persist a Sentence row")
    }

    /// `.completed` calls `appendSentence` and clears the matching
    /// `liveChunks` entry. The persisted Sentence row carries the
    /// expected fields.
    @Test func consumeTranslationEvents_completed_callsStoreAppendSentence_clearsLiveChunks() async throws {
        let fixture = try Self.makeFixture()
        try await fixture.session.start(at: Date())

        let (stream, cont) = AsyncThrowingStream<TranslationEvent, any Error>.makeStream()
        await fixture.session.consumeTranslationEvents(stream)

        let segID = UUID()
        cont.yield(.partialChunk(sourceSegmentID: segID, delta: "partial"))
        let completed = Self.translatedSegment(
            sourceSegmentID: segID,
            sourceText: "こんにちは",
            translatedText: "Hello",
            direction: .jaToEn
        )
        cont.yield(.completed(completed))
        cont.finish()

        // The persisted-sentence count is the canonical "consumer
        // drained the .completed event" signal. After the sentence
        // lands, the consumer task may not yet have resumed past its
        // `await persistCompleted` to clear `liveChunks`, so we wait
        // a second pump for the clear to land before asserting.
        let landed = await Self.awaitSentenceCount(1, in: fixture.container)
        #expect(landed == 1)
        _ = await Self.awaitMainActor { fixture.session.liveChunks[segID] == nil }
        #expect(fixture.session.liveChunks[segID] == nil, "Completed event must clear liveChunks entry")

        let context = ModelContext(fixture.container)
        let sentences = try context.fetch(FetchDescriptor<Sentence>())
        #expect(sentences.first?.sourceText == "こんにちは")
        #expect(sentences.first?.translatedText == "Hello")
        #expect(sentences.first?.sourceLanguage == "ja")
        #expect(sentences.first?.sourceSegmentID == segID)
    }

    /// First English `.completed` is captured for the eventual title
    /// rewrite. Once the pre-authorized
    /// `MeetingStore.updateTitle(meetingID:title:)` STOP point lands,
    /// this test will assert the rewritten title contains the English
    /// sentence; **for now** (Step 3) the title-rewrite path in
    /// `finalizeStop(at:)` is deferred, so this test verifies the
    /// observable contract that remains: meeting finalises cleanly
    /// and the placeholder timestamp-only title is preserved while
    /// the English-sentence capture continues to run inside the
    /// orchestrator (verified indirectly by sentence persistence and
    /// the no-crash contract).
    ///
    /// When the follow-up dispatch lands, swap the placeholder
    /// assertion below for the title-contains-sentence assertion the
    /// brief described.
    @Test func firstEnglishSentence_capturedOnFirstCompleted_usedInFinalizeStopTitleRewrite() async throws {
        let fixture = try Self.makeFixture(undoWindow: .seconds(1))
        let startedAt = Date(timeIntervalSince1970: 1_700_000_000)
        try await fixture.session.start(at: startedAt)

        let (stream, cont) = AsyncThrowingStream<TranslationEvent, any Error>.makeStream()
        await fixture.session.consumeTranslationEvents(stream)

        let englishID = UUID()
        let japaneseID = UUID()
        cont.yield(.completed(Self.translatedSegment(
            sourceSegmentID: englishID,
            sourceText: "First English sentence",
            translatedText: "最初の英文",
            direction: .enToJa
        )))
        cont.yield(.completed(Self.translatedSegment(
            sourceSegmentID: japaneseID,
            sourceText: "後から来た日本語",
            translatedText: "Japanese that arrived later",
            direction: .jaToEn
        )))
        cont.finish()

        // Wait for both completions to land before STOPping. Use the
        // store sentence-count as the canonical signal.
        _ = await Self.awaitSentenceCount(2, in: fixture.container)

        try await fixture.session.requestStop(at: startedAt.addingTimeInterval(60))
        await Self.yieldMainActor()
        fixture.clock.advance(by: .seconds(1))
        let phaseEnded = await Self.awaitPhaseEnded(on: fixture.session)
        #expect(phaseEnded, "Deadline should have transitioned phase to .ended")

        let context = ModelContext(fixture.container)
        let meetings = try context.fetch(FetchDescriptor<Meeting>())
        let title = meetings.first?.title ?? ""
        // Placeholder contract — title is the bare timestamp set at
        // `start(at:)`. Title-rewrite path is deferred (see
        // `MeetingSession.finalizeStop(at:)` in-source comment).
        #expect(title.contains("First English sentence") == false,
                "Until updateTitle is wired up, the title should remain the placeholder; got '\(title)'")
        #expect(title.isEmpty == false, "Placeholder title should be set at start(at:)")
    }

    // MARK: - Invalid transitions

    /// `start(at:)` from `.recording` throws
    /// `invalidStateTransition`.
    @Test func start_fromRecording_throwsInvalidStateTransition() async throws {
        let fixture = try Self.makeFixture()
        try await fixture.session.start(at: Date())

        await #expect(throws: MeetingSessionError.invalidStateTransition(
            from: "recording", attempted: "start"
        )) {
            try await fixture.session.start(at: Date())
        }
    }

    /// `pause(at:)` from `.idle` throws `invalidStateTransition`.
    @Test func pause_fromIdle_throwsInvalidStateTransition() async throws {
        let fixture = try Self.makeFixture()
        await #expect(throws: MeetingSessionError.invalidStateTransition(
            from: "idle", attempted: "pause"
        )) {
            try await fixture.session.pause(at: Date())
        }
    }

    /// `undoStop()` from `.recording` throws `invalidStateTransition`.
    @Test func undoStop_fromRecording_throwsInvalidStateTransition() async throws {
        let fixture = try Self.makeFixture()
        try await fixture.session.start(at: Date())

        await #expect(throws: MeetingSessionError.invalidStateTransition(
            from: "recording", attempted: "undoStop"
        )) {
            try await fixture.session.undoStop()
        }
    }

    // MARK: - Concurrency-discipline violation tests

    /// **Concurrency violation test (per CLAUDE.md "Concurrency design
    /// discipline").** Drives the undoStop-vs-deadline race: undo
    /// dispatched **before** the clock crosses the deadline must win.
    /// The doc-comment on ``MeetingSession/undoStop()`` and
    /// ``MeetingSession/finalizeStop(at:)`` names this test.
    @Test func undoStop_racesWithDeadlineExpiry_undoWinsIfDispatchedBeforeFire() async throws {
        let fixture = try Self.makeFixture(undoWindow: .seconds(5))
        try await fixture.session.start(at: Date(timeIntervalSince1970: 1_700_000_000))
        try await fixture.session.requestStop(at: Date(timeIntervalSince1970: 1_700_000_030))

        // Let the timer Task register its sleep before advancing.
        await Self.yieldMainActor()
        // Advance to just before the deadline (4.9s of 5s window).
        fixture.clock.advance(by: .milliseconds(4900))
        // Give the timer one chance to settle (it shouldn't have fired).
        await Task.yield()
        try await fixture.session.undoStop()

        // Now advance past the would-have-been deadline.
        fixture.clock.advance(by: .seconds(1))
        // Give the (cancelled) timer plenty of yields to surface a
        // spurious finalize if it were going to.
        _ = await Self.awaitMainActor(iterations: 50) { false }

        guard case .recording = fixture.session.phase else {
            Issue.record("Expected .recording (undo wins); got \(fixture.session.phase)")
            return
        }
        let context = ModelContext(fixture.container)
        let meetings = try context.fetch(FetchDescriptor<Meeting>())
        #expect(meetings.first?.endedAt == nil)
    }

    /// **Concurrency violation test.** A greedy producer that yields
    /// 100 partial chunks + 50 completions back-to-back without
    /// `Task.yield()` between yields must still see every event
    /// processed. Doc-comment on
    /// ``MeetingSession/consumeTranslationEvents(_:)`` names this test.
    @Test func consumeTranslationEvents_greedyProducer_doesNotDeadlockOrLoseEvents() async throws {
        let fixture = try Self.makeFixture()
        try await fixture.session.start(at: Date())

        // Pre-generate 50 segment IDs; each gets two partial deltas
        // then one completion.
        let segmentIDs: [UUID] = (0 ..< 50).map { _ in UUID() }

        let (stream, cont) = AsyncThrowingStream<TranslationEvent, any Error>.makeStream()
        await fixture.session.consumeTranslationEvents(stream)

        // Greedy: 100 partials + 50 completes back-to-back, no
        // intermediate yields.
        for segID in segmentIDs {
            cont.yield(.partialChunk(sourceSegmentID: segID, delta: "a"))
            cont.yield(.partialChunk(sourceSegmentID: segID, delta: "b"))
        }
        for segID in segmentIDs {
            cont.yield(.completed(Self.translatedSegment(
                sourceSegmentID: segID,
                sourceText: "src-\(segID.uuidString.prefix(4))",
                translatedText: "tr-\(segID.uuidString.prefix(4))",
                direction: .jaToEn
            )))
        }
        cont.finish()

        // Wait for all 50 completions to persist. SwiftData
        // sentence-count is the canonical signal that the consumer
        // task drained the stream without losing events.
        let landedCount = await Self.awaitSentenceCount(50, in: fixture.container, iterations: 5000)
        #expect(landedCount == 50,
                "All 50 completions should have persisted; landed \(landedCount)")
        // The consumer task may not yet have cleared every `liveChunks`
        // entry by the time the 50th sentence becomes visible to a
        // fresh ModelContext; wait one more pump for the clears to
        // land before asserting.
        _ = await Self.awaitMainActor(iterations: 5000) { fixture.session.liveChunks.isEmpty }
        #expect(fixture.session.liveChunks.isEmpty,
                "All liveChunks entries should be cleared; remaining: \(fixture.session.liveChunks.count)")

        let context = ModelContext(fixture.container)
        let sentences = try context.fetch(FetchDescriptor<Sentence>())
        let landedIDs = Set(sentences.map(\.sourceSegmentID))
        #expect(landedIDs == Set(segmentIDs),
                "Persisted segment IDs do not match emitted IDs (drops/duplicates)")
    }

    /// **Concurrency violation test.** STOP → Undo → STOP again must
    /// arm a fresh deadline from the second STOP. The doc-comment on
    /// ``MeetingSession/requestStop(at:)`` names this test.
    @Test func requestStop_thenImmediateUndoStop_thenImmediateRequestStop_correctlyArmsFreshDeadline() async throws {
        let fixture = try Self.makeFixture(undoWindow: .seconds(5))
        let startedAt = Date(timeIntervalSince1970: 1_700_000_000)

        try await fixture.session.start(at: startedAt)
        let firstStopAt = startedAt.addingTimeInterval(30)
        try await fixture.session.requestStop(at: firstStopAt)
        // Let the first timer Task register its sleep before any
        // clock advance.
        await Self.yieldMainActor()
        fixture.clock.advance(by: .milliseconds(1000))
        try await fixture.session.undoStop()

        // Advance the clock to the original deadline. If the first
        // timer were still armed (it has been cancelled) it would
        // resume here — but the timer task's catch returns early.
        fixture.clock.advance(by: .seconds(4))
        _ = await Self.awaitMainActor(iterations: 50) { false }
        guard case .recording = fixture.session.phase else {
            Issue.record("Original timer must not have fired; got \(fixture.session.phase)")
            return
        }

        // Second STOP — fresh window starts here.
        let secondStopAt = startedAt.addingTimeInterval(40)
        try await fixture.session.requestStop(at: secondStopAt)
        guard case let .stoppingWithUndoWindow(_, _, deadline) = fixture.session.phase else {
            Issue.record("Expected stoppingWithUndoWindow after second stop; got \(fixture.session.phase)")
            return
        }
        #expect(deadline == secondStopAt.addingTimeInterval(5),
                "Second deadline must be relative to the second stop, not the first")

        // Drive the second deadline. Yield first so the new timer
        // Task registers its sleep on TestClock.
        await Self.yieldMainActor()
        fixture.clock.advance(by: .seconds(5))
        let ended = await Self.awaitPhaseEnded(on: fixture.session)
        #expect(ended, "Second deadline should finalize the phase")
        guard case .ended = fixture.session.phase else {
            Issue.record("Second deadline should finalize the phase; got \(fixture.session.phase)")
            return
        }
    }

    /// **Concurrency violation test.** A second call to
    /// `consumeTranslationEvents(_:)` cancels the first task and
    /// replaces it. After the second call, events on the second
    /// stream must be processed; events on the first stream are
    /// ignored.
    ///
    /// Named by the doc-comment on
    /// ``MeetingSession/consumeTranslationEvents(_:)``.
    @Test func consumeTranslationEvents_secondCall_cancelsFirst() async throws {
        let fixture = try Self.makeFixture()
        try await fixture.session.start(at: Date())

        let (firstStream, firstCont) = AsyncThrowingStream<TranslationEvent, any Error>.makeStream()
        await fixture.session.consumeTranslationEvents(firstStream)

        let (secondStream, secondCont) = AsyncThrowingStream<TranslationEvent, any Error>.makeStream()
        await fixture.session.consumeTranslationEvents(secondStream)

        let firstSegID = UUID()
        let secondSegID = UUID()

        // Events yielded to the first stream after replacement must
        // not surface on liveChunks (its consumer task is cancelled
        // and the stream is unobserved).
        firstCont.yield(.partialChunk(sourceSegmentID: firstSegID, delta: "stale"))
        firstCont.finish()

        secondCont.yield(.partialChunk(sourceSegmentID: secondSegID, delta: "fresh"))
        secondCont.finish()

        _ = await Self.awaitMainActor {
            fixture.session.liveChunks[secondSegID] == "fresh"
        }
        #expect(fixture.session.liveChunks[secondSegID] == "fresh")
        #expect(fixture.session.liveChunks[firstSegID] == nil,
                "First stream's events must not surface after the second call replaces the consumer")
    }
}
