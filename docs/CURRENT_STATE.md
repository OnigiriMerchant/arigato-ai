# Current State — Arigato AI

Last updated: 2026-05-10 by end-of-session update at Group B completion.

## Most recent commit
- `174ace7` feat(app): add AppBootstrapper for Whisper pre-warm and startup error recovery

## Phase status
- **Phase 4 (WhisperKit/ArgmaxOSS streaming transcription): Group A and Group B shipped. Groups C and D pending.**
- Group A (commit `4fdc0fd`): 8 source files, 35 tests, domain types + Transcribing protocol
- Group B (commits `3b3b29c`, `2ba5831`, `174ace7`): WhisperKit SPM dependency + WhisperModelLoader actor + WhisperEngine seam + WhisperModelVariant enum + AppBootstrapper @MainActor @Observable + StartupErrorView. fatalError eliminated from App.init recoverable path.
- 71 tests passing total (35 Group A + 14 prior Phase 3 + 9 Group B Step 6 + 5 Group B Step 7 + 8 UI/launch tests). 0 warnings, 0 errors.
- All four Phase 4 architectural decisions still locked in. WhisperKit v1.0.0 pinned `1.0.0..<2.0.0`. Model variant locked to `openai_whisper-large-v3-v20240930_turbo_632MB` (turbo decoder per Phase 4 Decision 2 latency budget; deliberate override of Argmax's 626MB README recommendation, documented in V3_BACKLOG and CLAUDE.md "External dependency configuration" rule).

## Next planned action
1. Decide Group C scope (citizen-dev pause-and-think before invoking @feature-planner)
2. Invoke @feature-planner for Phase 4 Group C — TranscriptionActor (conforms to Group A's Transcribing protocol, consumes Group B's WhisperModelLoader/WhisperEngine) + LanguageRouter (consecutive-window disagreement gating, N=2 per CLAUDE.md). Per PHASE_4_HANDOFF.md spec.
3. After Group C: Group D (live UI surface — TranscriptLiveView consuming AppBootstrapper.loaderState and the transcription stream).

## Active prerequisites for next phase
- None blocking. The XcodeBuildMCP subagent tool-surface friction remains monitored via the daily briefing routine (`trig_015mBbun21cW5sDfuY1WnQ3b`) for state changes on anthropics/claude-code#25200, #13898, #13605 plus keyword-scan on Claude Code release notes. Subagents continue to fall back to raw xcodebuild via Bash; main session verifies via XcodeBuildMCP per CLAUDE.md "Build workflow" rule.
- @feature-planner self-critique rules entry in V3_BACKLOG would help Group C planning quality but is not blocking.

## V3 backlog priority items (relevant to upcoming work)
- @feature-planner self-critique rules: still pending; would catch dead tests, missing nonisolated annotations, missing contract tests during Group C planning before implementer dispatch
- @dispatch-implementer slash command: still pending; would eliminate the manual ~12-line dispatch prompt at Group C boundary
- TranscribingProtocolTests cancel-test timing race: 20ms Task.sleep replace with deterministic handshake before MVP 1 ships (still applies; Group C will not change this)
- Subagent MCP tool inheritance — known Claude Code limitation: monitored via daily brief; trigger to revisit is when Anthropic ships a fix to the linked GitHub issues
- WhisperKit model variant choice — turbo decoder, 632MB: locked, monitored via daily brief for Argmax recommendation drift
- Auto mode behaviour notes: reference only; consult when picking mode for Group C dispatch
- /update-state self-referential commit noise: deferred to post-Phase-4 workflow automation bundle
- Quarterly platform sanity review: calendar trigger Aug 2026
- Phase 7 design language direction: NEW today; trigger is Phase 7 kickoff (much later)
- @plan-reviewer subagent: SUPERSEDED by feature-planner self-critique rules
- @phase-walker subagent: REJECTED (strategic conversation stays in Claude.ai by design)

## Working tree
- Clean
- Branch: main
- Origin/main: in sync (0 ahead, 0 behind) before this refresh commit
