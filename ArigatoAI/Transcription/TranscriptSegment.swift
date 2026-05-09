//
//  TranscriptSegment.swift
//  ArigatoAI
//
//  Created by Jose Castell on 2026/05/09.
//

import Foundation

/// A single segment of transcribed speech ready for downstream translation,
/// persistence, or UI rendering.
///
/// `TranscriptSegment` is the unit of work produced by the language router
/// after consuming raw Whisper output and applying the consecutive-window
/// disagreement fallback policy. Values flow through the pipeline as
/// `AsyncStream<TranscriptSegment>`.
///
/// Timestamp duality: each segment carries both mach `hostTime` boundaries
/// and seconds-relative boundaries. The router computes one from the other
/// using the host time of sample 0 in the audio array passed to Whisper, so
/// the two representations are always consistent.
///
/// Final vs. preliminary: while a window's right edge is still inside the
/// rolling buffer, the segment may be re-emitted with corrected text on the
/// next hop. ``isFinal`` distinguishes this case so consumers can either
/// replace earlier preliminary copies or wait for the final value.
public nonisolated struct TranscriptSegment: Sendable, Hashable, Identifiable, Codable {
    /// Stable SwiftUI identity for rendering. Defaulted to a fresh `UUID`
    /// when not supplied. NOT used for de-duplication across windows — the
    /// language router de-duplicates on text and timestamp before assigning
    /// an id.
    public let id: UUID

    /// The transcribed text exactly as Whisper produced it. An empty string
    /// is legal at this layer and is left to the consumer to filter.
    public let text: String

    /// The effective language for this segment after the language router's
    /// fallback policy has run. May differ from the language Whisper
    /// reported for the underlying window when ``wasLanguageFallback`` is
    /// `true`.
    public let language: SpokenLanguage

    /// Mach absolute host time of the first sample of this segment. Anchored
    /// to the same clock as `AudioFrame.hostTime`, so consumers can align
    /// segments with raw audio frames or other host-time-based clocks.
    public let startHostTime: UInt64

    /// Mach absolute host time of the last sample of this segment. Anchored
    /// to the same clock as `AudioFrame.hostTime`.
    public let endHostTime: UInt64

    /// Seconds offset of the first sample, measured from the start of the
    /// audio array passed to Whisper for this window. Always consistent with
    /// ``startHostTime`` — the router computes one from the other.
    public let startSeconds: Double

    /// Seconds offset of the last sample, measured from the start of the
    /// audio array passed to Whisper for this window. Always consistent with
    /// ``endHostTime``.
    public let endSeconds: Double

    /// `false` while the window's right edge is still inside the rolling
    /// buffer (segment may be re-emitted with corrected text on the next
    /// hop); `true` when the window has slid past it and no further
    /// revision is possible.
    public let isFinal: Bool

    /// Set by `LanguageRouter` when its consecutive-disagreement gate held
    /// the previous language because Whisper reported a different language
    /// for the underlying window. This is the sole honesty signal the
    /// pipeline can offer — WhisperKit v1.0.0 does not surface per-segment
    /// confidence values.
    public let wasLanguageFallback: Bool

    /// Creates a transcript segment.
    ///
    /// - Parameters:
    ///   - id: Stable identity. Defaulted to a fresh UUID.
    ///   - text: Whisper's transcribed text verbatim.
    ///   - language: Effective language after router fallback policy.
    ///   - startHostTime: Mach host time of the first sample.
    ///   - endHostTime: Mach host time of the last sample.
    ///   - startSeconds: Seconds offset of the first sample.
    ///   - endSeconds: Seconds offset of the last sample.
    ///   - isFinal: Whether the segment is final or still subject to
    ///     revision on the next hop.
    ///   - wasLanguageFallback: Whether the language was held by the
    ///     router's disagreement gate.
    public init(
        id: UUID = UUID(),
        text: String,
        language: SpokenLanguage,
        startHostTime: UInt64,
        endHostTime: UInt64,
        startSeconds: Double,
        endSeconds: Double,
        isFinal: Bool,
        wasLanguageFallback: Bool
    ) {
        self.id = id
        self.text = text
        self.language = language
        self.startHostTime = startHostTime
        self.endHostTime = endHostTime
        self.startSeconds = startSeconds
        self.endSeconds = endSeconds
        self.isFinal = isFinal
        self.wasLanguageFallback = wasLanguageFallback
    }
}
