---
name: leap-sdk
description: Integration patterns for LFM2-350M-ENJP-MT via the LEAP iOS SDK. Use whenever adding, modifying, or debugging Japanese-English translation calls. Covers SDK setup, system prompt requirements, model loading, async streaming, and concurrency constraints.
---

> **This skill reflects v0.9.4 (pinned via `Liquid4All/leap-ios`) — and that is the deliberate ship channel, not a stopgap.** P-2 attempted a v0.10.6 migration and hit an upstream XCFramework packaging bug (`libinference_engine.dylib` recorded a `@rpath/inference_engine_llamacpp_backend.framework/inference_engine_llamacpp_backend` framework-bundle dependency while the SDK shipped only the plain `libinference_engine_llamacpp_backend.dylib`; dyld could not resolve at launch). **That bug is FIXED upstream in leap-sdk v0.10.9 (2026-05-29)** — see [Liquid4All/leap-sdk#5](https://github.com/Liquid4All/leap-sdk/issues/5) (still open but stale) and the v0.10.9 release notes (ref #265); _caveat:_ release-notes-asserted, not binary/device-verified by us. **The project is NOT adopting v0.10.9 (decision locked 2026-05-31):** no v0.10.x iOS feature benefits a JA↔EN translator, and SDK version does not affect translation quality (that is model-side). Upgrade only if a future release materially benefits THIS app. Full reconciliation + the breaking-change budget: `docs/V3_BACKLOG.md` → "LEAP SDK v0.10.x migration — upstream fix shipped (v0.10.9), NOT adopting".

# LEAP iOS SDK — LFM2-350M-ENJP-MT integration

## Critical system prompt requirement
LFM2-350M-ENJP-MT requires ONE of these EXACT system prompts. No variation, no rephrasing:
- `"Translate to English."` — for Japanese → English
- `"Translate to Japanese."` — for English → Japanese

The user turn is the text to translate. Single-turn conversations only — do not accumulate history across translation calls.

## SDK package setup (v0.9.4)

**Package URL:** `https://github.com/Liquid4All/leap-ios.git`

**Pinned product:** `LeapSDK` — single SPM product in v0.9.4. (v0.10.0+ splits into multiple products; **not adopted — by decision, not block:** the upstream @rpath block cleared in v0.10.9, but v0.10.x offers no benefit to this app. See top banner.)

**Swift import:** `import LeapSDK`

## Model loading pattern (v0.9.4)

```swift
import LeapSDK

let runner: any ModelRunner = try await Leap.load(
    model: "lfm2-350m-enjp-mt",
    quantization: "Q5_K_M",
    options: manifestOptions,
    downloadProgressHandler: { progress, _ in
        // progress: 0.0 ... 1.0
    }
)
```

The portal download path is the v0.9.4 default. The B1.1 spike (V3 entry, commit `6512662`) empirically disproved the `file://` manifest alternative — `Leap.load(manifestURL:)` does NOT accept `file://` URLs in v0.9.4, throws `NSURLErrorDomain` -1011 with empty `userInfo`.

**Authoritative manifest schema URL** (maintainer-published): `https://huggingface.co/LiquidAI/LFM2-350M-ENJP-MT-GGUF/resolve/main/leap/Q5_K_M.json`. Keys are `snake_case`; `inference_type` is `"llama.cpp/text-to-text"`; `schema_version` is `"1.0.0"`.

## KV cache config (v0.9.4)

```swift
let cacheOptions = LiquidCacheOptions(path: cachePath, maxEntries: 1000)
let manifestOptions = LiquidInferenceEngineManifestOptions(cacheOptions: cacheOptions)
```

Pass `manifestOptions` to `Leap.load(...)` via the `options:` parameter. `maxEntries: 1000` is locked per Phase 5 Decision 4 revision (persistent `Caches/` directory). Cache invalidation rules and on-device benchmark are V3-tracked under "LFM2 prompt cache effectiveness benchmark."

## Conversation creation and streaming (v0.9.4)

```swift
let conversation = runner.createConversation(systemPrompt: "Translate to English.")

let options = GenerationOptions(
    temperature: 0.3,
    topP: 1.0,
    minP: 0.15,
    repetitionPenalty: 1.05
)

let stream = conversation.generateResponse(
    userTextMessage: inputText,
    generationOptions: options
)
```

**Maintainer-recommended sampling defaults** (from the published manifest):
- `temperature: 0.3`
- `min_p: 0.15`
- `repetition_penalty: 1.05`

**`GenerationOptions` field names in v0.9.4:**
- `temperature: Float?`
- `topP: Float?`
- `minP: Float?`
- `topK: Int32?`
- `repetitionPenalty: Float?`
- `maxOutputTokens: UInt32?` ← **field name is `maxOutputTokens` (NOT `maxTokens`)**
- `rngSeed: Int64?`

(v0.10.5+ renames this field to `maxTokens: Int32?` and moves the type to builder-only `init()` + `.with(...)`. Both differences are upstream-block-deferred.)

**`MessageResponse` case handling in v0.9.4:**

```swift
for try await response in stream {
    switch response {
    case let .chunk(text):
        // text is a bare String
        accumulated += text
    case .complete:
        break
    default:
        continue
    }
}
```

In v0.9.4 the `.chunk` associated value is a **bare `String`**, not a `Chunk` struct. (v0.10.5+ changes this to `MessageResponseChunk` with `.text: String` and requires `onEnum(of:)` for case-match; upstream-block-deferred.)

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

No SDK-provided `prewarm()` primitive. Use a dummy inference at app launch:

```swift
_ = try? await translate("おはようございます", direction: .jaToEn)
```

## Concurrency constraints (v0.9.4)

- `ModelRunner` is a protocol with no `Sendable` inheritance.
- `Conversation` is a class with no `Sendable` conformance.
- The established `@unchecked Sendable` adapter pattern (`LFM2EngineAdapter`) is required for crossing actor boundaries.
- Keep both `ModelRunner` and `Conversation` inside one actor's isolation. Create `Conversation` via `runner.createConversation(systemPrompt:)` inside the actor that will consume it.

**Cancellation (v0.9.4):** Cooperative — cancelling the Swift Task stops generation and frees native resources, with at most one extra token of slack after `cancel()`. `GenerationFinishReason` has no `.cancelled` case in v0.9.4 (confirmed unchanged through v0.10.5 and v0.10.6 by P-2 swiftinterface grep). Cancellation may surface as a normal stream finish.

## What this model is good at (from model card)
- Short-to-medium text (optimized for low latency at sentence scale)
- Bidirectional Japanese ↔ English
- Preserves tone in natural speech

## What it's NOT good at (from model card)
- Long-form (>3 paragraphs) — chunk first
- Single-turn only — do not feed it multi-turn history

## Migration to v0.10.x — upstream fix shipped (v0.10.9); NOT adopting [decision 2026-05-31]

P-2 attempted the v0.9.4 → v0.10.6 migration and surfaced an upstream XCFramework packaging bug affecting **v0.10.5–v0.10.8**. **That bug is now fixed upstream in leap-sdk v0.10.9 (2026-05-29)** (release notes, ref #265; resolves the `@rpath/…framework/…` dyld launch crash). Issue [Liquid4All/leap-sdk#5](https://github.com/Liquid4All/leap-sdk/issues/5) is still open but stale — open ≠ unfixed. **Decision (locked 2026-05-31): the project is NOT migrating** — no v0.10.x iOS feature benefits a JA↔EN translator and SDK version does not change translation quality; MVP-1 ships on v0.9.4. _Caveat:_ the v0.10.9 fix is release-notes-asserted, not binary/device-verified by us.

The completed migration code is parked as evidence baselines (retained only if the standing material-benefit trigger ever revives the migration):
- `~/AI-projects/arigato-ai-p2` — v0.10.6 attempt, branch `p2-leap-migration`, HEAD `d8e65d9` (5 checkpoints, builds clean, crashed at launch with dyld error — pre-v0.10.9)
- `~/AI-projects/arigato-ai-p2-v0.10.5` — v0.10.5 retry, branch `p2-v0.10.5-attempt`, HEAD `3b72378` (2 checkpoints, same crash via `LeapSDK.framework`'s inner dylib — pre-v0.10.9)

Full call-site inventory and P-2 execution results: `docs/PHASE_5_B1_1_MIGRATION_INVENTORY.md` (sections 1–5).

If the migration is ever revived: rebase a parked worktree, **re-verify the `.swiftinterface` against the then-current release** (the B1/B2/B3/B6/B9 changes were verified at v0.10.5/v0.10.6 but predate v0.10.9), budget the v0.10.9 breaking Swift changes (`ModelDownloader` rename + dynamic framework + dual-import guard from v0.10.6; `LeapDownloaderConfig.with` #262; throwing image/audio factories #264/#267), and **validate on a PHYSICAL iPhone** (community reports sim-vs-device divergence).

## Sources Consulted

- https://github.com/Liquid4All/leap-ios (v0.9.4 pinned baseline)
- https://huggingface.co/LiquidAI/LFM2-350M-ENJP-MT-GGUF (model + manifest)
- https://huggingface.co/LiquidAI/LFM2-350M-ENJP-MT-GGUF/resolve/main/leap/Q5_K_M.json (authoritative manifest schema for Q5_K_M)
- https://github.com/Liquid4All/leap-sdk/issues/5 (P-2 block tracking; resolved upstream in v0.10.9 / 2026-05-29, issue still open/stale)
- `docs/PHASE_5_B1_1_MIGRATION_INVENTORY.md` §5 (P-2 execution results, swiftinterface findings)
