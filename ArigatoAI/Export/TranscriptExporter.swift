//
//  TranscriptExporter.swift
//  ArigatoAI
//
//  Created by Jose Castell on 2026/05/17.
//

import Foundation

/// Pure-value transcript-export utility producing a Markdown file in the
/// system temporary directory, for use with SwiftUI's `ShareLink`.
///
/// Step 13 of Phase 5 Group D — UI decision #9 Context B (detail-view
/// share) + UI decision #10 (Markdown format, both languages,
/// per-sentence timestamps). Context A (ended-state share on active
/// transcript) and Context C (history multi-select share) are out of
/// scope for Step 13.
///
/// ## Isolation
///
/// Explicitly `nonisolated` despite the project's
/// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` — Step 13 is the 4th
/// occurrence of this stateless-pure-value annotation pattern in
/// Group D (after ``MeetingListRowFormatter``,
/// ``TranscriptSplitScreenFormatter``, ``MeetingDetailFormatter``); V3
/// entry filed in Commit 2 of Step 13's two-commit cluster.
///
/// ## Scheduling assumptions
///
/// 1. ``writeTemporaryFile(markdown:filename:)`` performs synchronous
///    `Data.write(to:)` on the calling thread. MVP 1 transcript sizes
///    (30–60 KB) make this a non-issue. Documented per the project's
///    "Concurrency design discipline" rule. No violation test required
///    — the synchronous file write from a synchronous computed property
///    does not trip CLAUDE.md's concurrency gate.
/// 2. ``markdownBody(summary:sentences:)`` trusts caller-supplied
///    sentence ordering — it does NOT re-sort. ``MeetingDetail`` is the
///    canonical chronological-order source; callers passing sentences in
///    any other order will see them rendered in that order.
///
/// ## Format contract (D13-3)
///
/// Pair-by-pair body with a single `[HH:mm:ss]` prefix on the Japanese
/// line only (the English line carries no timestamp because the
/// translation timestamp would be byte-identical and the prefix would
/// duplicate). Header is `# <title>` then a metadata line
/// `<start> — <end> · <duration>` then a horizontal rule (`---`).
nonisolated enum TranscriptExporter {
    // MARK: - Header date format (POSIX en-US, deterministic)

    /// POSIX en-US `DateFormatter` for the export header's date range.
    /// Format: `"MMM d, yyyy 'at' HH:mm"` (e.g., `"May 17, 2026 at 14:22"`).
    ///
    /// Locale is locked to `en_US_POSIX` so exported transcripts are
    /// portable — same string regardless of the device's locale. Distinct
    /// from ``MeetingListRowFormatter/formattedDate(_:)`` (which uses
    /// `.short`/`.short` styles) by design: the export header carries a
    /// longer human-readable date range, the row formatter carries a
    /// compact list-row date.
    private static let headerDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM d, yyyy 'at' HH:mm"
        return formatter
    }()

    /// POSIX en-US `DateFormatter` for the filename `yyyy-MM-dd` short-date
    /// suffix (e.g., `"2026-05-17"`). Locale locked for determinism.
    private static let filenameDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    /// POSIX en-US `DateFormatter` for the per-sentence `[HH:mm:ss]` prefix.
    /// Distinct from ``TranscriptSplitScreenFormatter/formatTimestamp(_:locale:)``
    /// only in that it always uses `en_US_POSIX` — the live view's
    /// formatter is locale-flexible for caller convenience. Export
    /// stability requires the POSIX lock.
    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    /// POSIX en-US `DateFormatter` for the `-HHmmss` collision suffix on
    /// filenames (e.g., `"144208"`).
    private static let collisionSuffixFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HHmmss"
        return formatter
    }()

    // MARK: - Public API

    /// Renders meeting transcript to Markdown.
    ///
    /// Header is `# <title>` (line 1) + blank line + metadata line
    /// `<start> — <end> · <duration>` (line 3) + blank line + horizontal
    /// rule `---` (line 5) + blank line. Then one block per sentence in
    /// caller-supplied order:
    ///
    /// ```
    /// [HH:mm:ss] <japanese-text>
    /// <english-text>
    /// ```
    ///
    /// Blocks are separated by a single blank line. Output ends with
    /// exactly one trailing newline (POSIX file convention).
    ///
    /// Date format inside the header: `MMM d, yyyy 'at' HH:mm` (POSIX
    /// en-US). Duration is whole minutes (`"50 min"`) when `summary.endedAt`
    /// is non-nil; when `nil`, the metadata line degrades to
    /// `<start> · still active`.
    ///
    /// Per-sentence language projection mirrors
    /// ``MeetingDetailFormatter/sentenceBody(for:)``:
    /// - `sourceLanguage == "ja"`: Japanese line is `sourceText`, English
    ///   line is `translatedText`.
    /// - `sourceLanguage == "en"`: Japanese line is `translatedText`,
    ///   English line is `sourceText`.
    ///
    /// This method trusts caller ordering — it does NOT re-sort
    /// `sentences`. The scheduling-assumption doc-comment on the
    /// enclosing type captures the caller contract.
    ///
    /// - Parameters:
    ///   - summary: Meeting metadata for the header.
    ///     ``MeetingSummary/firstMatchSnippet`` is ignored (the export
    ///     header is not search-context-aware).
    ///   - sentences: Sentence projections in chronological order. An
    ///     empty array yields a header-only document (no body blocks).
    /// - Returns: UTF-8 Markdown string.
    static func markdownBody(
        summary: MeetingSummary,
        sentences: [MeetingDetail.SentenceProjection]
    ) -> String {
        let title = summary.title
        let header = renderHeader(title: title, summary: summary)
        // `header` ends with the `---\n` line — a single trailing newline.
        // For the empty case, this is also a valid POSIX-conformant file
        // (single trailing newline, no blank line after the rule).
        if sentences.isEmpty {
            return header
        }
        // Each block ends in `\n` (`[stamp] ja\nen\n`); joining with `\n`
        // produces `[block1]\n[block2]` where each `\n[block` is the
        // blank-line separator between blocks. The final character is the
        // last block's trailing `\n` — single trailing newline preserved.
        // Prefix with an extra `\n` so the header's `---\n` becomes
        // `---\n\n[block1]`, yielding a blank line between rule and body.
        let blocks = sentences.map(renderSentenceBlock(_:))
        let body = blocks.joined(separator: "\n")
        return header + "\n" + body
    }

    /// Sanitises `title` and appends a `-yyyy-MM-dd` short-date suffix +
    /// `.md` extension. POSIX-illegal characters (`/`), reserved Windows
    /// characters (`:`, `?`, `*`, `\`), and Unicode control characters
    /// are stripped; runs of whitespace collapse to a single `-`; the
    /// sanitised body is truncated to at most 60 characters before the
    /// date suffix.
    ///
    /// Empty or whitespace-only `title` falls back to
    /// `"transcript-yyyy-MM-dd.md"`.
    ///
    /// Date format is locked to `en_US_POSIX` `yyyy-MM-dd` so generated
    /// filenames are stable across devices and locales.
    ///
    /// - Parameters:
    ///   - title: Raw meeting title — typically ``MeetingSummary/title``.
    ///   - startedAt: Wall-clock start time used for the date suffix
    ///     (POSIX en-US for determinism).
    /// - Returns: `"<body>-yyyy-MM-dd.md"` or `"transcript-yyyy-MM-dd.md"`
    ///   when `title` is empty / whitespace-only after sanitisation.
    static func makeFilename(title: String, startedAt: Date) -> String {
        let datePart = filenameDateFormatter.string(from: startedAt)
        let sanitised = sanitiseTitleForFilename(title)
        if sanitised.isEmpty {
            return "transcript-\(datePart).md"
        }
        return "\(sanitised)-\(datePart).md"
    }

    /// Writes `markdown` (encoded as UTF-8) to
    /// `FileManager.default.temporaryDirectory/<filename>`.
    ///
    /// **Collision policy:** if a file already exists at the target URL,
    /// the method appends `-HHmmss` (current wall-clock time, POSIX
    /// en-US) before the `.md` extension and writes to that derived URL
    /// instead. The collision branch fires once; if the derived URL also
    /// exists, the existing file is overwritten (acceptable for MVP 1 —
    /// the second-of-day collision window is degenerate).
    ///
    /// The OS reclaims the temp directory on its own schedule (typically
    /// at OS-managed cleanup points or device reboot); no manual cleanup
    /// is performed by this method. Acceptable for MVP 1 share-and-discard
    /// usage. Post-MVP optimization candidate: explicit cleanup hook on
    /// app foreground.
    ///
    /// ## Scheduling assumption (1, doc-commented on the type)
    ///
    /// The write is synchronous on the calling thread. MVP 1 transcript
    /// sizes (30–60 KB) make this fine; the method does not spawn a
    /// background task. Callers on `@MainActor` may invoke this
    /// directly.
    ///
    /// - Parameters:
    ///   - markdown: UTF-8 Markdown body to persist. Typically the
    ///     output of ``markdownBody(summary:sentences:)``.
    ///   - filename: Last path component — typically the output of
    ///     ``makeFilename(title:startedAt:)``.
    /// - Throws: ``TranscriptExportError/writeFailed(underlying:)`` when
    ///   `Data.write(to:options:)` raises an error (e.g., a malformed
    ///   filename, sandbox-permissions failure, or volume-full
    ///   condition). The underlying error's `localizedDescription` is
    ///   captured for diagnostic surfacing.
    /// - Returns: `file://` URL of the written file, suitable for use
    ///   with `ShareLink(item:)`.
    static func writeTemporaryFile(
        markdown: String,
        filename: String
    ) throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let primaryURL = tempDir.appendingPathComponent(filename)
        let targetURL: URL
        if FileManager.default.fileExists(atPath: primaryURL.path) {
            let now = Date()
            let suffix = collisionSuffixFormatter.string(from: now)
            let derivedName = makeCollisionFilename(original: filename, suffix: suffix)
            targetURL = tempDir.appendingPathComponent(derivedName)
        } else {
            targetURL = primaryURL
        }
        guard let data = markdown.data(using: .utf8) else {
            throw TranscriptExportError.writeFailed(underlying: "UTF-8 encoding failed")
        }
        do {
            try data.write(to: targetURL, options: [.atomic])
        } catch {
            throw TranscriptExportError.writeFailed(underlying: error.localizedDescription)
        }
        return targetURL
    }

    // MARK: - Internal helpers

    /// Renders the header (title + metadata line + horizontal rule).
    /// Header consists of 5 lines:
    /// 1. `# <title>`
    /// 2. blank
    /// 3. `<start> — <end> · <duration>` (or `<start> · still active`)
    /// 4. blank
    /// 5. `---`
    /// Returned without a trailing newline — caller appends.
    private static func renderHeader(title: String, summary: MeetingSummary) -> String {
        let formattedStart = headerDateFormatter.string(from: summary.startedAt)
        let metadata: String
        if let endedAt = summary.endedAt {
            let formattedEnd = headerDateFormatter.string(from: endedAt)
            let duration = formattedDurationMinutes(start: summary.startedAt, end: endedAt)
            metadata = "\(formattedStart) — \(formattedEnd) · \(duration)"
        } else {
            metadata = "\(formattedStart) · still active"
        }
        return "# \(title)\n\n\(metadata)\n\n---\n"
    }

    /// Renders a single sentence block as two lines + trailing newline.
    /// `[HH:mm:ss] <japanese>\n<english>\n`.
    private static func renderSentenceBlock(_ sentence: MeetingDetail.SentenceProjection) -> String {
        let stamp = timestampFormatter.string(from: sentence.timestamp)
        let japanese: String
        let english: String
        if sentence.sourceLanguage == "ja" {
            japanese = sentence.sourceText
            english = sentence.translatedText
        } else {
            japanese = sentence.translatedText
            english = sentence.sourceText
        }
        return "[\(stamp)] \(japanese)\n\(english)\n"
    }

    /// Whole-minute duration string, e.g., `"50 min"`. Minimum 0 (a
    /// negative interval would imply clock skew between start and end —
    /// degrade gracefully rather than emit a `-1 min` artefact).
    private static func formattedDurationMinutes(start: Date, end: Date) -> String {
        let seconds = end.timeIntervalSince(start)
        let minutes = max(0, Int(seconds / 60))
        return "\(minutes) min"
    }

    /// Strips POSIX/Windows-reserved characters + Unicode control chars,
    /// collapses whitespace to a single `-`, trims leading/trailing
    /// dashes/whitespace, and truncates to 60 characters.
    ///
    /// Reserved character set: `/`, `:`, `?`, `*`, `\`. POSIX forbids
    /// `/` (path separator); the others are reserved on Windows and
    /// the AirDrop / Files.app / Mail integrations can choke on them.
    private static func sanitiseTitleForFilename(_ title: String) -> String {
        let reserved: Set<Character> = ["/", ":", "?", "*", "\\"]
        var output = ""
        var lastWasDash = false
        for scalar in title.unicodeScalars {
            let character = Character(scalar)
            if scalar.properties.generalCategory == .control {
                continue
            }
            if reserved.contains(character) {
                continue
            }
            if character.isWhitespace {
                if !lastWasDash, !output.isEmpty {
                    output.append("-")
                    lastWasDash = true
                }
                continue
            }
            output.append(character)
            lastWasDash = false
        }
        // Trim trailing dash(es).
        while output.hasSuffix("-") {
            output.removeLast()
        }
        // Trim leading dash(es).
        while output.hasPrefix("-") {
            output.removeFirst()
        }
        // Truncate to 60 chars, then re-trim trailing dash if truncation
        // landed on one.
        if output.count > 60 {
            output = String(output.prefix(60))
            while output.hasSuffix("-") {
                output.removeLast()
            }
        }
        return output
    }

    /// Derives a collision filename by inserting `-<suffix>` between the
    /// sanitised body + date and the `.md` extension. If `original` has
    /// no `.md` extension (defensive — caller always supplies one),
    /// the suffix is appended at the end.
    private static func makeCollisionFilename(original: String, suffix: String) -> String {
        let mdExtension = ".md"
        if original.hasSuffix(mdExtension) {
            let stem = String(original.dropLast(mdExtension.count))
            return "\(stem)-\(suffix)\(mdExtension)"
        }
        return "\(original)-\(suffix)"
    }
}

