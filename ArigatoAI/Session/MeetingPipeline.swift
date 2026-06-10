//
//  MeetingPipeline.swift
//  ArigatoAI
//
//  Created by Jose Castell on 2026/05/16.
//

import Foundation
import os

/// The realtime pipeline coordinator that bridges
/// ``LanguageRouter`` → ``Translating`` → ``MeetingSession``.
///
/// `MeetingPipeline` owns the lifetime of the segment-to-translation
/// bridge while a meeting is recording. It subscribes to
/// ``LanguageRouter/transcribe(frames:)``, derives the translation
/// direction from the **first** ``TranscriptSegment`` it observes (D4-C
/// "lazy first-segment direction"), invokes
/// ``Translating/translate(segments:direction:)`` with that direction, and
/// feeds the resulting ``TranslationEvent`` stream into
/// ``MeetingSession/consumeTranslationEvents(_:)``.
///
/// ## D4-C cancel-and-restart on language flip
///
/// LFM2-350M-ENJP-MT is direction-locked (see
/// ``TranslationDirection``); switching mid-translation is impossible.
/// When the router emits a segment whose
/// ``TranscriptSegment/language`` differs from the active direction's
/// source, the pipeline:
///
/// 1. Finishes the current per-direction routed
///    `AsyncStream<TranscriptSegment>`'s continuation.
/// 2. `await`s `translator.cancel()` so the stale ``TranslationActor``
///    session is torn down before the new one starts.
/// 3. Builds a fresh `(AsyncStream<TranscriptSegment>, continuation)`
///    pair.
/// 4. Re-invokes ``Translating/translate(segments:direction:)`` with the
///    new direction.
/// 5. Hands the new ``TranslationEvent`` stream to
///    ``MeetingSession/consumeTranslationEvents(_:)`` — which itself
///    cancels its previous consumer task and replaces it (Step 3
///    contract).
///
/// Trust the router's N=2 disagreement gate
/// (``LanguageRouter/confirmationsRequired``) — by the time a segment
/// reaches us with a flipped ``TranscriptSegment/language``, the gate
/// has already required two consecutive disagreeing windows. No
/// additional flip suppression lives here.
///
/// ## Concurrency design discipline — scheduling assumptions
///
/// 1. **Single-producer, single-consumer over the routed segment
///    stream.** The pipeline drives at most one
///    `AsyncStream<TranscriptSegment>` continuation at a time. A
///    second ``start(frames:)`` call cancels the prior pipeline task,
///    awaits cancellation propagation to router and translator, and
///    only then starts the new pipeline. Named violation test:
///    `pipeline_secondStart_cancelsFirstAndReplacesCleanly`.
///
/// 2. **Direction flips manifest as cancel + restart on the
///    translator.** A flip closes the current routed segment stream and
///    `await`s `translator.cancel()` before invoking
///    `translate(segments:direction:)` with the new direction. Named
///    violation test:
///    `pipeline_languageFlipMidStream_triggersTranslatorCancelAndRestart_withCorrectDirection`.
///
/// 3. **Upstream-error propagation is asymmetric.** When the router's
///    transcribe stream throws (typically a ``TranscriptionError``),
///    the pipeline clears its in-memory state and exits silently. It
///    does **NOT** call ``MeetingSession/finalizeStop(at:)`` — the
///    meeting's lifecycle is owned by the session and finalisation
///    only happens via the UI-driven STOP path. Named violation test:
///    `pipeline_upstreamThrowsTranscriptionError_clearsStateWithoutCallingFinalizeStop`.
///
/// ## State machine
///
/// ```
/// state ::= idle | running(direction)
/// idle --(first segment)--> running(direction from segment.language)
/// running(d) --(segment.language != d.source)--> [cancel translator] --> running(new d)
/// running(d) --(stop called)--> [cancel pipelineTask, router, translator] --> idle
/// running(d) --(upstream throws)--> idle (state cleared, NO finalizeStop)
/// ```
///
/// ## Wiring deferred to Step 5
///
/// `MeetingPipeline` is constructed and bound to a meeting's lifecycle
/// by an outer wiring layer landing in Step 5. Step 4 ships the
/// coordinator itself plus its 10 tests; it does **not** modify
/// `AppBootstrapper`, `AudioCaptureViewModel`, or any other production
/// type.
@MainActor
final class MeetingPipeline {
    // MARK: - Dependencies

    private let router: LanguageRouter
    private let translator: any Translating
    private let session: MeetingSession

    // MARK: - Active-pipeline state

    /// The task that drives the routed-segment loop. Cancelled by
    /// ``stop()`` and replaced by a second ``start(frames:)``.
    private var pipelineTask: Task<Void, Never>?

    // MARK: - Init

    /// Creates a new pipeline coordinator.
    ///
    /// - Parameters:
    ///   - router: The language router that owns the
    ///     ``Transcribing`` surface for one meeting.
    ///   - translator: The ``Translating`` conformer (typically
    ///     ``TranslationActor`` in production; a recording fake in
    ///     tests).
    ///   - session: The ``MeetingSession`` orchestrator that consumes
    ///     translation events.
    init(router: LanguageRouter, translator: any Translating, session: MeetingSession) {
        self.router = router
        self.translator = translator
        self.session = session
    }

    // MARK: - Public API

