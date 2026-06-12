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
///
/// **Phase 7 (Decision 5, 2026-05-31)** adds the source-led design-language
/// tokens: ``Colors/transcriptSource`` / ``Colors/transcriptTranslation``
/// (monochrome tonal hierarchy), ``Colors/metadataForeground``,
/// ``Colors/surfaceContent`` (solid — content is never glass), plus the
/// ``Typography`` and ``Spacing`` namespaces. Chrome Liquid Glass is applied
/// via the native `.glassEffect(.regular)` modifier at the view layer — there
/// is deliberately no glass colour/material token. See
/// `.claude/skills/swiftui-design/SKILL.md` and
/// `docs/PHASE_7_DESIGN_RESEARCH.md`.
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

        /// Foreground tint originally introduced for per-row timestamp
        /// annotations in the Step 9a split-screen layout. Resolves to
        /// `UIColor.tertiaryLabel`.
        ///
        /// **No production view consumes this token anymore.** The
        /// split-screen row converged its inline timestamp tint onto the
        /// canonical ``metadataForeground`` (same `.tertiaryLabel` value)
        /// per the Phase 7 metadata-role unification (D6). This token is
        /// **retained, not deleted**: `DesignSystemTests` still pins its
        /// value, and deleting a token is a wider token-catalog change than
        /// this bundle's scope. A future cleanup may remove it once that
        /// pin is migrated. Prefer ``metadataForeground`` for any new
        /// metadata tint.
        static let timestampForeground = Color(.tertiaryLabel)

        /// Background tint for the "return arrow" affordance that
        /// surfaces during scrollback in the Step 9a split-screen
        /// layout (jump-to-bottom on either column). Resolves to
        /// `UIColor.tertiarySystemFill` to match the existing capsule
        /// chrome style.
        static let returnArrowBackground = Color(.tertiarySystemFill)

        // MARK: - New tokens (Phase 7 Decision 5 — source-led design language)

        /// Foreground for the **source** (spoken-language) transcript line —
        /// the primary tonal level. Resolves to `UIColor.label` so the
        /// monochrome hierarchy adapts to light/dark and Increase Contrast
        /// automatically. Sits one tonal step above ``transcriptTranslation``.
        static let transcriptSource = Color(.label)

        /// Foreground for the **translation** transcript line — the secondary
        /// tonal level. Resolves to `UIColor.secondaryLabel`. Differs from
        /// ``transcriptSource`` by colour only (same size, same weight) per the
        /// locked monochrome source-led hierarchy (SKILL.md decision 1).
        static let transcriptTranslation = Color(.secondaryLabel)

        /// Foreground for the per-row metadata cluster (timestamp + JA/EN
        /// language tag) on the source line — the tertiary tonal level.
        /// Resolves to `UIColor.tertiaryLabel`. This is the canonical
        /// metadata-role token: the split-screen row's inline timestamp now
        /// tints through here too (D6 convergence), so the former
        /// ``timestampForeground`` (same `.tertiaryLabel` value) no longer
        /// has a production view consumer. Prefer this token for any new
        /// metadata tint.
        static let metadataForeground = Color(.tertiaryLabel)

        /// The **solid** content surface the transcript sits on. Resolves to
        /// `UIColor.systemBackground`. Content surfaces are solid, never glass
        /// (PHASE_7_DESIGN_RESEARCH.md collision A); replaces the removed
        /// placeholder `surfaceFloating`. Liquid Glass lives only on chrome.
        static let surfaceContent = Color(.systemBackground)
    }

    // MARK: - Typography (Phase 7 Decision 5)

    /// Typography roles for the design language. System fonts only — CJK is
    /// handled by iOS's automatic Hiragino Sans fallback, and SF Mono is
    /// reached via the native `.monospaced` system design (Dynamic-Type-aware,
    /// no bundled font). Geist Pixel (wordmark / app icon) is deferred to the
    /// brand-moment step and is intentionally absent here.
    enum Typography {
        /// Body text for both transcript lines (source and translation). The
        /// two lines share this font and differ by colour only
        /// (``Colors/transcriptSource`` vs ``Colors/transcriptTranslation``) —
        /// same size, same weight — per the locked monochrome tonal hierarchy.
        static let transcriptText: Font = .body

        /// Monospaced metadata text for the timestamp and JA/EN language tag.
        /// Uses native SF Mono via the `.monospaced` system design at the
        /// `.caption2` text style, so it scales with Dynamic Type and needs no
        /// bundled font.
        static let metadataText: Font = .system(.caption2, design: .monospaced)
    }

    // MARK: - Spacing (Phase 7 Decision 5)

    /// Spacing for the source-led transcript row rhythm. Minimal by design —
    /// only the values the row and its content inset actually need; no
    /// speculative scale. Values sit on the design-system spacing scale
    /// (SKILL.md).
    enum Spacing {
        /// Vertical gap between the source line, the translation line, and the
        /// metadata cluster within a single transcript row (`VStack` spacing).
        static let transcriptLineSpacing: CGFloat = 4

        /// Vertical padding applied to each transcript row.
        static let transcriptRowVerticalPadding: CGFloat = 8

        /// Horizontal inset from the screen edge for transcript content,
        /// matching the established view-edge padding.
        static let contentHorizontalInset: CGFloat = 20
    }
}
