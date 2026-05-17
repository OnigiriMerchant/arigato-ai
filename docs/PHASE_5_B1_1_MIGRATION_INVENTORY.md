# PHASE 5 B1.1 — LEAP SDK Migration Inventory

**Date:** 2026-05-18
**SDK migration:** v0.9.4 (Liquid4All/leap-ios) → v0.10.6 (Liquid4All/leap-sdk)
**Trigger:** Captured during B1.1 sprint post-doc-researcher-discipline-fix at commit `6361a4e`. Previous skill reconcile (commit `1f56009`) inspected the archived `Liquid4All/leap-ios` repo and concluded "v0.9.4 is latest" — incorrect. Actual current SDK is `Liquid4All/leap-sdk` v0.10.6 with substantially different APIs. This inventory is the remediation deliverable.

---

## 1. Call-Site Inventory Table

### Legend
- **PURE-RENAME:** Symbol name changed; call shape is identical.
- **SIGNATURE-CHANGE:** Parameter names, types, or associated value shapes changed; requires code edit beyond a rename.
- **BEHAVIORAL-CHANGE:** Runtime behavior changed even if the call site compiles.

| # | File | Line(s) | Current v0.9.4 API Usage | v0.10.6 Equivalent | Migration Risk | Notes |
|---|------|---------|--------------------------|--------------------|----------------|-------|
| 1 | `ArigatoAI/Translation/LFM2ModelLoader.swift` | 9 | `import LeapSDK` | `import LeapModelDownloader` | PURE-RENAME | v0.10.6 dual-import guard: cannot link both LeapSDK and LeapModelDownloader. Use only `import LeapModelDownloader`; it re-exports all LeapSDK types. |
| 2 | `ArigatoAI/Translation/LFM2ModelLoader.swift` | 156 | `private let modelRunner: any ModelRunner` | unchanged — `ModelRunner` is still the protocol name | PURE-RENAME | Protocol name unchanged. Verify at compile time whether `Sendable` conformance was added (would allow removing `@unchecked Sendable`). |
| 3 | `ArigatoAI/Translation/LFM2ModelLoader.swift` | 161 | `init(modelRunner: any ModelRunner)` | unchanged | PURE-RENAME | Constructor parameter type name unchanged. |
| 4 | `ArigatoAI/Translation/LFM2ModelLoader.swift` | 169 | `modelRunner.createConversation(systemPrompt: direction.systemPrompt)` | unchanged | PURE-RENAME | Method signature unchanged per v0.10.6 docs. |
| 5 | `ArigatoAI/Translation/LFM2ModelLoader.swift` | 177 | `ChatMessage(role: .user, content: [.text(canaryText)])` | unchanged (`ChatMessage` + `.text()` factory unchanged) | PURE-RENAME | `ChatMessageContent.text(...)` static factory confirmed in v0.10.6 docs. |
| 6 | `ArigatoAI/Translation/LFM2ModelLoader.swift` | 178 | `conversation.generateResponse(message: message, generationOptions: nil)` | unchanged | PURE-RENAME | Both overloads (`message:` and `userTextMessage:`) present in v0.10.6. |
| 7 | `ArigatoAI/Translation/LFM2ModelLoader.swift` | 182 | `if case .complete = response { return }` | requires `onEnum(of:)` or bare case match — **behavior TBD** | BEHAVIORAL-CHANGE | In v0.10.6, `MessageResponse` is a SKIE-bridged Kotlin sealed class. `onEnum(of:)` is the recommended exhaustive switch. Bare `if case .complete` may still compile via Swift bridging; must verify at compile time. |
| 8 | `ArigatoAI/Translation/LFM2ModelLoader.swift` | 212 | `modelRunner.createConversation(systemPrompt: direction.systemPrompt)` | unchanged | PURE-RENAME | Same as #4. |
| 9 | `ArigatoAI/Translation/LFM2ModelLoader.swift` | 214-219 | `GenerationOptions(temperature: Float(...), topP: Float(...), minP: Float(...), repetitionPenalty: Float(...))` | Same field names exist in v0.10.6 — `temperature: Float?`, `topP: Float?`, `minP: Float?`, `repetitionPenalty: Float?` | PURE-RENAME | Field names unchanged. Note: `maxOutputTokens` (v0.9.4 `UInt32?`) is not used in this call; `maxTokens: Int32?` is the v0.10.6 equivalent if added. See note for #10. |
| 10 | `.claude/skills/leap-sdk/SKILL.md` (prior reconcile) | doc-comment | `maxOutputTokens: UInt32?` (v0.9.4 field name) | `maxTokens: Int32?` (v0.10.6) | SIGNATURE-CHANGE | This field is NOT currently used in production code (the `GenerationOptions` call at line 214-219 omits it). However: (a) the old SKILL.md named it incorrectly; (b) if it is added in the future, callers must use `maxTokens: Int32?`. |
| 11 | `ArigatoAI/Translation/LFM2ModelLoader.swift` | 221-224 | `conversation.generateResponse(userTextMessage: userText, generationOptions: options)` | unchanged (overload confirmed in v0.10.6 docs) | PURE-RENAME | `userTextMessage:` overload present in v0.10.6. |
| 12 | `ArigatoAI/Translation/LFM2ModelLoader.swift` | 233-241 | `switch response { case let .chunk(text): ... case .complete: ... default: continue }` | `switch onEnum(of: response) { case .chunk(let c): use(c.text); case .complete: ...; case .reasoningChunk, .functionCalls, .audioSample: continue }` | SIGNATURE-CHANGE | In v0.10.6 `.chunk` carries `MessageResponse.Chunk` (struct), not a bare `String`. `case let .chunk(text)` binding `text` as a `String` will break — must use `c.text`. Also: v0.9.4 comment names case `.functionCall`; v0.10.6 uses `.functionCalls` (plural). |
| 13 | `ArigatoAI/Translation/LFM2ModelLoader.swift` | 228-229 | `// Case names verified against arm64-apple-ios-simulator.swiftinterface ... cases .chunk, .reasoningChunk, .audioSample, .complete, .functionCall` (doc-comment) | v0.10.6 case names: `.chunk`, `.reasoningChunk`, `.functionCalls`, `.audioSample`, `.complete` | SIGNATURE-CHANGE (doc-comment) | `.functionCall` → `.functionCalls` (plural). Doc-comment must be updated. |
| 14 | `ArigatoAI/Translation/LFM2ModelLoader.swift` | 290-298 (doc-comment) | `LeapSDK.Leap/load(model:quantization:options:downloadProgressHandler:)` | `LeapDownloader.loadSimpleModel(model:options:...)` | SIGNATURE-CHANGE (doc-comment + production code) | The factory `LFM2ClientFactory.make` at line 323-341 uses `Leap.load(...)` — full SIGNATURE-CHANGE, see #17. Doc-comments referencing this symbol on lines 290-341 need updating. |
| 15 | `ArigatoAI/Translation/LFM2ModelLoader.swift` | 314 (doc-comment) | `LeapSDK.LiquidCacheOptions` with `path: String` and `maxEntries: Int` | `LiquidCacheOptions.enabled(path: String)` static factory | SIGNATURE-CHANGE (doc-comment + production code) | See #18 and #19. |
| 16 | `ArigatoAI/Translation/LFM2ModelLoader.swift` | 319 (doc-comment) | `LeapSDK.Leap/load(model:quantization:options:downloadProgressHandler:)` | `ModelDownloader.loadSimpleModel(model:options:...)` | SIGNATURE-CHANGE (doc-comment) | See #14 and #17. |
| 17 | `ArigatoAI/Translation/LFM2ModelLoader.swift` | 332-339 | `let runner = try await Leap.load(model: "lfm2-350m-enjp-mt", quantization: quantization, options: manifestOptions, downloadProgressHandler: { progress, _ in progressHandler?(progress) })` | `let runner = try await downloader.loadSimpleModel(model: ModelSource(modelPath: ggufURL.path, modelName: "lfm2-350m-enjp-mt", quantizationId: quantization), options: manifestOptions)` | SIGNATURE-CHANGE | Free function `Leap.load(...)` replaced by `[ModelDownloader/LeapDownloader].loadSimpleModel(model:options:)`. `ModelSource` is a new struct. Progress handler moves to `downloadProgress:` parameter. `model:` label → `modelName:` in `ModelSource`. `quantization:` → `quantizationId:` in `ModelSource`. |
| 18 | `ArigatoAI/Translation/LFM2ModelLoader.swift` | 325-326 | `LiquidCacheOptions(path: cachePath, maxEntries: cacheMaxEntries)` | `LiquidCacheOptions.enabled(path: cachePath)` | SIGNATURE-CHANGE | `init(path:maxEntries:)` not in v0.10.6 public docs. `maxEntries` field removed from public API. Use `.enabled(path:)` static factory (added v0.10.4.3). |
| 19 | `ArigatoAI/Translation/LFM2ModelLoader.swift` | 327-329 | `LiquidInferenceEngineManifestOptions(cacheOptions: cacheOptions)` | unchanged (field name `cacheOptions` confirmed in v0.10.6 docs) | PURE-RENAME | Initializer label `cacheOptions:` unchanged. Shape of `LiquidInferenceEngineManifestOptions` confirmed in v0.10.6 docs. |
| 20 | `ArigatoAI/Translation/LFM2ModelLoader.swift` | 313 | `public static let cacheMaxEntries: Int = 1000` | Remove or repurpose — `maxEntries` parameter no longer in public `LiquidCacheOptions` API | BEHAVIORAL-CHANGE | The constant is currently passed to `LiquidCacheOptions(path:maxEntries:)`. In v0.10.6 the SDK manages LRU eviction internally (`use_mmap=true` default since v0.10.4). Remove constant and the call site. |
| 21 | `ArigatoAI/Translation/LFM2ModelLoader.swift` | 144 (type ref in comment and code) | `any ModelRunner` (protocol) as a type annotation | unchanged | PURE-RENAME | Protocol name `ModelRunner` unchanged in v0.10.6. |
| 22 | `ArigatoAI/Translation/LFM2ModelLoader.swift` | 355 (doc-comment) | `"LEAP iOS SDK v0.9.4"` (version reference in `@unchecked Sendable` rationale doc-comment at line ~145-155) | Update to v0.10.6; verify `Sendable` status | BEHAVIORAL-CHANGE (doc-comment) | Version reference in `@unchecked Sendable` rationale must update. Sendable status of `ModelRunner` in v0.10.6 is not confirmed as changed by docs (neither added nor removed). |
| 23 | `ArigatoAI/Translation/LFM2CachePathResolver.swift` | 13 (doc-comment) | `LiquidCacheOptions(path:maxEntries:)` mentioned in doc-comment | `LiquidCacheOptions.enabled(path:)` | SIGNATURE-CHANGE (doc-comment) | Line 13: "passed to `LiquidCacheOptions(path:maxEntries:)`" — must update. |
| 24 | `ArigatoAI/Translation/LFM2CachePathResolver.swift` | 38 (doc-comment) | `LiquidCacheOptions(path:)` mention | `LiquidCacheOptions.enabled(path:)` | SIGNATURE-CHANGE (doc-comment) | Line 38: "suitable for `LiquidCacheOptions(path:)`" — must update. |
| 25 | `ArigatoAI/Translation/TranslationEngineEvent.swift` | 17 (doc-comment) | `` `LeapSDK.MessageResponse` `` (doc-comment reference) | `MessageResponse` (unchanged type name; `import LeapModelDownloader`) | PURE-RENAME | Type name unchanged, but module reference in doc-comment should drop `LeapSDK.` prefix. |
| 26 | `ArigatoAI/Translation/TranslationEngineEvent.swift` | 18 (doc-comment) | `LeapSDK.Conversation.generateResponse(userTextMessage:...)`  | unchanged method name; `import LeapModelDownloader` | PURE-RENAME | Method name unchanged. |
| 27 | `ArigatoAI/Translation/TranslationEngineEvent.swift` | 22 (doc-comment) | "function-call payloads, telemetry stats" (informal description of dropped MessageResponse cases) | v0.10.6 dropped cases: `.reasoningChunk`, `.functionCalls`, `.audioSample` | PURE-RENAME (doc-comment) | Description is accurate directionally. Update case names for precision. |
| 28 | `ArigatoAI/Translation/TranslationActor.swift` | 374 (doc-comment) | "**LEAP SDK cancellation semantics** (doc-researcher findings, 2026-05-16): ... cooperative ... one extra token" | v0.10.6 docs confirm same behavior: "at most one extra token of slack after cancel()" | BEHAVIORAL-CHANGE (verified-no-change) | Cancellation behavior confirmed identical in v0.10.6. Doc-comment is accurate. No code change needed, but update the "2026-05-16" citation to reference v0.10.6 docs URL. |
| 29 | `ArigatoAI/Translation/TranslationActor.swift` | 574 (code comment) | `// LEAP SDK structural inference: cancellation may surface as a normal stream finish in some SDK versions, since GenerationFinishReason has no .cancelled case` | v0.10.6 docs do not document `GenerationFinishReason` — UNVERIFIABLE whether case set changed | BEHAVIORAL-CHANGE | `GenerationFinishReason` (referenced in inline comment) not documented in v0.10.6 public docs. Mark UNVERIFIABLE per Rule 1. Behavior assumption ("cancellation may arrive as normal finish") needs compile-time verification against v0.10.6. |
| 30 | `ArigatoAI/Translation/TranslationActor.swift` | 578-579 (code comment) | "**V3 #51 (cancellation-bridging three-mechanism gotcha)** does NOT apply here. The `AsyncThrowingStream` variant ... returns no `GenerationHandler`" | v0.10.6 docs do not document `GenerationHandler` separately. Confirmed: `generateResponse(...)` returns `AsyncThrowingStream`. No `GenerationHandler` in v0.10.6 public API docs. | BEHAVIORAL-CHANGE (verified-no-change) | V3 #51 reasoning still valid. `GenerationHandler` not surfaced in v0.10.6 docs. |
| 31 | `ArigatoAI/AppBootstrapper.swift` | No direct LEAP SDK imports or calls | No LEAP SDK call sites in AppBootstrapper | N/A | N/A | `AppBootstrapper` uses `LFM2ModelLoader` and `LFM2Engine` (our seam types), not LEAP SDK types directly. No migration needed in this file beyond any seam-API changes. |
| 32 | `Package.resolved` | All | `"location": "https://github.com/Liquid4All/leap-ios"`, `"version": "0.9.4"`, `"identity": "leap-ios"` | `"location": "https://github.com/Liquid4All/leap-sdk.git"`, `"version": "0.10.6"`, `"identity": "leap-sdk"` | PURE-RENAME | Package.resolved regenerates automatically from Package.swift; the identity will change from `leap-ios` to `leap-sdk`. |
| 33 | `ArigatoAITests/Translation/LFM2ModelLoaderTests.swift` | No direct LEAP SDK imports or calls | Test file uses `LFM2Engine`, `LFM2ModelLoader` (our seam) — no direct LEAP SDK symbols | N/A | N/A | Tests use seam types only; no migration needed provided seam API is stable. |
| 34 | `ArigatoAITests/Translation/TranslationActorTests.swift` | No direct LEAP SDK imports or calls | Test file uses `LFM2Engine`, `TranslationActor`, `TranslationEngineEvent` (our seam types) | N/A | N/A | No LEAP SDK symbols referenced directly in test code. |

