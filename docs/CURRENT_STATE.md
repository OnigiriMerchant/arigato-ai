# Current State — Arigato AI

Last updated: 2026-05-10 by end-of-session update.

## Most recent commit
- `eb37b00` docs: refresh current state for chat migration continuity
- Code commit: `4fdc0fd` feat(transcription): add domain types and Transcribing protocol

## Phase status
- Phase 4 (WhisperKit/ArgmaxOSS streaming transcription): Group A shipped, Groups B/C/D pending
- Group A: 8 source files, 35 tests, all passing, 0 warnings, 0 errors
- All four Phase 4 architectural decisions locked in
- All 10 ArgmaxOSS uncertainties resolved with citations

## Next planned action
1. Decide Group B scope (citizen-dev pause-and-think before invoking @feature-planner)
2. Invoke @feature-planner for Phase 4 Group B once scope is set (Steps 5-7: WhisperKit SPM dependency, WhisperModelLoader, AppBootstrapper). Group B proceeds with raw xcodebuild fallback for build/test verification — see prerequisite note below.

## Active prerequisites for next phase
- XcodeBuildMCP subagent tool-surface fix is **deferred**, not blocking. Original case-mismatch hypothesis was refuted on 2026-05-10: two consecutive verification probes against build-doctor confirmed that subagents receive only `Read`, `Edit`, `Bash` regardless of whether the YAML `tools:` field uses lowercase wildcards, mixed-case wildcards, or fully-qualified MCP tool names. Real diagnosis requires either spawning @claude-code-guide research agent against this specific failure, inspecting MCP scope propagation in `~/.claude.json` or plugin marketplace configs, or waiting for a Claude Code version that documents subagent MCP behaviour explicitly. Group B proceeds with raw xcodebuild via Bash; cost is per-invocation permission prompts (~16 fired during Group A).

## V3 backlog priority items (relevant to upcoming work)
- @feature-planner self-critique rules: mandate nonisolated annotations, drop dead tests, require contract tests for every doc-comment contract
- @dispatch-implementer slash command: eliminates 12-line dispatch prompt at every group boundary
- XcodeBuildMCP not in subagent default tool surface: revised framing on 2026-05-10 — root cause is broader than case mismatch, hypotheses listed in backlog entry, trigger to revisit moved to "when MCP resolution becomes blocking OR after Phase 4 ships OR Claude Code documents subagent MCP behaviour"
- @plan-reviewer subagent: SUPERSEDED by feature-planner self-critique rules
- @phase-walker subagent: REJECTED (strategic conversation stays in Claude.ai by design)
- TranscribingProtocolTests cancel-test timing race: 20ms Task.sleep replace with deterministic handshake before MVP 1 ships

## Working tree
- Clean
- Branch: main
- Origin/main: 3 commits ahead (push pending — leave to user's session-end flow)
