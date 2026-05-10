//
//  TranscriptLiveViewTests.swift
//  ArigatoAITests
//
//  Created by Jose Castell on 2026/05/10.
//

@testable import ArigatoAI
import Foundation
import Testing

// MARK: - Test fixtures

/// Builds a ``RoutedTranscript`` with explicit values for the locked
/// SEAM-2 fields. Defaults to a non-divergence "agreement" window so each
/// test names only the fields it cares about.
private func makeRouted(
    text: String = "sample",
    detected: SpokenLanguage = .ja,
    authoritative: SpokenLanguage = .ja,
    didFlip: Bool = false
) -> RoutedTranscript {
    RoutedTranscript(
        id: UUID(),
        text: text,
        detectedLanguage: detected,
        authoritativeLanguage: authoritative,
        didFlip: didFlip,
        windowAnchorHostTime: 0,
        windowStartSeconds: 0,
        windowEndSeconds: 5,
        isFinal: false
    )
}

// MARK: - Tests

@Suite("TranscriptLiveView display contracts")
@MainActor
struct TranscriptLiveViewTests {
    // MARK: D4-T-binding-detectedVsAuthoritative

    /// **D4-T-binding-detectedVsAuthoritative**. Locks the per-row binding
    /// contract: ``TranscriptRowDisplay`` reads
    /// ``RoutedTranscript/detectedLanguage`` (the per-window honest
    /// signal), NOT ``RoutedTranscript/authoritativeLanguage``. This
    /// matters during the SEAM-2 divergence window — exactly one window
    /// per language transition where the gate has observed the first
    /// disagreement but not yet flipped. If the row leaked
    /// `authoritativeLanguage` (or ``LanguageRouter/currentLanguage``)
    /// into its badge, the row would lie about what was actually heard
    /// for that window.
    ///
    /// Setup: a SEAM-2 divergence row (`detectedLanguage = .en`,
    /// `authoritativeLanguage = .ja`, `didFlip = false`) — gate is locked
    /// to JA, this single window detected EN, gate did not flip.
    ///
    /// Asserts:
    /// - badge string is "EN" (the detected language).
    /// - badge string is NOT "JA" (which would indicate it incorrectly
    ///   read `authoritativeLanguage`).
    /// - fallback marker is visible.
    @Test("D4-T-binding-detectedVsAuthoritative: row badge reads detectedLanguage, not authoritativeLanguage")
    func row_badge_reads_detectedLanguage_not_authoritative() {
        // SEAM-2 divergence: detected=en (the new language), authoritative=ja
        // (gate has not flipped yet because counter < N=2).
        let routed = makeRouted(
            text: "Good morning",
            detected: .en,
            authoritative: .ja,
            didFlip: false
        )

        let display = TranscriptRowDisplay(routed: routed)

        // The honest per-window signal is EN.
        #expect(display.badge == "EN")
        // The badge MUST NOT show the authoritative language. If this
        // assertion fires it means the row leaked `authoritativeLanguage`
        // (or worse, `LanguageRouter.currentLanguage`) into its badge.
        #expect(display.badge != "JA")
        // The divergence MUST surface as a fallback marker.
        #expect(display.showsFallbackMarker == true)
    }

    // MARK: D4-T-fallbackMarker-suppressedWhenAuthoritative

    /// **D4-T-fallbackMarker-suppressedWhenAuthoritative**. Locks the
    /// contract from the other side: when
    /// ``RoutedTranscript/detectedLanguage`` equals
    /// ``RoutedTranscript/authoritativeLanguage`` (an agreement window or
    /// a flip window), the row does NOT show a fallback marker.
    ///
    /// Two cases exercised in one body so the contract reads as a single
    /// invariant: agreement (both fields = ja) and post-flip (both = en).
    @Test("D4-T-fallbackMarker-suppressedWhenAuthoritative: agreement and flip windows hide marker")
    func row_fallbackMarker_hidden_when_detected_equals_authoritative() {
        // Agreement window.
        let agreement = makeRouted(detected: .ja, authoritative: .ja, didFlip: false)
        let agreementDisplay = TranscriptRowDisplay(routed: agreement)
        #expect(agreementDisplay.showsFallbackMarker == false)
        #expect(agreementDisplay.badge == "JA")

        // Flip window: detected=en flips authoritative to en. Detected
        // and authoritative both equal en for this window, so the marker
        // stays hidden — the flip itself is not a "fallback".
        let flip = makeRouted(detected: .en, authoritative: .en, didFlip: true)
        let flipDisplay = TranscriptRowDisplay(routed: flip)
        #expect(flipDisplay.showsFallbackMarker == false)
        #expect(flipDisplay.badge == "EN")
    }

