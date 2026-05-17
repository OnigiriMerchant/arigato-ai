# Pre-MVP-1 V3 Holistic Review

**Date**: 2026-05-17
**Trigger**: end-of-Group-D three-reviewer gate complete, 0 BLOCKING.
**Status**: approved by user; hardening sprint dispatches against this list.

**Bucket counts**: B1 = 6 entries (incl. B1.0) · B2 = 2 entries · B3 = ~30 entries · B4 = 12 entries · Appendix (newly-filed) = 1 entry.

**Sprint effort total**: 9.5–19h. Under 20h scope-drift ceiling, at top of 8–17h calibration band.

---

## Bucketing criteria

**Bucket 1 — MVP-1 ship blocker.** Any one of:
- (a) App cannot launch into a functional state without it
- (b) Core flow breaks without it (start → capture → transcribe → translate → stop → save → review)
- (c) Locked product decision shipped in a state that contradicts its spec (broken promise — even if invisible to the user)
- (d) Hard build/test infrastructure block

**Bucket 2 — MVP-1 polish.** Shippable without it, but the fix is worth doing while sprint work is already touching adjacent code OR it materially improves device-testing.

**Bucket 3 — Post-MVP-1 deferred.** Phase 6+ scope, edge case below any-reasonable-user-gesture threshold, optimization at scale we don't have yet, or workflow/tooling improvement.

**Bucket 4 — Closed / superseded.** Decision reversed, absorbed into a later change, or trigger never materialized.

**Tie-breaker**: when an entry could fit two buckets, classify to the more-deferred bucket. Bias to keep MVP-1 lean.

---

## Bucket 1 — MVP-1 ship blockers

| # | Entry | Trigger criterion | Effort |
|---|---|---|---|
| **B1.0** | **LEAP SDK skill v0.10.4.3 phantom-version reconcile** (`.claude/skills/leap-sdk/SKILL.md`) | (d) soft variant. Pre-flight for B1.1 will read this skill to verify SDK API surface. Wrong version reference contaminates pre-flight findings. Must land BEFORE B1.1 doc-researcher dispatches. | ~30–60 min |
| B1.1 | **LFM2 model download fix** (V3 `b851dad` + 3 amendments) | (a) App cannot launch. `StartupErrorView` fires every launch. | 4–12h (SDK-API-dependent) |
| B1.2 | **Swift 6 mode build warnings** (V3 `66d08b0`) | (d) Three of five warnings are Swift 6 language mode errors. Build breaks when strict mode tightens. | ~2.5h |
| B1.3 | **Cumulative-load timing race in cancellation-ordering tests** (V3 `395e104`, bundles `#16`) | (d) soft variant. Suite-green signal can't be trusted at ~1-in-5 first-run flake. Bundles `TranslationProtocolTests.translate_burstThenCancel` + `MeetingPipelineTests.pipeline_stop_...` (same `FakeTranslator` root cause). | ~1–2h |
| B1.4 | **UI #9 Context A — toolbar ShareLink + remove cluster Share no-op** | (c) Locked product decision shipped in contradicting state. Labeled "Share" button does nothing on tap. | ~1–2h |
| B1.5 | **StartupErrorView debug bypass** (*new entry, see appendix*) | (d) soft variant. Unblocks parallel UI device testing while LFM2 fix proceeds. | ~30 min |

**Sprint subtotal: 9.5–19h.**

---

## Bucket 2 — MVP-1 polish

| # | Entry | Why it earns the slot | Effort |
|---|---|---|---|
| B2.1 | **`TranscriptionActorTests withLock` unused-result warning** (`#38`) | Bundle with B1.2 Swift 6 work — already in warning-cleanup mindset. Pure free-ride. | ~5 min |
| B2.2 | **Scroll animation timing tuning** (Step 9a) | Iterative feel-check during MVP-1 device-testing window. *Not a Claude Code dispatch.* Tune duration in-device if it feels off. | ~10–15 min per iteration, in-device only |

---

## Bucket 3 — Post-MVP-1 deferred

Grouped by trigger family. All entries have zero MVP-1 blocker criteria firing.

### Pre-MVP-1 hardening candidates the V3 backlog flagged → defer

