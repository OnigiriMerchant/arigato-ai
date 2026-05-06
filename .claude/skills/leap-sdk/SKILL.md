---
name: leap-sdk
description: Integration patterns for LFM2-350M-ENJP-MT via the LEAP iOS SDK. Use whenever adding, modifying, or debugging Japanese-English translation calls. Covers SDK setup, system prompt requirements, model bundle loading, async streaming, generation parameters.
---

# LEAP iOS SDK — LFM2-350M-ENJP-MT integration

## Critical system prompt requirement
LFM2-350M-ENJP-MT requires ONE of these EXACT system prompts. No variation, no rephrasing:
- `"Translate to English."` — for Japanese → English
- `"Translate to Japanese."` — for English → Japanese

The user prompt is the text to translate. That's the entire interface.

## Generation parameters (from official model card)
```swift
GenerationOptions(
    temperature: 0.5,
    topP: 1.0,
    minP: 0.1,
    repetitionPenalty: 1.05,
    maxTokens: 512  // sentences are short; 512 is generous
)
```

## Bundle loading pattern
```swift
import LeapSDK

actor Translator {
    private var runner: LeapRunner?
    
    func warmup() async throws {
        guard runner == nil else { return }
        let bundleURL = Bundle.main.url(
            forResource: "LFM2-350M-ENJP-MT-Q5_K_M",
            withExtension: "bundle"
        )!
        runner = try await Leap.load(url: bundleURL)
        // Pre-warm with dummy inference to avoid cold-start glitch
        _ = try? await translate("おはようございます", direction: .jaToEn)
    }
}
```

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
First inference after model load can be slow or produce truncated output. ALWAYS pre-warm with a dummy translation at app launch. The user-facing impact of skipping this is broken first sentence in a meeting.

## What this model is good at
- 1-2 sentence business Japanese
- Tone/politeness preservation (keigo)
- News-article style content

## What it's NOT good at
- Single words (<5 words) — model needs sentence context
- Long-form (>3 paragraphs) — chunk first
- Technical/domain jargon (medical, legal) — fine-tune for production accuracy
- Novel proper nouns (product names introduced for first time)

## Latency expectations on iPhone 17 Pro Max
- Q5_K_M quantization: ~150-400ms per sentence (warm)
- Q8_0 quantization: ~250-600ms per sentence (warm)
- Cold first inference: 1-3s

## Common pitfalls
- Loading model on the main actor — DON'T. Use a dedicated actor.
- Calling translate() before warmup() completes — guard with `runner != nil`.
- Feeding partial sentences from Whisper — wait for sentence-end via VAD before calling translate.
