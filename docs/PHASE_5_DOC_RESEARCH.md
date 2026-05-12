# Phase 5 Doc-Researcher Pre-flight Findings

**Date**: 2026-05-12
**SDK version verified**: LEAP iOS SDK — pinned as "v0.10.4.3" in handoff; see BLOCKING GAP below. All findings based on `v0.9.4` (latest public tag, 2026-03-12) + current `main` README + `docs.liquid.ai` docs.
**Sources consulted**:
- https://github.com/Liquid4All/leap-ios (main branch)
- https://github.com/Liquid4All/leap-ios/tree/v0.9.4 (latest tag found)
- https://github.com/Liquid4All/leap-ios/releases
- https://github.com/Liquid4All/LeapSDK-Examples (main branch)
- https://docs.liquid.ai/leap/edge-sdk/overview
- https://docs.liquid.ai/deployment/on-device/ios/ios-quick-start-guide.md
- https://docs.liquid.ai/deployment/on-device/ios/model-loading.md
- https://docs.liquid.ai/deployment/on-device/ios/conversation-generation.md
- https://docs.liquid.ai/deployment/on-device/ios/messages-content.md
- https://docs.liquid.ai/deployment/on-device/ios/advanced-features.md
- https://docs.liquid.ai/deployment/on-device/ios/utilities.md
- https://huggingface.co/LiquidAI/LFM2-350M-ENJP-MT
- https://huggingface.co/LiquidAI/LFM2-350M-ENJP-MT-GGUF

---

## BLOCKING GAP: v0.10.4.3 does not exist in the public repo

The tag `v0.10.4.3` does not exist in the `Liquid4All/leap-ios` GitHub repository. The complete tag listing has been verified from first tag (`v0.3.0-2`, Aug 2025) through `v0.9.4` (March 12, 2026), which is the latest release. No `v0.10.x` tag exists. The `Package.swift` on both `main` and `v0.9.4` embeds binary xcframework URLs pointing to `v0.9.4`.

**Implication for the handoff**: The version "v0.10.4.3" specified in `PHASE_5_HANDOFF.md` line 27 does not correspond to any published release. All findings below are therefore based on `v0.9.4` (source tree) and current `main` (README + Package.swift), cross-referenced against official Liquid AI docs at `docs.liquid.ai`. The locked architectural decisions were presumably made against a version that does not exist publicly; the version pin must be corrected before Group B work begins.

---

## Category 1 — SDK API surface

**Official org confirmed**: `github.com/Liquid4All/leap-ios`. The repo is the official Liquid AI iOS SDK.

**Two distinct loading overloads exist** on the `Leap` static entry point:

1. **Legacy bundle loading** (ExecuTorch backend, `.bundle` files):
   ```swift
   let runner = try await Leap.load(options: .init(bundlePath: modelURL.path()))
   ```
   This appears in the v0.9.4 README Quick Start snippet. `options` is of type `LiquidInferenceEngineOptions` initialized with `bundlePath:`.

2. **GGUF manifest loading** (llama.cpp backend, recommended for new projects):
   ```swift
   let modelRunner = try await Leap.load(
     model: "LFM2-1.2B",
     quantization: "Q5_K_M",
     downloadProgressHandler: { progress, speed in }
   )
   ```
   Documented at `docs.liquid.ai/deployment/on-device/ios/model-loading.md`. The `options` parameter for this overload is `LiquidInferenceEngineManifestOptions` (a **distinct type** from `LiquidInferenceEngineOptions`). The fields of `LiquidInferenceEngineManifestOptions` are not fully documented.

**Conversation creation**: Two factory methods on `ModelRunner`:
- `createConversation(systemPrompt: String?) -> Conversation`
- `createConversationFromHistory(history: [ChatMessage]) -> Conversation`

The v0.9.4 README Quick Start shows `Conversation(modelRunner:history:)` as a direct initializer — this conflicts with the docs showing factory methods on `ModelRunner`. The docs page is more recent and authoritative. Likely a README lag. Feature-planner should use `modelRunner.createConversation(systemPrompt:)` per the current `conversation-generation.md` doc.

**Inference call name**: `conversation.generateResponse(message:generationOptions:)` returns `AsyncThrowingStream<MessageResponse, Error>`. The method is `generateResponse`, not `generate`, `predict`, or `run`. No rename has occurred; this name is consistent across v0.9.4 README and current docs.

**`ModelRunner` is a protocol**, not a concrete type. `Conversation` is a class. This matters for Group A's `Translating` protocol shape — the concrete `ModelRunner` instance type is opaque to callers.

Sources: https://github.com/Liquid4All/leap-ios/blob/v0.9.4/README.md, https://docs.liquid.ai/deployment/on-device/ios/conversation-generation.md, https://docs.liquid.ai/deployment/on-device/ios/model-loading.md

