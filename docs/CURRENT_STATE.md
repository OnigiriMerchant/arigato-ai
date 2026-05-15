# Current State — Arigato AI

Last updated: 2026-05-15 — Pre-Group-C tooling hygiene bundle COMPLETE. V3 #49 (TPC + MTC re-enable) and V3 #50 (`xcode` MCP startup failure) both resolved this session. Branch ready to push (3 commits ahead of origin/main). Group C kickoff via `@feature-planner` is the next action — no prerequisites blocking.

## Most recent commit
- 44f41ae docs(v3): close #49 (TPC + MTC re-enable verified clean) + dispute regression entry
- Most recent production commit: a49a93b fix(group-b): resolve V3 deadlock by reordering gate release before cancellation await

## Toolchain
- **Xcode**: 26.5 (Build 17F42)
- **SDK**: iOS 26.5
- **Swift**: 6.3.2
- **Default simulator**: iPhone 17 Pro Max — UUID `930EC6EA-DA72-4A38-ABFF-583AD70B28D4`. XcodeBuildMCP resolves `useLatestOS: true` against installed sim runtimes; current install has iOS 26.5 runtime present (CLAUDE.md note "no 26.5 sim created yet" is now stale, see Workflow risks below).
- **TPC + MTC re-verification (2026-05-15)**: 167/167 tests passing in 62.5s with `-parallel-testing-enabled NO`, Thread Performance Checker + Main Thread Checker enabled at default, NO `OS_ACTIVITY_DT_MODE=disable` workaround. 0 errors, 0 new warnings beyond pre-existing V3 #38 (TranscriptionActorTests withLock unused-result). The workaround was never persisted in project files — it was passed ad-hoc per `test_sim` invocation. Confirms the "testmanagerd hang" diagnosis in the V3 backlog was misattributed; the real cause was the V3 cancellation deadlock fixed in `a49a93b`.

## Phase status
- Phase 4 (WhisperKit/ArgmaxOSS streaming transcription): ✅ **SHIPPED in full**.
- Post-Phase-4 workflow automation bundle (2026-05-11): ✅ **SHIPPED**.
- Phase 5 strategic walkthrough (2026-05-12): ✅ **COMPLETE**. PHASE_5_HANDOFF.md drafted with six locked architectural decisions.
- **Phase 5 Group A** (domain types + Translating protocol): ✅ **SHIPPED**.
- **Phase 5 Group B** (LEAP SDK + LFM2ModelLoader + AppBootstrapper extension): ✅ **SHIPPED**.
- **Pre-Group-C tooling hygiene bundle (2026-05-15)**: ✅ **COMPLETE**.
  - V3 #50 (`xcode` MCP startup failure): resolved via hybrid approach — kept the MCP for `DocumentationSearch` + `RenderPreview` capabilities, added `.claude/hooks/auto-open-xcode.sh` SessionStart hook that auto-launches Xcode.app with this project. Wired in both `.claude/settings.json` (checked-in) and `.claude/settings.local.json` (gitignored). CLAUDE.md gained "Xcode MCP server dependency" section. doc-researcher / build-doctor / ui-reviewer prompts updated to reference DocumentationSearch as canonical Apple-side source. New monitoring V3 entry filed for hook friction.
  - V3 #49 (TPC + MTC re-enable): zero-edit resolution. Full suite passes clean with defaults. Bonus log scan of the 2026-05-13 hang log confirms the "testmanagerd regression" diagnosis was misattributed — execution died exactly at the V3 deadlock test. Future hangs should diagnose the stuck test name first, not reflexively re-disable TPC.
