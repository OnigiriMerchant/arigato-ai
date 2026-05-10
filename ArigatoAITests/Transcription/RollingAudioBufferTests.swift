//
//  RollingAudioBufferTests.swift
//  ArigatoAITests
//
//  Created by Jose Castell on 2026/05/10.
//

@testable import ArigatoAI
import Darwin.Mach
import Foundation
import Testing

/// Tests for ``RollingAudioBuffer``. Each test references the contract
/// (C1–C6) it enforces, mirroring the discipline that landed Group A and
/// Group B with zero signature-only tests.
@Suite("RollingAudioBuffer")
struct RollingAudioBufferTests {
    // MARK: - Helpers

    /// Builds a frame of `count` samples whose values increase from
    /// `firstValue` by `1.0` per sample. Distinguishable values let tests
    /// assert FIFO order without ambiguity.
    private func makeRampFrame(
        firstValue: Float,
        count: Int,
        hostTime: UInt64 = 0
    ) -> AudioFrame {
        var samples: [Float] = []
        samples.reserveCapacity(count)
        for index in 0 ..< count {
            samples.append(firstValue + Float(index))
        }
        return AudioFrame(samples: samples, hostTime: hostTime, frameCount: count)
    }

    /// Converts `seconds` of elapsed time into mach-tick units using the
    /// same `mach_timebase_info` contract the buffer relies on, so anchor
    /// arithmetic in tests matches the buffer's internal conversion
    /// exactly.
    private func machTicks(forSeconds seconds: Double) -> UInt64 {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        let nanos = seconds * 1_000_000_000.0
        let numer = Double(info.numer)
        let denom = Double(info.denom)
        guard numer > 0 else { return UInt64(nanos.rounded()) }
        return UInt64((nanos * denom / numer).rounded())
    }

    // MARK: - init

    @Test("init converts capacitySeconds to samples at the configured sample rate")
    func init_capacitySecondsIsConverted_correctly() {
        let buffer = RollingAudioBuffer(capacitySeconds: 5, sampleRate: 16000)
        #expect(buffer.capacityInSamples == 80000)
        #expect(buffer.sampleRate == 16000)
        #expect(buffer.count == 0)
        #expect(buffer.anchorHostTime == nil)
    }

    // MARK: - append

    @Test("appending below capacity retains every sample")
    func append_belowCapacity_retainsAllSamples() {
        var buffer = RollingAudioBuffer(capacitySeconds: 5, sampleRate: 16000)
        // 3 seconds of audio in three 1-second frames.
        for second in 0 ..< 3 {
            let frame = makeRampFrame(
                firstValue: Float(second * 16000),
                count: 16000,
                hostTime: UInt64(second) * 1000
            )
            buffer.append(frame)
        }
        #expect(buffer.count == 48000)
    }

    /// Contract C1: older samples are dropped FIFO when capacity is exceeded.
    @Test("appending beyond capacity drops oldest samples FIFO")
    func append_overCapacity_dropsOldestFIFO() {
        // Capacity 5 s × 16 kHz = 80 000 samples. Append 7 s ramped 0..<112_000.
        var buffer = RollingAudioBuffer(capacitySeconds: 5, sampleRate: 16000)
        let frame = makeRampFrame(firstValue: 0, count: 16000 * 7, hostTime: 0)
        buffer.append(frame)
        #expect(buffer.count == 80000)

        // The oldest 32 000 samples (2 s) should have been dropped, so the
        // buffer should now contain values 32_000..<112_000 in order.
        guard let window = buffer.trailingWindow(seconds: 5) else {
            Issue.record("Expected a 5 s trailing window after 7 s of input")
            return
        }
        #expect(window.samples.count == 80000)
        #expect(window.samples.first == 32000.0)
        #expect(window.samples.last == 111_999.0)
    }

    @Test("anchorHostTime is set on the first non-empty append to that frame's hostTime")
    func anchorHostTime_isSetOnFirstAppend_toFrameHostTime() {
        var buffer = RollingAudioBuffer(capacitySeconds: 5, sampleRate: 16000)
        // Empty frame is a no-op and must NOT set the anchor.
        buffer.append(AudioFrame(samples: [], hostTime: 999, frameCount: 0))
        #expect(buffer.anchorHostTime == nil)

        let frame = makeRampFrame(firstValue: 0, count: 1000, hostTime: 12345)
        buffer.append(frame)
        #expect(buffer.anchorHostTime == 12345)
    }

    /// Contract C2: anchorHostTime is the host time of the oldest sample
    /// still in the buffer, advancing by the tick delta of dropped samples.
    @Test("anchorHostTime advances by the tick delta of dropped samples on overflow")
    func anchorHostTime_advancesWhenOldestSamplesAreDropped() {
        var buffer = RollingAudioBuffer(capacitySeconds: 5, sampleRate: 16000)
        let frame = makeRampFrame(firstValue: 0, count: 16000 * 7, hostTime: 1_000_000)
        buffer.append(frame)

        // 32 000 samples were dropped (2 seconds) → expected anchor advance
        // is `machTicks(forSeconds: 2)` from the original 1_000_000.
        let expected = 1_000_000 &+ machTicks(forSeconds: 32000.0 / 16000.0)
        #expect(buffer.anchorHostTime == expected)
    }

