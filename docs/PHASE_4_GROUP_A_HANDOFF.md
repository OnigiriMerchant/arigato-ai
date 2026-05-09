# Phase 4 Group A Handoff — Streaming Transcription Foundation

Status: shipped on `main` as `4fdc0fd` on 2026-05-09. Resume with Group B (Whisper model loader and pre-warm) per `docs/PHASE_4_HANDOFF.md` Steps 5–7. Read the gating prerequisite below before invoking `@feature-planner` for Group B.

## What shipped

**Commit**: `4fdc0fd feat(transcription): add domain types and Transcribing protocol`

**Files added** (9 changed, 829 insertions, 0 deletions):

Source under `ArigatoAI/Transcription/`:
- `SpokenLanguage.swift` — `public nonisolated enum`, raw `String` `"ja"`/`"en"` matching WhisperKit codes
- `TranscriptionError.swift` — `public nonisolated enum` with 6 cases, stringified detail per `AudioCaptureError` precedent
- `TranscriptSegment.swift` — `public nonisolated struct`, 9 fields, NO `languageConfidence`
- `Transcribing.swift` — `public nonisolated enum WarmupState` + `public protocol Transcribing: Sendable`

Tests under `ArigatoAITests/Transcription/` (35 tests, all passing):
- `SpokenLanguageTests.swift` — 13 tests
- `TranscriptionErrorTests.swift` — 6 tests
- `TranscriptSegmentTests.swift` — 10 tests (including a real actor-crossing Sendable test)
- `TranscribingProtocolTests.swift` — 6 tests (including real D6 and D9 contract tests; uses a private `MinimalTranscriber` actor stub)

Plus `docs/V3_BACKLOG.md` updated with the timing-race entry for `transcribe_cancelFinishesStreamWithoutError`.

**Build state at shipping**: 0 errors, 0 warnings via XcodeBuildMCP authoritative build for iPhone 17 Pro Max simulator, iOS 26.4. 57 total tests pass (35 Group A + 22 existing Phase 3).

## Architectural decisions locked in

### Phase 4 top-level decisions (from `docs/PHASE_4_HANDOFF.md`)

1. **`argmax-oss-swift` package version pin**: v1.0.0+, package URL `https://github.com/argmaxinc/argmax-oss-swift`, SPM product `WhisperKit`, pinned `1.0.0..<2.0.0`. Source uses `import WhisperKit` unchanged. `WhisperKit` does *not* declare `Sendable`; actor-ownership inside `TranscriptionActor` (Group C) is the correct mitigation.
2. **Whisper model size**: `large-v3-turbo`.
3. **Pre-warm site**: `AppBootstrapper` fired from `App.init()` via `Task.detached`.
4. **Window/hop sizing**: 5s window, 1s hop.

### Q4 language-fallback design call (resolved this session)

**Consecutive-window disagreement gating (N=2)** replaces the original `<0.7` per-segment confidence threshold. WhisperKit v1.0.0 does not surface per-segment language probabilities — `TranscriptionResult.language` is `String` only; `languageProbs: [String: Float]` lives on `DecodingResult` and is *not* returned from `transcribe(audioArray:)`. Pre-detection via the typo'd `detectLangauge(audioArray:)` was rejected to avoid doubling encoder cost per window. `LanguageRouter` (Group C) implements the disagreement gate.

### `languageConfidence` field drop

`TranscriptSegment.languageConfidence` was dropped before implementation. `wasLanguageFallback: Bool` (set by `LanguageRouter` on disagreement gating) is the sole honesty signal. A synthesized float would imply precision the underlying API doesn't provide.

### Swift 6 nonisolated rule learned this session

Pure-domain value types must be marked **`public nonisolated`** explicitly. Under Swift 6 strict concurrency, conformances synthesized on types without explicit isolation are inferred `@MainActor`-isolated, which causes "main actor-isolated conformance cannot be used in nonisolated context" warnings (and errors in stricter modes). The planner's spec marked `SpokenLanguage` and `TranscriptSegment` `nonisolated` but missed `TranscriptionError` and `WarmupState`; both were corrected before commit. Apply this to every pure-domain type going forward.

### Doc-comment contracts that future code reviews must enforce

- **D6** on `Transcribing.transcribe(frames:)`: "Conformers throw only `TranscriptionError`. A non-`TranscriptionError` observed downstream is a contract violation."
- **D9** on `Transcribing.cancel()`: "After `cancel()` returns, the stream finishes normally; in-flight transcriptions are dropped without delivery. `CancellationError` is not thrown."

Both are test-enforced (`transcribe_errorsAreTranscriptionError` and `transcribe_cancelFinishesStreamWithoutError`).

## Open backlog items relevant to resuming

See `docs/V3_BACKLOG.md` for full entries.

- **XcodeBuildMCP not in subagent default tool surface** — *gating for Group B*; see prerequisites below.
- **Workflow automation narrow bundle** — `@feature-planner` self-critique rules + `/dispatch-implementer` slash command. Build between Phase 4 and Phase 5.
- **TranscribingProtocolTests cancel-test timing race** — 20ms `Task.sleep` in `transcribe_cancelFinishesStreamWithoutError`. Replace with deterministic handshake. Not blocking Group B.
- **`@plan-reviewer` subagent** — superseded by the workflow automation bundle. Entry preserved in backlog for the reasoning trail.

## Group B prerequisites

**Land the XcodeBuildMCP subagent tool-surface fix before invoking `@feature-planner` for Group B.**

Why: Group B's plan includes Step 5 — adding the `argmax-oss-swift` SPM dependency, which touches `ArigatoAI.xcodeproj/project.pbxproj`. During Group A, `@swift-implementer` did not have XcodeBuildMCP in its default tool surface and fell back to raw `xcodebuild` (a CLAUDE.md violation that cost ~16 approval prompts). Group B is more sensitive than Group A because:

1. Project structure changes (new SPM dependency, possible scheme edits) need authoritative MCP-driven verification, not just SourceKit.
2. The model-loader actor (Step 6) depends on a real WhisperKit instance; build/test cycles will be more frequent.
3. Build-doctor's fallback (loading MCP tools mid-session) worked but is operationally noisy.

The fix is documented in the backlog: edit `.claude/agents/swift-implementer.md`, `.claude/agents/build-doctor.md`, and any future `device-test-runner.md` to include XcodeBuildMCP tools in the YAML frontmatter `tools:` list. Estimate ~30 minutes total across the three subagents.

Once that lands, resume Group B planning by invoking `@feature-planner` against `docs/PHASE_4_HANDOFF.md` Steps 5–7:
- Step 5: Add `argmax-oss-swift` SwiftPM dependency
- Step 6: `WhisperModelLoader` actor (loading + 1s-of-silence pre-warm coalescing)
- Step 7: `AppBootstrapper` (fire `Task.detached` from `App.init()`; replace existing `fatalError` in model-container builder)

## Session metadata

- Branch: `main`
- Pushed to: `origin/main` (commit range `c8fcd8b..4fdc0fd`)
- Six commits this session: 5 docs corrections + 1 feat (Group A code)
- Working tree at handoff write time: clean
