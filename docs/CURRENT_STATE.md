# Current State — Arigato AI

Last updated: 2026-05-16 — Phase 5 Group C SHIPPED. TranslationActor + sentence buffer + cache config wired end-to-end with all four scheduling-assumption violation tests passing. Group D (UI integration into TranscriptLiveView + AudioCaptureViewModel) is the next action. UI working-intent captured in `docs/GROUP_D_UI_DECISIONS.md` for Group D strategic walkthrough. Branch is 15 commits ahead of origin/main, pending push.

## Most recent commit
- 3105c46 docs(group-d): capture UI intent from Group C walkthrough discussion
- Most recent production commit: 981c962 fix(group-c-step-10): capture sourceSegmentID once in startGeneration so partialChunk and completed agree

## Toolchain
- **Xcode**: 26.5 (Build 17F42)
- **SDK**: iOS 26.5
- **Swift**: 6.3.2
- **Default simulator**: iPhone 17 Pro Max — UUID `930EC6EA-DA72-4A38-ABFF-583AD70B28D4`. XcodeBuildMCP resolves `useLatestOS: true` against installed sim runtimes.
- **End-of-Group-C verification (2026-05-16)**: 204/204 tests passing (198 unit + 6 UI) in 63s with `-parallel-testing-enabled NO`, TPC + MTC enabled at default. 0 errors, 0 warnings.

## Phase status
- Phase 4 (WhisperKit/ArgmaxOSS streaming transcription): ✅ **SHIPPED in full**.
- Phase 5 strategic walkthrough (2026-05-12): ✅ **COMPLETE**. Six locked architectural decisions, one revised post-xcframework-inspection (Decision 4 cache strategy → persistent Caches/ with maxEntries 1000).
- **Phase 5 Group A** (domain types + Translating protocol): ✅ **SHIPPED**.
- **Phase 5 Group B** (LEAP SDK + LFM2ModelLoader + AppBootstrapper extension): ✅ **SHIPPED**.
- **Pre-Group-C tooling hygiene (2026-05-15)**: ✅ V3 #49 (TPC/MTC re-enable) + V3 #50 (xcode MCP startup hook) both resolved.
- **Phase 5 Group C** (TranslationActor + sentence buffer + cache config): ✅ **SHIPPED 2026-05-16**.
  - Step 1: `LFM2CachePathResolver` + typed error (`283bd63`).
  - Step 2: cache wiring in `LFM2ClientFactory` (`3640924`).
  - Step 3: `TranslationEngineEvent` + `LFM2Engine.translate` inference seam (`7b2131b`).
  - Step 4: `SentenceBuffer` + 11 tests including `C-T-VIOLATION-NO-PUNCT-WITH-SILENCE` (`b92c733`).
  - Step 5: `TranslationActor` scaffold (init + warmup + state) (`c74229d`).
  - Step 6: Session class + FIFO queue + drain task + silence-timer task + #if DEBUG seams + `C-T-VIOLATION-GREEDY-UPSTREAM` + project-local `TestClock` (`cb2dc16`).
  - Step 7: LFM2 dispatch loop + event mapping + `C-T-VIOLATION-SLOW-DOWNSTREAM` (`fa34b49`).
  - Step 8: `cancel()` via `Task.cancel()` + `CancellationError` catch + `C-T-VIOLATION-CANCEL-MID-GENERATION` (`e3b18fd`). Doc-researcher confirmed LEAP SDK's documented cancellation idiom (`Task.cancel()` on the consuming task; no `GenerationHandler.stop()` available for the AsyncThrowingStream variant); V3 #51 three-mechanism gotcha does NOT apply.
  - Step 9: violation test suite audit + sentence-boundary edge cases (`04dce65`). All four doc-comment ↔ test ID linkages independently verified.
  - Step 10: three-reviewer gate (code-reviewer APPROVED + git-historian APPROVED — KEEP chain + ui-reviewer N/A); UUID provenance fix (`981c962`); 7 V3 entries filed (`1fe83d8`).
  - Two MainActor-isolation fix commits (`5a8ca09`, `0a78e1a`) document Swift 6 gotchas — kept as standalone history per git-historian recommendation.
- 204/204 tests passing post-Group-C. 0 errors, 0 warnings. Pre-existing TranscriptionActorTests withLock warning is gone after recent Swift toolchain or test re-fixes.
- All six Phase 5 architectural decisions remain locked (Decision 4 revised version is the lock). LEAP iOS SDK v0.9.4 pinned. LFM2-350M-ENJP-MT quantization `Q5_K_M`.

## Next planned action
- **Phase 5 Group D strategic walkthrough**: discuss UI integration approach using `docs/GROUP_D_UI_DECISIONS.md` as the starting point. The doc captures 8 working-intent UX decisions from the Group C walkthrough conversation (button morphing, transcript-stays-on-stop, auto-save, export-scoped-to-history, pause/resume, undo-toast, multi-select delete/share) plus a long list of deferred sub-decisions for the walkthrough to lock.
- **Phase 5 Group D plan** (after walkthrough): dispatch `@feature-planner` for the numbered Group D plan. Group D wires `TranslationActor` into `AudioCaptureViewModel`, extends `TranscriptLiveView` with per-line Japanese/English row pair + "translating…" state, builds the meeting-state UI machine (idle/recording/paused/ended), implements auto-save to SwiftData (model schema is new — Group D scope), implements transcript history view + multi-select delete/share, implements export via iOS Share Sheet.
- **Reference material to skim before Group D**: V3 #51 Swift Concurrency cancellation bridging — still applies whenever bridging awaiter cancellation across unstructured Tasks; Group C's pattern (Task.cancel + catch is CancellationError + trailing Task.isCancelled guard) is the reference.

