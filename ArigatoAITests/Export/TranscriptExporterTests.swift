//
//  TranscriptExporterTests.swift
//  ArigatoAITests
//
//  Created by Jose Castell on 2026/05/17.
//

@testable import ArigatoAI
import Foundation
import SwiftData
import Testing

/// Tests for ``TranscriptExporter`` — the Step 13 Markdown-export
/// utility (UI #9 Context B + UI #10).
///
/// Marked `@MainActor` to match the project convention
/// (`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`). ``TranscriptExporter``
/// is explicitly `nonisolated`, so the main-actor host adds no friction
/// — calls into the exporter cross no actor boundary.
///
/// Coverage matrix (12 tests):
/// - `markdownBody` × 7 — empty / JA-source / EN-source / header /
///   nil-end / multi-sentence-separators / caller-order-preservation.
/// - `makeFilename` × 3 — sanitisation / 60-char-truncation / empty-fallback.
/// - `writeTemporaryFile` × 2 — UTF-8 round-trip / collision suffix.
@Suite("TranscriptExporter")
@MainActor
struct TranscriptExporterTests {
    // MARK: - In-memory ModelContainer for PersistentIdentifier minting

    /// Helper that builds a throwaway in-memory container so tests can
    /// mint real `PersistentIdentifier` values for the DTOs.
    private static func makeContainer() throws -> ModelContainer {
        let schema = Schema([Meeting.self, Sentence.self])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: configuration)
    }

    /// Inserts a `Meeting` and returns a `MeetingSummary` built via
    /// the canonical `MeetingSummary(from:)` initializer (no memberwise
    /// init exists on the struct — all construction goes through the
    /// model-derived init).
    private static func makeSummaryFromContainer(
        in container: ModelContainer,
        title: String,
        startedAt: Date,
        endedAt: Date?
    ) throws -> MeetingSummary {
        let context = ModelContext(container)
        let meeting = Meeting(startedAt: startedAt, title: title)
        meeting.endedAt = endedAt
        context.insert(meeting)
        try context.save()
        return MeetingSummary(from: meeting)
    }

    /// Inserts a `Sentence` and returns its `PersistentIdentifier`. The
    /// inserted row has no parent `Meeting` — this fixture exists only
    /// to mint a real `PersistentIdentifier` for the
    /// ``MeetingDetail/SentenceProjection`` DTO under test, which is a
    /// pure-value type that does not traverse the SwiftData relationship.
    private static func makeSentenceID(
        in container: ModelContainer,
        timestamp: Date
    ) throws -> PersistentIdentifier {
        let context = ModelContext(container)
        let sentence = Sentence(
            timestamp: timestamp,
            sourceLanguage: "ja",
            sourceText: "fixture",
            translatedText: "fixture",
            sourceSegmentID: UUID(),
            searchableText: "fixture"
        )
        context.insert(sentence)
        try context.save()
        return sentence.persistentModelID
    }

    // MARK: - Fixture builders

    private static func makeSummary(
        title: String = "Project sync",
        startedAt: Date,
        endedAt: Date?
    ) throws -> MeetingSummary {
        let container = try makeContainer()
        return try makeSummaryFromContainer(
            in: container,
            title: title,
            startedAt: startedAt,
            endedAt: endedAt
        )
    }

    private static func makeSentence(
        timestamp: Date,
        sourceLanguage: String,
        sourceText: String,
        translatedText: String,
        container: ModelContainer? = nil
    ) throws -> MeetingDetail.SentenceProjection {
        let useContainer = try (container ?? makeContainer())
        let sentenceID = try makeSentenceID(in: useContainer, timestamp: timestamp)
        return MeetingDetail.SentenceProjection(
            id: sentenceID,
            timestamp: timestamp,
            sourceLanguage: sourceLanguage,
            sourceText: sourceText,
            translatedText: translatedText,
            sourceSegmentID: UUID()
        )
    }

    /// Builds a `Date` from POSIX en-US `yyyy-MM-dd HH:mm:ss` for
    /// deterministic test inputs. Parses in `TimeZone.current` so the
    /// wall-clock value (e.g., `"14:22:00"`) round-trips through the
    /// exporter's `DateFormatter`s (which also use `TimeZone.current`
    /// by default). This matches production semantics where
    /// `MeetingSummary.startedAt` is a real wall-clock `Date.now` value.
    private static func date(_ string: String) throws -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.timeZone = TimeZone.current
        guard let result = formatter.date(from: string) else {
            throw TestSetupError.dateParseFailed(string)
        }
        return result
    }

    /// Lightweight test-only error used by the date helper instead of
    /// `fatalError` — keeps the project's "no `fatalError` to silence
    /// errors" rule unbroken.
    private enum TestSetupError: Error {
        case dateParseFailed(String)
    }

    // MARK: - markdownBody — empty input

    /// Empty `sentences` produces a valid Markdown document with header
    /// + horizontal rule + trailing newline, and no body blocks.
    @Test("markdownBody_emptyMeeting_returnsHeaderOnlyOrPlaceholder")
    func markdownBody_emptyMeeting_returnsHeaderOnlyOrPlaceholder() throws {
        let start = try Self.date("2026-05-17 14:22:00")
        let end = try Self.date("2026-05-17 15:12:00")
        let summary = try Self.makeSummary(startedAt: start, endedAt: end)

        let body = TranscriptExporter.markdownBody(summary: summary, sentences: [])

        #expect(body.contains("# Project sync"))
        #expect(body.contains("---"))
        #expect(body.hasSuffix("\n"))
        // No body block markers: no `[HH:mm:ss]` prefix in the empty
        // case (regex-free containment check is sufficient).
        #expect(!body.contains("["))
    }

    // MARK: - markdownBody — JA-source sentence projection

    /// `sourceLanguage == "ja"`: Japanese line is `sourceText`, English
    /// line is `translatedText`. Output ordering is JA-first then EN.
    @Test("markdownBody_singleJapaneseSourceSentence_emitsJaThenEn")
    func markdownBody_singleJapaneseSourceSentence_emitsJaThenEn() throws {
        let start = try Self.date("2026-05-17 14:22:00")
        let end = try Self.date("2026-05-17 15:12:00")
        let summary = try Self.makeSummary(startedAt: start, endedAt: end)
        let container = try Self.makeContainer()
        let sentence = try Self.makeSentence(
            timestamp: Self.date("2026-05-17 14:22:03"),
            sourceLanguage: "ja",
            sourceText: "こんにちは、皆さん。",
            translatedText: "Hello, everyone.",
            container: container
        )

        let body = TranscriptExporter.markdownBody(summary: summary, sentences: [sentence])

        // Japanese line (with timestamp prefix) appears before English line.
        let jaRange = body.range(of: "[14:22:03] こんにちは、皆さん。")
        let enRange = body.range(of: "Hello, everyone.")
        #expect(jaRange != nil)
        #expect(enRange != nil)
        if let jaRange, let enRange {
            #expect(jaRange.lowerBound < enRange.lowerBound)
        }
        // English line carries no timestamp prefix.
        #expect(!body.contains("[14:22:03] Hello, everyone."))
    }

    // MARK: - markdownBody — EN-source sentence projection (parity)

    /// `sourceLanguage == "en"`: Japanese line is `translatedText`,
    /// English line is `sourceText`. Pins language-projection parity
    /// with the JA-source case.
    @Test("markdownBody_singleEnglishSourceSentence_emitsJaThenEn")
    func markdownBody_singleEnglishSourceSentence_emitsJaThenEn() throws {
        let start = try Self.date("2026-05-17 14:22:00")
        let end = try Self.date("2026-05-17 15:12:00")
        let summary = try Self.makeSummary(startedAt: start, endedAt: end)
        let container = try Self.makeContainer()
        let sentence = try Self.makeSentence(
            timestamp: Self.date("2026-05-17 14:22:08"),
            sourceLanguage: "en",
            sourceText: "Let's review today's agenda.",
            translatedText: "今日のアジェンダを確認しましょう。",
            container: container
        )

        let body = TranscriptExporter.markdownBody(summary: summary, sentences: [sentence])

        // Japanese (translated) line carries the timestamp prefix and
        // appears first.
        let jaLine = "[14:22:08] 今日のアジェンダを確認しましょう。"
        let enLine = "Let's review today's agenda."
        let jaRange = body.range(of: jaLine)
        let enRange = body.range(of: enLine)
        #expect(jaRange != nil)
        #expect(enRange != nil)
        if let jaRange, let enRange {
            #expect(jaRange.lowerBound < enRange.lowerBound)
        }
        #expect(!body.contains("[14:22:08] Let's review today's agenda."))
    }

    // MARK: - markdownBody — header shape

    /// Header carries `# <title>` and a metadata line with formatted
    /// start, end, and a `min`-suffixed duration.
    @Test("markdownBody_headerCarriesTitleAndDateRangeAndDuration")
    func markdownBody_headerCarriesTitleAndDateRangeAndDuration() throws {
        let start = try Self.date("2026-05-17 14:22:00")
        let end = try Self.date("2026-05-17 15:12:00")
        let summary = try Self.makeSummary(
            title: "Weekly standup",
            startedAt: start,
            endedAt: end
        )

        let body = TranscriptExporter.markdownBody(summary: summary, sentences: [])

        #expect(body.contains("# Weekly standup"))
        // Header date format: `MMM d, yyyy 'at' HH:mm` POSIX en-US.
        #expect(body.contains("May 17, 2026 at 14:22"))
        #expect(body.contains("May 17, 2026 at 15:12"))
        // 50-minute duration: 15:12 − 14:22 = 50 min.
        #expect(body.contains("50 min"))
    }

    // MARK: - markdownBody — nil endedAt fallback

    /// `summary.endedAt == nil` degrades the metadata line to
    /// `<start> · still active` rather than emitting a dangling em-dash
    /// or an unformatted nil-end marker.
    @Test("markdownBody_nilEndedAt_fallbackToReasonableHeaderFormat")
    func markdownBody_nilEndedAt_fallbackToReasonableHeaderFormat() throws {
        let start = try Self.date("2026-05-17 14:22:00")
        let summary = try Self.makeSummary(
            title: "Still active",
            startedAt: start,
            endedAt: nil
        )

        let body = TranscriptExporter.markdownBody(summary: summary, sentences: [])

        #expect(body.contains("# Still active"))
        #expect(body.contains("May 17, 2026 at 14:22"))
        #expect(body.contains("still active"))
        // No `— ` (em-dash space) in the metadata line because the end
        // date is absent.
        #expect(!body.contains("— May"))
    }

    // MARK: - markdownBody — block separation + trailing newline

    /// Three sentences produce exactly two blank-line separators between
    /// blocks, and the file ends in exactly one `\n`.
    @Test("markdownBody_multipleSentences_emptyLinesBetweenPairs")
    func markdownBody_multipleSentences_emptyLinesBetweenPairs() throws {
        let start = try Self.date("2026-05-17 14:22:00")
        let end = try Self.date("2026-05-17 15:12:00")
        let summary = try Self.makeSummary(startedAt: start, endedAt: end)
        let container = try Self.makeContainer()
        let first = try Self.makeSentence(
            timestamp: Self.date("2026-05-17 14:22:03"),
            sourceLanguage: "ja",
            sourceText: "一つ目。",
            translatedText: "First.",
            container: container
        )
        let second = try Self.makeSentence(
            timestamp: Self.date("2026-05-17 14:22:10"),
            sourceLanguage: "ja",
            sourceText: "二つ目。",
            translatedText: "Second.",
            container: container
        )
        let third = try Self.makeSentence(
            timestamp: Self.date("2026-05-17 14:22:17"),
            sourceLanguage: "ja",
            sourceText: "三つ目。",
            translatedText: "Third.",
            container: container
        )

        let body = TranscriptExporter.markdownBody(
            summary: summary,
            sentences: [first, second, third]
        )

        // Each block is rendered as JA-line\nEN-line\n; the joiner is a
        // single `\n`, producing `EN-line\n\nJA-line` between blocks
        // (i.e., the boundary contains an empty line). Count the
        // `\n\n` boundaries inside the body region (after the header
        // rule). 3 blocks → 2 between-block double newlines.
        guard let ruleRange = body.range(of: "---\n") else {
            Issue.record("Header rule '---' missing from output")
            return
        }
        let afterRule = body[ruleRange.upperBound...]
        let doubleNewlineCount = afterRule.components(separatedBy: "\n\n").count - 1
        #expect(doubleNewlineCount == 2)
        // File ends in exactly one \n.
        #expect(body.hasSuffix("\n"))
        #expect(!body.hasSuffix("\n\n"))
    }

    // MARK: - markdownBody — caller order preserved

    /// Feeds sentences in reverse-chronological order; the exporter
    /// must NOT re-sort. The output reflects the caller-supplied order.
    @Test("markdownBody_preservesCallerOrder_doesNotSort")
    func markdownBody_preservesCallerOrder_doesNotSort() throws {
        let start = try Self.date("2026-05-17 14:22:00")
        let end = try Self.date("2026-05-17 15:12:00")
        let summary = try Self.makeSummary(startedAt: start, endedAt: end)
        let container = try Self.makeContainer()
        let early = try Self.makeSentence(
            timestamp: Self.date("2026-05-17 14:22:03"),
            sourceLanguage: "ja",
            sourceText: "EARLY",
            translatedText: "early-en",
            container: container
        )
        let late = try Self.makeSentence(
            timestamp: Self.date("2026-05-17 14:30:00"),
            sourceLanguage: "ja",
            sourceText: "LATE",
            translatedText: "late-en",
            container: container
        )

        // Feed late-then-early — exporter must preserve.
        let body = TranscriptExporter.markdownBody(
            summary: summary,
            sentences: [late, early]
        )

        guard let lateRange = body.range(of: "LATE"),
              let earlyRange = body.range(of: "EARLY")
        else {
            Issue.record("Expected sentinel strings missing from output")
            return
        }
        #expect(lateRange.lowerBound < earlyRange.lowerBound)
    }

    // MARK: - makeFilename — sanitisation

    /// Title carries POSIX-illegal `/`, Windows-reserved `:` + `?`, and
    /// internal whitespace — all of which must be stripped or
    /// dash-collapsed. The output ends in `-yyyy-MM-dd.md`.
    @Test("makeFilename_sanitisesPathSeparatorsAndReservedChars")
    func makeFilename_sanitisesPathSeparatorsAndReservedChars() throws {
        let start = try Self.date("2026-05-17 14:22:00")
        let title = "Q3/Q4 review: status & next?"

        let filename = TranscriptExporter.makeFilename(title: title, startedAt: start)

        #expect(!filename.contains("/"))
        #expect(!filename.contains(":"))
        #expect(!filename.contains("?"))
        // Whitespace runs collapse to a single dash.
        #expect(!filename.contains(" "))
        // Date suffix present.
        #expect(filename.hasSuffix("-2026-05-17.md"))
        // The non-illegal characters survive.
        #expect(filename.contains("Q3"))
        #expect(filename.contains("Q4"))
        #expect(filename.contains("review"))
        #expect(filename.contains("status"))
    }

    // MARK: - makeFilename — 60-char truncation

    /// A 200-character title's body portion (before `-yyyy-MM-dd.md`)
    /// must not exceed 60 characters; the date suffix must remain intact.
    @Test("makeFilename_truncatesBodyTo60Chars")
    func makeFilename_truncatesBodyTo60Chars() throws {
        let start = try Self.date("2026-05-17 14:22:00")
        let longTitle = String(repeating: "a", count: 200)

        let filename = TranscriptExporter.makeFilename(title: longTitle, startedAt: start)

        let dateSuffix = "-2026-05-17.md"
        #expect(filename.hasSuffix(dateSuffix))
        let body = String(filename.dropLast(dateSuffix.count))
        #expect(body.count <= 60)
        #expect(body.count > 0)
    }

    // MARK: - makeFilename — empty title fallback

    /// Whitespace-only title falls back to `transcript-yyyy-MM-dd.md`
    /// rather than `-yyyy-MM-dd.md` (which would start with a leading
    /// dash — degraded filename).
    @Test("makeFilename_emptyTitle_fallsBackToTranscriptDate")
    func makeFilename_emptyTitle_fallsBackToTranscriptDate() throws {
        let start = try Self.date("2026-05-17 14:22:00")

        let emptyFilename = TranscriptExporter.makeFilename(title: "", startedAt: start)
        let whitespaceFilename = TranscriptExporter.makeFilename(title: "    ", startedAt: start)

        #expect(emptyFilename == "transcript-2026-05-17.md")
        #expect(whitespaceFilename == "transcript-2026-05-17.md")
    }

    // MARK: - writeTemporaryFile — UTF-8 round-trip

    /// File lands in temp dir, contents round-trip through UTF-8 cleanly.
    @Test("writeTemporaryFile_writesUTF8ToTempDir_andReadableRoundTrip")
    func writeTemporaryFile_writesUTF8ToTempDir_andReadableRoundTrip() throws {
        let body = "# 日本語タイトル\n\nこんにちは。\nHello.\n"
        let filename = "roundtrip-\(UUID().uuidString).md"

        let url = try TranscriptExporter.writeTemporaryFile(markdown: body, filename: filename)

        let tempPath = FileManager.default.temporaryDirectory.path
        #expect(url.path.hasPrefix(tempPath))
        let readback = try String(contentsOf: url, encoding: .utf8)
        #expect(readback == body)

        // Clean up — temp dir reclamation is async, leave the OS to it,
        // but remove the test artifact eagerly.
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - writeTemporaryFile — collision suffix

    /// Writing the same filename twice produces two distinct URLs; the
    /// second URL's file contains the second call's input (not the first).
    @Test("writeTemporaryFile_collisionAppendsHHmmssSuffixOnce")
    func writeTemporaryFile_collisionAppendsHHmmssSuffixOnce() throws {
        let filename = "collision-\(UUID().uuidString).md"
        let firstBody = "first write\n"
        let secondBody = "second write\n"

        let firstURL = try TranscriptExporter.writeTemporaryFile(
            markdown: firstBody,
            filename: filename
        )
        let secondURL = try TranscriptExporter.writeTemporaryFile(
            markdown: secondBody,
            filename: filename
        )

        #expect(firstURL != secondURL)
        let firstReadback = try String(contentsOf: firstURL, encoding: .utf8)
        let secondReadback = try String(contentsOf: secondURL, encoding: .utf8)
        #expect(firstReadback == firstBody)
        #expect(secondReadback == secondBody)
        // The second URL's last path component carries the `-HHmmss`
        // suffix between the stem and the `.md` extension.
        let secondName = secondURL.lastPathComponent
        #expect(secondName != filename)
        #expect(secondName.hasSuffix(".md"))

        try? FileManager.default.removeItem(at: firstURL)
        try? FileManager.default.removeItem(at: secondURL)
    }
}
