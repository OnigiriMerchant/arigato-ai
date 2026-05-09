//
//  SpokenLanguage.swift
//  ArigatoAI
//
//  Created by Jose Castell on 2026/05/09.
//

import Foundation

/// The set of spoken languages supported by the on-device transcription
/// pipeline.
///
/// Arigato AI is intentionally bilingual: only Japanese and English are
/// recognised. Any other language code reported by the underlying ASR engine
/// is treated as unsupported and rejected by ``init(whisperCode:)``.
///
/// The raw values match WhisperKit's lowercase ISO 639-1 codes (`"ja"`,
/// `"en"`), so encoding the enum and reading WhisperKit output share the
/// same wire format.
public nonisolated enum SpokenLanguage: String, Sendable, Hashable, CaseIterable, Codable {
    /// Japanese.
    case ja
    /// English.
    case en

    /// Creates a ``SpokenLanguage`` from a language code reported by Whisper.
    ///
    /// The input is lowercased and trimmed of surrounding whitespace before
    /// being matched against the raw values. Returns `nil` for any code that
    /// is not exactly `"ja"` or `"en"` after normalisation, including
    /// unsupported ISO 639-1 codes (`"fr"`, `"zh"`), ISO 639-2 codes
    /// (`"jpn"`), BCP-47 tags (`"ja-JP"`), and the empty string.
    ///
    /// - Parameter whisperCode: The language code as reported by WhisperKit.
    public init?(whisperCode: String) {
        let normalised = whisperCode
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        self.init(rawValue: normalised)
    }

    /// A human-readable English display name suitable for UI badges and
    /// logs. Distinct per case.
    public var displayName: String {
        switch self {
        case .ja: return "Japanese"
        case .en: return "English"
        }
    }

    /// The BCP-47 locale identifier corresponding to this language. Useful
    /// when handing off text to system APIs that expect a region-qualified
    /// locale (speech synthesis, locale-aware formatting).
    public var bcp47: String {
        switch self {
        case .ja: return "ja-JP"
        case .en: return "en-US"
        }
    }
}
