//
//  MeetingEntityTests.swift
//  ArigatoAITests
//
//  Created by Jose Castell on 2026/05/16.
//

@testable import ArigatoAI
import Foundation
import SwiftData
import Testing

/// Tests for the ``Meeting`` + ``Sentence`` SwiftData entities locked
/// by Group D UI decision #20, with Amendment 4 regression coverage
/// for the cascade-delete failure mode documented in
/// Apple Developer Forums 740649 / FB13640004.
///
/// All tests use an in-memory `ModelContainer` so they run fast and
/// leave no on-disk artifacts.
struct MeetingEntityTests {
    /// Builds an in-memory container + context fresh for each test.
    /// Marked `throws` so configuration / container failures surface
    /// as Swift Testing errors rather than crashes.
    private static func makeContainer() throws -> (ModelContainer, ModelContext) {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Meeting.self, Sentence.self,
            configurations: config
        )
        let context = ModelContext(container)
        return (container, context)
    }

    /// Happy-path insert + fetch. Confirms the initializers, the
    /// `@Relationship` wiring, and that the inverse `Sentence.meeting`
    /// is populated when a sentence is attached via `Meeting.sentences`.
    @Test func meeting_initWithDefaults_persists() throws {
        let (_, context) = try Self.makeContainer()

        let sentence = Sentence(
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            sourceLanguage: "ja",
            sourceText: "こんにちは",
            translatedText: "Hello",
            sourceSegmentID: UUID(),
            searchableText: SearchTextNormalizer.normalize("こんにちは Hello")
        )
        let meeting = Meeting(
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            title: "Test meeting",
            sentences: [sentence]
        )
        context.insert(meeting)
        try context.save()

        let meetings = try context.fetch(FetchDescriptor<Meeting>())
        let sentences = try context.fetch(FetchDescriptor<Sentence>())

        #expect(meetings.count == 1)
        #expect(sentences.count == 1)
        #expect(meetings.first?.sentences.count == 1)
        #expect(sentences.first?.meeting?.title == "Test meeting")
    }

    /// Cascade delete happy path: single `save()` after `delete(meeting)`.
    /// WWDC23 session 10195 implies this is the supported pattern.
    @Test func cascadeDelete_singleSave_removesOrphanSentences() throws {
        let (_, context) = try Self.makeContainer()

        let meeting = Meeting(
            startedAt: Date(),
            title: "Cascade-target"
        )
        context.insert(meeting)
        for i in 0 ..< 3 {
            let s = Sentence(
                timestamp: Date(),
                sourceLanguage: "ja",
                sourceText: "s\(i)",
                translatedText: "t\(i)",
                sourceSegmentID: UUID(),
                searchableText: "s\(i) t\(i)"
            )
            // Attach via the parent-side relationship — this is the
            // documented insert path; the inverse `meeting` property
            // is populated automatically.
            meeting.sentences.append(s)
        }
        try context.save()

        #expect(try context.fetch(FetchDescriptor<Meeting>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<Sentence>()).count == 3)

        context.delete(meeting)
        try context.save()

        #expect(try context.fetch(FetchDescriptor<Meeting>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<Sentence>()).isEmpty)
    }

    /// Regression coverage for **FB13640004 / Apple Developer Forums 740649**:
    /// cascade delete after an explicit pre-delete `save()` historically
    /// left orphan sentences. Apple has not published a fix; iOS 26
    /// appears to behave correctly, but this test pins the contract so
    /// that if Apple re-introduces the bug we catch it locally before
    /// it ships in any build of Arigato AI.
    ///
    /// Pattern: insert meeting + 3 sentences, `save()` (FIRST save —
    /// the trigger), then `delete(meeting)`, `save()` (SECOND save).
    /// The expectation is identical to the single-save case:
    /// zero orphan sentences.
    @Test func cascadeDelete_afterExplicitPreDeleteSave_stillRemovesOrphanSentences() throws {
        let (_, context) = try Self.makeContainer()

        let meeting = Meeting(
            startedAt: Date(),
            title: "FB13640004 regression"
        )
        context.insert(meeting)
        for i in 0 ..< 3 {
            let s = Sentence(
                timestamp: Date(),
                sourceLanguage: "en",
                sourceText: "src\(i)",
                translatedText: "翻訳\(i)",
                sourceSegmentID: UUID(),
                searchableText: "src\(i) 翻訳\(i)"
            )
            meeting.sentences.append(s)
        }
        // FIRST save — the trigger for the FB13640004 failure mode.
        try context.save()

        #expect(try context.fetch(FetchDescriptor<Sentence>()).count == 3)

        context.delete(meeting)
        // SECOND save — under FB13640004 this would leave the 3
        // sentences orphaned. The assertion below catches regression.
        try context.save()

        let orphanedCount = try context.fetch(FetchDescriptor<Sentence>()).count
        #expect(orphanedCount == 0,
                "FB13640004 cascade-delete regression: sentences not removed after explicit pre-delete save")
    }
}
