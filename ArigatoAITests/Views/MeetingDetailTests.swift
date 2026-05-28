//
//  MeetingDetailTests.swift
//  ArigatoAITests
//
//  Created by Jose Castell on 2026/05/16.
//

@testable import ArigatoAI
import Foundation
import os
import SwiftData
import Testing

// MARK: - VM tests

/// Tests for ``MeetingDetailViewModel`` — Step 11's Phase-2 trio
/// view-model surface. Mirrors the test pattern locked by Step 6
/// (``MeetingListViewTests``) and Step 9a
/// (``TranscriptSplitScreenViewModelTests``): closure-injected fetcher
/// drives success / throw / sleep-then-return paths; assertions read the
/// `@Observable` state directly.
///
/// `@MainActor` because the VM is `@MainActor` and the project default
/// is `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`.
@Suite("MeetingDetailViewModel")
@MainActor
struct MeetingDetailViewModelTests {
    /// Builds an in-memory container fresh per test that needs real
    /// `PersistentIdentifier` values.
    private static func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: Meeting.self, Sentence.self,
            configurations: config
        )
    }

    /// Mints a real `PersistentIdentifier` by inserting a transient
    /// `Meeting` row into an in-memory container. `PersistentIdentifier`
    /// has no public initializer.
    private static func mintIdentifier() throws -> PersistentIdentifier {
        let container = try makeContainer()
        let context = ModelContext(container)
        let m = Meeting(startedAt: Date(), title: "id-mint")
        context.insert(m)
        try context.save()
        return m.persistentModelID
    }

    /// Builds a fixed-shape projection without going through SwiftData
    /// for the success/throw test paths.
    private static func makeProjection(
        id: PersistentIdentifier,
        timestamp: Date = Date(),
        sourceLanguage: String = "ja",
        sourceText: String = "src",
        translatedText: String = "tr"
    ) -> MeetingDetail.SentenceProjection {
        MeetingDetail.SentenceProjection(
            id: id,
            timestamp: timestamp,
            sourceLanguage: sourceLanguage,
            sourceText: sourceText,
            translatedText: translatedText,
            sourceSegmentID: UUID()
        )
    }

    // MARK: - D11-T-vm-1 (violation test)

    /// **D11-T-vm-1** (concurrency violation test) — Rapid
    /// ``MeetingDetailViewModel/reload()`` calls must be serialized
    /// last-query-wins: the second call's payload is the one that lands
    /// in ``MeetingDetailViewModel/sentences``, even when the first call
    /// is still in-flight.
    ///
    /// Mirrors the pattern from
    /// ``MeetingListViewTests/meetingListView_rapidRefreshTriggerChanges_lastQueryWins``
    /// (Step 6) and
    /// ``TranscriptSplitScreenViewModelTests/viewModel_rapidSentencesDidUpdate_lastReloadWins``
    /// (Step 9a): spawn the first `reload()` in a Task against a fetcher
    /// whose first call sleeps; cancel mid-sleep; await the cancelled
    /// task's completion; run the second `reload()` synchronously
    /// against the second-call payload. Only the second payload must
    /// land.
    @Test func rapidRequestReload_lastQueryWins() async throws {
        let id = try Self.mintIdentifier()
        let firstPayload = [
            Self.makeProjection(id: id, sourceText: "first-call (cancelled)"),
        ]
        let secondPayload = [
            Self.makeProjection(id: id, sourceText: "second-call (last query wins)"),
        ]

        let dispatcher = ProjectionDispatcher(
            slowResult: firstPayload,
            fastResult: secondPayload
        )

        let vm = MeetingDetailViewModel(meetingID: id, fetcher: dispatcher.makeFetcher())

        // Spawn the first reload; cancel before its sleep elapses.
        let firstReloadTask = Task { await vm.reload() }
        try? await Task.sleep(nanoseconds: 10_000_000)
        firstReloadTask.cancel()
        // Wait for the cancelled task to finish so its `catch
        // CancellationError` writes loadError BEFORE the second call's
        // success path clears it. Without this await the test would be
        // non-deterministic across runs.
        await firstReloadTask.value

        await vm.reload()

        #expect(vm.sentences.map(\.sourceText) == ["second-call (last query wins)"])
        #expect(
            vm.loadError == nil,
            "Second call's success should have cleared the cancellation error."
        )
    }

    // MARK: - D11-T-vm-2

    /// **D11-T-vm-2** — A successful reload publishes the fetcher's
    /// payload into ``MeetingDetailViewModel/sentences`` in the order
    /// the fetcher returned them, and leaves
    /// ``MeetingDetailViewModel/loadError`` nil.
    @Test func reload_success_publishesSentencesInTimestampOrder() async throws {
        let id = try Self.mintIdentifier()
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let payload = [
            Self.makeProjection(id: id, timestamp: t0.addingTimeInterval(0), sourceText: "first"),
            Self.makeProjection(id: id, timestamp: t0.addingTimeInterval(10), sourceText: "second"),
            Self.makeProjection(id: id, timestamp: t0.addingTimeInterval(20), sourceText: "third"),
        ]

        let vm = MeetingDetailViewModel(meetingID: id, fetcher: { _ in payload })
        await vm.reload()

        #expect(vm.sentences.count == 3)
        #expect(vm.sentences.map(\.sourceText) == ["first", "second", "third"])
        #expect(vm.loadError == nil)
    }

    // MARK: - D11-T-vm-3

    /// **D11-T-vm-3** — A throwing fetcher captures the error into
    /// ``MeetingDetailViewModel/loadError`` and leaves a
    /// previously-loaded ``MeetingDetailViewModel/sentences`` payload
    /// untouched. This is the "transient failure on a retry" contract:
    /// the view should keep showing the last good data while the
    /// inline error renders.
    @Test func reload_throwingFetcher_storesErrorAndLeavesSentencesUnchanged() async throws {
        let id = try Self.mintIdentifier()
        let seededPayload = [
            Self.makeProjection(id: id, sourceText: "seeded"),
        ]

        // Two-shot fetcher: first call seeds, second call throws.
        struct Boom: Error, Equatable {}
        let callCounter = OSAllocatedUnfairLock<Int>(initialState: 0)
        let fetcher: @MainActor (PersistentIdentifier) async throws -> [MeetingDetail.SentenceProjection] = { _ in
            let isFirst = callCounter.withLock { count -> Bool in
                count += 1
                return count == 1
            }
            if isFirst { return seededPayload }
            throw Boom()
        }

        let vm = MeetingDetailViewModel(meetingID: id, fetcher: fetcher)
        await vm.reload()
        #expect(vm.sentences.map(\.sourceText) == ["seeded"])
        #expect(vm.loadError == nil)

        await vm.reload()
        #expect(
            vm.sentences.map(\.sourceText) == ["seeded"],
            "A throwing reload must NOT clear previously-loaded sentences."
        )
        #expect(vm.loadError is Boom)
    }

    // MARK: - D11-T-vm-4

    /// **D11-T-vm-4** — An empty fetcher result publishes an empty array
    /// and clears any prior error. Drives the view body's empty-state
    /// branch (`sentences.isEmpty && loadError == nil`).
    @Test func reload_emptyFetcher_publishesEmptyArray() async throws {
        let id = try Self.mintIdentifier()
        let vm = MeetingDetailViewModel(meetingID: id, fetcher: { _ in [] })

        await vm.reload()

        #expect(vm.sentences.isEmpty)
        #expect(vm.loadError == nil)
    }

    // MARK: - MVP1-11-copy-1

    /// **MVP1-11-copy-1** — ``MeetingDetailViewModel/copyTranscript(summary:)``
    /// writes EXACTLY the exporter's Markdown to the injected pasteboard
    /// seam. Proves the VM (a) renders via
    /// ``TranscriptExporter/markdownBody(summary:sentences:)`` over its
    /// current ``MeetingDetailViewModel/sentences`` and (b) hands that
    /// string to the pasteboard writer — the byte-identity guarantee the
    /// Copy button relies on (same body the `ShareLink` exports).
    @Test func copyTranscript_writesExporterMarkdownToPasteboard() async throws {
        let container = try Self.makeContainer()
        let context = ModelContext(container)
        let started = Date(timeIntervalSince1970: 1_700_000_000)
        let meeting = Meeting(startedAt: started, title: "Copy fixture")
        meeting.endedAt = started.addingTimeInterval(60)
        context.insert(meeting)
        try context.save()
        let summary = MeetingSummary(from: meeting)
        let id = meeting.persistentModelID

        let payload = [
            Self.makeProjection(
                id: id,
                timestamp: started.addingTimeInterval(1),
                sourceLanguage: "ja",
                sourceText: "こんにちは",
                translatedText: "Hello"
            ),
            Self.makeProjection(
                id: id,
                timestamp: started.addingTimeInterval(2),
                sourceLanguage: "en",
                sourceText: "Goodbye",
                translatedText: "さようなら"
            ),
        ]

        // Fake pasteboard writer records the written string. The closure
        // is `@MainActor`-isolated like the seam, and the test suite is
        // `@MainActor`, so a plain box would suffice — but the project's
        // Swift 6 fake-state rule prefers `OSAllocatedUnfairLock` for any
        // recorder that could be read across isolation, and it costs
        // nothing here.
        let recorded = OSAllocatedUnfairLock<String?>(initialState: nil)
        let vm = MeetingDetailViewModel(
            meetingID: id,
            fetcher: { _ in payload },
            writeToPasteboard: { value in recorded.withLock { $0 = value } }
        )
        await vm.reload()
        #expect(vm.sentences.count == 2)

        vm.copyTranscript(summary: summary)

        let expected = TranscriptExporter.markdownBody(
            summary: summary,
            sentences: payload
        )
        #expect(recorded.withLock { $0 } == expected)
    }

    // MARK: - D11-T-vm-5

    /// **D11-T-vm-5** — The `convenience init(store:meetingID:)` closes
    /// over the live ``MeetingStore`` and the supplied identifier; a
    /// subsequent ``MeetingDetailViewModel/reload()`` performs the
    /// round-trip and lands the actor-returned projections in
    /// ``MeetingDetailViewModel/sentences``.
    ///
    /// Verifies the convenience path itself (production wiring) rather
    /// than only the closure-injected designated init.
    @Test func convenienceInit_closesOverStoreAndMeetingID() async throws {
        let container = try Self.makeContainer()
        let store = MeetingStore(modelContainer: container)
        let started = Date(timeIntervalSince1970: 1_700_000_000)
        let meetingID = try await store.startMeeting(startedAt: started, title: "round-trip")
        try await store.appendSentence(
            meetingID: meetingID,
            timestamp: started.addingTimeInterval(1),
            sourceLanguage: "ja",
            sourceText: "こんにちは",
            translatedText: "Hello",
            sourceSegmentID: UUID()
        )
        try await store.appendSentence(
            meetingID: meetingID,
            timestamp: started.addingTimeInterval(2),
            sourceLanguage: "en",
            sourceText: "Goodbye",
            translatedText: "さようなら",
            sourceSegmentID: UUID()
        )

        let vm = MeetingDetailViewModel(store: store, meetingID: meetingID)
        await vm.reload()

        #expect(vm.sentences.count == 2)
        #expect(vm.sentences.map(\.sourceText) == ["こんにちは", "Goodbye"])
        #expect(vm.loadError == nil)
    }
}

