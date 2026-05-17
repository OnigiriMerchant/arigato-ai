//
//  SettingsFormatter.swift
//  ArigatoAI
//
//  Created by Jose Castell on 2026/05/17.
//

import Foundation

/// Pure-value formatter for the Settings surface (UI #19).
///
/// Mirrors the Phase-2 trio convention (V3 `985aef6`): every view
/// extracts user-visible string composition into a stateless enum so
/// the rendering is unit-testable without SwiftUI runtime.
///
/// ## Isolation
/// Explicit `nonisolated` per the V3 "project-default-isolation
/// pattern" entry (`5067613` family). Without the annotation the
/// project's `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` build setting
/// would silently main-actor-isolate this enum, forcing every caller
/// (including the off-main ``StorageStatsProviding``) to hop. The 5th
/// recurrence of the pattern; CLAUDE.md update is V3-tracked.
nonisolated enum SettingsFormatter {
    /// Formats a byte count for the Storage section's "LFM2 cache
    /// size" row.
    ///
    /// Wraps `ByteCountFormatter` with `.useAll` allowed units +
    /// `.file` count style — matches the system pattern shown by
    /// Settings ▸ General ▸ iPhone Storage. Zero is reported via the
    /// formatter's localized "Zero bytes" string rather than a custom
    /// `"0 bytes"` constant, so the surface stays consistent with
    /// other byte-count UIs in the OS.
    ///
    /// - Parameter count: Cumulative byte size. `Int64` because
    ///   `ByteCountFormatter.string(fromByteCount:)` takes `Int64`.
    /// - Returns: Localized byte-count string.
    static func bytes(_ count: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = .useAll
        formatter.countStyle = .file
        return formatter.string(fromByteCount: count)
    }

    /// Formats a transcript count for the Storage section's
    /// "Transcripts" row.
    ///
    /// Hand-rolled English pluralization rather than `String.localized(...)`
    /// stringsdict — the project is en-only for MVP 1 and the four
    /// cases (0 / 1 / N) compose cleanly as a switch.
    ///
    /// - Parameter count: Non-negative meeting count.
    /// - Returns: `"No transcripts"` for 0, `"1 transcript"` for 1,
    ///   `"\(N) transcripts"` for N ≥ 2.
    static func transcriptCountLabel(_ count: Int) -> String {
        switch count {
        case 0: return "No transcripts"
        case 1: return "1 transcript"
        default: return "\(count) transcripts"
        }
    }

    /// Formats the app version string for the About section's
    /// "Version" row.
    ///
    /// Reads `CFBundleShortVersionString` (marketing version, e.g.
    /// `"1.2"`) + `CFBundleVersion` (build number, e.g. `"45"`) from
    /// the supplied bundle's `infoDictionary`. Returns
    /// `"Arigato AI X.Y (Z)"` when both keys are present; falls back
    /// to `"Arigato AI"` (no version suffix) when either key is
    /// missing per the dispatch brief's pre-authorized STOP #1.
    ///
    /// - Parameter bundle: Defaults to `.main`. Tests inject a
    ///   synthetic bundle stand-in via a small wrapper.
    /// - Returns: Versioned product string, or `"Arigato AI"` if keys
    ///   are absent.
    static func versionString(bundle: Bundle = .main) -> String {
        let info = bundle.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String
        let build = info?["CFBundleVersion"] as? String
        guard let short, let build, !short.isEmpty, !build.isEmpty else {
            return "Arigato AI"
        }
        return "Arigato AI \(short) (\(build))"
    }
}
