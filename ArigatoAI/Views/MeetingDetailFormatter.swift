//
//  MeetingDetailFormatter.swift
//  ArigatoAI
//
//  Created by Jose Castell on 2026/05/16.
//

import Foundation

/// Pure-value formatter for ``MeetingDetailView``'s header (date +
/// duration) and per-sentence body rows.
///
/// ## Isolation
///
/// `@MainActor`-isolated. The project sets
/// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, which makes
/// ``MeetingListRowFormatter`` (Step 6) implicitly main-actor. Because
/// this formatter delegates synchronously to ``MeetingListRowFormatter``
/// for ``formattedDate(_:)`` and ``formattedDuration(started:ended:)``
/// (UI decision #15 byte-identity — see the rationale below), the
/// enclosing enum inherits the same isolation. ``RowBody`` is
/// `nonisolated` and remains so — it's a plain Sendable value type.
/// Tests run on `@MainActor` (matching the project convention for
/// other Phase-2 trio formatters) so the delegation chain works
/// uniformly.
///
/// ## Delegation rationale (UI decision #15 byte-identity)
///
/// History list rows (Step 6 — ``MeetingListRowFormatter``), the live
/// transcript split-screen (Step 9a — ``TranscriptSplitScreenFormatter``),
/// and this detail-view formatter all render the SAME piece of meeting
/// metadata (start date) and the SAME per-sentence timestamps. To
/// guarantee byte-identical output across list / live / detail surfaces
/// per UI decision #15, this enum **delegates** to the existing
/// formatters rather than duplicating their `DateFormatter`
/// configuration:
///
/// - ``formattedDate(_:)`` → ``MeetingListRowFormatter/formattedDate(_:)``
/// - ``formattedDuration(started:ended:)`` → ``MeetingListRowFormatter/formattedDuration(startedAt:endedAt:)``
/// - ``formatTimestamp(_:)`` → ``TranscriptSplitScreenFormatter/formatTimestamp(_:locale:)``
///
/// Tests assert the byte-identity contract directly (see
/// `D11-T-fmt-1-formattedDate_matchesMeetingListRowFormatter`).
///
/// ## Source-led semantics (Phase 7 Decision 6)
///
/// A ``MeetingDetail/SentenceProjection`` carries `sourceLanguage`
/// (`"ja"` or `"en"`), a `sourceText` that is always the **original
/// spoken** utterance, and a `translatedText` that is its rendering in
/// the other language. ``sentenceBody(for:)`` projects the row
/// **source-led**: the spoken-language text leads (``RowBody/source``),
/// the translation follows (``RowBody/translation``), and
/// ``RowBody/languageTag`` carries the row's own `sourceLanguage`
/// (`"JA"` / `"EN"`) — so a bilingual transcript shows mixed tags down
/// the scroll. This replaces the prior fixed Japanese-primary
/// projection. Verified against
/// ``MeetingSession/persistCompleted(_:meetingID:)`` which calls
/// `appendSentence(sourceLanguage: translated.direction.source.rawValue,
/// sourceText: translated.sourceText, translatedText:
/// translated.translatedText, ...)`.
@MainActor
enum MeetingDetailFormatter {
    /// ISO 639-1 code for Japanese.
    static let japaneseTag = "ja"
    /// ISO 639-1 code for English.
    static let englishTag = "en"

    /// Short-style date+time string in the POSIX en-US locale. Delegates
    /// to ``MeetingListRowFormatter/formattedDate(_:)`` so the detail
    /// view's header and the history-list row render byte-identical
    /// strings for the same `Date` (UI decision #15).
    ///
    /// - Parameter date: Wall-clock time to render.
    /// - Returns: The same string ``MeetingListRowFormatter`` produces.
    static func formattedDate(_ date: Date) -> String {
        MeetingListRowFormatter.formattedDate(date)
    }

    /// Duration string. Whole minutes when `ended` is non-nil; an em-dash
    /// (`"—"`) when the meeting is still active. Delegates to
    /// ``MeetingListRowFormatter/formattedDuration(startedAt:endedAt:)``.
    ///
    /// - Parameters:
    ///   - started: Meeting start time.
    ///   - ended: Meeting end time, or `nil` if still active.
    /// - Returns: The same string ``MeetingListRowFormatter`` produces.
    static func formattedDuration(started: Date, ended: Date?) -> String {
        MeetingListRowFormatter.formattedDuration(startedAt: started, endedAt: ended)
    }

    /// Formats a `Date` to the per-sentence `HH:mm:ss` timestamp.
    /// Delegates to ``TranscriptSplitScreenFormatter/formatTimestamp(_:locale:)``
    /// so the detail view and the live split-screen render byte-identical
    /// per-sentence timestamps for the same `Date` (UI decision #15).
    ///
    /// - Parameter date: Wall-clock sentence timestamp.
    /// - Returns: The same string ``TranscriptSplitScreenFormatter`` produces.
    static func formatTimestamp(_ date: Date) -> String {
        TranscriptSplitScreenFormatter.formatTimestamp(date)
    }

    /// Projects a sentence into its **source-led** row body.
    ///
    /// The spoken-language text (`sourceText`) always leads as
    /// ``RowBody/source``; the translation (`translatedText`) follows as
    /// ``RowBody/translation``. ``RowBody/languageTag`` is the row's own
    /// `sourceLanguage` upper-cased (`"JA"` when `"ja"`, otherwise
    /// `"EN"`), so each row honestly labels the language that was spoken —
    /// a bilingual transcript shows mixed tags down the scroll.
    ///
    /// - Parameter sentence: The persisted projection.
    /// - Returns: Source-led row body for the detail view.
    static func sentenceBody(for sentence: MeetingDetail.SentenceProjection) -> RowBody {
        RowBody(
            source: sentence.sourceText,
            translation: sentence.translatedText,
            languageTag: sentence.sourceLanguage == japaneseTag ? "JA" : "EN",
            timestamp: formatTimestamp(sentence.timestamp)
        )
    }
}

/// Pure-value rendering of a single **source-led** detail-view row.
///
/// Returned by ``MeetingDetailFormatter/sentenceBody(for:)``. Sendable +
/// Equatable so tests can compare full row payloads and so the value
/// flows safely through SwiftUI's render graph.
nonisolated struct RowBody: Equatable {
    /// The spoken-language (source) text — the original utterance. Leads
    /// the row as the primary tonal level.
    let source: String

    /// The translation — the rendering in the other language. Follows the
    /// source as the secondary tonal level (colour-only difference).
    let translation: String

    /// The row's own source language as a display tag (`"JA"` / `"EN"`).
    let languageTag: String

    /// Pre-formatted `HH:mm:ss` timestamp string.
    let timestamp: String
}
