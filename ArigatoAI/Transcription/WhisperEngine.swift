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
    ///   in ``SpokenLanguage`` and the language router.
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
        let results = try await kit.transcribe(audioArray: audio)

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
        // bundled in the app, flattened into the bundle's resource root.
        // `modelFolder` points WhisperKit at those files. Note `download:
        // false` does NOT by itself guarantee offline operation: WhisperKit
        // v1.0.0's `ModelUtilities.loadTokenizer` has an unconditional
        // HuggingFace fallback that fires silently if `tokenizer.json` or
        // `tokenizer_config.json` is missing/malformed. The real offline
        // safeguard is `WhisperBundledModel.requireFolderPath()`, which
        // verifies the physical presence of both tokenizer files plus the
        // three `.mlmodelc` packages and throws a typed
        // ``WhisperBundledModelError`` if any is absent — converting a silent
        // network fetch into a fast packaging error the loader maps to
        // ``TranscriptionError/modelLoadFailed(_:)``.
        let config = try WhisperKitConfig(
            model: variant.rawValue,
            modelFolder: WhisperBundledModel.requireFolderPath(),
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
/// finds the tokenizer via its `[modelFolder]` search path.
///
/// **`download: false` does NOT make the tokenizer offline.** WhisperKit
/// v1.0.0's tokenizer loader (`ModelUtilities.loadTokenizer`) carries an
/// *unconditional* HuggingFace download fallback that ignores the
/// `download` flag and fires silently if `tokenizer.json` *or*
/// `tokenizer_config.json` is missing or malformed. The offline guarantee
/// therefore rests on the **physical presence** of both tokenizer files
/// *plus* the three CoreML model packages WhisperKit loads by name
/// (`MelSpectrogram.mlmodelc`, `AudioEncoder.mlmodelc`,
/// `TextDecoder.mlmodelc`) at the bundle resource root. A partial bundle —
/// e.g. `tokenizer.json` present but `tokenizer_config.json` absent — would
/// otherwise let WhisperKit silently phone home for the missing piece,
/// breaking the "no network during meetings" guarantee. This resolver
/// converts that silent network degradation into a fast, typed
/// ``WhisperBundledModelError`` at construction time.
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
    /// The names of the assets that must be physically present at the bundle
    /// resource root for an offline WhisperKit load to succeed without a
    /// silent network fallback. Shared between ``resolve(resourcePath:fileExists:)``
    /// and the packaging tests so there is a single source of truth.
    ///
    /// - The two tokenizer files (`tokenizer.json`, `tokenizer_config.json`)
    ///   are what WhisperKit's tokenizer loader needs locally; either being
    ///   absent triggers the unconditional HuggingFace fallback.
    /// - The three `.mlmodelc` packages are the CoreML models WhisperKit
    ///   loads by name. They are *directories* on disk; the injected
    ///   `fileExists` returns `true` for directories (as
    ///   `FileManager.fileExists(atPath:)` does).
    static let requiredTokenizerFiles = ["tokenizer.json", "tokenizer_config.json"]

    /// The CoreML model packages WhisperKit loads by name. See
    /// ``requiredTokenizerFiles`` for why directories are checked with the
    /// same `fileExists` probe.
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

        guard fileExists(path(for: "tokenizer.json")) else {
            throw WhisperBundledModelError.missingTokenizer
        }
        guard fileExists(path(for: "tokenizer_config.json")) else {
            throw WhisperBundledModelError.missingTokenizerConfig
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