- 167/167 tests passing post-Group-B and post-hygiene-bundle. 0 errors. Pre-existing withLock warning at `TranscriptionActorTests.swift:51` (V3 #38, still deferred to pre-MVP-1 hardening).
- All six Phase 5 architectural decisions still locked. LEAP iOS SDK v0.9.4 pinned. LFM2-350M-ENJP-MT quantization `Q5_K_M` per Decision 1.

## Next planned action
- **Phase 5 Group C kickoff**: `TranslationActor` + sentence-boundary buffer + `LiquidCacheOptions` in-memory cache config. Consumes `LanguageRouter.currentLanguage` from Group D Phase 4; emits `AsyncStream<TranslatedSegment>`. Per PHASE_5_HANDOFF.md Group C section.
- **Group C plan**: dispatch `@feature-planner` for a numbered Group C plan. No prerequisites blocking — tooling hygiene bundle has shipped.
- **Reference material to skim before Group C**: V3 #51 Swift Concurrency cancellation bridging — three-mechanism gotcha. Group C adds significant `AsyncStream` and `Task` surface area; the pattern guidance applies whenever bridging awaiter cancellation across unstructured Tasks or continuations.

## Active prerequisites for Phase 5 Group C
- **None blocking.** Tooling hygiene done. All Group B + post-hygiene test verification is green; branch is ready to push.
- Group C plan via `@feature-planner` is the gate for Group C implementation. Plan must include the "Doc-researcher pre-flight: ran on YYYY-MM-DD against [URL]. Findings: [summary]" line per V3 #41's rule (LiquidCacheOptions cache mechanics is the load-bearing pre-flight target).
- Subagent MCP-inheritance fallback rule remains in CLAUDE.md (V3 #23 monitored).
- Push protocol active: `git log origin/main..HEAD` before any push; targeted push after the three-reviewer gate.
- CLAUDE.md sections active: Rollback safety, Concurrency design discipline, feature-planner output discipline, swift-implementer scope-and-decision discipline, code-reviewer auto-BLOCKING "Doc-researcher pre-flight discipline", new "Xcode MCP server dependency".

## V3 backlog items relevant to upcoming work
- **Reference material — read before related Group C work:**
  - **#51 Swift Concurrency cancellation bridging — three-mechanism gotcha** — pattern guidance, no action required until a future bridging surface needs it
- **Pre-MVP-1 hardening:**
  - #16 TranscribingProtocolTests cancel-test timing race
  - #25 TranscriptionActor.awaitUpstreamDrained → DEBUG-only extension
  - #26 LanguageRouter scheduling-assumption violation test
  - #38 TranscriptionActorTests withLock unused-result warning
  - **#48 LFM2ModelLoader mid-load cancellation violation test** — V3 was renamed to honestly reflect that it no longer asserts cancellation propagation; replacement test still owed
- **Next workflow automation pass** (not blockers for Phase 5):
  - #41 / #42 / #43 / #44 — dispatch-implementer slash command pre-flight + agent prompt hygiene + rules-as-pointers refactor
- **Phase 6 kickoff:**
  - #46 Local-only diagnostics for performance tuning — bundles with SwiftData work
- **Phase 7 kickoff:**
  - #22 design language direction + @design-system subagent decision
  - #40 Group D UI deferred concerns (7 visual concerns from end-of-group gate)
- **Calendar trigger:**
  - #18 Quarterly platform sanity review — August 2026
- **Monitored:**
  - #21 WhisperKit model variant — locked at turbo-632MB
  - #23 Subagent MCP-inheritance — fallback rule in CLAUDE.md
  - #45 Liquid AI / LFM2 model updates — weekly brief
  - #47 LFM2 cache strategy — conditional on diagnostics evidence
  - **NEW: xcode MCP SessionStart hook monitoring** — watch for hook friction (slow Xcode cold-start blocking session, inappropriate firing, mcpbridge behavior changes in future Xcode releases). Revisit triggers logged in V3_BACKLOG.md.
- **Recently resolved (2026-05-15):**
  - #49 Re-enable Thread Performance Checker and Main Thread Checker ✅
  - #50 `xcode` MCP server failing on Claude Code startup ✅

## Process trim (still active)
- Doc-researcher pre-flight mandatory for third-party tool config changes per V3 #41 + code-reviewer Step 11 BLOCKING rule.
- Screenshot cadence: hard pauses, decision points, surprises only.
- V3 backlog hygiene: log entries as encountered (not deferred to end of session). Group B's V3 follow-ups (#48 / #49 / #50 / #51) all logged within session and in trigger map. #49 + #50 closed this session.
- Checkpoint discipline: every step that builds + tests clean commits as `checkpoint(group-N-step-M)` before next dispatch.
- Concurrency design discipline: explicit scheduling assumptions in doc-comments + at least one violation test per actor/AsyncStream/Task-spawning design.

## Working tree
- Clean post-commit.
- Branch: main
- Origin/main: 3 commits behind local. Push pending after this state-refresh.

## Local-only artifacts
- Tag pre-recovery-snapshot/group-c → 4a57d30 (forensic snapshot of pre-recovery Group C Phase 4 state — local only, not pushed)
