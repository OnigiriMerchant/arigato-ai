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
}
