//
//  DebugMeetingSeederTests.swift
//  ArigatoAITests
//
//  Created by Jose Castell on 2026/05/30.
//

#if DEBUG
    @testable import ArigatoAI
    import Foundation
    import SwiftData
    import Testing

    /// Behavioral test for the DEBUG-only ``DebugMeetingSeeder``.
    ///
    /// Verifies the seeder inserts the expected number of meetings and that
    /// its data is reachable through the production read + search path — i.e.
    /// that it routed every line through
    /// ``MeetingStore/appendSentence(meetingID:timestamp:sourceLanguage:sourceText:translatedText:sourceSegmentID:)``
    /// so that ``Sentence/searchableText`` was normalized exactly as a
    /// production sentence would be. A body-match search (including a pure
    /// hiragana needle) is the proof: it can only succeed if the seeder's
    /// text went through ``SearchTextNormalizer/normalize(_:)`` at insert time.
    ///
    /// The in-memory `ModelContainer` idiom is the same one
    /// ``MeetingStoreTests`` uses (in-memory config + `MeetingStore`
    /// constructed from that container) so the test runs fast and leaves no
    /// on-disk artifacts.
    ///
    /// The entire file is `#if DEBUG` because ``DebugMeetingSeeder`` itself
    /// is compiled only under DEBUG.
    @Suite("DebugMeetingSeeder")
    @MainActor
    struct DebugMeetingSeederTests {
        /// Builds an in-memory container fresh for each test — mirrors
        /// ``MeetingStoreTests``' helper so seeding hits the same persistence
        /// shape production does.
        private static func makeContainer() throws -> ModelContainer {
            let config = ModelConfiguration(isStoredInMemoryOnly: true)
            return try ModelContainer(
                for: Meeting.self, Sentence.self,
                configurations: config
            )
        }

        /// Seeding inserts exactly the three Decision-B sample meetings, and
        /// their sentence text is reachable through the production
        /// `fetchAll(searchText:)` body-match path — proving every line was
        /// inserted via `appendSentence` (the only path that normalizes
        /// `searchableText`).
        ///
        /// Three needles are drawn **verbatim** from
        /// ``DebugMeetingSeeder/samples``:
        /// - an English body needle present in a sentence's text,
        /// - a Japanese hiragana needle (exercises the hiragana→katakana
        ///   folding branch of ``SearchTextNormalizer``),
        /// - a Japanese needle bearing kanji + kana from the partnership
        ///   meeting.
        @Test func seed_insertsThreeMeetings_andSearchableTextIsPopulated() async throws {
            let container = try Self.makeContainer()
            let store = MeetingStore(modelContainer: container)

            try await DebugMeetingSeeder.seed(into: store)

            // (1) Exactly three meetings landed.
            let all = try await store.fetchAll(searchText: "")
            #expect(all.count == 3)

            // (2a) English body needle drawn verbatim from M3's
            // "The crash rate stayed well under our target." — matches only
            // if the seeder routed the line through `appendSentence`, which
            // normalizes `searchableText`.
            let englishMatches = try await store.fetchAll(searchText: "crash rate")
            #expect(englishMatches.count >= 1)

            // (2b) Pure-hiragana needle drawn verbatim from M3's opening
            // line ("皆さん、おはようございます。…"). Proves the
            // hiragana→katakana folding path is genuinely exercised: the
            // stored `searchableText` and the folded query both transform to
            // katakana, so the substring matches across the script boundary.
            let hiraganaMatches = try await store.fetchAll(searchText: "おはようございます")
            #expect(hiraganaMatches.count >= 1)

            // (2c) Kanji+kana needle drawn verbatim from M2
            // ("第3四半期の売上は、前年同期比で12パーセント増加いたしました。").
            let japaneseMatches = try await store.fetchAll(searchText: "前年同期比")
            #expect(japaneseMatches.count >= 1)
        }
    }
#endif