**Note on LFM2-350M-ENJP-MT model availability:** The LEAP Model Library at https://leap.liquid.ai/models is a dynamically-rendered SPA and the model list could not be extracted by the research tool. Whether `LFM2-350M-ENJP-MT` appears in the portal catalog is UNVERIFIABLE from this research pass. However, the sideloaded GGUF path (`LeapDownloader.loadSimpleModel`) does not require portal catalog availability — the model file is provided by the app, not downloaded via the SDK's manifest system. Our sideloaded path is unaffected by portal catalog status. The HuggingFace distribution (`LiquidAI/LFM2-350M-ENJP-MT-GGUF`) is the source of the GGUF file; that source is out of scope for this inventory.

---

## 2. Behavioral Diff Section

### B1 — `LiquidCacheOptions` shape (HIGH RISK — code change required)

**v0.9.4 behavior:** `LiquidCacheOptions` is a struct with a memberwise initializer `LiquidCacheOptions(path: String, maxEntries: Int)`. Both fields required. Our code at `LFM2ClientFactory.make` constructs `LiquidCacheOptions(path: cachePath, maxEntries: 1000)`.

**v0.10.6 behavior:** `LiquidCacheOptions` exposes a static factory `LiquidCacheOptions.enabled(path: String)`. The `maxEntries` field is not in the v0.10.6 public API. v0.10.4+ uses a "Bounded-LRU CacheOptions API" with internal eviction policy. The `init(path:maxEntries:)` memberwise initializer is not documented in v0.10.6 official docs.