---

## Category 2 — Streaming / token-by-token API

**LEAP does expose token-streaming inference.** The primary API returns `AsyncThrowingStream<MessageResponse, Error>`, consumed in a `for try await` loop. This is genuine incremental emission — the docs describe it as "token-by-token generation."

**`MessageResponse` enum cases** (verified across docs and example source):
- `.chunk(String)` — partial text delta, emitted per token or small group of tokens
- `.reasoningChunk(String)` — thinking tokens (chain-of-thought), wrapped in `<think>` tags in model output
- `.audioSample(samples: [Float], sampleRate: Int)` — for audio-output models; irrelevant for LFM2-350M-ENJP-MT
- `.functionCall([LeapFunctionCall])` — tool invocations; irrelevant for translation use
- `.complete(MessageCompletion)` — signals end of generation with assembled full reply and stats

**Example streaming loop** (from LeapChatExample, `ChatStore.swift`):
```swift
for try await resp in conversation.generateResponse(message: userMessage) {
    switch resp {
    case .chunk(let chunk): currentText.append(chunk.text)
    case .complete(let completion): // finalize
    default: break
    }
}
```

**Implication for TranslationActor design**: The SDK yields `.chunk` events incrementally during inference. `TranslationActor` will receive character/token deltas, not complete sentences. A sentence-boundary buffer inside `TranslationActor` is required and confirmed correct — the locked Streaming UX decision (chunk-by-chunk live for JA, per-sentence fill for EN) is structurally supported by this API.

**Overlapping generation guard**: `Conversation.isGenerating: Bool` prevents starting a second generation while one is running. If `isGenerating == true` when `generateResponse` is called, the stream finishes immediately with an empty response (async variant) or returns `nil` (callback variant). `TranslationActor` must gate on this.

**Callback variant also exists** for cases where Task-based cancellation is inconvenient:
```swift
let handler = conversation.generateResponse(message:onResponse:)
handler?.stop()
```
The `GenerationHandler` protocol conforms to `Sendable` and exposes `stop()`. The callback overload "does not surface generation errors."

Sources: https://docs.liquid.ai/deployment/on-device/ios/conversation-generation.md, https://github.com/Liquid4All/LeapSDK-Examples (ChatStore.swift, SloganStore.swift)

---

## Category 3 — Cache API mechanics

**What is confirmed**: `LiquidInferenceEngineOptions` contains a `cacheOptions: LiquidCacheOptions?` field. The docs describe it as: "Configure persistence of KV-cache data between generations." This field is passed when loading via the local-bundle path (`Leap.load(url:options:)`).

**What is NOT confirmed from official sources**:
- The concrete cases or values of the `LiquidCacheOptions` type. The type's definition is not exposed in the Swift source (the SDK ships as binary xcframeworks) and is not documented on any accessible docs page. The handoff assumes `LiquidCacheOptions.enabled(path:)` exists — this specific case name cannot be confirmed from official sources consulted.
- Whether an in-memory equivalent exists, and its exact API name.
- Eviction policy, size cap, or lifecycle behavior.
- Whether `LiquidCacheOptions` is accessible when loading via the GGUF manifest path (`Leap.load(model:quantization:options:)`), since that path uses `LiquidInferenceEngineManifestOptions` (a different type whose fields are undocumented).

**Locked decision 4 collision risk**: The locked decision specifies "in-memory only, no persistent disk cache." If `LiquidCacheOptions.enabled(path:)` is the only non-disabled case and requires a file path, then disabling disk persistence may only be achievable by passing `nil` for `cacheOptions` (i.e., disabling KV-cache entirely rather than using in-memory cache). This cannot be resolved from current official sources.

**Recommendation for Group B/C**: When `LFM2ModelLoader` is implemented, inspect the compiled SDK's Swift interface (`.swiftinterface` file inside the xcframework) via Xcode's "Jump to Definition" to determine the exact `LiquidCacheOptions` cases before committing to the cache config code. File this as a Group B pre-implementation check, not a planning blocker for Group A.

Sources: https://docs.liquid.ai/deployment/on-device/ios/model-loading.md

---

## Category 4 — Concurrency model and Sendable

**Thread safety guarantee** (verbatim from docs): "All functions listed in this document are safe to call from the main thread and all callbacks will be run on the main thread, unless there are explicit instructions or explanations."

This statement covers the `conversation-generation.md` surface (ModelRunner methods, Conversation methods, generateResponse). The scope of "all callbacks run on main thread" applies to the callback overload of `generateResponse`. Whether the `AsyncThrowingStream` overload delivers iterations on the main thread or the calling actor's thread is not explicitly stated.

