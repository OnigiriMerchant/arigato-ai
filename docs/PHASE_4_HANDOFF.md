# Phase 4 Handoff — WhisperKit/ArgmaxOSS Streaming Transcription

Status: planned, not implemented. Resume by answering the four decisions below, then invoke `@swift-implementer` against this plan.

## Goal

A transcription layer that:
- Consumes the `AsyncStream<AudioFrame>` from `ArigatoAI/Audio/AudioCaptureActor.swift` (Phase 3)
- Runs Whisper inference fully on-device with auto JA/EN language detection
- Emits `TranscriptSegment` values: text, language, confidence, host-time + seconds timestamps
- Pre-warms Whisper at app launch (CLAUDE.md rule)
- Falls back via consecutive-window disagreement gating (N=2) when WhisperKit reports a different language than `lastConfidentLanguage`

## Architectural call (locked in)

**Split `TranscriptionActor` (raw Whisper inference) from `LanguageRouter` (fallback policy + de-dup).**

The router owns the consecutive-disagreement language fallback and overlapping-window de-duplication. Phase 5's LFM2 translation dispatcher attaches at the router's `AsyncStream<TranscriptSegment>` output without touching Whisper code. Reasoning: CLAUDE.md says "no god objects" and Phase 5 routes by language — having the router as its own type is the natural seam.

## 15-step plan

### Group A — Domain types and protocols

1. **`TranscriptSegment`** — `ArigatoAI/Transcription/TranscriptSegment.swift`. Sendable struct: `id`, `text`, `language`, `languageConfidence`, `startHostTime`, `endHostTime`, `startSeconds`, `endSeconds`, `isFinal`, `wasLanguageFallback`.
2. **`SpokenLanguage`** — `ArigatoAI/Transcription/SpokenLanguage.swift`. Enum `case ja, en` with failable `init?(whisperCode:)`.
3. **`TranscriptionError`** — `ArigatoAI/Transcription/TranscriptionError.swift`. Cases: `modelLoadFailed`, `modelNotReady`, `decodeFailed`, `bufferUnderrun`, `audioStreamEnded`, `unsupportedSampleRate`. Mirrors `AudioCaptureError` pattern.
4. **`Transcribing` protocol + `WarmupState`** — `ArigatoAI/Transcription/Transcribing.swift`. Methods: `warmup()`, `warmupState()`, `transcribe(frames:)`, `cancel()`. Mirrors `AudioCapturing` so a `FakeTranscriber` can be injected in tests.

### Group B — Whisper model loader and pre-warm

5. **Add argmax-oss-swift SwiftPM dependency** — edit `ArigatoAI.xcodeproj/project.pbxproj`. Package URL `https://github.com/argmaxinc/argmax-oss-swift`, pinned `1.0.0..<2.0.0`. SPM product name is `WhisperKit` (one of several products in the package); source files use `import WhisperKit` unchanged from pre-rename. Link product to app target only (not test target — keeps unit tests Core ML-free).
6. **`WhisperModelLoader`** — `ArigatoAI/Transcription/WhisperModelLoader.swift`. Actor owning the ArgmaxOSS client. `loadIfNeeded(variant:)`, `currentState()`, `unload()`. Coalesces concurrent loads. Runs 1s-of-silence dummy pre-warm. `WhisperModelVariant` enum.
7. **`AppBootstrapper`** — new `ArigatoAI/AppBootstrapper.swift`, edit `ArigatoAI/ArigatoAIApp.swift`. `@MainActor @Observable` class holding shared loader. Fires `Task.detached` from `App.init()` to warm in parallel with mic-permission prompt. Also: replace existing `fatalError` in model-container builder with recoverable error path (CLAUDE.md ban).

### Group C — Transcription actor and language router

