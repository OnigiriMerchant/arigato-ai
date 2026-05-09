//
//  TranscriptionError.swift
//  ArigatoAI
//
//  Created by Jose Castell on 2026/05/09.
//

import Foundation

/// Errors thrown by the transcription pipeline (model loader, transcription
/// actor, and language router).
///
/// Underlying system errors are stringified rather than wrapped so the type
/// can be `Sendable` and `Equatable` without leaking non-`Sendable`
/// `NSError` references into actor messages. The pattern mirrors
/// ``AudioCaptureError`` for consistency.
public nonisolated enum TranscriptionError: Error, Sendable, Equatable {
    /// Loading the Whisper model from disk or downloading its assets failed.
    /// The associated string carries the underlying detail for diagnostics.
    case modelLoadFailed(String)

    /// A transcription call was issued before the model finished warming up.
    /// Callers should observe ``WarmupState`` and wait for ``WarmupState/ready``.
    case modelNotReady

    /// Whisper accepted the audio window but failed to decode it. The
    /// associated string carries the underlying detail for diagnostics.
    case decodeFailed(String)

    /// The rolling audio buffer ran dry mid-window. Typically indicates the
    /// upstream `AudioFrame` stream was cancelled or the producer fell
    /// behind the consumer.
    case bufferUnderrun

    /// The upstream `AsyncStream<AudioFrame>` finished while the actor was
    /// mid-window. Distinguished from ``bufferUnderrun`` because it is the
    /// expected terminal state at end-of-recording rather than a fault.
    case audioStreamEnded

    /// An audio frame arrived at a sample rate the transcriber cannot
    /// process. Whisper requires 16 kHz; any other rate is fatal to the
    /// current session.
    case unsupportedSampleRate(Double)
}

extension TranscriptionError: LocalizedError {
    /// Human-readable description suitable for logs and diagnostic UI.
    public var errorDescription: String? {
        switch self {
        case let .modelLoadFailed(detail):
            return "Whisper model failed to load: \(detail)"
        case .modelNotReady:
            return "Whisper model is not ready; warmup has not completed."
        case let .decodeFailed(detail):
            return "Whisper decode failed: \(detail)"
        case .bufferUnderrun:
            return "Audio buffer underrun while assembling a transcription window."
        case .audioStreamEnded:
            return "Audio stream ended before transcription completed."
        case let .unsupportedSampleRate(rate):
            return "Unsupported audio sample rate: \(rate) Hz (expected 16000 Hz)."
        }
    }
}
