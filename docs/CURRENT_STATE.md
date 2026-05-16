# Current State — Arigato AI

Last updated: 2026-05-16 — Phase 5 **Group D Step 3 SHIPPED** (checkpoint, not pushed). MeetingSession @MainActor @Observable orchestrator + phase state machine landed in `ArigatoAI/Session/`. 23 new tests pass; full suite 243/243 (237 unit + 6 UI). Amendment 3 compatibility preserved (all MeetingStore calls awaited; no @MainActor-on-store assumption). Title-rewrite path at `finalizeStop` deferred — pre-authorized STOP fired (see Step 3 phase status bullet below).

## Most recent commit
- 4db5e61 checkpoint(group-d-step-3): MeetingSession orchestrator + phase state machine
- Previous commits: 281fe5e checkpoint(group-d-step-2): MeetingStore @ModelActor + DTOs, 45a3198 docs(group-d-step-1) test-baseline + Step 1 results, 21dfb9d checkpoint(group-d-step-1): add Meeting/Sentence @Model entities + SearchTextNormalizer
- Most recent production commit: 981c962 fix(group-c-step-10): capture sourceSegmentID once in startGeneration so partialChunk and completed agree

## Toolchain
- **Xcode**: 26.5 (Build 17F42)
- **SDK**: iOS 26.5
- **Swift**: 6.3.2
- **Default simulator**: iPhone 17 Pro Max — UUID `930EC6EA-DA72-4A38-ABFF-583AD70B28D4`. XcodeBuildMCP resolves `useLatestOS: true` against installed sim runtimes.
- **End-of-Group-C verification (2026-05-16)**: 207/207 tests passing (201 unit + 6 UI) in 63s with `-parallel-testing-enabled NO`, TPC + MTC enabled at default. 0 errors, 0 warnings. (Corrected 2026-05-16 from initially-documented 204/204 — three unit tests had landed during Group C closeout without the baseline figure being updated; see V3 backlog "Documentation hygiene" → CURRENT_STATE.md test-baseline drift entry.)

