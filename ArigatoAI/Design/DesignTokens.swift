//
//  DesignTokens.swift
//  ArigatoAI
//
//  Created by Jose Castell on 2026/05/09.
//

import SwiftUI
import UIKit

// MARK: - Color tokens (forwarders)

//
// Top-level `Color` extensions resolve through ``DesignSystem/Colors``
// so the historical short-form spellings (`Color.recordingActive`,
// etc.) continue to work unchanged at every call site.
//
// Group D Step 9b introduced the ``DesignSystem`` namespace; this file
// kept its public surface as the original `Color.*` extensions so the
// migration is source-compatible (locked decision D9-2 option b).
// Every value here forwards to the canonical token without rewriting
// the RGB — the namespace owns the values, this file owns the
// short-form spellings.

public extension Color {
    /// Muted red used as the chromatic accent for an active recording
    /// session. Forwards to ``DesignSystem/Colors/recordingActive``.
    static var recordingActive: Color {
        DesignSystem.Colors.recordingActive
    }

    /// Mid-gray used for the idle recording control. Forwards to
    /// ``DesignSystem/Colors/recordingIdle``.
    static var recordingIdle: Color {
        DesignSystem.Colors.recordingIdle
    }

    /// Primary surface color matching the system background. Forwards to
    /// ``DesignSystem/Colors/surfaceBackground``.
    static var surfaceBackground: Color {
        DesignSystem.Colors.surfaceBackground
    }

    /// Track color for the VU meter capsule. Forwards to
    /// ``DesignSystem/Colors/meterTrack``.
    static var meterTrack: Color {
        DesignSystem.Colors.meterTrack
    }
}
