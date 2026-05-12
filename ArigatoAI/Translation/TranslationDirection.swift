//
//  TranslationDirection.swift
//  ArigatoAI
//
//  Created by Jose Castell on 2026/05/12.
//

import Foundation

/// The direction of a single translation request.
///
/// LFM2-350M-ENJP-MT is a single-turn, direction-locked translator: the
/// system prompt that initialises the conversation declares the target
/// language and must not be switched mid-turn. ``TranslationDirection``
/// captures that contract at the type level so callers cannot accidentally
/// route a Japanese segment through the English-output prompt or vice
/// versa.
///
/// The raw value is `"jaToEn"` / `"enToJa"` so the enum can be persisted to
/// SwiftData or JSON without a custom `Codable` implementation.
public nonisolated enum TranslationDirection: String, Sendable, Hashable, CaseIterable, Codable {
    /// Translate from Japanese source to English target.
    case jaToEn

    /// Translate from English source to Japanese target.
    case enToJa

    /// The system prompt that LFM2-350M-ENJP-MT requires for this direction.
    ///
    /// Verbatim from the HuggingFace model card
    /// (https://huggingface.co/LiquidAI/LFM2-350M-ENJP-MT). The model card
    /// explicitly warns: "The model cannot work as intended without one of
    /// these system prompts." Treat these strings as part of the locked
    /// contract — they are not configuration.
    public var systemPrompt: String {
        switch self {
        case .jaToEn: return "Translate to English."
        case .enToJa: return "Translate to Japanese."
        }
    }

    /// The source language of this direction.
    public var source: SpokenLanguage {
        switch self {
        case .jaToEn: return .ja
        case .enToJa: return .en
        }
    }

    /// The target language of this direction.
    public var target: SpokenLanguage {
        switch self {
        case .jaToEn: return .en
        case .enToJa: return .ja
        }
    }

    /// Returns the canonical translation direction for the given source
    /// language.
    ///
    /// ``SpokenLanguage`` is intentionally closed-set (Japanese and English
    /// only — see Phase 4 design), so the mapping is total and the return
    /// type is non-optional.
    ///
    /// - Parameter source: The detected source language.
    /// - Returns: The translation direction that targets the other language.
    public static func from(source: SpokenLanguage) -> TranslationDirection {
        switch source {
        case .ja: return .jaToEn
        case .en: return .enToJa
        }
    }
}

/// Generation hyperparameters for LFM2-350M-ENJP-MT inference.
///
/// Values are pinned per the LFM2-350M-ENJP-MT HuggingFace model card. The
/// type exists so callers can override individual parameters for
/// experimentation without rebuilding the recommended defaults from
/// scratch; production code should pass ``recommended`` unless there is a
/// specific reason to deviate.
public nonisolated struct TranslationGenerationParameters: Sendable, Hashable, Codable {
    /// Sampling temperature. Lower values make the model more deterministic;
    /// higher values widen the sampling distribution.
    public let temperature: Double

    /// Nucleus-sampling cumulative-probability cutoff. The next token is
    /// sampled from the smallest set whose cumulative probability exceeds
    /// this value.
    public let topP: Double

    /// Minimum-probability cutoff. Tokens below this probability relative to
    /// the most likely token are filtered out before sampling.
    public let minP: Double

    /// Multiplicative penalty applied to tokens that have appeared earlier
    /// in the generation, discouraging repetition loops.
    public let repetitionPenalty: Double

    /// Creates a generation-parameter bundle.
    ///
    /// - Parameters:
    ///   - temperature: Sampling temperature.
    ///   - topP: Nucleus-sampling cumulative-probability cutoff.
    ///   - minP: Minimum-probability cutoff.
    ///   - repetitionPenalty: Multiplicative repetition penalty.
    public init(
        temperature: Double,
        topP: Double,
        minP: Double,
        repetitionPenalty: Double
    ) {
        self.temperature = temperature
        self.topP = topP
        self.minP = minP
        self.repetitionPenalty = repetitionPenalty
    }

    /// The maintainer-recommended defaults for LFM2-350M-ENJP-MT.
    ///
    /// Sourced verbatim from the HuggingFace model card. Group A's
    /// `TranslationDirectionTests.recommendedGenerationParameters_carryLockedValues`
    /// locks these values so accidental edits surface as test failures.
    public static let recommended = TranslationGenerationParameters(
        temperature: 0.5,
        topP: 1.0,
        minP: 0.1,
        repetitionPenalty: 1.05
    )
}