    // MARK: - trailingWindow

    /// Contract C3: nil when the buffer holds fewer than `seconds`.
    @Test("trailingWindow returns nil when buffer holds fewer than the requested seconds")
    func trailingWindow_belowSeconds_returnsNil() {
        var buffer = RollingAudioBuffer(capacitySeconds: 5, sampleRate: 16000)
        let frame = makeRampFrame(firstValue: 0, count: 16000 * 3, hostTime: 0)
        buffer.append(frame)
        #expect(buffer.trailingWindow(seconds: 5) == nil)
    }

    /// Contract C4: returns exactly `seconds * sampleRate` samples and the
    /// anchor of the first sample in that slice.
    @Test("trailingWindow returns the exact sample count and the correct slice anchor")
    func trailingWindow_returnsExactSampleCountAndCorrectAnchor() {
        var buffer = RollingAudioBuffer(capacitySeconds: 7, sampleRate: 16000)
        let frame = makeRampFrame(firstValue: 0, count: 16000 * 7, hostTime: 5_000_000)
        buffer.append(frame)

        guard let window = buffer.trailingWindow(seconds: 5) else {
            Issue.record("Expected a 5 s window from a 7 s buffer")
            return
        }
        #expect(window.samples.count == 80000)
        // Slice values should be 32_000..<112_000 (the trailing 5 s of a 7 s ramp).
        #expect(window.samples.first == 32000.0)
        #expect(window.samples.last == 111_999.0)
        // Anchor should be original anchor advanced by 32 000 samples == 2 s.
        let expectedAnchor = 5_000_000 &+ machTicks(forSeconds: 32000.0 / 16000.0)
        #expect(window.anchorHostTime == expectedAnchor)
    }

    @Test("trailingWindow does not mutate the buffer")
    func trailingWindow_doesNotMutate() {
        var buffer = RollingAudioBuffer(capacitySeconds: 5, sampleRate: 16000)
        let frame = makeRampFrame(firstValue: 0, count: 16000 * 5, hostTime: 42)
        buffer.append(frame)

        let first = buffer.trailingWindow(seconds: 4)
        let second = buffer.trailingWindow(seconds: 4)
        #expect(first?.samples == second?.samples)
        #expect(first?.anchorHostTime == second?.anchorHostTime)
        #expect(buffer.count == 16000 * 5)
        #expect(buffer.anchorHostTime == 42)
    }

    // MARK: - remainingWindow

    /// Contract C6: nil when buffer holds fewer than `minSeconds`.
    @Test("remainingWindow returns nil when buffer holds fewer than minSeconds")
    func remainingWindow_belowMinimum_returnsNil() {
        var buffer = RollingAudioBuffer(capacitySeconds: 5, sampleRate: 16000)
        // 0.3 s of audio at 16 kHz = 4 800 samples.
        let frame = makeRampFrame(firstValue: 0, count: 4800, hostTime: 0)
        buffer.append(frame)
        #expect(buffer.remainingWindow(minSeconds: 0.5) == nil)
    }

    /// Contract C6: returns all currently-buffered samples otherwise.
    @Test("remainingWindow returns every buffered sample when above minSeconds")
    func remainingWindow_aboveMinimum_returnsAll() {
        var buffer = RollingAudioBuffer(capacitySeconds: 5, sampleRate: 16000)
        // 1.7 s × 16 kHz = 27 200 samples.
        let frame = makeRampFrame(firstValue: 0, count: 27200, hostTime: 7777)
        buffer.append(frame)

        guard let window = buffer.remainingWindow(minSeconds: 0.5) else {
            Issue.record("Expected remaining window for a 1.7 s buffer with min 0.5 s")
            return
        }
        #expect(window.samples.count == 27200)
        #expect(window.samples.first == 0.0)
        #expect(window.samples.last == 27199.0)
        #expect(window.anchorHostTime == 7777)
    }

    // MARK: - performance guard (C5)

    /// Contract C5: append is O(1) amortised. A regression to per-frame
    /// reallocation would blow this budget by orders of magnitude even on a
    /// slow CI runner.
    @Test("appending many frames completes under a generous wall-clock budget")
    func append_largeNumberOfFrames_completesUnderTimeBudget() {
        var buffer = RollingAudioBuffer(capacitySeconds: 5, sampleRate: 16000)
        let frame = AudioFrame(samples: [0.5], hostTime: 0, frameCount: 1)

        let start = Date()
        for _ in 0 ..< 100_000 {
            buffer.append(frame)
        }
        let elapsed = Date().timeIntervalSince(start)
        // Generous: well under a second on real hardware, leaving headroom
        // for noisy CI. Anything quadratic would be tens of seconds.
        #expect(elapsed < 5.0)
        #expect(buffer.count == 80000)
    }
}