## Phase status
- Phase 4 (WhisperKit/ArgmaxOSS streaming transcription): ✅ **SHIPPED in full**.
- Phase 5 strategic walkthrough (2026-05-12): ✅ **COMPLETE**. Six locked architectural decisions, one revised post-xcframework-inspection (Decision 4 cache strategy → persistent Caches/ with maxEntries 1000).
- **Phase 5 Group A** (domain types + Translating protocol): ✅ **SHIPPED**.
- **Phase 5 Group B** (LEAP SDK + LFM2ModelLoader + AppBootstrapper extension): ✅ **SHIPPED**.
- **Pre-Group-C tooling hygiene (2026-05-15)**: ✅ V3 #49 (TPC/MTC re-enable) + V3 #50 (xcode MCP startup hook) both resolved.
- **Phase 5 Group C** (TranslationActor + sentence buffer + cache config): ✅ **SHIPPED 2026-05-16**. 10 step-checkpoints + 3 fix commits + 1 V3-entries commit. All four doc-comment ↔ violation-test linkages verified.
- **Phase 5 Group D pre-flight** (2026-05-16): ✅ **COMPLETE**.
  - Strategic walkthrough locked 20 UI decisions in `docs/GROUP_D_UI_DECISIONS.md` (commit `55275b0`).
  - Xcode IDE prompts cleared (String Catalog Symbol Generation + LeapSDK macro Trust & Enable, commit `1cec081`).
  - @feature-planner returned a 15-step plan in 3 phases (persistence + session core → UI shell → history/search/export/onboarding/settings). 6 surfaced decisions all approved: D-1 `@ModelActor` macro, D-2 persistence-first ordering, D-3 auto-save subscriber on bootstrapper, D-4 `UserDefaults` first-launch flag, D-5 explicit `.stoppingWithUndoWindow(deadline:)` state, D-6 `TranslationEvent.queueOverflow` extension (touches Group C's locked API — acceptable enum-case addition).
  - 4 parallel @doc-researcher runs filed in `docs/PHASE_5_GROUP_D_DOC_RESEARCH.md` (commit `5067613`):
    - **DR-1** (`@ModelActor` + Sendable): confirmed pattern + flagged FB13399899 (background executor inheritance) + FB13640004 (cascade-delete with explicit save).
    - **DR-2** (`ShareLink`): clean — `ShareLink(items: [URL])` handles Context C natively, no `UIActivityViewController` wrapper.
    - **DR-3** (SwiftData `localizedStandardContains`): three compounding concerns — hiragana↔katakana not in option set, documented runtime failures for to-many `contains-where` predicates (forums 731609, 747226, 758449), B-tree indexes can't accelerate `%term%` substring (sqlite.org optimizer). Decision #14 FTS5 trigger "likely fires on day one" — empirical 15K-row on-device benchmark added to Step 12 as gating test.
    - **DR-4** (SwiftUI ScrollView iOS 26): confirmed `.scrollPosition(_:anchor:)` + `.onScrollGeometryChange(for:of:action:)` as iOS 18+ canonical for split-screen layout.
  - 4 plan amendments approved:
    - Amendment 1 (Step 1): add `Sentence.searchableText: String` field + `SearchTextNormalizer` (`hiraganaToKatakana` transform + `.diacriticInsensitive, .caseInsensitive, .widthInsensitive` folding).
    - Amendment 2 (Step 12): restructure `MeetingStore.fetchAll(searchText:)` to flat `Sentence` fetch + Swift-side group-by-meeting (avoids documented to-many `contains-where` failures). On-device 15K-row benchmark gates Decision #14.
    - Amendment 3 (Step 8): initialize `MeetingStore` via `Task.detached { ... }` per FB13399899 workaround. New violation test asserts main-thread responsiveness under 100-call `appendSentence` burst.
    - Amendment 4 (Step 1): cascade-delete regression test exercising FB13640004 failure mode (explicit pre-delete save).
- **Phase 5 Group D Step 1 (shipped 2026-05-16)**: ✅ checkpoint `21dfb9d` landed locally on main — 214/214 tests passing (208 unit + 6 UI). Not pushed per protocol.
  - New files: `ArigatoAI/Persistence/Meeting.swift`, `ArigatoAI/Persistence/Sentence.swift`, `ArigatoAI/Persistence/SearchTextNormalizer.swift`, `ArigatoAITests/Persistence/MeetingEntityTests.swift`, `ArigatoAITests/Persistence/SearchTextNormalizerTests.swift`.
  - Implements UI decision #20 schema + Amendment 1 (`Sentence.searchableText` + `SearchTextNormalizer` with hiragana→katakana transform + diacritic/case/width folding) + Amendment 4 (FB13640004 cascade-delete regression test cites "FB13640004 / Apple Developer Forums 740649" by doc-comment).
  - No `@Attribute(.spotlight)` / `#Index` on `searchableText` per DR-3 (B-tree indexes can't accelerate `%term%` substring scans; FTS5 is the real fix, V3-tracked under decision #14).
  - pbxproj untouched — project uses `PBXFileSystemSynchronizedRootGroup`, new files auto-pick-up.
- **Phase 5 Group D Step 2 (shipped 2026-05-16)**: ✅ checkpoint `281fe5e` landed locally — 220/220 tests passing (214 unit + 6 UI). Not pushed per protocol.
  - New files: `ArigatoAI/Persistence/MeetingStore.swift`, `ArigatoAI/Persistence/MeetingSummary.swift`, `ArigatoAI/Persistence/MeetingDetail.swift`, `ArigatoAITests/Persistence/MeetingStoreTests.swift`.
  - Implements DR-1 §2 — DTOs are Sendable structs, never `@Model` instances cross-actor.
  - Scheduling-assumption doc-comment on `MeetingStore`; main-thread violation test deferred to Step 8 per Amendment 3.
  - No `fetchAll(searchText:)` — deferred to Step 12 per plan.
  - `searchableText` populated in `appendSentence` via `SearchTextNormalizer.normalize(source + ' ' + translation)`.
  - Lookup uses `FetchDescriptor<Meeting>` + `#Predicate` on `persistentModelID`. `model(for:)` rejected (crashes on stale IDs); `registeredModel(for:)` rejected (post-save eviction).
  - `nonisolated` added to `SearchTextNormalizer.normalize` so off-main `@ModelActor` can call without a main-actor hop — a Swift-6 fix surfaced and approved mid-Step-2.
  - pbxproj untouched — `PBXFileSystemSynchronizedRootGroup` auto-pickup.
- **Phase 5 Group D Step 3 (shipped 2026-05-16)**: ✅ checkpoint `4db5e61` landed locally — 243/243 tests passing (237 unit + 6 UI). Not pushed per protocol.
  - New files: `ArigatoAI/Session/MeetingSession.swift`, `ArigatoAI/Session/MeetingSessionPhase.swift`, `ArigatoAI/Session/MeetingSessionError.swift`, `ArigatoAI/Session/MeetingTitleGenerator.swift`, `ArigatoAITests/Session/MeetingSessionTests.swift`, `ArigatoAITests/Session/MeetingTitleGeneratorTests.swift`.
  - Locks **D3-A option 2** (persist on `.completed`, expose `liveChunks: [UUID: String]` via `@Observable` for streaming UI; delta semantics = append, verified against `TranslationActor.swift:619-627` `.chunk(delta)` handler) + **D3-B option 1** (`start(at:) → Void`; UI reads `@Observable phase`).
  - 4 named concurrency-violation tests: `consumeTranslationEvents_greedyProducer_doesNotDeadlockOrLoseEvents`, `consumeTranslationEvents_secondCall_cancelsFirst`, `undoStop_racesWithDeadlineExpiry_undoWinsIfDispatchedBeforeFire`, `requestStop_thenImmediateUndoStop_thenImmediateRequestStop_correctlyArmsFreshDeadline`. All 4 referenced by doc-comments on `consumeTranslationEvents(_:)`, `requestStop(at:)`, `undoStop()`, `finalizeStop(at:)`. Doc-comment ↔ named-test linkages verified.
  - Test infrastructure: **Option F3** (in-memory `MeetingStore` via `ModelConfiguration(isStoredInMemoryOnly: true)`; no protocol gymnastics). Reused project-local `TestClock` from `ArigatoAITests/Translation/TestClock.swift`. Tests yield once after `requestStop(at:)` to let the timer task register its `Clock.sleep` continuation before advancing the synthetic clock — TestClock only resolves already-registered continuations.
  - Amendment 3 compatibility preserved: all `MeetingStore` calls `await`ed; orchestrator makes no `@MainActor`-on-store assumption; Step 8 `Task.detached` workaround does not change `MeetingSession`'s API.
  - **Pre-authorized STOP fired**: title rewrite at `finalizeStop(at:)` deferred. `MeetingStore` has no `updateTitle(meetingID:title:)` method; the brief required surfacing before adding it. `MeetingSession.finalizeStop` calls `store.endMeeting` only and leaves a commented call-site showing the exact two-line addition needed once the method lands. `firstEnglishSentence` continues to be captured by the event pump so the follow-up dispatch is a surgical add (add `MeetingStore.updateTitle` + uncomment + flip one test assertion). The placeholder title set at `start(at:)` (bare timestamp via `MeetingTitleGenerator.makeTitle(startedAt:firstEnglishSentence: nil)`) is final under the current Step 3 contract.
  - Suite count exceeds brief minimum 241 by 2 (243 actual). 0 errors, 0 warnings.
  - pbxproj untouched.
- 243/243 tests passing. 0 errors, 0 warnings. All six Phase 5 architectural decisions remain locked. LEAP iOS SDK v0.9.4 pinned. LFM2-350M-ENJP-MT quantization `Q5_K_M`.

## Next planned action
- **Group D Step 4 dispatch — next session.** Step 3 shipped (checkpoint `4db5e61` local-only). Resume by reading: `docs/GROUP_D_UI_DECISIONS.md` (20 locked decisions), `docs/PHASE_5_GROUP_D_DOC_RESEARCH.md` (findings + 4 approved amendments, especially Amendment 3 for the eventual Step 8 `Task.detached` workaround), and the feature-planner's plan in conversation history.
- **Step 4 wires**: `TranscriptionActor` → `LanguageRouter` (Group A↔C bridge) → `TranslationActor` → `MeetingSession`. The orchestrator's `consumeTranslationEvents(_:)` accepts the `AsyncThrowingStream<TranslationEvent, any Error>` returned by `TranslationActor.translate(segments:direction:)`. Concurrency design discipline applies — scheduling assumptions + at least one violation test for the wiring.
- **Pre-authorized STOP follow-up**: `MeetingStore.updateTitle(meetingID:title:)` lands as a small surgical addition before Step 4 starts, OR as part of Step 4's dispatch brief if the wiring naturally touches `MeetingStore`. Recommended signature in the in-source comment on `MeetingSession.finalizeStop(at:)`. Test impact: 1 happy-path + 1 not-found in `MeetingStoreTests`, plus uncomment + assertion flip in `MeetingSessionTests.firstEnglishSentence_capturedOnFirstCompleted_usedInFinalizeStopTitleRewrite` and `deadlineExpiry_fromStoppingWithUndoWindow_transitionsToEnded_andCallsStoreEndMeeting`.
- **Plan structure**: Phase 1 (persistence + session core, Steps 1–5) → Phase 2 (UI shell + transcript view, Steps 6–10) → Phase 3 (history/search/export/onboarding/settings, Steps 11–15) → three-reviewer gate. Checkpoint commits per step per "Rollback safety."
- **Group D queued V3 entries (file at execution time, not pre-emptively)**:
  - "Migrate meeting title generation from first-sentence to Foundation Models summarization" — fires when title-rewrite follow-up dispatch lands (decision #12).
  - "Migrate history search to SQLite FTS5" — files when Step 12 lands OR fires immediately if Amendment 2's on-device benchmark exceeds 200ms.
  - "First-launch download UX measurement" — files when Step 14 lands (decision #16).
  - "SwiftData VersionedSchema migration" — files when Step 15 lands (decision #20).

## Active prerequisites for Phase 5 Group D Step 1
- **None blocking.** Pre-flight gate satisfied. Plan + amendments approved. All three queued docs commits pushed.
- @swift-implementer must follow CLAUDE.md "swift-implementer scope-and-decision discipline" — absolute file scope from the plan; STOP-and-surface on any out-of-scope question; written diagnosis required for discarded tests; doc-comment claims naming a specific test ID must be verified against the named test's actual behavior.
- @code-reviewer applies "Concurrency design discipline" — every actor/AsyncStream/Task addition must doc-comment its scheduling assumption AND have a named violation test that actually enforces it. Step 1 has no concurrency surface but later steps do — track this through the chain.
- Push protocol active: `git log origin/main..HEAD` before any push; targeted push after the three-reviewer gate at end-of-Group-D.
- CLAUDE.md sections active: Rollback safety, Concurrency design discipline, feature-planner output discipline, swift-implementer scope-and-decision discipline, code-reviewer auto-BLOCKING "Doc-researcher pre-flight discipline", "Xcode MCP server dependency."

## V3 backlog items relevant to upcoming work
- **Group D Step 1 (next session):**
  - **#22 design language direction + @design-system subagent decision** — Step 9 (split-screen `TranscriptLiveView` refactor) is the trigger.
  - **#40 Group D UI deferred concerns** (7 visual concerns from Group C end-of-group gate).
  - **7 Group C end-of-group entries filed 2026-05-16** (V3_BACKLOG.md "Phase 5 Group C follow-ups"): TranslationActor queue cap revisit, ModelRunner exclusive ownership invariant, TranscriptionActor C16 test-seam backport, LEAP SDK cancellation semantics confirmation, SentenceBuffer clock-injectable refactor, SentenceBuffer multi-boundary provenance accuracy, TranslationProtocolTests post-cancel reusability flake.
- **Reference material — skim before related Group D work:**
  - **#51 Swift Concurrency cancellation bridging — three-mechanism gotcha** — relevant for Step 5 (`MeetingSession` undo-window Task) and Step 8 (bridge `AsyncThrowingStream` → `AsyncStream`).
- **Pre-MVP-1 hardening:**
  - #16 TranscribingProtocolTests cancel-test timing race
  - #25 TranscriptionActor.awaitUpstreamDrained → DEBUG-only extension (Group C TranscriptionActor backport entry has concrete reference pattern)
  - #26 LanguageRouter scheduling-assumption violation test
  - #38 TranscriptionActorTests withLock unused-result warning
  - #48 LFM2ModelLoader mid-load cancellation violation test
- **Next workflow automation pass** (not blockers for Phase 5):
  - #41 / #42 / #43 / #44 — dispatch-implementer slash command pre-flight + agent prompt hygiene + rules-as-pointers refactor
- **Phase 6 kickoff:**
  - #46 Local-only diagnostics for performance tuning (bundles with SwiftData work landing in Group D)
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
  - xcode MCP SessionStart hook monitoring — watch for friction
- **Recently resolved (2026-05-15 to 2026-05-16):**
  - #49 Re-enable TPC + MTC ✅
  - #50 xcode MCP startup failure ✅
  - LFM2 cache strategy SUPERSEDED by xcframework-driven Decision 4 revision ✅

## Process trim (still active)
- Doc-researcher pre-flight mandatory for third-party tool config changes per V3 #41 + code-reviewer Step 11 BLOCKING rule. Group D pre-flight executed (4 researchers, findings filed in `docs/PHASE_5_GROUP_D_DOC_RESEARCH.md`).
- Screenshot cadence: hard pauses, decision points, surprises only.
- V3 backlog hygiene: log entries as encountered. Group C's 7 follow-ups filed within session. Group D's 4 queued entries fire at step-execution time.
- Checkpoint discipline: every step that builds + tests clean commits as `checkpoint(group-N-step-M)` before next dispatch. Group C produced 10 checkpoints + 3 fix commits + 1 docs commit; Group D plan calls for ~15 checkpoints.
- Concurrency design discipline: explicit scheduling assumptions in doc-comments + at least one violation test per actor/AsyncStream/Task-spawning design. Group D's concurrency table maps each new actor/Task to its scheduling assumption + named violation test (see plan: `MeetingStore` burst test, `MeetingAutoSaver` greedy-producer test, `MeetingSession` undo-race test, debounced-search rapid-typing test, bridge router-throws test).
- Test seams `#if DEBUG`-gated up-front (Group C convention): `pendingSentenceCount()`, `droppedNewestCount()`, `awaitUpstreamDrained()` on `TranslationActor` all wrapped in `#if DEBUG`. TranscriptionActor backport pending. Step 7 will add `TranslationEvent.queueOverflow(sourceSegmentID:)` — a new event, not a `#if DEBUG` seam.
- Process finding from Step 3: dispatch brief STOP rules vs session-level decisiveness — see V3 backlog "Phase 5 Group D follow-ups" → "Dispatch brief STOP rules supersede session-level 'make the reasonable call' system-reminder" for precedence work. Revisit before Step 4 dispatch.

## Working tree
- Clean.
- Branch: main
- Origin/main: 7 ahead, 0 behind — Step 1 checkpoint + Step 1 docs + Step 2 checkpoint + Step 2 docs + Step 2 V3 entry + Step 3 checkpoint + Step 3 docs not pushed per protocol (push gated on three-reviewer gate at end-of-Group-D).

## Local-only artifacts
- Tag pre-recovery-snapshot/group-c → 4a57d30 (forensic snapshot of pre-recovery Group C Phase 4 state — local only, not pushed)
