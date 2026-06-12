//
//  WhisperClient.swift
//  ArigatoAI
//
//  Created by Jose Castell on 2026/05/10.
//

import Foundation

/// One Whisper segment as surfaced by the underlying ASR adapter, mapped
/// to value-typed primitives the rest of the pipeline can treat as
/// `Sendable`.
///
/// The fields mirror WhisperKit v1.0.0's `TranscriptionSegment`, but with
/// two intentional shape differences:
///
/// 1. `Float`-typed time fields (`start`, `end`) and `avgLogprob` are
///    widened to `Double` here so downstream code never has to think
///    about precision loss when combining segment offsets with the host
///    clock (which is `UInt64`/`Double`-based).
/// 2. The names `startSeconds` and `endSeconds` make the unit explicit
///    at the call site. WhisperKit's `start` / `end` are also seconds,
///    but the names alone do not say so — the rename is contract
///    documentation, not a unit conversion.
///
/// **C18 (locked).** `startSeconds` and `endSeconds` are relative to the
/// start of the audio array passed into
/// ``WhisperClient/transcribe(audio:anchorHostTime:)``, **not** absolute
/// host time. Callers that need an absolute timestamp must combine these
/// offsets with ``WhisperWindowResult/windowAnchorHostTime`` themselves.
///
/// `avgLogprob` is passed through unchanged. WhisperKit may emit
/// `-Float.infinity` or `NaN` for degenerate windows; this type does not
/// sanitize those values. No Group C consumer reads this field, so the
/// pass-through is documentation-only for now.
nonisolated struct WhisperRawSegment: Equatable {
    /// Recognised text for this segment. May be empty for silence-only
    /// windows.
    let text: String

    /// Segment start, in seconds, relative to the start of the audio
    /// array supplied to ``WhisperClient/transcribe(audio:anchorHostTime:)``.
    let startSeconds: Double

    /// Segment end, in seconds, relative to the start of the audio array
    /// supplied to ``WhisperClient/transcribe(audio:anchorHostTime:)``.
    let endSeconds: Double

    /// Average per-token log probability reported by WhisperKit.
    /// Pass-through; can be `-.infinity` or `.nan` for degenerate windows.
    let avgLogprob: Double
}

/// Result of transcribing a single sliding window of audio.
///
/// Bundles the language tag WhisperKit reported for the window, the
/// host-time anchor of the first sample in the window (so the router can
/// place the result on the absolute clock), and the per-segment output.
///
/// **C17 (locked).** ``windowAnchorHostTime`` equals the
/// `anchorHostTime` argument passed to
/// ``WhisperClient/transcribe(audio:anchorHostTime:)`` verbatim — the
/// adapter must not synthesise, round-trip, or "improve" this value.
///
/// The ``language`` field is the raw string WhisperKit returned. It now
/// reflects an explicitly-requested detection pass: the production adapter
/// transcribes with `detectLanguage: true` (see
/// ``ArgmaxOSSWhisperClient/decodeOptions()``), so the tag is the language
/// WhisperKit *detected* for the window rather than WhisperKit v1.0.0's
/// default forced-`<|en|>` prefill. It can still be an empty string when
/// the detector falls back; the router (Step 11) is responsible for parsing
/// it via ``SpokenLanguage/init(whisperCode:)`` and deciding the
/// disagreement gating outcome. Adapters must **never** substitute
/// `"en"`/`"ja"` for an empty value or inject a default of their own — the
/// adapter forwards the detection result, it does not detect.
nonisolated struct WhisperWindowResult: Equatable {
    /// Language tag reported by WhisperKit for this window. Pass-through
    /// of an explicitly-requested detection pass (`detectLanguage: true`);
    /// may be `""` when the underlying detector fell back, which the router
    /// treats as a no-op. Routing logic lives in ``SpokenLanguage`` and the
    /// language router (Step 11), not here.
    let language: String

    /// Mach host time of the first sample of the audio window passed to
    /// ``WhisperClient/transcribe(audio:anchorHostTime:)``. Round-tripped
    /// from the caller verbatim per contract **C17**.
    let windowAnchorHostTime: UInt64

    /// Segments WhisperKit produced for the window. Empty arrays are
    /// legal and represent silence-only or otherwise-empty windows.
    let segments: [WhisperRawSegment]
}

/// Internal seam isolating the Whisper-backed transcriber behind a
/// `Sendable` protocol that ``WhisperModelLoader`` and downstream
/// pipeline actors can hold safely.
///
/// `WhisperClient` extends ``WhisperEngine`` (which carries the pre-warm
/// entry point) with a single transcription method: callers hand in an
/// audio window plus the host-time anchor of its first sample, and the
/// adapter returns a fully value-typed ``WhisperWindowResult`` ready for
/// the router and persistence layers.
///
/// ## Window enforcement
///
/// Per Phase 4 Decision 4 the production window is 5 seconds @ 16 kHz
/// mono. **The protocol does not enforce that contract** — the adapter
/// transcribes whatever `[Float]` it receives. Window-size validation is
/// the responsibility of `TranscriptionActor` (Step 9), which constructs
/// the windows from the rolling buffer in the first place.
///
/// ## Why no language-detection method
///
/// WhisperKit v1.0.0 exposes both `detectLangauge(audioArray:)`
/// (misspelled, takes float audio) and `detectLanguage(audioPath:)`
/// (correctly spelled, takes a file path). They are two distinct public
/// methods, not one method with a typo waiting to be patched.
///
/// We omit both from this protocol intentionally. Phase 4 Decision 5
/// uses **consecutive-window disagreement gating** (N=2) on the language
/// tag returned alongside each window, not pre-detection on a separate
/// audio buffer. If a future caller needs in-memory language detection,
/// the misspelled selector should be isolated inside the adapter and
/// re-exposed under a corrected name on this protocol — not surfaced
/// through `any WhisperClient` with the WhisperKit typo intact.
protocol WhisperClient: WhisperEngine {
    /// Transcribes a single audio window and returns the language tag,
    /// host-time anchor, and per-segment output.
    ///
    /// - Parameters:
    ///   - audio: 16 kHz mono `Float32` PCM samples, in append order.
    ///     The adapter does **not** validate sample rate or window
    ///     length; that is `TranscriptionActor`'s job.
    ///   - anchorHostTime: Mach host time of the first sample of `audio`,
    ///     sourced from the rolling buffer's anchor. Round-tripped onto
    ///     the returned ``WhisperWindowResult/windowAnchorHostTime``
    ///     verbatim (contract **C17**).
    /// - Returns: A ``WhisperWindowResult`` bundling the WhisperKit
    ///   language tag, the round-tripped anchor, and the segments.
    /// - Throws: Underlying adapter errors. The loader / transcription
    ///   actor wraps these into ``TranscriptionError`` for the rest of
    ///   the app.
    func transcribe(
        audio: [Float],
        anchorHostTime: UInt64
    ) async throws -> WhisperWindowResult
}
