//
//  DesignTokens.swift
//  ArigatoAI
//
//  Created by Jose Castell on 2026/05/09.
//

import SwiftUI
import UIKit

// MARK: - Color tokens

//
// Canonical color palette for Arigato AI. These values are defined by the
// `swiftui-design` skill (see `.claude/skills/swiftui-design/SKILL.md`).
// Views should reference these tokens rather than redeclaring colors locally.

public extension Color {
    /// Muted red used as the chromatic accent for an active recording session.
    /// Source: `swiftui-design` skill, "Recording state" tokens.
    static let recordingActive = Color(red: 0.94, green: 0.27, blue: 0.27)

    /// Mid-gray used for the idle recording control. Source: `swiftui-design`
    /// skill, "Recording state" tokens.
    static let recordingIdle = Color(white: 0.5, opacity: 1.0)

    /// Primary surface color matching the system background. Source:
    /// `swiftui-design` skill, "Surfaces (Liquid Glass)" tokens.
    static let surfaceBackground = Color(.systemBackground)

    /// Track color for the VU meter capsule. Source: `swiftui-design` skill,
    /// derived for component patterns (meter track on neutral surface).
    static let meterTrack = Color(.tertiarySystemFill)
}