Source: docs.liquid.ai/deployment/on-device/sdk/model-loading (v0.10.6); changelog entry v0.10.4.3: "New `LiquidCacheOptions.enabled(path:)` static factory."

**Affected code:** `LFM2ModelLoader.swift:325-326`, `LFM2ClientFactory.cacheMaxEntries` constant at line 313, doc-comments on lines 290-298 and 314; `LFM2CachePathResolver.swift` doc-comments lines 13 and 38.

**Verification gate:** After migration, the project must compile against `import LeapModelDownloader` with `LiquidCacheOptions.enabled(path:)`. A compilation error confirms the old initializer is gone. A test that exercises `LFM2ClientFactory.make` end-to-end on device would verify the cache directory is created and written to on first translation.

**STOP condition for migration:** If `LiquidCacheOptions(path:maxEntries:)` is still present as a public initializer in the v0.10.6 xcframework (compile-time verification), then this is a PURE-RENAME of the new factory addition, not a breaking removal. Verify by attempting to compile both call shapes.

---

### B2 — `MessageResponse` chunk associated value type (HIGH RISK — code change required)

**v0.9.4 behavior:** `case let .chunk(text)` where `text` was a bare `String`. Our code at `LFM2ModelLoader.swift:233-235` binds it directly: `case let .chunk(text): continuation.yield(.chunk(text))`.

