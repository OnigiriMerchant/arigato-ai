//
//  TranslationError.swift
//  ArigatoAI
//
//  Created by Jose Castell on 2026/05/12.
//

import Foundation

/// Errors thrown by the translation pipeline (LFM2 model loader and
/// translation actor).
///
/// Underlying system errors are stringified rather than wrapped so the type
/// can be `Sendable` and `Equatable` without leaking non-`Sendable`
/// `NSError` references into actor messages. The pattern mirrors
/// ``TranscriptionError`` for cross-pipeline consistency.
public nonisolated enum TranslationError: Error, Sendable, Equatable {
    /// Loading the LFM2 model from disk or downloading its assets failed.
    /// The associated string carries the underlying detail for diagnostics.
    case modelLoadFailed(String)

    /// A translation call was issued before the model finished warming up.
    /// Callers should observe ``TranslationWarmupState`` and wait for
    /// ``TranslationWarmupState/ready``.
    case modelNotReady

    /// LFM2 accepted the input but failed to produce a complete translation.
    /// The associated string carries the underlying detail for diagnostics.
    case generationFailed(String)

    /// A translation call was issued while a previous translation was still
    /// generating tokens. The protocol guarantees serial-per-conformer
    /// processing; conformers raise this when callers violate that
    /// expectation directly (rather than via the upstream segment stream).
    case overlappingGenerationRejected

    /// The translator was asked to translate from a source language to a
    /// target language that does not match one of the supported directions.
    /// The closed-set ``SpokenLanguage`` makes this case unreachable in
    /// practice; it exists so future expansions of the language set can
    /// surface the boundary cleanly.
    case unsupportedDirection(source: SpokenLanguage, target: SpokenLanguage)

    /// Warmup completed the load step but the post-load dummy inference
    /// failed. The associated string carries the underlying detail.
    case warmupFailed(String)

    /// The LFM2 cache directory path could not be resolved from the OS Caches
    /// directory. In practice this should never fire on a sandboxed iOS process
    /// — `FileManager.urls(for: .cachesDirectory, in: .userDomainMask)` always
    /// returns at least one URL — but the explicit case avoids a force-unwrap
    /// in the resolver and gives the caller a typed error to react to. The
    /// associated string carries the underlying detail for diagnostics.
    case cachePathResolutionFailed(String)
}

extension TranslationError: LocalizedError {
    /// Human-readable description suitable for logs and diagnostic UI.
    public var errorDescription: String? {
        switch self {
        case let .modelLoadFailed(detail):
            return "Failed to load LFM2 model: \(detail)"
        case .modelNotReady:
            return "Translation requested before model warmup completed."
        case let .generationFailed(detail):
            return "Translation generation failed: \(detail)"
        case .overlappingGenerationRejected:
            return "Translation rejected: another generation is in flight."
        case let .unsupportedDirection(source, target):
            return "Unsupported translation direction: \(source.rawValue) to \(target.rawValue)."
        case let .warmupFailed(detail):
            return "LFM2 warmup failed: \(detail)"
        case let .cachePathResolutionFailed(detail):
            return "Failed to resolve LFM2 cache directory path: \(detail)"
        }
    }
}