    // MARK: D4-T-chrome-readsCurrentLanguage

    /// **D4-T-chrome-readsCurrentLanguage**. Locks the chrome-side binding
    /// contract: ``IndicatorChromeDisplay`` derives its language badge
    /// from the supplied `currentLanguage` (the router's authoritative
    /// signal), independent of any per-row data.
    ///
    /// Setup: chrome constructed with `currentLanguage: .ja` and a
    /// loader state of `.idle`. The test then constructs a chrome with
    /// `currentLanguage: .en` and asserts the badge tracks the
    /// authoritative input. There is no path for the chrome to observe a
    /// `RoutedTranscript`, so the contract holds by construction; the
    /// test makes that explicit so a future refactor can't break it
    /// silently.
    @Test("D4-T-chrome-readsCurrentLanguage: chrome badge tracks currentLanguage authoritative input")
    func chrome_badge_tracks_currentLanguage() {
        // Authoritative is JA — chrome should show "JA", not the dash.
        let chromeJA = IndicatorChromeDisplay(
            currentLanguage: .ja,
            loaderState: .idle
        )
        #expect(chromeJA.languageBadge == "JA")
        #expect(chromeJA.showsListeningHint == false)

        // Authoritative is EN — chrome should show "EN".
        let chromeEN = IndicatorChromeDisplay(
            currentLanguage: .en,
            loaderState: .idle
        )
        #expect(chromeEN.languageBadge == "EN")
        #expect(chromeEN.showsListeningHint == false)

        // No authoritative yet — dash + listening hint.
        let chromeNone = IndicatorChromeDisplay(
            currentLanguage: nil,
            loaderState: .idle
        )
        #expect(chromeNone.languageBadge == "—")
        #expect(chromeNone.showsListeningHint == true)
    }

    // MARK: D4-T-chrome-warmupStateMapping

    /// **D4-T-chrome-warmupStateMapping**. The warmup pill maps the four
    /// ``LoaderState`` cases to distinct labels and the failed case
    /// surfaces the underlying error description plus disables the record
    /// button. Locks the four-state contract so a future refactor can't
    /// silently drop one of the states.
    @Test("D4-T-chrome-warmupStateMapping: four loader states map to distinct chrome rendering")
    func chrome_warmupStateMapping_coversAllStates() {
        let idle = IndicatorChromeDisplay(currentLanguage: nil, loaderState: .idle)
        #expect(idle.warmupLabel == "idle")
        #expect(idle.recordButtonDisabled == false)
        #expect(idle.warmupErrorText == nil)

        let loading = IndicatorChromeDisplay(currentLanguage: nil, loaderState: .loading)
        #expect(loading.warmupLabel == "warming…")
        #expect(loading.recordButtonDisabled == false)

        // Failed must disable the record button AND surface error text.
        let failed = IndicatorChromeDisplay(
            currentLanguage: nil,
            loaderState: .failed(.modelLoadFailed("disk full"))
        )
        #expect(failed.warmupLabel == "failed")
        #expect(failed.recordButtonDisabled == true)
        // The error description rides through the LocalizedError surface.
        if let errorText = failed.warmupErrorText {
            #expect(errorText.contains("disk full"))
        } else {
            Issue.record("Expected warmupErrorText to surface the failure detail")
        }
    }

    // MARK: D4-T-emptyState

