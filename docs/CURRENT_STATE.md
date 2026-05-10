# Current State — Arigato AI

Last updated: 2026-05-10 after Group D shipped.

## Most recent commit
- a1fa4d9 docs(v3): log Group D UI deferred concerns; amend MCP-inheritance entry with Group D gate datapoint

## Phase status
- Phase 4 (WhisperKit/ArgmaxOSS streaming transcription): **shipped**. Groups A, B, C, D all complete.
- Group A: domain types + Transcribing protocol.
- Group B (commits 3b3b29c, 2ba5831, 174ace7): WhisperKit SPM + WhisperModelLoader + WhisperEngine seam + WhisperModelVariant + AppBootstrapper + StartupErrorView. fatalError eliminated from App.init recoverable path.
- Group C (commits 809d65e, e29176e, b04baf5, 8a8131f, d284d67, 6812231): RollingAudioBuffer + WhisperClient cascade + TranscriptionActor with hop-scheduler fix (bounded FIFO queue cap 4, oldest-drop overflow, deterministic awaitUpstreamDrained test seam) + LanguageRouter with N=2 consecutive-window disagreement gate + RoutedTranscript value type. @MainActor @Observable currentLanguage exposed for UI chrome binding.
- Group D (checkpoints 1780c83, 04c1f95, c16d683, 9f20c24, 9ff18b4 + Concern 6 fix 3b7c311): live transcription UI surface end-to-end. LanguageRouter routedTranscripts() multiplex resolved (Option 2 — dropped, replaced with @Observable routedHistory + resetSession). AppBootstrapper owns shared TranscriptionActor + LanguageRouter. AudioCaptureViewModel drains pipeline through router when injected. TranscriptLiveView with three-region layout (chrome / list / record control) + TranscriptRowDisplay/IndicatorChromeDisplay testability helpers. RecordControl injects bootstrapper.router → pipeline runs end-to-end. End-of-group gate ui-review surfaced 8 visual concerns; Concern 6 (duplicate "listening…" hint) fixed pre-push, locked by D4-T-concern6 regression test; remaining 7 deferred to Phase 7 (V3 #40).
- 125/125 tests passing post-Group-D. 0 errors. Pre-existing withLock warning at TranscriptionActorTests.swift:51 (V3 #38, deferred to pre-MVP-1 hardening).
- All eight Phase 4 architectural decisions still locked. WhisperKit v1.0.0 pinned 1.0.0..<2.0.0. Model variant: openai_whisper-large-v3-v20240930_turbo_632MB.

## Next planned action
- **Phase 5 kickoff**: LFM2 translation via LEAP iOS SDK. Translation dispatcher attaches at LanguageRouter's output (bound to authoritativeLanguage, not detectedLanguage — never sends a half-sentence through the wrong direction). Streaming bilingual text consumed by TranscriptLiveView.
- Pre-Phase-5 workflow automation bundle (V3 #14, #28, #29, #30, #31, #37, #39): feature-planner self-critique rules, /dispatch-implementer slash command, concurrency rule update, scope-and-decision sharpening, AudioCaptureViewModel router param required-promotion, Anthropic Opus 4.7 prompting best practices adoption.

## Active prerequisites for Phase 5
- None blocking.
- Pre-Phase-5 workflow automation bundle (V3 #14, #28, #29, #30, #37, #39) — recommended before Phase 5 kickoff to make Phase 5 cheaper. ~90 minutes.
- Subagent MCP-inheritance fallback rule remains in CLAUDE.md. New @ui-reviewer Bash-screenshot fallback action item added to V3 #23.
- Push protocol active: `git log origin/main..HEAD` before any push during a group's lifetime; targeted single-commit push or skip when checkpoints are unpushed.
- CLAUDE.md sections active from Group C closure: Rollback safety, Concurrency design discipline, feature-planner output discipline, swift-implementer scope-and-decision discipline.

## V3 backlog items relevant to upcoming work
- LanguageRouter routedTranscripts() multiplex: RESOLVED 2026-05-10 by Group D Step 1 (option 2)
- Group D UI deferred concerns (#40): Phase 7 kickoff — 7 visual concerns deferred to design-language pass
- Anthropic Opus 4.7 prompting best practices (#39): post-Phase-4 workflow automation bundle
- AudioCaptureViewModel router param: optional → required (#37): post-Phase-4 workflow automation bundle
- TranscriptionActorTests withLock unused-result warning (#38): pre-MVP-1 hardening
- /dispatch-research slash command (#13): Phase 5 kickoff
- Test infrastructure as agent blind spot (#29): post-Phase-4 workflow automation bundle
- swift-implementer scope-and-decision discipline (sharpening) (#30): post-Phase-4 workflow automation bundle
- feature-planner concurrency scheduling-assumption rule (#28): post-Phase-4 workflow automation bundle
- @feature-planner self-critique rules + @dispatch-implementer slash command (#14): post-Phase-4 workflow automation bundle
- LanguageRouter scheduling-assumption violation test (#26): pre-MVP-1 hardening
- TranscriptionActor.awaitUpstreamDrained → DEBUG-only extension (#25): pre-MVP-1 hardening
- TranscribingProtocolTests cancel-test timing race (#16): pre-MVP-1 hardening
- WhisperKit model variant choice — turbo decoder, 632MB: locked, monitored via daily brief
- Subagent MCP tool inheritance (#23): monitored via daily brief, new ui-reviewer Bash-screenshot fallback action item recorded
- Quarterly platform sanity review: calendar trigger Aug 2026
- Phase 7 design language direction: trigger is Phase 7 kickoff (#22 + #40 bundle)

## Process trim applied at Group C closure (still active)
- Doc-researcher pre-flight checks: situational, not default
- Screenshot cadence: hard pauses, decision points, surprises only — main-session screenshots performed during Group D end-of-group gate as ui-reviewer fallback
- Supervisory model: routine continuations go directly to Claude Code; strategic-thinking-partner role for architectural decisions, plan reviews, recovery situations
- V3 backlog hygiene: log entries as encountered (not deferred to end of session)

## Working tree
- Clean at the time of this commit
- Branch: main
- Origin/main: behind local — Group D chain pending push (4 checkpoints + Concern 6 fix + 3 docs commits = 7 commits ahead of origin)

## Local-only artifacts
- Tag pre-recovery-snapshot/group-c → 4a57d30 (forensic snapshot of pre-recovery Group C state including C30 regression — local only, not pushed)
