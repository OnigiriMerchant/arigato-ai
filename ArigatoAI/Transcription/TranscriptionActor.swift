//
//  TranscriptionActor.swift
//  ArigatoAI
//
//  Created by Jose Castell on 2026/05/10.
//

import Darwin.Mach
import Foundation

/// Actor that drains an `AsyncStream<AudioFrame>` into a stream of
/// ``TranscriptionWindow`` values by running 5-second sliding-window
/// inference against a ``WhisperClient``.
///
/// The actor owns three pieces of internal state:
///
/// 1. A ``RollingAudioBuffer`` sized to ``windowSeconds`` that absorbs the
///    upstream frame flow.
/// 2. A ``WhisperModelLoader`` (or a test-injected factory) that resolves
///    a `WhisperClient` lazily on the first ``warmup()`` call and
///    coalesces concurrent warmups.
/// 3. A bounded FIFO scheduler of pending audio hops. Each hop boundary
///    captures a window snapshot; if a previous inference is still
///    running, the snapshot is queued behind it and dispatched in order
///    once the inflight call completes.
///
/// ## Scheduling assumption (Concurrency design discipline)
///
/// The drain task that consumes ``windowStream(frames:)``'s upstream may
/// produce hops faster than ``inferenceCompleted(...)`` can run on this
/// actor. This happens during continuous frame flow under sustained load,
/// during post-stall catchup, and when paused-then-resumed audio arrives
/// in a burst. The actor maintains a bounded FIFO of up to
/// ``maxPendingHops`` backlog hops to absorb these bursts.
///
/// **Overflow behaviour.** When the queue is full and a new hop arrives,
/// the OLDEST pending hop is dropped (FIFO overflow). This preserves the
/// most recent backlog because the freshest audio is the most useful for
/// live captions. Sustained inference-slower-than-hop pressure is the
/// only documented data-loss case under this design (contract **C30**).
///
/// **End-of-stream guarantee.** Every hop that survived the bounded
/// queue WILL reach the consumer before ``windowStream(frames:)``'s
/// continuation finishes (contract **C31**). The drain task explicitly
/// awaits the inflight chain to drain after the upstream
/// `AsyncStream<AudioFrame>` finishes.
///
/// **Failure-mode footnote.** If an inflight inference throws while
/// pending hops exist, the pending hops are discarded silently. This
/// matches contract **C14**: client errors propagate via the throwing
/// stream, and the session ends. Recoverable errors are not the actor's
/// concern; the language router (Step 11) decides whether to restart a
/// session.
actor TranscriptionActor {
    /// Default sliding-window length in seconds (Phase 4 Decision 4).
    static let defaultWindowSeconds: Double = 5.0

    /// Default hop length in seconds. The actor emits one
    /// ``TranscriptionWindow`` per hop boundary once the rolling buffer
    /// first reaches ``defaultWindowSeconds`` of audio.
    static let defaultHopSeconds: Double = 1.0

    /// Minimum leftover-buffer length (seconds) below which the
    /// end-of-stream flush is suppressed (contract **C11**).
    static let endOfStreamFlushMinimumSeconds: Double = 0.5

    /// Maximum number of backlog hops the scheduler retains before it
    /// starts dropping the oldest pending hop on overflow (contract
    /// **C30**).
    static let maxPendingHops: Int = 4

    // MARK: - Private types

    /// One queued audio window ready to be transcribed. Captured at the
    /// hop boundary so the audio array is decoupled from the rolling
    /// buffer's later mutations.
    private struct PendingHop {
        let audio: [Float]
        let anchorHostTime: UInt64
        let windowStartSeconds: Double
        let windowEndSeconds: Double
        let isFinal: Bool
    }

    /// Identity token for the in-flight session. A second
    /// ``windowStream(frames:)`` call replaces the session and its token;
    /// the previous drain task uses the token to detect that it has been
    /// superseded and exit cleanly without yielding into the new
    /// continuation.
    private final nonisolated class SessionToken: Sendable {}

    /// Bag of mutable state describing one ``windowStream(frames:)``
    /// session. Instances are owned exclusively by the actor; the
    /// `@unchecked Sendable` declaration is safe because every mutation
    /// is serialised through ``TranscriptionActor``'s isolation domain.
    private final nonisolated class Session: @unchecked Sendable {
        let token: SessionToken
        let continuation: AsyncThrowingStream<TranscriptionWindow, any Error>.Continuation
        var drainTask: Task<Void, Never>?
        var inflightTask: Task<Void, Never>?
        var pendingHops: [PendingHop] = []
        var inflightWaiters: [CheckedContinuation<Void, Never>] = []

        init(
            token: SessionToken,
            continuation: AsyncThrowingStream<TranscriptionWindow, any Error>.Continuation
        ) {
            self.token = token
            self.continuation = continuation
        }
    }

    // MARK: - Stored state

    private let clientFactory: @Sendable () async throws -> any WhisperClient
    private let stateProvider: @Sendable () async -> WarmupState
    private let windowSeconds: Double
    private let hopSeconds: Double
    private let clock: any Clock<Duration>

    private var warmupTask: Task<any WhisperClient, any Error>?
    private var loadedClient: (any WhisperClient)?
    private var lastWarmupError: TranscriptionError?
    private var session: Session?

    // MARK: - Test instrumentation

    /// Continuations awaiting the drain loop's transition out of upstream
    /// frame consumption. Exposed only via ``awaitUpstreamDrained()`` and
    /// fired exactly once per session by ``signalUpstreamDrained()``. Used
    /// by ``TranscriptionActorTests`` to remove the
    /// release-before-frames-consumed race that otherwise destabilises
    /// the C30 contract test. Production callers do not need this signal.
    private var upstreamDrainedObservers: [CheckedContinuation<Void, Never>] = []
    private var upstreamDrainedSession: SessionToken?

    // MARK: - Initialisation

    /// Production initialiser wiring the actor to a ``WhisperModelLoader``.
    ///
    /// The actor delegates client resolution to the loader so concurrent
    /// warmups across the actor and other callers (e.g. `AppBootstrapper`)
    /// share a single in-flight load.
    ///
    /// - Parameters:
    ///   - loader: The loader that owns the underlying Whisper client.
    ///   - windowSeconds: Sliding-window length in seconds. Defaults to
    ///     ``defaultWindowSeconds``.
    ///   - hopSeconds: Hop length in seconds. Defaults to
    ///     ``defaultHopSeconds``.
    ///   - clock: Clock used for any future time-based scheduling. The
    ///     current implementation does not call any ``Clock`` API, but the
    ///     parameter is wired so future timing logic does not require an
    ///     initialiser change. Defaults to ``ContinuousClock``.
    init(
        loader: WhisperModelLoader,
        windowSeconds: Double = TranscriptionActor.defaultWindowSeconds,
        hopSeconds: Double = TranscriptionActor.defaultHopSeconds,
        clock: any Clock<Duration> = ContinuousClock()
    ) {
        self.windowSeconds = windowSeconds
        self.hopSeconds = hopSeconds
        self.clock = clock
        clientFactory = { try await loader.loadIfNeeded() }
        stateProvider = {
            let state = await loader.currentState()
            switch state {
            case .idle:
                return .cold
            case .loading:
                return .warming
            case .loaded:
                return .ready
            case let .failed(error):
                return .failed(error)
            }
        }
    }

    /// Test seam initialiser. Allows the test target to inject a custom
    /// client factory without booting `WhisperModelLoader` or WhisperKit.
    ///
    /// The actor synthesises its own ``WarmupState`` snapshots from
    /// internal state when this initialiser is used. This keeps the test
    /// surface narrow: a test does not need to fake a loader to validate
    /// the actor's lifecycle behaviour.
    ///
    /// - Parameters:
    ///   - clientFactory: Async closure returning a ``WhisperClient``.
    ///     Invoked at most once per successful warmup; concurrent
    ///     ``warmup()`` callers coalesce against a shared task.
    ///   - windowSeconds: Sliding-window length in seconds. Defaults to
    ///     ``defaultWindowSeconds``.
    ///   - hopSeconds: Hop length in seconds. Defaults to
    ///     ``defaultHopSeconds``.
    ///   - clock: Clock used for any future time-based scheduling.
    ///     Defaults to ``ContinuousClock``.
    init(
        clientFactory: @escaping @Sendable () async throws -> any WhisperClient,
        windowSeconds: Double = TranscriptionActor.defaultWindowSeconds,
        hopSeconds: Double = TranscriptionActor.defaultHopSeconds,
        clock: any Clock<Duration> = ContinuousClock()
    ) {
        self.clientFactory = clientFactory
        self.windowSeconds = windowSeconds
        self.hopSeconds = hopSeconds
        self.clock = clock
        // Captured weak via an indirection box so the closure does not
        // strongly retain the actor (which would create a retention
        // cycle: actor -> closure -> actor).
        let box = WarmupStateBox()
        stateProvider = {
            await box.read()
        }
        warmupStateBox = box
    }

    // MARK: - Warmup state plumbing for the test seam

    /// Actor used to bridge the actor's `loaded`/`failed`/`idle` snapshot
    /// to the test-seam ``stateProvider`` closure without forming a
    /// retention cycle. Only used by the test-seam initialiser.
    private actor WarmupStateBox {
        private var state: WarmupState = .cold

        func update(_ newState: WarmupState) {
            state = newState
        }

        func read() async -> WarmupState {
            state
        }
    }

    private var warmupStateBox: WarmupStateBox?

    /// Pushes the actor's current warmup snapshot into the test-seam box
    /// (if any). No-op for the production initialiser path.
    private func publishWarmupState(_ newState: WarmupState) async {
        guard let box = warmupStateBox else { return }
        await box.update(newState)
    }

    // MARK: - Lifecycle API

    /// Loads the Whisper client (or coalesces with an in-flight load) and
    /// resolves once a usable client is available.
    ///
    /// Idempotent across repeated and concurrent calls (contract **C7**).
    /// The first call invokes the configured ``clientFactory`` exactly
    /// once; subsequent calls return immediately if the client is already
    /// loaded, or `await` the same in-flight task if a load is in
    /// progress. After a failed load, the next call retries.
    ///
    /// - Throws: ``TranscriptionError/modelLoadFailed(_:)`` wrapping any
    ///   factory error.
    func warmup() async throws {
        if loadedClient != nil { return }

        if let task = warmupTask {
            _ = try await task.value
            return
        }

        let factory = clientFactory
        let task = Task<any WhisperClient, any Error> {
            try await factory()
        }
        warmupTask = task
        await publishWarmupState(.warming)

        do {
            let client = try await task.value
            loadedClient = client
            warmupTask = nil
            lastWarmupError = nil
            await publishWarmupState(.ready)
        } catch let error as TranscriptionError {
            warmupTask = nil
            lastWarmupError = error
            await publishWarmupState(.failed(error))
            throw error
        } catch {
            let wrapped = TranscriptionError.modelLoadFailed(error.localizedDescription)
            warmupTask = nil
            lastWarmupError = wrapped
            await publishWarmupState(.failed(wrapped))
            throw wrapped
        }
    }

    /// Returns a snapshot of the warmup lifecycle (contract **C8**).
    ///
    /// In the production initialiser path this is a direct mapping from
    /// the underlying ``WhisperModelLoader``'s state. In the test-seam
    /// path this reflects the actor's own internal warmup state machine.
    /// Cheap to call; safe to poll from UI on every render pass.
    func warmupState() async -> WarmupState {
        await stateProvider()
    }

    /// Cancels in-flight transcription and ends the active stream cleanly.
    ///
    /// After ``cancel()`` returns, the active stream's continuation has
    /// been finished without an error and its drain task has been
    /// signalled to exit. Repeat calls are safe (idempotent). Pending and
    /// inflight inferences are abandoned without yielding (contract
    /// **C12**).
    func cancel() {
        guard let active = session else { return }
        session = nil
        active.inflightTask?.cancel()
        active.drainTask?.cancel()
        for waiter in active.inflightWaiters {
            waiter.resume()
        }
        active.inflightWaiters.removeAll()
        for observer in upstreamDrainedObservers {
            observer.resume()
        }
        upstreamDrainedObservers.removeAll()
        upstreamDrainedSession = nil
        active.continuation.finish()
    }

    // MARK: - Stream API

    /// Begins draining `frames` and returns a throwing async stream of
    /// ``TranscriptionWindow`` values.
    ///
    /// Behaviour:
    /// - Once the rolling buffer first reaches ``windowSeconds`` of
    ///   audio, the actor emits one ``TranscriptionWindow`` per
    ///   ``hopSeconds`` of additional ingest (contract **C9**).
    /// - No emission happens before that prefill threshold is reached
    ///   (contract **C10**).
    /// - When `frames` finishes, the actor drains the inflight scheduler
    ///   chain (contract **C31**) and then optionally flushes a final
    ///   `isFinal: true` window when the leftover buffer holds at least
    ///   ``endOfStreamFlushMinimumSeconds`` of audio (contract **C11**).
    /// - Errors thrown by ``WhisperClient/transcribe(audio:anchorHostTime:)``
    ///   are wrapped as ``TranscriptionError/decodeFailed(_:)`` and
    ///   propagated via the throwing stream (contract **C14**).
    /// - Calling ``windowStream(frames:)`` a second time finishes the
    ///   previous stream cleanly before starting the new one (contract
    ///   **C16**).
    ///
    /// ## Scheduling
    ///
    /// The drain task may produce hops faster than this actor's
    /// ``inferenceCompleted(payload:client:token:)`` method can run on
    /// the actor (continuous frame flow, post-stall catchup, paused
    /// audio resuming). The actor maintains a bounded FIFO queue of up
    /// to ``maxPendingHops`` hops to absorb these bursts. When the queue
    /// is full, the oldest pending hop is dropped (contract **C30**) so
    /// the freshest audio always wins. Every hop that survives the queue
    /// reaches the consumer.
    ///
    /// - Parameter frames: The upstream audio frame stream.
    /// - Returns: A throwing async stream of ``TranscriptionWindow``
    ///   values.
    nonisolated func windowStream(
        frames: AsyncStream<AudioFrame>
    ) -> AsyncThrowingStream<TranscriptionWindow, any Error> {
        AsyncThrowingStream<TranscriptionWindow, any Error> { continuation in
            let drainTask = Task {
                await self.startSession(frames: frames, continuation: continuation)
            }
            continuation.onTermination = { @Sendable _ in
                drainTask.cancel()
            }
        }
    }

    /// Replaces any current session, then drives the new one.
    ///
    /// Doc-comment supports contract **C16**: a previous session's
    /// continuation is finished cleanly before the new drain begins.
    private func startSession(
        frames: AsyncStream<AudioFrame>,
        continuation: AsyncThrowingStream<TranscriptionWindow, any Error>.Continuation
    ) async {
        if let previous = session {
            session = nil
            previous.inflightTask?.cancel()
            previous.drainTask?.cancel()
            for waiter in previous.inflightWaiters {
                waiter.resume()
            }
            previous.inflightWaiters.removeAll()
            for observer in upstreamDrainedObservers {
                observer.resume()
            }
            upstreamDrainedObservers.removeAll()
            upstreamDrainedSession = nil
            previous.continuation.finish()
        }

        let token = SessionToken()
        let newSession = Session(token: token, continuation: continuation)
        session = newSession

        do {
            try await warmup()
        } catch let error as TranscriptionError {
            continuation.finish(throwing: error)
            session = nil
            return
        } catch {
            let wrapped = TranscriptionError.modelLoadFailed(error.localizedDescription)
            continuation.finish(throwing: wrapped)
            session = nil
            return
        }

        guard let client = loadedClient else {
            continuation.finish(throwing: TranscriptionError.modelNotReady)
            session = nil
            return
        }

        await drain(frames: frames, client: client, token: token)
    }

    // MARK: - Drain loop

    /// Drives one session's frame consumption, hop scheduling, and
    /// end-of-stream flush. Runs as the drain task body.
    private func drain(
        frames: AsyncStream<AudioFrame>,
        client: any WhisperClient,
        token: SessionToken
    ) async {
        var buffer = RollingAudioBuffer(capacitySeconds: windowSeconds)
        var cumulativeSamples = 0
        let sampleRate: Double = 16000
        let windowSamples = Int((windowSeconds * sampleRate).rounded())
        let hopSamples = Int((hopSeconds * sampleRate).rounded())
        var nextEmissionThresholdSamples: Int = windowSamples
        var lastEmittedEndSamples = 0

        for await frame in frames {
            if !isActive(token: token) { return }
            buffer.append(frame)
            cumulativeSamples += frame.samples.count

            while cumulativeSamples >= nextEmissionThresholdSamples,
                  let snapshot = buffer.trailingWindow(seconds: windowSeconds)
            {
                let endSamples = nextEmissionThresholdSamples
                let startSamples = endSamples - windowSamples
                let hop = PendingHop(
                    audio: snapshot.samples,
                    anchorHostTime: snapshot.anchorHostTime,
                    windowStartSeconds: Double(startSamples) / sampleRate,
                    windowEndSeconds: Double(endSamples) / sampleRate,
                    isFinal: false
                )
                submitHop(hop, client: client, token: token)
                lastEmittedEndSamples = endSamples
                nextEmissionThresholdSamples += hopSamples
            }
        }

        // Test-instrumentation hop: signal that upstream has been fully
        // consumed and every steady-state hop has been submitted. Fired
        // before we begin the inflight-drain loop so a test can park
        // itself here with ``awaitUpstreamDrained()`` and only then
        // release any pre-blocked inference (contract **C30**).
        signalUpstreamDrained(token: token)

        // End-of-stream: drain the inflight chain so every queued hop
        // reaches the consumer (contract **C31**).
        while isActive(token: token),
              let active = session,
              active.inflightTask != nil || !active.pendingHops.isEmpty
        {
            await waitForInflight(token: token)
        }

        if !isActive(token: token) { return }

        // Optional final flush (contract **C11**).
        let leftoverSamples = cumulativeSamples - lastEmittedEndSamples
        let minimumFlushSamples = Int(
            (TranscriptionActor.endOfStreamFlushMinimumSeconds * sampleRate).rounded()
        )
        if leftoverSamples >= minimumFlushSamples,
           let remaining = buffer.remainingWindow(
               minSeconds: TranscriptionActor.endOfStreamFlushMinimumSeconds
           )
        {
            // For the final flush we use the buffer's full remaining
            // contents. The window covers from "the oldest sample left
            // in the buffer" to cumulativeSamples; the audio array's
            // first sample is the buffer's anchor.
            let totalRemainingCount = remaining.samples.count
            let endSamples = cumulativeSamples
            let startSamples = endSamples - totalRemainingCount
            let hop = PendingHop(
                audio: remaining.samples,
                anchorHostTime: remaining.anchorHostTime,
                windowStartSeconds: Double(startSamples) / sampleRate,
                windowEndSeconds: Double(endSamples) / sampleRate,
                isFinal: true
            )
            submitHop(hop, client: client, token: token)

            // Drain the final flush before finishing.
            while isActive(token: token),
                  let active = session,
                  active.inflightTask != nil || !active.pendingHops.isEmpty
            {
                await waitForInflight(token: token)
            }
        }

        if !isActive(token: token) { return }
        guard let active = session, active.token === token else { return }
        active.continuation.finish()
        session = nil
    }

    // MARK: - Hop scheduling

    /// Submits a captured hop to the FIFO scheduler.
    ///
    /// If no inference is currently inflight, a new inference task is
    /// started immediately. Otherwise the hop joins the back of the
    /// pending queue. Queue overflow drops the oldest pending hop
    /// (contract **C30**).
    private func submitHop(
        _ hop: PendingHop,
        client: any WhisperClient,
        token: SessionToken
    ) {
        guard isActive(token: token), let active = session else { return }

        if active.inflightTask == nil {
            active.inflightTask = startInference(
                hop: hop,
                client: client,
                token: token
            )
            return
        }

        if active.pendingHops.count >= TranscriptionActor.maxPendingHops {
            active.pendingHops.removeFirst()
        }
        active.pendingHops.append(hop)
    }

    /// Spawns one inference task for `hop`, calling
    /// ``inferenceCompleted(payload:client:token:)`` on this actor when
    /// the call returns.
    private func startInference(
        hop: PendingHop,
        client: any WhisperClient,
        token: SessionToken
    ) -> Task<Void, Never> {
        Task { [weak self] in
            do {
                let result = try await client.transcribe(
                    audio: hop.audio,
                    anchorHostTime: hop.anchorHostTime
                )
                await self?.inferenceCompleted(
                    payload: .success((hop, result)),
                    client: client,
                    token: token
                )
            } catch {
                await self?.inferenceCompleted(
                    payload: .failure(error),
                    client: client,
                    token: token
                )
            }
        }
    }

    /// Handles one inference's outcome on the actor's isolation domain.
    ///
    /// On success: yields the resulting ``TranscriptionWindow`` to the
    /// continuation, then pops the next pending hop and starts the next
    /// inference. On failure: wraps the error as
    /// ``TranscriptionError/decodeFailed(_:)`` if it is not already a
    /// ``TranscriptionError``, finishes the continuation with that
    /// error, and ends the session. Pending hops are discarded.
    private func inferenceCompleted(
        payload: Result<(PendingHop, WhisperWindowResult), any Error>,
        client: any WhisperClient,
        token: SessionToken
    ) {
        guard isActive(token: token), let active = session else { return }
        active.inflightTask = nil

        switch payload {
        case let .success((hop, result)):
            let detected: SpokenLanguage? = result.language.isEmpty
                ? nil
                : SpokenLanguage(whisperCode: result.language)
            let window = TranscriptionWindow(
                detectedLanguage: detected,
                windowAnchorHostTime: result.windowAnchorHostTime,
                windowStartSeconds: hop.windowStartSeconds,
                windowEndSeconds: hop.windowEndSeconds,
                segments: result.segments,
                isFinal: hop.isFinal
            )
            active.continuation.yield(window)

            if !active.pendingHops.isEmpty {
                let next = active.pendingHops.removeFirst()
                active.inflightTask = startInference(
                    hop: next,
                    client: client,
                    token: token
                )
            }

            for waiter in active.inflightWaiters {
                waiter.resume()
            }
            active.inflightWaiters.removeAll()

        case let .failure(error):
            let wrapped: TranscriptionError
            if let typed = error as? TranscriptionError {
                wrapped = typed
            } else {
                wrapped = .decodeFailed(error.localizedDescription)
            }
            active.continuation.finish(throwing: wrapped)
            for waiter in active.inflightWaiters {
                waiter.resume()
            }
            active.inflightWaiters.removeAll()
            session = nil
        }
    }

    /// Suspends the drain task until the current inflight inference (if
    /// any) completes. If the session is replaced or ends before the
    /// inflight call returns, the waiter is resumed by ``cancel()``,
    /// ``startSession(frames:continuation:)``, or the failure branch in
    /// ``inferenceCompleted(payload:client:token:)``.
    private func waitForInflight(token: SessionToken) async {
        guard let active = session, active.token === token else { return }
        guard active.inflightTask != nil || !active.pendingHops.isEmpty else { return }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            active.inflightWaiters.append(continuation)
        }
    }

    // MARK: - Helpers

    /// Returns `true` when `token` is the session's current identity
    /// token. Used by the drain loop, scheduler, and inference-completion
    /// callback to detect superseded sessions.
    private func isActive(token: SessionToken) -> Bool {
        session?.token === token
    }

    // MARK: - Test instrumentation

    /// Returns once the current ``windowStream(frames:)`` session's
    /// drain loop has finished consuming the upstream frame stream
    /// (i.e. its `for await frame in frames` loop has exited). If the
    /// drain has already reached that point when this is called, the
    /// method returns immediately.
    ///
    /// This is a test-only synchronisation point. ``TranscriptionActorTests``
    /// uses it to wait until every hop submission has happened before
    /// releasing a parked inference, so the C30 hop-queue overflow
    /// behaviour is observed deterministically rather than as a race.
    /// Production callers do not need this signal — the streaming API
    /// already covers their visibility into pipeline state.
    func awaitUpstreamDrained() async {
        guard let active = session else { return }
        if upstreamDrainedSession === active.token { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            upstreamDrainedObservers.append(continuation)
        }
    }

    /// Marks the current session's upstream as drained and resumes any
    /// observers that registered via ``awaitUpstreamDrained()``. Called
    /// by ``drain(frames:client:token:)`` exactly once per session,
    /// immediately after its `for await` loop exits.
    private func signalUpstreamDrained(token: SessionToken) {
        guard isActive(token: token) else { return }
        upstreamDrainedSession = token
        for observer in upstreamDrainedObservers {
            observer.resume()
        }
        upstreamDrainedObservers.removeAll()
    }
}
