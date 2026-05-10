# Current State — Arigato AI

Last updated: 2026-05-10 after Group D Step 2.

## Most recent commit
- 46e092f docs(v3): log TranscriptionActorTests withLock unused warning

## Phase status
- Phase 4 (WhisperKit/ArgmaxOSS streaming transcription): Groups A, B, C shipped. Group D in flight (Steps 1 + 2 of 6 shipped at checkpoint level; Step 3 in flight).
- Group A: domain types + Transcribing protocol.
- Group B (commits 3b3b29c, 2ba5831, 174ace7): WhisperKit SPM + WhisperModelLoader + WhisperEngine seam + WhisperModelVariant + AppBootstrapper + StartupErrorView. fatalError eliminated from App.init recoverable path.
- Group C (commits 809d65e, e29176e, b04baf5, 8a8131f, d284d67, 6812231): RollingAudioBuffer + WhisperClient cascade + TranscriptionActor with hop-scheduler fix (bounded FIFO queue cap 4, oldest-drop overflow, deterministic awaitUpstreamDrained test seam) + LanguageRouter with N=2 consecutive-window disagreement gate + RoutedTranscript value type. @MainActor @Observable currentLanguage exposed for UI chrome binding.
- Group D Step 1 (checkpoint 1780c83): routedTranscripts() multiplex V3 entry resolved — dead-stream method removed; routed transcripts now surfaced via @MainActor @Observable routedHistory on LanguageRouter. Single UI consumer pattern.
- Group D Step 2 (checkpoint 04c1f95): AppBootstrapper now owns shared TranscriptionActor + LanguageRouter instances. UI binds via the bootstrapper-owned router.
- 115/115 tests passing post-Step-2. 0 errors. Pre-existing withLock warning at TranscriptionActorTests.swift:51 (V3 #38, deferred to pre-MVP-1 hardening).
- All eight Phase 4 architectural decisions still locked. WhisperKit v1.0.0 pinned 1.0.0..<2.0.0. Model variant: openai_whisper-large-v3-v20240930_turbo_632MB.

## Next planned action
- Group D Step 3 (in flight): AudioCaptureViewModel drains pipeline through LanguageRouter when injected. Optional router param for incremental landing (V3 #37 logged for post-Group-D required-param promotion).
- Group D Step 4: TranscriptLiveView + ContentView rewire. Per-line detectedLanguage binding test added per user direction (binding-contract honesty: one-window mismatch is information, not a bug).
- Group D Step 5: RecordControl injects bootstrapper.router into AudioCaptureViewModel — activates pipeline end-to-end.
- Group D Step 6: end-of-group three-reviewer gate (@code-reviewer + @ui-reviewer + @git-historian) + push.
- UI binding split per ROADMAP: language-indicator chrome → LanguageRouter.currentLanguage (authoritative, stability over accuracy); transcript lines → RoutedTranscript.detectedLanguage (honest, one-window mismatch is information).

## Active prerequisites for Group D Steps 3–6
- None blocking.
- Subagent MCP-inheritance fallback rule remains in CLAUDE.md (subagents fall back to raw xcodebuild via Bash; main session verifies via XcodeBuildMCP).
- Push protocol (added 2026-05-10): run `git log origin/main..HEAD` before any push during a group's lifetime; surface unpushed checkpoints; default to targeted single-commit push (`git push origin <sha>:main`) or skip the push entirely.
- CLAUDE.md sections active from Group C closure: Rollback safety (mandatory checkpoint commits at every step boundary), Concurrency design discipline, feature-planner output discipline, swift-implementer scope-and-decision discipline.

## V3 backlog items relevant to upcoming work
- LanguageRouter routedTranscripts() multiplex: RESOLVED 2026-05-10 by Group D Step 1 (option 2)
- AudioCaptureViewModel router param: optional → required (#37): bundles with post-Phase-4 workflow automation
- TranscriptionActorTests withLock unused-result warning (#38): pre-MVP-1 hardening
- Test infrastructure as agent blind spot: bundles with post-Phase-4 workflow automation
- swift-implementer scope-and-decision discipline (sharpening): bundles with post-Phase-4 workflow automation
- feature-planner system prompt update — concurrency scheduling-assumption rule: bundles with post-Phase-4 workflow automation
- @feature-planner self-critique rules: bundles with post-Phase-4 workflow automation
- @dispatch-implementer slash command: bundles with post-Phase-4 workflow automation
- LanguageRouter scheduling-assumption violation test (#26): pre-MVP-1 hardening
- TranscriptionActor.awaitUpstreamDrained → DEBUG-only extension (#25): pre-MVP-1 hardening
- TranscribingProtocolTests cancel-test timing race (#16): pre-MVP-1 hardening
- WhisperKit model variant choice — turbo decoder, 632MB: locked, monitored via daily brief
- Subagent MCP tool inheritance: monitored via daily brief
- Quarterly platform sanity review: calendar trigger Aug 2026
- Phase 7 design language direction: trigger is Phase 7 kickoff (much later)

## Process trim applied at Group C closure (still active)
- Doc-researcher pre-flight checks: situational, not default
- Screenshot cadence: hard pauses, decision points, surprises only
- Supervisory model: routine continuations go directly to Claude Code; strategic-thinking-partner role for architectural decisions, plan reviews, recovery situations
- V3 backlog hygiene: log entries as encountered (not deferred to end of session)

## Working tree
- Clean at the time of this commit
- Branch: main
- Origin/main: in sync at 46e092f at the time of this commit; Step 3 checkpoint may exist locally and unpushed per Group D in-flight protocol

## Local-only artifacts
- Tag pre-recovery-snapshot/group-c → 4a57d30 (forensic snapshot of pre-recovery Group C state including C30 regression — local only, not pushed)
