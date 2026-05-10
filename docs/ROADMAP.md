# Arigato AI — Roadmap

On-device bidirectional Japanese↔English meeting translator for iPhone 17 Pro Max. Personal use first, App Store later if it earns it. Built with Swift 6 / SwiftUI / SwiftData on iOS 26.4+, WhisperKit for ASR, LFM2-350M for translation, Apple Foundation Models for cleanup tier 1, Anthropic API (Claude Opus 4.7) for cleanup tier 2.

This file is the single source of truth for the project arc. New chat sessions and Claude Code agents read this to orient. When state changes, update this file alongside CURRENT_STATE.md.

## MVP 1 definition

MVP 1 ships when the app is usable for real meetings, personal use only, no App Store. App Store submission triggers after 30 days personal use plus 3 colleagues independently asking for access.

The 12 features that constitute MVP 1:

**Core capture loop**
1. Start/stop meeting button (single tap each)
2. Live dual-line captions: Japanese on top, English below, last 3 lines visible
3. Auto-save every line to SwiftData as it finalizes (crash-resilient)
4. Pause/resume mid-meeting

**Meeting library**
5. Past meetings list, sorted by date
6. Meeting detail view, scrollable, copyable per line
7. Rename meeting (default: timestamp)
8. Delete with undo toast

**Export and post-process**
9. Export as Markdown (bilingual or English-only toggle)
10. Share sheet integration
11. AI summary on demand via Apple Foundation Models

**Settings**
12. Single settings screen: model warmup toggle, default export format, transcript retention period, microphone input override

Excluded from MVP 1, deferred to v2: speaker diarization, multi-language beyond JA↔EN, cloud sync, live caption sharing to second device, custom glossary.

## Phase status

| Phase | Scope | Status |
|-------|-------|--------|
| 0 | Environment setup | ✅ Shipped |
| 1 | Agentic stack | ✅ Shipped |
| 2 | First simulator deployment | ✅ Shipped |
| 2.5 | Physical iPhone deployment | ⏸️ Deferred (triggers when Phase 4 needs real mic hardware) |
| 3 | Audio capture foundation | ✅ Shipped |
| 4 | WhisperKit streaming transcription | 🚧 Group D pending (Groups A, B, C shipped) |
| 5 | LFM2 translation | ⏳ Pending |
| 6 | SwiftData transcript storage | ⏳ Pending |
| 7 | UI polish | ⏳ Pending |
| 8 | Export + ShareLink | ⏳ Pending |
| 9 | AI summary | ⏳ Pending |
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

### Phase 4 — WhisperKit streaming transcription (in progress)

Argmax's ArgmaxOSS package (post-rename of WhisperKit) integrated. Streaming JA + EN ASR with auto language detection per chunk. Confidence-based fallback to previous chunk's language. Model pre-warming at app launch to avoid cold-start glitch. Audio frames from Phase 3's AsyncStream become text segments here.

Groups A, B, C shipped. Group D is the active surface.

**Shipped:**
- Group A: domain types and Transcribing protocol
- Group B: WhisperKit SPM dependency, WhisperModelLoader actor, WhisperEngine seam, WhisperModelVariant enum, AppBootstrapper, StartupErrorView
- Group C: RollingAudioBuffer, WhisperClient cascade, TranscriptionActor (bounded FIFO queue cap 4, oldest-drop overflow, deterministic awaitUpstreamDrained test seam, end-of-stream drain), LanguageRouter (N=2 disagreement gate, @MainActor @Observable currentLanguage, Transcribing protocol conformance with lossy mapping)

**Group D scope:** TranscriptLiveView consuming AppBootstrapper.loaderState and the transcription stream. Language indicator chrome bound to LanguageRouter.currentLanguage (authoritative — stability over accuracy). Transcript lines bound to RoutedTranscript.detectedLanguage (honesty — one-window mismatch is information).

**First decision in Group D plan review:** evaluate the routedTranscripts() multiplex V3 entry. Three options on the table — refactor multiplex, drop the surface and use @Observable, restructure UI bindings.

**Eight locked architectural decisions** (see PHASE_4_HANDOFF.md): ArgmaxOSS package source, Whisper model large-v3-turbo, AppBootstrapper pre-warm pattern, 5s window with 1s hop streaming, consecutive-disagreement language gating with N=2, detectLangauge typo handling, openai_whisper-large-v3-v20240930_turbo_632MB variant, subagent MCP-inheritance fallback rule.

### Phase 5 — LFM2 translation (planned)

Liquid AI's LFM2-350M-ENJP-MT bidirectional model loaded via LEAP iOS SDK v0.10.4.3. Q5_K_M quantization for vibe check, Q5/Q8 bake-off for production. Translation dispatcher attaches at LanguageRouter's output, routes Whisper's authoritative language to the correct translation direction. Cache control via the `LiquidCacheOptions.enabled(path:)` API. Outputs streaming bilingual text.

The dispatcher consumes authoritativeLanguage (not detectedLanguage) — never sends a half-sentence through the wrong direction because the language gate already stabilized routing.

Includes model warmup at app launch (5-line addition addressing cold-start glitches per the warmup behavior observed during pre-build vibe checks).

### Phase 6 — SwiftData transcript storage (planned)

Replaces the default Xcode `Item.swift` scaffold with `MeetingLine` and `Meeting` models. Persists transcripts locally, no iCloud (privacy stance). Each line carries timestamps, original + translated text, language confidence, and metadata for route changes. Ready for export and AI summary phases to consume.

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

**End of Phase 4 (post-Group-D, before Phase 5 kickoff):**
- #14 Workflow automation narrow bundle: feature-planner self-critique rules + /dispatch-implementer slash command
- #28 feature-planner system prompt update — concurrency scheduling-assumption rule
- #29 Test infrastructure as agent blind spot
- #30 swift-implementer scope-and-decision discipline (sharpening)
- #31 Process trim re-evaluate
- #37 AudioCaptureViewModel router param: optional → required
- #39 Adopt Anthropic prompting best practices for Opus 4.7

**Phase 2.5 trigger:**
- Physical iPhone deployment: when Group D needs real mic hardware

**Phase 5 kickoff:**
- #13 /dispatch-research slash command

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
