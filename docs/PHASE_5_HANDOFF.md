# Phase 5 Handoff — LFM2 Translation via LEAP iOS SDK

## Goal

Attach Japanese↔English translation at `LanguageRouter`'s output. Produces `TranslatedSegment` values: source text, translated text, direction (JA→EN or EN→JA), timestamps, fallback flag. Pre-warm LFM2 at app launch after Whisper warmup completes (sequential, not parallel).

## Architectural call (locked in strategic walkthrough 2026-05-12)

Split `TranslationActor` (raw LFM2 inference + sentence buffering) from `LFM2ModelLoader` (lifecycle owner). Mirrors Phase 4's `TranscriptionActor` + `WhisperModelLoader` pattern. Translation dispatcher attaches at `LanguageRouter`'s `currentLanguage` (authoritative) surface, not `detectedLanguage` (per-window).

## Six locked architectural decisions

1. **Streaming UX**: Chunk-by-chunk Japanese live as Whisper streams, English fills in per complete sentence (option c). 200–500ms gap between Japanese line and English fill is the perceived "translating" state.

2. **Language binding**: Translator consumes `LanguageRouter.currentLanguage` (authoritative). Never sends half-sentence through wrong direction because language gate already stabilized routing. UI still shows per-line `detectedLanguage` honestly (preserves Phase 4 honesty contract).

3. **Warmup pattern**: `AppBootstrapper` warms Whisper first, then LFM2 in sequence after Whisper reports ready. Prevents 1.5GB peak memory from parallel loads, predictable startup, both models ready when user taps record.

4. **Cache strategy** (revised 2026-05-15 after xcframework inspection — original "in-memory only" lock is impossible to implement):

   `LiquidCacheOptions` in LEAP iOS SDK v0.9.4 is a struct with REQUIRED `path: String` + `maxEntries: Int` (NOT an enum; no `.inMemory` case exists — see Step 0 findings in CURRENT_STATE.md). The originally-locked "in-memory only" framing cannot be implemented directly through the SDK's type surface. The only way to avoid persistence entirely is to pass `cacheOptions: nil` to `LiquidInferenceEngineOptions.init(...)`, which disables prompt cache acceleration entirely.

   **Revised decision**: use a persistent path under iOS's Caches directory with `maxEntries: 1000`.

   ```swift
   let path = FileManager.default
       .urls(for: .cachesDirectory, in: .userDomainMask)
       .first!
       .appendingPathComponent("leap-cache")
       .path
   LiquidCacheOptions(path: path, maxEntries: 1000)
   ```

   **Privacy preserved at architecture level**: Caches/ is NOT backed up to iCloud (Apple documents this — Caches/ is excluded from iCloud and iTunes backups by default). Transcripts/cache fragments never leave the device. iOS auto-purges Caches/ under storage pressure; cache rebuilds automatically on next translation.

   **Reasoning for going with persistence rather than `cacheOptions: nil`**: performance > privacy on-device (the "no iCloud sync" architecture rule already covers privacy at the higher level), capture any speedup the SDK delivers, flipping back is trivial if diagnostics prove the cache is irrelevant. The originally-locked "cross-meeting hit rate near zero" reasoning is acknowledged but does not block use of a persistent cache — Caches/ may be purged by iOS between meetings anyway, and even within a meeting some prompt-prefix reuse is plausible (system prompt, recurring proper nouns, conversation-history accumulation).

   **V3 entry filed** (2026-05-15): "LFM2 prompt cache effectiveness benchmark" — Phase 6 diagnostics verify whether `maxEntries: 1000` in Caches/ delivers measurable per-sentence inference speedup on iPhone 17 Pro Max. If savings <20ms per sentence, flip to `cacheOptions: nil`. If yes, log baseline numbers and consider tuning `maxEntries` based on observed cache hit patterns. Trigger: Phase 6 diagnostics ship and accumulate ~1 week of real meeting data.

   **Adjacent finding** (informational, not directly affecting Decision 4): `GenerationOptions.CacheControl` is a SEPARATE per-call mechanism with `.cache | .noCache` policy at each `generateResponse(...)` call. This is layered on top of the engine-level `LiquidCacheOptions`. Group C does not tune per-call CacheControl in MVP 1 (left at SDK default).

5. **Doc-researcher pre-flight**: Full 5-category run before any code work. Categories: (1) SDK API surface, (2) streaming/token-by-token API, (3) cache API mechanics, (4) concurrency model and Sendable, (5) model loading and warmup API.

6. **Group breakdown**: 4 groups mirroring Phase 4 shape. Group A — domain types + `Translating` protocol. Group B — LEAP SDK + `LFM2ModelLoader` + `AppBootstrapper` extension. Group C — `TranslationActor` + sentence buffering + cache config. Group D — UI integration into `TranscriptLiveView`.

## Doc-researcher pre-flight (Step 0 — runs before Group A)

Five categories to verify against Liquid AI's current published docs and the LEAP iOS SDK v0.9.4 source/README:

1. **SDK API surface**: Confirm current method signatures for model loading, init parameters, inference call. Has anything renamed/restructured since handoff was written?
2. **Streaming/token-by-token API**: Does LEAP expose token-streaming inference, or batched complete-output only? Determines internal shape of `TranslationActor`'s emission pipeline.
3. **Cache API mechanics**: ✅ RESOLVED 2026-05-15 by xcframework inspection. `LiquidCacheOptions` is `struct LiquidCacheOptions { let path: String; let maxEntries: Int }` (NOT an enum). The originally-assumed `.enabled(path:)` case does not exist; there is no `.inMemory` case. To disable cache entirely, pass `cacheOptions: nil` to `LiquidInferenceEngineOptions.init(...)`. Both `LiquidInferenceEngineOptions` and `LiquidInferenceEngineManifestOptions` expose `cacheOptions: LiquidCacheOptions?` (GGUF-manifest load path also supports cache config — open question from PHASE_5_DOC_RESEARCH.md line 191 also resolved). Eviction policy beyond `maxEntries` cap is not documented in the swiftinterface.
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

`TranslationActor.swift` + sentence-boundary buffer + `LiquidCacheOptions(path: <Caches/leap-cache>, maxEntries: 1000)` per revised Decision 4. Consumes `LanguageRouter.currentLanguage` stream from Group D Phase 4 work. Emits `AsyncStream<TranslatedSegment>`.

### Group D — UI integration

Extend `TranscriptLiveView` with per-line English row beneath Japanese row. "translating…" state during LFM2 inference, fills with text when complete. Wire `TranslationActor` into `AudioCaptureViewModel`.
