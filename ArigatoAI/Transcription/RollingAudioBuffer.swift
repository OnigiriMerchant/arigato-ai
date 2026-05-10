//
//  RollingAudioBuffer.swift
//  ArigatoAI
//
//  Created by Jose Castell on 2026/05/10.
//

import Darwin.Mach
import Foundation

/// Fixed-capacity rolling PCM buffer used by `TranscriptionActor` to assemble
/// trailing audio windows for Whisper inference.
///
/// The buffer stores 16 kHz mono `Float32` samples in append order. Older
/// samples are dropped FIFO when capacity is exceeded; this is contract
/// **C1**. The buffer also tracks the mach host time of the oldest sample
/// still in the buffer (contract **C2**) so callers can convert
/// sample-relative offsets back into the same absolute clock that
/// `AudioFrame.hostTime` uses.
///
/// Sample-rate validation is intentionally NOT performed here: the buffer
/// trusts that every appended ``AudioFrame`` was produced at the configured
/// `sampleRate`. That validation belongs to `TranscriptionActor`, which owns
/// the upstream resampler.
///
/// Capacity of `0` seconds is a precondition violation. A degenerate buffer
/// has no useful semantics and the type makes the failure mode loud rather
/// than silently swallowing every append.
///
/// **Time units.** `anchorHostTime` is in mach absolute units (the same
/// clock as `AudioFrame.hostTime`, sourced from `mach_absolute_time`). When
/// the buffer drops `k` samples it advances the anchor by the tick delta
/// corresponding to `k / sampleRate` seconds, computed via the system's
/// `mach_timebase_info` so the math is correct on every Apple Silicon
/// generation regardless of timebase numerator/denominator.
///
/// The buffer is a `Sendable` value type and is the implementation detail
/// of a single owning actor. It has no internal locking — every mutation
/// is protected by the actor that owns the value.
///
/// `nonisolated` is applied explicitly because the project sets
/// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`. Without it, methods on
/// the buffer would be main-actor isolated, which would prevent
/// ``TranscriptionActor`` (a non-main actor) from constructing or
/// mutating its own owned buffer.
nonisolated struct RollingAudioBuffer {
    /// Maximum number of samples retained at any time. Computed from the
    /// `capacitySeconds` and `sampleRate` passed to ``init(capacitySeconds:sampleRate:)``.
    let capacityInSamples: Int

    /// Sample rate the buffer assumes for every appended frame, in hertz.
    let sampleRate: Double

    /// Mach host time of the oldest sample still in the buffer, or `nil`
    /// while the buffer is empty (contract **C2**). Set on the first
    /// non-empty append and advanced on every FIFO drop.
    private(set) var anchorHostTime: UInt64?

    /// Backing storage. We use a single `[Float]` reserved up to
    /// `capacityInSamples` and slice off the front when over capacity.
    /// Although `removeFirst(k)` on `Array` is `O(n)` in the worst case,
    /// `reserveCapacity` plus a never-growing length keeps amortised
    /// `append` cost bounded; the perf-guard test (contract **C5**)
    /// catches accidental regressions if the implementation ever starts
    /// reallocating per frame.
    private var samples: [Float]

    /// Currently-buffered sample count.
    var count: Int {
        samples.count
    }

    /// Creates a rolling buffer sized to hold the trailing
    /// `capacitySeconds` of audio at the given `sampleRate`.
    ///
    /// `capacityInSamples` is computed by rounding `capacitySeconds *
    /// sampleRate` to the nearest integer, so a 5-second buffer at 16 kHz
    /// holds exactly 80,000 samples.
    ///
    /// - Parameters:
    ///   - capacitySeconds: Trailing window the buffer will keep. Must be
    ///     strictly positive; otherwise the initializer traps via
    ///     `precondition`.
    ///   - sampleRate: Sample rate in hertz. Defaults to 16,000 Hz, which
    ///     matches WhisperKit's required input format and the resampler
    ///     output produced by ``AudioCaptureActor``.
    init(capacitySeconds: Double, sampleRate: Double = 16000) {
        precondition(
            capacitySeconds > 0,
            "RollingAudioBuffer requires a strictly positive capacity in seconds; got \(capacitySeconds)."
        )
        precondition(
            sampleRate > 0,
            "RollingAudioBuffer requires a strictly positive sample rate; got \(sampleRate)."
        )
        self.sampleRate = sampleRate
        capacityInSamples = Int((capacitySeconds * sampleRate).rounded())
        samples = []
        samples.reserveCapacity(capacityInSamples)
    }

    /// Appends an ``AudioFrame`` to the buffer, dropping older samples
    /// FIFO when capacity is exceeded (contract **C1**).
    ///
    /// Behaviour:
    /// - An empty `frame.samples` is a no-op. The anchor is set only on
    ///   the first non-empty append.
    /// - On the first non-empty append, ``anchorHostTime`` is set to
    ///   `frame.hostTime`.
    /// - When samples are dropped, ``anchorHostTime`` is advanced by the
    ///   tick delta corresponding to the dropped sample count (contract
    ///   **C2**).
    /// - Amortised cost is `O(1)` per appended sample (contract **C5**).
    ///
    /// - Parameter frame: The audio frame to append. The frame's sample
    ///   rate is trusted to match the buffer's; mismatch is the caller's
    ///   responsibility (typically `TranscriptionActor`).
    mutating func append(_ frame: AudioFrame) {
        guard frame.samples.isEmpty == false else { return }

        if anchorHostTime == nil {
            anchorHostTime = frame.hostTime
        }

        samples.append(contentsOf: frame.samples)

        let overflow = samples.count - capacityInSamples
        if overflow > 0 {
            samples.removeFirst(overflow)
            advanceAnchor(by: overflow)
        }
    }

    /// Returns the trailing `seconds` of audio along with the host time of
    /// the first sample of that slice (contracts **C3** and **C4**).
    ///
    /// - Parameter seconds: Window length in seconds. Rounded to the
    ///   nearest sample count via `seconds * sampleRate`.
    /// - Returns: A tuple of `(samples, anchorHostTime)`, or `nil` when
    ///   the buffer holds fewer than `seconds` of audio. The returned
    ///   `samples` array always contains exactly
    ///   `Int((seconds * sampleRate).rounded())` elements when non-`nil`.
    ///
    /// The buffer is not mutated.
    func trailingWindow(seconds: Double) -> (samples: [Float], anchorHostTime: UInt64)? {
        let requested = Int((seconds * sampleRate).rounded())
        guard requested > 0, samples.count >= requested else { return nil }
        guard let anchor = anchorHostTime else { return nil }

        let droppedFromAnchor = samples.count - requested
        let sliceAnchor = anchorHostTime(byAdvancing: anchor, sampleCount: droppedFromAnchor)
        let slice = Array(samples.suffix(requested))
        return (slice, sliceAnchor)
    }

    /// Returns every currently-buffered sample along with the buffer's
    /// anchor host time, but only when the buffer holds at least
    /// `minSeconds` of audio (contract **C6**).
    ///
    /// Used by `TranscriptionActor` at end-of-recording to flush any
    /// partial tail that's shorter than the regular sliding window but
    /// still long enough to be worth transcribing.
    ///
    /// - Parameter minSeconds: Minimum duration the buffer must hold for a
    ///   non-`nil` return.
    /// - Returns: All buffered samples with the current ``anchorHostTime``,
    ///   or `nil` when the buffer holds less than `minSeconds`.
    ///
    /// The buffer is not mutated.
    func remainingWindow(minSeconds: Double) -> (samples: [Float], anchorHostTime: UInt64)? {
        let minimum = Int((minSeconds * sampleRate).rounded())
        guard samples.count >= minimum, samples.isEmpty == false else { return nil }
        guard let anchor = anchorHostTime else { return nil }
        return (samples, anchor)
    }

    // MARK: - Private

    /// Advances ``anchorHostTime`` by the mach-tick delta corresponding
    /// to `sampleCount` samples at ``sampleRate``.
    private mutating func advanceAnchor(by sampleCount: Int) {
        guard let current = anchorHostTime, sampleCount > 0 else { return }
        anchorHostTime = anchorHostTime(byAdvancing: current, sampleCount: sampleCount)
    }

    /// Pure helper that returns `base` advanced by `sampleCount` samples
    /// worth of mach ticks. Factored out so both ``append(_:)`` (which
    /// mutates the stored anchor) and ``trailingWindow(seconds:)`` (which
    /// computes a slice anchor without mutation) share one conversion.
    private func anchorHostTime(
        byAdvancing base: UInt64,
        sampleCount: Int
    ) -> UInt64 {
        guard sampleCount > 0 else { return base }
        let nanos = (Double(sampleCount) / sampleRate) * 1_000_000_000.0
        let ticks = RollingAudioBuffer.machTicks(forNanoseconds: nanos)
        return base &+ ticks
    }

    /// Converts a nanosecond count into mach-absolute ticks using the
    /// system's `mach_timebase_info`. The `mach_timebase_info` contract is
    /// `nanos = ticks * numer / denom`, so `ticks = nanos * denom / numer`.
    private static func machTicks(forNanoseconds nanos: Double) -> UInt64 {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        let numer = Double(info.numer)
        let denom = Double(info.denom)
        guard numer > 0 else { return UInt64(nanos.rounded()) }
        let ticks = (nanos * denom / numer).rounded()
        guard ticks >= 0 else { return 0 }
        return UInt64(ticks)
    }
}
