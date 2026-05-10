# Current State — Arigato AI

Last updated: 2026-05-10 after Group D Step 1.

## Most recent commit
- 1780c83 Group D Step 1: LanguageRouter routedTranscripts() multiplex resolved (option 2 — dead-stream method removed, routed transcripts surfaced via @MainActor @Observable routedHistory)

## Phase status
- Phase 4 (WhisperKit/ArgmaxOSS streaming transcription): Groups A, B, C shipped. Group D in flight (Step 1 of 4 complete).
- Group A: domain types + Transcribing protocol.
- Group B (commits 3b3b29c, 2ba5831, 174ace7): WhisperKit SPM + WhisperModelLoader + WhisperEngine seam + WhisperModelVariant + AppBootstrapper + StartupErrorView. fatalError eliminated from App.init recoverable path.
- Group C (commits 809d65e, e29176e, b04baf5, 8a8131f, d284d67, 6812231): RollingAudioBuffer + WhisperClient cascade + TranscriptionActor with hop-scheduler fix (bounded FIFO queue cap 4, oldest-drop overflow, deterministic awaitUpstreamDrained test seam) + LanguageRouter with N=2 consecutive-window disagreement gate + RoutedTranscript value type. @MainActor @Observable currentLanguage exposed for UI chrome binding.
- Group D Step 1 (commit 1780c83): routedTranscripts() multiplex V3 entry resolved. Dead-stream method removed; routed transcripts now surfaced via @MainActor @Observable routedHistory on LanguageRouter. Single UI consumer pattern; no multiplex needed.
- 108/108 tests passing. 0 warnings, 0 errors.
- All eight Phase 4 architectural decisions still locked. WhisperKit v1.0.0 pinned 1.0.0..<2.0.0. Model variant: openai_whisper-large-v3-v20240930_turbo_632MB.

## Next planned action
- Group D Step 2: TranscriptLiveView + AppBootstrapper wiring + language-indicator chrome.
- UI binding split per ROADMAP: language-indicator chrome → LanguageRouter.currentLanguage (authoritative, stability over accuracy); transcript lines → RoutedTranscript.detectedLanguage (honest, one-window mismatch is information).

## Active prerequisites for Group D Step 2
- None blocking.
- Subagent MCP-inheritance fallback rule remains in CLAUDE.md (subagents fall back to raw xcodebuild via Bash; main session verifies via XcodeBuildMCP).
- CLAUDE.md sections active from Group C closure: Rollback safety (mandatory checkpoint commits at every step boundary), Concurrency design discipline, feature-planner output discipline, swift-implementer scope-and-decision discipline.

## V3 backlog items relevant to upcoming work
- LanguageRouter routedTranscripts() multiplex: RESOLVED 2026-05-10 by Group D Step 1 (option 2)
- Test infrastructure as agent blind spot: bundles with post-Phase-4 workflow automation
- swift-implementer scope-and-decision discipline (sharpening): bundles with post-Phase-4 workflow automation
- feature-planner system prompt update — concurrency scheduling-assumption rule: bundles with post-Phase-4 workflow automation
- @feature-planner self-critique rules: bundles with post-Phase-4 workflow automation
- @dispatch-implementer slash command: bundles with post-Phase-4 workflow automation
- AudioCaptureViewModel router param: optional → required: bundles with post-Phase-4 workflow automation
- LanguageRouter scheduling-assumption violation test: pre-MVP-1 hardening
- TranscriptionActor.awaitUpstreamDrained → DEBUG-only extension: pre-MVP-1 hardening
- TranscribingProtocolTests cancel-test timing race: pre-MVP-1 hardening
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
- Clean
- Branch: main
- Origin/main: in sync (1780c83 pushed)

## Local-only artifacts
- Tag pre-recovery-snapshot/group-c → 4a57d30 (forensic snapshot of pre-recovery Group C state including C30 regression — local only, not pushed)