// MARK: - Formatter tests

/// Tests for ``MeetingDetailFormatter`` — pure-value byte-identity
/// assertions over delegated formatters (UI decision #15) plus the
/// language-alignment contract for ``MeetingDetailFormatter/sentenceBody(for:)``.
@Suite("MeetingDetailFormatter")
@MainActor
struct MeetingDetailFormatterTests {
    /// Builds an in-memory container to mint a real
    /// `PersistentIdentifier` for projection fixtures.
    private static func mintIdentifier() throws -> PersistentIdentifier {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Meeting.self, Sentence.self,
            configurations: config
        )
        let context = ModelContext(container)
        let m = Meeting(startedAt: Date(), title: "fmt-mint")
        context.insert(m)
        try context.save()
        return m.persistentModelID
    }

    // MARK: - D11-T-fmt-1

    /// **D11-T-fmt-1** — ``MeetingDetailFormatter/formattedDate(_:)``
    /// produces byte-identical output to
    /// ``MeetingListRowFormatter/formattedDate(_:)`` for three sample
    /// dates. Locks UI decision #15 byte-identity (history list and
    /// detail header render the SAME string for the SAME date).
    @Test func formattedDate_matchesMeetingListRowFormatter() {
        let samples = [
            Date(timeIntervalSince1970: 1_700_000_000),
            Date(timeIntervalSince1970: 1_500_000_000),
            Date(timeIntervalSince1970: 2_000_000_000),
        ]
        for date in samples {
            #expect(
                MeetingDetailFormatter.formattedDate(date) ==
                    MeetingListRowFormatter.formattedDate(date),
                "Detail and list formatters must produce byte-identical date strings (UI #15)."
            )
        }
    }

    // MARK: - D11-T-fmt-2

    /// **D11-T-fmt-2** — Whole-minute duration when `ended` is non-nil.
    /// 50:12 elapsed should round down to `"50 min"`, matching
    /// ``MeetingListRowFormatter/formattedDuration(startedAt:endedAt:)``'s
    /// floor behavior.
    @Test func formattedDuration_endedNonNil_returnsWholeMinutes() {
        let started = Date(timeIntervalSince1970: 1_700_000_000)
        let ended = started.addingTimeInterval(50 * 60 + 12) // 50 min 12 sec

        let duration = MeetingDetailFormatter.formattedDuration(started: started, ended: ended)

        #expect(duration == "50 min")
    }

    // MARK: - D11-T-fmt-3

    /// **D11-T-fmt-3** — An active meeting (`ended == nil`) renders the
    /// em-dash sentinel `"—"`. Matches
    /// ``MeetingListRowFormatter/formattedDuration(startedAt:endedAt:)``'s
    /// active-meeting contract.
    @Test func formattedDuration_endedNil_returnsEmDash() {
        let started = Date(timeIntervalSince1970: 1_700_000_000)

        let duration = MeetingDetailFormatter.formattedDuration(started: started, ended: nil)

        #expect(duration == "—")
    }

    // MARK: - D11-T-fmt-4

    /// **D11-T-fmt-4** — When `sourceLanguage == "ja"`, the Japanese
    /// row body equals `sourceText` (the original utterance) and the
    /// English row body equals `translatedText`.
    @Test func sentenceBody_jaSource_japaneseEqualsSourceText() throws {
        let id = try Self.mintIdentifier()
        let sentence = MeetingDetail.SentenceProjection(
            id: id,
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            sourceLanguage: "ja",
            sourceText: "こんにちは",
            translatedText: "Hello",
            sourceSegmentID: UUID()
        )

        let body = MeetingDetailFormatter.sentenceBody(for: sentence)

        #expect(body.japanese == "こんにちは")
        #expect(body.english == "Hello")
    }

    // MARK: - D11-T-fmt-5

    /// **D11-T-fmt-5** — When `sourceLanguage == "en"`, the English row
    /// body equals `sourceText` (the original utterance) and the
    /// Japanese row body equals `translatedText`. Mirror of
    /// `D11-T-fmt-4`.
    @Test func sentenceBody_enSource_englishEqualsSourceText() throws {
        let id = try Self.mintIdentifier()
        let sentence = MeetingDetail.SentenceProjection(
            id: id,
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            sourceLanguage: "en",
            sourceText: "Goodbye",
            translatedText: "さようなら",
            sourceSegmentID: UUID()
        )

        let body = MeetingDetailFormatter.sentenceBody(for: sentence)

        #expect(body.english == "Goodbye")
        #expect(body.japanese == "さようなら")
    }
}

