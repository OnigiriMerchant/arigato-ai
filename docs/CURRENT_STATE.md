# Current State — Arigato AI

Last updated: 2026-05-11 after post-Phase-4 workflow automation bundle shipped.

## Most recent commit
- ed41695 docs(v3): log rules-as-pointers convention for next workflow pass

## Phase status
- Phase 4 (WhisperKit/ArgmaxOSS streaming transcription): ✅ **SHIPPED in full**. Groups A, B, C, D all complete.
- Post-Phase-4 workflow automation bundle (2026-05-11): ✅ **SHIPPED**. 15 + 1 commits on origin/main (13 bundle steps + 2 hygiene-pass commits + 1 V3 #44 logging commit). origin/main up to date. See V3 entries #41/#42/#43/#44 for follow-on work deferred to next workflow pass.
- Group A: domain types + Transcribing protocol.
- Group B (commits 3b3b29c, 2ba5831, 174ace7): WhisperKit SPM + WhisperModelLoader + WhisperEngine seam + WhisperModelVariant + AppBootstrapper + StartupErrorView. fatalError eliminated from App.init recoverable path.
- Group C (commits 809d65e, e29176e, b04baf5, 8a8131f, d284d67, 6812231): RollingAudioBuffer + WhisperClient cascade + TranscriptionActor with hop-scheduler fix (bounded FIFO queue cap 4, oldest-drop overflow, deterministic awaitUpstreamDrained test seam) + LanguageRouter with N=2 consecutive-window disagreement gate + RoutedTranscript value type. @MainActor @Observable currentLanguage exposed for UI chrome binding.
- Group D (checkpoints 1780c83, 04c1f95, c16d683, 9f20c24, 9ff18b4 + Concern 6 fix 3b7c311): live transcription UI surface end-to-end. LanguageRouter routedTranscripts() multiplex resolved (Option 2 — dropped, replaced with @Observable routedHistory + resetSession). AppBootstrapper owns shared TranscriptionActor + LanguageRouter. AudioCaptureViewModel drains pipeline through router when injected. TranscriptLiveView with three-region layout (chrome / list / record control) + TranscriptRowDisplay/IndicatorChromeDisplay testability helpers. RecordControl injects bootstrapper.router → pipeline runs end-to-end. End-of-group gate ui-review surfaced 8 visual concerns; Concern 6 (duplicate "listening…" hint) fixed pre-push, locked by D4-T-concern6 regression test; remaining 7 deferred to Phase 7 (V3 #40).
- 125/125 tests passing post-Group-D. 0 errors. Pre-existing withLock warning at TranscriptionActorTests.swift:51 (V3 #38, deferred to pre-MVP-1 hardening).
- All eight Phase 4 architectural decisions still locked. WhisperKit v1.0.0 pinned 1.0.0..<2.0.0. Model variant: openai_whisper-large-v3-v20240930_turbo_632MB.

## Next planned action
- **Phase 5 kickoff**: LFM2 translation via LEAP iOS SDK v0.10.4.3. Translation dispatcher attaches at LanguageRouter's output (bound to authoritativeLanguage, not detectedLanguage — never sends a half-sentence through the wrong direction). Streaming bilingual text consumed by TranscriptLiveView.
- **Pre-Phase-5 prep (before dispatching @feature-planner):**
  - **Ghostty terminal onboarding** — migration from current terminal setup before Phase 5 dispatch starts moving fast.
  - **Strategic walkthrough in Claude.ai** of Phase 5 architectural decisions before invoking @feature-planner: translation dispatcher placement, `LiquidCacheOptions.enabled(path:)` usage, model warmup pattern, error-path semantics for translation failures during a live meeting, retry/fallback behavior, latency budget reconciliation with the existing Whisper streaming budget.
  - **Doc-researcher pre-flight against LEAP iOS SDK v0.10.4.3 docs** — verify SDK surface, model bundle loading, async streaming behavior, generation parameters. Required per V3 #41 "Doc-researcher trigger: third-party tool configuration changes" since LEAP SDK is a third-party dependency with version-specific behavior and the dispatch-brief layer pre-flight enforcement is not yet in place (deferred to V3 #41/#42/#43 next workflow pass).

## Active prerequisites for Phase 5
- **None blocking.**
- Open V3 items in the "Next workflow automation pass" group (#41 + #42 + #43 + #44) — not blockers for Phase 5 kickoff. Address opportunistically; bundles well as a ~3–4 hour session before Phase 5 dispatch starts moving fast, OR interleave with Phase 5 if appetite surfaces.
- Subagent MCP-inheritance fallback rule remains in CLAUDE.md (V3 #23 monitored).
- Push protocol active: `git log origin/main..HEAD` before any push during a group's lifetime; targeted single-commit push or skip when checkpoints are unpushed.
- CLAUDE.md sections active from Group C closure + 2026-05-11 workflow bundle: Rollback safety, Concurrency design discipline, feature-planner output discipline, swift-implementer scope-and-decision discipline. Plus code-reviewer's auto-BLOCKING "Doc-researcher pre-flight discipline" rule (Step 11) and doc-researcher's broadened scope + input-discipline rules (Step 9).

## V3 backlog items relevant to upcoming work
- **Next workflow automation pass** (deferred from the 2026-05-11 bundle; not blockers for Phase 5):
  - #41 Doc-researcher trigger: third-party tool configuration changes — code-reviewer BLOCKING rule shipped; remaining: dispatch-implementer slash command pre-flight template + CLAUDE.md cross-reference under "External dependency configuration"
  - #42 feature-planner output channel rigidity — deferred-implementation plan IS the dispatch-implementer slash command pre-flight work (shared with #41)
  - #43 Agent prompt hygiene — INFO findings from workflow bundle gate (5 findings, ~50 min; Finding 4 is the load-bearing dispatch-implementer pre-flight work shared with #41/#42)
  - #44 Agent prompt rules-as-pointers convention — refactor agent prompts to point at CLAUDE.md sections instead of duplicating; verify reliability on code-reviewer (most rule-dense agent) before wide adoption (~1–2 hr)
- **Phase 5 kickoff:**
  - #13 /dispatch-research slash command — fires at Phase 5 kickoff for the LEAP iOS SDK doc-researcher pre-flight pattern
- **Pre-MVP-1 hardening:**
  - #16 TranscribingProtocolTests cancel-test timing race
  - #25 TranscriptionActor.awaitUpstreamDrained → DEBUG-only extension
  - #26 LanguageRouter scheduling-assumption violation test
  - #38 TranscriptionActorTests withLock unused-result warning
- **Phase 7 kickoff:**
  - #22 design language direction + @design-system subagent decision
  - #40 Group D UI deferred concerns (7 visual concerns from end-of-group gate)
- **Calendar trigger:**
  - #18 Quarterly platform sanity review — August 2026
- **Monitored:**
  - #21 WhisperKit model variant — locked at turbo-632MB
  - #23 Subagent MCP-inheritance — fallback rule in CLAUDE.md, monitored via daily brief

## Process trim applied at Group C closure (still active)
- Doc-researcher pre-flight checks: **now mandatory for third-party tool config changes** per V3 #41 + code-reviewer Step 11 BLOCKING rule. Other pre-flight checks remain situational.
- Screenshot cadence: hard pauses, decision points, surprises only — main-session screenshots performed during Group D end-of-group gate as ui-reviewer fallback.
- Supervisory model: routine continuations go directly to Claude Code; strategic-thinking-partner role for architectural decisions, plan reviews, recovery situations.
- V3 backlog hygiene: log entries as encountered (not deferred to end of session).
- **Re-evaluate trigger fired** at end of Group D AND during 2026-05-11 workflow automation bundle retrospective. No changes proposed; trim carries forward into Phase 5.

## Working tree
- Clean at the time of this commit
- Branch: main
- Origin/main: **up to date** — all 16 workflow-automation-bundle-related commits landed (13 bundle + 2 hygiene + 1 V3 #44 logging). This state-refresh commit will be the 17th to push.

## Local-only artifacts
- Tag pre-recovery-snapshot/group-c → 4a57d30 (forensic snapshot of pre-recovery Group C state including C30 regression — local only, not pushed)
