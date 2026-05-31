//
//  OnboardingHeroView.swift
//  ArigatoAI
//
//  Created by Jose Castell on 2026/05/31.
//

import SwiftUI

/// The onboarding Screen-1 brand hero with its **"Terminal Power-On"** entrance
/// animation (Phase 7 Step 5 Checkpoint B — Variation A "Snappy").
///
/// The wordmark ("ARIGATO AI", Geist Pixel) types on left→right with a blinking
/// `.primary` block cursor that advances then dissolves; the tagline (Geist
/// Mono) then streams on word-by-word at `.secondary`. Because the Geist Pixel
/// glyphs are blocky pixel clusters, letter-by-letter type-on already reads as
/// "pixels powering on" — no sub-glyph masking. All monochrome; the timing is
/// owned by the pure ``HeroRevealFormatter``.
///
/// ## Stop-on-settle (the load-bearing correctness point)
/// The animated branch lives inside `TimelineView(.animation)`, which redraws
/// every display frame. A one-shot ``settleTask`` flips ``settled`` after
/// ``HeroRevealFormatter/total`` seconds, which swaps the body to the plain
/// static hero — **removing the `TimelineView` from the hierarchy so it stops
/// redrawing**. Without this the timeline would redraw forever (battery /
/// frame-time). The static branch (``staticHero``) reproduces today's hero
/// verbatim, so the settled state is pixel-identical to the pre-animation hero.
///
/// ## Scheduling assumption (Concurrency design discipline)
/// The only async work is the one-shot settle timer started by `.task`. It
/// **assumes** it runs to completion once: sleep ``HeroRevealFormatter/total``,
/// then set ``settled`` on the main actor. **If the view disappears first**
/// (e.g. the user taps "Get Started", advancing to Screen 2 and removing this
/// view) SwiftUI cancels the `.task`; `Task.sleep` throws `CancellationError`,
/// swallowed by `try?`, and ``settled`` stays `false` — harmless, the view is
/// gone. A fresh appearance starts a new ``start`` and replays the entrance.
/// The reveal *logic* (the only thing with interesting ordering) is the pure
/// ``HeroRevealFormatter``, exercised at its boundaries by
/// `HeroRevealFormatterTests`; the lifecycle-cancellation path is a thin
/// SwiftUI-owned timer not unit-tested here (would require XCUITest).
@MainActor
struct OnboardingHeroView: View {
    // MARK: - Content (source of truth for the hero copy)

    /// The wordmark. Length must equal ``HeroRevealFormatter/wordmarkLength``.
    static let wordmark = "ARIGATO AI"

    /// The tagline. Must equal `taglineWords.joined(separator: " ")`.
    static let tagline = "Translate Japanese ↔ English meetings in real time, fully on-device."

    /// The tagline split into reveal chunks. Count must equal
    /// ``HeroRevealFormatter/taglineWordCount``.
    static let taglineWords = [
        "Translate", "Japanese", "↔", "English", "meetings",
        "in", "real", "time,", "fully", "on-device.",
    ]

    static let wordmarkFont = Font.custom(
        BrandFont.geistPixelWordmark, size: 54, relativeTo: .largeTitle
    )
    static let taglineFont = Font.custom(
        BrandFont.geistMonoTagline, size: 16, relativeTo: .subheadline
    )

    // MARK: - State

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start: Date?
    @State private var settled = false

    init() {
        // Resolve the bundled Geist faces before first render (also makes them
        // resolve in Previews). Idempotent — see ``BrandFont``.
        BrandFont.registerIfNeeded()
    }

    var body: some View {
        Group {
            if reduceMotion || settled {
                StaticHero()
            } else {
                TimelineView(.animation) { context in
                    let elapsed = start.map { context.date.timeIntervalSince($0) } ?? 0
                    AnimatedHero(state: HeroRevealFormatter.state(at: elapsed))
                }
            }
        }
        .onAppear { if start == nil { start = .now } }
        .task {
            guard !reduceMotion else { return }
            try? await Task.sleep(for: .seconds(HeroRevealFormatter.total))
            settled = true
        }
    }
}

// MARK: - Static hero (settled / calm mode — pixel-identical to the prior hero)

/// The fully-revealed, cursor-free hero. Reproduces the Phase 7 Step 5 static
/// hero verbatim (same fonts, sizes, colours, copy, accessibility) so the
/// settled and reduced-motion states are pixel-identical to the pre-animation
/// hero.
private struct StaticHero: View {
    init() {
        BrandFont.registerIfNeeded()
    }

