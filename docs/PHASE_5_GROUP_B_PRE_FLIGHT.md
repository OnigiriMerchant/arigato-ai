# Phase 5 Group B Pre-flight Findings

**Date**: 2026-05-12
**Step**: Group B Step 2 — `.swiftinterface` inspection post-SPM-install
**SDK version**: LEAP iOS SDK v0.9.4 (tag commit `0c444e584971ee08106cb3ed999dae7dc0bed706`, peeled to source commit `72afe9bf4c2fae086fbced3b05995edaad2c6bf2`)
**xcframework path**: `/Users/josecastell/Library/Developer/Xcode/DerivedData/ArigatoAI-cqfyrsgbtxsvntgobayhpahfospt/SourcePackages/artifacts/leap-ios/LeapSDK/LeapSDK.xcframework`
**.swiftinterface paths inspected**:
- `LeapSDK.xcframework/ios-arm64_x86_64-simulator/LeapSDK.framework/Modules/LeapSDK.swiftmodule/arm64-apple-ios-simulator.swiftinterface` (760 lines, primary source)
- `LeapSDK.xcframework/ios-arm64_x86_64-simulator/LeapSDK.framework/Modules/LeapSDK.swiftmodule/x86_64-apple-ios-simulator.swiftinterface` (760 lines, verified identical surface)
- `arm64-apple-ios-simulator.private.swiftinterface` and `x86_64-apple-ios-simulator.private.swiftinterface` (760 lines each — same public surface; "private" file is the underscored-symbol-preserving variant used for `@testable import`, not a richer API)

**Compiler banner**: `Apple Swift version 6.2.4 effective-5.10`, `-swift-version 5`, `-target arm64-apple-ios17.0-simulator`, `-enable-library-evolution`. SDK is shipped as a stable-ABI binary framework built with Swift 6.2.4 in effective-5.10 mode.

## (a) `LiquidInferenceEngineManifestOptions` — field list

Verbatim from `.swiftinterface` lines 645–656:

```
public struct LiquidInferenceEngineManifestOptions {
  public var cacheOptions: LeapSDK.LiquidCacheOptions?
  public var cpuThreads: Swift.UInt32?
  public var contextSize: Swift.UInt32?
  public var nGpuLayers: Swift.UInt32?
  public var audioDecoderUseGpu: Swift.Bool?
  public var chatTemplate: Swift.String?
  public var extras: Swift.String?
  public init(cacheOptions: ... = nil, cpuThreads: ... = nil, contextSize: ... = nil,
              nGpuLayers: ... = nil, audioDecoderUseGpu: ... = nil,
              chatTemplate: ... = nil, extras: ... = nil)
}
```

| Field | Type | Default in init |
| --- | --- | --- |
| `cacheOptions` | `LiquidCacheOptions?` | `nil` |
| `cpuThreads` | `UInt32?` | `nil` |
| `contextSize` | `UInt32?` | `nil` |
| `nGpuLayers` | `UInt32?` | `nil` |
| `audioDecoderUseGpu` | `Bool?` | `nil` |
| `chatTemplate` | `String?` | `nil` |
| `extras` | `String?` | `nil` |

All fields are `public var` (mutable). All are optional with `nil` defaults — the type can be constructed with `LiquidInferenceEngineManifestOptions()` and every field individually set if needed.

**`cacheOptions` field present on this type**: **YES**.