**Sendable conformance status**:
- `GenerationHandler` protocol: **explicitly `Sendable`** — documented as `public protocol GenerationHandler: Sendable`.
- `ModelRunner` protocol: **not documented as Sendable**. No Sendable conformance appears in any official source.
- `Conversation` class: **not documented as Sendable**. It is a reference type (class). No Sendable annotation found.
- `LiquidInferenceEngineOptions`: **not documented as Sendable**.
- `LiquidCacheOptions`: **not documented as Sendable** (type definition not found in public sources).
- `ChatMessage`, `ChatMessageContent`: **not documented as Sendable**.
- `MessageResponse` enum: **not documented as Sendable**.

**`@preconcurrency import` question**: Not addressed anywhere in official documentation. No official guidance on using these APIs from non-main-actor Swift concurrency contexts.

**Critical implication for TranslationActor design**: The examples (ChatStore, SloganStore) all annotate their view-model classes with `@MainActor` and store `ModelRunner` and `Conversation` as `@MainActor`-isolated properties. If `ModelRunner` and `Conversation` are not `Sendable`, they cannot be passed across actor boundaries without `@preconcurrency` or `nonisolated(unsafe)`. A `TranslationActor` that holds a `Conversation` instance and calls `generateResponse` from actor isolation may require the `Conversation` to live on that same actor — which is structurally fine as long as the `Conversation` is created and owned inside the actor. Passing it in from outside (e.g., via `LFM2ModelLoader`) would require a `Sendable` wrapper or a different lifecycle pattern.

**Recommendation**: The `LFM2ModelLoader` should create the `Conversation` inside `TranslationActor`'s isolation context, not pass a `Conversation` instance across actor boundaries. `LFM2ModelLoader` can pass the `ModelRunner` to `TranslationActor.init` with a `nonisolated(unsafe)` annotation if needed, or `TranslationActor` can call a factory method to obtain its `Conversation` at init time. This is a Group B decision that must be surfaced to feature-planner.

Sources: https://docs.liquid.ai/deployment/on-device/ios/conversation-generation.md, https://github.com/Liquid4All/LeapSDK-Examples (ChatStore.swift, SloganStore.swift)

---

## Category 5 — Model loading and warmup API

