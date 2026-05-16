//
//  MeetingTitleGeneratorTests.swift
//  ArigatoAITests
//
//  Created by Jose Castell on 2026/05/16.
//

@testable import ArigatoAI
import Foundation
import Testing

/// Tests for ``MeetingTitleGenerator`` — the MVP 1 path of Group D UI
/// decision #12. The Phase 6+ Foundation Models replacement is out of
/// scope for these tests.
///
/// All timestamps use a pinned `TimeZone(identifier: "America/Los_Angeles")`
/// + `en_US_POSIX` locale so the formatter output is deterministic
/// regardless of host machine settings.
@Suite("MeetingTitleGenerator")
@MainActor
struct MeetingTitleGeneratorTests {
    /// A deterministic date: 2026-05-16 (Saturday) 14:22:00 PDT.
    /// `en_US_POSIX` + LA timezone → `"Sat 2:22 PM"`.
    private static var fixedDate: Date {
        var comps = DateComponents()
        comps.year = 2026
        comps.month = 5
        comps.day = 16
        comps.hour = 14
        comps.minute = 22
        comps.second = 0
        comps.timeZone = TimeZone(identifier: "America/Los_Angeles")
        let calendar = Calendar(identifier: .gregorian)
        guard let date = calendar.date(from: comps) else {
            // No force-unwraps in production code; in test setup a
            // construction failure here is a developer error in the
            // fixture, not an environmental issue.
            return Date(timeIntervalSince1970: 0)
        }
        return date
    }

    private static var fixedTimeZone: TimeZone {
        TimeZone(identifier: "America/Los_Angeles") ?? .gmt
    }

    /// `makeTitle` with a non-nil sentence shorter than the truncation
    /// budget returns `"<timestamp> — <sentence>"` verbatim.
    @Test func makeTitle_withShortSentence_appendsVerbatim() {
        let title = MeetingTitleGenerator.makeTitle(
            startedAt: Self.fixedDate,
            firstEnglishSentence: "Hello there",
            timeZone: Self.fixedTimeZone
        )
        #expect(title == "Sat 2:22 PM — Hello there")
    }

    /// `makeTitle` truncates an over-budget sentence to exactly 40
    /// characters total — 39 visible characters + one trailing
    /// ellipsis. The bare-timestamp portion is unaffected.
    @Test func makeTitle_withSentence_truncatesAt40CharsWithEllipsis() {
        // 60 'a' characters — well over the 40-char budget.
        let longSentence = String(repeating: "a", count: 60)
        let title = MeetingTitleGenerator.makeTitle(
            startedAt: Self.fixedDate,
            firstEnglishSentence: longSentence,
            timeZone: Self.fixedTimeZone
        )
        // Title splits on " — ". Tail is the sentence portion.
        let parts = title.components(separatedBy: " — ")
        #expect(parts.count == 2, "Title should split into timestamp + sentence")
        guard parts.count == 2 else { return }
        #expect(parts[0] == "Sat 2:22 PM")
        let sentencePart = parts[1]
        #expect(sentencePart.count == 40, "Truncated sentence should be exactly 40 chars; got \(sentencePart.count)")
        #expect(sentencePart.last == "…")
    }

    /// `makeTitle` with a `nil` sentence returns just the bare
    /// timestamp — no separator, no ellipsis.
    @Test func makeTitle_withNilSentence_returnsBareTimestamp() {
        let title = MeetingTitleGenerator.makeTitle(
            startedAt: Self.fixedDate,
            firstEnglishSentence: nil,
            timeZone: Self.fixedTimeZone
        )
        #expect(title == "Sat 2:22 PM")
    }

    /// Empty-string and whitespace-only sentences are treated as the
    /// "no sentence" fallback — bare timestamp only.
    @Test func makeTitle_withEmptySentence_returnsBareTimestamp() {
        let emptyTitle = MeetingTitleGenerator.makeTitle(
            startedAt: Self.fixedDate,
            firstEnglishSentence: "",
            timeZone: Self.fixedTimeZone
        )
        let whitespaceTitle = MeetingTitleGenerator.makeTitle(
            startedAt: Self.fixedDate,
            firstEnglishSentence: "   \t  \n  ",
            timeZone: Self.fixedTimeZone
        )
        #expect(emptyTitle == "Sat 2:22 PM")
        #expect(whitespaceTitle == "Sat 2:22 PM")
    }

    /// Multi-line / multi-whitespace input collapses to single-spaced
    /// output in the title's sentence portion.
    @Test func makeTitle_withMultilineSentence_collapsesWhitespace() {
        let title = MeetingTitleGenerator.makeTitle(
            startedAt: Self.fixedDate,
            firstEnglishSentence: "Hello\nworld\t \tagain",
            timeZone: Self.fixedTimeZone
        )
        #expect(title == "Sat 2:22 PM — Hello world again")
    }
}
