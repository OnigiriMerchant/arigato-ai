---
name: leap-sdk
description: Integration patterns for LFM2-350M-ENJP-MT via the LEAP iOS SDK. Use whenever adding, modifying, or debugging Japanese-English translation calls. Covers SDK setup, system prompt requirements, model loading, async streaming, and concurrency constraints.
---

<!-- Verified against: LEAP iOS SDK v0.10.6 (released 2026-05-12, tag v0.10.6 on Liquid4All/leap-sdk). Reconcile date: 2026-05-18. Sources: docs.liquid.ai quick-start, model-loading, conversation-generation, leap-sdk-changelog; github.com/Liquid4All/leap-sdk Package.swift (tag v0.10.6); github.com/Liquid4All/leap-sdk/releases/tag/v0.10.6. -->

# LEAP iOS SDK — LFM2-350M-ENJP-MT integration

## Critical system prompt requirement
LFM2-350M-ENJP-MT requires ONE of these EXACT system prompts. No variation, no rephrasing:
- `"Translate to English."` — for Japanese → English
- `"Translate to Japanese."` — for English → Japanese

The user turn is the text to translate. Single-turn conversations only — do not accumulate history across translation calls.

## SDK package setup (v0.10.0+)

**Package URL (changed in v0.10.0):** `https://github.com/Liquid4All/leap-sdk.git`

**Minimum iOS deployment target:** 17.0 (raised from 15.0 in v0.10.0)

**Swift tools version required:** 6.0 (Xcode 16+)

**Pick exactly one product per target:**
- `LeapSDK` — core inference + conversation; no download manager
- `LeapModelDownloader` — re-exports all `LeapSDK` types PLUS `URLSession`-backed downloads

For sideloaded GGUF (our use case), use `LeapModelDownloader`. In v0.10.6, linking both `LeapSDK` and `LeapModelDownloader` together produces a build-time dual-import guard error. Use only `import LeapModelDownloader` — it re-exports all `LeapSDK` types, so no separate `import LeapSDK` is needed.

Other products (not used in Arigato AI): `LeapOpenAIClient`, `LeapUI`, `LeapSDKMacros`.

## Model loading pattern (v0.10.6 — sideloaded GGUF)

For sideloaded GGUF files (not portal download), use `LeapDownloader.loadSimpleModel(model:options:...)`:

```swift
import LeapModelDownloader  // NOT import LeapSDK

let downloader = LeapDownloader(
    config: LeapDownloaderConfig(saveDir: modelsDir)
)

let cacheDir = // ... resolve from FileManager (.cachesDirectory)
let options = LiquidInferenceEngineManifestOptions(
    cacheOptions: .enabled(path: cacheDir)
)

let runner: any ModelRunner = try await downloader.loadSimpleModel(
    model: ModelSource(
        modelPath: ggufURL.path,
        modelName: "lfm2-350m-enjp-mt",
        quantizationId: "Q5_K_M"
    ),
    options: options
)
```

Key changes from v0.9.4:
- `Leap.load(model:quantization:options:downloadProgressHandler:)` is the legacy compatibility API. New code should use `LeapDownloader.loadSimpleModel(model:options:...)`.
- `ModelSource(modelPath:modelName:quantizationId:)` is the new type (replaces bare string args).
- `LiquidCacheOptions(path:maxEntries:)` initializer is no longer the documented API; use `LiquidCacheOptions.enabled(path:)` static factory (added in v0.10.4.3).
- `LiquidInferenceEngineManifestOptions` uses `cacheOptions: LiquidCacheOptions?` (unchanged field name, but construction changes).

**`LeapDownloader` vs `ModelDownloader`:** In v0.10.6, `LeapModelDownloader` SPM product exposes `ModelDownloader` as the class name (renamed from `LeapModelDownloader` class in v0.10.6 breaking change). `LeapDownloader` is the older non-SPM-product class, still present for compatibility. For SPM consumers importing `LeapModelDownloader`, use `ModelDownloader`.

## Conversation creation and streaming (v0.10.6)

```swift
let conversation = runner.createConversation(systemPrompt: "Translate to English.")

// v0.10.6 GenerationOptions — key field name: maxTokens (NOT maxOutputTokens)
let options = GenerationOptions(
    temperature: 0.5,
    topP: 1.0,
    minP: 0.1,
    repetitionPenalty: 1.05
)

let stream = conversation.generateResponse(
    userTextMessage: inputText,  // or: message: ChatMessage(...)
    generationOptions: options
)
```

**`GenerationOptions` field names in v0.10.6:**
- `temperature: Float?`
- `topP: Float?`
- `minP: Float?`
- `topK: Int32?`
- `repetitionPenalty: Float?`
- `maxTokens: Int32?` ← **field name is `maxTokens`, NOT `maxOutputTokens`** (v0.9.4 had `maxOutputTokens: UInt32?`)
- `rngSeed: Int64?`
- `jsonSchemaConstraint: String?`, `extras: String?`, etc.

**`MessageResponse` case handling in v0.10.6:**
Use `switch onEnum(of: response)` for exhaustive matching (SKIE-bridged Kotlin sealed class):

```swift
for try await response in stream {
    switch onEnum(of: response) {
    case .chunk(let c):
        // c is MessageResponse.Chunk — access text via c.text
        accumulated += c.text
    case .complete(let completion):
        // completion.fullMessage, completion.finishReason, completion.stats
        break
    case .reasoningChunk, .functionCalls, .audioSample:
        // drop — not surfaced in translation pipeline
        continue
    }
}
```

