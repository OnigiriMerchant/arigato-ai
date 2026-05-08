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
/// executor. The CoreAudio tap callback hops onto the actor via a `Task`.
public actor AudioCaptureActor {
    /// Target sample rate for downstream consumers (WhisperKit's input rate).
    public static let targetSampleRate: Double = 16000

    private let engine: AVAudioEngine
    private var converter: AVAudioConverter?
    private let targetFormat: AVAudioFormat

    private var frameContinuation: AsyncStream<AudioFrame>.Continuation?
    private var levelContinuation: AsyncStream<Float>.Continuation?

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

        frameContinuation?.finish()
        frameContinuation = nil
        levelContinuation?.finish()
        levelContinuation = nil

        converter = nil
        levelEmitter = LevelEmitter(targetHz: 12.0)
        isRunning = false
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

        // The tap closure runs on a CoreAudio render thread. It must not
        // touch actor-isolated state synchronously; instead, copy the buffer
        // and hop into the actor via a Task. Use guard-cast to honour the
        // no-force-unwrap rule.
        inputNode.installTap(
            onBus: 0,
            bufferSize: 4096,
            format: inputFormat
        ) { [weak self] buffer, time in
            guard let copied = buffer.copy() as? AVAudioPCMBuffer else { return }
            let hostTime = time.hostTime
            Task { [weak self] in
                await self?.ingest(buffer: copied, hostTime: hostTime)
            }
        }
    }

    private func ingest(buffer: AVAudioPCMBuffer, hostTime: UInt64) {
        guard let converter else { return }

        let samples: [Float]
        do {
            samples = try resample(buffer, using: converter, targetFormat: targetFormat)
        } catch {
            // Drop the frame on conversion failure rather than tear down the
            // whole session; route changes will recreate the converter.
            return
        }

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
}
