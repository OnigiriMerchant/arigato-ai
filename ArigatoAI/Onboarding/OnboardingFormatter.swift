//
//  OnboardingFormatter.swift
//  ArigatoAI
//
//  Created by Jose Castell on 2026/05/17.
//

import Foundation

/// Pure-value formatter for ``OnboardingView``'s Screen 2 status line,
/// progress indicator, and continue-button label.
///
/// Extracted from the view body per the Phase-2 trio pattern
/// (``MeetingListRowFormatter`` Step 6, ``MeetingControlsFormatter``
/// Step 7, ``TranscriptSplitScreenFormatter`` Step 9a,
/// ``MeetingDetailFormatter`` Step 11) so every UI string is directly
/// testable without driving the SwiftUI runtime. Tests exercise the
/// static functions as plain expressions.
///
/// ## Isolation
///
/// `nonisolated` because the project's default isolation is
/// `MainActor` and this enum is a pure pile of static functions over
/// `Sendable` value types. Callable from any actor — production reads
/// happen on `@MainActor` from the view body; tests run on
/// `@MainActor` for convention parity.
///
/// ## Copy lock (UI #16)
///
/// Status strings are locked verbatim against the Phase 5 Group D UI
/// decisions doc. Modifying any of these strings requires a doc-update
/// + reviewer pass — they are part of the privacy-promise contract.
nonisolated enum OnboardingFormatter {
    /// Maps the bootstrapper's two loader states onto Screen 2's
    /// user-facing status string. Precedence: a failed Whisper load
    /// blocks app start entirely (the line reads "App can't start...");
    /// otherwise a failed LFM2 load surfaces the soft-fail message;
    /// otherwise the next active step wins (Whisper loading → LFM2
    /// downloading → warming → ready).
    ///
    /// The mapping is exhaustive against the actual enum cases in
    /// ``LoaderState`` and ``LFM2LoaderState``. ``LFM2LoaderState/idle``
    /// and ``LoaderState/idle`` collapse onto "Loading the speech
    /// model..." because the detached prewarm task always transitions
    /// out of `.idle` immediately on entry; the idle branch should be
    /// observationally unreachable but is handled for total coverage.
    ///
    /// - Parameters:
    ///   - whisperState: The Whisper loader's state mirrored on
    ///     ``AppBootstrapper/loaderState``.
    ///   - lfm2State: The LFM2 loader's state mirrored on
    ///     ``AppBootstrapper/lfm2LoaderState``.
    /// - Returns: The verbatim status string per UI #16.
    static func statusText(
        whisperState: LoaderState,
        lfm2State: LFM2LoaderState
    ) -> String {
        // Whisper failure is terminal — the app cannot start without
        // ASR. Surface the locked copy regardless of LFM2 state.
        if case .failed = whisperState {
            return "App can't start. The speech model failed to load."
        }

        // LFM2 failure is soft — the app can still run without
        // translation. Surface the locked LFM2-unavailable copy.
        if case .failed = lfm2State {
            return "Translation model unavailable. The app can still run but translations will not work."
        }

        // Whisper still loading (or hasn't started). Surface the
        // speech-model loading line.
        switch whisperState {
        case .idle, .loading:
            return "Loading the speech model..."
        case .loaded:
            break
        case .failed:
            // Handled above.
            return "App can't start. The speech model failed to load."
        }

        // Whisper loaded — LFM2's state drives the status line.
        switch lfm2State {
        case .idle, .loading, .downloading:
            return "Downloading the translation model..."
        case .loaded, .warming:
            return "Warming up..."
        case .ready:
            return "Ready."
        case .failed:
            // Handled above.
            return "Translation model unavailable. The app can still run but translations will not work."
        }
    }

    /// Returns the determinate-progress fraction in `[0.0, 1.0]` when
    /// LFM2 is actively downloading, or `nil` otherwise.
    ///
    /// Used by Screen 2's `ProgressView(value:)`. SwiftUI renders an
    /// indeterminate progress indicator (or nothing at all) when this
    /// returns `nil`, which is correct for the `loading` (pre-progress)
    /// and `warming` (compute-bound canary inference) phases.
    ///
    /// - Parameter lfm2State: The LFM2 loader's state.
    /// - Returns: The download fraction, or `nil` when no determinate
    ///   progress is available.
    static func progressFraction(lfm2State: LFM2LoaderState) -> Double? {
        switch lfm2State {
        case let .downloading(fraction):
            return fraction
        case .idle, .loading, .loaded, .warming, .ready, .failed:
            return nil
        }
    }

    /// The Continue button's user-facing label.
    ///
    /// Normally renders "Start translating" — the affirmative
    /// happy-path framing. Morphs to "Continue without translation"
    /// when LFM2 has failed, so the user understands what they're
    /// opting into (per UI #16 + the LFM2-broken-handling rationale in
    /// the Step 14 dispatch brief).
    ///
    /// - Parameter lfm2State: The LFM2 loader's state.
    /// - Returns: The verbatim button label per UI #16.
    static func continueButtonLabel(lfm2State: LFM2LoaderState) -> String {
        if case .failed = lfm2State {
            return "Continue without translation"
        }
        return "Start translating"
    }
}
