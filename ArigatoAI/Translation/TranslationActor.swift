//
//  TranslationActor.swift
//  ArigatoAI
//
//  Created by Jose Castell on 2026/05/16.
//

import Foundation
import os

/// Test-seam factory closure that resolves an ``LFM2Engine`` for
/// ``TranslationActor`` without going through ``LFM2ModelLoader``.
///
/// Declared at file scope (matching the ``LFM2EngineFactory`` and
/// ``WhisperEngineFactory`` patterns from Phase 4 / Group B) so the
/// closure type has a stable named home and the test-seam initializer
/// signature stays compact.
typealias TranslationActorEngineFactory = @Sendable () async throws -> any LFM2Engine

/// Actor that owns LFM2 inference for one bidirectional translation
/// session.
///
/// **Scheduling assumption.** This actor enqueues at most one in-flight
/// LFM2 generation at a time (NOTE: LFM2 dispatch arrives in Step 7;
/// Step 6 builds the queue and timer infrastructure but does not yet
/// invoke the engine). A `Conversation` instance is created per
/// `translate(segments:direction:)` call, retained for the lifetime of
/// the active call, and never shared across calls or actors.
/// Concurrent upstream segments queue FIFO inside
/// ``Session/pendingSentences``; the queue is bounded by
/// ``maxQueuedSentences`` (20).
///
/// **Violation behavior.** When `pendingSentences.count == maxQueuedSentences`
/// and a new sentence arrives, the **newest** sentence is dropped
/// (logged via `os_log`, not silently) and the queue-cap counter
/// increments. Drop-newest diverges from ``TranscriptionActor``'s C30
/// drop-oldest policy because sentences are coarser and irrecoverable
/// once dropped, whereas audio hops are re-creatable from upstream.
/// The violation is exercised by the test
/// `C-T-VIOLATION-GREEDY-UPSTREAM` in `TranslationActorTests`.
///
/// When upstream finishes before all queued sentences are drained, the
/// drain task flushes the buffer's remaining accumulator and (Step 7+)
/// awaits inflight completion before the actor's
/// `continuation.finish()` fires.
///
/// **Cancel semantics.** ``cancel()`` cancels the drain task, the
/// timer task, finishes the continuation normally (not with
/// `CancellationError` per the ``Translating/cancel()`` contract), and
/// clears the active session. Real LFM2 generation handles are
/// cancelled in Step 8.
actor TranslationActor {
    // MARK: - Constants

    /// Maximum number of sentences retained in the pending queue
    /// before drop-newest overflow fires (Q2; C-T-VIOLATION-GREEDY-UPSTREAM).
    static let maxQueuedSentences: Int = 20

    // MARK: - Stored state

    /// The production model loader. Optional because the test-seam
    /// initializer bypasses the loader and uses an engine factory
    /// directly. Exactly one of `loader` and `engineFactory` is
    /// non-nil at any time.
    private let loader: LFM2ModelLoader?

    /// The test-seam engine factory. Bypasses the loader entirely
    /// — used by ``TranslationActorTests`` to inject a fake
    /// ``LFM2Engine`` without linking LEAP SDK or constructing a real
    /// loader.
    private let engineFactory: TranslationActorEngineFactory?

    /// Resolved engine. Cached after first successful `warmup()`.
    private var resolvedEngine: (any LFM2Engine)?

    /// In-flight warmup task. Concurrent `warmup()` callers coalesce
    /// against this task.
    private var inFlightWarmup: Task<any LFM2Engine, Error>?

    /// Current warmup state. Mutated by `warmup()` transitions and
    /// observed by `warmupState()`.
    private var currentState: TranslationWarmupState = .cold

    /// The injected clock. Production: `ContinuousClock()`. Tests
    /// inject a project-local `TestClock` so the silence-timer
    /// polling cadence is reachable without long real waits.
    ///
    /// Note: ``SentenceBuffer`` is anchored to `ContinuousClock` per
    /// Step 4's locked signature; the injected clock controls only
    /// the timer task's polling interval, not the staleness check
    /// itself.
    private let clock: any Clock<Duration>

    /// The currently active translation session, if any.
    private var session: Session?

    /// Sequence counter used to mint distinct ``SessionToken`` values
    /// so drain / timer / inflight callbacks from a prior session can
    /// be ignored once the session is replaced or cancelled.
    private var nextSessionTokenValue: UInt64 = 0

    // MARK: - #if DEBUG diagnostics

    #if DEBUG
        /// Diagnostic accessor for the violation test
        /// `C-T-VIOLATION-GREEDY-UPSTREAM`. Returns the number of
        /// sentences currently sitting in the active session's pending
        /// queue. Returns 0 if no session is active. Test-only.
        func pendingSentenceCount() -> Int {
            session?.pendingSentences.count ?? 0
        }

        /// Diagnostic accessor for the violation test. Counts how many
        /// times the queue-cap drop-newest path has fired in the active
        /// session. Returns 0 if no session is active. Test-only.
        func droppedNewestCount() -> Int {
            session?.droppedNewestCount ?? 0
        }

        /// Awaits completion of the active session's upstream-drain task.
        /// Used by tests to deterministically wait until every yielded
        /// segment has been consumed and the upstream finish-handling
        /// callback has run. No-op if no session is active. Test-only.
        func awaitUpstreamDrained() async {
            guard let drainTask = session?.drainTask else { return }
            await drainTask.value
        }
    #endif

    // MARK: - Init

    /// Production initializer. Uses the supplied ``LFM2ModelLoader``
    /// for engine resolution.
    ///
    /// - Parameters:
    ///   - loader: The shared ``LFM2ModelLoader`` whose
    ///     `loadIfNeeded(quantization:)` + `warmup()` pair drives
    ///     engine resolution.
    ///   - clock: Clock used for the silence-timer task's polling
    ///     cadence. Production callers should accept the default
    ///     (`ContinuousClock`). Tests inject `TestClock`.
    init(loader: LFM2ModelLoader, clock: any Clock<Duration> = ContinuousClock()) {
        self.loader = loader
        engineFactory = nil
        self.clock = clock
    }

    /// Test-seam initializer. Bypasses the loader entirely and
    /// resolves the engine via the supplied factory closure.
    /// Used by ``TranslationActorTests`` to inject a fake engine
    /// without constructing a real `LFM2ModelLoader` or linking
    /// LEAP SDK.
    ///
    /// - Parameters:
    ///   - engineFactory: Closure returning an ``LFM2Engine``
    ///     conformer. Invoked exactly once across all coalesced
    ///     `warmup()` callers per fresh-warmup epoch.
    ///   - clock: Clock used for the silence-timer task's polling
    ///     cadence. Tests typically inject `TestClock`.
    init(
        engineFactory: @escaping TranslationActorEngineFactory,
        clock: any Clock<Duration> = ContinuousClock()
    ) {
        loader = nil
        self.engineFactory = engineFactory
        self.clock = clock
    }

    // MARK: - Session token + Session class

    /// Opaque token minted per session for late-callback rejection.
    /// Drain / timer / inflight callbacks compare against the actor's
    /// current session token; if mismatched, the callback was
    /// scheduled by a prior session and is ignored.
    private struct SessionToken: Equatable {
        let value: UInt64
    }

    /// Per-session scheduling state. Created at the start of every
    /// ``translate(segments:direction:)`` call; cleared at
    /// ``cancel()`` or natural completion.
    ///
    /// Declared `final class @unchecked Sendable` because the session
    /// is shared between the actor and the drain / timer task
    /// closures; all reads/writes to its mutable fields occur under
    /// the actor's isolation domain via the closures hopping back
    /// into actor methods.
    private final class Session: @unchecked Sendable {
        let token: SessionToken
        let direction: TranslationDirection
        let continuation: AsyncThrowingStream<TranslationEvent, any Error>.Continuation
        var sentenceBuffer: SentenceBuffer
        var pendingSentences: [BufferedSentence] = []
        var droppedNewestCount: Int = 0
        var drainTask: Task<Void, Never>?
        var timerTask: Task<Void, Never>?
        var inflightTask: Task<Void, Never>?
        /// `true` once the upstream-drain task has observed the upstream
        /// stream finishing and flushed any remaining accumulator into
        /// the pending queue. Used by
        /// ``handleGenerationNaturalCompletion(sessionToken:)`` to decide
        /// when the session's continuation can finish — only after the
        /// drain task has finished AND the pending queue is empty AND
        /// no inflight LFM2 task is running.
        var drainTaskFinished: Bool = false

        init(
            token: SessionToken,
            direction: TranslationDirection,
            continuation: AsyncThrowingStream<TranslationEvent, any Error>.Continuation,
            sentenceBuffer: SentenceBuffer
        ) {
            self.token = token
            self.direction = direction
            self.continuation = continuation
            self.sentenceBuffer = sentenceBuffer
        }
    }

    // MARK: - Translating (warmup + state)

    /// Resolves the engine and runs warmup canaries.
    ///
    /// **Behavior**:
    /// - First call from `.cold` transitions to `.warming`, spawns a
    ///   single task that runs the loader path (production) or the
    ///   engine-factory path (test), and transitions to `.ready` on
    ///   success or `.failed(_:)` on failure.
    /// - Concurrent callers coalesce against the in-flight task —
    ///   exactly one factory or loader invocation per fresh-warmup
    ///   epoch.
    /// - A call after success is a no-op (returns immediately).
    /// - A call after failure retries: the failed state does not
    ///   strand future warmup attempts.
    ///
    /// - Throws: ``TranslationError`` wrapping any underlying error.
    func warmup() async throws {
        if case .ready = currentState {
            return
        }

        if let inFlightWarmup {
            _ = try await inFlightWarmup.value
            return
        }

        let task = Task<any LFM2Engine, Error> { [loader, engineFactory] in
            if let loader {
                let engine = try await loader.loadIfNeeded()
                try await loader.warmup()
                return engine
            } else if let engineFactory {
                return try await engineFactory()
            } else {
                // Unreachable: one of the two is set per init.
                throw TranslationError.modelLoadFailed("TranslationActor has neither loader nor engineFactory")
            }
        }
        inFlightWarmup = task
        currentState = .warming

        do {
            let engine = try await task.value
            resolvedEngine = engine
            currentState = .ready
            inFlightWarmup = nil
        } catch let error as TranslationError {
            currentState = .failed(error)
            inFlightWarmup = nil
            throw error
        } catch {
            let wrapped = TranslationError.modelLoadFailed(error.localizedDescription)
            currentState = .failed(wrapped)
            inFlightWarmup = nil
            throw wrapped
        }
    }

    /// Returns the current warmup state. Cheap and safe to poll.
    func warmupState() async -> TranslationWarmupState {
        currentState
    }

    // MARK: - Translating (translate + cancel)

    /// Begins a translation session over the supplied upstream segment
    /// stream.
    ///
    /// Cancels any prior session before spawning a new one. The drain
    /// task consumes the upstream stream, appends each segment to the
    /// session's ``SentenceBuffer``, and enqueues every boundary-
    /// detected sentence into ``Session/pendingSentences``. The timer
    /// task polls the injected clock every 500ms and flushes any
    /// stale buffered text via ``SentenceBuffer/flushIfStaleSince(_:)``.
    ///
    /// Step 6 scope: no LFM2 dispatch yet — sentences collect in the
    /// queue and nothing happens beyond enqueueing. Step 7 wires
    /// LFM2 dispatch via ``LFM2Engine/translate(userText:direction:)``.
    func translate(
        segments: AsyncStream<TranscriptSegment>,
        direction: TranslationDirection
    ) async -> AsyncThrowingStream<TranslationEvent, any Error> {
        // Cancel any prior session.
        if let priorSession = session {
            priorSession.drainTask?.cancel()
            priorSession.timerTask?.cancel()
            priorSession.continuation.finish()
            session = nil
        }

        nextSessionTokenValue &+= 1
        let token = SessionToken(value: nextSessionTokenValue)

        var continuationHandle: AsyncThrowingStream<TranslationEvent, any Error>.Continuation?
        let stream = AsyncThrowingStream<TranslationEvent, any Error> { c in
            continuationHandle = c
        }
        guard let resolvedContinuation = continuationHandle else {
            // AsyncThrowingStream's builder is synchronous and the
            // closure is invoked exactly once before the initialiser
            // returns; the only path where `continuationHandle` would
            // still be nil is an internal stdlib regression. Treat as
            // an immediately-finished stream rather than force-unwrap.
            return AsyncThrowingStream { c in c.finish() }
        }

        let buffer = SentenceBuffer()
        let newSession = Session(
            token: token,
            direction: direction,
            continuation: resolvedContinuation,
            sentenceBuffer: buffer
        )
        session = newSession

        // Spawn drain task — reads upstream, calls back into actor on
        // each segment to enqueue boundary-detected sentences.
        newSession.drainTask = Task { [weak self] in
            for await segment in segments {
                if Task.isCancelled { break }
                await self?.handleSegment(segment, sessionToken: token)
            }
            // Upstream finished: flush remaining accumulator + drain.
            await self?.handleUpstreamFinished(sessionToken: token)
        }

        // Spawn timer task — polls the injected clock for silence-
        // timeout flushes.
        newSession.timerTask = Task { [weak self, clock] in
            while !Task.isCancelled {
                do {
                    try await clock.sleep(for: .milliseconds(500))
                } catch {
                    break
                }
                if Task.isCancelled { break }
                await self?.handleTimerTick(sessionToken: token)
            }
        }

        return stream
    }

    /// Cancels in-flight translation, finishing the active stream
    /// without throwing per the ``Translating/cancel()`` contract.
    ///
    /// Cancels the drain task and the timer task, finishes the
    /// continuation normally, and clears the active session.
    /// Pending queued sentences are discarded.
    func cancel() async {
        guard let session else { return }
        session.drainTask?.cancel()
        session.timerTask?.cancel()
        session.continuation.finish()
        self.session = nil
    }

    // MARK: - Drain task callbacks (actor-isolated)

    /// Handles one upstream segment on the actor's isolation domain.
    /// Appends to the buffer and enqueues every boundary-detected
    /// sentence (including any post-split overflow drained via
    /// ``SentenceBuffer/drainNext()``).
    private func handleSegment(_ segment: TranscriptSegment, sessionToken: SessionToken) {
        guard let session, session.token == sessionToken else { return }

        let appendInstant = ContinuousClock.now
        if let sentence = session.sentenceBuffer.append(segment, at: appendInstant) {
            enqueue(sentence, into: session)
            while let next = session.sentenceBuffer.drainNext() {
                enqueue(next, into: session)
            }
        }
    }

    /// Handles the upstream stream's natural finish on the actor's
    /// isolation domain. Flushes any unfinished accumulator as a
    /// terminal sentence, sets ``Session/drainTaskFinished`` so the
    /// final inflight task's natural-completion branch will close out
    /// the session, and immediately closes the session if no work
    /// remains.
    ///
    /// Step 7 wiring: the continuation no longer finishes here in the
    /// general case. The continuation finishes either (a) immediately
    /// in this method if the pending queue is empty AND no inflight
    /// generation is running, or (b) later via
    /// ``handleGenerationNaturalCompletion(sessionToken:)`` when the
    /// last inflight task observes `drainTaskFinished && queue empty`.
    private func handleUpstreamFinished(sessionToken: SessionToken) {
        guard let session, session.token == sessionToken else { return }

        if let last = session.sentenceBuffer.flushRemaining() {
            enqueue(last, into: session)
        }
        session.drainTaskFinished = true
        dispatchNextSentenceIfIdle()
        if session.pendingSentences.isEmpty, session.inflightTask == nil {
            finishSession(sessionToken: sessionToken)
        }
        // Otherwise: the last inflight task's natural-completion branch
        // detects `drainTaskFinished && empty queue` and calls
        // `finishSession(sessionToken:)`.
    }

    /// Finishes the session's continuation normally, cancels the timer
    /// task, and clears `self.session` if it still matches the supplied
    /// token. Late callers with a stale token are no-ops.
    private func finishSession(sessionToken: SessionToken) {
        guard let session, session.token == sessionToken else { return }
        session.continuation.finish()
        session.timerTask?.cancel()
        self.session = nil
    }

    /// Handles one timer-task tick on the actor's isolation domain.
    /// If the buffer's accumulator has aged past the silence-timeout
    /// threshold, flushes it as a sentence and enqueues.
    private func handleTimerTick(sessionToken: SessionToken) {
        guard let session, session.token == sessionToken else { return }
        let now = ContinuousClock.now
        if let stale = session.sentenceBuffer.flushIfStaleSince(now) {
            enqueue(stale, into: session)
        }
    }

    /// Enqueues a buffered sentence into the session's pending queue,
    /// applying the drop-NEWEST overflow policy (Q2). When the queue
    /// is at cap, the incoming sentence is dropped and the diagnostic
    /// counter increments. On successful enqueue, kicks
    /// ``dispatchNextSentenceIfIdle()`` so the LFM2 pump observes the
    /// newly-arrived work.
    private func enqueue(_ sentence: BufferedSentence, into session: Session) {
        if session.pendingSentences.count >= Self.maxQueuedSentences {
            // Drop-NEWEST cap policy (Q2). Differs from
            // TranscriptionActor's C30 drop-OLDEST because sentences
            // are coarser and irrecoverable once dropped, whereas
            // audio hops are re-creatable from upstream.
            session.droppedNewestCount += 1
            os_log(
                .info,
                "TranslationActor: queue at cap (%{public}d), dropping newest sentence",
                Self.maxQueuedSentences
            )
            return
        }
        session.pendingSentences.append(sentence)
        dispatchNextSentenceIfIdle()
    }

    // MARK: - LFM2 dispatch (Step 7)

    /// Spawns LFM2 dispatch for the next pending sentence if (a) the
    /// session has one queued, and (b) no inflight generation is
    /// currently running. Idempotent.
    ///
    /// **Scheduling assumption.** This method is called from
    /// (1) ``enqueue(_:into:)`` after appending a fresh sentence, and
    /// (2) the natural-completion branch of
    /// ``handleGenerationNaturalCompletion(sessionToken:)`` after the
    /// prior inflight task finishes. The actor's isolation guarantees
    /// at most one of (1) or (2) runs at a time, so the
    /// `session.inflightTask == nil` guard cannot race against itself.
    ///
    /// **Violation behavior.** If a future caller bypasses the actor's
    /// isolation domain (e.g., calls this from a detached Task without
    /// awaiting actor state), the guard becomes a check-then-act race
    /// and two generations could start. The doc-comment is the only
    /// guardrail; the protocol-level scheduling assumption (one
    /// inflight per actor instance) is enforced by Swift's actor
    /// model only when callers stay inside the actor's isolation.
    private func dispatchNextSentenceIfIdle() {
        guard let session, session.inflightTask == nil else { return }
        guard !session.pendingSentences.isEmpty else { return }
        let sentence = session.pendingSentences.removeFirst()
        startGeneration(
            sentence: sentence,
            direction: session.direction,
            sessionToken: session.token
        )
    }

    /// Drives one LFM2 translation for the supplied sentence + direction.
    ///
    /// **Scheduling assumption.** The actor's isolation serialises
    /// every method call against this engine instance. Conformers of
    /// ``LFM2Engine/translate(userText:direction:)`` document a
    /// serial-per-conformer contract; this actor honors that contract
    /// by guarding dispatch with `session.inflightTask == nil` in
    /// ``dispatchNextSentenceIfIdle()``. A `LeapSDK.Conversation`
    /// instance is created and consumed inside
    /// ``LFM2EngineAdapter/translate(userText:direction:)``'s body; it
    /// never escapes that scope and is never shared across
    /// ``TranslationActor`` calls.
    ///
    /// **Violation behavior.** If the engine emits `.complete` with no
    /// prior `.chunk` events — i.e. an empty translation — the
    /// assembled text is empty. Per the ``TranslatedSegment/isFallback``
    /// contract, the actor emits a ``TranslatedSegment`` whose
    /// `translatedText` is the source sentence text and whose
    /// `isFallback` flag is `true` (passthrough source text). This
    /// honors the fallback discipline without throwing.
    ///
    /// If the engine throws mid-stream, the actor finishes the session
    /// continuation with ``TranslationError/generationFailed(_:)``
    /// wrapping the underlying message, clears the pending queue, and
    /// cancels the inflight task. Step 8 separately wires
    /// `LeapSDK.GenerationHandler.stop()` cancellation; at Step 7 the
    /// dispatch path observes cooperative `Task.isCancelled` only.
    ///
    /// **Violation test.** `C-T-VIOLATION-SLOW-DOWNSTREAM` in
    /// ``TranslationActorTests`` drives a slow downstream consumer
    /// against a fast upstream burst to assert that downstream stall
    /// does not affect upstream queueing or LFM2 generation, and that
    /// output ordering matches input ordering.
    private func startGeneration(
        sentence: BufferedSentence,
        direction: TranslationDirection,
        sessionToken: SessionToken
    ) {
        guard let engine = resolvedEngine else {
            // Defensive: should not happen if warmup() ran first. Finish
            // the session with a typed error.
            session?.continuation.finish(throwing: TranslationError.modelNotReady)
            return
        }
        guard let session, session.token == sessionToken else { return }

        let task = Task<Void, Never> { [weak self] in
            var accumulated = ""
            let stream = engine.translate(userText: sentence.text, direction: direction)

            do {
                for try await event in stream {
                    if Task.isCancelled { break }
                    switch event {
                    case let .chunk(delta):
                        if !delta.isEmpty {
                            accumulated += delta
                            await self?.yieldPartialChunk(
                                delta: delta,
                                sourceSegmentID: sentence.sourceSegmentIDs.first ?? UUID(),
                                sessionToken: sessionToken
                            )
                        }
                    case .complete:
                        let translated = TranslatedSegment(
                            sourceSegmentID: sentence.sourceSegmentIDs.first ?? UUID(),
                            sourceText: sentence.text,
                            translatedText: accumulated.isEmpty ? sentence.text : accumulated,
                            direction: direction,
                            startHostTime: sentence.startHostTime,
                            endHostTime: sentence.endHostTime,
                            isFallback: accumulated.isEmpty
                        )
                        await self?.yieldCompleted(translated, sessionToken: sessionToken)
                    }
                }
            } catch {
                await self?.handleGenerationError(error, sessionToken: sessionToken)
                return
            }

            await self?.handleGenerationNaturalCompletion(sessionToken: sessionToken)
        }
        session.inflightTask = task
    }

    /// Yields a `.partialChunk` event on the active session's
    /// continuation, guarded by session-token equality so stale-session
    /// callbacks become no-ops.
    private func yieldPartialChunk(
        delta: String,
        sourceSegmentID: UUID,
        sessionToken: SessionToken
    ) {
        guard let session, session.token == sessionToken else { return }
        session.continuation.yield(.partialChunk(sourceSegmentID: sourceSegmentID, delta: delta))
    }

    /// Yields a `.completed` event on the active session's continuation,
    /// guarded by session-token equality so stale-session callbacks
    /// become no-ops.
    private func yieldCompleted(
        _ translated: TranslatedSegment,
        sessionToken: SessionToken
    ) {
        guard let session, session.token == sessionToken else { return }
        session.continuation.yield(.completed(translated))
    }

    /// Handles a mid-generation error: finishes the continuation with
    /// the wrapped ``TranslationError``, clears the pending queue, and
    /// drops the session. Non-``TranslationError`` values are wrapped
    /// as ``TranslationError/generationFailed(_:)`` per the
    /// ``Translating`` error contract.
    private func handleGenerationError(_ error: any Error, sessionToken: SessionToken) {
        guard let session, session.token == sessionToken else { return }
        let wrapped: TranslationError
        if let translationError = error as? TranslationError {
            wrapped = translationError
        } else {
            wrapped = .generationFailed(error.localizedDescription)
        }
        session.continuation.finish(throwing: wrapped)
        session.pendingSentences.removeAll()
        session.inflightTask = nil
        session.timerTask?.cancel()
        self.session = nil
    }

    /// Handles natural (non-error) completion of one inflight LFM2
    /// generation. Clears `inflightTask`, dispatches the next queued
    /// sentence if any, and finishes the session if upstream has
    /// already drained and the queue is empty.
    private func handleGenerationNaturalCompletion(sessionToken: SessionToken) {
        guard let session, session.token == sessionToken else { return }
        session.inflightTask = nil
        dispatchNextSentenceIfIdle()
        if session.drainTaskFinished,
           session.pendingSentences.isEmpty,
           session.inflightTask == nil
        {
            finishSession(sessionToken: sessionToken)
        }
    }
}

// MARK: - Translating conformance

/// Conformance is declared in an extension (rather than on the actor
/// declaration itself) to keep the actor's explicit designated
/// initializers from being inferred as `@MainActor`-isolated under the
/// project's ``SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`` setting. When
/// the conformance is declared inline (`actor TranslationActor:
/// Translating`), the compiler infers MainActor isolation on the
/// synchronous designated initializers, which then prevents test code
/// running outside the main actor from constructing the actor. Splitting
/// the conformance into an extension restores the actor's natural
/// nonisolated-init posture without changing runtime behavior — every
/// protocol requirement is satisfied by methods already declared on the
/// actor body above.
extension TranslationActor: Translating {}
