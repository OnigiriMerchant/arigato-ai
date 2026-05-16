//
//  MeetingListRow.swift
//  ArigatoAI
//
//  Created by Jose Castell on 2026/05/16.
//

import Foundation
import SwiftUI

/// Single-row presentation for a meeting in ``MeetingListView``.
///
/// Renders the locked per-meeting card metadata from Group D UI decision
/// #13:
/// - Title (decision #12) as the headline.
/// - Date + time in short style.
/// - Duration in whole minutes (e.g., `"50 min"`) when ``MeetingSummary/endedAt``
///   is non-nil; an em-dash (`"—"`) when the meeting is still active.
/// - Step 12: when ``MeetingSummary/firstMatchSnippet`` is non-nil, a third
///   line below the date/duration HStack displays the matching sentence
///   truncated to ~80 characters via
///   ``MeetingListRowFormatter/snippet(_:maxLength:)``. The snippet is
///   muted-secondary styled and serves as inline visual feedback that the
///   match came from sentence content rather than the title.
///
/// Date formatting uses `Locale(identifier: "en_US_POSIX")` for
/// deterministic test output — the date string the view emits is the same
/// string the test asserts against regardless of host locale.
///
/// Styling is pure stock SwiftUI per UI decisions #17 (semantic colors)
/// and #18 (system fonts — SF Pro for Latin, Hiragino Sans for Japanese).
/// ``Design/DesignTokens`` is intentionally untouched (V3 #22 design-system
/// work is deferred to Step 9).
struct MeetingListRow: View {
    /// The DTO to render. Sendable value type from ``MeetingStore``.
    let summary: MeetingSummary

    var body: some View {
        VStack(alignment: .leading) {
            Text(summary.title)
                .font(.headline)
            HStack {
                Text(MeetingListRowFormatter.formattedDate(summary.startedAt))
                Text("·")
                Text(MeetingListRowFormatter.formattedDuration(
                    startedAt: summary.startedAt,
                    endedAt: summary.endedAt
                ))
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            // Step 12: body-match snippet. Rendered when the store
            // populated `firstMatchSnippet` (body match, not title match;
            // non-empty needle). Pure stock SwiftUI styling — semantic
            // `.secondary` color per UI #17 to keep the row's visual
            // hierarchy (title > date/duration > snippet).
            if let snippet = summary.firstMatchSnippet {
                Text(MeetingListRowFormatter.snippet(snippet))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

/// Pure-value formatter for ``MeetingListRow``'s date and duration text.
///
/// Extracted from the `View` body so the formatting logic is testable
/// without the SwiftUI view tree — tests can call these static functions
/// directly and assert against the strings the row will display.
enum MeetingListRowFormatter {
    /// Short-style date+time string in the POSIX en-US locale. Locale
    /// is fixed for deterministic test output regardless of host locale.
    static func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    /// Duration string. Whole minutes when `endedAt` is non-nil; an
    /// em-dash (`"—"`) when the meeting is still active.
    ///
    /// Em-dash is the sentinel for "active meeting" in the history list;
    /// active meetings still show in the list (UI decision #6 — auto-save
    /// keeps the row visible even before STOP).
    static func formattedDuration(startedAt: Date, endedAt: Date?) -> String {
        guard let endedAt else { return "—" }
        let seconds = endedAt.timeIntervalSince(startedAt)
        let minutes = max(0, Int(seconds / 60))
        return "\(minutes) min"
    }

    /// Truncates a body-match snippet to `maxLength` characters and
    /// appends a horizontal-ellipsis suffix when truncated. Short snippets
    /// (at or below `maxLength`) are returned unchanged.
    ///
    /// Operates on `Character` count (grapheme clusters), so emoji and
    /// CJK characters count as 1 each — the visible-length contract
    /// matches user perception rather than UTF-16 code-unit count.
    ///
    /// Step 12: called from ``MeetingListRow`` when
    /// ``MeetingSummary/firstMatchSnippet`` is non-nil.
    ///
    /// - Parameters:
    ///   - text: Raw snippet (typically a ``Sentence/translatedText``
    ///     value forwarded by ``MeetingStore/fetchAll(searchText:)``).
    ///   - maxLength: Inclusive character cap. Defaults to 80.
    /// - Returns: `text` unchanged when its character count is at most
    ///   `maxLength`; otherwise the first `maxLength` characters plus
    ///   `"…"`.
    static func snippet(_ text: String, maxLength: Int = 80) -> String {
        if text.count <= maxLength {
            return text
        }
        let prefix = text.prefix(maxLength)
        return "\(prefix)…"
    }
}
