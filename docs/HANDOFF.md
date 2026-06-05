# Arigato AI — Session Handoff (READ FIRST)

> **You are a fresh Claude.ai chat picking up an ongoing project.** This doc orients you. Read it fully before responding to the user's first real request. Then read the docs in the "Read-first sequence" below. Do not improvise project state — verify against the docs.

## 0. Read-first sequence

The exact order to get oriented:

1. This file (`docs/HANDOFF.md`) — workflow, rules, landmines.
2. `docs/CURRENT_STATE.md` — authoritative live state (what's done, what's next, recent commits).
3. `docs/ROADMAP.md` — the phase plan + MVP-1 feature list.
4. `docs/V3_BACKLOG.md` — deferred decisions with trigger conditions.
5. `CLAUDE.md` — project rules, stack, conventions (Claude Code's rules file, but the conventions apply to strategy too).
6. `docs/PRE_MVP1_REVIEW.md` — historical record of the pre-MVP-1 hardening sprint (reference only).

## 1. What Arigato AI is

On-device bidirectional Japanese↔English live meeting translator for iPhone 17 Pro Max. Built with Swift 6 / SwiftUI / SwiftData on iOS 26.4+, WhisperKit for ASR, LFM2-350M-ENJP-MT for translation (via LEAP iOS SDK v0.9.4). **Citizen-dev project**: the user (Jose) is a Marketing Executive at Roche, not a software engineer — he "vibe codes" via Claude as the engineering engine. **Privacy-first:** audio never leaves the device; transcripts stay on-device unless the user explicitly exports or copies. Personal use first, App Store later if it earns its way there. Current phase: **MVP-1 feature-complete, pending real-meeting validation** — see `docs/CURRENT_STATE.md` for the live state.

## 2. The two-surface workflow (CRITICAL — this is how the project runs)

- **Claude.ai (the strategic surface):** architectural decisions, plan review, recovery, dispatch-prompt authoring. Does **not** write production code directly. Produces clean dispatch prompts that get pasted into Claude Code.
- **Claude Code (the execution surface):** agentic implementation via subagents (`@swift-implementer`, `@code-reviewer`, `@ui-reviewer`, `@doc-researcher`, etc.). Reads the repo, writes code, runs tests, commits.
- **The loop:** user describes a goal to Claude.ai → Claude.ai produces a dispatch brief → user pastes it into Claude Code → Claude Code executes with phase gates → user pastes results back to Claude.ai for review → repeat.
- **GitHub sync:** Claude Code commits + pushes to `OnigiriMerchant/arigato-ai`; the Claude.ai project is GitHub-integrated, so a fresh chat reads current repo content on session start.
- **Phase-gate discipline:** dispatches use STOP gates (verify → decide → implement → commit). Claude Code stops before committing and waits for explicit go-ahead. **Push is ALWAYS separately gated — never pushed without explicit user authorization** (per `CLAUDE.md` "Don't" rule).

## 3. Doc map — which doc is authoritative for what

- **`docs/CURRENT_STATE.md`** → live project state. **The** source of truth for "where are we now." Updated every reconciliation pass.
- **`docs/ROADMAP.md`** → the phase plan (0–9) + the MVP-1 12-feature list with shipped/superseded status.
- **`docs/V3_BACKLOG.md`** → deferred decisions, future work, each with a trigger condition. Nothing here is active until its trigger fires.
- **`CLAUDE.md`** → project rules, stack, conventions, the "Don't" list. Claude Code's rules file.
- **`docs/PRE_MVP1_REVIEW.md`** → historical record of the pre-MVP-1 hardening sprint. Reference only, not live.
- **`docs/HANDOFF.md` (this file)** → orientation + workflow + behavioral guide. Semi-static.

## 4. Current state snapshot (defers to `CURRENT_STATE.md` for detail)

- **MVP-1: FEATURE-COMPLETE** as of `eea5abc` — all 12 features shipped or deliberately superseded; zero pending.
- **Zero ship-blockers** — B1.6 (SwiftData schema-registration mismatch) shipped at `32abc3e`; B1.1 (LFM2 v0.10.x) downgraded to v1.x, shipping on LEAP v0.9.4.
- **Remaining gate:** real-meeting validation (not build work).
- **Build phase: Phase 7 (UI polish, V3 #22) — UNDERWAY.** The onboarding brand-moment hero is complete (Geist Pixel wordmark + Geist Mono tagline + reusable Mono Key button + terminal power-on entrance animation), shipped + pushed. Remaining (none blocking): app-wide button rollout, `timestampForeground`→`metadataForeground` convergence, `@ui-reviewer` mandate tighten, V3 #40 deferred concerns, remaining brand moments (empty state / `StartupErrorView` icon / app icon). Detail: `docs/CURRENT_STATE.md` §Phase 7.
- **HEAD = `93f724b`** — last **app-code** commit is `c7577a2` (Phase 7 onboarding entrance animation). Everything pushed; working tree clean.
- **Public README showcase added (2026-06-04 session, `23fde20`→`93f724b`, 8 commits, no app-code change).** A GIF-driven `README.md` for sharing the repo (Liquid AI hackathon) + 6 transparent **iPhone-mockup** media files in `docs/media/`: the split-screen live-translation **concept** (light/dark), an animated **welcome screen** with a smooth fade-blink terminal cursor + a **pixel-ninja brand mascot**, and framed **transcript** stills (real `MeetingDetailView` UI). Honesty posture baked in: WIP banner; live GIF = concept; transcript = real UI; **mascot = brand concept, NOT a shipped in-app asset**. Detail: `CURRENT_STATE.md` §2026-06-04 session.
- **Strategic gap surfaced (not yet acted on):** feature-complete in code + unit-tested, but **never validated in a real meeting or on a physical device** (user: "looks empty and non-functional"). On-device end-to-end validation (Phase 2.5) is the highest-leverage next step and doubles as the hackathon demo.
- **Tooling:** Claude Code **v2.1.162** on Opus 4.8 (auto-updated from 2.1.156, 2026-06-04); subagent stack on Opus 4.8 via the `opus` alias except `git-historian` (Haiku 4.5) — `doc-researcher` + `test-writer` upgraded `sonnet`→`opus` at `14846d5`.

> For live detail (test counts, recent commits, working-tree status), **always read `docs/CURRENT_STATE.md`** — this snapshot may lag.

## 5. How Claude.ai should behave on this project

- **Lead with the answer, no preamble.** Citizen-dev framing: plain language, explain the "why," flag what the user might not know to ask.
- **Flag trade-offs** in any shipped recommendation: what worked but isn't ideal, what "better" looks like, what the next-iteration polish would be.
- **Anti-sycophancy:** challenge flawed reasoning, don't validate just because the user seems committed. The user explicitly values pushback.
- **VERIFY, DON'T ASSERT.** Never pattern-match what a correct answer "looks like." For any current-state fact (SDK versions, API surfaces, product behavior, upstream issue status), fetch primary sources — GitHub issue/release URLs, official docs, or the live-docs MCPs. This rule exists because confident-but-wrong claims have cost real reconciliation time on this project.
- **Dispatches to Claude Code:** numbered, bounded scope, phase gates, stop-before-commit, no-push-without-authorization. Surface architecture decisions for the user to make rather than silently choosing.
- **Deliver dispatch briefs inline as code blocks** (four-backtick outer fence if the brief contains nested triple-backtick blocks), NOT as file artifacts.

## 6. Known landmines (things that bit us — don't re-step)

- **LFM2 / LEAP SDK:** Shipping on `Liquid4All/leap-ios` v0.9.4 (legacy repo) **by decision, not block.** The `@rpath` launch crash that blocked the unified `Liquid4All/leap-sdk` v0.10.x (issue #5 — framework-bundle path vs shipped plain-dylib form) was **fixed upstream in v0.10.9 (2026-05-29)** per the release notes (ref #265; caveat: not binary/device-verified by us). Issue #5 is still open but **stale** — open ≠ unfixed. The project is **NOT** adopting v0.10.9 (decision locked 2026-05-31): no v0.10.x iOS feature benefits a JA↔EN translator, and SDK version ≠ translation quality (model-side). Upgrade only on the standing material-benefit principle. The old escalation cadence is **closed** (moot). Full reconciliation: `docs/V3_BACKLOG.md` "LEAP SDK v0.10.x migration — upstream fix shipped (v0.10.9), NOT adopting" + `docs/CURRENT_STATE.md` "Upstream status".
- **Doc drift:** This project has repeatedly drifted between what docs claim and what code does. **Every reconciliation must verify against actual code / primary sources, not summarize stale annotations.** The current "feature-complete" claim was earned by reading all 12 features in code, not asserted.
- **The migration catastrophe:** A prior Claude.ai chat compaction caused severe context loss; reconciling took a full Claude Code session. This doc exists to prevent the repeat. **If you are the fresh chat reading this — the system worked.**
- **Stale-version hallucination:** A phantom SDK version (`v0.10.4.3`) and a "v0.10.x doesn't exist" error both came from trusting training data over live sources. The **`liquid-docs` MCP** (`https://docs.liquid.ai/mcp`) and the **`xcode` MCP's `DocumentationSearch`** are the live-docs channels. Use them.
- **Apple FoundationModels:** Permanently dropped as the AI-summary path (4096-token hard context window, Apple-confirmed unchangeable — unsuitable for 30+ min meetings). AI summary ships as **copy-transcript → paste into Claude app**. In-app Anthropic Claude API integration is a single consolidated V3 entry with trigger conditions.
- **SourceKit "errors" in Claude Code:** Stale-indexer noise has appeared repeatedly (`Cannot find type 'X' in scope`, `No such module 'Y'`, even spurious type-check timeouts). **Authoritative build/test verification is via XcodeBuildMCP from the main session, NOT the harness's SourceKit diagnostics.** Clean builds + green tests via `mcp__XcodeBuildMCP__build_sim` / `test_sim` are the truth.
- **`@ui-reviewer` visual-estimation errors (2026-05-31):** the `@ui-reviewer` subagent can `Read` images but **cannot run pixel/numeric measurements**, so its precise *spatial* (size/position/alignment) and *contrast* (WCAG-ratio) figures are visual estimates. It produced two confident, wrong BLOCKs in one session — disabled-button contrast (claimed ≈2.85:1; **measured 5.74:1**) and an onboarding wordmark "1.7× size-pop + re-center" (**measured identical**: cap 66px, left x=100, span x[100..588] in both typing-complete and settled). **Verify such claims by measurement** (stdlib `zlib` PNG decode + the WCAG luminance formula; PIL/ffmpeg are NOT installed in this env, `qlmanage -t` yields a poster frame) before acting on a spatial/contrast BLOCK. Mandate-tighten is a tracked Phase 7 follow-up (V3). Distinct from the older `@ui-reviewer` MCP-inheritance gap (V3 #23).
- **`record_sim_video` (AXe) is unreliable for animation capture (2026-05-31):** XcodeBuildMCP's `record_sim_video` failed twice — `stop` returned *"could not determine the recorded file path from AXe output"* and wrote no MP4. **Fallback that works:** native `xcrun simctl io <UDID> recordVideo --codec h264 <path>` started detached, then **`kill -INT`** to finalize (clean moov-atom write; `kill -9` corrupts the file). Use this for on-device animation/feel capture; `qlmanage -t` extracts a poster frame to sanity-check the result.

## 7. The standing rule

**Verify, don't assert.** No shortcuts, no pattern-matching, only real work. When uncertain, fetch the primary source or read the actual code. A correct "I need to check" beats a confident wrong answer — the latter has cost this project real time.

## 8. Before migrating to a new Claude.ai chat

This doc is only as good as its freshness at migration time. Before switching to a new chat, run a pre-migration refresh so the new chat reads accurate state:

1. In the CURRENT chat, confirm all work is committed + pushed to `origin/main` (0 ahead / 0 behind).
2. Dispatch to Claude Code: *"Pre-migration refresh: reconcile `CURRENT_STATE.md` to HEAD, then update `docs/HANDOFF.md` Section 4 snapshot to match. Verify, don't assert. Stop before commit."* Review, commit, push.
3. THEN open the new chat. First message: *"Read `docs/HANDOFF.md`, then follow its read-first sequence."*

The durable sections (0, 2, 3, 5, 6, 7) rarely change. Section 4 (snapshot) is the one that drifts — the refresh above keeps it honest. This protocol exists because a prior un-refreshed migration caused severe context loss.