**Model identifier for LFM2-350M-ENJP-MT**:
- LEAP model library slug: `lfm2-350m-enjp-mt` (confirmed from https://huggingface.co/LiquidAI/LFM2-350M-ENJP-MT model card, which links to `leap.liquid.ai/models?model=lfm2-350m-enjp-mt`)
- For `Leap.load(model:quantization:)`: the `model` parameter would be `"lfm2-350m-enjp-mt"`. The exact quantization string accepted by the LEAP SDK (not the GGUF filename) is **not confirmed** from official sources — the GGUF repo lists `Q4_0`, `Q4_K_M`, `Q5_K_M`, `Q6_K`, `Q8_0`, `F16`, `F32`, but these are GGUF quantization names not necessarily identical to LEAP SDK quantization slug strings. One search result surfaced a quantization slug `lfm2-350m-enjp-mt-20250904-8da4w` for the legacy bundle format — this appears to be a bundle-specific slug, not a GGUF quantization name.
- **The GGUF format is recommended for new projects** per the current docs.

**System prompts required** (confirmed from HuggingFace model card):
- English → Japanese: `"Translate to Japanese."`
- Japanese → English: `"Translate to English."`
- The model card explicitly warns: "The model cannot work as intended without one of these system prompts."
- The model is designed for **single-turn conversations only** — each translation call should be a fresh single-turn exchange, not accumulated conversation history.

**Recommended generation parameters** (from model card):
- `temperature: 0.5`, `top_p: 1.0`, `min_p: 0.1`, `repetition_penalty: 1.05`

**Loading state machine**: No state machine type (enum with idle/loading/ready/failed cases, or similar) is documented in official sources. The `Leap.load()` call is a simple `async throws` function. The caller is responsible for tracking state. The Phase 4 `WhisperModelLoader` pattern of maintaining a `@Observable` state enum is not provided by LEAP's SDK itself — it must be implemented in `LFM2ModelLoader`.

**Warmup API**: No explicit warmup method exists in the SDK. No `prewarm()`, `warmup()`, or equivalent is documented. The LeapSDK-Examples README mentions models are "automatically downloaded and cached on first run," but no inference-engine warmup call is documented. The pattern used by WhisperKit (1-second silent audio dummy inference) has no SDK-equivalent in LEAP's documented surface. The dummy-inference pattern (sending one short translation request at load time to initialize the Metal/llama.cpp pipeline) is a viable approach but is an implementation choice, not an SDK-provided feature.

**Backend selection**: Automatic based on file format. `.bundle` files → ExecuTorch backend. `.gguf` files → embedded llama.cpp backend. No explicit backend selection parameter.

Sources: https://docs.liquid.ai/deployment/on-device/ios/model-loading.md, https://docs.liquid.ai/deployment/on-device/ios/ios-quick-start-guide.md, https://huggingface.co/LiquidAI/LFM2-350M-ENJP-MT, https://huggingface.co/LiquidAI/LFM2-350M-ENJP-MT-GGUF

---

## Collisions with locked decisions

**Locked decision 4 (Cache strategy)** — Partial collision risk, not a confirmed collision:

The handoff assumes `LiquidCacheOptions.enabled(path:)` exists as a named case and that an in-memory equivalent is available. Official sources confirm only that `cacheOptions: LiquidCacheOptions?` is a field and that it "configures persistence of KV-cache data between generations." The type's cases are not documented publicly. The in-memory option's existence cannot be confirmed or denied from accessible official sources. The locked reasoning (in-memory only, no disk, no iCloud) is sound, but whether the SDK API supports that configuration exactly as assumed is unverified.

**Locked decision 3 (Warmup pattern: sequential Whisper-then-LFM2)** — No collision with SDK behavior, but the warmup *mechanism* must be implemented differently than WhisperKit. WhisperKit exposes a `prewarm()` method. LEAP does not. The AppBootstrapper sequential-warmup decision remains valid, but the warmup signal from LFM2 side will be "first inference completes" (dummy-inference pattern), not "prewarm() returns." This is an implementation detail, not a locked-decision conflict.

**No collisions detected** with decisions 1, 2, 5, or 6.

**Version-pin collision (separate from the six locked decisions)**: The handoff names `v0.10.4.3` as the SDK version under test. This tag does not exist publicly. Latest public release is `v0.9.4`. This is a factual error in the handoff document, not a conflict between maintainer guidance and a locked decision. It must be corrected before Group B SPM-dependency work.

---

## Gaps

1. **v0.10.4.3 does not exist.** The pinned version in the handoff has no corresponding tag, release, or source in the public `Liquid4All/leap-ios` repository. Latest public release is `v0.9.4` (2026-03-12). The handoff must be corrected before Group B work. **STOP condition for Group B** — do not proceed until the SPM pin is confirmed against a real tag.

2. **`LiquidCacheOptions` type definition is not publicly accessible.** The SDK ships as binary xcframeworks. The type's cases, in-memory option name, eviction policy, and lifecycle are all undocumented in official sources. Required action before Group C cache config code: inspect the `.swiftinterface` file inside the installed xcframework in Xcode to read the compiled type definition. This is a Group B pre-work task.

3. **`LiquidInferenceEngineManifestOptions` fields are undocumented.** If the GGUF path is used (recommended), the `options` type for `Leap.load(model:quantization:options:)` is `LiquidInferenceEngineManifestOptions`, not `LiquidInferenceEngineOptions`. Whether `LiquidInferenceEngineManifestOptions` has a `cacheOptions` field at all is unknown from public docs.

4. **Quantization slug for LFM2-350M-ENJP-MT in LEAP SDK not confirmed.** The GGUF repo lists standard GGUF quantization names (`Q4_K_M`, etc.). Whether the LEAP SDK's `Leap.load(model:quantization:)` accepts these same strings or uses different LEAP-specific identifiers for this model has not been confirmed from official sources. Required action: check the LEAP model library UI at `leap.liquid.ai/models?model=lfm2-350m-enjp-mt` while logged in, or open a Liquid AI support ticket.

5. **Sendable conformance of `ModelRunner`, `Conversation`, `ChatMessage`, `MessageResponse`, and `LiquidInferenceEngineOptions` is not documented.** None of these types have confirmed `Sendable` conformance in official sources. This directly affects `TranslationActor`'s design. Required action: inspect `.swiftinterface` files after SDK installation to read actual conformances.

6. **`AsyncThrowingStream` delivery thread for `generateResponse` is unspecified.** The docs guarantee callbacks run on main thread, but do not explicitly state whether the `AsyncThrowingStream` overload delivers iterations on the calling actor's thread, the main thread, or an unspecified thread. Required action: empirical test in an isolated Swift file after SDK installation, or open a GitHub issue at `Liquid4All/leap-ios`.

7. **No SDK-provided warmup API.** The dummy-inference pattern is the implied approach but is not documented by Liquid AI. If there is startup latency concern for the first real translation, a short warmup inference (e.g., "Hello." → "こんにちは。") should be issued in AppBootstrapper after model load. This is an implementation decision for Group B, not a planning blocker for Group A.
