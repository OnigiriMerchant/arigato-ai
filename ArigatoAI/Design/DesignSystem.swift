//
//  DesignSystem.swift
//  ArigatoAI
//
//  Created by Jose Castell on 2026/05/16.
//

import SwiftUI

// MARK: - DesignSystem namespace

/// Canonical design-language namespace for Arigato AI.
///
/// Group D Step 9b introduces this namespace as a minimal consolidation
/// of the four Phase-4 ``Color`` tokens (``recordingActive``,
/// ``recordingIdle``, ``surfaceBackground``, ``meterTrack``) plus four
/// new tokens (``recordingReady``, ``columnDivider``,
/// ``timestampForeground``, ``returnArrowBackground``) that Step 9a's
/// split-screen transcript refactor will consume.
///
/// The existing ``Color`` extensions in `DesignTokens.swift` remain as
/// **thin forwarders** that resolve through this namespace, so every
/// existing call site (``MeetingControlsView``, ``AudioCaptureView``,
/// ``UndoStopToastView``, ``StartupErrorView``,
/// ``TranscriptLiveView``) keeps its current short-form spelling
/// (`Color.recordingActive` etc.) without source change.
///
/// Full V3 #22 visual identity (particles, glassmorphism, monospace
/// readouts) remains deferred to Phase 7 polish — Step 9b takes only the
/// minimal load-bearing slice (locked decision D9-1 option c, D9-2
/// option b).
enum DesignSystem {
    /// Color palette. Values intentionally preserve the existing RGB
    /// choices from the prior `DesignTokens.swift` `Color` extensions
    /// so the forwarder migration is byte-identical.
    enum Colors {
        // MARK: - Existing (preserved at exact RGB)

        /// Muted red used as the chromatic accent for an active recording
        /// session. Preserved from the prior `Color.recordingActive`
        /// extension (RGB `0.94, 0.27, 0.27`).
        static let recordingActive = Color(red: 0.94, green: 0.27, blue: 0.27)

        /// Mid-gray used for the idle recording control. Preserved from
        /// the prior `Color.recordingIdle` extension (`white: 0.5`).
        static let recordingIdle = Color(white: 0.5, opacity: 1.0)

        /// Primary surface color matching the system background. Preserved
        /// from the prior `Color.surfaceBackground` extension (resolves
        /// to `UIColor.systemBackground`).
        static let surfaceBackground = Color(.systemBackground)

        /// Track color for capsules / meter backgrounds. Preserved from
        /// the prior `Color.meterTrack` extension (resolves to
        /// `UIColor.tertiarySystemFill`).
        static let meterTrack = Color(.tertiarySystemFill)

        // MARK: - New tokens (Step 9b)

        /// Calm green used to signal "ready / loaded" states (e.g., the
        /// Whisper warmup pill on `.loaded`). Replaces the ad-hoc
        /// `Color.green` previously hard-coded in
        /// ``TranscriptLiveView`` (V3 #40 concern 1). RGB chosen for
        /// chromatic distance from ``recordingActive``'s red while
        /// maintaining WCAG AA contrast against the system background.
        static let recordingReady = Color(red: 0.26, green: 0.66, blue: 0.45)

        // MARK: - New tokens (Step 9a consumers — split-screen refactor)

        /// Vertical divider between the source / translation columns in
        /// the upcoming Step 9a split-screen transcript view. Resolves
        /// to `UIColor.separator` so the divider adapts to light/dark
        /// appearance automatically.
        static let columnDivider = Color(.separator)

        /// Foreground tint for per-row timestamp annotations in the
        /// Step 9a split-screen layout. Resolves to
        /// `UIColor.tertiaryLabel` for a calm, low-contrast read that
        /// pairs with primary transcript text.
        static let timestampForeground = Color(.tertiaryLabel)

        /// Background tint for the "return arrow" affordance that
        /// surfaces during scrollback in the Step 9a split-screen
        /// layout (jump-to-bottom on either column). Resolves to
        /// `UIColor.tertiarySystemFill` to match the existing capsule
        /// chrome style.
        static let returnArrowBackground = Color(.tertiarySystemFill)
    }
}
