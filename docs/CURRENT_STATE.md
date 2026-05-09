# Current State — Arigato AI

Last updated: 2026-05-10 by end-of-session update.

## Most recent commit
- `01f15ea` feat(routine): monitor Claude Code subagent MCP bug; log quarterly platform review
- Most recent Swift source commit: `4fdc0fd` feat(transcription): add domain types and Transcribing protocol

## Phase status
- Phase 4 (WhisperKit/ArgmaxOSS streaming transcription): Group A shipped, Groups B/C/D pending
- Group A: 8 source files, 35 tests, all passing, 0 warnings, 0 errors
- All four Phase 4 architectural decisions locked in
- All 10 ArgmaxOSS uncertainties resolved with citations

## Next planned action
1. Decide Group B scope (citizen-dev pause-and-think before invoking @feature-planner)
2. Invoke @feature-planner for Phase 4 Group B once scope is set (Steps 5-7: WhisperKit SPM dependency, WhisperModelLoader, AppBootstrapper). Subagents proceed with raw xcodebuild via Bash for build verification; main session uses XcodeBuildMCP-wrapped tools to verify subagent output afterward — workflow now codified in CLAUDE.md.

## Active prerequisites for next phase
- None blocking. The XcodeBuildMCP subagent tool-surface friction is now treated as a known Claude Code platform limitation (anthropics/claude-code#25200, #13898, #13605), with the daily briefing routine (`trig_015mBbun21cW5sDfuY1WnQ3b`) configured to flag any state change on those issues plus keyword-scan of new Claude Code release notes for "subagent", "MCP", "mcp__", "inherit", "tools field". Group B kickoff is unblocked.

## V3 backlog priority items (relevant to upcoming work)
- @feature-planner self-critique rules: mandate nonisolated annotations, drop dead tests, require contract tests for every doc-comment contract
- @dispatch-implementer slash command: eliminates 12-line dispatch prompt at every group boundary
- Subagent MCP tool inheritance — known Claude Code limitation: monitored via daily brief; trigger to revisit is when Anthropic ships a fix to the linked GitHub issues. Optional ~5-min spike: try moving XcodeBuildMCP to user scope (`-s user`) since some reports suggest user-scope MCPs propagate to subagents.
- Quarterly platform sanity review: NEW — calendar trigger Aug 2026, or earlier if daily brief surfaces multiple platform changes in one week. Strategic review work in Claude.ai, not code.
- @plan-reviewer subagent: SUPERSEDED by feature-planner self-critique rules
- @phase-walker subagent: REJECTED (strategic conversation stays in Claude.ai by design)
- TranscribingProtocolTests cancel-test timing race: 20ms Task.sleep replace with deterministic handshake before MVP 1 ships

## Working tree
- Clean
- Branch: main
- Origin/main: 7 commits ahead (push pending — leave to user's session-end flow)