**v0.10.6 behavior:** `MessageResponse.Chunk` is a struct with a `.text: String` field. The correct pattern is `case .chunk(let c): continuation.yield(.chunk(c.text))` or via `switch onEnum(of: response)` then `case .chunk(let c): c.text`.

Source: docs.liquid.ai/deployment/on-device/sdk/conversation-generation — v0.10.6 streaming example uses `case .chunk(let c): print(c.text)`.

**Affected code:** `LFM2ModelLoader.swift:233-235` (production path in `LFM2EngineAdapter.translate`). Also the comment on line 228-229 names `.functionCall` (singular) as a case — v0.10.6 uses `.functionCalls` (plural).

**Verification gate:** Compile `LFM2EngineAdapter.translate()` against v0.10.6 xcframework. If `case let .chunk(text)` fails type-checking with "type of pattern cannot be used to match value of type 'MessageResponse'", the fix is confirmed necessary. A unit test that drives a real `LFM2EngineAdapter` against a short translation sentence and asserts at least one `.chunk(_:)` event arrives in `TranslationEngineEvent` form would verify end-to-end.

**Note on `onEnum(of:)` vs bare `switch`:** The v0.10.6 docs recommend `onEnum(of:)` for exhaustive switching on Kotlin-bridged sealed types. However, using `onEnum(of:)` requires that the function be available from `import LeapModelDownloader`. Verify availability at compile time.

