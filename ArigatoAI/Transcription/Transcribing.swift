//
//  Transcribing.swift
//  ArigatoAI
//
//  Created by Jose Castell on 2026/05/09.
//

import Foundation

/// Lifecycle state of a Whisper-backed transcriber.
///
/// The states are observed by UI to gate the record button: while
/// ``cold`` or ``warming``, the user should be informed that the model is
/// not yet ready; ``ready`` permits transcription; ``failed`` carries a
/// ``TranscriptionError`` for diagnostic display.
public nonisolated enum WarmupState: Sendable, Equatable {
    /// The transcriber has not yet been warmed up.
    case cold

    /// A warmup is in progress.
    case warming

    /// The model is loaded and a dummy inference has been run; subsequent
    /// transcription calls will not pay cold-start cost.
    case ready

    /// Warmup failed. The associated error carries the underlying detail.
    case failed(TranscriptionError)
}

/// Minimal protocol describing the transcription surface the rest of the
/// app depends on. Concrete conformers wrap Whisper; tests inject a fake to
/// drive the pipeline without booting Core ML.
///
/// The protocol mirrors ``AudioCapturing`` so the same dependency-injection
/// pattern used in Phase 3 carries over. Conformers are typically actors
/// to isolate the underlying Whisper client (which is not `Sendable` in
/// WhisperKit v1.0.0).
public protocol Transcribing: Sendable {
    /// Loads the Whisper model and runs a dummy inference to defeat
    /// cold-start latency.
    ///
    /// Idempotent: conformers must coalesce concurrent calls. Calling
    /// ``warmup()`` after a successful warmup is a no-op; calling it after
    /// a failed warmup retries.
    ///
    /// - Throws: ``TranscriptionError`` on load or pre-warm failure.
    func warmup() async throws

    /// Returns the current ``WarmupState``. Cheap to call; safe to poll
    /// from UI on every render pass.
    func warmupState() async -> WarmupState

    /// Begins transcribing audio frames from `frames`.
    ///
    /// The conformer drains `frames` until it finishes or ``cancel()`` is
    /// called. Errors are delivered via the throwing stream rather than
    /// thrown synchronously. Conformers throw only ``TranscriptionError``;
    /// a non-`TranscriptionError` observed downstream is a contract
    /// violation.
    ///
    /// - Parameter frames: The upstream audio frame stream produced by
    ///   ``AudioCaptureActor`` or a test fake.
    /// - Returns: A throwing async stream of ``TranscriptSegment`` values.
    func transcribe(
        frames: AsyncStream<AudioFrame>
    ) async -> AsyncThrowingStream<TranscriptSegment, any Error>

    /// Cancels in-flight transcription.
    ///
    /// After ``cancel()`` returns, the stream finishes normally; in-flight
    /// transcriptions are dropped without delivery. `CancellationError` is
    /// not thrown.
    func cancel() async
}