    var body: some View {
        VStack(spacing: 16) {
            Text(OnboardingHeroView.wordmark)
                .font(OnboardingHeroView.wordmarkFont)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .accessibilityAddTraits(.isHeader)
                .accessibilityLabel("Arigato AI")

            Text(OnboardingHeroView.tagline)
                .font(OnboardingHeroView.taglineFont)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}

// MARK: - Animated hero (one deterministic frame of the entrance)

/// Renders a single ``HeroRevealFormatter/State`` of the entrance. Pure of the
/// clock — the live view samples one of these per frame; previews pin fixed
/// states. Layout is **reserved to the final size** so nothing re-centres or
/// reflows as text reveals ("typing, not twitching"): the wordmark sizes to the
/// full word (hidden) and types into a leading overlay; the tagline always lays
/// out the full string and reveals per word via `.clear`→`.secondary` colour.
private struct AnimatedHero: View {
    let state: HeroRevealFormatter.State

    init(state: HeroRevealFormatter.State) {
        BrandFont.registerIfNeeded()
        self.state = state
    }

    var body: some View {
        VStack(spacing: 16) {
            wordmark
            tagline
        }
    }

    /// Reserved full-width frame (hidden full wordmark) with the revealed prefix
    /// + advancing block cursor overlaid leading. The reserved frame keeps the
    /// block centred (it never re-centres as letters land).
    private var wordmark: some View {
        let prefix = String(OnboardingHeroView.wordmark.prefix(state.wordmarkRevealed))
        return Text(OnboardingHeroView.wordmark)
            .font(OnboardingHeroView.wordmarkFont)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .hidden()
            .overlay(alignment: .leading) {
                HStack(alignment: .center, spacing: 4) {
                    Text(prefix)
                        .font(OnboardingHeroView.wordmarkFont)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Rectangle()
                        .fill(.primary)
                        .frame(width: 20, height: 40)
                        .opacity(state.cursorOpacity)
                        .accessibilityHidden(true)
                }
                // Natural width so the prefix never truncates; the cursor is
                // free to overhang the reserved frame (into the 32pt inset) at
                // full word rather than compressing "ARIGATO AI" to "ARIGATO…".
                .fixedSize(horizontal: true, vertical: false)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isHeader)
            .accessibilityLabel("Arigato AI")
    }

    /// Full tagline always laid out (fixed centred wrap); each word's colour is
    /// `.secondary` once revealed, `.clear` before — so the layout never
    /// reflows and the settled all-`.secondary` state matches the static hero.
    private var tagline: some View {
        Text(Self.taglineAttributed(wordsRevealed: state.taglineWordsRevealed))
            .font(OnboardingHeroView.taglineFont)
            .multilineTextAlignment(.center)
            .accessibilityLabel(OnboardingHeroView.tagline)
    }

    /// Builds the tagline as an `AttributedString` with per-word colour driven
    /// by `wordsRevealed`. Hidden words are `.clear` (laid out, transparent) so
    /// the paragraph keeps its final wrap throughout the reveal.
    static func taglineAttributed(wordsRevealed: Int) -> AttributedString {
        var out = AttributedString()
        let words = OnboardingHeroView.taglineWords
        for (index, word) in words.enumerated() {
            let isLast = index == words.count - 1
            var piece = AttributedString(isLast ? word : word + " ")
            piece.foregroundColor = index < wordsRevealed ? Color.secondary : Color.clear
            out += piece
        }
        return out
    }
}

// MARK: - Previews

#if DEBUG
    /// Hosts a hero view centred on a full screen background, matching the Screen-1
    /// layout (horizontal inset 32) so frame-strip stills read like the real screen.
    private struct HeroPreviewHost<Content: View>: View {
        @ViewBuilder var content: Content
        var body: some View {
            content
                .padding(.horizontal, 32)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemBackground))
        }
    }

    #Preview("Frame 1 — pre-roll cursor") {
        HeroPreviewHost { AnimatedHero(state: HeroRevealFormatter.state(at: 0.12)) }
    }

    #Preview("Frame 2 — wordmark ~30%") {
        HeroPreviewHost { AnimatedHero(state: HeroRevealFormatter.state(at: 0.54)) }
    }

    #Preview("Frame 3 — wordmark ~70%") {
        HeroPreviewHost { AnimatedHero(state: HeroRevealFormatter.state(at: 0.75)) }
    }

    #Preview("Frame 4 — wordmark complete + cursor") {
        HeroPreviewHost { AnimatedHero(state: HeroRevealFormatter.state(at: 1.00)) }
    }

    #Preview("Frame 5 — tagline mid") {
        HeroPreviewHost { AnimatedHero(state: HeroRevealFormatter.state(at: 1.45)) }
    }

    #Preview("Frame 6 — settled (static)") {
        HeroPreviewHost { StaticHero() }
    }

    #Preview("Live entrance") {
        HeroPreviewHost { OnboardingHeroView() }
    }
#endif