| Entry | Criterion not met | Trigger when |
|---|---|---|
| `#16` TranscribingProtocolTests cancel-test timing race | (d) doesn't flake on M5 today | Already bundled into B1.3 |
| `#25` TranscriptionActor.awaitUpstreamDrained → DEBUG-only extension | Quality polish only; production behavior unaffected | If seam visibility becomes a concern |
| `#26` LanguageRouter scheduling-assumption violation test | Missing test for a correct contract; sprint doesn't touch `LanguageRouter` | **If router regression observed** |
| `#48` LFM2ModelLoader mid-load cancellation violation test | Doc-comment claims contract; no production bug manifest. Test needs new scaffolding (1–2h). Cost/value bad. | Real bug surfaces |
| `#24` Test isolation strategy | Group C crash misattribution already painful but resolved | Next crash-misattribution event |

### Pass 1 standalone INFO entries (all doc-comment-only)

| Entry | Why deferred |
|---|---|
| AppBootstrapper.assumeIsolated unenforced for non-main callers | Doc-comment only. ~5 min. |
| Auto-save `persistCompleted` phase enumeration doc-polish | Doc-comment only. ~5 min. |
| ContentView onboarding-pending invariant not doc-asserted | Doc-comment only. ~5 min. Structurally enforced in MVP-1. |

### Workflow automation / CLAUDE.md updates (next workflow automation pass)

| Entry | Effort | Trigger |
|---|---|---|
| Phase-2 view trio convention — CLAUDE.md | ~15 min | Next workflow automation pass |
| Agent verification rigor — CLAUDE.md | ~15 min | Same |
| Project-default-isolation pattern — CLAUDE.md | ~30 min | Same |
| Step 15 STOP-#5 not surfaced — CLAUDE.md | ~20 min | Same |
| Dispatch brief STOP rules supersede session-level — CLAUDE.md | ~15 min | Same |
| `#41` Doc-researcher trigger for third-party config | ~30 min | Same |
| `#42` feature-planner output channel rigidity (dispatch-implementer pivot) | ~30 min | Same |
| `#43` Agent prompt hygiene (5 INFO findings) | ~50 min | Same |
| `#44` Agent prompt rules-as-pointers convention | ~1–2h | Same |
| `#39` Adopt Anthropic Opus 4.7 prompting best practices | ~30 min | Same |
| `#31` Process trim re-evaluate | ~30 min | Same |
| `#29` Test infrastructure as agent blind spot (Step 8 fix) | Variable | Phase 5+ library extraction |
| `/update-state` self-referential commit noise | ~15 min | Same |
| `#37` AudioCaptureViewModel router param: optional → required | ~10 min | Post-Group-D cleanup |
| `#23` Subagent MCP-inheritance — monitor | — | Anthropic ships fix |

### Dead-code cleanup

| Entry | Effort |
|---|---|
| Remove dead router-drain path from AudioCaptureViewModel | ~30 min |
| LanguageRouter.routedHistory retire (chrome-only consumer) | ~30 min |

### Discoverability / pattern-capture (no code work)

| Entry | Why deferred |
|---|---|
| SwiftData ModelContext lookup primitive (`model(for:)` crash workaround) | Workaround works in production. Entry is future-discoverability for new `@ModelActor` work. |

### Group C follow-ups (trigger-based)

| Entry | Trigger when |
|---|---|
| TranslationActor queue cap revisit | `actor.droppedNewestCount() > 0` observed in real meeting |
| ModelRunner exclusive ownership invariant | Code-review gate; fires only if a PR introduces a new caller |
| LEAP SDK cancellation semantics confirmation | LEAP SDK ships explicit doc |
| SentenceBuffer clock-injectable refactor | Test-suite perf sweep OR new time-sensitive buffer responsibility |
| SentenceBuffer multi-boundary provenance accuracy | Visible mistiming on hop-overlapped sentences OR persistence/replay features need it |

### Phase 6 work

