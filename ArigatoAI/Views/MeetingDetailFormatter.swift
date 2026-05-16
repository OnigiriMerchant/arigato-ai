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
/// ## Source/translated semantics
///
/// A ``MeetingDetail/SentenceProjection`` carries `sourceLanguage`
/// (`"ja"` or `"en"`) and a `sourceText` that is always the **original**
/// utterance. ``sentenceBody(for:)`` projects the row into a
/// language-aligned ``RowBody`` so the view always displays the
/// Japanese text in one slot and the English text in the other,
/// regardless of which language the speaker used. Verified against
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

    /// Projects a sentence to its Japanese / English / timestamp row body.
    ///
    /// `sourceLanguage == "ja"` means `sourceText` is the original
    /// Japanese utterance and `translatedText` is the English rendering;
    /// `sourceLanguage == "en"` means the inverse. The returned
    /// ``RowBody`` always puts the Japanese text in ``RowBody/japanese``
    /// and the English text in ``RowBody/english``, regardless of which
    /// language the speaker originally used.
    ///
    /// - Parameter sentence: The persisted projection.
    /// - Returns: Language-aligned row body for the detail view.
    static func sentenceBody(for sentence: MeetingDetail.SentenceProjection) -> RowBody {
        let japanese: String
        let english: String
        if sentence.sourceLanguage == japaneseTag {
            japanese = sentence.sourceText
            english = sentence.translatedText
        } else {
            japanese = sentence.translatedText
            english = sentence.sourceText
        }
        return RowBody(
            japanese: japanese,
            english: english,
            timestamp: formatTimestamp(sentence.timestamp)
        )
    }
}

/// Pure-value rendering of a single detail-view row.
///
/// Returned by ``MeetingDetailFormatter/sentenceBody(for:)``. Sendable +
/// Equatable so tests can compare full row payloads and so the value
/// flows safely through SwiftUI's render graph.
nonisolated struct RowBody: Equatable {
    /// The Japanese text — either the original utterance (when the
    /// speaker spoke Japanese) or the LFM2 translation (when the
    /// speaker spoke English).
    let japanese: String

    /// The English text — either the original utterance (when the
    /// speaker spoke English) or the LFM2 translation (when the
    /// speaker spoke Japanese).
    let english: String

    /// Pre-formatted `HH:mm:ss` timestamp string.
    let timestamp: String
}
