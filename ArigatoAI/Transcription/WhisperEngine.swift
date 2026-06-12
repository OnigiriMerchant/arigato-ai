//
//  WhisperEngine.swift
//  ArigatoAI
//
//  Created by Jose Castell on 2026/05/10.
//

import Foundation
import WhisperKit

/// Internal seam isolating the underlying WhisperKit instance behind a
/// `Sendable` protocol that ``WhisperModelLoader`` can hold safely.
///
/// WhisperKit v1.0.0 does not declare `Sendable` conformance on the
/// `WhisperKit` class. Routing all access through a `Sendable` protocol
/// (combined with actor ownership inside the loader) is the correct
/// mitigation rather than reaching for `@preconcurrency import`.
///
/// ``WhisperClient`` extends this protocol with the transcription entry
/// point used during a live meeting; this base protocol carries only the
/// pre-warm operation needed at app launch (Step 7 / `AppBootstrapper`).
protocol WhisperEngine: Sendable {
    /// Triggers Neural Engine specialisation for the loaded WhisperKit
    /// model (CoreML compilation/caching). Idempotent on the underlying
    /// kit; safe to call once per fresh load.
    func prewarmModels() async throws
}

/// Production adapter wrapping a real WhisperKit instance.
///
/// The class is marked `@unchecked Sendable` because `WhisperKit` itself
/// is not `Sendable` in v1.0.0. The unchecked annotation is sound only
/// because ``WhisperModelLoader`` (an actor) is the sole owner of the
/// adapter and serialises every method call against it. Do NOT share an
/// `ArgmaxOSSWhisperClient` value across other actors directly.
///
/// Conforms to ``WhisperClient`` so consumers downstream of the loader
/// can call ``transcribe(audio:anchorHostTime:)`` against a real
/// WhisperKit instance. The adapter performs the value-type translation
/// from WhisperKit's `TranscriptionResult` / `TranscriptionSegment` into
/// this module's ``WhisperWindowResult`` / ``WhisperRawSegment``,
/// including the explicit `Float -> Double` widening on the segment time
/// fields.
final nonisolated class ArgmaxOSSWhisperClient: WhisperClient, @unchecked Sendable {
    private let kit: WhisperKit

    /// Creates the adapter from an already-constructed WhisperKit instance.
    /// Construction is delegated to ``WhisperClientFactory/make`` so the
    /// adapter never needs to know the model identifier directly.
    init(kit: WhisperKit) {
        self.kit = kit
    }

    func prewarmModels() async throws {
        try await kit.prewarmModels()
    }

    /// The decode options every production transcription request uses.
    ///
    /// Two non-default flags are deliberately set; everything else stays at
    /// WhisperKit v1.0.0's defaults (`language: nil`, `usePrefillPrompt:
    /// true`, `withoutTimestamps: false`, etc.):
    ///
    /// 1. **`skipSpecialTokens: true`** — strips the `<|...|>` control tokens
    ///    (`<|en|>`, `<|0.00|>`, `<|transcribe|>`, …) from each segment's
    ///    decoded text before it reaches the rest of the pipeline. Without
    ///    this, the literal `.` characters *inside* a timestamp token such as
    ///    `<|0.00|>` are visible to `SentenceBuffer`'s boundary detector
    ///    (`。！？.!?`), which split mid-token and produced spurious sentence
    ///    boundaries; the same tokens also leaked into the LFM2 translation
    ///    input. Stripping them per-segment means neither the boundary
    ///    detector nor the translator ever sees a control token.
    /// 2. **`detectLanguage: true`** — restores the architecture's
    ///    auto-detection pass (Phase 4 Decision 5's consecutive-window
    ///    disagreement gating depends on a real per-window prediction). With
    ///    `usePrefillPrompt` at its `true` default, WhisperKit v1.0.0 would
    ///    otherwise resolve `detectLanguage` to `false` (`detectLanguage ??
    ///    !usePrefillPrompt`) and force the prefill language to its
    ///    `Constants.defaultLanguageCode` (`<|en|>`), so every window would
    ///    report `en` regardless of what was spoken. Passing `true`
    ///    explicitly enables the detection pass independent of
    ///    `usePrefillPrompt`, so `LanguageRouter` receives the language
    ///    WhisperKit actually detected.
    ///
    /// Per-segment start/end timing is driven by the timestamp tokens, which
    /// are emitted and consumed by `SegmentSeeker` *independently* of
    /// `skipSpecialTokens` (the flag only filters tokens below
    /// `specialTokenBegin` from the decoded *text*, not the timing path).
    /// `withoutTimestamps` therefore deliberately stays at its `false`
    /// default — flipping it would suppress the timestamp tokens the
    /// per-segment timing relies on.
    ///
    /// `internal static` so the contract is exercisable from
    /// `WhisperDecodeOptionsTests` via `@testable import` without exposing a
    /// configuration seam to non-test callers.
    static func decodeOptions() -> DecodingOptions {
        DecodingOptions(
            detectLanguage: true,
            skipSpecialTokens: true
        )
    }

    /// Transcribes the supplied audio window via the underlying
    /// `WhisperKit` instance and returns a value-typed
    /// ``WhisperWindowResult``.
    ///
    /// Behaviour notes:
    /// - WhisperKit's `transcribe(audioArray:)` returns
    ///   `[TranscriptionResult]`. We use the first element when present
    ///   (the production decode path produces one result per audio
    ///   array). When the array is empty we return a result with the
    ///   round-tripped anchor, an empty `language`, and zero segments;
    ///   the router treats an empty language tag as a no-op for
    ///   disagreement gating.
    /// - The `language` field is passed through verbatim. The adapter
    ///   never substitutes `"en"`/`"ja"` defaults — that decision lives
    ///   in ``SpokenLanguage`` and the language router. The tag now
    ///   reflects an explicitly-requested detection pass (the shared
    ///   ``decodeOptions()`` set `detectLanguage: true`), **not** WhisperKit
    ///   v1.0.0's default forced-`<|en|>` prefill. The adapter itself does
    ///   not detect; it forwards whatever the requested pass produced. An
    ///   empty string remains legal and remains a router no-op.
    /// - Each `TranscriptionSegment.start` / `.end` (`Float`, in
    ///   seconds) is widened to `Double` explicitly. The widening is
    ///   exact for the magnitudes Whisper produces (window length is
    ///   bounded by Phase 4 Decision 4 to 5 seconds).
    /// - `anchorHostTime` is round-tripped onto
    ///   ``WhisperWindowResult/windowAnchorHostTime`` verbatim
    ///   (contract **C17**).
    func transcribe(
        audio: [Float],
        anchorHostTime: UInt64
    ) async throws -> WhisperWindowResult {
        let results = try await kit.transcribe(
            audioArray: audio,
            decodeOptions: ArgmaxOSSWhisperClient.decodeOptions()
        )

        guard let first = results.first else {
            return WhisperWindowResult(
                language: "",
                windowAnchorHostTime: anchorHostTime,
                segments: []
            )
        }

        let mapped = first.segments.map { segment in
            WhisperRawSegment(
                text: segment.text,
                startSeconds: Double(segment.start),
                endSeconds: Double(segment.end),
                avgLogprob: Double(segment.avgLogprob)
            )
        }

        return WhisperWindowResult(
            language: first.language,
            windowAnchorHostTime: anchorHostTime,
            segments: mapped
        )
    }
}

