# B1.1 LFM2 Download Fix — Pre-flight findings

**Date**: 2026-05-17
**SDK pin**: v0.9.4 (commit `72afe9bf4c2fae086fbced3b05995edaad2c6bf2`)
**Trigger**: pre-flight for B1.1 per `docs/PRE_MVP1_REVIEW.md`
**Status**: research-only; gates the B1.1 implementation approach decision

---

## Summary table

| Path | Status | Evidence |
|---|---|---|
| (a) `Leap.load` local-URL overload in v0.9.4 | DEPRECATED-BUT-CALLABLE — BUT targets ExecuTorch bundle format, NOT GGUF; not viable for LFM2 GGUF local loading | `LeapSDK.swiftinterface` lines 267–269; `LiquidInferenceEngineOptions` struct lines 629–643 |
| (a2) `Leap.load(manifestURL:)` with local `file://` manifest JSON | VIABLE-UNVERIFIED-AT-RUNTIME — overload takes `Foundation.URL`; accepting `file://` URL to locally-constructed manifest JSON is architecturally plausible but not explicitly documented | `LeapSDK.swiftinterface` lines 261–264; `ModelManifest` struct in `LeapModelDownloader` interface |
| (b) `LeapModelDownloader` HF-direct download + local file result | EXISTS — `HuggingFaceDownloadableModel` + `ModelDownloader.downloadModel(_:DownloadableModel)` returns `Result<URL, Error>` of local path; `queryStatus` confirms `.downloaded`; `getModelFile` returns expected local path pre-download | `LeapModelDownloader.swiftinterface` lines 14–212 |
| (b2) `LeapModelDownloader` local-path loader (bypass portal, load directly) | DOES NOT EXIST as a single-call API — no `loadModel(localURL:)` method; downloaded file must be routed back to `Leap.load` or `LiquidInferenceEngineRunner` | `LeapModelDownloader.swiftinterface` exhaustive inspection |
| (c) Lower-level `ModelRunner` construction from local GGUF in v0.9.4 | EXISTS via deprecated `LiquidInferenceEngineRunner.init(path:options:)` — but `path` parameter is ExecuTorch bundle path, NOT GGUF; the manifest-URL path on `LiquidInferenceEngineRunner.init(manifestURL:)` is the same GGUF path as `Leap.load(manifestURL:)` and requires a manifest JSON (remote or local `file://`) | `LeapSDK.swiftinterface` lines 33–61 |
| (d) SDK bump to v0.10.x with HF-direct API | DOES NOT EXIST — v0.9.4 IS the latest release tag as of 2026-05-17; no v0.10.x published | `github.com/Liquid4All/leap-ios/releases` — full releases listing shows v0.9.4 as most recent |
| (e) HF direct download via `URLSession` | CDN URL: `https://huggingface.co/LiquidAI/LFM2-350M-ENJP-MT-GGUF/resolve/main/LFM2-350M-ENJP-MT-Q5_K_M.gguf?download=true`; redirects to Xet CAS presigned URL (time-limited, 1h TTL); auth: none; size Q5_K_M: **260 MB** (confirmed from HF file listing); integrity: SHA256 (confirmed via `ModelDownloadError.sha256Mismatch` case in SDK + Xet docs) | HF file listing (`huggingface.co/LiquidAI/LFM2-350M-ENJP-MT-GGUF/tree/main`); redirect target observed via WebFetch; `LeapModelDownloader` interface |

---

## Q1 — Local-URL overload of `Leap.load()` in v0.9.4

The v0.9.4 `.swiftinterface` (path: `~/Library/Developer/Xcode/DerivedData/ArigatoAI-cqfyrsgbtxsvntgobayhpahfospt/SourcePackages/artifacts/leap-ios/LeapSDK/LeapSDK.xcframework/ios-arm64_x86_64-simulator/LeapSDK.framework/Modules/LeapSDK.swiftmodule/arm64-apple-ios-simulator.swiftinterface`) contains four `Leap.load` overloads at lines 258–270.

