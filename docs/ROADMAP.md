# Arigato AI — Roadmap

On-device bidirectional Japanese↔English meeting translator for iPhone 17 Pro Max. Personal use first, App Store later if it earns it. Built with Swift 6 / SwiftUI / SwiftData on iOS 26.4+, WhisperKit for ASR, LFM2-350M for translation, Apple Foundation Models for cleanup tier 1, Anthropic API (Claude Opus 4.7) for cleanup tier 2.

This file is the single source of truth for the project arc. New chat sessions and Claude Code agents read this to orient. When state changes, update this file alongside CURRENT_STATE.md.

## MVP 1 definition

MVP 1 ships when the app is usable for real meetings, personal use only, no App Store. App Store submission triggers after 30 days personal use plus 3 colleagues independently asking for access.

The 12 features that constitute MVP 1:

> **Status reflects 2026-05-25 reconciliation.** UI decisions doc (`docs/GROUP_D_UI_DECISIONS.md`) supersedes the original ROADMAP feature wording in several places; supersession trail noted per feature.

**Core capture loop**
1. Start/stop meeting button (single tap each) — ✅ shipped (Steps 7, 8)
2. Live dual-line captions: Japanese on top, English below, last 3 lines visible — ⚠️ superseded by Decision #1 scrolling split-screen (`TranscriptSplitScreenView`, Step 9a); the "last 3 lines" framing is obsolete
3. Auto-save every line to SwiftData as it finalizes (crash-resilient) — ⚠️ shipped in code (Steps 1–3, 8); broken in production wiring (B1.6)
4. Pause/resume mid-meeting — ⚠️ state machine + button morphing shipped; spec-vs-code divergence on whether capture halts (see V3 entry "Pause spec-vs-code divergence")