/// A factory closure that resolves a ``WhisperModelVariant`` into a fully
/// constructed ``WhisperClient``.
///
/// The closure is `@Sendable` so ``WhisperModelLoader`` can hold it across
/// actor boundaries. Production wiring uses
/// ``WhisperClientFactory/make``; tests inject their own closure that
/// returns a fake client.
typealias WhisperEngineFactory = @Sendable (WhisperModelVariant) async throws -> any WhisperClient

/// Production factory wiring for the WhisperKit-backed client.
///
/// Kept as a namespace (`enum` with a single static let) rather than a
/// free function so the production factory and any future variants live
/// next to each other in the type system.
nonisolated enum WhisperClientFactory {
    /// The production ``WhisperEngineFactory``. Constructs a real
    /// `WhisperKit` instance using the variant's raw model identifier and
    /// wraps it in ``ArgmaxOSSWhisperClient``. Any error thrown by
    /// `WhisperKit.init` propagates unchanged; the loader is responsible
    /// for translating it into ``TranscriptionError/modelLoadFailed(_:)``.
    static let make: WhisperEngineFactory = { variant in
        // Offline load (Phase 2.5): the CoreML model AND the tokenizer ship
        // bundled in the app, flattened into the bundle's resource root. Two
        // settings together make this fully offline:
        //
        // 1. `modelFolder` + `download: false` — points WhisperKit at the
        //    bundled `.mlmodelc` packages and forbids the model-download arm.
        // 2. `tokenizerFolder` set to the SAME bundled folder — the
        //    load-bearing tokenizer safeguard. `download: false` does NOT
        //    cover the tokenizer: WhisperKit v1.0.0's
        //    `ModelUtilities.loadTokenizer` searches a GLOBAL Hub cache
        //    (`Documents/huggingface/…`) BEFORE the bundle and probes it on
        //    `tokenizer.json` alone; a stale partial cache from a prior
        //    download-mode build would shadow a complete bundle and silently
        //    fall back to a HuggingFace download. Setting `tokenizerFolder`
        //    re-roots WhisperKit's tokenizer search base at the bundle, so the
        //    global cache is dropped from the search entirely and the bundled
        //    tokenizer is authoritative even on an upgrade-over-prior-build
        //    device (verified against WhisperKit v1.0.0
        //    `ModelUtilities.loadTokenizer` lines 24-44).
        //
        // `WhisperBundledModel.requireFolderPath()` verifies all five required
        // assets are physically present and throws a typed
        // ``WhisperBundledModelError`` otherwise — converting a silent network
        // fetch into a fast packaging error the loader maps to
        // ``TranscriptionError/modelLoadFailed(_:)``.
        let folderPath = try WhisperBundledModel.requireFolderPath()
        let config = WhisperKitConfig(
            model: variant.rawValue,
            modelFolder: folderPath,
            tokenizerFolder: URL(fileURLWithPath: folderPath),
            download: false
        )
        let kit = try await WhisperKit(config)
        return ArgmaxOSSWhisperClient(kit: kit)
    }
}

