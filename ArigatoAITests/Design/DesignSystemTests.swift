//
//  DesignSystemTests.swift
//  ArigatoAITests
//
//  Created by Jose Castell on 2026/05/16.
//

@testable import ArigatoAI
import SwiftUI
import Testing
import UIKit

/// Tests for the Group D Step 9b ``DesignSystem`` namespace.
///
/// Covers four contracts:
/// - The forwarder pattern: existing `Color.*` extensions resolve to the
///   namespace tokens (locked decision D9-2 option b).
/// - The four new tokens (``DesignSystem/Colors/recordingReady``,
///   ``DesignSystem/Colors/columnDivider``,
///   ``DesignSystem/Colors/timestampForeground``,
///   ``DesignSystem/Colors/returnArrowBackground``) resolve to the
///   intended system colors / RGB values.
/// - The new ``recordingReady`` token is chromatically distinct from
///   ``recordingActive`` (V3 #40 concern 1 closure — prevents
///   accidental hue collision).
/// - The ``TranscriptLiveView`` failed-state error-text region uses
///   the semantic `.secondary` foreground rather than red
///   ``Color.recordingActive`` (V3 #40 concern 2 closure).
@Suite("DesignSystem")
struct DesignSystemTests {
    // MARK: - 1. Hue distance: recordingReady vs recordingActive

    /// Asserts that ``DesignSystem/Colors/recordingReady`` and
    /// ``DesignSystem/Colors/recordingActive`` are chromatically distinct
    /// — specifically that their red and green channels differ
    /// substantially. Prevents an accidental "ready and active look the
    /// same" regression if the recordingReady RGB is ever tweaked.
    @Test
    func recordingReady_hueDistinctFromRecordingActive() {
        let ready = UIColor(DesignSystem.Colors.recordingReady)
        let active = UIColor(DesignSystem.Colors.recordingActive)

        var readyR: CGFloat = 0
        var readyG: CGFloat = 0
        var readyB: CGFloat = 0
        var readyA: CGFloat = 0
        ready.getRed(&readyR, green: &readyG, blue: &readyB, alpha: &readyA)

        var activeR: CGFloat = 0
        var activeG: CGFloat = 0
        var activeB: CGFloat = 0
        var activeA: CGFloat = 0
        active.getRed(&activeR, green: &activeG, blue: &activeB, alpha: &activeA)

        // recordingActive is RGB (0.94, 0.27, 0.27) — high red, low green.
        // recordingReady is RGB (0.26, 0.66, 0.45) — low red, high green.
        // Red-channel delta and green-channel delta should both be large.
        let redDelta = abs(readyR - activeR)
        let greenDelta = abs(readyG - activeG)
        #expect(redDelta > 0.5, "red channel difference too small: \(redDelta)")
        #expect(greenDelta > 0.3, "green channel difference too small: \(greenDelta)")
    }

    // MARK: - 2. Existing forwarders resolve to namespace tokens

    /// Asserts that the four existing `Color.*` extensions resolve to
    /// the same value as their ``DesignSystem/Colors/*`` namespace
    /// counterparts. Confirms the forwarder pattern (locked decision
    /// D9-2 option b) — every existing call site (e.g.,
    /// ``MeetingControlsView``, ``AudioCaptureView``,
    /// ``UndoStopToastView``) sees an identical color through the
    /// short-form spelling.
    @Test
    func existingForwarders_resolveToNamespaceTokens() {
        #expect(Color.recordingActive == DesignSystem.Colors.recordingActive)
        #expect(Color.recordingIdle == DesignSystem.Colors.recordingIdle)
        #expect(Color.surfaceBackground == DesignSystem.Colors.surfaceBackground)
        #expect(Color.meterTrack == DesignSystem.Colors.meterTrack)
    }

    // MARK: - 3. New tokens resolve to intended system colors

    /// Asserts that the three Step-9a-bound tokens
    /// (``columnDivider``, ``timestampForeground``,
    /// ``returnArrowBackground``) resolve to the intended UIKit
    /// semantic colors. Step 9a will consume these for the split-screen
    /// transcript divider, per-row timestamps, and jump-to-bottom
    /// affordance respectively.
    @Test
    func newSystemTokens_resolveToIntendedSemanticColors() {
        #expect(DesignSystem.Colors.columnDivider == Color(.separator))
        #expect(DesignSystem.Colors.timestampForeground == Color(.tertiaryLabel))
        #expect(DesignSystem.Colors.returnArrowBackground == Color(.tertiarySystemFill))
    }

    // MARK: - 4. Failed-state error text uses .secondary foreground

    /// V3 #40 concern 2 closure: asserts the failed-state error-text
    /// region in ``TranscriptLiveView`` uses the semantic `.secondary`
    /// foreground rather than the red ``Color/recordingActive`` token.
    ///
    /// The view body's `.foregroundStyle(.secondary)` is gated on the
    /// derived ``IndicatorChromeDisplay/warmupErrorTextUsesSecondaryForeground``
    /// flag — this test asserts the flag is `true` for the `.failed`
    /// loader state. The red warmup dot itself continues to use
    /// ``Color/recordingActive`` (verified inline) — the contract is
    /// that the adjacent error TEXT is secondary while the dot alone
    /// carries the failed-state hue.
    @Test
    @MainActor
    func transcriptLiveView_failedStateErrorText_usesSecondaryForeground() {
        let display = IndicatorChromeDisplay(
            currentLanguage: .ja,
            loaderState: .failed(.modelLoadFailed("stub failure"))
        )
        // The failed-state error text contract: text region uses the
        // semantic `.secondary` foreground; the warmup dot continues to
        // carry the failed semantic via `Color.recordingActive`.
        #expect(display.warmupErrorText != nil)
        #expect(display.warmupErrorTextUsesSecondaryForeground == true)
        #expect(display.warmupColor == Color.recordingActive)
    }

    // MARK: - 5. recordingReady replaces ad-hoc Color.green

    /// V3 #40 concern 1 closure: asserts the `.loaded` loader state
    /// surfaces ``DesignSystem/Colors/recordingReady`` as the warmup
    /// pill color rather than the prior ad-hoc `Color.green`. Pre-Step-9b
    /// this branch wrote `warmupColor = Color.green`; Step 9b replaces
    /// it with the canonical token so the hue is locked + nameable.
    @Test
    @MainActor
    func recordingReady_replacesAdHocColorGreen_onLoadedLoaderState() {
        let display = IndicatorChromeDisplay(
            currentLanguage: .ja,
            loaderState: .loaded(DesignSystemTestsStubClient())
        )
        #expect(display.warmupColor == DesignSystem.Colors.recordingReady)
        // Sanity: the new token is not equal to the prior ad-hoc green.
        #expect(display.warmupColor != Color.green)
    }
}

// MARK: - File-private stub WhisperClient

/// Trivial ``WhisperClient`` conformer used solely to populate
/// ``LoaderState/loaded(_:)`` in the recordingReady contract test.
/// Mirrors the pattern in ``TranscriptLiveViewTests/StubClient``; kept
/// file-private here to avoid sharing test-only types across suites.
private final nonisolated class DesignSystemTestsStubClient: WhisperClient, @unchecked Sendable {
    func prewarmModels() async throws {}
    func transcribe(audio _: [Float], anchorHostTime: UInt64) async throws -> WhisperWindowResult {
        WhisperWindowResult(language: "ja", windowAnchorHostTime: anchorHostTime, segments: [])
    }
}
