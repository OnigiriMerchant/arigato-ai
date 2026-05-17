//
//  OnboardingFormatterTests.swift
//  ArigatoAITests
//
//  Created by Jose Castell on 2026/05/17.
//

@testable import ArigatoAI
import Foundation
import Testing

/// Tests for ``OnboardingFormatter`` — pure-value formatter for
/// Screen 2's status line, progress fraction, and continue-button
/// label.
///
/// All tests exercise the static functions directly. No SwiftUI
/// runtime required; mirrors the testing approach used by
/// ``MeetingListRowFormatter`` (Step 6), the formatter enum inside
/// ``MeetingControlsView`` (Step 7), and ``MeetingDetailFormatter``
/// (Step 11).
///
/// Marked `@MainActor` for project convention parity — the formatter
/// is `nonisolated`, so calls are legal from any context.
@Suite("OnboardingFormatter")
@MainActor
struct OnboardingFormatterTests {
    // MARK: - statusText

    @Test
    func statusText_whisperLoading_returnsLoadingTheSpeechModel() {
        let text = OnboardingFormatter.statusText(
            whisperState: .loading,
            lfm2State: .idle
        )
        #expect(text == "Loading the speech model...")
    }

    @Test
    func statusText_lfm2Downloading_returnsDownloadingTheTranslationModel() {
        // Whisper loaded; LFM2 mid-download.
        let text = OnboardingFormatter.statusText(
            whisperState: .loaded(StubWhisperClient()),
            lfm2State: .downloading(0.42)
        )
        #expect(text == "Downloading the translation model...")
    }

    @Test
    func statusText_lfm2Warming_returnsWarmingUp() {
        let text = OnboardingFormatter.statusText(
            whisperState: .loaded(StubWhisperClient()),
            lfm2State: .warming
        )
        #expect(text == "Warming up...")
    }

    @Test
    func statusText_lfm2Failed_returnsTranslationModelUnavailable() {
        let text = OnboardingFormatter.statusText(
            whisperState: .loaded(StubWhisperClient()),
            lfm2State: .failed(.modelLoadFailed("portal -1011"))
        )
        #expect(text == "Translation model unavailable. The app can still run but translations will not work.")
    }

    // MARK: - progressFraction

    @Test
    func progressFraction_lfm2Downloading_passthroughValue() {
        #expect(OnboardingFormatter.progressFraction(lfm2State: .downloading(0.0)) == 0.0)
        #expect(OnboardingFormatter.progressFraction(lfm2State: .downloading(0.5)) == 0.5)
        #expect(OnboardingFormatter.progressFraction(lfm2State: .downloading(1.0)) == 1.0)

        // Non-downloading states return nil so the view renders no
        // determinate progress bar.
        #expect(OnboardingFormatter.progressFraction(lfm2State: .idle) == nil)
        #expect(OnboardingFormatter.progressFraction(lfm2State: .loading) == nil)
        #expect(OnboardingFormatter.progressFraction(lfm2State: .warming) == nil)
        #expect(OnboardingFormatter.progressFraction(lfm2State: .ready) == nil)
        #expect(OnboardingFormatter.progressFraction(lfm2State: .failed(.modelLoadFailed("x"))) == nil)
    }
}

// MARK: - Test helpers

/// Minimal ``WhisperClient`` stand-in so the `.loaded(_:)` test cases
/// have a concrete payload without dragging in WhisperKit. Mirrors the
/// fileprivate `FakeWhisperClient` in `AppBootstrapperTests.swift`.
private final class StubWhisperClient: WhisperClient, @unchecked Sendable {
    func prewarmModels() async throws {}

    func transcribe(
        audio _: [Float],
        anchorHostTime: UInt64
    ) async throws -> WhisperWindowResult {
        WhisperWindowResult(
            language: "",
            windowAnchorHostTime: anchorHostTime,
            segments: []
        )
    }
}
