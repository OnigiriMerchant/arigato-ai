//
//  PrimaryActionButtonStyle.swift
//  ArigatoAI
//
//  Created by Jose Castell on 2026/05/31.
//

import SwiftUI

/// Reusable primary call-to-action button style — the **"Mono Key"** treatment
/// (Phase 7 Step 5).
///
/// A full-width capsule with a **solid monochrome** fill, for the single
/// primary action on a screen. Per the locked design language (color carries
/// semantic meaning only — see `.claude/skills/swiftui-design/SKILL.md`), a
/// primary CTA is **not** a recording-state signal, so it uses **no chromatic
/// accent**: no system `accentColor` blue, no `recordingActive` /
/// `recordingReady` red or green. Depth comes from the solid fill plus a press
/// scale, **never** a drop shadow.
///
/// Role-based name so it can be adopted by every primary action app-wide; in
/// Phase 7 Step 5 it is applied only to the two onboarding buttons.
///
/// ## States
/// - **Resting (enabled):** solid `.primary` capsule (black in light, white in
///   dark) with the label in the inverted surface colour
///   (`Color(.systemBackground)`), `.font(.headline)`, ≥ 44 pt tall.
/// - **Pressed:** scales to `0.97` and the fill drops to `.primary.opacity(0.85)`,
///   animated with `.spring(response: 0.3, dampingFraction: 0.7)`.
/// - **Disabled:** fill → `.primary.opacity(0.6)` (a dimmed key that reads as
///   "not ready"); the label stays the fully-opaque inverted surface colour.
///   The plan's literal `.secondary` fill was **rejected on contrast grounds**:
///   white-on-`.secondary` measures ≈ 3.4:1 in light mode (below the WCAG AA
///   4.5:1 floor for normal text). For `.primary.opacity(0.6)` the contrast is
///   measured against the **alpha-composite over `systemBackground`**, not the
///   standalone fill: in light mode the fill resolves to sRGB 102 (#666666 —
///   `0.6·black + 0.4·white`) under a white label → **5.74:1**; in dark mode it
///   resolves to sRGB 153 (#999999) under a black label → **7.37:1** (both
///   verified by sampling the rendered pixels, not estimated). This disabled
///   appearance is UI #16's sanctioned enabled/disabled exception for the
///   onboarding "Start translating" button.
///
/// ## Reduce Motion
/// The press scale + spring are **suppressed** under
/// `@Environment(\.accessibilityReduceMotion)`: the control stays static and
/// only the fill colour changes (a colour change is not motion), so press
/// feedback survives without animating size.
///
/// ## Implementation note
/// A `ButtonStyle` cannot read `@Environment(\.isEnabled)` or
/// `@Environment(\.accessibilityReduceMotion)` from `makeBody(configuration:)`
/// directly, so the body is delegated to the nested ``MonoKeyLabel`` view,
/// which can.
struct PrimaryActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        MonoKeyLabel(configuration: configuration)
    }

    /// Renders the configured label as a Mono Key capsule. Nested so it can
    /// read `@Environment(\.isEnabled)` and
    /// `@Environment(\.accessibilityReduceMotion)` — neither is reachable from
    /// ``PrimaryActionButtonStyle/makeBody(configuration:)``.
    private struct MonoKeyLabel: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            configuration.label
                .font(.headline)
                .foregroundStyle(Color(.systemBackground))
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(fill, in: Capsule())
                .scaleEffect(scale)
                .contentShape(Capsule())
                .animation(
                    reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.7),
                    value: configuration.isPressed
                )
        }

        /// Solid monochrome fill: full `.primary` at rest, `0.85` when pressed,
        /// `0.6` when disabled. No chromatic accent (locked colour rule).
        private var fill: Color {
            guard isEnabled else { return .primary.opacity(0.6) }
            return configuration.isPressed ? .primary.opacity(0.85) : .primary
        }

        /// Press shrink, suppressed when disabled or under Reduce Motion.
        private var scale: CGFloat {
            guard isEnabled, !reduceMotion else { return 1.0 }
            return configuration.isPressed ? 0.97 : 1.0
        }
    }
}

#if DEBUG
    #Preview("Primary action — enabled") {
        VStack(spacing: 24) {
            // Screen 1 CTA.
            Button("Get Started") {}
                .buttonStyle(PrimaryActionButtonStyle())

            // Screen 2 CTA (LFM2 ready / failed — both enabled).
            Button("Start translating") {}
                .buttonStyle(PrimaryActionButtonStyle())
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }

    #Preview("Primary action — disabled") {
        VStack(spacing: 24) {
            // Screen 2 CTA while models are still loading.
            Button("Start translating") {}
                .buttonStyle(PrimaryActionButtonStyle())
                .disabled(true)
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
#endif
