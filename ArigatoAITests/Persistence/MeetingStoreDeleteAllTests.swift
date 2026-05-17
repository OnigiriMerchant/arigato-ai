//
//  MeetingStoreDeleteAllTests.swift
//  ArigatoAITests
//
//  Created by Jose Castell on 2026/05/17.
//

@testable import ArigatoAI
import Foundation
import SwiftData
import Testing

/// Step 15 — tests for ``MeetingStore/deleteAllMeetings()``.
///
/// Each test builds an in-memory `ModelContainer` so they run fast and
/// leave no on-disk artifacts. The actor's saves are verified against a
/// **fresh** `ModelContext` constructed from the same container, so the
/// assertions confirm durability of the actor's `save()` rather than
/// mere visibility inside the actor's own context.
///
/// Mirrors the ``MeetingStoreTests`` helper pattern.
@Suite("MeetingStore.deleteAllMeetings")
@MainActor
struct MeetingStoreDeleteAllTests {
    private static func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: Meeting.self, Sentence.self,
            configurations: config
        )
    }

    /// Seeds 3 meetings, calls ``MeetingStore/deleteAllMeetings()``,
    /// asserts the returned count is 3 and that
    /// ``MeetingStore/fetchAllUnfiltered()`` returns an empty array.
    /// Verified against a fresh `ModelContext` to prove durability.
    @Test
    func deleteAllMeetings_returnsCount_removesAllRows() async throws {
        let container = try Self.makeContainer()
        let store = MeetingStore(modelContainer: container)

        for index in 0 ..< 3 {
            _ = try await store.startMeeting(
                startedAt: Date(timeIntervalSince1970: 1_700_000_000 + Double(index)),
                title: "Meeting \(index)"
            )
        }

        let count = try await store.deleteAllMeetings()
        #expect(count == 3)

        // Actor-level: fetchAllUnfiltered should now be empty.
        let remaining = try await store.fetchAllUnfiltered()
        #expect(remaining.isEmpty)

        // Durability: fresh context against the same container also
        // sees zero rows.
        let context = ModelContext(container)
        let onDisk = try context.fetch(FetchDescriptor<Meeting>())
        #expect(onDisk.isEmpty)
    }

    /// Seeds 2 meetings with multiple sentences each, calls
    /// ``MeetingStore/deleteAllMeetings()``, then asserts a fresh
    /// `Sentence` fetch returns empty — verifying the
    /// `@Relationship(deleteRule: .cascade)` declared on
    /// ``Meeting/sentences`` (Step 1) actually fires.
    @Test
    func deleteAllMeetings_cascadesToSentences_freshFetchReturnsEmpty() async throws {
        let container = try Self.makeContainer()
        let store = MeetingStore(modelContainer: container)

        let firstID = try await store.startMeeting(
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            title: "First"
        )
        let secondID = try await store.startMeeting(
            startedAt: Date(timeIntervalSince1970: 1_700_000_100),
            title: "Second"
        )

        for parentID in [firstID, secondID] {
            for sentenceIndex in 0 ..< 2 {
                try await store.appendSentence(
                    meetingID: parentID,
                    timestamp: Date(timeIntervalSince1970: 1_700_000_010 + Double(sentenceIndex)),
                    sourceLanguage: "en",
                    sourceText: "Source \(sentenceIndex)",
                    translatedText: "Translation \(sentenceIndex)",
                    sourceSegmentID: UUID()
                )
            }
        }

        // Sanity: 4 sentences on disk before delete.
        do {
            let context = ModelContext(container)
            let sentencesBefore = try context.fetch(FetchDescriptor<Sentence>())
            #expect(sentencesBefore.count == 4)
        }

        let count = try await store.deleteAllMeetings()
        #expect(count == 2)

        // Cascade check: fresh fetch of Sentence direct (not via Meeting
        // navigation) returns empty. This is the contract documented on
        // ``MeetingStore/deleteAllMeetings()``.
        let context = ModelContext(container)
        let sentencesAfter = try context.fetch(FetchDescriptor<Sentence>())
        #expect(sentencesAfter.isEmpty)
    }
}