Overload #4 (the deprecated local-URL one) at lines 267–269:
```
@available(*, deprecated, message: "Use load(options:) instead")
public static func load(url: Foundation.URL, options: LeapSDK.LiquidInferenceEngineOptions? = nil) throws -> any LeapSDK.ModelRunner
```

**Deprecation status**: Soft — marked `@available(*, deprecated)`. The function body is present (it is a binary xcframework, not source). It compiles with a warning, not an error, so it is callable in our Swift 6 app target.

**Critical limitation — ExecuTorch-only**: The `options` parameter type is `LiquidInferenceEngineOptions`, whose struct (lines 629–643) has:
- `bundlePath: Swift.String` (required, first parameter)
- All other fields (`cacheOptions`, `cpuThreads`, etc.) optional

This `options` struct is the ExecuTorch bundle loading path. The `url` parameter is the ExecuTorch `.bundle` file URL. This overload does NOT accept a GGUF file URL.

**Conclusion for Q1**: The deprecated `Leap.load(url:)` exists and is callable, but it targets ExecuTorch `.bundle` format, not GGUF. **It is NOT a viable path for loading `LFM2-350M-ENJP-MT-Q5_K_M.gguf` from a local file.** Path (a) is eliminated for LFM2/GGUF.

**Alternative path — `Leap.load(manifestURL:)` with a local `file://` URL**: Overload #2 at lines 261–264:
```
public static func load(manifestURL: Foundation.URL, options: LeapSDK.LiquidInferenceEngineManifestOptions? = nil, downloadProgressHandler: ...) async throws -> any LeapSDK.ModelRunner
```
This takes any `Foundation.URL`. If the URL is a local `file://` path to a manifest JSON on disk, the SDK may parse the manifest and load the GGUF from the `loadTimeParameters.model` path recorded in the manifest. The `ModelManifest` struct (in the `LeapModelDownloader` interface) has `loadTimeParameters.model: String` — this is the path to the model file. This path is ARCHITECTURALLY viable but is UNVERIFIED at runtime — the SDK may require an HTTPS manifest URL and reject `file://` schemes, or it may accept them. No documentation source explicitly confirms or denies `file://` acceptance. This requires an empirical test as the first implementation step.

---

## Q2 — `LeapModelDownloader` API surface in v0.9.4

The `LeapModelDownloader.xcframework` `.swiftinterface` was found at:
`~/Library/Developer/Xcode/DerivedData/ArigatoAI-cqfyrsgbtxsvntgobayhpahfospt/SourcePackages/artifacts/leap-ios/LeapModelDownloader/LeapModelDownloader.xcframework/ios-arm64_x86_64-simulator/LeapModelDownloader.framework/Modules/LeapModelDownloader.swiftmodule/arm64-apple-ios-simulator.swiftinterface`

This is distinct from `LeapSDK.xcframework`. It is already linked into our app — the `LeapSDK.swiftinterface` line 6 reads `import LeapModelDownloader`, making it a re-exported dependency.

### `ModelDownloader` class — full public API

**Initializer:**
```
public init(sessionConfiguration: Foundation.URLSessionConfiguration = .leapDefault, notificationConfig: LeapModelDownloaderNotificationConfig? = nil)
```
`URLSessionConfiguration.leapDefault` is a custom static property defined in an extension. The initializer does NOT take a storage directory — the download directory is determined internally by the SDK.

**Download methods:**
```
public func downloadModelFromManifest(_ manifestURL: Foundation.URL, downloadProgress: ...) async throws -> DownloadedModelManifest
public func downloadModel(_ model: String, quantization: String, downloadProgress: ...) async throws -> DownloadedModelManifest
public func downloadModel(_ model: any DownloadableModel, forceDownload: Bool = false) async -> Result<Foundation.URL, any Error>
public func requestDownloadModel(_ model: any DownloadableModel, forceDownload: Bool = false)
```

The `downloadModel(_:DownloadableModel)` overload returns `Result<Foundation.URL, any Error>`. The success `URL` is the local filesystem path to the downloaded file.

