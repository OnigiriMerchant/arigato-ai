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
        let kit = try await WhisperKit(model: variant.rawValue)
        return ArgmaxOSSWhisperClient(kit: kit)
    }
}