    /// **D4-T-emptyState**. When ``LanguageRouter/routedHistory`` is
    /// empty, the chrome's "listening…" hint surfaces alongside the
    /// dash badge. Constructing the chrome with `currentLanguage = nil`
    /// is the contract for "router has not yet seen a supported-code
    /// window", which is exactly the state the empty middle region
    /// covers. The middle region's empty placeholder is rendered by the
    /// view body branch on `routedHistory.isEmpty`; that branch is
    /// asserted on by the chrome's `showsListeningHint` here as the
    /// pure-value test surface.
    @Test("D4-T-emptyState: nil currentLanguage triggers listening hint")
    func chrome_emptyState_showsListeningHint() {
        let chrome = IndicatorChromeDisplay(currentLanguage: nil, loaderState: .loaded(StubClient()))
        #expect(chrome.languageBadge == "—")
        #expect(chrome.showsListeningHint == true)
        #expect(chrome.warmupLabel == "ready")
    }

    // MARK: D4-T-row-textPassthrough

    /// **D4-T-row-textPassthrough**. The row's display value carries the
    /// ``RoutedTranscript/text`` field through unchanged. Trivial, but
    /// locks the contract so a future refactor that adds e.g.
    /// truncation or trimming surfaces here.
    @Test("D4-T-row-textPassthrough: row text equals routed.text verbatim")
    func row_text_passthrough() {
        let text = "  おはようございます。Hello world.  "
        let routed = makeRouted(text: text, detected: .ja, authoritative: .ja)
        let display = TranscriptRowDisplay(routed: routed)
        #expect(display.text == text)
    }

    // MARK: D4-T-concern6 — listening hint lives in middle region only

    /// **D4-T-concern6**. End-of-group gate review (2026-05-10) surfaced
    /// that "listening…" was rendered in BOTH the chrome and the
    /// middle-region emptyState placeholder on first launch — visible
    /// duplication that read as "is the app stuck?". This test locks the
    /// fix: the "listening…" copy lives in exactly one place — the
    /// middle-region empty placeholder, exposed as
    /// ``TranscriptLiveView/emptyStateHintPrimary``. The chrome's
    /// ``IndicatorChromeDisplay`` still carries the `showsListeningHint`
    /// semantic flag (data-model honesty: the router has no language yet,
    /// preserved for accessibility / future use) but the view body no
    /// longer renders text for it.
    ///
    /// If a future refactor reintroduces a chrome property whose string
    /// value equals the middle-region listening copy, this test fires.
    @Test("D4-T-concern6: listening hint lives in middle region only, not duplicated in chrome")
    func concern6_listeningHint_livesInMiddleRegionOnly() {
        // The middle region's empty placeholder owns the listening copy.
        #expect(TranscriptLiveView.emptyStateHintPrimary == "listening…")

        // The chrome's data model still flags "no language yet" semantically.
        let chrome = IndicatorChromeDisplay(currentLanguage: nil, loaderState: .idle)
        #expect(chrome.showsListeningHint == true)
        #expect(chrome.languageBadge == "—")

        // Concern 6 contract: no chrome string property carries the
        // middle-region listening hint copy. If a future refactor
        // reintroduces a duplicating field (e.g. a chrome label that
        // also reads "listening…"), the assertion fires by name.
        let mirror = Mirror(reflecting: chrome)
        for child in mirror.children {
            if let stringValue = child.value as? String {
                #expect(
                    stringValue != TranscriptLiveView.emptyStateHintPrimary,
                    "Chrome property '\(child.label ?? "?")' duplicates the middle-region listening hint copy — Concern 6 regression"
                )
            }
            if let optionalString = child.value as? String?,
               let value = optionalString
            {
                #expect(
                    value != TranscriptLiveView.emptyStateHintPrimary,
                    "Chrome optional property '\(child.label ?? "?")' duplicates the middle-region listening hint copy — Concern 6 regression"
                )
            }
        }
    }
}

// MARK: - Stub WhisperClient for chrome warmup-state tests

/// Trivial conformer used to populate ``LoaderState/loaded(_:)`` in the
/// chrome warmup-state tests. The rendering surface only inspects the
/// case discriminator, so the wrapped client never has its methods
/// called.
private final nonisolated class StubClient: WhisperClient, @unchecked Sendable {
    func prewarmModels() async throws {}
    func transcribe(audio _: [Float], anchorHostTime: UInt64) async throws -> WhisperWindowResult {
        WhisperWindowResult(language: "ja", windowAnchorHostTime: anchorHostTime, segments: [])
    }
}
