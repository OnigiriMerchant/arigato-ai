# Arigato AI — Project Context

## What this is
On-device bidirectional Japanese↔English meeting translator for iPhone 17 Pro Max.
Personal use first, App Store later if it earns its way there.

## Stack
- iOS 26.4+, Swift 6, SwiftUI, SwiftData, Swift Testing
- WhisperKit via argmax-oss-swift v1.0.0+ (Apache-2.0) — Japanese + English ASR with auto language detection
- LFM2-350M-ENJP-MT via LEAP iOS SDK (pinned to `Liquid4All/leap-ios` v0.9.4; the unified `Liquid4All/leap-sdk` v0.10.x channel is upstream-blocked per issue #5 — see CURRENT_STATE "Upstream block status") — bidirectional JA↔EN translation
- Post-meeting AI summary: handled via an external workflow (Copy transcript → paste into the Claude app). No in-app AI integration in MVP-1; in-app summary via the Anthropic Claude API is tracked as a V3 entry.
- Bundle ID: com.jose.ArigatoAI

## Documentation map
- docs/ROADMAP.md — end-to-end project arc, phase status, V3 trigger map. Read alongside CURRENT_STATE.md to orient at session start.

## Setup

Fresh clones require Git LFS for the bundled LFM2 model file
(`ArigatoAI/Resources/Models/LFM2-350M-ENJP-MT-Q5_K_M.gguf`, ~260 MB).

After cloning:
```bash
brew install git-lfs       # if not already installed
git lfs install --local    # enable LFS hooks for this repo
git lfs pull               # pull the LFS-tracked files
```

Without LFS, the GGUF file appears as a small pointer file and the
app fails to load LFM2 at launch.

## Architecture rules
- All real-time inference is on-device. No network calls during meetings.
- Audio capture → Whisper streaming with language tag → router → LFM2 translate (JA→EN or EN→JA) → SwiftData persist → SwiftUI render.
- Each pipeline stage is its own actor or class. No god objects.
- Whisper language fallback uses consecutive-window disagreement gating (N=2). See LanguageRouter spec in PHASE_4_HANDOFF.md.
- Pre-warm both models at app launch to avoid cold-start glitches.
- Default toolchain: Xcode 26.5 (Build 17F42), iOS 26.5 SDK, Swift 6.3.2. Default simulator: iPhone 17 Pro Max on iOS 26.4.1 runtime (sim major.minor 26.4 intentionally matches the deployment target iOS 26.4, not the SDK 26.5; patch version is whatever 26.4.x sim Xcode ships — currently 26.4.1). XcodeBuildMCP picks the latest available sim runtime via useLatestOS: true — currently resolves to 26.4.1 because no 26.5 sim has been created (see V3 "Workflow risks" bonus item). The physical target device is iPhone 17 Pro Max — different screen size, safe-area insets, Dynamic Island. Never test against iPhone 17 Pro.

## Coding standards
- SwiftUI for all views. UIKit only when wrapping a system API that requires it.
- @Observable for view models (not @ObservableObject — this is Swift 6).
- SwiftData for persistence. No Core Data.
- async/await everywhere. No completion handlers in new code.
- Public types and methods get DocC doc comments.
- No force-unwraps in production code. Use guard/if-let.
- No fatalError to silence errors. Find the real cause.

## Design language (Phase 7)
Locked design language for all SwiftUI views. Full spec: `.claude/skills/swiftui-design/SKILL.md`. Verified iOS 26 API basis + the 5 collisions behind these rules: `docs/PHASE_7_DESIGN_RESEARCH.md`. Decisions: `docs/V3_BACKLOG.md` "Design language direction" (V3 #22). **@ui-reviewer owns enforcement.** Tokens live in `ArigatoAI/Design/DesignSystem.swift` (source of truth; thin `Color.*` forwarders in `DesignTokens.swift`) — use a token where one exists.

- **Source-led, per-line transcript hierarchy.** Each row leads with the spoken language (driven per line by `Sentence.sourceLanguage`, never hardcoded): source = `DesignSystem.Colors.transcriptSource` (primary), translation = `transcriptTranslation` (secondary). **Color-only** differentiation — same `.body` size AND weight, no weight/size delta, no italics/boxes. Metadata (timestamp + JA/EN tag) = `DesignSystem.Typography.metadataText` (SF Mono) + `Colors.metadataForeground`, tertiary.
- **Content surfaces are solid** — `DesignSystem.Colors.surfaceContent`. Never `.ultraThinMaterial` on content; `.ultraThinMaterial` is NOT Liquid Glass.
- **Liquid Glass = chrome/navigation only.** Standard toolbar items receive it **system-automatically** (iOS 26) — do NOT hand-apply `.glassEffect` to standard toolbar items (doubles the system glass, violates Apple perf guidance). Custom `.glassEffect` is only for genuine custom floating chrome, never content.
- **Ambient / particles: minimalist, non-content surfaces only** (onboarding hero / empty state / warmup orb) — never behind content. Any custom ambient must hand-build light/dark parity + a reduced-motion "calm" mode + hold 60fps.
- **Fonts.** System (SF Pro + Hiragino Sans, incl. CJK) for all text; SF Mono (`.monospaced` system design) for technical readouts/timestamps/tags. Two bundled Geist faces are **hero-scoped ONLY** (Phase 7 Step 5 — onboarding welcome screen; Latin-only, no CJK): Geist Pixel for the "ARIGATO AI" wordmark + app icon, Geist Mono for the onboarding tagline. No bundled font in transcript / body / metadata / content / chrome.
- **Light-first.** Design and verify light mode first, then confirm dark parity; prefer semantic system colors so light/dark + accessibility adaptation come free. Only the locked recording accents (`recordingActive`/`recordingReady`) are hard-coded RGB — WCAG-AA-check both modes by hand. Real Liquid Glass material renders fully only on device (Phase 2.5 check).

## Swift 6 concurrency
- New types default to `nonisolated` unless they touch main-actor UI state.
- Use `Sendable` for value types passed across actor boundaries.
- `@MainActor` only on view models bound to SwiftUI views, not on internal types.
- Test fakes: use `OSAllocatedUnfairLock` or actor-based fakes. Never `NSLock` — Swift 6 forbids it from async contexts.
- AVAudioPCMBuffer is non-Sendable. Copy to plain `[Float]` before crossing actor boundaries.
- When in doubt about isolation, invoke @doc-researcher rather than guessing.

## Concurrency design discipline
For any plan or implementation involving Swift actors, AsyncStreams, async sequences, or Task spawning, the design must explicitly document its execution-order assumptions and the system must include at least one test that violates those assumptions.

**Required in production code:**
- Doc-comment on the type or method specifying what the scheduler assumes about external pacing (e.g., "this design assumes the producer yields between iterations" or "this actor assumes inflight tasks complete before the next is enqueued").
- Doc-comment specifying what happens when those assumptions are violated (drops, queues, blocks, deadlocks, retries).

**Required in test code:**
- At least one test that drives the system in violation of its scheduling assumptions (greedy producer, stalled consumer, simultaneous spawn, etc.) and asserts correct behavior under that load.
- Doc-comment claims naming a specific test ID must be verified against that test's actual behavior. A doc-comment that names a test which does not enforce the contract is worse than not naming one — it creates false confidence that the rule is enforced. If no real violation test exists yet, document the gap explicitly and log a V3 entry with a concrete trigger.

**Rationale:** Swift actors prevent data races but not scheduling races. The Group C Step 9 hop-scheduler bug (single pending slot silently overwritten under greedy drain) shipped past plan review and implementation review because the scheduling assumption was implicit. C9 and C15 caught it only because their frame-feeding pattern happened to be unfriendly. Future concurrency code must make the assumption explicit so reviewers (human or agent) can challenge it.

**Subagents:** @feature-planner must surface scheduling assumptions in plan output for any actor/async work. @swift-implementer must implement the doc-comments. @code-reviewer must verify both the assumption is documented and the violation test exists.

## Build workflow
- Use XcodeBuildMCP for all build/test/run/deploy from the main session. Subagents may fall back to raw xcodebuild via Bash due to a known MCP-inheritance bug in Claude Code (see https://github.com/anthropics/claude-code/issues/25200). When this happens, the main session is responsible for verifying subagent build output via XcodeBuildMCP after subagent completion. Do not blanket-permit raw xcodebuild from the main session.
- Use Apple's xcode MCP for documentation search, SwiftUI preview snapshots, and live Xcode diagnostics. See "Xcode MCP server dependency" below.
- After every Swift edit, run mcp__xcodebuildmcp__build_sim_name_proj to verify.
- Run tests with mcp__xcodebuildmcp__test_sim_name_proj before committing.

### Xcode MCP server dependency
- The `xcode` MCP server is Apple's `xcrun mcpbridge`, shipped with Xcode 26.3+. It requires Xcode.app to be running with a project open — mcpbridge fatal-errors at startup if no Xcode process exists.
- Auto-launched via SessionStart hook `.claude/hooks/auto-open-xcode.sh` (wired in `.claude/settings.json`). The hook checks `pgrep -x Xcode`, opens this project's `.xcodeproj` if no Xcode is running, and waits briefly for the process to be detectable. Tolerant of failure — never blocks Claude Code start.
- Provides capabilities XcodeBuildMCP does not replicate:
  - `DocumentationSearch` — canonical Apple/Swift/iOS API source (semantic search over Apple Developer Docs + WWDC transcripts). Primary research tool for new APIs (SwiftUI iOS 26, FoundationModels, Liquid Glass, post-cutoff frameworks).
  - `RenderPreview` — SwiftUI preview snapshots without booting the simulator. Useful for fast UI iteration.
  - Live diagnostics — `XcodeRefreshCodeIssuesInFile`, `XcodeListNavigatorIssues` surface the indexer's current view.
- XcodeBuildMCP remains primary for builds, tests, simulators — it works independently of Xcode running. The two MCP servers are complementary, not redundant.
- If Xcode is closed mid-session, MCP calls through `xcode` will fail until Xcode is reopened. The MCP reconnects on next call after Xcode comes back up. Restarting Claude Code is not required.

## Rollback safety
Every step within a group that lands clean (production code compiles, tests pass) must be committed locally as a checkpoint before the next step is dispatched.

Commit message format: `checkpoint(group-N-step-M): brief description`

Checkpoint commits live on main alongside production commits. They are not pushed to origin until the three-reviewer gate approves the full group. The three-reviewer gate runs at end-of-group; checkpoint commits are rollback points, not production milestones.

**Rationale:** the absence of intermediate checkpoints in Group C caused a two-hour recovery procedure when an in-flight scope violation corrupted Step 9. Checkpoint commits at every step boundary are the cheapest possible defense against working-tree corruption between gates.

**Subagents:** @swift-implementer must commit as the final action of every step that builds clean and passes tests. @code-reviewer at the end-of-group gate may squash the chain into a single feature commit at its discretion if the chain reads cleaner that way, but the four-checkpoint chain itself must exist on main during the group's lifetime.

## Privacy and data rules
- No analytics. No tracking. No telemetry.
- No cloud sync of transcripts. iCloud / CloudKit explicitly disabled.
- API keys live in iOS Keychain or .env (gitignored). Never in source files.
- Transcripts never leave the device unless the user explicitly exports or copies them (Share / Copy write to the local share sheet / clipboard; the user chooses where to send them).

## Don't
- Don't add cloud features without explicit instruction.
- Don't add force-unwraps.
- Don't commit until the three-reviewer gate has run (@code-reviewer + @ui-reviewer + @git-historian) AND I have explicitly approved.
- Don't use deprecated APIs. If unsure, invoke @doc-researcher.

## External dependency configuration
- When picking configuration values for external dependencies (model identifiers, API endpoints, recommended defaults, tokenizer names, etc.), verify against BOTH the pinned version's source tree AND the maintainer's current README/docs.
- Source tree confirms what works in your pinned version. README confirms what the maintainer recommends. Locked architectural decisions in phase handoffs encode use-case-specific reasoning.
- When recommendations conflict with locked decisions, surface the collision before acting. The locked decision wins by default — it was made with full context. A recommendation overriding it requires explicit re-examination of the original reasoning.
- Pin specific values explicitly. Do not rely on dynamic-recommendation APIs (e.g., recommendedRemoteModels()) for MVP — explicit pinning is more predictable and easier to debug.
- Maintainer recommendations are general-purpose. Your use case may legitimately be in a niche the maintainer doesn't recommend on their front page. Phase 4 Decision 2 (large-v3-turbo) is an example — Argmax's README recommends 626MB non-turbo for accuracy, but our use case (live meeting captions) prioritizes latency, so turbo is the correct niche choice.
- When verifying SDK or upstream state (versions, repo names, issue status, API surface), always fetch PRIMARY sources — the GitHub issue/releases/tags page and the official docs — not training data or doc summaries. Training data is stale for fast-moving SDKs (the phantom-`v0.10.4.3` and "v0.10.x doesn't exist" errors both came from trusting summaries over live sources). Canonical live-docs channels: for Liquid AI, the **`liquid-docs` MCP** (`https://docs.liquid.ai/mcp`; installed 2026-05-25 at project scope via `claude mcp add --transport http liquid-docs https://docs.liquid.ai/mcp`; tools `search_liquid_docs` + `query_docs_filesystem_liquid_docs`); for Apple frameworks, the `xcode` MCP's `DocumentationSearch`. MCP tools load at session start — restart Claude Code after installing one. When the MCP is unavailable, fall back to `WebFetch` against the official docs/GitHub URLs.

## Project rhythm
- Plan first via @feature-planner. Implement second via @swift-implementer.
- Review every diff via @code-reviewer before commit.
- Use @swift-tutor whenever I ask "what does this do?" or "why this way?".
- Use @doc-researcher anytime an API/SDK detail is uncertain.

## feature-planner output discipline
@feature-planner surfaces decisions for human approval where reasonable engineers might disagree — architectural choices, contract shapes, test seam patterns, scope boundaries, decisions that affect locked architectural constraints. Internal organization (file naming, helper function placement, private method names, formatter-driven choices) does not require human surface and may be resolved by the planner directly.

Target: 5–8 surfaced decisions per group plan, not 15–20. The planner self-filters using this rule.

**Rationale:** in Group C the planner surfaced 16 decisions of which 7 were load-bearing and 9 were trust-the-planner. The 9 created cognitive load without adding value.

## swift-implementer scope-and-decision discipline
@swift-implementer dispatch briefs declare an absolute file scope. Files outside that scope must not be touched, including via formatter side effects, including via "consistency" renames, including for ostensibly minor reasons. If integration with another file appears to require modification, @swift-implementer must STOP and surface the question before touching any file outside scope.

"Surface in summary" is not "surface and pause." Post-hoc lists in the completion summary do not satisfy the rule. Architectural decisions outside the brief must be raised before code is written that depends on them, with a recommended answer, and pause for human confirmation.

Discarded tests require written diagnosis. If a test surfaces an unexpected failure, @swift-implementer must determine: was the test wrong, or did production code violate a contract? If the answer is unclear from inspection, that is a STOP condition — surface the test, the failure, the production code, and pause. Discarding a test without diagnosis is forbidden.

Doc-comment claims that name a specific test ID must be verified — open the named test, read it, confirm it actually enforces the documented contract. Naming a test that doesn't is worse than not naming one.

**Rationale:** Group C produced three independent failures of these rules — a Step 11 scope violation that corrupted Step 9, an `awaitUpstreamDrained` test seam added without surfacing, a discarded "greedy upstream burst" test that may have masked a real C30-class bug. The reviewer gate caught the third; the first two cost real recovery time.
