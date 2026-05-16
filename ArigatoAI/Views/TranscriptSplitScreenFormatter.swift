//
//  TranscriptSplitScreenFormatter.swift
//  ArigatoAI
//
//  Created by Jose Castell on 2026/05/16.
//

import Foundation

/// Pure-value formatter for ``TranscriptSplitScreenView``'s per-column
/// rows and timestamp annotations.
///
/// Extracted from the view body so the projection logic is testable
/// without the SwiftUI view tree — tests call these static functions
/// directly and assert against the row + timestamp strings the view will
/// display. Matches the Phase-2 trio pattern established by
/// ``MeetingListRowFormatter`` (Step 6) and the formatter enum inside
/// ``MeetingControlsView`` (Step 7).
///
/// ## Source/translated semantics (resolved 2026-05-16)
///
/// A ``MeetingDetail/SentenceProjection`` carries `sourceLanguage`
/// (`"ja"` or `"en"`), `sourceText` (the **original** language — whatever
/// the speaker actually said), and `translatedText` (the **opposite**
/// language — the translation output). Confirmed against
/// ``MeetingSession/persistCompleted(_:meetingID:)`` which calls
/// `appendSentence(sourceLanguage: translated.direction.source.rawValue,
/// sourceText: translated.sourceText, translatedText:
/// translated.translatedText, ...)` so `sourceText` is always the
/// original-language utterance.
///
/// Therefore:
/// - ``japaneseRow(for:)`` returns `sourceText` when
///   `sourceLanguage == "ja"`, otherwise `translatedText`.
/// - ``englishRow(for:)`` returns `sourceText` when
///   `sourceLanguage == "en"`, otherwise `translatedText`.
///
/// `nonisolated` because the formatter touches no actor state — pure
/// value-in, value-out projection callable from any context (test
/// suites running on any thread, view body running on the main actor).
nonisolated enum TranscriptSplitScreenFormatter {
    /// ISO 639-1 code for Japanese.
    static let japaneseTag = "ja"
    /// ISO 639-1 code for English.
    static let englishTag = "en"

    /// Projects a sentence to its Japanese-column display row.
    ///
    /// - Parameter sentence: The persisted projection.
    /// - Returns: The row's Japanese text, formatted timestamp, and
    ///   provenance (the original `sourceLanguage`).
    static func japaneseRow(for sentence: MeetingDetail.SentenceProjection) -> RowDisplay {
        let text = sentence.sourceLanguage == japaneseTag
            ? sentence.sourceText
            : sentence.translatedText
        return RowDisplay(
            text: text,
            timestamp: formatTimestamp(sentence.timestamp),
            sourceLanguage: sentence.sourceLanguage
        )
    }

    /// Projects a sentence to its English-column display row.
    ///
    /// - Parameter sentence: The persisted projection.
    /// - Returns: The row's English text, formatted timestamp, and
    ///   provenance (the original `sourceLanguage`).
    static func englishRow(for sentence: MeetingDetail.SentenceProjection) -> RowDisplay {
        let text = sentence.sourceLanguage == englishTag
            ? sentence.sourceText
            : sentence.translatedText
        return RowDisplay(
            text: text,
            timestamp: formatTimestamp(sentence.timestamp),
            sourceLanguage: sentence.sourceLanguage
        )
    }

    /// Formats a `Date` to a deterministic `HH:mm:ss` timestamp.
    ///
    /// Locale defaults to `en_US_POSIX` so the same `Date` produces the
    /// same string regardless of host locale — matches the
    /// determinism pattern from ``MeetingListRowFormatter/formattedDate(_:)``.
    /// The timestamp is rendered alongside per-row text in both columns
    /// so users can correlate sentence pairs across the JA/EN split per
    /// UI decision #1.
    ///
    /// - Parameters:
    ///   - date: Wall-clock time to render.
    ///   - locale: Locale used for formatting. Default
    ///     `en_US_POSIX` for deterministic test output.
    /// - Returns: A `HH:mm:ss` string in the supplied locale.
    static func formatTimestamp(
        _ date: Date,
        locale: Locale = Locale(identifier: "en_US_POSIX")
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
}

/// Pure-value rendering of a single split-screen row.
///
/// Returned by ``TranscriptSplitScreenFormatter/japaneseRow(for:)`` and
/// ``TranscriptSplitScreenFormatter/englishRow(for:)``. Sendable +
/// Equatable so tests can compare full row payloads and so the value
/// flows safely through SwiftUI's render graph.
nonisolated struct RowDisplay: Equatable {
    /// The text to display in the column. Either `sourceText` or
    /// `translatedText` depending on which column the row belongs to
    /// and which language the speaker used (see formatter doc-comment
    /// for the full table).
    let text: String

    /// Pre-formatted timestamp string for the per-row annotation.
    let timestamp: String

    /// The original `sourceLanguage` of the underlying sentence
    /// (`"ja"` or `"en"`). Carried through so the row can render
    /// provenance affordances (e.g., a subtle indicator that this row
    /// is the translation, not the original utterance) without
    /// re-deriving from the projection.
    let sourceLanguage: String
}
