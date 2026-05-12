//
//  Translating.swift
//  ArigatoAI
//
//  Created by Jose Castell on 2026/05/12.
//

import Foundation

/// Lifecycle state of an LFM2-backed translator.
///
/// The states are observed by UI to gate translation-dependent features:
/// while ``cold`` or ``warming``, the user should be informed that the
/// translator is not yet ready; ``ready`` permits translation; ``failed``
/// carries a ``TranslationError`` for diagnostic display.
///
/// Distinct from ``WarmupState`` so the transcription pipeline's lifecycle
/// can evolve independently of the translation pipeline's. The Phase 4
/// design ensured ``WarmupState/failed`` carries a ``TranscriptionError``
/// payload; mirroring that here with a ``TranslationError`` payload keeps
/// each pipeline's diagnostics typed without forcing a shared error
/// hierarchy.
public nonisolated enum TranslationWarmupState: Sendable, Equatable {
    /// The translator has not yet been warmed up.
    case cold

    /// A warmup is in progress.
    case warming

    /// The model is loaded and a dummy inference has been run; subsequent
    /// translation calls will not pay cold-start cost.
    case ready

    /// Warmup failed. The associated error carries the underlying detail.
    case failed(TranslationError)
}

/// A single event emitted by ``Translating/translate(segments:direction:)``.
///
/// LFM2 streams output token-by-token. The protocol exposes both the
/// incremental delta stream (so UI can render partial English text as it
/// arrives) and a terminal completion event carrying the assembled
/// ``TranslatedSegment``. Consumers that only care about completed
/// translations may ignore ``partialChunk(sourceSegmentID:delta:)`` events.
public nonisolated enum TranslationEvent: Sendable, Hashable {
    /// An incremental token delta for the upstream segment identified by
    /// `sourceSegmentID`. Deltas are concatenated in arrival order to form
    /// the in-progress translated text. Empty deltas are not emitted.
    case partialChunk(sourceSegmentID: UUID, delta: String)

    /// A completed translation. After this event fires for a given source
    /// segment, no further ``partialChunk(sourceSegmentID:delta:)`` events
    /// for that segment will be emitted.
    case completed(TranslatedSegment)
}

/// Minimal protocol describing the translation surface the rest of the app
/// depends on. Concrete conformers wrap an LFM2 ``Conversation`` (via the
/// LEAP iOS SDK); tests inject a fake to drive the pipeline without booting
/// the model.
///
/// The protocol mirrors ``Transcribing`` so the same dependency-injection
/// pattern carries across phases. Conformers are typically actors to
/// isolate the underlying ``Conversation`` instance (which is not
/// `Sendable` in the LEAP SDK as of v0.9.4).
public protocol Translating: Sendable {
    /// Loads the LFM2 model and runs a dummy inference to defeat cold-start
    /// latency.
    ///
    /// Idempotent: conformers must coalesce concurrent calls. Calling
    /// ``warmup()`` after a successful warmup is a no-op; calling it after
    /// a failed warmup retries.
    ///
    /// - Throws: ``TranslationError`` on load or dummy-inference failure.
    func warmup() async throws

    /// Returns the current ``TranslationWarmupState``. Cheap to call; safe
    /// to poll from UI on every render pass.
    func warmupState() async -> TranslationWarmupState

    /// Begins translating ``TranscriptSegment`` values arriving on
    /// `segments`.
    ///
    /// **Direction is fixed for the lifetime of this call.** LFM2 is a
    /// direction-locked single-turn translator (the system prompt declares
    /// the target language at conversation construction), and conformers
    /// do not switch direction mid-stream. Callers that need to switch
    /// direction must call ``cancel()`` and re-invoke
    /// ``translate(segments:direction:)`` with the new direction.
    ///
    /// **Scheduling assumption.** Conformers process upstream segments
    /// serially: at most one inflight translation per conformer. Two
    /// segments arriving simultaneously are queued FIFO and processed in
    /// arrival order; a third arriving before the first completes is also
    /// queued. The queue is unbounded at this protocol layer — bounding
    /// belongs to a higher layer (Phase 5 Group C). Conformers MAY assume
    /// the queue size stays bounded by upstream pacing; if upstream
    /// produces faster than translation drains, the in-memory queue grows
    /// without limit.
    ///
    /// **Violation of the scheduling assumption.** A greedy producer that
    /// emits multiple segments without yielding between them must still
    /// observe FIFO ``TranslationEvent/completed(_:)`` ordering matching
    /// input arrival order. Conformers must not interleave or reorder
    /// completion events.
    ///
    /// **Errors.** Conformers throw only ``TranslationError`` values onto
    /// the returned stream. A non-``TranslationError`` observed downstream
    /// is a contract violation.
    ///
    /// - Parameters:
    ///   - segments: The upstream segment stream produced by
    ///     `LanguageRouter` (Phase 4) or a test fake.
    ///   - direction: The translation direction, fixed for this call.
    /// - Returns: A throwing async stream of ``TranslationEvent`` values.
    func translate(
        segments: AsyncStream<TranscriptSegment>,
        direction: TranslationDirection
    ) async -> AsyncThrowingStream<TranslationEvent, any Error>

    /// Cancels in-flight translation.
    ///
    /// After ``cancel()`` returns, the current event stream finishes
    /// normally; any queued segments are dropped without delivery; the
    /// conformer remains usable for subsequent
    /// ``translate(segments:direction:)`` calls. `CancellationError` is
    /// not thrown.
    ///
    /// This is the **terminal-for-stream, not-for-conformer** contract.
    /// The contrast with `Task.cancel()` is intentional: a translator that
    /// becomes unusable after a single cancel would force callers to
    /// reload the LFM2 model on every direction switch, which is
    /// prohibitively expensive.
    func cancel() async
}