**Meeting library**
5. Past meetings list, sorted by date — ⚠️ shipped in code (Step 6); broken in production wiring (B1.6)
6. Meeting detail view, scrollable, copyable per line — ⚠️ shipped in code (Step 11); broken in production wiring (B1.6)
7. Rename meeting (default: timestamp) — ❌ superseded by Decision #12 (no edit affordance in MVP-1)
8. Delete with undo toast — ⚠️ bulk delete-all shipped via Settings (Step 15); per-meeting delete: `MeetingStore.deleteMeeting(meetingID:)` exists at `MeetingStore.swift:393` + tested, UI wiring missing; multi-select (Decision #13) explicitly not shipped

**Export and post-process**
9. Export as Markdown (bilingual or English-only toggle) — ⚠️ superseded by Decision #10 (bilingual-only with timestamps); no toggle planned
10. Share sheet integration — ✅ shipped (Step 13 + B1.4)
11. AI summary on demand via Apple Foundation Models — ❌ not shipped; genuinely-new feature remaining for MVP-1

**Settings**
12. Single settings screen: model warmup toggle, default export format, transcript retention period, microphone input override — ❌ superseded by Decision #19 (About + Storage only); four-toggle spec deferred to Phase 6+ polish

Excluded from MVP 1, deferred to v2: speaker diarization, multi-language beyond JA↔EN, cloud sync, live caption sharing to second device, custom glossary.

## Phase status

| Phase | Scope | Status |
|-------|-------|--------|
| 0 | Environment setup | ✅ Shipped |
| 1 | Agentic stack | ✅ Shipped |
| 2 | First simulator deployment | ✅ Shipped |
| 2.5 | Physical iPhone deployment | ⏸️ Deferred (triggers when Phase 4 needs real mic hardware) |
| 3 | Audio capture foundation | ✅ Shipped |
| 4 | WhisperKit streaming transcription | ✅ Shipped |
| 5 | LFM2 translation | 🟡 Shipping — Groups A–D shipped via SDK v0.9.4 (legacy `Liquid4All/leap-ios` repo). **v0.9.4 is the MVP-1 ship channel per 2026-05-25 user decision.** v0.10.x migration deferred to v1.x (tracked in V3). |
| 6 | SwiftData transcript storage | ✅ Shipped — Meeting/Sentence entities, MeetingStore @ModelActor, auto-save, history list, detail view, search, export, delete-all all shipped via Group D. Production SwiftData container schema fixed in B1.6 (`32abc3e`, 2026-05-25): now registers `Schema([Meeting.self, Sentence.self])`. |
| 7 | UI polish | ⏳ Pending — minimal DesignSystem namespace shipped (Step 9b); V3 #22 ambient-intelligence pass not started |
| 8 | Export + ShareLink | ✅ Shipped — Markdown bilingual export; active-view + detail-view ShareLink contexts. Multi-select context (UI #13) deferred. |
| 9 | AI summary | ⏳ Pending — genuinely untouched |
| MVP 1 | All 12 features functional, used in real meetings | ⏳ Pending |
| Post-MVP-1 | App Store submission (30 days personal + 3 colleague requests) | ⏳ Pending |

## Phase detail

### Phase 0 — Environment setup (shipped)

Apple Developer Program paid, Xcode 26.4.1 + iOS 26.4 SDK, Swift 6.3.1, GitHub repo, Homebrew tooling (Node, gh, swiftformat, swiftlint). Foundation that lets the project build iOS apps at all.

### Phase 1 — Agentic stack (shipped, commit bdda137)

11 specialist subagents (feature-planner, swift-implementer, doc-researcher, build-doctor, code-reviewer, ui-reviewer, test-writer, device-deployer, performance-profiler, swift-tutor, git-historian) + 4 skills (whisperkit, leap-sdk, swiftui-design, ios-simulator) + 4 hooks (session-start, post-swift-edit, detect-secrets, pre-commit-guard) + 6 slash commands + 3 MCPs (XcodeBuildMCP, mcpbridge, GitHub) + swift-lsp + 2 daily/weekly routines. Infrastructure that makes Claude do quality iOS work for this specific project.

### Phase 2 — First simulator deployment (shipped)

Default Xcode SwiftUI + SwiftData scaffold built, installed, launched on iPhone 17 Pro Max simulator (iOS 26.4) entirely through XcodeBuildMCP. Proves the deployment pipeline works end-to-end before any real code goes on top.

### Phase 2.5 — Physical iPhone deployment (deferred)

Will trigger when Phase 4 needs real microphone hardware that simulators can't provide. Developer Mode on iPhone + iPhone trust on Mac + provisioning profile setup. Goal: app runs on the actual iPhone 17 Pro Max for end-to-end audio testing.

Trigger condition: Phase 4 Group D ships and tests need physical microphone capture (rather than simulator audio injection).

### Phase 3 — Audio capture foundation (shipped, commit b92938b)

AVAudioEngine actor capturing 16kHz mono PCM from microphone. Permission flow (Info.plist + runtime alert + Settings deeplink). Live VU meter visualizing audio level. AsyncStream-based buffer delivery ready for Phase 4 to consume. Route-change handling for AirPods / charger plug-ins mid-meeting. No transcription yet — clean audio capture proven solid.

### Phase 4 — WhisperKit streaming transcription (shipped)

Argmax's ArgmaxOSS package (post-rename of WhisperKit) integrated. Streaming JA + EN ASR with auto language detection per chunk. Consecutive-window disagreement gating (N=2) replaces per-segment confidence threshold. Model pre-warming at app launch. Audio frames from Phase 3's AsyncStream become text segments here, then route through LanguageRouter and surface in TranscriptLiveView.

All four groups shipped. Pipeline runs end-to-end on simulator audio. 125/125 tests passing.

**Shipped:**
- Group A: domain types and Transcribing protocol
- Group B: WhisperKit SPM dependency, WhisperModelLoader actor, WhisperEngine seam, WhisperModelVariant enum, AppBootstrapper, StartupErrorView
- Group C: RollingAudioBuffer, WhisperClient cascade, TranscriptionActor (bounded FIFO queue cap 4, oldest-drop overflow, deterministic awaitUpstreamDrained test seam, end-of-stream drain), LanguageRouter (N=2 disagreement gate, @MainActor @Observable currentLanguage, Transcribing protocol conformance with lossy mapping)
- Group D: routedTranscripts() multiplex resolved (Option 2 — dead-stream method removed, replaced with @Observable routedHistory + resetSession). AppBootstrapper owns shared TranscriptionActor + LanguageRouter. AudioCaptureViewModel drains pipeline through router when injected (D3-T3 violation test for greedy upstream burst). TranscriptLiveView with three-region layout (chrome / list / record control). Per-row binding contract locked: chrome reads currentLanguage (authoritative), rows read detectedLanguage (per-window honest signal). End-of-group gate Concern 6 (duplicate "listening…") fixed pre-push; remaining 7 visual concerns deferred to Phase 7 (V3 #40).

**Eight locked architectural decisions** (see PHASE_4_HANDOFF.md): ArgmaxOSS package source, Whisper model large-v3-turbo, AppBootstrapper pre-warm pattern, 5s window with 1s hop streaming, consecutive-disagreement language gating with N=2, detectLangauge typo handling, openai_whisper-large-v3-v20240930_turbo_632MB variant, subagent MCP-inheritance fallback rule.

**Pre-Phase-5 workflow automation bundle** (V3 #14, #28, #29, #30, #31, #37, #39): recommended before Phase 5 kickoff. ~90 minutes total.

### Phase 5 — LFM2 translation (planned)

Liquid AI's LFM2-350M-ENJP-MT bidirectional model loaded via LEAP iOS SDK v0.9.4. Q5_K_M quantization for vibe check, Q5/Q8 bake-off for production. Translation dispatcher attaches at LanguageRouter's output, routes Whisper's authoritative language to the correct translation direction. Cache control via the `LiquidCacheOptions.enabled(path:)` API. Outputs streaming bilingual text.

The dispatcher consumes authoritativeLanguage (not detectedLanguage) — never sends a half-sentence through the wrong direction because the language gate already stabilized routing.

Includes model warmup at app launch (5-line addition addressing cold-start glitches per the warmup behavior observed during pre-build vibe checks).

### Phase 6 — SwiftData transcript storage (shipped in code via Group D / production wiring broken)

Originally scoped to replace the default Xcode `Item.swift` scaffold with `Meeting`/`Sentence` models (renamed from the earlier `MeetingLine`/`Meeting` framing per Decision #20). Persists transcripts locally, no iCloud (privacy stance). Each `Sentence` carries timestamps, original + translated text, source language, and the upstream Whisper segment ID.

**Shipped via Phase 5 Group D (code + tests green):**
- `Meeting` + `Sentence` `@Model` entities with cascade delete (Step 1, Decision #20).
- `MeetingStore` `@ModelActor` — the single write/read seam; off-main init per Amendment 3 / FB13399899 (Steps 2, 8).
- Continuous auto-save on every completed sentence (Steps 3, 8; Decision #6).
- History list (Step 6), detail view (Step 11), full-content search (Step 12), Markdown export (Step 13), bulk delete-all + Settings storage section (Step 15).

**Open ship-blocker — B1.6 (schema-registration mismatch):** the production SwiftData container is constructed with `Schema([Item.self])` (`ArigatoAIApp.swift:41`), and `MeetingStore` runs against that same container (`AppBootstrapper.swift:598`). `Meeting`/`Sentence` are absent from the production schema (they appear only in a `#if DEBUG` preview at `MeetingControlsView.swift:791`), so the first production insert will fail at runtime. The gap is currently masked by the B1.1 LFM2 block — store construction is gated on `lfm2Loader.warmup()` succeeding, which never happens while LFM2 is down. Every persistence test passes because each injects its own correctly-schema'd in-memory container. Fix tracked as **B1.6** in `docs/PRE_MVP1_REVIEW.md` Bucket 1 (replace the schema, delete `Item.swift`, add a production-container registration test). The legacy `Item.swift` scaffold removal is tracked alongside.

Remaining genuine Phase 6 scope beyond B1.6: V3 #46 (local-only diagnostics for performance tuning). Ready for export and AI summary phases to consume once B1.6 lands.

### Phase 7 — UI polish (planned)

Caption-first hierarchy. Dark mode parity. Recording state visual language. SwiftUI animations using `withAnimation` and `matchedGeometryEffect`. Accessibility (Dynamic Type, VoiceOver, contrast). Live captions sliding up like a teleprompter. The "feels like a real product" pass.

Hard requirements per V3 #22: light AND dark mode parity, iOS 26.4+ primitives only, WCAG AA, 60fps. Anti-patterns: rainbow color, unnecessary animation, chrome that competes with captions during live sessions.

Open at kickoff: decide whether to introduce a @design-system subagent or extend @ui-reviewer's mandate. Lean toward extension unless workload justifies a new subagent.

### Phase 8 — Export + ShareLink (planned)

AirDrop / Mail / Files / Notes via native iOS share sheet. Plain text, Markdown, PDF formats. Native iOS share sheet so users send transcripts wherever. No proprietary formats — interoperate with existing tools.

### Phase 9 — AI summary (planned)

Two-tier post-meeting cleanup. Tier 1: Apple Foundation Models (free, on-device) generates summary, action items, key decisions. Tier 2: Claude Opus 4.7 via Anthropic API (~$0.30–0.50 per 2-hour transcript, premium quality, network required). User picks tier per meeting. Privacy stance: Tier 1 is the default, Tier 2 explicit opt-in.

After Phase 9 ships and all 12 MVP 1 features are functional in real meetings: MVP 1 milestone reached.

## Trigger map (V3 entries by firing point)

**Group D plan review (next):**
- #27 routedTranscripts() multiplex — first thing during plan review

**End of Phase 4 (post-Group-D, before Phase 5 kickoff) — FIRED 2026-05-11 as the post-Phase-4 workflow automation bundle; see "Next workflow automation pass" below for follow-on items:**
- #14 Workflow automation narrow bundle: feature-planner self-critique rules + /dispatch-implementer slash command
- #28 feature-planner system prompt update — concurrency scheduling-assumption rule
- #29 Test infrastructure as agent blind spot (Step 7 shipped; Step 8 finding-only — real fix deferred to Phase 5+ library extraction)
- #30 swift-implementer scope-and-decision discipline (sharpening)
- #31 Process trim re-evaluate
- #37 AudioCaptureViewModel router param: optional → required
- #39 Adopt Anthropic prompting best practices for Opus 4.7

**Next workflow automation pass (deferred from the 2026-05-11 bundle):**
- #41 Doc-researcher trigger: third-party tool configuration changes — code-reviewer BLOCKING rule shipped (workflow-step-11); remaining items: dispatch-implementer slash command pre-flight template + CLAUDE.md cross-reference under "External dependency configuration"
- #42 feature-planner output channel rigidity — pre-flight enforcement permanently deferred from feature-planner system prompt; deferred-implementation plan IS the dispatch-implementer slash command work referenced by #41 (shared scope)
- #43 Agent prompt hygiene — INFO findings from workflow bundle gate (5 findings, ~50 min total; Finding 4 is the load-bearing dispatch-implementer pre-flight work shared with #41 and #42)
- #44 Agent prompt rules-as-pointers convention — refactor agent prompts to point at CLAUDE.md sections instead of duplicating; verify reliability on representative agent before wide adoption

Estimated total: ~3–4 hours. Items share scope (the dispatch-implementer pre-flight work spans #41, #42, #43's Finding 4) so they compose naturally into one session.

**Phase 2.5 trigger:**
- Physical iPhone deployment: when Group D needs real mic hardware

**Phase 5 kickoff:**
- #13 /dispatch-research slash command

**Phase 5 Group C kickoff:**
- #49 Re-enable Thread Performance Checker and Main Thread Checker — verify post-V3-fix that the workaround is no longer needed
- #50 `xcode` MCP server failing on Claude Code startup — bundle with #49 as MCP/tooling hygiene before Group C

**Phase 6 kickoff:**
- #46 Local-only diagnostics for performance tuning — natural bundle with SwiftData persistence work

**Phase 7 kickoff:**
- #22 Design language direction — @design-system subagent decision
- #32 User-tunable latency/accuracy slider — after 5 real meetings if defaults wrong (may fire later)
- #40 Group D UI deferred concerns — 7 visual concerns from end-of-group gate

**Before MVP 1:**
- #16 TranscribingProtocolTests cancel-test timing race
- #24 Test isolation strategy (Swift Testing parallel-execution misattribution)
- #25 TranscriptionActor.awaitUpstreamDrained → DEBUG-only extension
- #26 LanguageRouter scheduling-assumption violation test
- #34 JP-WER head-to-head benchmark — only if MVP 1 quality disappoints
- #38 TranscriptionActorTests withLock unused-result warning
- #48 LFM2ModelLoader mid-load cancellation violation test — V3 was renamed in commit a49a93b to honestly reflect that it no longer asserts cancellation propagation; replacement test still owed

**MVP 1 acceptance gate:**
- #10 App Store submission — 30 days personal use + 3 colleagues independently asking

**Post-MVP-1 (triggered by real-meeting evidence):**
- #5 LFM2 fine-tuning on Roche terminology — 5+ meetings reveal consistent terminology errors
- #6 Speaker diarization — 5+ meetings where "who said what?" is top pain
- #7 Multi-language beyond JA↔EN — named colleagues whose language can't be handled
- #8 Live caption sharing to second device — meeting partners specifically request access
- #9 Custom glossary — fine-tuning feels like overkill but terms keep failing
- #35 Test larger LFM2 models on iPhone 17 Pro Max — 5+ meetings if 350M misses keigo
- #36 Evaluate Gemma 4 / TranslateGemma — only if expanding beyond JA↔EN

**Calendar trigger:**
- #18 Quarterly platform sanity review — August 2026

**Anthropic platform features (fire on platform release):**
- #1 Outcomes (Managed Agents) — after Phase 4 + Phase 5 ship
- #2 Dreaming research preview — after 2-3 months active development
- #3 Advisor strategy (Opus advises Sonnet) — budget pressure or confidence about agent execution
- #4 Auto mode for Claude Code — GA release for Max users

**Conditional / monitored:**
- #21 WhisperKit model variant — locked at turbo-632MB, monitored for Argmax recommendation drift
- #23 Subagent MCP-inheritance — auto-revalidation when Anthropic ships fix
- #45 Liquid AI / LFM2 model updates monitoring — weekly brief watches for variants, ENJP-MT releases, LEAP SDK changes
- #47 LFM2 cache strategy — revisit after diagnostics (#46) ships AND 5+ real meetings show >50% within-meeting cache hit rate

**Reference material — read before related work:**
- #51 Swift Concurrency cancellation bridging — three-mechanism gotcha. Read before writing any test gate or production code that bridges awaiter cancellation through unstructured Task or continuation. Pattern guidance is the deliverable; no action required until a future bridging surface needs it.

## Agent stack

11 subagents in `.claude/agents/`:

| Agent | Purpose |
|-------|---------|
| build-doctor | Diagnoses and fixes Xcode build failures |
| code-reviewer | Reviews git diff before commit, blocks CLAUDE.md violations |
| device-deployer | iOS code signing, provisioning, physical device deployment |
| doc-researcher | Verifies API/framework details against official sources only |
| feature-planner | Produces numbered implementation plan, surfaces decisions for human approval |
| git-historian | Conventional Commits messages, branches, PR descriptions |
| performance-profiler | Memory leaks, thermal, battery, latency regressions |
| swift-implementer | Implements Swift 6 / SwiftUI features from approved plans |
| swift-tutor | Explains Swift / SwiftUI / SwiftData / iOS using project examples |
| test-writer | Writes Swift Testing tests for new code |
| ui-reviewer | Captures simulator screenshots, audits hierarchy/color/typography/a11y |

No design agent exists. Decision deferred to Phase 7 kickoff per V3 #22.

## How to use this file

**For new chat sessions:** read this file plus CURRENT_STATE.md to orient. The two files together describe the full project arc and the current position within it.

**For Claude Code agents:** read this file as part of project bootstrap. CLAUDE.md describes the rules; this file describes the plan; PHASE_4_HANDOFF.md describes the current phase's locked decisions.

**When state changes:** update CURRENT_STATE.md (live state) and this file (when phases ship or scope changes). Both files are durable truth sources, not chat-session artifacts.

**When new V3 entries are added:** update the trigger map above to place the entry at the right firing point.

**When a phase scope is defined or changes:** update the relevant Phase N section in detail.
