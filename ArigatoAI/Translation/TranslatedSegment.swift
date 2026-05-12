//
//  TranslatedSegment.swift
//  ArigatoAI
//
//  Created by Jose Castell on 2026/05/12.
//

import Foundation

/// A single completed translation ready for persistence or UI rendering.
///
/// `TranslatedSegment` is the unit of work produced by the translation
/// pipeline once LFM2 emits its `.complete` event for an upstream
/// ``TranscriptSegment``. Values flow downstream as the payload of
/// ``TranslationEvent/completed(_:)``.
///
/// LFM2-350M-ENJP-MT is a single-turn translator: once a translation
/// completes there is no preliminary-vs-final distinction (contrast with
/// ``TranscriptSegment/isFinal``), so this type has no `isFinal` field.
/// Likewise, ``direction`` encodes both source and target language, so a
/// separate `language` field would be redundant.
///
/// ``sourceSegmentID`` is the identity of the originating
/// ``TranscriptSegment``, retained so the UI can match translated text back
/// to the transcript row that produced it and so downstream consumers can
/// de-duplicate when an upstream segment is re-emitted by the language
/// router.
public nonisolated struct TranslatedSegment: Sendable, Hashable, Identifiable, Codable {
    /// Stable SwiftUI identity for rendering. Defaulted to a fresh `UUID`
    /// when not supplied.
    public let id: UUID

    /// The identity of the upstream ``TranscriptSegment`` that produced
    /// this translation. The pair (`sourceSegmentID`, `direction`) is the
    /// natural de-duplication key.
    public let sourceSegmentID: UUID

    /// The text of the upstream ``TranscriptSegment`` exactly as Whisper
    /// produced it.
    public let sourceText: String

    /// The translated text as assembled from LFM2's streamed `.chunk`
    /// events at the moment its `.complete` event fired.
    public let translatedText: String

    /// The direction of this translation. Encodes both source and target
    /// language.
    public let direction: TranslationDirection

    /// Mach absolute host time of the first sample of the upstream
    /// transcript segment. Preserved here so translations can be aligned
    /// against the audio timeline without back-referencing the transcript.
    public let startHostTime: UInt64

    /// Mach absolute host time of the last sample of the upstream
    /// transcript segment.
    public let endHostTime: UInt64

    /// `true` when this translation was produced under a fallback condition
    /// (for example, the model emitted an empty completion and the
    /// pipeline substituted source text, or a future cleanup tier reused a
    /// prior translation). At Group A this flag is settable but no
    /// production conformer sets it yet — it is reserved for downstream
    /// honesty signalling, mirroring ``TranscriptSegment/wasLanguageFallback``.
    public let isFallback: Bool

    /// Creates a translated segment.
    ///
    /// - Parameters:
    ///   - id: Stable identity. Defaulted to a fresh UUID.
    ///   - sourceSegmentID: The identity of the upstream transcript segment.
    ///   - sourceText: The upstream transcript text verbatim.
    ///   - translatedText: The assembled translated text.
    ///   - direction: The translation direction.
    ///   - startHostTime: Mach host time of the first sample of the
    ///     upstream transcript segment.
    ///   - endHostTime: Mach host time of the last sample of the upstream
    ///     transcript segment.
    ///   - isFallback: Whether this translation was produced by a fallback
    ///     path rather than a normal LFM2 generation.
    public init(
        id: UUID = UUID(),
        sourceSegmentID: UUID,
        sourceText: String,
        translatedText: String,
        direction: TranslationDirection,
        startHostTime: UInt64,
        endHostTime: UInt64,
        isFallback: Bool
    ) {
        self.id = id
        self.sourceSegmentID = sourceSegmentID
        self.sourceText = sourceText
        self.translatedText = translatedText
        self.direction = direction
        self.startHostTime = startHostTime
        self.endHostTime = endHostTime
        self.isFallback = isFallback
    }
}
