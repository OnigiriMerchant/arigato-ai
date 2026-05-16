//
//  MeetingStoreTests.swift
//  ArigatoAITests
//
//  Created by Jose Castell on 2026/05/16.
//

@testable import ArigatoAI
import Foundation
import SwiftData
import Testing

/// Tests for ``MeetingStore`` — the first `@ModelActor` in the project.
///
/// Each test builds an in-memory `ModelContainer` so they run fast and
/// leave no on-disk artifacts. The actor's saves are verified against
/// a **fresh** `ModelContext` constructed from the same container, so
/// the assertions confirm durability of the actor's `save()` rather
/// than mere visibility inside the actor's own context.
///
/// Marked `@MainActor` to match the project convention
/// (`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`) and so that the
/// suite can safely call main-actor-isolated helpers like
/// ``SearchTextNormalizer/normalize(_:)`` between `await` calls on
/// the actor under test.
@Suite("MeetingStore")
@MainActor
struct MeetingStoreTests {
    /// Builds an in-memory container fresh for each test.
    private static func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: Meeting.self, Sentence.self,
            configurations: config
        )
    }

    /// `startMeeting` inserts a `Meeting` row and returns its
    /// persistent identifier. Verified against a fresh `ModelContext`
    /// to confirm the actor's `save()` is durable.
    @Test func startMeeting_returnsPersistentIdentifier() async throws {
        let container = try Self.makeContainer()
        let store = MeetingStore(modelContainer: container)

        let id = try await store.startMeeting(
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            title: "Kickoff"
        )

        // Fresh context against the same container — proves the row
        // landed on the persistent store, not just the actor's context.
        let context = ModelContext(container)
        let meetings = try context.fetch(FetchDescriptor<Meeting>())
        #expect(meetings.count == 1)
        #expect(meetings.first?.persistentModelID == id)
        #expect(meetings.first?.title == "Kickoff")
    }

    /// `appendSentence` must populate `searchableText` via
    /// ``SearchTextNormalizer/normalize(_:)`` over the concatenated
    /// source + translation text. This is the Amendment 1 contract.
    @Test func appendSentence_populatesSearchableText() async throws {
        let container = try Self.makeContainer()
        let store = MeetingStore(modelContainer: container)

        let meetingID = try await store.startMeeting(
            startedAt: Date(),
            title: "Search-field test"
        )

        let source = "こんにちは、Tanaka-san"
        let translation = "Hello, Mr. Tanaka"
        try await store.appendSentence(
            meetingID: meetingID,
            timestamp: Date(),
            sourceLanguage: "ja",
            sourceText: source,
            translatedText: translation,
            sourceSegmentID: UUID()
        )

        let context = ModelContext(container)
        let sentences = try context.fetch(FetchDescriptor<Sentence>())
        #expect(sentences.count == 1)
        let expected = SearchTextNormalizer.normalize(source + " " + translation)
        #expect(sentences.first?.searchableText == expected)
        #expect(sentences.first?.searchableText.isEmpty == false)
    }

    /// `appendSentence` against a deleted meeting must throw
    /// ``MeetingStoreError/meetingNotFound(_:)``. The test path uses a
    /// real-but-stale `PersistentIdentifier` — start a meeting, capture
    /// its id, delete it, then call `appendSentence`. We do not
    /// fabricate identifiers because `PersistentIdentifier`'s internals
    /// are not public.
    @Test func appendSentence_meetingNotFound_throwsMeetingStoreError() async throws {
        let container = try Self.makeContainer()
        let store = MeetingStore(modelContainer: container)

        let meetingID = try await store.startMeeting(
            startedAt: Date(),
            title: "Doomed"
        )
        try await store.deleteMeeting(meetingID: meetingID)

        await #expect(throws: MeetingStoreError.meetingNotFound(meetingID)) {
            try await store.appendSentence(
                meetingID: meetingID,
                timestamp: Date(),
                sourceLanguage: "en",
                sourceText: "won't land",
                translatedText: "届かない",
                sourceSegmentID: UUID()
            )
        }
    }

    /// `endMeeting` sets `endedAt` to the value passed in and saves.
    @Test func endMeeting_setsEndedAt() async throws {
        let container = try Self.makeContainer()
        let store = MeetingStore(modelContainer: container)

        let startedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let endedAt = Date(timeIntervalSince1970: 1_700_003_600)
        let meetingID = try await store.startMeeting(
            startedAt: startedAt,
            title: "Bounded meeting"
        )

        try await store.endMeeting(meetingID: meetingID, endedAt: endedAt)

        let context = ModelContext(container)
        let meetings = try context.fetch(FetchDescriptor<Meeting>())
        #expect(meetings.count == 1)
        #expect(meetings.first?.endedAt == endedAt)
    }

    /// `updateTitle` rewrites the existing meeting's title and saves.
    /// Verified against a fresh `ModelContext` so we confirm the
    /// actor's `save()` is durable rather than only context-visible.
    @Test func updateTitle_existingMeeting_persistsNewTitle() async throws {
        let container = try Self.makeContainer()
        let store = MeetingStore(modelContainer: container)

        let meetingID = try await store.startMeeting(
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            title: "Placeholder"
        )

        try await store.updateTitle(meetingID: meetingID, title: "Renamed kickoff")

        let context = ModelContext(container)
        let meetings = try context.fetch(FetchDescriptor<Meeting>())
        #expect(meetings.count == 1)
        #expect(meetings.first?.title == "Renamed kickoff")
    }

    /// `updateTitle` against a deleted meeting must throw
    /// ``MeetingStoreError/meetingNotFound(_:)``. Mirrors the stale-ID
    /// pattern from
    /// ``appendSentence_meetingNotFound_throwsMeetingStoreError`` —
    /// start a meeting, capture its id, delete it, then call
    /// `updateTitle`. We do not fabricate identifiers because
    /// `PersistentIdentifier`'s internals are not public.
    @Test func updateTitle_meetingNotFound_throwsMeetingStoreError() async throws {
        let container = try Self.makeContainer()
        let store = MeetingStore(modelContainer: container)

        let meetingID = try await store.startMeeting(
            startedAt: Date(),
            title: "Doomed"
        )
        try await store.deleteMeeting(meetingID: meetingID)

        await #expect(throws: MeetingStoreError.meetingNotFound(meetingID)) {
            try await store.updateTitle(meetingID: meetingID, title: "won't land")
        }
    }

    /// `deleteMeeting` cascades through the `@Relationship(deleteRule:
    /// .cascade)` declared on `Meeting.sentences`. The cascade is
    /// already covered at the unit-entity level in
    /// `MeetingEntityTests.cascadeDelete_singleSave_removesOrphanSentences`;
    /// this test confirms the same contract holds when the writes go
    /// through the actor's save path.
    @Test func deleteMeeting_cascadesSentences() async throws {
        let container = try Self.makeContainer()
        let store = MeetingStore(modelContainer: container)

        let meetingID = try await store.startMeeting(
            startedAt: Date(),
            title: "Cascade-through-actor"
        )
        for i in 0 ..< 3 {
            try await store.appendSentence(
                meetingID: meetingID,
                timestamp: Date(),
                sourceLanguage: "ja",
                sourceText: "src\(i)",
                translatedText: "tr\(i)",
                sourceSegmentID: UUID()
            )
        }

        // Pre-delete sanity.
        let preContext = ModelContext(container)
        #expect(try preContext.fetch(FetchDescriptor<Sentence>()).count == 3)

        try await store.deleteMeeting(meetingID: meetingID)

        let postContext = ModelContext(container)
        #expect(try postContext.fetch(FetchDescriptor<Meeting>()).isEmpty)
        #expect(try postContext.fetch(FetchDescriptor<Sentence>()).isEmpty)
    }

    /// **D6-T-8** — `fetchAllUnfiltered` returns an empty array when no
    /// meetings exist in the store. Step 6's MeetingListView empty-state
    /// branch keys off this contract (model.meetings.isEmpty +
    /// loadError == nil).
    @Test func meetingStoreTests_fetchAllUnfiltered_returnsEmptyArrayWhenNoMeetings() async throws {
        let container = try Self.makeContainer()
        let store = MeetingStore(modelContainer: container)

        let summaries = try await store.fetchAllUnfiltered()

        #expect(summaries.isEmpty)
    }

    /// **D6-T-9** — `fetchAllUnfiltered` returns all meetings sorted
    /// **newest-first** by ``Meeting/startedAt``. Insert order is
    /// intentionally NOT chronological so the assertion proves the sort
    /// is the descriptor's, not the insertion order's. UI decision #13
    /// pins newest-first as the history view contract.
    @Test func meetingStoreTests_fetchAllUnfiltered_returnsAllMeetingsNewestFirst() async throws {
        let container = try Self.makeContainer()
        let store = MeetingStore(modelContainer: container)

        // Three meetings inserted out of order.
        let middle = Date(timeIntervalSince1970: 1_700_001_000)
        let oldest = Date(timeIntervalSince1970: 1_700_000_000)
        let newest = Date(timeIntervalSince1970: 1_700_002_000)

        _ = try await store.startMeeting(startedAt: middle, title: "Middle")
        _ = try await store.startMeeting(startedAt: oldest, title: "Oldest")
        _ = try await store.startMeeting(startedAt: newest, title: "Newest")

        let summaries = try await store.fetchAllUnfiltered()

        #expect(summaries.count == 3)
        #expect(summaries.map(\.title) == ["Newest", "Middle", "Oldest"])
        #expect(summaries.map(\.startedAt) == [newest, middle, oldest])
    }

    // MARK: - fetchSentences (Step 9a)

    /// **D9a-T-store-1** — `fetchSentences` for a meeting with no
    /// sentences returns an empty array (NOT throw). The empty-array
    /// contract matches ``fetchAllUnfiltered`` and supports
    /// ``TranscriptSplitScreenViewModel/reload()`` treating absence as
    /// "nothing to display yet."
    @Test func fetchSentences_meetingWithNoSentences_returnsEmptyArray() async throws {
        let container = try Self.makeContainer()
        let store = MeetingStore(modelContainer: container)

        let meetingID = try await store.startMeeting(
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            title: "Empty"
        )

        let sentences = try await store.fetchSentences(meetingID: meetingID)
        #expect(sentences.isEmpty)
    }

    /// **D9a-T-store-2** — `fetchSentences` returns every sentence in the
    /// meeting, **oldest-first** by `timestamp`. Inserted out of
    /// chronological order so the assertion proves the sort is the
    /// descriptor's, not the insertion order's. Step 9a's split-screen
    /// UI relies on the ascending order to render top-down chronological
    /// rows under the auto-follow contract (UI decision #2).
    @Test func fetchSentences_meetingWithSentences_returnsAllInTimestampOrder() async throws {
        let container = try Self.makeContainer()
        let store = MeetingStore(modelContainer: container)

        let meetingID = try await store.startMeeting(
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            title: "Ordered"
        )

        // Three sentences inserted out of timestamp order so the
        // assertion proves the descriptor sorted them, not insertion
        // order.
        let middle = Date(timeIntervalSince1970: 1_700_000_010)
        let oldest = Date(timeIntervalSince1970: 1_700_000_000)
        let newest = Date(timeIntervalSince1970: 1_700_000_020)

        try await store.appendSentence(
            meetingID: meetingID,
            timestamp: middle,
            sourceLanguage: "ja",
            sourceText: "middle source",
            translatedText: "middle translated",
            sourceSegmentID: UUID()
        )
        try await store.appendSentence(
            meetingID: meetingID,
            timestamp: oldest,
            sourceLanguage: "en",
            sourceText: "oldest source",
            translatedText: "oldest translated",
            sourceSegmentID: UUID()
        )
        try await store.appendSentence(
            meetingID: meetingID,
            timestamp: newest,
            sourceLanguage: "ja",
            sourceText: "newest source",
            translatedText: "newest translated",
            sourceSegmentID: UUID()
        )

        let sentences = try await store.fetchSentences(meetingID: meetingID)
        #expect(sentences.count == 3)
        #expect(sentences.map(\.timestamp) == [oldest, middle, newest])
        #expect(sentences.map(\.sourceText) == ["oldest source", "middle source", "newest source"])
    }

    /// **D9a-T-store-3** — `fetchSentences` against a deleted meeting
    /// (stale `PersistentIdentifier`) returns an **empty array** rather
    /// than throwing `meetingNotFound`. The read-path contract is
    /// distinct from the write-path contract (`appendSentence`,
    /// `updateTitle`, `endMeeting`, `deleteMeeting` all throw on stale
    /// IDs). The doc-comment on ``MeetingStore/fetchSentences(meetingID:)``
    /// documents this divergence.
    @Test func fetchSentences_nonexistentMeetingID_returnsEmptyArray() async throws {
        let container = try Self.makeContainer()
        let store = MeetingStore(modelContainer: container)

        // Real-but-stale identifier — start, capture id, delete. We
        // cannot fabricate `PersistentIdentifier` values because the
        // initializer is not public.
        let meetingID = try await store.startMeeting(
            startedAt: Date(),
            title: "Doomed"
        )
        try await store.deleteMeeting(meetingID: meetingID)

        let sentences = try await store.fetchSentences(meetingID: meetingID)
        #expect(sentences.isEmpty)
    }

    /// **Concurrency violation test (per CLAUDE.md "Concurrency design
    /// discipline").** The doc-comment on ``MeetingStore`` declares the
    /// scheduling assumption that the actor serializes its work on its
    /// own executor. This test violates the assumption by firing 50
    /// concurrent `appendSentence` calls via `withTaskGroup` against
    /// the same meeting. Actor isolation must serialize them
    /// automatically — the floor-test is: all 50 sentences land, with
    /// 50 distinct `sourceSegmentID` values and no duplicates.
    ///
    /// If this test fails, the `@ModelActor` pattern itself is broken
    /// in the toolchain — not a regression in our code.
    @Test func appendSentence_concurrentCallsSerializeCleanly() async throws {
        let container = try Self.makeContainer()
        let store = MeetingStore(modelContainer: container)

        let meetingID = try await store.startMeeting(
            startedAt: Date(),
            title: "Greedy producer"
        )

        // Pre-generate 50 distinct segment IDs so we can detect drops
        // or duplicates after the fact.
        let segmentIDs: [UUID] = (0 ..< 50).map { _ in UUID() }

        try await withThrowingTaskGroup(of: Void.self) { group in
            for segID in segmentIDs {
                group.addTask {
                    try await store.appendSentence(
                        meetingID: meetingID,
                        timestamp: Date(),
                        sourceLanguage: "ja",
                        sourceText: "burst",
                        translatedText: "burst-tr",
                        sourceSegmentID: segID
                    )
                }
            }
            try await group.waitForAll()
        }

        let context = ModelContext(container)
        let sentences = try context.fetch(FetchDescriptor<Sentence>())
        #expect(sentences.count == 50)

        let landedIDs = Set(sentences.map(\.sourceSegmentID))
        #expect(landedIDs.count == 50, "Duplicate or dropped segment IDs after concurrent burst")
        #expect(landedIDs == Set(segmentIDs), "Landed IDs do not match dispatched IDs")
    }
}