/// Error surface for ``TranscriptExporter/writeTemporaryFile(markdown:filename:)``.
///
/// Thrown when the underlying `Data.write(to:options:)` raises or when
/// UTF-8 encoding of the Markdown body fails (a degenerate case for
/// `String`, captured defensively). The `underlying` payload carries
/// the wrapped error's `localizedDescription` for diagnostic surfacing
/// in `MeetingDetailView`'s `exportURL` computed property — which
/// returns `nil` on any throw so the `ShareLink` toolbar item is
/// suppressed (UI decision #4: "buttons exist only when usable.").
///
/// `Equatable` conformance is value-insensitive: two
/// `.writeFailed(underlying:)` cases compare equal regardless of the
/// captured message. The narrow ergonomic — `if error == .writeFailed`
/// in tests — is the entire point. Diagnostic detail is preserved on
/// the instance for logging, not for comparison.
nonisolated enum TranscriptExportError: Error, Equatable {
    /// The underlying file-write failed. `underlying` carries the
    /// wrapped error's `localizedDescription` (or `"UTF-8 encoding
    /// failed"` for the degenerate encoding case).
    case writeFailed(underlying: String)

    static func == (lhs: TranscriptExportError, rhs: TranscriptExportError) -> Bool {
        switch (lhs, rhs) {
        case (.writeFailed, .writeFailed): return true
        }
    }
}
