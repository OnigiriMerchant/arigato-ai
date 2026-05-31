# Phase 7 Doc-Researcher Pre-flight Findings — UI Polish / Design Language

**Date**: 2026-05-31
**Phase**: 7 (UI polish) kickoff — design-language pre-flight (V3 #22, #40, onboarding/brand-moment entries)
**Type**: READ-ONLY research. No production code changed, no design tokens modified, no commit. Findings only — for the Claude.ai design-planning session that gates @feature-planner Phase 7.
**Method**: Multi-agent workflow (`phase7-design-research`, run `wf_9103cc83-72b`, 31 agents). Codebase inventory via read-only `Explore` agents; external API/licensing claims via `@doc-researcher` streams, each finding then **adversarially re-checked** by a skeptic that defaults to *refuted* unless a primary source confirms. Followed by a collision-synthesis pass (surface-only) and a completeness critic. Source discipline per `.claude/agents/doc-researcher.md`: primary sources only; unconfirmed claims are flagged UNVERIFIABLE, not asserted; source disagreements are surfaced, not silently resolved.

> **How to read this.** Categories 1, 2, 4 are *findings* (current state + verified API facts). Category 3 is the **Collisions** section — the load-bearing output: five places where the stated design intent conflicts with verified Apple guidance or the project's own locked decisions. **Collisions are surfaced, not resolved** — each is a decision for the human, with the original reasoning to be re-examined. The Gaps/UNVERIFIABLE section lists what could not be confirmed from primary sources.

> **iOS 26 doc methodology caveat (applies to all Apple findings).** Apple's `/documentation/` and HIG pages are JavaScript-rendered; `WebFetch` returned empty bodies for the human-facing URLs. API findings were verified against Apple's own JSON data-backing endpoints (`developer.apple.com/tutorials/data/...`), the same source that populates the HTML docs. Where a JSON endpoint 404'd (notably HIG Materials), the quote rests on a single rendering of the live HIG page — a primary Apple source, but not cross-checked against a second rendering. Such cases are flagged inline.

---

## Sources consulted

**Apple (developer.apple.com) — verified against JSON data endpoints unless noted:**
- SwiftUI Liquid Glass: `/documentation/swiftui/view/glasseffect(_:in:)`, `/documentation/swiftui/glass`, `/glass/tint(_:)`, `/glass/interactive(_:)`, `/documentation/swiftui/glasseffectcontainer`, `/documentation/swiftui/view/glasseffectid(_:in:)`, `/documentation/swiftui/primitivebuttonstyle/glass`, `/primitivebuttonstyle/glassprominent`
- Liquid Glass guides: `/documentation/SwiftUI/Applying-Liquid-Glass-to-custom-views`, `/documentation/TechnologyOverviews/adopting-liquid-glass`
- HIG: `/design/human-interface-guidelines/materials` (rendered page; JSON endpoint 404'd)
- WWDC25 session 219 "Meet Liquid Glass": `/videos/play/wwdc2025/219/` (transcript rendered in full)
- Typography / Dynamic Type: `/documentation/swiftui/font/textstyle`, `/view/font(_:)`, `/font/body`, `/documentation/swiftui/scaledmetric` (+ `/init(wrappedvalue:relativeto:)`), `/documentation/swiftui/font/custom(_:size:relativeto:)`, `/documentation/SwiftUI/Applying-Custom-Fonts-to-Text`, `/documentation/uikit/uifontmetrics`, `/font/textstyle/extralargetitle`, `/documentation/updates/swiftui`, `/documentation/swiftui/dynamictypesize`
- Custom font embedding: `/documentation/uikit/adding-a-custom-font-to-your-app`, `/documentation/bundleresources/information-property-list/uiappfonts`

**Geist / Geist Pixel (official Vercel repo):**
- `raw.githubusercontent.com/vercel/geist-font/main/readme.md`
- `.../main/documentation/DESCRIPTION.en_us.html`
- `.../main/sources/CustomFilter_GF_Latin_All.plist`, `.../main/sources/config-Geist.yaml`, `github.com/vercel/geist-font/tree/main/sources`
- `.../main/LICENSE.txt`, `.../main/OFL.txt`
- `github.com/vercel/geist-font/tree/main/fonts/Geist`, `.../fonts/GeistPixel`

**Codebase (local, read-only):** `ArigatoAI/Views/{MeetingDetailView,MeetingDetailFormatter,MeetingListRow,TranscriptSplitScreenFormatter,MeetingListView,MeetingControlsView,SettingsView}.swift`, `ArigatoAI/Transcription/TranscriptLiveView.swift`, `ArigatoAI/Design/{DesignSystem,DesignTokens}.swift`, `ArigatoAI/Onboarding/OnboardingView.swift`, `ArigatoAI/StartupErrorView.swift`, `ArigatoAI/Assets.xcassets/AppIcon.appiconset/Contents.json`, `.claude/skills/swiftui-design/SKILL.md`.

---

## Category 1 — Codebase ground truth

### 1.1 Meeting detail view — JA/EN reading hierarchy (shipped)

`MeetingDetailView.swift:254-264` renders each transcript row as a `VStack(alignment: .leading, spacing: 4)`:

```swift
Text(body.japanese).font(.body)                       // PRIMARY  (.primary default)
Text(body.english).font(.body).foregroundStyle(.secondary)  // SECONDARY
Text(body.timestamp).font(.caption2).foregroundStyle(.tertiary)  // TERTIARY
```

**A reading-hierarchy IS encoded, three-tier, via semantic color (not font weight or size):**
- **Primary** — Japanese, `.body`, default `.primary` foreground (top).
- **Secondary** — English, `.body`, explicit `.secondary` foreground (middle).
- **Tertiary** — `HH:mm:ss` timestamp, `.caption2`, `.tertiary` foreground (bottom).

Both languages share `.body` size; the only differentiator is foreground tier. Japanese sits on top and reads as primary. Language projection (`MeetingDetailFormatter.sentenceBody`, lines 109-124) always maps to the (Japanese, English) slots regardless of who spoke: `sourceLanguage == "ja"` → sourceText to JA slot; `== "en"` → inverse. Timestamp formatting delegates to `TranscriptSplitScreenFormatter.formatTimestamp` and date/duration to `MeetingListRowFormatter` for byte-identity across the three surfaces (UI #15).

> **Design-decision flag for Phase 7:** the shipped hierarchy makes **Japanese primary, English secondary**. See Collision-adjacent finding 1.6 — the documented design system says the *opposite*.

### 1.2 Design tokens — registry, values, source-of-truth, consumers

- **Source of truth:** `Design/DesignSystem.swift:32-89` (`enum DesignSystem { enum Colors { … } }`, 8 color tokens).
- **Public API:** `Design/DesignTokens.swift:25-49` — thin `Color.*` forwarders, pure delegation, zero logic.
- **There are NO typography, spacing, motion, or radius tokens** — color only. Fonts/spacing are inline literals at each call site.

| Token | Literal value | Defined | Consumers |
|---|---|---|---|
| `recordingActive` | `Color(red: 0.94, green: 0.27, blue: 0.27)` (muted red) | DesignSystem.swift:42 | 7 sites (AudioCaptureView 165/199; MeetingControlsView 198/200-201; TranscriptLiveView 433/452; +comment 213) |
| `recordingIdle` | `Color(white: 0.5)` (mid gray) | :46 | TranscriptLiveView.swift:426 |
| `surfaceBackground` | `Color(.systemBackground)` | :51 | 4 sites (AudioCaptureView 41; StartupErrorView 26; TranscriptLiveView 157/787) |
| `meterTrack` | `Color(.tertiarySystemFill)` | :56 | 10 sites (capsule/meter/toast backgrounds across AudioCaptureView, MeetingControlsView, TranscriptLiveView, UndoStopToastView 73, PendingDeletionToast 81) |
| `recordingReady` | `Color(red: 0.26, green: 0.66, blue: 0.45)` (calm green) | :66 | TranscriptLiveView.swift:445 (`.loaded` warmup dot; replaced ad-hoc `Color.green`, V3 #40 concern 1) |
| `columnDivider` | `Color(.separator)` | :74 | TranscriptSplitScreenView.swift:76 |
| `timestampForeground` | `Color(.tertiaryLabel)` | :80 | TranscriptSplitScreenView.swift:235 |
| `returnArrowBackground` | `Color(.tertiarySystemFill)` | :87 | TranscriptSplitScreenView.swift:210 |

All non-recording tokens map to **system semantic colors**, so they already adapt light/dark automatically. The only hard-coded RGB tokens are the two recording-accent colors (`recordingActive` red, `recordingReady` green) — these do **not** auto-adapt and are the WCAG-AA-in-both-modes risk surface.

### 1.3 Recording status badge (shipped)

`MeetingControlsView.swift:168-184` — `HStack(spacing: 6)` of an icon + `Text` in `.caption.monospacedDigit().weight(.semibold)`, padded 10×4, on a `Color.meterTrack` `Capsule()`. Icon by state: **Recording** = 8pt `Circle().fill(Color.recordingActive)` pulsing opacity `1.0↔0.4`, `.easeInOut(0.6).repeatForever(autoreverses:)` (`:200-201`); **Paused** = `pause.fill` (static, `.secondary`); **Ended** = `stop.fill` (static, `.secondary`). Driven by `TimelineView(.periodic(by: 1.0))` at 1 Hz (`:169`); paused/ended freeze elapsed time per UI #3. The live chrome (`TranscriptLiveView.swift:163-224`, `IndicatorChromeDisplay:376-459`) carries a language badge ("JA"/"EN"/"—") and a warmup pill whose dot color is `recordingIdle`/`recordingActive`/`recordingReady`/`recordingActive` for `.idle`/`.loading`/`.loaded`/`.failed`. Failed-state error text uses `.secondary` (not red) per V3 #40 concern 2.

### 1.4 Brand-moment surfaces (all stock SF Symbols + system fonts today)

| Surface | File | Current visual |
|---|---|---|
| Onboarding Screen 1 hero | OnboardingView.swift:110-112 | SF Symbol `text.bubble.fill` @ **64pt**, `.tint` (accent). Headline `.title.semibold`; privacy body `.body.secondary` (D14-4 locked copy). Button `.borderedProminent` capsule. |
| Onboarding Screen 2 | OnboardingView.swift:153-237 | Reactive setup screen; permission indicator morphs SF Symbols (`checkmark.circle.fill`/`exclamationmark.triangle.fill`/`circle.dotted`); `.green`/`.orange`/`.secondary`. |
| MeetingListView empty state | MeetingListView.swift:269-284 | SF Symbol `list.bullet.rectangle` @ **48pt** `.secondary`; "No meetings yet" `.headline`; subhead `.subheadline.secondary`. Search-empty = stock `ContentUnavailableView.search`. |
| StartupErrorView | StartupErrorView.swift:24-61 | **No icon** (intentionally minimal). `Color.surfaceBackground` fill; "App can't start" `.title.semibold`; `.localizedDescription` `.body.secondary`; destructive Quit button. |
| SettingsView | SettingsView.swift:65-213 | `List` with About / Storage (+ DEBUG Developer). No icons; system fonts; destructive roles. |
| **App icon** | Assets.xcassets/AppIcon.appiconset/Contents.json | **PLACEHOLDER — no custom artwork.** Contents.json defines three 1024² slots (light / dark-luminosity / tinted-luminosity) but carries **no `filename` and no image files on disk** (only the 607-byte Contents.json). Ships the Xcode default icon. |

All brand surfaces use system fonts (UI #18) + semantic colors (UI #17); design tokens deliberately untouched (V3 #22 deferred). Brand-moment polish is tracked in the V3 "Onboarding visual identity polish" entry (hero illustration, empty state, StartupErrorView icon, app icon).

### 1.5 Live-caption styling (TranscriptLiveView / split-screen)

The live split-screen and chrome use the same token set (§1.2). No `Material`/blur/`glassEffect`/`.ultraThinMaterial` is used **anywhere in shipped code** — every surface is solid `Color`. (Confirmed by the consumer grep: zero `Material`/`glassEffect` call sites.)

### 1.6 ⚠️ Documented design system has DRIFTED from shipped code (`.claude/skills/swiftui-design/SKILL.md`)

The design-system skill — the file `@ui-reviewer` and implementers are told to follow — is materially out of sync with shipped reality and with V3 #22. This is current-state ground truth and feeds Collisions B and D:

1. **JA/EN hierarchy is inverted vs shipped code.** SKILL.md:23-24 declares `captionPrimary = .primary // English (target)` and `captionSecondary = .secondary // Japanese (source)`, and SKILL.md:34 makes translations (English) `.title` (larger) over source `.title3`. **Shipped `MeetingDetailView` does the opposite** (§1.1: Japanese `.primary`, English `.secondary`). Genuine doc-vs-code contradiction — Phase 7 must pick the intended primary language and reconcile both.
2. **Tokens that don't exist.** SKILL.md:23-28 references `captionPrimary`, `captionSecondary`, `surfaceFloating` — **none exist** in `DesignSystem.swift` (§1.2). The skill's color block is aspirational/stale.
3. **"No custom font files. SF Pro family only." (SKILL.md:89)** — direct tension with V3 #22's "drop Inter, adopt a distinctive face (Geist/Geist Pixel)" (Collision D).
4. **"ALL text uses Dynamic Type — no fixed font sizes." (SKILL.md:37)** — a custom face must therefore use `Font.custom(_:size:relativeTo:)` (the verified reconciliation, §3 Cat 4), not a fixed-size `Font.custom(_:size:)`.
5. **".ultraThinMaterial handles dark mode automatically." (SKILL.md:79) / "Liquid Glass aesthetic" (line 12).** `.ultraThinMaterial` is the **older Material idiom, NOT the iOS 26 Liquid Glass primitive** (`glassEffect`, §Cat 2). The skill conflates them, and shipped code uses neither (§1.5). Feeds Collision B.

---

## Category 2 — iOS 26 Liquid Glass API surface (verified)

All 11 findings returned `refuted=false` (i.e., the adversarial skeptic could not refute them). Confidence noted per finding.

| # | Finding | Conf. |
|---|---|---|
| 1 | `glassEffect(_:in:)` — `nonisolated func glassEffect(_ glass: Glass = .regular, in shape: some Shape = DefaultGlassEffectShape()) -> some View`. Default = regular variant in a capsule. Signature confirmed token-for-token against the SwiftUI symbol JSON. | high |
| 2 | `Glass` type variants: `.regular`, `.clear`, `.identity`; instance methods `.tint(_:)`, `.interactive(_:)`. | high |
| 3 | `GlassEffectContainer(spacing: CGFloat?, content:)` groups/morphs multiple glass shapes. *(Note: the "higher the spacing, the sooner blending begins" behavior is a **paraphrase** of the custom-views article, not a verbatim Apple quote.)* | high |
| 4 | `glassEffectID(_:in:)` — `nonisolated func glassEffectID(_ id: (some Hashable & Sendable)?, in namespace: Namespace.ID) -> some View`, used with `@Namespace` for morph transitions. | high |
| 5 | Button styles named `.glass` (`GlassButtonStyle`) and `.glassProminent` (`GlassProminentButtonStyle`). | high |
| 6 | Liquid Glass adapts automatically to light/dark and to content behind it (WWDC219: "each layer continuously adapts based on what's behind it"; elements "flip from light to dark based on the background"). | **medium** (HIG-Materials leg of the attribution could not be re-rendered; WWDC219 core confirmed) |
| 7 | **Reduce Transparency** — system automatically "makes Liquid Glass frostier and obscures more of the content behind it." | high |
| 8 | **Increase Contrast** — system automatically makes glass elements predominantly black/white with a contrasting border. | high |
| 9 | **Reduce Motion** — system automatically "decreases the intensity of some effects and disables any elastic properties for the material." | high |
| 10 | **Placement (where it belongs):** Liquid Glass belongs on the **topmost navigation layer** — tab bars, sidebars, toolbars, navigation bars, controls, sheets/popovers — floating above content. | high |
| 11 | **Placement (where it does NOT belong):** Apple explicitly advises **against** content-layer glass. HIG Materials: *"…including it in the content layer can result in unnecessary complexity and a confusing visual hierarchy."* WWDC219 (re a list): keep it "in the content layer instead" of glass; glass "is best reserved for the navigation layer that floats above the content of your app." Documented in-content exception: **transient interactive controls** (slider/toggle) that take glass only while actively manipulated. | high |

**Critical accessibility nuance (load-bearing for Collisions C & E):** the automatic Reduce Transparency / Increase Contrast / Reduce Motion / light-dark adaptation applies **only to standard system components**. Apple (adopting-liquid-glass): *"If you use standard components from system frameworks, this experience adapts automatically"* — and you must *"test your app's custom elements, colors, and animations with different configurations of these settings."* **A custom particle background, custom glows, or a hand-rolled glass material get NONE of the automatic adaptation.**

---

## Category 4 — iOS 26 typography APIs + Geist fonts

### 4.1 Dynamic Type (all verified `refuted=false`, high confidence)

1. `Font.TextStyle`, the semantic `.font(.body)` modifier and static `Font` values (`Font.body` …), `@ScaledMetric` (with optional `relativeTo:`), and `DynamicTypeSize` are all **current, non-deprecated** for iOS 26.
2. **Custom-font + Dynamic Type pattern (SUPPORTED):** SwiftUI `Font.custom(_:size:relativeTo:)` scales a bundled font with the user's text-size setting. UIKit companion: `UIFontMetrics.scaledFont(for:)`. This is the reconciliation for any custom face under SKILL.md:37's "no fixed font sizes" rule.
3. **iOS 26 added no new typography / Dynamic Type / text-style / ScaledMetric APIs** (per the SwiftUI updates page). `extraLargeTitle`/`extraLargeTitle2` text styles are **visionOS-only**, not available on iOS 26.

### 4.2 Geist / Geist Pixel (all returned findings verified `refuted=false`, high confidence)

1. **Latin:** Geist Sans and Geist Mono cover the Latin script (alphabet, numbers, punctuation, symbols). *(The "Latin-only" build-flag `ttfaUseScript` in `config-Geist.yaml` is a **commented-out example line**, not an active setting; the Latin-target conclusion rests on the `GF_Latin_All` filter + README banner, which stand.)*
2. **CJK / Japanese — DOCUMENTED ABSENCE (high confidence), binary-level absence UNVERIFIED.** No primary-source artifact in the official Vercel repo (README, DESCRIPTION, config, sources folder) mentions CJK/Japanese coverage for Geist **or** Geist Pixel; the only script artifact is a **Latin** filter. **However, strict glyph-set absence in the shipped binary was NOT proven** — that would require a `fonttools`/`.glyphspackage` glyph dump, which the read-only pre-flight did not run. **Posture: treat as "no Japanese coverage" — a Latin-only display face cannot render the Japanese half of a transcript and would require a separate CJK fallback (e.g. Hiragino Sans) wired in before shipping. This must NOT be treated as closed.**
3. **License:** SIL Open Font License 1.1 — embedding in a shipped app + redistribution inside the bundle is permitted. *(Framing note: the repo carries both `LICENSE.txt` (© 2023 Vercel) and `OFL.txt` (© 2024 The Geist Project Authors) with different copyright headers; both are genuinely OFL 1.1 — the legal conclusion holds.)*
4. **iOS embedding:** Geist ships OTF/TTF (both Apple-supported). Requires adding the file to the app target and registering each filename in `Info.plist` under `UIAppFonts` ("Fonts provided by application").

---

## Category 3 — Collisions (SURFACED, not resolved)

Five conflicts between stated design intent and verified guidance / locked decisions. Each is a human decision; the original V3 #22 reasoning should be re-examined before any is overridden. Apple's placement guidance is a **design recommendation, not an API/compile restriction** — the project *may* override it, deliberately.

### Collision A — Glassmorphic transcript bubbles vs Apple "no glass in the content layer" *(real; primary-sourced)*
- **V3 #22 intent:** "Glassmorphic transcript bubbles layered over dark particle background, with semantic color for JA vs EN" (V3_BACKLOG.md:183); "frosted semi-transparent cards layered over dark/particle backgrounds" (:159).
- **Apple says:** glass is reserved for the navigation layer above content; content-layer glass causes "a confusing visual hierarchy" (HIG Materials); in-content glass exception is transient interactive controls only — **not** static scrolling reading content.
- **Nature:** the transcript is the densest long-form reading surface in the app — exactly what the guidance steers glass away from. Direct placement conflict.
- **Sources:** HIG Materials; WWDC25 219; adopting-liquid-glass.

### Collision B — "iOS 26.4+ primitives ONLY (Liquid Glass), no deprecated APIs" vs achieving the glass-bubble look — a pincer *(real; primary-sourced)*
- **V3 #22 intent:** "Use iOS 26.4+ design system primitives (Liquid Glass …). No deprecated APIs." (:187) + render "glassmorphic transcript bubbles" (:183).
- **Apple says:** the genuine iOS-26 glass primitive is `glassEffect`/`Glass`/`GlassEffectContainer`/`glassEffectID`/`.glass(.glassProminent)` — and that same primitive's intended home is the navigation/control layer (Collision A). There is **no iOS-26 "glass card for content" primitive.**
- **Nature — pincer:** *Arm 1* — use the real `glassEffect` on transcript bubbles to satisfy "primitives only" → violates Apple's placement guidance (Collision A). *Arm 2* — hand-roll a frosted/blur material for "bubbles over a particle background" → a bespoke material is **not** an iOS-26.4 primitive (strains "primitives only"), and the classic `.ultraThinMaterial`/`UIVisualEffectView` path is **not** Liquid Glass and risks the "no deprecated/UIKit" rule. Either arm violates a stated hard requirement. **Also collides with the local SKILL.md (§1.6): line 79 conflates `.ultraThinMaterial` with "Liquid Glass."**
- **Sources:** glasseffect(_:in:); glass; glasseffectcontainer; Applying-Liquid-Glass-to-custom-views; HIG Materials; WWDC219.

### Collision C — Light-first + parity + reduced-motion + 60 fps vs dark-particle + glows + ambient motion *(real; primary-sourced)*
- **V3 #22 intent:** "flawless" light/dark parity, "design from light-mode-first" (:186); reduced-motion "calm mode" + WCAG AA both modes (:188); 60 fps during transcription, "particle systems must not steal frame time" (:189) — set against "particle/starfield backgrounds … pulsing or slow movement" (:158) and "backgrounds that react to AI states" (:161).
- **Apple says:** the automatic light/dark + Reduce Motion/Transparency/Contrast adaptations apply to **standard components only**; **custom elements must be hand-tested** and hand-built for every setting (Cat 2 nuance).
- **Nature — three fronts:** (a) a dark-tuned particle/glow language must be re-made to pass WCAG AA on light, with no automatic help for the custom layer; (b) continuous ambient motion opposes the reduced-motion calm mode, which the project must build itself; (c) particle motion + glass compositing competes for GPU time against the 60-fps-during-inference budget. These are V3 #22's own aesthetic vs its own hard requirements.
- **Sources:** WWDC219; adopting-liquid-glass; HIG Materials.

### Collision D — Geist/Geist Pixel distinctive face vs locked Decision #18 (system fonts; CJK non-negotiable) *(real; contingency met at the documented level)*
- **V3 #22 intent:** anti-pattern "Inter font stacks as default" (:166); wants distinctive "Neo Terminal" typography; named candidates Geist/Geist Pixel.
- **Locked Decision #18:** transcript text = **System** (SF Pro Latin + Hiragino Sans Japanese) because "CJK readability is non-negotiable. System fonts handle CJK better than any custom font we could bundle." (GROUP_D_UI_DECISIONS.md:256-260). Also local SKILL.md:89 "No custom font files. SF Pro family only."
- **Verified:** Geist & Geist Pixel have **no documented CJK coverage** (high confidence); binary glyph absence not yet proven (see Gaps). Geist Latin coverage, OFL-1.1 license, and OTF/TTF embedding are all fine.
- **Nature:** using Geist for transcript text (half Japanese) is impossible without a CJK fallback — which **re-creates exactly the situation Decision #18 rejected.** **Scope nuance:** Decision #18 already confines Geist to **Latin-only branding moments** (wordmark, status badge), where there is **no conflict** — Geist's Latin coverage is sufficient. The collision fires **only if** a Geist-led identity is extended to bilingual transcript text.
- **Sources:** Geist repo (readme/DESCRIPTION/config/sources); `Font.custom(_:size:relativeTo:)`.

### Collision E — Locked Decision #17 "semantic colors handle adaptation automatically" vs the custom dark-particle/glow language *(real; softer; primary-sourced)*
- **Locked Decision #17:** "SwiftUI's semantic colors handle most of the adaptation automatically." (GROUP_D_UI_DECISIONS.md:244-246) — true for stock chrome (§1.2 confirms 6/8 tokens are semantic).
- **Apple says:** automatic adaptation covers standard components/semantic surfaces; custom visuals are the developer's responsibility to test/build (Cat 2 nuance).
- **Nature:** a custom particle background, glows, and any hand-rolled glass fall **outside** the automatic path. V3 #22's "flawless light/dark parity" for the custom aesthetic cannot lean on Decision #17's mechanism — it needs explicit per-mode design + accessibility-setting handling. The color/theme analogue of Collision C. The two hard-coded RGB accents (`recordingActive`, `recordingReady`) are the only current tokens that already need manual both-mode contrast checking.
- **Sources:** adopting-liquid-glass; WWDC219; HIG Materials.

---

## Gaps / UNVERIFIABLE

1. **Geist/Geist Pixel CJK glyph absence — DOCUMENTED but not BINARY-PROVEN.** No primary source documents Japanese coverage; absence at the glyph level was not confirmed (needs a `fonttools`/`.glyphspackage` dump on the shipped `.otf`/`.ttf`). **Load-bearing — carry as: "UNVERIFIED — a CJK fallback font (e.g. Hiragino Sans) MUST be wired before any Geist adoption touches Japanese text." Do not treat the CJK question as closed.**
2. **`glassEffect` overloads beyond `(_:in:)`** — an `isEnabled`-gated variant was not separately verified (only the `(_:in:)` data endpoint was rendered). If Phase 7 wants conditionally-enabled glass (e.g. recording vs idle control states), confirm against its own data endpoint before relying on it.
3. **`DefaultGlassEffectShape` standalone semantics** — its capsule behavior came from the custom-views article, not its own type page (which was not fetched).
4. **`backgroundExtensionEffect` / scroll-edge / content-behind-glass behavior** — not researched. How Liquid Glass interacts with the SwiftData-backed scrolling transcript list (the content layer) is unmapped; the navigation-vs-content boundary for *this app's specific screens* (caption rows, list cells, recording control, toolbar) is stated only in principle, not mapped surface-by-surface. Natural input to the design-planning session.
5. **HIG Materials JSON endpoint 404'd.** The Materials-page quotes rest on a single live-page rendering (primary Apple source, not cross-checked against a second rendering). Finding 6 (auto light/dark adaptation) is therefore **medium confidence** on its HIG leg; its WWDC219 core is high confidence.
6. **Citation hygiene (downgrades applied above, flagged for reuse):** GlassEffectContainer spacing behavior is a **paraphrase**, not a verbatim Apple quote; the Geist `ttfaUseScript` flag is a **commented example**, not active; `LICENSE.txt`/`OFL.txt` carry different copyright headers (both OFL 1.1).
7. **Exact Geist Latin codepage** (Latin-1 vs Latin Extended / Vietnamese / diacritics) not enumerated by any primary source — "Latin" confirmed at script level only.
8. **Exact bundled Geist filenames** for `UIAppFonts` registration not pinned (the `fonts/Geist/otf` folder exists but individual filenames weren't enumerated; a `config-Geist.yaml` comment disables OTFs "for this demo"). Pin the actual `fonts/Geist/ttf` + `fonts/GeistPixel/ttf` filenames before any embedding step.
9. **Local SKILL.md drift (§1.6)** is itself a gap to close in Phase 7: inverted JA/EN hierarchy vs shipped code, non-existent tokens, and `.ultraThinMaterial`≠Liquid Glass conflation. The design-system skill should be rewritten as part of the Phase 7 token/component pass (V3 #22 deliverable 3 + the @design-system-subagent decision).

---

## Sources Consulted (provenance audit)

Per `doc-researcher.md` Rule 5, every claim above ties to a URL in the **Sources consulted** list at the top. Apple API/behavior claims → developer.apple.com (JSON data endpoints, except the HIG Materials page which was rendered live; WWDC219 transcript rendered in full). Font coverage/license/format claims → the official `vercel/geist-font` repo files. Codebase claims → the local files enumerated, with file:line. Nothing in this document is asserted from training-data recollection; iOS-26 surface was verified against live Apple sources and adversarially re-checked.
