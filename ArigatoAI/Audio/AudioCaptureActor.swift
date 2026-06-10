//
//  AudioCaptureActor.swift
//  ArigatoAI
//
//  Created by Jose Castell on 2026/05/09.
//

@preconcurrency import AVFAudio
import Foundation
import os

/// Microphone capture pipeline running off the main actor.
///
/// `AudioCaptureActor` owns the `AVAudioEngine`, installs a tap on the input
/// node, resamples each buffer to 16 kHz mono float32, and emits two streams:
///
/// - ``frameStream()`` produces ``AudioFrame`` values for the transcription
///   pipeline.
/// - ``levelStream()`` produces normalized RMS values in `[0, 1]` for the
///   VU meter, throttled to roughly 12 Hz.
///
/// Lifecycle: call ``start()`` to configure the audio session, install the
/// tap, and start the engine; call ``stop()`` to tear everything down. After
/// each ``start()``, callers must re-subscribe via ``frameStream()`` and
/// ``levelStream()`` because ``stop()`` finishes the previous continuations.
///
/// Audio session route changes (e.g. plugging in headphones) are handled by
/// rebuilding the converter and reinstalling the tap; the streams continue
/// producing values across the brief gap.
///
/// The class is an `actor`, so all mutable state is serialized on its own
/// executor.
///
/// ## Scheduling assumption — single-consumer serial drain
///
/// The CoreAudio tap callback is invoked **serially** on a render thread.
/// Each callback copies the buffer's samples into a `Sendable` payload and
/// **synchronously yields** it into an internal, actor-private
/// `AsyncStream<TapPayload>`. A single ``drainTask`` consumes that stream with
/// one `for await` loop, so every payload is resampled, framed, and emitted on
/// ``frameStream()`` **in the order the tap produced it**.
///
/// FIFO order is established at `yield` time on the serially-invoked tap thread,
/// and `AsyncStream` preserves that order to its single consumer. This is the
/// contract the downstream `RollingAudioBuffer` depends on: it sets
/// `anchorHostTime` from the **first** frame it sees and assumes appended
/// frames arrive in non-decreasing host-time order.
///
/// The previous design spawned a **new** `Task { await self.ingest(...) }` per
/// tap callback. Those tasks were unordered: the Swift runtime gives no
/// ordering guarantee across independently-spawned tasks, so under back-pressure
/// frame N+1 could be ingested before frame N. That re-ordering corrupts the
/// `RollingAudioBuffer` window content (samples appended out of capture order)
/// and the first-arrival `anchorHostTime` (a later-captured frame could win the
/// "first non-empty append" and anchor the window to the wrong host time).
///
/// What the violation tests deterministically prove (suite `AudioCaptureActor`,
/// IDs `C-T-VIOLATION-OUT-OF-ORDER-INGEST`):
///
/// - **FIFO / no-reorder discriminator** (`violation_submissionOrderPreserved`):
///   frames submitted **serially** in arbitrary order — specifically with
///   host times in *decreasing* order — are emitted on ``frameStream()`` in
///   **exact submission order** (decreasing). This is the load-bearing proof
///   that the single consumer preserves submission order and does **not** sort
///   by host time; a sorting or reordering pipe would fail it.
/// - **No-loss / no-dupe / single-consumer serialization**
///   (`violation_outOfOrderIngest_staysSerializedAndMonotonic`): a simultaneous
///   burst of concurrent submissions is emitted with no frame lost and none
///   duplicated (asserted order-blind via `Set` membership + exact count),
///   proving the single drain loop serializes concurrent yields into whole,
///   non-interleaved frames.
///
/// Residual (stated honestly): output **order** under genuinely-concurrent
/// acceptance is *not* asserted, because the order in which concurrently-spawned
/// tasks hop onto this actor's executor and `yield` into the channel is itself
/// nondeterministic. The FIFO-preservation guarantee that downstream
/// `RollingAudioBuffer` relies on (monotonic host-time anchor + non-decreasing
/// window content) is established by the deterministic serial-reordered case,
/// not by the burst.
public actor AudioCaptureActor {
    /// Target sample rate for downstream consumers (WhisperKit's input rate).
    public static let targetSampleRate: Double = 16000

    /// Fully-`Sendable` unit of work carried across the internal tap→actor
    /// channel. Holds the raw samples copied out of the (non-`Sendable`)
    /// `AVAudioPCMBuffer` inside the tap closure plus the host time of the
    /// first sample.
    ///
    /// The non-`Sendable` `AVAudioPCMBuffer` deliberately does **not** cross
    /// the channel: the tap closure extracts `[Float]` from it, and the
    /// resample runs later on the actor (in ``ingest(payload:)``) using the
    /// actor-isolated ``converter`` and ``sourceFormat``. This keeps the
    /// channel payload `Sendable` and keeps the actor-isolated converter off
    /// the nonisolated tap thread.
    private struct TapPayload {
        let samples: [Float]
        let hostTime: UInt64
    }

    private let engine: AVAudioEngine
    private var converter: AVAudioConverter?
    private let targetFormat: AVAudioFormat

    /// Format of the input node at the time the current tap was installed.
    /// Captured on the actor so ``ingest(payload:)`` can rebuild a source PCM
    /// buffer from the channel's raw samples without the non-`Sendable` format
    /// reference ever crossing the channel.
    private var sourceFormat: AVAudioFormat?

    private var frameContinuation: AsyncStream<AudioFrame>.Continuation?
    private var levelContinuation: AsyncStream<Float>.Continuation?

    /// Continuation for the internal tap→actor channel. The tap closure yields
    /// `TapPayload` values into this synchronously; the single ``drainTask``
    /// consumes them. Created in ``installTapAndConverter()``, finished and
    /// niled in ``stop()`` and at the top of the reconfiguration path so a
    /// reinstalled tap never yields into a finished continuation.
    private var tapFrameContinuation: AsyncStream<TapPayload>.Continuation?

    /// The single ordered consumer of the internal tap→actor channel. Exactly
    /// one of these runs per installed tap. Cancelled and niled in ``stop()``
    /// and at the top of the reconfiguration path before a new tap is installed,
    /// so two drain tasks never race over the same actor state.
    private var drainTask: Task<Void, Never>?

    private var isRunning: Bool = false
    private var levelEmitter: LevelEmitter
    private var routeChangeObserver: NSObjectProtocol?

    /// Pending one-shot retry for a failed reconfiguration rebuild. Non-nil
    /// only between a failed rebuild attempt and its retry firing; cancelled
    /// by ``stop()`` and by a newer reconfiguration notification (latest
    /// reconfiguration wins). See ``handleEngineReconfiguration()`` for the
    /// scheduling contract.
    private var reconfigurationRetryTask: Task<Void, Never>?

    /// Monotonic stamp identifying the CURRENT reconfiguration pass. Each
    /// ``handleEngineReconfiguration()`` entry bumps it; a scheduled retry
    /// captures the stamp and no-ops if a newer pass superseded it. This
    /// closes the stale-retry race: `cancel()` alone cannot stop a retry
    /// that already passed its cancellation check and is suspended on the
    /// actor hop — such a retry would double-install a tap over the newer
    /// pass's rebuild and orphan its drain task.
    private var reconfigurationGeneration = 0

    /// Capture-lifecycle logging at persisted levels (`.notice`/`.error`
    /// survive into `log collect` on device; `.info`/`.debug` are
    /// memory-only). Added 2026-06-10 after the on-device zombie-capture
    /// bug shipped invisibly — capture state transitions must be
    /// reconstructable from a device log archive.
    private static let log = Logger(
        subsystem: "com.jose.ArigatoAI",
        category: "AudioCapture"
    )

    /// Creates a new actor. The engine is constructed but not started.
    public init() {
        engine = AVAudioEngine()
        levelEmitter = LevelEmitter(targetHz: 12.0)
        guard let target = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: AudioCaptureActor.targetSampleRate,
            channels: 1,
            interleaved: false
        ) else {
            // The Float32 mono 16 kHz format is canonical and cannot fail to
            // construct on any supported iOS version. We fall back to a
            // best-effort placeholder format; downstream code still validates.
            targetFormat = AVAudioFormat()
            return
        }
        targetFormat = target
    }

    // MARK: - Public API

    /// Starts the capture pipeline. Idempotency is rejected with
    /// ``AudioCaptureError/alreadyRunning`` to surface caller bugs.
    ///
    /// A failure at ANY setup step rolls back the partial setup (tap
    /// removed, engine stopped, session deactivated) before rethrowing, so
    /// a failed start never leaves the microphone held or the session
    /// active behind a `false` ``isRunning``.
    public func start() throws {
        guard !isRunning else {
            Self.log.error("start() rejected: capture already running")
            throw AudioCaptureError.alreadyRunning
        }

        do {
            try configureSession()
            try installTapAndConverter()
            try engine.start()
        } catch {
            Self.log.error("Capture start failed: \(String(describing: error), privacy: .public)")
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            deactivateSession()
            teardownDrain()
            if let captureError = error as? AudioCaptureError {
                throw captureError
            }
            throw AudioCaptureError.engineStartFailed(error.localizedDescription)
        }

        registerRouteChangeObserver()
        isRunning = true
        Self.log.notice("Capture started")
    }

    /// Stops the pipeline, deactivates the audio session, and finishes both
    /// streams. Callers must call ``frameStream()`` and ``levelStream()`` again
    /// after a subsequent ``start()`` to receive new values.
    public func stop() {
        guard isRunning else { return }

        Self.log.notice("Capture stopping")
        reconfigurationRetryTask?.cancel()
        reconfigurationRetryTask = nil
        unregisterRouteChangeObserver()
        teardownCapture()
    }

    /// Single teardown nucleus shared by ``stop()`` and the reconfiguration
    /// failure path: stops the engine, releases the microphone (session
    /// deactivation), finishes both public streams, and restores the
    /// "``isRunning`` mirrors the engine" invariant.
    ///
    /// This must remain the ONLY way capture winds down. A path that flips
    /// ``isRunning`` to `false` without stopping the engine recreates the
    /// 2026-06-10 on-device zombie-capture bug: the microphone stays held
    /// (orange indicator forever), ``stop()`` early-returns on its guard,
    /// and the next ``start()`` walks into corrupted engine state.
    private func teardownCapture() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        deactivateSession()

        // Tear down the single drain consumer before finishing the public
        // streams. Finishing the internal channel lets the drain loop fall out
        // of its `for await` naturally; cancelling + niling guarantees a
        // subsequent ``start()`` installs exactly one fresh drain task with no
        // prior task still racing over actor state.
        teardownDrain()

        frameContinuation?.finish()
        frameContinuation = nil
        levelContinuation?.finish()
        levelContinuation = nil

        converter = nil
        sourceFormat = nil
        levelEmitter = LevelEmitter(targetHz: 12.0)
        isRunning = false
        Self.log.notice("Capture torn down (engine stopped, session released)")

        #if DEBUG
            fullTeardownCountForTesting += 1
        #endif
    }

    /// Cancels the single drain consumer and finishes the internal tap→actor
    /// channel. Idempotent: safe to call when no drain task or continuation
    /// exists. Called from ``stop()`` and at the top of
    /// ``handleEngineReconfiguration()`` so a reinstalled tap never yields into
    /// a finished continuation and two drain tasks never race.
    private func teardownDrain() {
        tapFrameContinuation?.finish()
        tapFrameContinuation = nil
        drainTask?.cancel()
        drainTask = nil
    }

    /// Returns a fresh ``AsyncStream`` of ``AudioFrame`` values. Call this
    /// once per ``start()`` cycle. Iterating the returned stream from another
    /// actor is safe because ``AudioFrame`` is `Sendable`.
    public func frameStream() -> AsyncStream<AudioFrame> {
        AsyncStream { continuation in
            self.frameContinuation = continuation
        }
    }

    /// Returns a fresh ``AsyncStream`` of normalized RMS levels in `[0, 1]`,
    /// throttled to roughly 12 Hz. Call this once per ``start()`` cycle.
    public func levelStream() -> AsyncStream<Float> {
        AsyncStream { continuation in
            self.levelContinuation = continuation
        }
    }

    // MARK: - Session configuration

    private func configureSession() throws {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(
                .record,
                mode: .measurement,
                options: [.allowBluetoothHFP]
            )
            try session.setActive(true, options: [.notifyOthersOnDeactivation])
        } catch {
            throw AudioCaptureError.sessionConfigurationFailed(error.localizedDescription)
        }
    }

    private func deactivateSession() {
        let session = AVAudioSession.sharedInstance()
        // Best effort: deactivation can fail if another audio client is
        // active, which is not worth surfacing as an error from stop().
        try? session.setActive(false, options: [.notifyOthersOnDeactivation])
    }

    // MARK: - Tap and converter

    private func installTapAndConverter() throws {
        #if DEBUG
            if forcedInstallFailuresForTesting > 0 {
                forcedInstallFailuresForTesting -= 1
                throw AudioCaptureError.converterCreationFailed
            }
            if bypassResampleForTesting {
                // Test mode (``setupForTesting()``): there is no live engine
                // to tap — rebuild only the internal channel + drain so the
                // reconfiguration tests exercise the real rebuild flow.
                installDrainChannel()
                return
            }
        #endif

        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        guard inputFormat.sampleRate > 0 else {
            throw AudioCaptureError.sessionConfigurationFailed(
                "Input node reported sample rate 0; microphone may be unavailable."
            )
        }

        guard let newConverter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw AudioCaptureError.converterCreationFailed
        }
        converter = newConverter
        sourceFormat = inputFormat

        // Build the internal tap→actor channel and its single drain consumer.
        //
        // Buffering policy: `.unbounded`. The tap thread yields synchronously
        // and must never block a CoreAudio render callback, and the original
        // per-Task design processed *every* frame; `.unbounded` preserves that
        // "no frame dropped at the channel" behavior. If the drain consumer
        // stalls (e.g. a slow resample), payloads accumulate in the channel
        // rather than being dropped — backed by memory, not by silently losing
        // capture data. A stalled consumer therefore grows memory; it does not
        // drop or reorder frames.
        let tapContinuation = installDrainChannel()

        // The tap closure runs on a CoreAudio render thread. It must NOT touch
        // actor-isolated state and must NOT spawn a Task. It copies the
        // buffer's samples into a `Sendable` ``TapPayload`` and yields it
        // synchronously into the internal channel; FIFO order is established
        // here, on the serially-invoked tap thread, and preserved to the single
        // drain consumer.
        inputNode.installTap(
            onBus: 0,
            bufferSize: 4096,
            format: inputFormat
        ) { buffer, time in
            guard let samples = Self.extractSamples(from: buffer) else { return }
            let payload = TapPayload(samples: samples, hostTime: time.hostTime)
            tapContinuation.yield(payload)
        }
    }

    /// Builds the internal tap→actor channel and its single drain consumer,
    /// returning the continuation the tap closure yields into.
    ///
    /// Single ordered consumer: one `for await` loop drains the channel and
    /// routes every payload through ``ingest(payload:)`` on the actor, so
    /// resample / level emission / frame yield all stay serialized in
    /// capture order. Exactly one drain task exists per installed tap;
    /// ``teardownDrain()`` cancels it before any reinstall.
    @discardableResult
    private func installDrainChannel() -> AsyncStream<TapPayload>.Continuation {
        // Self-defending: every designed caller tears down first, but if a
        // future path (or a stale-retry bug) reaches here with a live
        // channel, finish + cancel it rather than orphaning a drain task
        // and an abandoned continuation. Idempotent when already torn down.
        teardownDrain()

        let (tapStream, tapContinuation) = AsyncStream<TapPayload>.makeStream(
            bufferingPolicy: .unbounded
        )
        tapFrameContinuation = tapContinuation
        drainTask = Task { [weak self] in
            for await payload in tapStream {
                await self?.ingest(payload: payload)
            }
        }
        return tapContinuation
    }

    /// Copies the first channel of `buffer` into a flat `[Float]` on the
    /// CoreAudio render thread. Returns `nil` when the buffer has no float
    /// channel data or is empty.
    ///
    /// Runs inside the tap closure (nonisolated). It deliberately does NOT
    /// resample: the resample needs the actor-isolated ``converter`` and runs
    /// later in ``ingest(payload:)``. Only `Sendable` `[Float]` leaves this
    /// function.
    private nonisolated static func extractSamples(from buffer: AVAudioPCMBuffer) -> [Float]? {
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0, let channelData = buffer.floatChannelData else { return nil }
        return Array(UnsafeBufferPointer(start: channelData[0], count: frameLength))
    }

    /// Resamples one channel payload to 16 kHz, emits a frame on
    /// ``frameStream()``, and throttle-emits an RMS level on ``levelStream()``.
    ///
    /// Called only from the single ``drainTask`` loop, so all access to
    /// ``converter`` / ``levelEmitter`` / the public continuations stays
    /// serialized on the actor and in capture order.
    private func ingest(payload: TapPayload) {
        #if DEBUG
            // Test mode skips the AVAudioConverter resample (the seam feeds
            // payloads that are already at the target rate). The resample would
            // couple ordering tests to process-global CoreAudio state, which is
            // unstable across tests in one process. Ordering — the thing under
            // test — is established by the single drain consumer and is fully
            // exercised either way: the payload still flows through the same
            // channel, the same drain loop, and the same ``emit(samples:hostTime:)``.
            if bypassResampleForTesting {
                emit(samples: payload.samples, hostTime: payload.hostTime)
                return
            }
        #endif

        guard let converter, let sourceFormat else { return }

        let samples: [Float]
        do {
            guard let sourceBuffer = Self.makeSourceBuffer(
                from: payload.samples,
                format: sourceFormat
            ) else { return }
            samples = try resample(sourceBuffer, using: converter, targetFormat: targetFormat)
        } catch {
            // Drop the frame on conversion failure rather than tear down the
            // whole session; route changes will recreate the converter.
            return
        }

        emit(samples: samples, hostTime: payload.hostTime)
    }

    /// Builds an ``AudioFrame`` from resampled `samples` and the payload's
    /// `hostTime`, emits it on ``frameStream()``, and throttle-emits an RMS
    /// level on ``levelStream()``.
    ///
    /// Called only from the single ``drainTask`` loop (via ``ingest(payload:)``),
    /// so all access to ``levelEmitter`` and the public continuations stays
    /// serialized on the actor and in capture order.
    private func emit(samples: [Float], hostTime: UInt64) {
        guard !samples.isEmpty else { return }

        let frame = AudioFrame(
            samples: samples,
            hostTime: hostTime,
            frameCount: samples.count
        )
        frameContinuation?.yield(frame)

        let level = Self.normalizedRMS(samples: samples)
        if levelEmitter.shouldEmit(now: ContinuousClock.now) {
            levelContinuation?.yield(level)
        }
    }

    /// Rebuilds a source `AVAudioPCMBuffer` from the channel's raw samples and
    /// the tap's input `format`, so the actor-side ``resample(_:using:targetFormat:)``
    /// can run on the actor. Returns `nil` if the buffer cannot be allocated.
    ///
    /// The buffer is reconstructed here, on the actor, rather than carried
    /// across the channel because `AVAudioPCMBuffer` is non-`Sendable`.
    private static func makeSourceBuffer(
        from samples: [Float],
        format: AVAudioFormat
    ) -> AVAudioPCMBuffer? {
        let frameCount = AVAudioFrameCount(samples.count)
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let channelData = buffer.floatChannelData
        else { return nil }
        buffer.frameLength = frameCount
        samples.withUnsafeBufferPointer { source in
            guard let base = source.baseAddress else { return }
            channelData[0].update(from: base, count: samples.count)
        }
        return buffer
    }

    /// Computes the mean-square energy of `samples` and converts it to a
    /// normalized `[0, 1]` value suitable for a VU meter.
    ///
    /// - Floor of `-60 dB` clamps near-silence to `0`.
    /// - Ceiling of `0 dB` clamps clipping to `1`.
    static func normalizedRMS(samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        var sumSquares: Float = 0
        for sample in samples {
            sumSquares += sample * sample
        }
        let meanSquare = sumSquares / Float(samples.count)
        guard meanSquare > 0 else { return 0 }
        let rms = sqrtf(meanSquare)
        // Convert to dBFS, clamp to floor.
        let dBFS = 20.0 * log10f(rms)
        let floorDB: Float = -60.0
        if dBFS <= floorDB { return 0 }
        if dBFS >= 0 { return 1 }
        return (dBFS - floorDB) / -floorDB
    }

    // MARK: - Route change handling

    private func registerRouteChangeObserver() {
        let center = NotificationCenter.default
        let observer = center.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: nil
        ) { [weak self] _ in
            Task { [weak self] in
                await self?.handleEngineReconfiguration()
            }
        }
        routeChangeObserver = observer
    }

    private func unregisterRouteChangeObserver() {
        if let observer = routeChangeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        routeChangeObserver = nil
    }

    /// Rebuilds the tap + converter when the engine's I/O configuration
    /// changes (route change — headphones, Bluetooth, or the route settling
    /// moments after ``start()`` on a physical device; the simulator never
    /// fires this, which is how the old failure branch shipped untested).
    ///
    /// ## Scheduling assumptions (Concurrency design discipline)
    ///
    /// - The `AVAudioEngineConfigurationChange` notification arrives on an
    ///   arbitrary queue and hops onto this actor via an unstructured `Task`,
    ///   so a reconfiguration can interleave with ``stop()`` or a newer
    ///   reconfiguration. Latest event wins: each entry cancels any pending
    ///   retry, and the retry re-checks ``isRunning`` after its delay so a
    ///   ``stop()`` that lands inside the retry window wins.
    /// - Mid-transition, the input node can transiently report an unusable
    ///   format (sample rate 0) or reject converter creation. The rebuild is
    ///   therefore retried ONCE after ``reconfigurationRetryDelay``. If the
    ///   retry also fails (or the engine cannot restart), capture winds down
    ///   through ``teardownCapture()`` — engine stopped, microphone
    ///   released, streams finished — and is NEVER left as a zombie (engine
    ///   running while ``isRunning`` is `false`).
    ///
    /// Violated-assumption behaviour: a `stop()` racing the retry window
    /// tears down first and the retry no-ops on its ``isRunning`` re-check;
    /// back-to-back reconfigurations cancel the older retry. The zombie
    /// shape this contract forbids is exactly the 2026-06-10 on-device bug:
    /// the old failure branch flipped ``isRunning`` without stopping the
    /// engine, so the mic stayed held, `stop()` early-returned, and the
    /// next `start()` failed invisibly.
    ///
    /// Violation tests (suite `AudioCaptureActor`):
    /// `reconfiguration_transientFailure_recoversOnRetry`,
    /// `reconfiguration_persistentFailure_tearsDownCleanly_streamsFinish`,
    /// `reconfiguration_stopDuringRetryWindow_stopWins_retryDoesNotResurrect`,
    /// `reconfiguration_backToBackPasses_staleRetryNoOps_singleChannelSurvives`.
    private func handleEngineReconfiguration() {
        reconfigurationGeneration += 1
        reconfigurationRetryTask?.cancel()
        reconfigurationRetryTask = nil
        guard isRunning else { return }

        Self.log.notice("Engine reconfiguration: rebuilding tap + converter")
        engine.inputNode.removeTap(onBus: 0)

        // Tear down the prior drain consumer and internal channel BEFORE
        // reinstalling. ``installTapAndConverter()`` creates a fresh channel +
        // drain task; without this teardown the old continuation would be
        // orphaned (the reinstalled tap yields into a finished/abandoned
        // continuation) and two drain tasks would race over actor state. This
        // ordering is the most lifecycle-sensitive part of the route-change
        // path.
        teardownDrain()

        rebuildAfterReconfiguration(attempt: 1)
    }

    /// Delay before the single reconfiguration-rebuild retry: long enough
    /// for a route transition to settle, short enough to lose only a
    /// fraction of a second of audio.
    private static let reconfigurationRetryDelay: Duration = .milliseconds(300)

    /// One rebuild attempt. `attempt == 1` schedules a retry on failure;
    /// `attempt == 2` (the retry) winds capture down on failure. See
    /// ``handleEngineReconfiguration()`` for the full contract.
    private func rebuildAfterReconfiguration(attempt: Int) {
        do {
            try installTapAndConverter()
        } catch {
            if attempt == 1 {
                Self.log.error("Reconfiguration rebuild failed (attempt 1), retrying in 300ms: \(String(describing: error), privacy: .public)")
                let generation = reconfigurationGeneration
                reconfigurationRetryTask = Task { [weak self] in
                    try? await Task.sleep(for: Self.reconfigurationRetryDelay)
                    guard !Task.isCancelled else { return }
                    await self?.retryReconfigurationRebuild(generation: generation)
                }
            } else {
                Self.log.error("Reconfiguration rebuild failed after retry — tearing down capture: \(String(describing: error), privacy: .public)")
                unregisterRouteChangeObserver()
                teardownCapture()
            }
            return
        }

        #if DEBUG
            if bypassResampleForTesting {
                // Test mode: there is no live engine to restart — the rebuild
                // ends at the reinstalled drain channel.
                return
            }
        #endif

        if !engine.isRunning {
            do {
                try engine.start()
            } catch {
                Self.log.error("Engine restart after reconfiguration failed — tearing down capture: \(String(describing: error), privacy: .public)")
                unregisterRouteChangeObserver()
                teardownCapture()
                return
            }
        }
        Self.log.notice("Engine reconfiguration complete (attempt \(attempt))")
    }

    /// Retry entry point. Re-checks both staleness gates because the retry
    /// crossed a suspension (its delay) and an actor hop: ``isRunning``
    /// because a ``stop()`` may have landed during the delay (stop wins),
    /// and the generation stamp because a NEWER reconfiguration may have
    /// superseded this pass after the retry passed its cancellation check
    /// (a stale rebuild here would double-install a tap over the newer
    /// pass's work). A stale retry must also not touch
    /// ``reconfigurationRetryTask`` — the slot may already belong to the
    /// newer pass.
    private func retryReconfigurationRebuild(generation: Int) {
        guard generation == reconfigurationGeneration else { return }
        reconfigurationRetryTask = nil
        guard isRunning else { return }
        rebuildAfterReconfiguration(attempt: 2)
    }

    deinit {
        if let observer = routeChangeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - #if DEBUG diagnostics

    #if DEBUG
        /// Test-only flag: when set, ``ingest(payload:)`` skips the
        /// `AVAudioConverter` resample and treats the payload's samples as
        /// already at the target rate. Set by ``setupForTesting()``. Lets the
        /// ordering contract be exercised without coupling to process-global
        /// CoreAudio converter state. ``installTapAndConverter()`` also
        /// branches on it so reconfiguration tests rebuild only the internal
        /// channel (no live engine to tap).
        private var bypassResampleForTesting = false

        /// Counts ``teardownCapture()`` executions. Lets the reconfiguration
        /// violation tests assert exactly-one clean teardown (and that a
        /// stale retry never resurrects or double-tears-down). Test-only.
        private(set) var fullTeardownCountForTesting = 0

        /// When > 0, ``installTapAndConverter()`` throws
        /// ``AudioCaptureError/converterCreationFailed`` and decrements —
        /// the seam that drives the reconfiguration rebuild into its
        /// failure branches. Test-only.
        private var forcedInstallFailuresForTesting = 0

        /// Arms ``forcedInstallFailuresForTesting``. Test-only.
        func setForcedInstallFailuresForTesting(_ count: Int) {
            forcedInstallFailuresForTesting = count
        }

        /// Exposes ``isRunning`` so reconfiguration tests can assert the
        /// bookkeeping side of the "isRunning mirrors the engine"
        /// invariant. Test-only.
        var isRunningForTesting: Bool {
            isRunning
        }

        /// Drives the (private) reconfiguration handler, exactly as the
        /// `AVAudioEngineConfigurationChange` notification would. Test-only.
        func triggerReconfigurationForTesting() {
            handleEngineReconfiguration()
        }

        /// Test-only setup that wires the internal tap→actor channel and its
        /// single drain consumer WITHOUT a live `AVAudioEngine`, so the
        /// ordering contract can be exercised in a unit test.
        ///
        /// It mirrors the production path in ``installTapAndConverter()``: it
        /// builds the same `.unbounded` internal channel and the same single
        /// drain task that calls ``ingest(payload:)``. Payloads fed via
        /// ``ingestForTesting(_:)`` flow through the exact same channel and the
        /// exact same single drain consumer the production tap uses — and out
        /// through the same ``emit(samples:hostTime:)`` — so the test proves the
        /// real ordering behavior. The only step skipped is the resample
        /// arithmetic (via ``bypassResampleForTesting``), which is irrelevant to
        /// ordering and otherwise couples the test to unstable process-global
        /// CoreAudio state.
        ///
        /// Wires the public ``frameStream()`` / ``levelStream()`` continuations
        /// and returns them so the test can observe emitted frames.
        func setupForTesting() -> (frames: AsyncStream<AudioFrame>, levels: AsyncStream<Float>) {
            let frames = frameStream()
            let levels = levelStream()

            bypassResampleForTesting = true
            installDrainChannel()
            isRunning = true
            return (frames, levels)
        }

        /// Submits one frame through the SAME internal serial channel the
        /// production tap yields into. The single drain consumer resamples
        /// (identity, under ``setupForTesting()``), frames, and emits it on
        /// ``frameStream()`` in submission order. Test-only.
        ///
        /// - Note: ordering is established at `yield` time, exactly as in
        ///   production. Concurrent callers are serialized by the actor at the
        ///   `yield` call and by the single consumer at the `for await` loop.
        func ingestForTesting(_ frame: AudioFrame) async {
            tapFrameContinuation?.yield(
                TapPayload(samples: frame.samples, hostTime: frame.hostTime)
            )
        }

        /// Deterministically waits until every frame submitted via
        /// ``ingestForTesting(_:)`` has been fully processed by the single
        /// drain consumer. Finishes the internal channel and awaits the drain
        /// task's completion — modeled on
        /// `TranslationActor.awaitUpstreamDrained()`. No `Task.sleep`.
        /// Test-only.
        func awaitFramesDrained() async {
            tapFrameContinuation?.finish()
            tapFrameContinuation = nil
            await drainTask?.value
        }

        /// Returns `true` while a drain task exists, `false` after teardown.
        /// Lets the lifecycle test assert ``stop()`` cancelled and niled the
        /// single drain consumer. Test-only.
        func hasActiveDrainTask() -> Bool {
            drainTask != nil
        }
    #endif
}