**Implications for L4 (in-memory cache lock)**: `cacheOptions` is reachable on the GGUF manifest path (D1's locked path). However, see section (c) — the cache type itself does not expose an in-memory mode, which is the load-bearing collision against D4.

## (b) Sendable conformance status

| Type | Kind | Sendable status | Notes |
| --- | --- | --- | --- |
| `ModelRunner` | `public protocol` | **NOT Sendable** | Declared on line 518 as `public protocol ModelRunner` with no Sendable inheritance. Used as `any ModelRunner` return type from all four `Leap.load(...)` overloads. |
| `Conversation` | `public class` | **NOT Sendable** | Declared on line 413 as `public class Conversation` (no `final`, no Sendable). Stores `final public let modelRunner: any ModelRunner` and mutable `history`. Reference type held by user code. |
| `ChatMessage` | `public struct` | **NOT Sendable** | Declared on line 325. Has `Codable` extension (line 308) — that's the only conformance found. No Sendable annotation. |
| `MessageResponse` | `public enum` | **NOT Sendable** | Declared on line 508. Five cases (`chunk`, `reasoningChunk`, `audioSample`, `complete`, `functionCall`). No Sendable annotation. |
| `GenerationHandler` | `public protocol` | **IS Sendable** | Declared on line 515 as `public protocol GenerationHandler : Swift.Sendable { func stop() }`. The only Sendable type in the surface relevant to D2. |

No `@preconcurrency` annotations appear anywhere in the `.swiftinterface`. No conditional Sendable conformances (no `Sendable where ...` clauses).

**Adjacent observation**: `LiquidInferenceEngine` (line 550, a lower-level type distinct from `LiquidInferenceEngineRunner`) is declared `final public class LiquidInferenceEngine : @unchecked Swift.Sendable`. This is the only `@unchecked Sendable` annotation in the entire interface. It is the C-shim wrapper, not the API consumers normally touch — `LiquidInferenceEngineRunner` (line 33, the concrete `ModelRunner` implementer) is **NOT** declared Sendable.

**Implications for D2** (`LFM2ModelLoader` owns `ModelRunner`; passes to `TranslationActor.init`):

D2 lock-text said: "passes to `TranslationActor.init` with `nonisolated(unsafe)` if not Sendable." Inspection confirms **`ModelRunner` is not Sendable**, so the `nonisolated(unsafe)` annotation **is required** if the `ModelRunner` instance is to be initialized in `LFM2ModelLoader` and passed across to `TranslationActor`.

Three pattern options for Group C planning (recommend the planner choose one):

1. **`nonisolated(unsafe) let runner: any ModelRunner` on a `Sendable`-wrapper** — pass through actor init; ownership transfer is logically single-writer/single-reader so unsafe-but-actually-fine.
2. **`LFM2ModelLoader` never hands the runner out** — exposes only a factory method `makeConversation(systemPrompt:) async -> Conversation` that calls `runner.createConversation(...)` on its own isolation; `Conversation` (also non-Sendable) is created inside `TranslationActor`'s context via a closure dispatched onto `LFM2ModelLoader`. Adds an extra hop per warmup but avoids any unsafe annotation.
3. **`LFM2ModelLoader` is itself an actor and lazily produces the `Conversation` on the actor's isolation** — caller passes the actor reference rather than the runner; all SDK calls go through the actor. Mirrors the Phase 4 `WhisperModelLoader` shape closely.

The doc-researcher Category 4 recommendation (`Conversation` created inside the consumer's isolation) is compatible with options 2 and 3. Option 1 was the lock-text default; options 2 and 3 are tighter. **Surfacing this to Group C planner** — not blocking Group B.

## (c) `LiquidCacheOptions` cases

`LiquidCacheOptions` is a **struct, not an enum**. Verbatim (lines 624–628):

```
public struct LiquidCacheOptions {
  public let path: Swift.String
  public let maxEntries: Swift.Int
  public init(path: Swift.String, maxEntries: Swift.Int)
}
```

Both fields are non-optional. There is no static factory case, no `.enabled(path:)` case (because there's no enum), no `.inMemory` constructor, and no path-defaulting initializer. The only constructor requires both arguments.

**This is the load-bearing finding for D4.** See "Collisions with locked decisions" below.

For completeness, a related (but separate) cache-related type exists for per-generation control: `GenerationOptions.CacheControl` (lines 440–454) with policies `.cache` and `.noCache`, plus a top-level `LiquidCacheControl` / `LiquidCacheControlType` pair (lines 696–711). Those govern *whether to use* the cache during a given generation, not whether the cache is in-memory or on-disk. They do not provide an in-memory mode for the underlying cache storage.

## (d) `Leap.load(...)` overload signatures

Four overloads exist on `public struct Leap` (lines 258–270):

```
1. public static func load(options: LiquidInferenceEngineOptions) throws -> any ModelRunner
2. public static func load(manifestURL: Foundation.URL,
                          options: LiquidInferenceEngineManifestOptions? = nil,
                          downloadProgressHandler: ((Double, Int64) -> Void)? = nil)
                          async throws -> any ModelRunner
3. public static func load(model: Swift.String,
                          quantization: Swift.String,
                          options: LiquidInferenceEngineManifestOptions? = nil,
                          downloadProgressHandler: ((Double, Int64) -> Void)? = nil)
                          async throws -> any ModelRunner
4. @available(*, deprecated, message: "Use load(options:) instead")
   public static func load(url: Foundation.URL,
                          options: LiquidInferenceEngineOptions? = nil)
                          throws -> any ModelRunner
```

| # | Path | Async | Options type | Notes |
| --- | --- | --- | --- | --- |
| 1 | Bundle path via options struct | sync `throws` | `LiquidInferenceEngineOptions` | ExecuTorch backend; bundle file at `options.bundlePath`. |
| 2 | Manifest URL | `async throws` | `LiquidInferenceEngineManifestOptions?` | For self-hosted GGUF manifests. |
| 3 | **Model slug + quantization** | `async throws` | `LiquidInferenceEngineManifestOptions?` | **D1's locked GGUF path.** Calls `model: "lfm2-350m-enjp-mt", quantization: "Q5_K_M"`. |
| 4 | URL (deprecated) | sync `throws` | `LiquidInferenceEngineOptions?` | Marked deprecated; use #1. |

**Overload #3 is the GGUF/manifest path confirmed by D1.** The `quantization` parameter is `String` (not an enum), so the locked `Q5_K_M` slug is passed verbatim. The doc-researcher's open gap on quantization-slug acceptance is resolved by Jose's external verification at `leap.liquid.ai`; the SDK does not validate the string at compile time.

The progress handler signature is `(Double, Int64) -> Void` — progress in `[0.0, 1.0]` and download speed (presumably bytes/second). Both parameters carry only positional positions in the `.swiftinterface`; the actual parameter labels in the closure signature are `progress` and `speed` (visible inside the closure type).

## (e) `Conversation.createConversation(systemPrompt:)` verification

**Both forms exist.** The Step 0 collision is resolved as follows:

1. **Factory method on the `ModelRunner` protocol** (line 520):
   ```
   public protocol ModelRunner {
     func createConversation(systemPrompt: Swift.String?) -> LeapSDK.Conversation
     ...
   }
   ```
   The default-implementation is also on `LiquidInferenceEngineRunner` (the concrete class, line 49) with the same signature. Returns a fresh `Conversation`.

2. **Direct `Conversation` initializer** (line 424):
   ```
   public init(modelRunner: any LeapSDK.ModelRunner, history: [LeapSDK.ChatMessage])
   ```
   Takes a `ModelRunner` plus initial history. The Quick Start README snippet uses this; the docs prefer the factory.

**Recommendation**: use the factory method `runner.createConversation(systemPrompt: "Translate to Japanese.")` per the locked direction. The factory is cleaner: no need to construct an empty history array, and the model card explicitly requires the system prompt to be set for translation to work. Both forms ultimately produce the same class, so this is style not capability.

Additionally observed: `ModelRunner` also exposes `createConversationFromHistory(history:)` (no system prompt), and `Conversation` exposes a `registerFunction(_:)` method. Neither is relevant to LFM2 translation use.

## Collisions with locked decisions

### D4 (Cache strategy: in-memory only, no persistent disk cache) — **COLLISION CONFIRMED**

The lock-text said:

> Cache strategy: `LiquidCacheOptions` in-memory only. No persistent disk cache. Reasoning: LFM2 prompt cache is KV-state inference acceleration not translation memory; cross-meeting hit rate near zero; persistent cache in Documents folder backs up to iCloud (privacy conflict).

What the SDK actually provides:

> `LiquidCacheOptions(path: String, maxEntries: Int)` — both required, both non-optional. No in-memory variant.

The three possible postures, with implications:

| Posture | How | Honors privacy (no iCloud) | Honors "in-memory only" | KV-cache acceleration kept |
| --- | --- | --- | --- | --- |
| A. `cacheOptions: nil` | Pass nil to the options init | yes | yes (trivially, no cache at all) | **NO — cache fully off** |
| B. `cacheOptions: LiquidCacheOptions(path: Caches/, maxEntries: N)` | Use `URLs.cachesDirectory` (not Documents) | yes (`Library/Caches` is not iCloud-backed) | NO — cache is on disk | yes |
| C. `cacheOptions: LiquidCacheOptions(path: tmp/, maxEntries: N)` | Use `NSTemporaryDirectory()` | yes (purged by system, not iCloud-backed) | partial — disk-backed but ephemeral across launches | yes |

**The strict "in-memory only" letter of D4 is unachievable in v0.9.4.** The reasoning underlying D4 (privacy + cross-meeting hit-rate-near-zero) can be honored *either* by Posture A (drop KV-cache acceleration entirely) *or* by Posture B/C (relocate cache off the iCloud-backed Documents folder). Posture B is what Apple recommends for "non-essential cached data that can be regenerated"; Posture C is what's used for genuinely throwaway state.

**Recommendation**: this is a **strategic re-walk trigger per the dispatch brief's STOP conditions**. The locked reasoning was sound but assumed an API shape that does not exist. Two viable replacements (B vs. C vs. A) each have different perf/privacy trade-offs and need the human gate. **Surfacing to Jose for Claude.ai strategic re-walk before Group C begins.**

Note that this is a Group **C** planning input, not a Group B blocker. Group B's remaining work (Steps 3–7: `LFM2ModelLoader`, AppBootstrapper extension, error view, tests) does not need `LiquidCacheOptions` configured — model loading via `Leap.load(model:quantization:)` accepts `options: nil` for the manifest options, and the cache decision can be threaded through later. **Group B itself can proceed once the dispatch resumes**; the cache-strategy revisit is queued for the Group C boundary.

### D1 (GGUF path via `Leap.load(model:quantization:)`) — **NO COLLISION**

Confirmed exactly as locked. Overload #3 (`load(model:quantization:options:downloadProgressHandler:)`) is present, async, returns `any ModelRunner`. The `quantization: String` parameter accepts the verified `"Q5_K_M"` slug as a plain string. `LiquidInferenceEngineManifestOptions?` is optional with `nil` default — Group B can pass `nil` initially and decide cache config in Group C.

### D2 (`LFM2ModelLoader` owns `ModelRunner`; passes to `TranslationActor.init` with `nonisolated(unsafe)`) — **PARTIAL COLLISION**

D2's text said `nonisolated(unsafe)` would be the mitigation "if not Sendable." Inspection confirms `ModelRunner` is not Sendable, so `nonisolated(unsafe)` *would* work as stated. However, the doc-researcher pre-flight's Category 4 recommendation suggested *not* passing the `ModelRunner` across actor boundaries at all, but instead obtaining the `Conversation` inside the `TranslationActor`'s isolation. That recommendation is structurally compatible with what the `.swiftinterface` shows (the runner exposes a sync `createConversation(systemPrompt:)` that produces a non-Sendable `Conversation` — putting both inside one actor's isolation is the cleanest fit).

This is not a hard collision — D2 as written still works. But the cleaner alternative is better. **Surfacing the three pattern options in section (b) to the Group C planner.** Not a Group B blocker.

### D3 (Sequential warmup pattern), D5 (doc-researcher pre-flight), D6 (group breakdown) — **NO COLLISION**

No findings affect these decisions.

## Gaps

1. **Quantization-slug exact-match acceptance is runtime-only.** The SDK takes `quantization: String` without compile-time validation. Jose's external verification at `leap.liquid.ai` is the source of truth for `Q5_K_M`. Empirically confirmable at Group B Step 3 once `LFM2ModelLoader` makes a real `Leap.load(...)` call against the model registry.

2. **AsyncThrowingStream delivery thread is still unspecified.** The interface declares `generateResponse(message:generationOptions:) -> AsyncThrowingStream<MessageResponse, Error>` on `Conversation` but does not specify which actor/thread the stream iterations execute on. The docs say callbacks run on main; for `AsyncThrowingStream`, this is still empirically unknown. Resolution path: empirical test inside Group C when `TranslationActor` exercises the stream, or open a GitHub issue at `Liquid4All/leap-ios`. Not a Group B blocker.

3. **No SDK-provided warmup primitive.** Confirmed by absence — no `prewarm()`, `warmup()`, or `preload()` is exposed on `ModelRunner` or `Leap`. The dummy-inference pattern remains the only path. Group B Step 6 (`LFM2ModelLoader.warmup()`) will issue a short "Hello." → "こんにちは。" inference; D3's locked warmup pattern stands.

4. **`LiquidGenerationStats` vs. `GenerationStats` duality.** Two stats types exist (`GenerationStats` line 487, `LiquidGenerationStats` line 688) with overlapping fields. Not material to Group B but worth noting for any later perf-instrumentation work.

5. **`LiquidInferenceEngineRunner.getLatestStats()` returns `LiquidGenerationStats?`** — available for post-translation observability. Not used by Group B; potential future-phase signal source.

6. **Effective Swift version: 5.10.** The framework was built with `-swift-version 5` and `effective-5.10`. Our app target is Swift 6 with strict concurrency. The framework's Sendable annotations (or absence) are authoritative as imported — `ModelRunner` will read as a non-Sendable existential in our Swift 6 module. No `@preconcurrency import` needed unless a future warning surfaces; document the assumption.

## Summary for the dispatch return

- `cacheOptions` on `LiquidInferenceEngineManifestOptions`: **YES** (field present, type `LiquidCacheOptions?`).
- `ModelRunner` Sendable: **NO** (plain protocol, no Sendable inheritance).
- `Conversation` Sendable: **NO** (plain class).
- `LiquidCacheOptions` cases visible: **not an enum** — single struct with two non-optional fields (`path: String`, `maxEntries: Int`). No in-memory mode.
- `Leap.load(...)` GGUF overload signature confirmed: **YES** — `load(model:quantization:options:downloadProgressHandler:) async throws -> any ModelRunner`.
- `createConversation(systemPrompt:)` exists: **YES, both forms** — factory on `ModelRunner` and direct `Conversation` initializer.

**D1 collision**: no.
**D2 collision**: partial — D2 as written still works; cleaner alternatives exist for Group C planning.
**D4 collision**: yes — surface to Jose for Claude.ai strategic re-walk before Group C.

**STOP at end of Step 2 per dispatch brief. Do not proceed to Step 3.**
