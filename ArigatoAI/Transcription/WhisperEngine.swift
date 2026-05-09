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
/// Step 10 of `docs/PHASE_4_HANDOFF.md` (`WhisperClient`) will widen this
/// protocol with `transcribe(audioArray:)` and `detectLanguage(audio:)`
/// methods. Until then, the only pre-warm-relevant entry point is
/// ``prewarmModels()``.
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
/// `ArgmaxOSSWhisperEngine` value across other actors directly.
final nonisolated class ArgmaxOSSWhisperEngine: WhisperEngine, @unchecked Sendable {
    private let kit: WhisperKit

    /// Creates the adapter from an already-constructed WhisperKit instance.
    /// Construction is delegated to ``ArgmaxOSSWhisperFactory/make`` so the
    /// adapter never needs to know the model identifier directly.
    init(kit: WhisperKit) {
        self.kit = kit
    }

    func prewarmModels() async throws {
        try await kit.prewarmModels()
    }
}

/// A factory closure that resolves a ``WhisperModelVariant`` into a fully
/// constructed ``WhisperEngine``.
///
/// The closure is `@Sendable` so ``WhisperModelLoader`` can hold it across
/// actor boundaries. Production wiring uses
/// ``ArgmaxOSSWhisperFactory/make``; tests inject their own closure that
/// returns a fake engine.
typealias WhisperEngineFactory = @Sendable (WhisperModelVariant) async throws -> any WhisperEngine

/// Production factory wiring for the WhisperKit-backed engine.
///
/// Kept as a namespace (`enum` with a single static let) rather than a
/// free function so the production factory and any future variants live
/// next to each other in the type system.
nonisolated enum ArgmaxOSSWhisperFactory {
    /// The production ``WhisperEngineFactory``. Constructs a real
    /// `WhisperKit` instance using the variant's raw model identifier and
    /// wraps it in ``ArgmaxOSSWhisperEngine``. Any error thrown by
    /// `WhisperKit.init` propagates unchanged; the loader is responsible
    /// for translating it into ``TranscriptionError/modelLoadFailed(_:)``.
    static let make: WhisperEngineFactory = { variant in
        let kit = try await WhisperKit(model: variant.rawValue)
        return ArgmaxOSSWhisperEngine(kit: kit)
    }
}