## Active prerequisites for Phase 5 Group D
- **None blocking implementation.** Group C shipped, all tests green.
- Group D plan via `@feature-planner` is the gate for Group D implementation. Plan must include the "Doc-researcher pre-flight: ran on YYYY-MM-DD against [URL]. Findings: [summary]" line per V3 #41's rule. Likely pre-flight targets: SwiftData schema migration patterns for iOS 26.4, `ShareLink` / `UIActivityViewController` Swift 6 surface, SwiftUI iOS 26 Liquid Glass design tokens.
- `docs/GROUP_D_UI_DECISIONS.md` is the working-intent input. Strategic walkthrough will lock the deferred sub-decisions (layout, typography, scroll behavior, color/theme, recording indicator, history layout, title generation, error states, first-launch experience, settings screen, accessibility, navigation).
- Push protocol active: `git log origin/main..HEAD` before any push; targeted push after the three-reviewer gate.
- CLAUDE.md sections active: Rollback safety, Concurrency design discipline, feature-planner output discipline, swift-implementer scope-and-decision discipline, code-reviewer auto-BLOCKING "Doc-researcher pre-flight discipline", "Xcode MCP server dependency".

## V3 backlog items relevant to upcoming work
- **Group D kickoff (next):**
  - **#22 design language direction + @design-system subagent decision** — Group D's typography/color/recording-indicator decisions are the trigger.
  - **#40 Group D UI deferred concerns** (7 visual concerns from end-of-group gate).
  - **New: 7 Group C end-of-group entries filed 2026-05-16** (in V3_BACKLOG.md "Phase 5 Group C follow-ups" section): TranslationActor queue cap revisit (trigger: any meeting test where queue hits cap), ModelRunner exclusive ownership invariant (code-review gate), TranscriptionActor C16 test-seam backport (mirror Group C's #if DEBUG pattern), LEAP SDK cancellation semantics confirmation (SDK doc update trigger), SentenceBuffer clock-injectable refactor (test perf trigger), SentenceBuffer multi-boundary provenance accuracy (Group D UI mistiming trigger), TranslationProtocolTests post-cancel reusability flake.
- **Reference material — read before related Group D work:**
  - **#51 Swift Concurrency cancellation bridging — three-mechanism gotcha** — pattern guidance for any new bridging surface.
- **Pre-MVP-1 hardening:**
  - #16 TranscribingProtocolTests cancel-test timing race
  - #25 TranscriptionActor.awaitUpstreamDrained → DEBUG-only extension (the Group C TranscriptionActor backport entry above is the same concern with a concrete reference pattern)
  - #26 LanguageRouter scheduling-assumption violation test
  - #38 TranscriptionActorTests withLock unused-result warning
  - #48 LFM2ModelLoader mid-load cancellation violation test
- **Next workflow automation pass** (not blockers for Phase 5):
  - #41 / #42 / #43 / #44 — dispatch-implementer slash command pre-flight + agent prompt hygiene + rules-as-pointers refactor
- **Phase 6 kickoff:**
  - #46 Local-only diagnostics for performance tuning — bundles with SwiftData work (some SwiftData arrives in Group D)
  - **LFM2 prompt cache effectiveness benchmark** — Phase 6 verifies whether `maxEntries: 1000` in Caches/ delivers measurable speedup
- **Phase 7 kickoff:**
  - #22 design language direction + @design-system subagent decision (also relevant to Group D)
  - #40 Group D UI deferred concerns
- **Calendar trigger:**
  - #18 Quarterly platform sanity review — August 2026
- **Monitored:**
  - #21 WhisperKit model variant — locked at turbo-632MB
  - #23 Subagent MCP-inheritance — fallback rule in CLAUDE.md
  - #45 Liquid AI / LFM2 model updates — weekly brief
  - **xcode MCP SessionStart hook monitoring** — watch for friction
- **Recently resolved (2026-05-15 to 2026-05-16):**
  - #49 Re-enable TPC + MTC ✅
  - #50 xcode MCP startup failure ✅
  - LFM2 cache strategy SUPERSEDED by xcframework-driven Decision 4 revision ✅

## Process trim (still active)
- Doc-researcher pre-flight mandatory for third-party tool config changes per V3 #41 + code-reviewer Step 11 BLOCKING rule.
- Screenshot cadence: hard pauses, decision points, surprises only.
- V3 backlog hygiene: log entries as encountered. Group C's 7 follow-ups (queue cap, ModelRunner ownership, TranscriptionActor backport, LEAP cancellation, SentenceBuffer clock-injection, multi-boundary provenance, FakeTranslator flake) all filed within session.
- Checkpoint discipline: every step that builds + tests clean commits as `checkpoint(group-N-step-M)` before next dispatch. Group C produced 10 checkpoints + 3 fix commits + 1 docs commit.
- Concurrency design discipline: explicit scheduling assumptions in doc-comments + at least one violation test per actor/AsyncStream/Task-spawning design. Group C added 4 violation tests across 2 production types.
- Test seams `#if DEBUG`-gated up-front (Group C convention): `pendingSentenceCount()`, `droppedNewestCount()`, `awaitUpstreamDrained()` on `TranslationActor` all wrapped in `#if DEBUG`. TranscriptionActor backport pending.

## Working tree
- Clean post-commit.
- Branch: main
- Origin/main: 15 commits behind local. Push pending after `/update-state`.

## Local-only artifacts
- Tag pre-recovery-snapshot/group-c → 4a57d30 (forensic snapshot of pre-recovery Group C Phase 4 state — local only, not pushed)
