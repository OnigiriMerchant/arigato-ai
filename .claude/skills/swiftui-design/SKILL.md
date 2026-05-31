---
name: swiftui-design
description: Arigato AI's design system — color tokens, typography, glass usage, ambient rules, component patterns. Use when creating or modifying any SwiftUI view to ensure visual consistency.
---

# Arigato AI design system

> **Phase 7 design language — locked 2026-05-31.** Basis: `docs/PHASE_7_DESIGN_RESEARCH.md` (collisions A–E) + `docs/V3_BACKLOG.md` "Design language direction" (V3 #22). Named design tokens beyond the shipped color set **do not exist yet** — token authoring is a later Phase 7 dispatch. Do NOT invent token values.

## Design principles (in priority order)
1. **Caption-first hierarchy** — captions are the product; controls recede.
2. **Calm color, intentional accent** — restraint over decoration; color reserved for semantic meaning.
3. **Glanceable status, no chrome** — minimal UI during a session.
4. **Liquid Glass on chrome only** — translucent navigation/controls floating above solid content (see Glass usage).
5. **Light AND dark parity** — every view works in both, designed light-first.

## Hierarchy — source-led, per line (decision 1)
Each transcript row leads with the **spoken-language** text as primary and the translation as secondary. The primary language is chosen **per line** from `Sentence.sourceLanguage` — never a hardcoded language.
- Differentiation = **one weight step + one color step** (`.primary` vs `.secondary`). **Same font size.** No italics, no boxes, no size change between the two lines.
- An SF Mono language tag (`JA`/`EN`) plus the timestamp form a **tertiary** metadata cluster on the source line.

> Shipped detail view currently hardcodes Japanese-primary; migrates to source-led in the Phase 7 detail-view restyle dispatch.

## Color tokens
`DesignSystem.swift` is the source of truth; `DesignTokens.swift` provides thin `Color.*` forwarders.

```swift
// Recording accent — the only hard-coded chromatic accents. Hand-check WCAG AA in BOTH modes.
recordingActive = Color(red: 0.94, green: 0.27, blue: 0.27)  // muted red
recordingReady  = Color(red: 0.26, green: 0.66, blue: 0.45)  // calm green
recordingIdle   = Color(white: 0.5, opacity: 1.0)            // mid gray
```
- Caption emphasis uses the semantic `.primary` / `.secondary` label colors directly (per the source-led hierarchy above) — there are **no** dedicated caption tokens.
- Surfaces use semantic system colors that auto-adapt light/dark: `surfaceBackground` (`.systemBackground`), `meterTrack` (`.tertiarySystemFill`), `columnDivider` (`.separator`), `timestampForeground` (`.tertiaryLabel`), `returnArrowBackground` (`.tertiarySystemFill`). `DesignSystem.swift` is the canonical list.

> **Removed (drift fix):** the previously-documented `captionPrimary`, `captionSecondary`, and `surfaceFloating` tokens **never existed** in `DesignSystem.swift`. A named caption-hierarchy + surface-token set is *planned for the token-authoring dispatch* — do not reference those names until that dispatch defines real values.

## Typography (decision 4)
- **All text, including Japanese (CJK):** SYSTEM fonts — SF Pro (Latin) + Hiragino Sans (Japanese) via iOS's automatic language-aware cascade. CJK readability is non-negotiable; no bundled custom font carries CJK.
- **Technical readouts / timestamps / language tags:** **SF Mono** (use `monospacedDigit()` for stable width).
- Headlines: system `.title2`/`.title`, `.semibold`. Body: system `.body`.
- **ALL text uses Dynamic Type — no fixed font sizes.** Any custom face, when adopted, must use `Font.custom(_:size:relativeTo:)` so it still scales.
- **Geist Pixel:** reserved for the "ARIGATO AI" wordmark + app-icon design **ONLY** (Latin-only; no documented CJK coverage). Activated at the brand-moment step — **not now**. The detail view ships with no custom-font dependency.

## Glass usage (decision 2)
- Liquid Glass (`.regular` via `glassEffect(_:in:)`) belongs on **chrome/navigation ONLY**: toolbar, nav bar, Copy/Share controls, scroll-to-top affordance, sheets/popovers — floating above content.
- **Content surfaces stay SOLID** (transcript rows, lists, captions). Apple advises against content-layer glass (PHASE_7_DESIGN_RESEARCH.md collision A).
- The system handles light/dark + Reduce Transparency / Increase Contrast / Reduce Motion **automatically for Liquid Glass and standard components** — but NOT for any custom material/visual.
- ⚠️ **`.ultraThinMaterial` is NOT Liquid Glass.** Do not conflate them or use it to imitate glass.

## Ambient / particles (decision 3 — minimalist)
- Confined to **non-content brand moments only**: onboarding hero, empty state, model-warmup orb. **NEVER** behind the transcript or any content surface. Detail view = zero particles.
- Any custom ambient must hand-build: light/dark parity, a reduced-motion **"calm" mode**, and hold **60fps** (must not steal frame time from the inference pipeline).

## Spacing scale
- 4, 8, 12, 16, 24, 32, 48 — use these only.
- Section padding 16; view edge padding 20; caption line spacing 1.4× font line height.

## Component patterns

### Transcript caption row (source-led)
`source` / `translation` are resolved per line from `Sentence.sourceLanguage`; `tag` is `"JA"`/`"EN"`.
```swift
VStack(alignment: .leading, spacing: 4) {
    Text(source)                       // PRIMARY — the spoken language
        .font(.body)
        .foregroundStyle(.primary)
    Text(translation)                  // SECONDARY — same size, one color/weight step down
        .font(.body)
        .foregroundStyle(.secondary)
    HStack(spacing: 6) {               // TERTIARY metadata cluster on the source line
        Text(tag)
        Text(timestamp)
    }
    .font(.system(.caption2, design: .monospaced))
    .foregroundStyle(.tertiary)
}
.padding(.vertical, 8)
```

### Recording button
- 64pt circle idle (gray), 80pt + pulse animation when active (red). Centered, bottom of live view. Long press = stop, single tap = pause/resume.

## Dark mode rules
- Use semantic colors (`.primary`, `.secondary`, `Color(.systemBackground)`) — never hard-coded hex **except** the recording accents (which must be WCAG-AA-checked in both modes by hand).
- Test EVERY view in both modes via SwiftUI Preview.
- Liquid Glass + standard components adapt automatically; custom visuals (ambient, glows) must be hand-tested in both modes.

## Accessibility floor
- Dynamic Type support up to `.accessibility3` minimum.
- VoiceOver labels on every interactive element and on status/confidence indicators.
- 44×44pt minimum tap targets.
- Reduce Motion respected for the recording-button pulse **and** any ambient motion (calm mode).

## What NOT to do
- No emoji icons. SF Symbols only.
- No custom font for transcript / body / CJK text — system fonts only there. Geist Pixel only for the wordmark + app icon.
- No Liquid Glass (or `.ultraThinMaterial`) on content surfaces — chrome only.
- No particles / ambient behind content.
- No fixed-pixel layouts. Use HStack/VStack with spacing tokens.
- No more than 2–3 colors per screen.
- No drop shadows — depth comes from Liquid Glass on chrome, not from shadows or blur on content (which stays flat).