// MARK: - View tests

/// Tests for ``MeetingDetailView`` — view-level behavior exercised
/// indirectly via the VM state the view branches on (ViewInspector is
/// not a project dependency, see ``MeetingListViewTests`` for the
/// established pattern).
@Suite("MeetingDetailView")
@MainActor
struct MeetingDetailViewTests {
    /// Builds an in-memory container for `PersistentIdentifier` fixtures.
    private static func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: Meeting.self, Sentence.self,
            configurations: config
        )
    }

    /// Mints a real `PersistentIdentifier`.
    private static func mintIdentifier() throws -> PersistentIdentifier {
        let context = try ModelContext(makeContainer())
        let m = Meeting(startedAt: Date(), title: "view-mint")
        context.insert(m)
        try context.save()
        return m.persistentModelID
    }

    /// Builds a fixture ``MeetingSummary`` with known field values.
    private static func makeSummary(
        id: PersistentIdentifier,
        startedAt: Date,
        endedAt: Date?,
        title: String,
        sentenceCount: Int
    ) throws -> MeetingSummary {
        // Build via a real Meeting since MeetingSummary's only public
        // init is `init(from:)`. The Meeting itself isn't held; only
        // the projected struct is.
        let container = try makeContainer()
        let context = ModelContext(container)
        let m = Meeting(startedAt: startedAt, title: title)
        m.endedAt = endedAt
        context.insert(m)
        // Append sentenceCount placeholders so the summary's
        // sentenceCount matches the asserted value.
        for _ in 0 ..< sentenceCount {
            let s = Sentence(
                timestamp: startedAt,
                sourceLanguage: "ja",
                sourceText: "x",
                translatedText: "y",
                sourceSegmentID: UUID(),
                searchableText: "x y"
            )
            s.meeting = m
            context.insert(s)
        }
        try context.save()
        // Real summary projects field values from the Meeting; the
        // returned struct keeps its own copies and the in-memory
        // container can be released after this returns.
        let summary = MeetingSummary(from: m)
        _ = id // unused (the meeting's persistentModelID is its own)
        return summary
    }

    // MARK: - D11-T-view-1

    /// **D11-T-view-1** — When the VM has no sentences and no error,
    /// the view body branches into the empty-state placeholder. We
    /// assert the state predicate the view branches on rather than
    /// inspecting the rendered tree (ViewInspector is not in project).
    @Test func emptyState_rendersWhenNoSentences() async throws {
        let id = try Self.mintIdentifier()
        let summary = try Self.makeSummary(
            id: id,
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            endedAt: Date(timeIntervalSince1970: 1_700_001_000),
            title: "Empty meeting",
            sentenceCount: 0
        )
        let vm = MeetingDetailViewModel(meetingID: summary.id, fetcher: { _ in [] })
        await vm.reload()

        #expect(vm.sentences.isEmpty)
        #expect(vm.loadError == nil)

        // The view can be instantiated without throwing (smoke check
        // that the test-only init path is sound under the empty-state
        // branch).
        _ = MeetingDetailView(summary: summary, viewModel: vm)
    }

    // MARK: - D11-T-view-2

    /// **D11-T-view-2** — When the VM has at least one sentence,
    /// the view body branches into the sentence list. Asserts the
    /// state predicate and that view instantiation does not throw.
    @Test func populatedState_rendersWhenSentencesPresent() async throws {
        let id = try Self.mintIdentifier()
        let summary = try Self.makeSummary(
            id: id,
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            endedAt: Date(timeIntervalSince1970: 1_700_003_000),
            title: "Populated meeting",
            sentenceCount: 0
        )
        let projection = MeetingDetail.SentenceProjection(
            id: summary.id,
            timestamp: summary.startedAt.addingTimeInterval(1),
            sourceLanguage: "ja",
            sourceText: "こんにちは",
            translatedText: "Hello",
            sourceSegmentID: UUID()
        )
        let vm = MeetingDetailViewModel(meetingID: summary.id, fetcher: { _ in [projection] })
        await vm.reload()

        #expect(vm.sentences.count == 1)
        #expect(vm.loadError == nil)

        _ = MeetingDetailView(summary: summary, viewModel: vm)
    }

    // MARK: - D11-T-view-3

    /// **D11-T-view-3** — The view's header binds to the supplied
    /// ``MeetingSummary``'s fields. Verified indirectly by asserting the
    /// formatter outputs the view would render against the summary
    /// match the expected strings (byte-identical to the formatter's
    /// own output for the same `Date` values).
    @Test func init_summaryFieldsBindToHeader() throws {
        let id = try Self.mintIdentifier()
        let started = Date(timeIntervalSince1970: 1_700_000_000)
        let ended = started.addingTimeInterval(50 * 60)
        let summary = try Self.makeSummary(
            id: id,
            startedAt: started,
            endedAt: ended,
            title: "Header binding meeting",
            sentenceCount: 5
        )

        // The header would render:
        //   Title (via .navigationTitle)
        //   formattedDate(summary.startedAt) · formattedDuration(...)
        let expectedDate = MeetingDetailFormatter.formattedDate(summary.startedAt)
        let expectedDuration = MeetingDetailFormatter.formattedDuration(
            started: summary.startedAt,
            ended: summary.endedAt
        )

        // Locale-stable assertions — POSIX en-US ensures repeatability.
        let listFormatterDate = MeetingListRowFormatter.formattedDate(started)
        let listFormatterDuration = MeetingListRowFormatter.formattedDuration(
            startedAt: started,
            endedAt: ended
        )
        #expect(expectedDate == listFormatterDate)
        #expect(expectedDuration == listFormatterDuration)
        #expect(expectedDuration == "50 min")

        // Title round-trips through the summary unchanged.
        #expect(summary.title == "Header binding meeting")
    }
}