---

### B3 — `Leap.load(...)` free function vs `loadSimpleModel` (HIGH RISK — code change required)

**v0.9.4 behavior:** `Leap.load(model:quantization:options:downloadProgressHandler:)` — a top-level free function that took model string + quantization string + options + a progress closure.

**v0.10.6 behavior:** The new path is `ModelDownloader.loadSimpleModel(model: ModelSource(...), options:, generationTimeParameters:, downloadProgress:)`. The `Leap.load(...)` compatibility shim is noted as present in v0.10.0 ("Swift compatibility layer keeps 0.9.x call sites compiling"), but calling into `Leap.load(...)` requires `import LeapSDK`, and the v0.10.6 dual-import guard prohibits linking both `LeapSDK` and `LeapModelDownloader`. Since we will import `LeapModelDownloader`, `Leap.load(...)` is effectively unavailable. New code must use `ModelDownloader` or `LeapDownloader`.

Source: changelog v0.10.0 ("Swift compatibility layer keeps 0.9.x call sites compiling"); changelog v0.10.6 ("Dual-import build-time guard added; use `OTHER_CFLAGS: LEAP_DUAL_IMPORT_ALLOW=1` to opt out").

**Affected code:** `LFM2ModelLoader.swift:332-339` (`LFM2ClientFactory.make` factory closure).

**Verification gate:** After replacing `Leap.load(...)` with `ModelDownloader.loadSimpleModel(model:options:...)`, the project must compile. A device-run integration test driving the full `startPrewarm` path (Whisper → LFM2 load → warmup → translation) is the behavioral regression gate.

