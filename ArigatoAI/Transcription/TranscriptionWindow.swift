//
//  TranscriptionWindow.swift
//  ArigatoAI
//
//  Created by Jose Castell on 2026/05/10.
//

import Foundation

/// One Whisper inference call's output, anchored in host time.
///
/// `TranscriptionWindow` is the unit of work `TranscriptionActor` (Step 9)
/// emits to its downstream consumer. Each value corresponds to exactly one
/// invocation of ``WhisperClient/transcribe(audio:anchorHostTime:)``. The
/// actor owns the rolling buffer, decides when to start a window, calls
/// the client, then wraps the result up here for the language router
/// (Step 11) to consume.
///
/// **Locked contracts** (see Phase 4 plan):
///
/// - **C9** — `TranscriptionActor.windowStream(frames:)` emits one
///   ``TranscriptionWindow`` per hop boundary once the rolling buffer
///   first reaches the window length.
/// - **C11** — At end of stream, the actor flushes a final
///   ``TranscriptionWindow`` with ``isFinal`` set when the leftover
///   buffer is at least 0.5 s.
/// - **C15** — ``windowAnchorHostTime`` is the host time of sample 0 of
///   the audio array passed to the client for this call. It is
///   round-tripped from ``WhisperWindowResult/windowAnchorHostTime``,
///   which the adapter copies verbatim from its `anchorHostTime`
///   argument (contract **C17**).
///
/// The struct is `Sendable` so it can cross from the actor into the
/// throwing async stream's continuation, and `Equatable` for ergonomic
/// test assertions.
///
/// `nonisolated` is applied explicitly because the project sets
/// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`. Without it, the type
/// would default to main-actor isolation, which would prevent
/// ``TranscriptionActor`` (a non-main actor) from constructing values of
/// it during inference.
nonisolated struct TranscriptionWindow: Equatable {
    /// The language Whisper reported for this window after parsing the
    /// raw tag through ``SpokenLanguage/init(whisperCode:)``.
    ///
    /// `nil` when WhisperKit returned a code outside the supported
    /// `{ja, en}` set, including the empty string. The actor passes this
    /// value through verbatim — disagreement gating (Decision 5) is the
    /// language router's job, not the actor's.
    let detectedLanguage: SpokenLanguage?

    /// Mach host time of the first sample of the audio array passed to
    /// ``WhisperClient/transcribe(audio:anchorHostTime:)`` for this
    /// window. Same clock as `AudioFrame.hostTime` (contract **C15**).
    let windowAnchorHostTime: UInt64

    /// Seconds offset of the first sample of the audio array, measured
    /// from the start of the recording session as represented by the
    /// rolling buffer. The actor sets this from the offset between the
    /// session start and the window's anchor.
    let windowStartSeconds: Double

    /// Seconds offset of the last sample of the audio array, measured
    /// the same way as ``windowStartSeconds``.
    let windowEndSeconds: Double

    /// Per-segment Whisper output for this window, value-typed for
    /// `Sendable` transit. Empty arrays are legal for silence-only
    /// windows.
    let segments: [WhisperRawSegment]

    /// `false` for steady-state hops where the right edge is still
    /// inside the rolling buffer; `true` for the end-of-stream flush
    /// (contract **C11**).
    let isFinal: Bool
}
