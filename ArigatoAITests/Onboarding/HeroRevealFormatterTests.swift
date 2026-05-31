//
//  HeroRevealFormatterTests.swift
//  ArigatoAITests
//
//  Created by Jose Castell on 2026/05/31.
//

@testable import ArigatoAI
import Foundation
import Testing

/// Tests for ``HeroRevealFormatter`` — the pure timing model behind the
/// onboarding hero's "Terminal Power-On" entrance.
///
/// Exercises the deterministic ``HeroRevealFormatter/state(at:)`` at the key
/// schedule boundaries (pre-roll, mid-wordmark, wordmark-complete, cursor
/// dissolve/gone, mid-tagline, settled) plus the content invariants that tie
/// the formatter's counts to ``OnboardingHeroView``'s actual copy. No SwiftUI
/// runtime required; mirrors ``OnboardingFormatterTests``.
@Suite("HeroRevealFormatter")
@MainActor
struct HeroRevealFormatterTests {
    // MARK: - Pre-roll

    @Test
    func preRoll_cursorBlinksOn_noWordmark() {
        // 0.10s → blink phase 0.25 < onFraction 0.6 → cursor on, nothing typed.
        let s = HeroRevealFormatter.state(at: 0.10)
        #expect(s.wordmarkRevealed == 0)
        #expect(s.cursorOpacity == 1)
        #expect(s.cursorIndex == 0)
        #expect(s.taglineWordsRevealed == 0)
        #expect(s.isSettled == false)
    }

    @Test
    func preRoll_cursorBlinksOff_inOffWindow() {
        // 0.27s → blink phase 0.675 >= 0.6 → cursor off (the wake blink).
        let s = HeroRevealFormatter.state(at: 0.27)
        #expect(s.cursorOpacity == 0)
        #expect(s.wordmarkRevealed == 0)
    }

    @Test
    func negativeElapsed_clampsToStart() {
        let s = HeroRevealFormatter.state(at: -1.0)
        #expect(s.wordmarkRevealed == 0)
        #expect(s.isSettled == false)
    }

    // MARK: - Wordmark type-on

    @Test
    func wordmarkStart_firstCharImmediately() {
        // At preRollEnd the first character is showing, cursor solid + advancing.
        let s = HeroRevealFormatter.state(at: HeroRevealFormatter.preRollEnd)
        #expect(s.wordmarkRevealed == 1)
        #expect(s.cursorOpacity == 1)
        #expect(s.cursorIndex == 1)
    }

    @Test
    func midWordmark_revealsProportionally() {
        // 0.54s → (0.54-0.30)/0.07 = 3.43 → 3 + 1 = 4 chars ("ARIG").
        let s = HeroRevealFormatter.state(at: 0.54)
        #expect(s.wordmarkRevealed == 4)
        #expect(s.cursorOpacity == 1)
        #expect(s.cursorIndex == 4)
        #expect(s.taglineWordsRevealed == 0)
        #expect(s.isSettled == false)
    }

    @Test
    func wordmarkComplete_atWordmarkEnd_fullWordCursorSolid() {
        // 1.00s → full wordmark; cursor at full opacity, dissolve just beginning.
        let s = HeroRevealFormatter.state(at: HeroRevealFormatter.wordmarkEnd)
        #expect(s.wordmarkRevealed == HeroRevealFormatter.wordmarkLength)
        #expect(s.cursorOpacity == 1)
        #expect(s.cursorIndex == HeroRevealFormatter.wordmarkLength)
        #expect(s.taglineWordsRevealed == 0)
    }

    // MARK: - Cursor dissolve / gone

    @Test
    func cursorDissolve_halfway_isHalfOpacity() {
        // Midpoint of the 0.15s dissolve → opacity ≈ 0.5.
        let mid = HeroRevealFormatter.wordmarkEnd + HeroRevealFormatter.cursorDissolve / 2
        let s = HeroRevealFormatter.state(at: mid)
        #expect(abs(s.cursorOpacity - 0.5) < 0.0001)
        #expect(s.wordmarkRevealed == HeroRevealFormatter.wordmarkLength)
    }

    @Test
    func cursorGone_afterDissolve_taglineBegins() {
        // At taglineStart (== cursorGone) the cursor is gone and word 1 shows.
        let s = HeroRevealFormatter.state(at: HeroRevealFormatter.taglineStart)
        #expect(s.cursorOpacity == 0)
        #expect(s.taglineWordsRevealed == 1)
        #expect(s.wordmarkRevealed == HeroRevealFormatter.wordmarkLength)
    }

    // MARK: - Tagline stream

    @Test
    func midTagline_revealsWordsProportionally_noCursor() {
        // 1.45s → (1.45-1.15)/0.06 = 5.0 → 5 + 1 = 6 words; cursor already gone.
        let s = HeroRevealFormatter.state(at: 1.45)
        #expect(s.taglineWordsRevealed == 6)
        #expect(s.cursorOpacity == 0)
        #expect(s.wordmarkRevealed == HeroRevealFormatter.wordmarkLength)
        #expect(s.isSettled == false)
    }

    // MARK: - Settled

    @Test
    func settled_atTotal_fullStaticNoCursor() {
        let s = HeroRevealFormatter.state(at: HeroRevealFormatter.total)
        #expect(s == HeroRevealFormatter.settledState)
        #expect(s.wordmarkRevealed == HeroRevealFormatter.wordmarkLength)
        #expect(s.taglineWordsRevealed == HeroRevealFormatter.taglineWordCount)
        #expect(s.cursorOpacity == 0)
        #expect(s.isSettled == true)
    }

    @Test
    func settled_wellAfterTotal_staysSettled() {
        #expect(HeroRevealFormatter.state(at: 5.0) == HeroRevealFormatter.settledState)
    }

    // MARK: - Monotonicity (reveal never regresses)

    @Test
    func revealCounts_areMonotonicAcrossTheSweep() {
        var lastWord = 0
        var lastTagline = 0
        var t = 0.0
        while t <= HeroRevealFormatter.total + 0.1 {
            let s = HeroRevealFormatter.state(at: t)
            #expect(s.wordmarkRevealed >= lastWord)
            #expect(s.taglineWordsRevealed >= lastTagline)
            lastWord = s.wordmarkRevealed
            lastTagline = s.taglineWordsRevealed
            t += 0.01
        }
        #expect(lastWord == HeroRevealFormatter.wordmarkLength)
        #expect(lastTagline == HeroRevealFormatter.taglineWordCount)
    }

    // MARK: - Schedule sanity

    @Test
    func schedule_boundariesAddUp() {
        #expect(abs(HeroRevealFormatter.wordmarkEnd - 1.00) < 0.0001)
        #expect(abs(HeroRevealFormatter.cursorGone - 1.15) < 0.0001)
        #expect(abs(HeroRevealFormatter.total - 1.80) < 0.0001)
    }

    // MARK: - Content invariants (formatter counts match the actual hero copy)

    @Test
    func wordmarkLength_matchesContent() {
        #expect(OnboardingHeroView.wordmark.count == HeroRevealFormatter.wordmarkLength)
    }

    @Test
    func taglineWordCount_matchesContent() {
        #expect(OnboardingHeroView.taglineWords.count == HeroRevealFormatter.taglineWordCount)
    }

    @Test
    func taglineWords_joinToTheFullTagline() {
        #expect(
            OnboardingHeroView.taglineWords.joined(separator: " ") == OnboardingHeroView.tagline
        )
    }
}