---

### B4 — `import LeapSDK` → `import LeapModelDownloader` dual-import guard (HIGH RISK — build change)

**v0.9.4 behavior:** `import LeapSDK` was the single import path.

**v0.10.6 behavior:** `import LeapModelDownloader` re-exports all `LeapSDK` types. Linking both `LeapSDK` and `LeapModelDownloader` SPM products in the same target produces a build-time preprocessor error (the "dual-import guard" added in v0.10.6). The App target and test target must link `LeapModelDownloader` only (or `LeapSDK` only if no downloader is needed, which is not our case).

Source: changelog v0.10.6 ("Dual-import build-time guard added"); quick-start docs ("Use only `import LeapModelDownloader`").

**Affected code:** `LFM2ModelLoader.swift:9` (`import LeapSDK`). `ArigatoAI.xcodeproj` SPM product dependency must change from `LeapSDK` to `LeapModelDownloader`.

**Verification gate:** Build succeeds with no "duplicate symbols" or dual-import guard preprocessor error.

---

### B5 — `ModelDownloader` class rename in v0.10.6 (MEDIUM RISK — names to resolve)

**v0.9.4 behavior:** Class was `LeapModelDownloader` (in the `LeapModelDownloader` SPM product).

**v0.10.6 behavior:** The class exposed to Swift is now `ModelDownloader` (renamed from `LeapModelDownloader` class — changelog: "Class renamed: `LeapModelDownloader` → `ModelDownloader`"). The SPM *product* is still named `LeapModelDownloader`; the *class* inside it is now `ModelDownloader`.

Note: `LeapDownloader` (a different class) is also available and has the same `loadSimpleModel` method signature. For new code, use `ModelDownloader` (the renamed class from the `LeapModelDownloader` product). For our factory, either `ModelDownloader` or `LeapDownloader` will work; prefer `ModelDownloader` per the maintainer's direction.

**Affected code:** `LFM2ClientFactory.make` (wherever we construct the downloader). Currently `Leap.load(...)` bypasses the downloader construction entirely — after migration, explicit `ModelDownloader(...)` construction is needed.

---

### B6 — `GenerationOptions.maxOutputTokens` → `maxTokens` (MEDIUM RISK — currently unused; future risk)

**v0.9.4 behavior:** `maxOutputTokens: UInt32?` per SKILL.md reconcile at commit `1f56009` (spike `6512662` confirmed field name).

**v0.10.6 behavior:** `maxTokens: Int32?` (different name AND different type: `UInt32` → `Int32`, which is also a range change).

Source: docs.liquid.ai/deployment/on-device/sdk/conversation-generation — `GenerationOptions` struct definition.

**Affected code:** Currently NOT used in production code (the `GenerationOptions` call at `LFM2ModelLoader.swift:214-219` omits the field). The old SKILL.md named this field — update docs only. If it is added in future, the caller must use `maxTokens: Int32?` not `maxOutputTokens: UInt32?`.

---

### B7 — `ModelRunner` and `Conversation` Sendable status (VERIFICATION REQUIRED)

**v0.9.4 behavior:** `ModelRunner` is a non-`Sendable` protocol; `Conversation` is a non-`Sendable` class. Our code uses `@unchecked Sendable` on `LFM2EngineAdapter` with doc-comment rationale at lines 143-155 of `LFM2ModelLoader.swift`.

**v0.10.6 behavior:** The v0.10.6 public API docs state "All API functions are safe to call from the main/UI thread" and "Callbacks run on the main thread unless explicitly noted." This hints at improved thread safety, but explicit `Sendable` conformance on `ModelRunner` or `Conversation` is NOT documented in the v0.10.6 docs pages inspected. The `@unchecked Sendable` pattern remains appropriate as a conservative choice.

**STOP condition:** If compile-time verification against v0.10.6 shows `ModelRunner` or `Conversation` gained `Sendable`, the `@unchecked Sendable` annotation on `LFM2EngineAdapter` becomes unnecessary (not harmful, but misleading). Update the doc-comment if this is confirmed.

---

### B8 — `GenerationFinishReason` case set (UNVERIFIABLE)

**Context:** `TranslationActor.swift:574` contains an inline comment: "LEAP SDK structural inference: cancellation may surface as a normal stream finish in some SDK versions, since `GenerationFinishReason` has no `.cancelled` case."