8. **`RollingAudioBuffer`** — `ArigatoAI/Transcription/RollingAudioBuffer.swift`. Value type, owned by transcription actor. Capacity in seconds, append-frame, slice-trailing-window, drop-oldest. Tracks host time of sample 0 for downstream timestamp conversion. Use ring buffer to avoid O(n²) appends.
9. **`TranscriptionActor`** — `ArigatoAI/Transcription/TranscriptionActor.swift`. `actor` conforming to `Transcribing`. Drains `AsyncStream<AudioFrame>`, fills buffer, slices windows on hop boundary, calls Whisper with `language: nil, detectLanguage: true`. Emits `WhisperRawSegment` (not `TranscriptSegment` — language fallback happens in router).
10. **`WhisperClient` protocol + `WhisperRawSegment`** — `ArigatoAI/Transcription/WhisperClient.swift`. Internal seam isolating WhisperKit field-name and concurrency uncertainty. Concrete `ArgmaxOSSWhisperClient` adapter. `WhisperRawSegment`: `text`, `languageCode`, `startSeconds`, `endSeconds`, `avgLogprob`, `windowAnchorHostTime`. **API typo note**: WhisperKit v1.0.0 ships a real misspelling — the `[Float]` overload is named `detectLangauge(audioArray:)` ("auge", not "uage") at `WhisperKit.swift:528`, while the `audioPath:` overload uses the correct spelling at `WhisperKit.swift:519`. Confirmed by doc-researcher against the v1.0.0 tag; this is intentional in our implementation, not a typo to fix. The `WhisperClient` protocol method is named in correct English (e.g., `detectLanguage(audio: [Float])`); only the `ArgmaxOSSWhisperClient` adapter calls the typo'd selector. This isolates a future Argmax patch (which would be source-breaking) to a single adapter line.
11. **`LanguageRouter`** — `ArigatoAI/Transcription/LanguageRouter.swift`. Actor consuming raw segments, de-duplicating across overlapping windows, emitting `AsyncStream<TranscriptSegment>`. **Language fallback policy: consecutive-window disagreement gating (N=2).** State: `lastConfidentLanguage: SpokenLanguage?`. On each window's `TranscriptionResult.language`: if it agrees with `lastConfidentLanguage`, emit normally and reset the disagreement counter. If it disagrees, emit the segment under `lastConfidentLanguage` with `wasLanguageFallback = true` and increment the counter; only switch `lastConfidentLanguage` to the new language after 2 consecutive windows agree on it. First window has no `lastConfidentLanguage` — accept whatever WhisperKit reports and seed state. **Why this replaces the per-segment `<0.7` confidence threshold**: v1.0.0 does not surface per-segment language probabilities. `TranscriptionSegment` has no language fields; `TranscriptionResult.language` is `String` only; `languageProbs: [String: Float]` lives on `DecodingResult` and is *not* returned from `transcribe(audioArray:)`. Pre-detection via the typo'd `detectLangauge(audioArray:)` call was rejected because it would double encoder cost per window. Consecutive-disagreement gating gives equivalent stickiness without the extra inference pass.

### Group D — Wiring and integration

12. **Wire into `AudioCaptureViewModel`** — edit `ArigatoAI/Audio/AudioCaptureViewModel.swift`. Replace Phase-3 frame drain with full pipeline: capture → transcriber → router → published `liveSegments: [TranscriptSegment]` capped at recent N for UI.
13. **`TranscriptLiveView`** — `ArigatoAI/Transcription/TranscriptLiveView.swift` + edit `ArigatoAI/ContentView.swift`. SwiftUI list rendering segments with JA/EN badge and a fallback dot when `wasLanguageFallback`. No translation UI yet (Phase 5).
14. **`FakeTranscriber`** — `ArigatoAITests/Transcription/FakeTranscriber.swift`. Implements `Transcribing` for unit tests. Mirrors `FakeCapture` pattern from `AudioCaptureViewModelTests`.
15. **End-to-end integration test** — `ArigatoAITests/Transcription/TranscriptionPipelineIntegrationTests.swift`. Synthetic JA WAV through real `TranscriptionActor` + real `LanguageRouter`. Guard with `#if INTEGRATION_TESTS` so default test runs stay fast.

## Decisions to answer on resume

These were the four blocking questions when the session was interrupted. None are answered yet.

### 1. argmax-oss-swift package version pin
- **Recommended**: v1.0.0+, package URL `https://github.com/argmaxinc/argmax-oss-swift`, SPM product `WhisperKit`, pinned `1.0.0..<2.0.0`. The package was renamed at the SPM level but the SPM product name and the `import WhisperKit` statement are unchanged from pre-rename. Note: `WhisperKit` does *not* declare `Sendable` conformance in v1.0.0 source — actor-ownership inside `TranscriptionActor` is the correct mitigation; do *not* fall back to `@preconcurrency import`.
- Alternative: stay on pre-rename `argmaxinc/WhisperKit` — older, no v1.0.0 fixes, also non-Sendable. No reason to choose this.