**Status / query methods:**
```
public func getModelFile(_ model: any DownloadableModel) -> Foundation.URL
public func queryStatus(_ model: any DownloadableModel) -> ModelDownloadStatus
public func queryStatus(_ manifestURL: Foundation.URL) -> ModelDownloadStatus
public func queryStatus(_ model: String, quantization: String) -> ModelDownloadStatus
public func getModelFileSize(_ model: any DownloadableModel) -> Int64?
```

`getModelFile(_:)` returns the local URL where the model WOULD be stored (the expected cache path), regardless of whether the file exists yet. `queryStatus` returns:
- `.notOnLocal` — not downloaded
- `.downloadInProgress(progress: Double)` — in flight
- `.downloaded` — file is present locally

**Critical answer — does `LeapModelDownloader` expose a load-from-local-path method?** NO. The downloader's responsibilities are: download management, status reporting, cache cleanup. It has no `loadModel` or `createRunner` method. Downloaded files must be fed to a loading API.

**Does it expose "check if model exists locally before downloading"?** YES. `queryStatus(_:DownloadableModel)` returning `.downloaded` is the check. `getModelFile(_:DownloadableModel)` returns the local path. Together, code can check `queryStatus` and if `.downloaded`, use `getModelFile` to get the path — no portal hit required for the check.

**Does its download path use the LEAP portal or a different endpoint?** This is split:
- `downloadModel(_:String, quantization:String)` and `downloadModelFromManifest(_:)` — use the LEAP portal/manifest endpoint. These are the broken paths.
- `downloadModel(_ model: any DownloadableModel, ...)` with a `HuggingFaceDownloadableModel` — uses the `uri` computed by `HuggingFaceDownloadableModel`, which is constructed from `ownerName/repoName/filename` as a Hugging Face URL. **This bypasses the LEAP portal entirely.** This is the viable HF-direct download path.

### `HuggingFaceDownloadableModel` struct

```
public struct HuggingFaceDownloadableModel : DownloadableModel {
  public let ownerName: Swift.String
  public let repoName: Swift.String
  public let filename: Swift.String
  public init(ownerName: Swift.String, repoName: Swift.String, filename: Swift.String)
  public var uri: Foundation.URL { get }
  public var name: Swift.String { get }
  public var localFilename: Swift.String { get }
}
```

For LFM2: `HuggingFaceDownloadableModel(ownerName: "LiquidAI", repoName: "LFM2-350M-ENJP-MT-GGUF", filename: "LFM2-350M-ENJP-MT-Q5_K_M.gguf")`. The `uri` computes to the Hugging Face resolve URL. The `localFilename` determines where the SDK caches the file on disk.

### `DownloadedModelManifest` struct

```
public struct DownloadedModelManifest {
  public let manifest: ModelManifest
  public let localModelURL: Foundation.URL
  public let localMultimodalProjectorURL: Foundation.URL?
  public let localAudioDecoderURL: Foundation.URL?
  public let localAudioTokenizerURL: Foundation.URL?
  public let chatTemplate: Swift.String?
}
```

