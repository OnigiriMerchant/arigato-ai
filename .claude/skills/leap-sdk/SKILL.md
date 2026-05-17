---
name: leap-sdk
description: Integration patterns for LFM2-350M-ENJP-MT via the LEAP iOS SDK. Use whenever adding, modifying, or debugging Japanese-English translation calls. Covers SDK setup, system prompt requirements, model loading, async streaming, and concurrency constraints.
---

<!-- Verified against: LEAP iOS SDK v0.9.4 (commit 72afe9bf4c2fae086fbced3b05995edaad2c6bf2). Reconcile date: 2026-05-17. Sources: .swiftinterface inspection (PHASE_5_GROUP_B_PRE_FLIGHT.md), github.com/Liquid4All/leap-ios tree, docs.liquid.ai model card. -->

# LEAP iOS SDK — LFM2-350M-ENJP-MT integration

## Critical system prompt requirement
LFM2-350M-ENJP-MT requires ONE of these EXACT system prompts. No variation, no rephrasing:
- `"Translate to English."` — for Japanese → English
- `"Translate to Japanese."` — for English → Japanese

The user turn is the text to translate. Single-turn conversations only — do not accumulate history across translation calls.

## Model loading pattern (v0.9.4)
The locked GGUF path uses overload #3 from the `.swiftinterface`:

```swift
import LeapSDK

actor LFM2ModelLoader {
    private(set) var runner: (any ModelRunner)?

    func load() async throws {
        guard runner == nil else { return }
        runner = try await Leap.load(
            model: "lfm2-350m-enjp-mt",
            quantization: "Q5_K_M",
            options: nil,
            downloadProgressHandler: nil
        )
    }
}
```

`Leap.load(url:)` exists in v0.9.4 but is marked `@available(*, deprecated, message: "Use load(options:) instead")`. Do not use it in new code.

## Conversation creation
Use the factory on `ModelRunner` — cleaner than the `Conversation(modelRunner:history:)` initializer:

```swift
let conversation = runner.createConversation(systemPrompt: "Translate to English.")
let stream = conversation.generateResponse(
    message: ChatMessage(role: .user, content: [.text(inputText)]),
    generationOptions: GenerationOptions(maxTokens: 256)
)
```

`maxTokens: 256` is sourced from the official model card examples. Other `GenerationOptions` fields (`temperature`, `topP`, `minP`, `repetitionPenalty`) are available but their recommended values for this model are not confirmed by an allowed source — prefer the bundle manifest defaults (pass `nil` fields).

## Direction handling
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

## Cold-start mitigation
No SDK-provided warmup primitive exists (`prewarm()`, `warmup()`, and `preload()` are absent from the v0.9.4 interface). Use a dummy inference at app launch — the dummy-inference pattern is the only path:

```swift
_ = try? await translate("おはようございます", direction: .jaToEn)
```

First inference after load can be slow. Pre-warm before the first meeting session.

## What this model is good at (from model card)
- Short-to-medium text (optimized for low latency at sentence scale)
- Bidirectional Japanese ↔ English
- Preserves tone in natural speech

## What it's NOT good at (from model card)
- Long-form (>3 paragraphs) — chunk first
- Single-turn only — do not feed it multi-turn history

## Concurrency constraints (v0.9.4 .swiftinterface)
`ModelRunner` is a non-Sendable protocol. `Conversation` is a non-Sendable class. Neither crosses actor boundaries safely.

- Do NOT hold `any ModelRunner` or `Conversation` as stored properties in a `Sendable` type without `nonisolated(unsafe)`.
- Preferred pattern: keep both `ModelRunner` and `Conversation` inside one actor's isolation. Create `Conversation` via `runner.createConversation(systemPrompt:)` inside the actor that will consume it.
- `GenerationHandler` is the only Sendable type in the relevant surface — use it for cancellation across boundaries.

## KV cache (v0.9.4)
`LiquidCacheOptions` is a plain struct: `LiquidCacheOptions(path: String, maxEntries: Int)`. Both fields are non-optional. There is no in-memory variant and no `.enabled(path:)` factory in v0.9.4. If omitting the cache entirely (`options: nil`), KV-cache acceleration is disabled. If enabling it, use `Library/Caches` (not `Documents`) to avoid iCloud backup. Cache strategy is a pending architectural decision (see V3 backlog, D4 collision).