    /// Subscribes to ``LanguageRouter/transcribe(frames:)`` and drives
    /// the segment → translation → session pipeline.
    ///
    /// The pipeline derives translation direction lazily from the
    /// first ``TranscriptSegment`` observed (D4-C). Each subsequent
    /// segment whose ``TranscriptSegment/language`` matches the active
    /// direction's source is forwarded to the active translator
    /// session. A segment whose language differs from the active
    /// direction triggers a cancel-and-restart on the translator with
    /// the new direction (see the type-level "D4-C" section).
    ///
    /// ## Single-pipeline invariant
    ///
    /// At most one pipeline runs at a time. A second ``start(frames:)``
    /// call cancels the prior `pipelineTask`, then proceeds to start
    /// the new one with the supplied frame stream. Router and
    /// translator cancellation are awaited before the replacement
    /// starts so the new pipeline sees a clean translator session.
    ///
    /// ## Scheduling assumption — named violation tests
    ///
    /// - `pipeline_secondStart_cancelsFirstAndReplacesCleanly`
    /// - `pipeline_languageFlipMidStream_triggersTranslatorCancelAndRestart_withCorrectDirection`
    /// - `pipeline_greedyUpstreamSegments_doesNotDeadlockOrLoseEvents`
    ///
    /// - Parameter frames: The audio frame stream from
    ///   `AudioCaptureActor`. The pipeline does not own this stream's
    ///   lifecycle — its producer terminates it via
    ///   `continuation.finish()` or by tearing down the actor.
    func start(frames: AsyncStream<AudioFrame>) async {
        // Cancel-and-replace: at most one pipelineTask in flight.
        if let prior = pipelineTask {
            prior.cancel()
            await router.cancel()
            await translator.cancel()
            // Await prior task's exit so a second start truly replaces.
            _ = await prior.value
        }
        pipelineTask = nil

        let segmentStream = await router.transcribe(frames: frames)
        pipelineTask = Task { [weak self] in
            await self?.drive(segments: segmentStream)
        }
    }

    /// Cancels the pipeline task, then `await`s router cancel,
    /// then `await`s translator cancel — in that order.
    ///
    /// Idempotent: a second call after the pipeline has already been
    /// torn down is a no-op (the prior `pipelineTask` is already
    /// `nil`).
    ///
    /// ## Scheduling assumption — named violation tests
    ///
    /// - `pipeline_stop_awaitsRouterCancelThenTranslatorCancel_inOrder`
    /// - `pipeline_stop_isIdempotent_secondCallIsNoOp`
    func stop() async {
        guard let task = pipelineTask else {
            // Idempotent: already stopped, or never started.
            return
        }
        task.cancel()
        await router.cancel()
        await translator.cancel()
        _ = await task.value
        pipelineTask = nil
    }

    // MARK: - Pipeline driver

    /// Drives the routed-segment loop on the main actor.
    ///
    /// Maintains a single active per-direction
    /// `AsyncStream<TranscriptSegment>` plus its continuation. On a
    /// direction change, the continuation is finished, the translator
    /// is cancelled, and a fresh pair is built before the next segment
    /// is forwarded. On upstream termination (normal finish), the
    /// active continuation is finished cleanly. On upstream error, the
    /// continuation is finished and state cleared — `finalizeStop` is
    /// **not** invoked.
    private func drive(
        segments routerStream: AsyncThrowingStream<TranscriptSegment, any Error>
    ) async {
        var activeDirection: TranslationDirection?
        var activeContinuation: AsyncStream<TranscriptSegment>.Continuation?

        do {
            for try await segment in routerStream {
                if Task.isCancelled {
                    activeContinuation?.finish()
                    return
                }
                let segmentDirection = TranslationDirection.from(source: segment.language)
                if activeDirection == nil {
                    // First segment: establish direction.
                    Self.log.notice("Pipeline first segment arrived (direction: \(String(describing: segmentDirection), privacy: .public))")
                    let (newStream, newCont) = AsyncStream<TranscriptSegment>.makeStream()
                    activeDirection = segmentDirection
                    activeContinuation = newCont
                    let events = await translator.translate(
                        segments: newStream,
                        direction: segmentDirection
                    )
                    await session.consumeTranslationEvents(events)
                    newCont.yield(segment)
                } else if activeDirection != segmentDirection {
                    // Direction flip — cancel translator, build new
                    // routed stream, hand the new event stream to the
                    // session.
                    activeContinuation?.finish()
                    await translator.cancel()
                    let (newStream, newCont) = AsyncStream<TranscriptSegment>.makeStream()
                    activeDirection = segmentDirection
                    activeContinuation = newCont
                    let events = await translator.translate(
                        segments: newStream,
                        direction: segmentDirection
                    )
                    await session.consumeTranslationEvents(events)
                    newCont.yield(segment)
                } else {
                    // Same direction: forward to active translator.
                    activeContinuation?.yield(segment)
                }
            }
            // Upstream finished normally.
            Self.log.notice("Pipeline upstream finished normally")
            activeContinuation?.finish()
        } catch is CancellationError {
            // Pipeline task cancelled (likely from stop() or a second start()).
            Self.log.notice("Pipeline cancelled")
            activeContinuation?.finish()
        } catch {
            // Upstream error — typically TranscriptionError. Per the
            // type-level "Upstream-error propagation is asymmetric"
            // scheduling assumption, we clear state and exit
            // silently — finalizeStop is owned by the UI lifecycle,
            // not by the pipeline. The error is NOT surfaced to the UI
            // (V3 "pipeline error surfacing"); this log line is the only
            // place it becomes observable, so it stays at `.error`.
            Self.log.error("Pipeline upstream threw: \(String(describing: error), privacy: .public)")
            activeContinuation?.finish()
        }
    }

    /// Pipeline-lifecycle logging at persisted levels (`.notice`/`.error`
    /// survive into `log collect` on device). Added 2026-06-10: zero
    /// transcription on device was indistinguishable from a healthy-but-
    /// silent meeting because nothing in the segment path logged.
    private static let log = Logger(
        subsystem: "com.jose.ArigatoAI",
        category: "Pipeline"
    )
}