**CRITICAL:** In v0.10.6, `.chunk` associated value is `MessageResponse.Chunk` (a struct with `.text: String`), NOT a bare `String`. The v0.9.4 pattern `case let .chunk(text): use(text)` is now `case .chunk(let c): use(c.text)` or via `onEnum(of:)`.

**`MessageResponse` cases in v0.10.6 (complete set):**
- `.chunk(Chunk)` — `Chunk.text: String`
- `.reasoningChunk(ReasoningChunk)` — `ReasoningChunk.reasoning: String`
- `.functionCalls(FunctionCalls)` — `FunctionCalls.functionCalls: [LeapFunctionCall]`
- `.audioSample(AudioSample)` — `AudioSample.samples`, `.sampleRate`
- `.complete(Complete)` — `Complete.fullMessage`, `.finishReason`, `.stats: GenerationStats?`

**Note on case name:** v0.9.4's `.swiftinterface` recorded `.functionCall` (singular). v0.10.6 docs show `.functionCalls` (plural). The compatibility layer may bridge this — verify at compile time.

## Direction handling (unchanged)

```swift
enum TranslationDirection {
    case jaToEn, enToJa

    var systemPrompt: String {
        switch self {
        case .jaToEn: return "Translate to English."
        case .enToJa: return "Translate to Japanese."
        }
    }
}
```

## Cold-start mitigation (unchanged)

No SDK-provided `prewarm()` primitive. Use a dummy inference at app launch:

```swift
_ = try? await translate("おはようございます", direction: .jaToEn)
```

## GenerationStats (v0.10.6)

Available via `completion.stats: GenerationStats?` in the `.complete` case:
- `promptTokens: Long`
- `completionTokens: Long`
- `totalTokens: Long`
- `tokenPerSecond: Float`
- `cachedPromptTokens: Long` (non-zero when KV cache hit)

## What this model is good at (from model card)
- Short-to-medium text (optimized for low latency at sentence scale)
- Bidirectional Japanese ↔ English
- Preserves tone in natural speech

## What it's NOT good at (from model card)
- Long-form (>3 paragraphs) — chunk first
- Single-turn only — do not feed it multi-turn history

## Concurrency constraints (v0.10.6)

The docs state all API functions are safe to call from the main/UI thread. `ModelRunner` remains a protocol with no `Sendable` inheritance in v0.10.6 public docs. `Conversation` remains a class. Neither is explicitly `Sendable` in the v0.10.6 documentation.

- The established `@unchecked Sendable` adapter pattern (`LFM2EngineAdapter`) remains appropriate. Verify at compile time whether `ModelRunner` or `Conversation` gained `Sendable` conformance in v0.10.6 — if they did, the `nonisolated(unsafe)` and `@unchecked Sendable` annotations become unnecessary overhead but not errors.
- Keep both `ModelRunner` and `Conversation` inside one actor's isolation. Create `Conversation` via `runner.createConversation(systemPrompt:)` inside the actor that will consume it.

**Cancellation (v0.10.6 — confirmed from docs):**
> "Cancelling the Swift Task ... stops generation and frees native resources."
> "Cancellation is cooperative — the engine checks between tokens, so there's at most one extra token of slack after cancel()."

This matches the existing `TranslationActor.cancel()` doc-comment which was based on 2026-05-16 doc-researcher findings. The v0.10.6 docs confirm this behavior is still current.

## KV cache (v0.10.6)

`LiquidCacheOptions` now exposes a static factory instead of a memberwise init:

```swift
// v0.10.6 (correct):
let cacheOptions: LiquidCacheOptions = .enabled(path: cacheDir.path)

// v0.9.4 (no longer documented public API):
// LiquidCacheOptions(path: cachePath, maxEntries: 1000)  ← do NOT use
```

The `maxEntries` parameter is no longer part of the public `LiquidCacheOptions` API in v0.10.6. The SDK manages its own eviction internally. Pass `options.cacheOptions = .enabled(path:)` to `LiquidInferenceEngineManifestOptions`.

KV cache config in v0.10.4+ uses a "Bounded-LRU CacheOptions API" internally. `use_mmap=true` is the engine default since v0.10.4.

## Migration from v0.9.4

A full call-site inventory and sequenced migration plan are in `docs/PHASE_5_B1_1_MIGRATION_INVENTORY.md`. Summary: the migration involves 1 package URL change, ~15 pure-rename call sites, ~10 signature changes, and 4 behavioral-area verifications (LiquidCacheOptions construction, MessageResponse case payload access pattern, Leap.load removal forced by dual-import guard, GenerationFinishReason case-set verification).

## Sources Consulted

- https://docs.liquid.ai/deployment/on-device/sdk/quick-start
- https://docs.liquid.ai/deployment/on-device/sdk/model-loading
- https://docs.liquid.ai/deployment/on-device/sdk/conversation-generation
- https://docs.liquid.ai/deployment/on-device/leap-sdk-changelog
- https://github.com/Liquid4All/leap-sdk (v0.10.6 tag)
- https://github.com/Liquid4All/leap-sdk/releases/tag/v0.10.6
- https://raw.githubusercontent.com/Liquid4All/leap-sdk/refs/tags/v0.10.6/Package.swift
