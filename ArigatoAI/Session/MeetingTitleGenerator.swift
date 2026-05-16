//
//  MeetingTitleGenerator.swift
//  ArigatoAI
//
//  Created by Jose Castell on 2026/05/16.
//

import Foundation

/// Generates a meeting display title from its start timestamp and the
/// first English sentence captured during the session.
///
/// This is the **MVP 1** path defined by Group D UI decision #12.
///
/// ## Format
/// - When `firstEnglishSentence` is non-nil and non-empty after trimming,
///   the title is `"<EEE h:mm a> — <truncated sentence>"`.
/// - When `firstEnglishSentence` is `nil` or empty/whitespace-only after
///   trimming, the title is just the timestamp — no separator, no ellipsis.
///
/// The timestamp uses `DateFormatter` with format `"EEE h:mm a"` and locale
/// `en_US_POSIX` so test output is deterministic regardless of the host
/// machine's locale. The timezone defaults to the current timezone —
/// tests pin a specific timezone via the optional `timeZone` parameter.
///
/// ## Truncation rule
/// The sentence portion is collapsed (any run of whitespace, including
/// newlines/tabs, becomes a single space) and then truncated to 39 user
/// characters + a single trailing `…` — 40 characters total. Sentences
/// shorter than the budget appear verbatim with no ellipsis.
///
/// ## Phase 6+ migration
/// This generator is **first-sentence-only** by design. The
/// Foundation-Models-based summarization path lands in Phase 6 per
/// decision #12 and the queued V3 entry "Migrate meeting title
/// generation from first-sentence to Foundation Models summarization".
/// The storage shape (a single `String` on `Meeting`) does not change;
/// only the function that produces the value swaps.
public nonisolated enum MeetingTitleGenerator {
    /// Maximum overall length of the sentence-portion suffix, including
    /// the trailing ellipsis character. Matches decision #12's "~40
    /// chars" target.
    private static let sentenceCharacterBudget = 40

    /// Single ellipsis character (`U+2026 HORIZONTAL ELLIPSIS`). Used
    /// when the sentence portion is truncated.
    private static let ellipsis: Character = "…"

    /// Builds the MVP 1 title.
    ///
    /// - Parameters:
    ///   - startedAt: The meeting's start time.
    ///   - firstEnglishSentence: The first English sentence captured
    ///     during the session, if any. Passing `nil` or an empty /
    ///     whitespace-only string yields the bare-timestamp fallback.
    ///   - timeZone: Timezone for the formatter. Defaults to the
    ///     current timezone. Tests pin a specific timezone so the
    ///     formatted output is deterministic.
    /// - Returns: The composed title.
    public static func makeTitle(
        startedAt: Date,
        firstEnglishSentence: String?,
        timeZone: TimeZone = .current
    ) -> String {
        let stamp = formatTimestamp(startedAt, timeZone: timeZone)
        guard let raw = firstEnglishSentence else { return stamp }
        let collapsed = collapseWhitespace(raw)
        if collapsed.isEmpty { return stamp }
        let truncated = truncate(collapsed, budget: Self.sentenceCharacterBudget)
        return "\(stamp) — \(truncated)"
    }

    // MARK: - Internals

    private static func formatTimestamp(_ date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "EEE h:mm a"
        return formatter.string(from: date)
    }

    /// Collapses any whitespace run (spaces, tabs, newlines) to a single
    /// space and trims leading/trailing whitespace.
    private static func collapseWhitespace(_ input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "" }
        var result = ""
        result.reserveCapacity(trimmed.count)
        var lastWasSpace = false
        for scalar in trimmed.unicodeScalars {
            if CharacterSet.whitespacesAndNewlines.contains(scalar) {
                if !lastWasSpace {
                    result.append(" ")
                    lastWasSpace = true
                }
            } else {
                result.append(Character(scalar))
                lastWasSpace = false
            }
        }
        return result
    }

    /// Truncates `input` to fit within `budget` Swift `Character`s.
    /// When truncation is needed, the result is `budget - 1` characters
    /// of `input` followed by a single trailing ellipsis (total length
    /// `budget`). When `input` is already within `budget`, it is
    /// returned verbatim.
    private static func truncate(_ input: String, budget: Int) -> String {
        if input.count <= budget { return input }
        let keep = budget - 1
        let prefix = input.prefix(keep)
        return String(prefix) + String(Self.ellipsis)
    }
}