### 2. Whisper model size
- **Recommended**: `large-v3-turbo` (~600 MB, ~1 GB peak RAM, 1–1.5s end-of-utterance latency on iPhone 17 Pro Max, best JA accuracy).
- Alternative: `small` (~500 MB, lower JA accuracy — probably no reason to pick).
- Alternative: `base` (~150 MB, noticeably worse JA — only if memory pressure).
- Not considered: `tiny`, full `large` (turbo dominates both for this device).

### 3. Pre-warm site
- **Recommended**: `AppBootstrapper` fired from `App.init()` via `Task.detached`. Warmup overlaps with the mic-permission prompt. More wiring; earliest start.
- Alternative: `.task` modifier on root `ContentView`. Simpler but starts later — user may hit record before warmup begins.
- Alternative: lazy on first tap. Worst latency, simplest. Not recommended.

### 4. Window/hop sizing for streaming transcription
- **Recommended**: 5s window, 1s hop. 5s gives JA enough context for kanji disambiguation; 1s hop bounds end-of-utterance latency. Predictable.
- Alternative: VAD-gated chunks (if ArgmaxOSS v1.0.0 ships VAD). More accurate, more variable latency.
- Alternative: hybrid (VAD when available, force-flush at 5s). Best behavior, most complex state machine.

## Doc-researcher uncertainties (resolve before Step 5)

Invoke `@doc-researcher` against argmax-oss-swift v1.0.0 release notes and source for:

1. **Module/product names post-rename.** Resolved — see Step 5 and Decision 1. SPM URL is `argmaxinc/argmax-oss-swift`, product name is `WhisperKit`, source uses `import WhisperKit` unchanged.
2. **Streaming API surface in v1.0.0.** Repeated `transcribe(audioArray:)` over a rolling buffer vs. a dedicated streaming session object (`AudioStreamTranscriber` or similar)?
3. **Per-segment timestamp field names.** Confirm exact names for `start`, `end`, `text`, `avgLogprob` in v1.0.0.
4. **Language confidence field.** Resolved — see Step 11. v1.0.0 exposes language only at `TranscriptionResult.language` (String); `languageProbs: [String: Float]` lives on `DecodingResult` and is not returned from `transcribe(audioArray:)`. Drove the switch to consecutive-window disagreement gating.
5. **Built-in VAD.** Does v1.0.0 ship a public VAD type? What's its API? (Affects decision 4.)
6. **`Sendable` conformance.** Confirm the client class is `Sendable` so we can hold it inside `TranscriptionActor` without `@preconcurrency`.
7. **Concurrent-decode behavior.** Is calling `transcribe` while a previous call is in flight safe? If not, we need a serial queue inside the actor.
8. **`DecodingOptions` field names.** v1.0.0 may have renamed `temperatureFallbackCount`, `usePrefillPrompt`, `withoutTimestamps`.
9. **Model download API.** Download-vs.-bundled resolution; observable progress for a consent UI.
10. **Tokenizer warmup.** Does `prewarmModels()` exist in v1.0.0, or do we still need the 1s-of-silence trick?

## Files this plan will touch (for swift-implementer reference)

New under `ArigatoAI/Transcription/`:
- `TranscriptSegment.swift`, `SpokenLanguage.swift`, `TranscriptionError.swift`, `Transcribing.swift`
- `WhisperModelLoader.swift`, `RollingAudioBuffer.swift`, `WhisperClient.swift`
- `TranscriptionActor.swift`, `LanguageRouter.swift`, `TranscriptLiveView.swift`

New at app root: `ArigatoAI/AppBootstrapper.swift`

New tests under `ArigatoAITests/Transcription/`:
- `FakeTranscriber.swift`
- `TranscriptSegmentTests.swift`, `SpokenLanguageTests.swift`, `WhisperModelLoaderTests.swift`
- `RollingAudioBufferTests.swift`, `TranscriptionActorTests.swift`, `LanguageRouterTests.swift`
- `AppBootstrapperTests.swift`, `TranscriptionPipelineIntegrationTests.swift`

Edited:
- `ArigatoAI/ArigatoAIApp.swift`, `ArigatoAI/ContentView.swift`
- `ArigatoAI/Audio/AudioCaptureViewModel.swift`
- `ArigatoAITests/Audio/AudioCaptureViewModelTests.swift`
- `ArigatoAI.xcodeproj/project.pbxproj`
