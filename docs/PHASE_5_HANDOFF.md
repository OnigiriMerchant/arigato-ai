# Phase 5 Handoff — LFM2 Translation via LEAP iOS SDK

## Goal

Attach Japanese↔English translation at `LanguageRouter`'s output. Produces `TranslatedSegment` values: source text, translated text, direction (JA→EN or EN→JA), timestamps, fallback flag. Pre-warm LFM2 at app launch after Whisper warmup completes (sequential, not parallel).

## Architectural call (locked in strategic walkthrough 2026-05-12)

Split `TranslationActor` (raw LFM2 inference + sentence buffering) from `LFM2ModelLoader` (lifecycle owner). Mirrors Phase 4's `TranscriptionActor` + `WhisperModelLoader` pattern. Translation dispatcher attaches at `LanguageRouter`'s `currentLanguage` (authoritative) surface, not `detectedLanguage` (per-window).

## Six locked architectural decisions

1. **Streaming UX**: Chunk-by-chunk Japanese live as Whisper streams, English fills in per complete sentence (option c). 200–500ms gap between Japanese line and English fill is the perceived "translating" state.

2. **Language binding**: Translator consumes `LanguageRouter.currentLanguage` (authoritative). Never sends half-sentence through wrong direction because language gate already stabilized routing. UI still shows per-line `detectedLanguage` honestly (preserves Phase 4 honesty contract).

3. **Warmup pattern**: `AppBootstrapper` warms Whisper first, then LFM2 in sequence after Whisper reports ready. Prevents 1.5GB peak memory from parallel loads, predictable startup, both models ready when user taps record.

4. **Cache strategy**: `LiquidCacheOptions` in-memory only. No persistent disk cache. Reasoning: LFM2 prompt cache is KV-state inference acceleration not translation memory; cross-meeting hit rate near zero; persistent cache in Documents folder backs up to iCloud (privacy conflict). V3 entry filed for revisit if real-meeting data flips the assumption.

5. **Doc-researcher pre-flight**: Full 5-category run before any code work. Categories: (1) SDK API surface, (2) streaming/token-by-token API, (3) cache API mechanics, (4) concurrency model and Sendable, (5) model loading and warmup API.

6. **Group breakdown**: 4 groups mirroring Phase 4 shape. Group A — domain types + `Translating` protocol. Group B — LEAP SDK + `LFM2ModelLoader` + `AppBootstrapper` extension. Group C — `TranslationActor` + sentence buffering + cache config. Group D — UI integration into `TranscriptLiveView`.

## Doc-researcher pre-flight (Step 0 — runs before Group A)

Five categories to verify against Liquid AI's current published docs and the LEAP iOS SDK v0.10.4.3 source/README:

1. **SDK API surface**: Confirm current method signatures for model loading, init parameters, inference call. Has anything renamed/restructured since handoff was written?
2. **Streaming/token-by-token API**: Does LEAP expose token-streaming inference, or batched complete-output only? Determines internal shape of `TranslationActor`'s emission pipeline.
3. **Cache API mechanics**: Confirm `LiquidCacheOptions.enabled(path:)` and in-memory equivalent exist and behave as assumed.
4. **Concurrency model**: Is LEAP's inference thread-safe? Can we call from an actor without `@preconcurrency`? Sendable conformance of relevant types?
5. **Model loading and warmup API**: How to load LFM2-350M-ENJP-MT specifically, what state machine the loader exposes, how to perform warmup call.

Findings document drives Group A planning. Plan that comes out must include the "Doc-researcher pre-flight: ran on YYYY-MM-DD against [URL]. Findings: [summary]" line per V3 #41's rule.

## Group structure summary

(Files this plan will touch — drafts only, exact list refined by @feature-planner after doc-researcher pre-flight findings.)

### Group A — Domain types + `Translating` protocol

New under `ArigatoAI/Translation/`:
- `TranslatedSegment.swift`, `TranslationDirection.swift`, `TranslationError.swift`
- `Translating.swift` (protocol mirroring `Transcribing`)

New tests under `ArigatoAITests/Translation/`:
- `FakeTranslator.swift`, `TranslatedSegmentTests.swift`, `TranslationProtocolTests.swift`

### Group B — LEAP SDK + `LFM2ModelLoader` + `AppBootstrapper` extension

SPM addition + new `LFM2ModelLoader` actor + extend `AppBootstrapper` to warm LFM2 after Whisper ready. Extend `StartupErrorView` for LFM2 load failures. State machine mirrors `WhisperModelLoader`.

### Group C — `TranslationActor` + sentence buffering + cache config

`TranslationActor.swift` + sentence-boundary buffer + `LiquidCacheOptions` in-memory config. Consumes `LanguageRouter.currentLanguage` stream from Group D Phase 4 work. Emits `AsyncStream<TranslatedSegment>`.

### Group D — UI integration

Extend `TranscriptLiveView` with per-line English row beneath Japanese row. "translating…" state during LFM2 inference, fills with text when complete. Wire `TranslationActor` into `AudioCaptureViewModel`.