**v0.10.6 status:** `GenerationFinishReason` is not documented in any of the v0.10.6 docs pages consulted. Its case set in v0.10.6 is UNVERIFIABLE per Rule 1 from the allowed source set. The behavioral assumption (cancellation may arrive as normal stream finish) remains a compile-time/runtime unknown.

**Verification gate:** After migration, confirm compile-time whether `GenerationFinishReason` is accessible and what cases it exposes.

---

## 3. Recommended Migration Plan

### Step M-1: SDK bump (ONE commit — `Package.swift` only)

**Action:**
1. In `ArigatoAI.xcodeproj`, remove the `Liquid4All/leap-ios` SPM dependency.
2. Add `https://github.com/Liquid4All/leap-sdk.git` at version `0.10.6`.
3. Change the linked SPM *product* from `LeapSDK` to `LeapModelDownloader` (in the App target's framework/library list).
4. `Package.resolved` regenerates automatically.

**Verification:** Project builds even before any Swift changes (expect compile errors in `LFM2ModelLoader.swift` from the API changes — that's expected).

---

### Step M-2: Import change (PURE-RENAME)

**Scope:** `ArigatoAI/Translation/LFM2ModelLoader.swift` line 9 only.

**Action:** `import LeapSDK` → `import LeapModelDownloader`

**Verification:** Build; confirm no dual-import guard error.

---

### Step M-3: `LiquidCacheOptions` construction (SIGNATURE-CHANGE)

**Scope:** `ArigatoAI/Translation/LFM2ModelLoader.swift` lines 313, 325-326; `ArigatoAI/Translation/LFM2CachePathResolver.swift` doc-comments lines 13, 38.

**Actions:**
1. Remove `public static let cacheMaxEntries: Int = 1000`.
2. Replace `LiquidCacheOptions(path: cachePath, maxEntries: cacheMaxEntries)` with `LiquidCacheOptions.enabled(path: cachePath)`.
3. Update doc-comments in `LFM2CachePathResolver.swift` lines 13 and 38 to reference `.enabled(path:)`.
4. Update `LFM2ClientFactory` doc-comment to reference `.enabled(path:)` and remove `maxEntries` discussion.

**STOP condition:** If `LiquidCacheOptions(path:maxEntries:)` compiles successfully against v0.10.6, then this is an optional modernization not a breaking change. Verify before assuming it fails.

**Verification:** Build clean. Existing tests pass (seam tests don't exercise the factory directly; the cache path resolver has its own unit tests that don't touch `LiquidCacheOptions`).

---

### Step M-4: `Leap.load(...)` → `LeapDownloader.loadSimpleModel(...)` (SIGNATURE-CHANGE)

**Scope:** `ArigatoAI/Translation/LFM2ModelLoader.swift` `LFM2ClientFactory.make` closure, lines 323-341.

**Action:** Replace:
```swift
let runner = try await Leap.load(
    model: "lfm2-350m-enjp-mt",
    quantization: quantization,
    options: manifestOptions,
    downloadProgressHandler: { progress, _ in progressHandler?(progress) }
)
```
with:
```swift
let downloader = LeapDownloader(
    config: LeapDownloaderConfig(saveDir: /* appropriate dir */)
)
let runner = try await downloader.loadSimpleModel(
    model: ModelSource(
        modelPath: /* gguf bundle path */,
        modelName: "lfm2-350m-enjp-mt",
        quantizationId: quantization
    ),
    options: manifestOptions,
    downloadProgress: { fraction, _ in progressHandler?(fraction) }
)
```

**ARCHITECTURAL DECISION NEEDED:** `Leap.load(model:quantization:...)` with just a model name string assumed the SDK would locate the GGUF file from its own download cache. `loadSimpleModel(model:ModelSource(...))` requires an explicit `modelPath: String` (the local filesystem path to the GGUF file). This changes the loading strategy: either the GGUF is bundled in the app, or a separate download step must locate/download it first. **This decision must be surfaced to the user before implementation** — it touches the Phase 5 Decision 1 scope.

---

### Step M-5: `MessageResponse` chunk pattern match (SIGNATURE-CHANGE)

**Scope:** `ArigatoAI/Translation/LFM2ModelLoader.swift` lines 180-188 (warmup stream), 225-244 (translate stream).

**Actions:**
1. In `warmupCanary`: `if case .complete = response` — verify this compiles; if not, switch to `switch onEnum(of: response) { case .complete: return; default: break }`.
2. In `translate`: Replace `switch response { case let .chunk(text): continuation.yield(.chunk(text)) ...}` with:
   ```swift
   switch onEnum(of: response) {
   case .chunk(let c):
       continuation.yield(.chunk(c.text))
   case .complete:
       continuation.yield(.complete)
   case .reasoningChunk, .functionCalls, .audioSample:
       continue
   }
   ```
3. Update inline comment at line 228-229 to name `.functionCalls` (plural).

**Verification:** Build clean. Run `LFM2ModelLoaderTests` and `TranslationActorTests`. Both suites exercise the seam (`LFM2Engine` protocol); the warmup path exercises `warmupCanary` which drives the real stream if a real engine is injected.

---

### Step M-6: `maxOutputTokens` → `maxTokens` (SIGNATURE-CHANGE — doc/code update only)

**Scope:** Old SKILL.md (Part A of this deliverable already reflects v0.10.6). No production code uses this field currently.

**Action:** Update `TranslationDirection.swift` doc-comment for `TranslationGenerationParameters` (lines 82-130) to note that if `maxTokens` is added to `GenerationOptions` calls, use `maxTokens: Int32?` not `maxOutputTokens: UInt32?`.

---

### Step M-7: Behavioral regression check pass

After M-1 through M-6:
1. Build the full app target: `mcp__xcodebuildmcp__build_sim_name_proj`.
2. Run all tests: `mcp__xcodebuildmcp__test_sim_name_proj`.
   - `LFM2ModelLoaderTests` — verifies loader lifecycle (seam, not SDK-dependent).
   - `TranslationActorTests` — verifies actor scheduling / cancellation / FIFO / violation tests (seam, not SDK-dependent).
3. On-device integration check: boot real device, run app, confirm warmup reaches `LFM2LoaderState.ready`, perform one JA→EN translation, confirm output is non-empty.
4. Verify no dual-import guard build error.
5. Verify cancellation (`C-T-VIOLATION-CANCEL-MID-GENERATION` test) still passes — this is the LEAP SDK cooperative cancellation contract test.

---

## 4. Footer — Sources Consulted

All URLs consulted during this research, with what they verified:

| URL | Claim verified |
|-----|----------------|
| https://docs.liquid.ai/deployment/on-device/leap-sdk-changelog | Full changelog v0.9.x → v0.10.6; all breaking changes, API additions, behavioral changes |
| https://docs.liquid.ai/deployment/on-device/sdk/quick-start | Package URL, min iOS 17.0, SPM product list (5 products), loadSimpleModel Swift example, import statement |
| https://docs.liquid.ai/deployment/on-device/sdk/model-loading | Full model loading API signatures: ModelDownloader, LeapDownloader, loadSimpleModel, loadModel, ModelSource, LiquidInferenceEngineManifestOptions, LiquidCacheOptions.enabled(path:), LiquidInferenceEngineOptions builder |
| https://docs.liquid.ai/deployment/on-device/sdk/conversation-generation | GenerationOptions field names and types (confirmed maxTokens:Int32?, not maxOutputTokens:UInt32?), MessageResponse cases and payload types, createConversation, generateResponse overloads, GenerationStats fields, cancellation behavior |
| https://github.com/Liquid4All/leap-sdk/releases/tag/v0.10.6 | v0.10.6 is "Release v0.10.6 Latest"; breaking changes (class rename LeapModelDownloader→ModelDownloader, dual-import guard, dynamic xcframework); confirmed latest version |
| https://raw.githubusercontent.com/Liquid4All/leap-sdk/refs/tags/v0.10.6/Package.swift | Swift tools version 6.0; platform minimums iOS 17, macOS 15; product names: LeapSDK, LeapModelDownloader, LeapOpenAIClient, LeapUI, LeapSDKMacros; all targets |
| https://github.com/Liquid4All/leap-sdk/tree/v0.10.6 | Repository exists; written in Swift 100%; 17 releases; v0.10.6 is latest tag |
| https://leap.liquid.ai/models | UNVERIFIABLE — dynamically rendered SPA; model list not extractable |
