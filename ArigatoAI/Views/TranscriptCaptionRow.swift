//
//  TranscriptCaptionRow.swift
//  ArigatoAI
//
//  Created by Jose Castell on 2026/05/31.
//

import SwiftUI

/// A single **source-led** transcript caption row (Phase 7 Decision 6).
///
/// Leads with the spoken-language ``source`` text at the primary tonal
/// level, renders the ``translation`` beneath it at the secondary tonal
/// level (a **colour-only** difference — same size, same weight, per the
/// locked monochrome hierarchy), and closes with a tertiary metadata
/// cluster: an SF Mono language tag + timestamp.
///
/// All styling flows from the Phase 7 ``DesignSystem`` tokens —
/// ``DesignSystem/Colors/transcriptSource`` /
/// ``DesignSystem/Colors/transcriptTranslation`` /
/// ``DesignSystem/Colors/metadataForeground``,
/// ``DesignSystem/Typography/transcriptText`` /
/// ``DesignSystem/Typography/metadataText``, and ``DesignSystem/Spacing``.
/// There is **no bundled font**: SF Mono is reached via the native
/// `.monospaced` system design, so the row scales with Dynamic Type.
///
/// Extracted as a standalone component so the live-view restyle can reuse
/// it later; for now it renders only in ``MeetingDetailView``. The row is
/// solid — it carries no glass (glass is chrome-only per Phase 7
/// Decision 6 / `docs/PHASE_7_DESIGN_RESEARCH.md` collision A).
@MainActor
struct TranscriptCaptionRow: View {
    /// The spoken-language (source) text — leads the row, primary tonal level.
    let source: String

    /// The translation — secondary tonal level, colour-only difference.
    let translation: String

    /// The row's source language as a display tag (`"JA"` / `"EN"`).
    let languageTag: String

    /// Pre-formatted `HH:mm:ss` timestamp string.
    let timestamp: String

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.transcriptLineSpacing) {
            Text(source)
                .font(DesignSystem.Typography.transcriptText)
                .foregroundStyle(DesignSystem.Colors.transcriptSource)

            Text(translation)
                .font(DesignSystem.Typography.transcriptText)
                .foregroundStyle(DesignSystem.Colors.transcriptTranslation)

            // Tertiary metadata cluster: SF Mono language tag + timestamp.
            // Reuses the 4pt line-spacing token for the tight horizontal gap.
            HStack(spacing: DesignSystem.Spacing.transcriptLineSpacing) {
                Text(languageTag)
                Text(timestamp)
            }
            .font(DesignSystem.Typography.metadataText)
            .foregroundStyle(DesignSystem.Colors.metadataForeground)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, DesignSystem.Spacing.transcriptRowVerticalPadding)
    }
}

#if DEBUG
    #Preview("Source-led caption rows") {
        List {
            TranscriptCaptionRow(
                source: "おはようございます。始めましょう。",
                translation: "Good morning. Let's begin.",
                languageTag: "JA",
                timestamp: "09:00:05"
            )
            TranscriptCaptionRow(
                source: "Sounds good — I'll share my screen.",
                translation: "いいですね。画面を共有します。",
                languageTag: "EN",
                timestamp: "09:00:20"
            )
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(DesignSystem.Colors.surfaceContent)
    }
#endif
