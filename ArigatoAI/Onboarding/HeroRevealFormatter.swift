//
//  HeroRevealFormatter.swift
//  ArigatoAI
//
//  Created by Jose Castell on 2026/05/31.
//

import Foundation

/// Pure, deterministic timing model for the onboarding hero's **"Terminal
/// Power-On"** entrance (Phase 7 Step 5 Checkpoint B — Variation A "Snappy").
///
/// Maps `elapsed` seconds since the entrance began to a ``State`` describing how
/// much of the wordmark + tagline is revealed and the block cursor's state.
/// Extracted as a pure type — like ``OnboardingFormatter`` /
/// `MeetingControlsFormatter` — so the reveal schedule is unit-testable
/// independently of `TimelineView`. ``OnboardingHeroView`` samples
/// ``state(at:)`` once per frame inside a `TimelineView(.animation)` and stops
/// sampling once settled (the view's stop-on-settle swap).
///
/// ## Schedule (seconds, Variation A — total ≈ 1.8 s)
/// - `[0, preRollEnd)` — pre-roll: empty wordmark; the block cursor blinks once
///   ("the terminal wakes").
/// - `[preRollEnd, wordmarkEnd)` — wordmark types on, one char per ``perChar``;
///   cursor solid, advancing at the trailing edge.
/// - `[wordmarkEnd, cursorGone)` — wordmark complete; cursor **dissolves**
///   (opacity 1 → 0). No persistent blink — the settled screen is fully static.
/// - `[taglineStart, taglineEnd)` — tagline streams on word-by-word.
/// - `>= total` — **settled**: full wordmark + full tagline, no cursor.
///   Pixel-identical to the pre-animation static hero.
///
/// Counts only — this type holds **no content strings**. The wordmark length
/// (``wordmarkLength``) and tagline word count (``taglineWordCount``) are
/// invariants verified against ``OnboardingHeroView``'s actual content in
/// `HeroRevealFormatterTests`.
enum HeroRevealFormatter {
    // MARK: - Schedule constants (seconds)

    /// End of the pre-roll beat (cursor blink before typing starts).
    static let preRollEnd: Double = 0.30

    /// Per-character cadence of the wordmark type-on.
    static let perChar: Double = 0.07

    /// Character count of the wordmark ("ARIGATO AI").
    static let wordmarkLength = 10

    /// Duration of the cursor's post-wordmark dissolve.
    static let cursorDissolve: Double = 0.15

    /// Duration of the tagline word-stream.
    static let taglineDuration: Double = 0.60

    /// Word-chunk count of the tagline.
    static let taglineWordCount = 10

    /// Trailing buffer after the tagline completes, before `settled` flips.
    static let settleTail: Double = 0.05

    /// Time the wordmark finishes typing.
    static let wordmarkEnd = preRollEnd + Double(wordmarkLength) * perChar // 1.00

    /// Time the wordmark cursor has fully dissolved.
    static let cursorGone = wordmarkEnd + cursorDissolve // 1.15

    /// Time the tagline begins streaming (after the cursor is gone).
    static let taglineStart = cursorGone // 1.15

    /// Time the tagline finishes streaming.
    static let taglineEnd = taglineStart + taglineDuration // 1.75

    /// Total entrance duration; at/after this the hero is settled & static.
    static let total = taglineEnd + settleTail // 1.80

    /// Pre-roll cursor blink period.
    static let blinkPeriod: Double = 0.40

    /// Fraction of ``blinkPeriod`` the cursor is "on" (opacity 1).
    static let blinkOnFraction: Double = 0.6

    // MARK: - State

    /// A snapshot of the hero entrance at one instant.
    struct State: Equatable {
        /// Number of wordmark characters revealed (`0...wordmarkLength`).
        var wordmarkRevealed: Int
        /// Block-cursor opacity; `0` once dissolved / gone.
        var cursorOpacity: Double
        /// Cursor's advancing position — it sits after this many wordmark
        /// characters (`0` during pre-roll, `wordmarkRevealed` while typing,
        /// `wordmarkLength` during dissolve).
        var cursorIndex: Int
        /// Number of tagline words revealed (`0...taglineWordCount`).
        var taglineWordsRevealed: Int
        /// `true` only at/after ``total`` — the fully static settled hero.
        var isSettled: Bool
    }

    /// The fully-revealed, cursor-free end state. The view renders this for the
    /// reduce-motion calm mode and after stop-on-settle; it is the same content
    /// as the pre-animation static hero.
    static let settledState = State(
        wordmarkRevealed: wordmarkLength,
        cursorOpacity: 0,
        cursorIndex: wordmarkLength,
        taglineWordsRevealed: taglineWordCount,
        isSettled: true
    )

    // MARK: - Reveal

    /// Computes the reveal state at `elapsed` seconds since the entrance began.
    /// Deterministic and side-effect-free; negative inputs clamp to `0`.
    static func state(at elapsed: Double) -> State {
        let t = max(0, elapsed)

        if t >= total { return settledState }

        // Wordmark reveal count.
        let wordmarkRevealed: Int
        if t < preRollEnd {
            wordmarkRevealed = 0
        } else if t < wordmarkEnd {
            wordmarkRevealed = min(wordmarkLength, Int((t - preRollEnd) / perChar) + 1)
        } else {
            wordmarkRevealed = wordmarkLength
        }

        // Cursor opacity + advancing position.
        let cursorOpacity: Double
        let cursorIndex: Int
        if t < preRollEnd {
            let phase = t.truncatingRemainder(dividingBy: blinkPeriod) / blinkPeriod
            cursorOpacity = phase < blinkOnFraction ? 1 : 0
            cursorIndex = 0
        } else if t < wordmarkEnd {
            cursorOpacity = 1
            cursorIndex = wordmarkRevealed
        } else if t < cursorGone {
            cursorOpacity = 1 - (t - wordmarkEnd) / cursorDissolve
            cursorIndex = wordmarkLength
        } else {
            cursorOpacity = 0
            cursorIndex = wordmarkLength
        }

        // Tagline word reveal.
        let taglineWordsRevealed: Int
        if t < taglineStart {
            taglineWordsRevealed = 0
        } else if t < taglineEnd {
            let perWord = taglineDuration / Double(taglineWordCount)
            taglineWordsRevealed = min(taglineWordCount, Int((t - taglineStart) / perWord) + 1)
        } else {
            taglineWordsRevealed = taglineWordCount
        }

        return State(
            wordmarkRevealed: wordmarkRevealed,
            cursorOpacity: cursorOpacity,
            cursorIndex: cursorIndex,
            taglineWordsRevealed: taglineWordsRevealed,
            isSettled: false
        )
    }
}
