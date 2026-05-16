//
//  TranscriptSplitScreenFormatterTests.swift
//  ArigatoAITests
//
//  Created by Jose Castell on 2026/05/16.
//

@testable import ArigatoAI
import Foundation
import SwiftData
import Testing

/// Tests for ``TranscriptSplitScreenFormatter`` — the pure-value formatter
/// extracted from ``TranscriptSplitScreenView``'s body per the Phase-2
/// trio pattern.
///
/// All tests exercise the static functions directly. No SwiftUI runtime
/// required; mirrors the testing approach used by
/// ``MeetingListRowFormatter`` (Step 6) and the formatter enum inside
/// ``MeetingControlsView`` (Step 7).
///
/// Marked `@MainActor` for project convention parity — the formatter
/// itself is `nonisolated`, so calls are legal from any context.
@Suite("TranscriptSplitScreenFormatter")
@MainActor
struct TranscriptSplitScreenFormatterTests {
    // MARK: - Helpers

    private static func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: Meeting.self, Sentence.self,
            configurations: config
        )
    }

    /// Mints a real `PersistentIdentifier` because `PersistentIdentifier`
    /// has no public initializer — we have to round-trip through a
    /// real (in-memory) SwiftData insert.
    private static func mintIdentifier() throws -> PersistentIdentifier {
        let container = try makeContainer()
        let context = ModelContext(container)
        let m = Meeting(startedAt: Date(), title: "fmt-id-mint")
        context.insert(m)
        try context.save()
        return m.persistentModelID
    }

    private static func makeProjection(
        id: PersistentIdentifier,
        timestamp: Date = Date(),
        sourceLanguage: String,
        sourceText: String,
        translatedText: String
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

    // MARK: - japaneseRow projection

    /// **D9a-T-fmt-1** — A Japanese-source sentence (`sourceLanguage ==
    /// "ja"`) renders `sourceText` in the Japanese column. The
    /// `sourceText` field carries the original utterance; for a Japanese
    /// speaker, that field IS Japanese. Verified against
    /// `MeetingSession.persistCompleted` which writes
    /// `sourceLanguage = direction.source.rawValue` and `sourceText =
    /// translated.sourceText` — so when direction's source is `.ja`,
    /// `sourceText` is Japanese.
    @Test func formatter_japaneseRow_forJapaneseSourceSentence_returnsSourceText() throws {
        let id = try Self.mintIdentifier()
        let projection = Self.makeProjection(
            id: id,
            sourceLanguage: "ja",
            sourceText: "こんにちは",
            translatedText: "Hello"
        )

        let row = TranscriptSplitScreenFormatter.japaneseRow(for: projection)

        #expect(row.text == "こんにちは",
                "Japanese-source sentence → JA column renders sourceText (the original).")
        #expect(row.sourceLanguage == "ja")
    }

    /// **D9a-T-fmt-2** — An English-source sentence (`sourceLanguage ==
    /// "en"`) renders `translatedText` in the Japanese column — the
    /// translation IS the Japanese rendering of the English utterance.
    @Test func formatter_japaneseRow_forEnglishSourceSentence_returnsTranslatedText() throws {
        let id = try Self.mintIdentifier()
        let projection = Self.makeProjection(
            id: id,
            sourceLanguage: "en",
            sourceText: "Hello, everyone.",
            translatedText: "皆さん、こんにちは。"
        )

        let row = TranscriptSplitScreenFormatter.japaneseRow(for: projection)

        #expect(row.text == "皆さん、こんにちは。",
                "English-source sentence → JA column renders translatedText (the JA rendering).")
        #expect(row.sourceLanguage == "en")
    }

    // MARK: - englishRow projection

    /// **D9a-T-fmt-3** — A Japanese-source sentence renders
    /// `translatedText` in the English column — the translation IS the
    /// English rendering of the Japanese utterance.
    @Test func formatter_englishRow_forJapaneseSourceSentence_returnsTranslatedText() throws {
        let id = try Self.mintIdentifier()
        let projection = Self.makeProjection(
            id: id,
            sourceLanguage: "ja",
            sourceText: "こんにちは",
            translatedText: "Hello"
        )

        let row = TranscriptSplitScreenFormatter.englishRow(for: projection)

        #expect(row.text == "Hello",
                "Japanese-source sentence → EN column renders translatedText (the EN rendering).")
        #expect(row.sourceLanguage == "ja")
    }

    /// **D9a-T-fmt-4** — An English-source sentence renders `sourceText`
    /// in the English column — the original utterance IS English.
    @Test func formatter_englishRow_forEnglishSourceSentence_returnsSourceText() throws {
        let id = try Self.mintIdentifier()
        let projection = Self.makeProjection(
            id: id,
            sourceLanguage: "en",
            sourceText: "Hello, everyone.",
            translatedText: "皆さん、こんにちは。"
        )

        let row = TranscriptSplitScreenFormatter.englishRow(for: projection)

        #expect(row.text == "Hello, everyone.",
                "English-source sentence → EN column renders sourceText (the original).")
        #expect(row.sourceLanguage == "en")
    }

    // MARK: - Timestamp formatting

    /// **D9a-T-fmt-5** — Timestamp formatting must be deterministic
    /// across host locales. Default locale is `en_US_POSIX`. The
    /// expected output for a fixed `Date` is checked against a manually
    /// constructed `DateFormatter` so the test is locale-independent.
    @Test func formatter_formatTimestamp_returnsLocaleDeterministicFormat() {
        // Fixed epoch — 2026-05-16 22:22:33 UTC. The exact rendered
        // hour depends on the host timezone (POSIX locale honors it),
        // so verify against a reference formatter rather than a hardcoded
        // string.
        let fixed = Date(timeIntervalSince1970: 1_779_236_553)

        let rendered = TranscriptSplitScreenFormatter.formatTimestamp(fixed)

        let reference = DateFormatter()
        reference.locale = Locale(identifier: "en_US_POSIX")
        reference.dateFormat = "HH:mm:ss"
        #expect(rendered == reference.string(from: fixed))

        // Cross-locale invariance: en-US locale call should not produce
        // a different string from en_US_POSIX for HH:mm:ss (the format
        // string is locale-independent for these tokens).
        let crossLocale = TranscriptSplitScreenFormatter.formatTimestamp(
            fixed,
            locale: Locale(identifier: "ja_JP")
        )
        // HH:mm:ss is digit-only; ja_JP must produce identical output.
        #expect(crossLocale == rendered)
    }
}