`localModelURL` is the local GGUF file path after a portal-based `downloadModel(_:String, quantization:String)` call. This path could then be passed to `Leap.load(manifestURL:)` via a locally-constructed manifest JSON. But the portal-based `downloadModel` path is broken (the bug we're trying to fix), so `DownloadedModelManifest` is only useful via the `HuggingFaceDownloadableModel` path.

### `LeapDownloadableModel` struct

```
public struct LeapDownloadableModel : DownloadableModel {
  public let modelSlug: String
  public let quantizationSlug: String
  public var uri: Foundation.URL { get }
  ...
  public static func resolve(modelSlug: String, quantizationSlug: String) async -> LeapDownloadableModel?
}
```

`LeapDownloadableModel.uri` points to the LEAP portal. `resolve()` hits the portal to look up model metadata. This is another broken path (same -1011 failure).

**Q2 summary — the viable workaround chain:**
1. `let hfModel = HuggingFaceDownloadableModel(ownerName: "LiquidAI", repoName: "LFM2-350M-ENJP-MT-GGUF", filename: "LFM2-350M-ENJP-MT-Q5_K_M.gguf")`
2. Check `downloader.queryStatus(hfModel)` — if `.downloaded`, skip download
3. `let result = await downloader.downloadModel(hfModel, forceDownload: false)` — downloads from HF directly
4. `guard case .success(let localURL) = result else { ... }`
5. ← gap here: how to load `localURL` into `Leap.load()` — see Q3

---

## Q3 — Lower-level `Conversation` / `ModelRunner` construction in v0.9.4

### `Conversation` initializers

```
public init(modelRunner: any LeapSDK.ModelRunner, history: [LeapSDK.ChatMessage])
```
One public initializer. Requires an already-loaded `any ModelRunner`. Does not provide a path to construct a runner from scratch.

### `LiquidInferenceEngineRunner` (concrete `ModelRunner` conformer) — full initializer list

From `.swiftinterface` lines 33–61:

```
public init(options: LeapSDK.LiquidInferenceEngineOptions) throws
```
Synchronous, throws. Takes `LiquidInferenceEngineOptions` (ExecuTorch bundle format — `bundlePath: String` required). NOT the GGUF path.

```
convenience public init(manifestURL: Foundation.URL, options: LiquidInferenceEngineManifestOptions? = nil, downloadProgressHandler: ...) async throws
```
Same as `Leap.load(manifestURL:)`. Takes a manifest `URL`. The same `file://` question from Q1 applies here.

```
convenience public init(model: Swift.String, quantization: Swift.String, options: ...) async throws
```
Same as `Leap.load(model:quantization:)`. Uses the LEAP portal. Broken path.

```
@available(*, deprecated, message: "Use load(options:) instead")
convenience public init(path: Swift.String, options: LeapSDK.LiquidInferenceEngineOptions?) throws
```
Deprecated. Takes `path: String`. The `path` is the ExecuTorch `.bundle` path (matches `LiquidInferenceEngineOptions.bundlePath`). The deprecation note "Use load(options:) instead" points to `LiquidInferenceEngineOptions`, the ExecuTorch struct. This is NOT a GGUF loader.

**Critical finding**: There is NO `LiquidInferenceEngineRunner` initializer that takes a bare GGUF file path as a `String` or `URL` without a manifest wrapper. The GGUF loading path is always manifest-mediated — the manifest JSON is what tells the SDK where the GGUF file is on disk via `loadTimeParameters.model: String`.

**Complete construction chain from local GGUF to `any ModelRunner`:**

The only viable path connecting a local GGUF file to a runnable `ModelRunner` in v0.9.4 (without a portal call) is:

1. Obtain local GGUF path (e.g., from `ModelDownloader.downloadModel(hfModel)` or a pre-placed file)
2. Construct a manifest JSON file on disk with content matching `ModelManifest` structure:
   ```json
   {
     "inferenceType": "gguf",
     "schemaVersion": "1",
     "loadTimeParameters": {
       "model": "/path/to/LFM2-350M-ENJP-MT-Q5_K_M.gguf"
     }
   }
   ```
3. Write this manifest JSON to a temp location (e.g., `NSTemporaryDirectory()`)
4. Call `Leap.load(manifestURL: URL(fileURLWithPath: manifestJSONPath))` — **IF** the SDK accepts `file://` manifest URLs

**STOP NOTE**: Step 4's "IF" is the single unverified runtime assumption. If the SDK rejects `file://` manifest URLs, this entire chain collapses to no viable v0.9.4 path except forking the SDK. This must be the first empirical test in the B1.1 implementation.

**Fallback if `file://` manifest rejected**: The only remaining v0.9.4 path would be the deprecated `LiquidInferenceEngineRunner.init(path:options:)` — but this requires an ExecuTorch bundle, not a GGUF. LFM2 is distributed as GGUF only; there is no ExecuTorch bundle available on HF. This path is a dead end.

---

## Q4 — v0.10.x API surface

**Latest release tag as of 2026-05-17: v0.9.4** (released March 12).

The GitHub releases page (`github.com/Liquid4All/leap-ios/releases`, pages 1 and 2 inspected) shows:
- Page 1 (most recent): v0.9.4, v0.9.3, v0.9.2, v0.9.1, v0.9.0, v0.8.0, v0.7.7, v0.7.6, v0.7.5, v0.7.4
- Page 2 (older): v0.7.3, v0.7.2, v0.7.1, v0.7.0, v0.6.0, v0.5.0, v0.4.0, v0.3.0-x

**v0.10.x does not exist.** The prior V3 backlog "External research findings" subsection (V3_BACKLOG.md:881-888) correctly flagged the v0.10.x API surface as UNVERIFIED. That suspicion is now confirmed — v0.10.x was phantom. The `ModelDownloader.loadModel(repoId:quantization:)` API mentioned by external AI research does not exist in any published release.

The `docs.liquid.ai/deployment/on-device/sdk/model-loading.md` page mentions v0.10.5+ APIs (`downloader.loadModel(modelName:quantizationType:)`, `downloader.loadSimpleModel(model: ModelSource(modelPath:...))`) — but these are NOT present in the v0.9.4 `.swiftinterface`. The docs website is documenting a version ahead of what is publicly released on GitHub. This is a `docs.liquid.ai` vs. pinned-SDK source-conflict. **The `.swiftinterface` governs** per the source-conflict rule. Do not implement against the v0.10.5+ docs surface.

**Migration cost from v0.9.4 to a future version with `loadSimpleModel`**: Cannot be estimated — the release does not exist yet on GitHub. The `loadSimpleModel(model: ModelSource(modelPath: ggufURL.path, modelName:, quantizationId:))` API visible in the docs would be a low-migration-cost bump (probably S), but it is shipping with a currently-unpublished SDK version.

---

## Q5 — Hugging Face direct download path

**Confirmed from HF file listing** (huggingface.co/LiquidAI/LFM2-350M-ENJP-MT-GGUF/tree/main):

| File | Size |
|---|---|
| `LFM2-350M-ENJP-MT-Q5_K_M.gguf` | **260 MB** |
| `LFM2-350M-ENJP-MT-Q4_K_M.gguf` | 229 MB |
| `LFM2-350M-ENJP-MT-Q4_0.gguf` | 219 MB |
| `LFM2-350M-ENJP-MT-Q6_K.gguf` | 293 MB |
| `LFM2-350M-ENJP-MT-Q8_0.gguf` | 379 MB |
| `LFM2-350M-ENJP-MT-F16.gguf` | 711 MB |
| `LFM2-350M-ENJP-MT-F32.gguf` | 1.42 GB |

**Note on size discrepancy**: V3 backlog (line 883) said Q5_K_M ~350MB and Q4_K_M ~229MB. HF file listing shows Q5_K_M = **260 MB**, Q4_K_M = 229 MB. The ~350MB estimate was wrong; 260 MB is confirmed from the source.

**URL pattern for direct `URLSession` download:**
```
https://huggingface.co/LiquidAI/LFM2-350M-ENJP-MT-GGUF/resolve/main/LFM2-350M-ENJP-MT-Q5_K_M.gguf?download=true
```

**Redirect behavior (confirmed empirically via WebFetch)**: The `resolve/main/` endpoint returns HTTP 302 and redirects to a Xet CAS presigned URL on `cas-bridge.xethub.hf.co`. The presigned URL includes `X-Amz-Expires=3600` — TTL is **1 hour**. `URLSession` follows redirects automatically so this is transparent to the caller, but the direct presigned URL must not be cached as a persistent download link. The `resolve/main/` stable URL is what should be stored; `URLSession` will re-resolve the redirect on each download attempt.

**Authentication**: None required. The repo is public (license `lfm1.0`, open). No `Authorization` header needed. No special `User-Agent` requirement is documented by Hugging Face for public repos.

**File integrity — SHA256 mechanism**: The Xet storage backend uses LFS SHA256 as its integrity anchor (confirmed from HF Xet docs: "query the Xet CAS with the LFS SHA256 hash"). The `LeapModelDownloader` interface contains `ModelDownloadError.sha256Mismatch(expectedHash: String, actualHash: String)` — confirming the SDK performs SHA256 post-download verification when using its own downloader. For a `URLSession`-based implementation, the SHA256 of the known file can be hardcoded as a build-time constant and verified post-download via `CryptoKit.SHA256` (which is already imported by `LeapModelDownloader`, visible in its interface header at line 5).

**ETag behavior**: The `resolve/main/` URL itself does not return a stable ETag — the redirect target URL is time-limited. For cache invalidation in a custom `URLSession` downloader, the reliable pattern is: check if the local file exists AND if its size matches the expected 260 MB (272,629,504 bytes or similar), and if so, skip re-download. SHA256 verification can be added as a stronger check on first download and stored in `UserDefaults` / `Keychain` for subsequent launch checks.

---

## Recommendation

The recommended implementation path for B1.1 is a **two-phase approach using `HuggingFaceDownloadableModel` + `Leap.load(manifestURL:)` with a locally-constructed manifest JSON**, which keeps the implementation within v0.9.4 and avoids a SDK fork. The steps are:

**Phase 1 (empirical gate — ~30 min)**: Before writing any production code, write a single throwaway test that:
1. Downloads the GGUF via `ModelDownloader.downloadModel(HuggingFaceDownloadableModel(...))`, obtaining a local `URL`
2. Constructs a minimal manifest JSON on disk pointing to that local URL
3. Calls `Leap.load(manifestURL: URL(fileURLWithPath: manifestPath))` with a `file://` URL

If this succeeds (runner is created and a warmup inference works), the path is confirmed and the full implementation follows. If the SDK rejects `file://` manifest URLs, the decision tree has only two remaining options: (i) wait for a future leap-ios release that adds `loadSimpleModel(model: ModelSource(modelPath:...))` — the `docs.liquid.ai` docs suggest this is coming but with no release date — or (ii) fork the SDK to add disk-first lookup before portal initiation.

**If Phase 1 succeeds**, the implementation scope for B1.1 is:
- `AppBootstrapper`: add `ModelDownloader` initialization, `HuggingFaceDownloadableModel` constant for Q5_K_M, status check before download, download-with-progress callback, manifest JSON construction to temp directory, then `Leap.load(manifestURL:)` — replacing or supplementing the existing `Leap.load(model:quantization:)` call
- `LFM2ModelLoader.swift`: may need to accept a manifest URL instead of model slug + quantization slug, OR the manifest construction stays entirely in `AppBootstrapper` and only the final `Leap.load` call moves
- `StartupErrorView` / progress reporting: already exists; the `downloadProgressHandler` closure from `Leap.load(manifestURL:)` can drive it

**If Phase 1 fails**, surface to human gate immediately. Do not proceed to Phase 2 production code. The SDK version bump option becomes the only path — and that version is currently unreleased on GitHub, making "wait for release" the only non-fork option.

The Q5_K_M variant remains the correct choice: 260 MB actual (not 350 MB as estimated), within the acceptable download-on-first-launch budget, and the quality/latency balance was already justified in the D1 locked decision.

---

## Unverifiable claims encountered

- **`file://` URL acceptance by `Leap.load(manifestURL:)`**: Whether `Leap.load(manifestURL:)` (and the equivalent `LiquidInferenceEngineRunner.init(manifestURL:)`) accepts a local `file://` URL is not documented in the README, docs.liquid.ai, or the `.swiftinterface`. The interface declares `Foundation.URL` without scheme restriction. This is the single load-bearing unknown for the B1.1 implementation path.

- **Manifest JSON schema exact fields and `inferenceType` string values**: The `ModelManifest` struct in the `LeapModelDownloader` interface shows the field shape (`inferenceType: String`, `schemaVersion: String`, `loadTimeParameters.model: String`), but the exact string values expected (e.g., `"gguf"` vs `"gguf-manifest"` for `inferenceType`, valid `schemaVersion` values) are not documented in any allowed source. These must be reverse-engineered from a successfully-downloaded manifest (which can be obtained by capturing the manifest JSON that `ModelDownloader.downloadModelFromManifest` writes to disk during a portal-download, using a different network or mocked endpoint).

- **V3 backlog Q5_K_M size estimate of ~350 MB** (line 883): Was incorrect. Confirmed as 260 MB from HF file listing. The Q4_K_M estimate of ~229 MB was correct. The ~350 MB figure may have confused Q5_K_M with Q6_K (293 MB) or F16 (711 MB).

- **`docs.liquid.ai` v0.10.5+ API surface** (`loadSimpleModel(model: ModelSource(modelPath:...))`, `ModelSource` struct): The docs describe this API as shipping with "v0.10.5+" but no such version is published on GitHub as of 2026-05-17. This API surface cannot be verified against a released xcframework. It exists in docs only.

- **`HuggingFaceDownloadableModel.localFilename` computation**: The exact local filename the SDK uses for the cached file (stored internally by `ModelDownloader`) is not documented. It is computable from the `localFilename` property on the struct but the storage directory is determined internally by the SDK. The `getModelFile(_:DownloadableModel)` method returns the full local URL, making this a non-issue for implementation — use `getModelFile` rather than constructing the path manually.

- **`ModelDownloader.downloadModel(_:DownloadableModel)` download endpoint for `HuggingFaceDownloadableModel`**: Confirmed architecturally that `uri` is HF-derived (not portal-derived), but the exact HTTP behavior (whether it uses the `leapDefault` `URLSessionConfiguration` with any custom headers that might interfere with HF's CDN) is not documented. If the `leapDefault` session config adds custom headers that break HF's Xet redirect chain, the download would fail. This is a second empirical gate.

---

## Corrigendum (filed 2026-05-17 post-spike)

**Status update**: this pre-flight's main recommendation is **DISPROVEN**. The Phase 1 spike (`ArigatoAITests/Spikes/LFM2LocalLoadSpike.swift`, commit `6512662`) ran the recommended chain end-to-end against the real v0.9.4 SDK and the real LFM2 model.

### Verdict

> **SPIKE FAIL**: `Leap.load(manifestURL:)` rejected `file://` URL after 3.5s. Error: `Error Domain=NSURLErrorDomain Code=-1011 "(null)"`. Production path requires SDK fork or future release.

The HF download half of the chain works fine (260,374,304 bytes in 3.5s, exact size match, Xet redirect handled transparently by `URLSession`). The `Leap.load(manifestURL:)` step closes the path — the SDK throws the SAME `NSURLErrorDomain -1011` against a `file://` URL that it throws against the broken portal, with empty `userInfo` (no `NSURLErrorFailingURLErrorKey`). Strong evidence the SDK has a single HTTP-only network code path that doesn't dispatch on URL scheme, regardless of the `Foundation.URL` parameter type's lack of scheme restriction.

### What this means for the Summary table

Re-grade row (a2):

| Path | Status (pre-spike) | Status (post-spike) |
|---|---|---|
| (a2) `Leap.load(manifestURL:)` with local `file://` manifest JSON | VIABLE-UNVERIFIED-AT-RUNTIME | **DISPROVEN — SDK rejects `file://` with same `-1011` as portal path** |

All other rows remain accurate (the spike did not re-verify them; it only tested row (a2)).

### What this means for the Recommendation section

The two-phase approach is invalidated. The "If Phase 1 fails" branch (lines ~244-249 of the original recommendation) fires. The remaining viable paths for B1.1 production, as surfaced to the human gate post-spike:

- **(A) Fork LEAP SDK v0.9.4** to add `file://` handling to the manifest-URL load path. Multi-day; touches private SDK internals; open-ended maintenance cost; forks are sticky.
- **(B) Wait for Liquid AI** to ship the `loadSimpleModel(modelPath:)` API the `docs.liquid.ai` docs describe but no GitHub release contains. v0.10.x does NOT exist on GitHub as of 2026-05-17 (confirmed by Q4); the docs site is documenting an unreleased version. Unknown wait; cheap if it ships soon.
- **(C) Fix the LEAP portal auth** — investigate what changed in `leap.liquid.ai`, possibly file an issue with Liquid AI. Cost depends on whether the bug is on their side, in our config, or in the SDK's cached creds. Lowest cost IF the bug is recoverable on our side.
- **(D) Bundle the model in the app binary**, skip download entirely. ~260 MB binary inflation; App Store distribution complications; cheap to revert.

Option selection is pending human-gate decision as of this corrigendum's filing.

### Authoritative manifest schema URL captured (resolves a Q3 "Unverifiable claim")

The pre-flight Q3 example manifest JSON used GUESSED string values:

```json
{
  "inferenceType": "gguf",          // GUESSED — wrong
  "schemaVersion": "1",              // GUESSED — wrong
  "loadTimeParameters": {            // camelCase — wrong
    "model": "/path/to/model.gguf"
  }
}
```

The spike discovered the **maintainer-published manifest** at:

```
https://huggingface.co/LiquidAI/LFM2-350M-ENJP-MT-GGUF/resolve/main/leap/Q5_K_M.json
```

This URL is Liquid AI's official LEAP manifest for our exact pinned quantization (LFM2-350M-ENJP-MT-Q5_K_M). The real schema:

- `inference_type`: `"llama.cpp/text-to-text"` (NOT `"gguf"`)
- `schema_version`: `"1.0.0"` (NOT `"1"`)
- Keys are `snake_case` (NOT `camelCase`)
- `generation_time_parameters.sampling_parameters` block publishes maintainer-recommended defaults: `temperature: 0.3`, `min_p: 0.15`, `repetition_penalty: 1.05`

These last three values resolve the previous "Other `GenerationOptions` fields … recommended values for this model are not confirmed by an allowed source" hedge that appeared in `.claude/skills/leap-sdk/SKILL.md` (commit `1f56009`). The skill was reconciled with the verified values in commit `2610a4d`.

**The maintainer manifest URL is now the authoritative schema reference** for whichever B1.1 production path is selected. Even option (A) — SDK fork — would benefit from a manifest constructed against the real schema once `file://` handling is added.

### Side findings from the spike worth recording

1. **`GenerationOptions` field name regression in `leap-sdk` SKILL** — `maxTokens` does not exist in v0.9.4; the correct field is `maxOutputTokens` (`UInt32?`). Fixed in commit `2610a4d`.
2. **Empty `userInfo` on SDK errors makes production diagnostics opaque** — when LEAP SDK throws `NSURLErrorDomain -1011`, the failing URL is not surfaced via `NSURLErrorFailingURLErrorKey` or `NSURLErrorFailingURLStringErrorKey`. Any production error-handler that wants to log "which URL did the SDK actually attempt" will need to capture it via a different path (e.g., `URLProtocol` interception during diagnostics).
3. **`-1011` is the same code from both portal and `file://` paths** — production code that distinguishes "portal-auth-broken" from "file://-not-accepted" cannot use the error code as a discriminator. Both manifest as the same indistinguishable failure.
4. **HF Xet redirect chain works seamlessly with `URLSession.download`** — no special configuration needed; the time-limited Xet CAS presigned URL is followed automatically. For any future option that downloads from HF directly, this is verified-good.
5. **Doc-researcher source-not-found discipline gap** (manifest schema guessed at in pre-flight Q3 instead of flagged UNVERIFIABLE-with-STOP). Recorded as a workflow lesson in V3 commit `8e785a0`. The pre-flight should have surfaced "the verification path is unreachable in practice, so STOP and ask for a different research path" rather than recommending the construction-template approach with the values flagged in a tail section.

### Cross-references

- Spike commit: `6512662` — `ArigatoAITests/Spikes/LFM2LocalLoadSpike.swift` (env-var gated via `RUN_NETWORK_SPIKES=1`, gets deleted in the B1.1 production implementation commit regardless of which option lands).
- V3 closure entry: commit `d3b621c` — "B1.1 HF-download → local-manifest → `Leap.load(manifestURL: file://)` chain — empirically disproven."
- Doc-researcher discipline lesson: commit `8e785a0` (bullet within V3 entry `d3b621c`).
- SKILL second reconcile: commit `2610a4d` — fixes `maxTokens` → `maxOutputTokens` and populates the verified sampling defaults from the manifest URL above.
- Parent V3 entry: `b851dad` ("LFM2 model download failing — LEAP SDK portal path stale") — the work this pre-flight was gating.
- Sprint sequencing doc: `docs/PRE_MVP1_REVIEW.md` B1.1 — sprint-window deliverable whose recommended approach is now obsolete.