/// Resolves the app-bundled WhisperKit model folder for offline load.
///
/// The model's CoreML packages + `config.json` and the tokenizer's
/// `tokenizer.json` / `tokenizer_config.json` ship under
/// `Resources/WhisperModels/<model>/`, which Xcode flattens into the
/// bundle's resource root — so the folder WhisperKit loads from is
/// ``Bundle/resourcePath``. WhisperKit reads the model packages by name and
/// finds the tokenizer via its `tokenizerFolder` / `[modelFolder]` search
/// paths.
///
/// **`download: false` does NOT make the tokenizer offline.** WhisperKit
/// v1.0.0's tokenizer loader (`ModelUtilities.loadTokenizer`) carries an
/// *unconditional* HuggingFace download fallback that ignores the `download`
/// flag and fires silently whenever the tokenizer fails to load locally. Two
/// independent hazards must both be closed for a real offline guarantee:
///
/// 1. **Missing bundled file.** If `tokenizer.json` *or*
///    `tokenizer_config.json` is absent from the bundle, the local load
///    throws and WhisperKit silently downloads. This resolver closes it by
///    verifying the **physical presence** of both tokenizer files *plus* the
///    three CoreML model packages WhisperKit loads by name
///    (`MelSpectrogram.mlmodelc`, `AudioEncoder.mlmodelc`,
///    `TextDecoder.mlmodelc`) at the bundle resource root, failing fast with
///    a typed ``WhisperBundledModelError`` at construction time.
/// 2. **Stale Hub cache shadowing the bundle.** WhisperKit searches a global
///    Hub cache (`Documents/huggingface/…`) *before* the bundle and probes it
///    on `tokenizer.json` alone, so a partial leftover cache (from a prior
///    download-mode build) would shadow a complete bundle and fall through to
///    a network download. This resolver cannot see that cache; the closing
///    fix lives in ``WhisperClientFactory/make``, which sets `tokenizerFolder`
///    to the bundled folder so WhisperKit's tokenizer search base is re-rooted
///    at the bundle and the global cache is dropped from the search entirely.
///
/// Together these keep the "no network during meetings" guarantee intact on
/// both clean installs and upgrade-over-prior-build devices.
///
/// The resolver is split into a pure, injectable ``resolve(resourcePath:fileExists:)``
/// (mirroring the ``LFM2CachePathResolver`` precedent) and a thin
/// production wrapper ``requireFolderPath()`` that binds the real
/// `Bundle.main` / `FileManager` dependencies. The split lets the offline
/// guard be exercised deterministically without touching the filesystem.
///
/// This type is `nonisolated`: the lookup is not actor-isolated and the
/// returned string is `Sendable`.
nonisolated enum WhisperBundledModel {
    /// Each required tokenizer file paired with the typed error
    /// ``resolve(resourcePath:fileExists:)`` throws when that file is absent.
    /// `resolve` iterates this list, so it is the single source of truth for
    /// *which* tokenizer files are required *and which* error names each — the
    /// list and the checks cannot drift. Distinct errors
    /// (``WhisperBundledModelError/missingTokenizer`` vs
    /// ``WhisperBundledModelError/missingTokenizerConfig``) keep a
    /// partial-bundle failure diagnosable from the thrown error alone.
    ///
    /// Both files are what WhisperKit's tokenizer loader needs locally; either
    /// being absent triggers the unconditional HuggingFace fallback.
    static let requiredTokenizerChecks: [(name: String, error: WhisperBundledModelError)] = [
        ("tokenizer.json", .missingTokenizer),
        ("tokenizer_config.json", .missingTokenizerConfig),
    ]

    /// The tokenizer filenames the resolver requires, derived from
    /// ``requiredTokenizerChecks`` so the packaging tests' manifest cannot
    /// drift from what `resolve` actually enforces.
    static var requiredTokenizerFiles: [String] {
        requiredTokenizerChecks.map(\.name)
    }

    /// The CoreML model packages WhisperKit loads by name. They are
    /// *directories* on disk; the injected `fileExists` returns `true` for
    /// directories (as `FileManager.fileExists(atPath:)` does), so the same
    /// probe verifies them.
    static let requiredModelPackages = [
        "MelSpectrogram.mlmodelc",
        "AudioEncoder.mlmodelc",
        "TextDecoder.mlmodelc",
    ]

    /// Pure, injectable resolver: verifies that every asset required for an
    /// offline WhisperKit load is physically present, returning the folder
    /// path on success.
    ///
    /// A missing asset fails fast here — as a typed
    /// ``WhisperBundledModelError`` — rather than silently degrading to a
    /// HuggingFace network fetch inside WhisperKit's tokenizer loader (see
    /// the type-level doc for why `download: false` does not cover this).
    ///
    /// - Parameters:
    ///   - resourcePath: The bundle resource root to resolve against
    ///     (``Bundle/resourcePath`` in production). `nil` means the bundle
    ///     has no resource path, which is a packaging error.
    ///   - fileExists: Predicate answering whether an asset exists at a given
    ///     absolute path. Production passes `FileManager.fileExists(atPath:)`;
    ///     it returns `true` for both files and directories, which is correct
    ///     because the `.mlmodelc` packages are directories.
    /// - Returns: `resourcePath` unchanged once every required asset is
    ///   verified present.
    /// - Throws: ``WhisperBundledModelError/bundleResourcePathUnavailable``
    ///   when `resourcePath` is `nil`;
    ///   ``WhisperBundledModelError/missingTokenizer`` when `tokenizer.json`
    ///   is absent; ``WhisperBundledModelError/missingTokenizerConfig`` when
    ///   `tokenizer_config.json` is absent;
    ///   ``WhisperBundledModelError/missingModelPackage(_:)`` (carrying the
    ///   package name) on the first absent `.mlmodelc`.
    static func resolve(
        resourcePath: String?,
        fileExists: (String) -> Bool
    ) throws -> String {
        guard let resourcePath else {
            throw WhisperBundledModelError.bundleResourcePathUnavailable
        }

        func path(for name: String) -> String {
            (resourcePath as NSString).appendingPathComponent(name)
        }

        for check in requiredTokenizerChecks where !fileExists(path(for: check.name)) {
            throw check.error
        }

        for package in requiredModelPackages where !fileExists(path(for: package)) {
            throw WhisperBundledModelError.missingModelPackage(package)
        }

        return resourcePath
    }

    /// Thin production wrapper binding ``resolve(resourcePath:fileExists:)``
    /// to the real `Bundle.main` resource path and `FileManager`. The
    /// absence of any required asset means the model resources were not
    /// bundled — a build/packaging error, surfaced as
    /// ``WhisperBundledModelError`` so the loader can map it to
    /// ``TranscriptionError/modelLoadFailed(_:)``.
    static func requireFolderPath() throws -> String {
        try resolve(
            resourcePath: Bundle.main.resourcePath,
            fileExists: { FileManager.default.fileExists(atPath: $0) }
        )
    }
}

/// Errors raised when the bundled WhisperKit model/tokenizer is incompletely
/// packaged into the app bundle (a packaging error, never expected at
/// runtime). Each case names the specific missing asset so a partial-bundle
/// build failure is diagnosable from the thrown error alone.
///
/// `Equatable` is synthesized (``missingModelPackage(_:)`` carries a
/// `String`) so the packaging tests can assert the exact case — including
/// which package was reported missing — cleanly.
enum WhisperBundledModelError: Error, Equatable {
    /// `Bundle.main.resourcePath` returned `nil`. The bundle has no resource
    /// root to resolve against.
    case bundleResourcePathUnavailable

    /// `tokenizer.json` is absent from the bundle resource root. Without it
    /// WhisperKit's tokenizer loader falls back to a HuggingFace download.
    case missingTokenizer

    /// `tokenizer_config.json` is absent from the bundle resource root.
    /// Same silent-network-fallback consequence as ``missingTokenizer``.
    case missingTokenizerConfig

    /// A required CoreML model package (`.mlmodelc`) is absent. The
    /// associated value is the package name that was reported missing.
    case missingModelPackage(String)
}