// MARK: - Test infrastructure

/// Two-shot dispatcher used by `D11-T-vm-1` to simulate a "slow first
/// call, fast second call" fetcher. Mirrors the pattern from
/// ``MeetingListViewTests``'s and ``TranscriptSplitScreenViewModelTests``'s
/// `FetcherDispatcher`.
///
/// `nonisolated` + `OSAllocatedUnfairLock` per the project's Swift 6
/// fake-state rules — `NSLock` is forbidden from async contexts.
private final nonisolated class ProjectionDispatcher: @unchecked Sendable {
    private let slow: [MeetingDetail.SentenceProjection]
    private let fast: [MeetingDetail.SentenceProjection]
    private let callCount = OSAllocatedUnfairLock<Int>(initialState: 0)

    init(
        slowResult: [MeetingDetail.SentenceProjection],
        fastResult: [MeetingDetail.SentenceProjection]
    ) {
        slow = slowResult
        fast = fastResult
    }

    /// Returns the fetcher closure to hand into
    /// ``MeetingDetailViewModel``. First invocation sleeps then returns
    /// `slow`; subsequent invocations return `fast` immediately.
    func makeFetcher() -> @MainActor (PersistentIdentifier) async throws -> [MeetingDetail.SentenceProjection] {
        { [self] _ in
            let isFirstCall = callCount.withLock { count -> Bool in
                count += 1
                return count == 1
            }
            if isFirstCall {
                // Cancellable sleep — the test cancels the spawning
                // task before this elapses, so the sleep throws
                // `CancellationError`. We never reach `return slow`;
                // the VM captures the error into `loadError` and
                // leaves `sentences` untouched on the first call.
                try await Task.sleep(nanoseconds: 200_000_000)
                return slow
            }
            return fast
        }
    }
}