| Entry | Effort |
|---|---|
| `#46` Local-only diagnostics for performance tuning | ~1–2 days |
| LFM2 prompt cache effectiveness benchmark | ~1–2h instrumentation + analysis once data accumulates |
| `#47` LFM2 cache strategy revisit | Needs `#46` + 5+ real meetings + >50% within-meeting cache hit rate |
| SwiftData VersionedSchema migration | Files when entity-evolution actually fires |
| Migrate meeting title generation to Foundation Models summarization | Files when title-rewrite follow-up dispatch lands |
| Migrate history search to SQLite FTS5 (Decision #14) | On-device latency >200ms at 15K sentences OR transcript volume >50K sentences |

### Phase 7 design language

| Entry | Trigger |
|---|---|
| `#22` Design language direction — @design-system subagent decision | Phase 7 kickoff |
| `#40` Group D UI deferred concerns (4 remaining of 7) | Phase 7 kickoff |
| `#32` User-tunable latency/accuracy slider | After 5 real meetings if defaults wrong |
| Re-onboarding from Settings | Phase 7 settings polish OR MVP-1 device-test feedback |
| Onboarding visual identity polish — replace SF Symbol hero | V3 #22 design language pass |
| MeetingListView empty state, StartupErrorView icon, app icon | V3 #22 design language pass |

### Post-MVP-1 (real-meeting evidence)

| Entry | Trigger |
|---|---|
| `#5` LFM2 fine-tuning on Roche terminology | 5+ meetings reveal consistent terminology errors |
| `#6` Speaker diarization | 5+ meetings where "who said what?" is top pain |
| `#7` Multi-language beyond JA↔EN | Named colleagues' languages unhandled |
| `#8` Live caption sharing to second device | Meeting partners specifically request access |
| `#9` Custom glossary | Fine-tuning feels overkill but terms keep failing |
| `#35` Test larger LFM2 models | 5+ meetings if 350M misses keigo |
| `#36` Evaluate Gemma 4 / TranslateGemma | Only if expanding beyond JA↔EN |
| `#34` JP-WER head-to-head benchmark | Only if MVP 1 quality disappoints |
| Onboarding A/B copy testing ("Continue without translation") | Post-MVP-1 user feedback on framing |
| `#10` App Store submission | 30 days personal use + 3 colleagues independently asking |
| First-launch download UX measurement | Post-MVP-1 testing reveals download time >2 min on Wi-Fi |
| **MeetingListView surface loadError when present** (cascade B) | Real user reports OR Phase 6 polish pass |
| **Permission-revoked mid-meeting overlay** (cascade C) | Post-MVP-1 user research OR Phase 6 polish pass |

### Anthropic platform features

| Entry | Trigger |
|---|---|
| `#1` Outcomes (Managed Agents) | After Phase 5 ships, when translation outputs exist to grade |
| `#2` Dreaming research preview | 2–3 months active development corpus |
| `#3` Advisor strategy | Budget pressure OR confidence about agent execution work |

### Monitored

| Entry | Watch |
|---|---|
| `#21` WhisperKit model variant — locked at turbo-632MB | Argmax recommendation drift |
| `#45` Liquid AI / LFM2 model updates | Weekly brief |
| xcode MCP SessionStart hook | Friction signal |
| Claude Code feature adoption (`/goal`, `/ultrareview`, `xhigh`, `claude agents`) | Pilot opportunity |
| Claude Code programmatic tool calling | Workflow automation pass evaluation |
| Xcode auto-update interrupts active work | Next occurrence |
| swift-implementer false-GREEN build reporting | Workflow risk |
| ui-reviewer MCP-inheritance datapoints | Recurrence pattern |
| Xcode 26.3 native agentic coding (`xcrun mcpbridge`) | Automation permission bug resolution |
| Cleaner ios-simulator-skill installation | Upstream plugin.json fix |

### Calendar

| Entry | When |
|---|---|
| `#18` Quarterly platform sanity review | August 2026 |

### Reference material (no action)

| Entry | Use |
|---|---|
| `#51` Swift Concurrency cancellation bridging — three-mechanism gotcha | Read before related work |

---

## Bucket 4 — Closed / superseded

| Entry | Why obsolete |
|---|---|
| `#49` Re-enable Thread Performance Checker + Main Thread Checker | ✅ Shipped 2026-05-15 |
| `#50` xcode MCP startup failure | ✅ Shipped 2026-05-15 |
| `#4` Auto mode for Claude Code | ✅ GA for Max users, in active use |
| `#14` Workflow automation narrow bundle (feature-planner self-critique + /dispatch-implementer) | ✅ Shipped 2026-05-11 |
| `#28` feature-planner concurrency scheduling-assumption rule | ✅ Shipped 2026-05-11 |
| `#30` swift-implementer scope-and-decision discipline sharpening | ✅ Shipped 2026-05-10 |
| LFM2 cache strategy (original in-memory framing) | Superseded by xcframework-driven Decision 4 revision (2026-05-15) |
| Cross-surface friction between Claude.ai and Claude Code | Superseded by narrow-bundle entry (strategic stays in Claude.ai by design) |
| `@plan-reviewer` subagent | Superseded by `#14` narrow bundle |
| LanguageRouter `routedTranscripts()` multiplex | Resolved 2026-05-10 by Group D Step 1 (option 2 chosen) |
| Step 7 MeetingControlsView consumes Phase-4 DesignTokens | Absorbed by Step 9b design-system consolidation |
| `#13` /dispatch-research slash command | Phase 5 in progress without it; manual flow stable. Re-evaluate at Phase 6 kickoff if friction returns. |

---

## Appendix — Newly-filed entry surfaced during the review

### StartupErrorView debug bypass

- **What**: Add `#if DEBUG` branch in `ContentView` that ignores `startupError` (specifically `LFM2LoaderState.failed`) and routes to `TranscriptLiveView` anyway. Translation fails at runtime (LFM2 not loaded), but UI shell + Whisper transcription work normally.
- **Why this is V3-worthy and Bucket 1**: Without it, the hardening sprint forces strictly serial work — LFM2 fix MUST complete before any UI device testing can begin. With it, UI device testing (history, search, export, onboarding, settings — all locked-decision-verifiable surfaces) runs parallel to LFM2 fix. Recovers ~half a session of wall-clock time.
- **Criterion fire**: (d) soft variant — unblocks parallel device-test workflow.
- **Effort**: ~30 min. Single-file change to `ContentView.swift`. Optional: surface the bypass in a debug-only Settings toggle to make it discoverable without rebuilds.
- **Bundle with**: B1.1 LFM2 fix dispatch (do this *first* in the dispatch sequence so device testing can begin in parallel).
- **Cross-references**: V3 `b851dad` (LFM2 download), `StartupErrorView` routing in `ArigatoAIApp.swift:57-67`.
- **Severity**: Bucket 1 — workflow unblocker.

---

## Sequencing for the hardening sprint

**Sprint Day 1 (sequential prereqs)**:
```
1. B1.0  LEAP SDK skill v0.10.4.3 reconcile   ~30-60 min  ← MUST land before B1.1 pre-flight
2. B1.5  StartupErrorView debug bypass        ~30 min     ← unblocks parallel UI device-test
3. B1.1  doc-researcher pre-flight dispatch   variable    ← gates B1.1 implementation effort
```

**Sprint Days 2–3 (parallel-capable)**:
```
4. B1.1  LFM2 model download fix              4–12h       ← biggest unknown
5. B1.2  Swift 6 mode build warnings          ~2.5h       ← concurrency-annotation mindset
   B2.1  withLock unused-result warning       ~5 min      ← free-ride bundle with B1.2
6. B1.3  Cumulative-load timing race          ~1–2h       ← test-discipline mindset
7. B1.4  UI #9 Context A toolbar ShareLink    ~1–2h       ← isolated, last
```

**During MVP-1 device test window (in-device, not a Claude Code dispatch)**:
```
8. B2.2  Scroll animation timing tuning       iterative feel-check
```

**Total**: 9.5–19h focused work over 2–3 sessions. UI device testing begins in parallel after B1.5 lands (~1h in).

---

## Approval trail

- Drafted in Claude.ai strategic session 2026-05-17 against full `docs/V3_BACKLOG.md` + end-of-Group-D three-reviewer gate findings + ROADMAP `Before MVP 1` list + Group D queued entries.
- Bucketing framework + criteria approved by user before walkthrough.
- Cascade entries (UI #9 Context A, MeetingListView loadError, Permission-revoked overlay) walked through per-criterion with user pushback gate; Entry A locked to Bucket 1, Entries B+C to Bucket 3.
- Refinements applied post-walkthrough: `#26` LanguageRouter test → Bucket 3 "router regression observed" trigger only (sprint doesn't touch `LanguageRouter`); LEAP SDK skill reconcile promoted to B1.0; B2.2 clarified as in-device feel-check.
- Hardening sprint dispatches against this list.
