# Current State — Arigato AI

Last updated: 2026-05-15 — Phase 5 Group B shipped. V3 deadlock resolved via Fix A; 167/167 tests green. Branch ready to push (11 commits ahead of origin/main). Group C kickoff is the next action.

## Most recent commit
- 95d31c2 docs(v3): log thread-checker re-enable, xcode MCP failure, and Swift concurrency cancellation-bridging gotcha post-Group-B
- Most recent production commit: a49a93b fix(group-b): resolve V3 deadlock by reordering gate release before cancellation await

## Toolchain
- **Xcode**: 26.5 (Build 17F42)
- **SDK**: iOS 26.5
- **Swift**: 6.3.2
- **Default simulator**: iPhone 17 Pro Max — UUID `930EC6EA-DA72-4A38-ABFF-583AD70B28D4`. XcodeBuildMCP resolves `useLatestOS: true` against installed sim runtimes; current install has iOS 26.5 runtime present (CLAUDE.md note "no 26.5 sim created yet" is now stale, see Workflow risks below).
- **Re-verification post-Fix-A**: 167/167 tests passing in 62s with `-parallel-testing-enabled NO`. 0 errors, 0 new warnings beyond pre-existing V3 #38 (TranscriptionActorTests withLock unused-result).

## Phase status
- Phase 4 (WhisperKit/ArgmaxOSS streaming transcription): ✅ **SHIPPED in full**.
- Post-Phase-4 workflow automation bundle (2026-05-11): ✅ **SHIPPED**.
- Phase 5 strategic walkthrough (2026-05-12): ✅ **COMPLETE**. PHASE_5_HANDOFF.md drafted with six locked architectural decisions.
- **Phase 5 Group A** (domain types + Translating protocol): ✅ **SHIPPED**.
- **Phase 5 Group B** (LEAP SDK + LFM2ModelLoader + AppBootstrapper extension): ✅ **SHIPPED**.
  - Step 1: LEAP SDK SPM add + `.swiftinterface` inspection.
  - Step 2: documented LEAP SDK swiftinterface findings (`b65a7e8`).
  - Step 3: `LFM2LoaderState` + `LFM2Engine` + `LFM2ClientFactory` (`3b581fd`).
  - Step 4: `LFM2ModelLoader` actor + tests + `FakeModelRunner` (`ca08abd`).
  - Step 6: extend `AppBootstrapper` to drive LFM2 load + warmup (`b202183`).
  - Step 7: wire `StartupErrorView` selection for LFM2 failures (`7056349`).
  - Swift 6 concurrency warnings in `AppBootstrapper` resolved (`d477924`).
  - V3 test deadlock investigation (`2008d96`) → Fix A (`a49a93b`) → V3 follow-up backlog entries (`95d31c2`).
- 167/167 tests passing post-Group-B. 0 errors. Pre-existing withLock warning at `TranscriptionActorTests.swift:51` (V3 #38, still deferred to pre-MVP-1 hardening).
- All six Phase 5 architectural decisions still locked. LEAP iOS SDK v0.9.4 pinned. LFM2-350M-ENJP-MT quantization `Q5_K_M` per Decision 1.

## Next planned action
- **Phase 5 Group C kickoff**: `TranslationActor` + sentence-boundary buffer + `LiquidCacheOptions` in-memory cache config. Consumes `LanguageRouter.currentLanguage` from Group D Phase 4; emits `AsyncStream<TranslatedSegment>`. Per PHASE_5_HANDOFF.md Group C section.
- **Pre-Group-C tooling hygiene bundle** (V3 #49 + #50, ~45–90 min): re-enable Thread Performance Checker and Main Thread Checker post-Fix-A (verify the workaround is no longer needed); investigate the `xcode` MCP server startup failure and decide fix vs remove. Bundle as one tooling pass before Group C plan review.
- **Reference material to skim before Group C**: V3 #51 Swift Concurrency cancellation bridging — three-mechanism gotcha. Group C adds significant `AsyncStream` and `Task` surface area; the pattern guidance applies whenever bridging awaiter cancellation across unstructured Tasks or continuations.
- **Group C plan**: dispatch `@feature-planner` for a numbered Group C plan once the tooling hygiene bundle has shipped (or in parallel, since the bundle is independent of plan-time work).

## Active prerequisites for Phase 5 Group C
- **None blocking.** All Group B test verification is green; branch is ready to push.
- Group C plan via `@feature-planner` is the gate for Group C implementation. Plan must include the "Doc-researcher pre-flight: ran on YYYY-MM-DD against [URL]. Findings: [summary]" line per V3 #41's rule (LiquidCacheOptions cache mechanics is the load-bearing pre-flight target).
- Subagent MCP-inheritance fallback rule remains in CLAUDE.md (V3 #23 monitored).
- Push protocol active: `git log origin/main..HEAD` before any push; targeted push after the three-reviewer gate.
- CLAUDE.md sections active: Rollback safety, Concurrency design discipline, feature-planner output discipline, swift-implementer scope-and-decision discipline, code-reviewer auto-BLOCKING "Doc-researcher pre-flight discipline".

## V3 backlog items relevant to upcoming work
- **Phase 5 Group C kickoff (next):**
  - **#49 Re-enable Thread Performance Checker and Main Thread Checker** — verify post-V3-fix that the workaround is no longer needed
  - **#50 `xcode` MCP server failing on Claude Code startup** — bundle with #49 as MCP/tooling hygiene before Group C
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

## Process trim (still active)
- Doc-researcher pre-flight mandatory for third-party tool config changes per V3 #41 + code-reviewer Step 11 BLOCKING rule.
- Screenshot cadence: hard pauses, decision points, surprises only.
- V3 backlog hygiene: log entries as encountered (not deferred to end of session). Group B's V3 follow-ups (#48 / #49 / #50 / #51) all logged within session and in trigger map.
- Checkpoint discipline: every step that builds + tests clean commits as `checkpoint(group-N-step-M)` before next dispatch.
- Concurrency design discipline: explicit scheduling assumptions in doc-comments + at least one violation test per actor/AsyncStream/Task-spawning design.

## Working tree
- Clean post-commit.
- Branch: main
- Origin/main: 11 commits behind local. Push pending after this state-refresh.

## Local-only artifacts
- Tag pre-recovery-snapshot/group-c → 4a57d30 (forensic snapshot of pre-recovery Group C Phase 4 state — local only, not pushed)
