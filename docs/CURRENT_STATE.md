# Current State — Arigato AI

Last updated: 2026-05-10 by end-of-Group-C session.

## Most recent commit
- 6812231 docs(group-c): process trim — rollback safety, scope discipline, planner output, V3 entries

## Phase status
- Phase 4 (WhisperKit/ArgmaxOSS streaming transcription): Groups A, B, C shipped. Group D pending.
- Group A: domain types + Transcribing protocol (commits superseded in original timeline by Group B integration; types live in current main).
- Group B (commits 3b3b29c, 2ba5831, 174ace7): WhisperKit SPM + WhisperModelLoader + WhisperEngine seam + WhisperModelVariant + AppBootstrapper + StartupErrorView. fatalError eliminated from App.init recoverable path.
- Group C (commits 809d65e, e29176e, b04baf5, 8a8131f, d284d67, 6812231): RollingAudioBuffer + WhisperClient cascade + TranscriptionActor with hop-scheduler fix (bounded FIFO queue cap 4, oldest-drop overflow, deterministic awaitUpstreamDrained test seam) + LanguageRouter with N=2 consecutive-window disagreement gate + RoutedTranscript value type. @MainActor @Observable currentLanguage exposed for UI chrome binding.
- 108/108 tests passing. 0 warnings, 0 errors.
- All eight Phase 4 architectural decisions still locked. WhisperKit v1.0.0 pinned 1.0.0..<2.0.0. Model variant: openai_whisper-large-v3-v20240930_turbo_632MB.

## Next planned action
1. Group D kickoff: TranscriptLiveView + AppBootstrapper wiring + language-indicator chrome.
2. First thing during Group D plan review: evaluate the LanguageRouter routedTranscripts() multiplex V3 entry. Current implementation returns a dead stream. Three options on the table (refactor multiplex, drop the surface and use @Observable patterns, restructure UI bindings). Decision belongs in plan review.

## Active prerequisites for Group D
- None blocking.
- Subagent MCP-inheritance fallback rule remains in CLAUDE.md (subagents fall back to raw xcodebuild via Bash; main session verifies via XcodeBuildMCP).
- New CLAUDE.md sections from Group C closure now active: Rollback safety (mandatory checkpoint commits at every step boundary), Concurrency design discipline, feature-planner output discipline, swift-implementer scope-and-decision discipline.

## V3 backlog items relevant to upcoming work
- LanguageRouter routedTranscripts() multiplex: trigger fires at Group D plan review (first item)
- Test infrastructure as agent blind spot: bundles with post-Phase-4 workflow automation (explicit shared scheme files, drop TEST_HOST, document test target hygiene)
- swift-implementer scope-and-decision discipline (sharpening): bundles with post-Phase-4 workflow automation
- feature-planner system prompt update — concurrency scheduling-assumption rule: bundles with post-Phase-4 workflow automation
- @feature-planner self-critique rules: bundles with post-Phase-4 workflow automation
- @dispatch-implementer slash command: bundles with post-Phase-4 workflow automation
- LanguageRouter scheduling-assumption violation test: pre-MVP-1 hardening
- TranscriptionActor.awaitUpstreamDrained → DEBUG-only extension: pre-MVP-1 hardening
- TranscribingProtocolTests cancel-test timing race: pre-MVP-1 hardening
- WhisperKit model variant choice — turbo decoder, 632MB: locked, monitored via daily brief
- Subagent MCP tool inheritance: monitored via daily brief
- Quarterly platform sanity review: calendar trigger Aug 2026
- Phase 7 design language direction: trigger is Phase 7 kickoff (much later)

## Process trim applied at Group C closure
- Doc-researcher pre-flight checks: situational, not default
- Screenshot cadence: hard pauses, decision points, surprises only
- Supervisory model: routine continuations go directly to Claude Code; strategic-thinking-partner role for architectural decisions, plan reviews, recovery situations
- V3 backlog hygiene: log entries as encountered (not deferred to end of session)

## Working tree
- Clean
- Branch: main
- Origin/main: in sync (6812231)

## Local-only artifacts
- Tag pre-recovery-snapshot/group-c → 4a57d30 (forensic snapshot of pre-recovery Group C state including C30 regression — local only, not pushed)
