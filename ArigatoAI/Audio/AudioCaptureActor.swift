//
//  AudioCaptureActor.swift
//  ArigatoAI
//
//  Created by Jose Castell on 2026/05/09.
//

@preconcurrency import AVFAudio
import Foundation

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
    public func start() throws {
        guard !isRunning else {
            throw AudioCaptureError.alreadyRunning
        }

        try configureSession()
        try installTapAndConverter()

        do {
            try engine.start()
        } catch {
            throw AudioCaptureError.engineStartFailed(error.localizedDescription)
        }

        registerRouteChangeObserver()
        isRunning = true
    }

    /// Stops the pipeline, deactivates the audio session, and finishes both
    /// streams. Callers must call ``frameStream()`` and ``levelStream()`` again
    /// after a subsequent ``start()`` to receive new values.
    public func stop() {
        guard isRunning else { return }

        unregisterRouteChangeObserver()
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
        let (tapStream, tapContinuation) = AsyncStream<TapPayload>.makeStream(
            bufferingPolicy: .unbounded
        )
        tapFrameContinuation = tapContinuation

        // Single ordered consumer. One `for await` loop drains the channel and
        // routes every payload through ``ingest(payload:)`` on the actor, so
        // resample / level emission / frame yield all stay serialized in
        // capture order. Exactly one drain task exists per installed tap;
        // ``teardownDrain()`` cancels it before any reinstall.
        drainTask = Task { [weak self] in
            for await payload in tapStream {
                await self?.ingest(payload: payload)
            }
        }

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

    private func handleEngineReconfiguration() {
        guard isRunning else { return }

        engine.inputNode.removeTap(onBus: 0)

        // Tear down the prior drain consumer and internal channel BEFORE
        // reinstalling. ``installTapAndConverter()`` creates a fresh channel +
        // drain task; without this teardown the old continuation would be
        // orphaned (the reinstalled tap yields into a finished/abandoned
        // continuation) and two drain tasks would race over actor state. This
        // ordering is the most lifecycle-sensitive part of the route-change
        // path.
        teardownDrain()

        do {
            try installTapAndConverter()
        } catch {
            // If we cannot rebuild, finish the streams so the consumer sees
            // the failure rather than receiving silence forever.
            frameContinuation?.finish()
            levelContinuation?.finish()
            isRunning = false
            return
        }

        if !engine.isRunning {
            do {
                try engine.start()
            } catch {
                frameContinuation?.finish()
                levelContinuation?.finish()
                isRunning = false
            }
        }
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
        /// CoreAudio converter state.
        private var bypassResampleForTesting = false

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

            let (tapStream, tapContinuation) = AsyncStream<TapPayload>.makeStream(
                bufferingPolicy: .unbounded
            )
            tapFrameContinuation = tapContinuation
            drainTask = Task { [weak self] in
                for await payload in tapStream {
                    await self?.ingest(payload: payload)
                }
            }
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
