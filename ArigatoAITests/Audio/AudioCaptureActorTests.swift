//
//  AudioCaptureActorTests.swift
//  ArigatoAITests
//
//  Created by Jose Castell on 2026/06/05.
//

@testable import ArigatoAI
import AVFAudio
import Foundation
import Testing

@Suite("AudioCaptureActor")
struct AudioCaptureActorTests {
    // MARK: - normalizedRMS behavioral coverage

    @Test("normalizedRMS: empty samples returns 0")
    func normalizedRMS_empty_isZero() {
        #expect(AudioCaptureActor.normalizedRMS(samples: []) == 0)
    }

    @Test("normalizedRMS: all-zero samples returns 0")
    func normalizedRMS_allZero_isZero() {
        let samples = [Float](repeating: 0, count: 256)
        #expect(AudioCaptureActor.normalizedRMS(samples: samples) == 0)
    }

    @Test("normalizedRMS: near-silence below -60 dB floor returns 0")
    func normalizedRMS_belowFloor_isZero() {
        // RMS of a constant signal equals its magnitude. -60 dBFS is 10^(-3)
        // = 0.001. A constant 0.0005 is ~-66 dBFS, well below the floor.
        let samples = [Float](repeating: 0.0005, count: 256)
        #expect(AudioCaptureActor.normalizedRMS(samples: samples) == 0)
    }

    @Test("normalizedRMS: clipping (all 1.0) returns 1")
    func normalizedRMS_clipping_isOne() {
        // Constant 1.0 has RMS 1.0 -> 0 dBFS -> clamped to ceiling 1.
        let samples = [Float](repeating: 1.0, count: 256)
        #expect(AudioCaptureActor.normalizedRMS(samples: samples) == 1)
    }

    @Test("normalizedRMS: known mid-range RMS maps to expected normalized value")
    func normalizedRMS_midRange_matchesExpected() {
        // Constant 0.0316 -> RMS 0.0316 -> 20*log10(0.0316) ~= -30 dBFS.
        // Normalized = (dBFS - floor) / -floor = (-30 - -60) / 60 = 0.5.
        let magnitude: Float = 0.0316227766 // 10^(-1.5)
        let samples = [Float](repeating: magnitude, count: 512)
        let value = AudioCaptureActor.normalizedRMS(samples: samples)
        #expect(abs(value - 0.5) < 0.01)
    }

    @Test("normalizedRMS: at exactly the -60 dB floor returns 0")
    func normalizedRMS_atFloor_isZero() {
        // RMS 0.001 == -60 dBFS exactly; the floor is inclusive (<=).
        let samples = [Float](repeating: 0.001, count: 256)
        #expect(AudioCaptureActor.normalizedRMS(samples: samples) == 0)
    }

    // MARK: - Helpers

    /// Builds a single-sample-per-frame ``AudioFrame`` with a known host time.
    /// One sample keeps the identity-resample output count predictable so the
    /// test can map emitted frames back to submissions by host time.
    private static func frame(hostTime: UInt64, value: Float = 0.5) -> AudioFrame {
        AudioFrame(samples: [value], hostTime: hostTime, frameCount: 1)
    }

    // MARK: - Violation test (load-bearing)

    /// Burst half of `C-T-VIOLATION-OUT-OF-ORDER-INGEST`. Drives a simultaneous
    /// burst of concurrent submissions through the actor's internal serial
    /// channel and proves **no-loss / no-dupe / single-consumer serialization**:
    /// every submitted frame is emitted exactly once, whole and non-interleaved.
    ///
    /// This test does **not** assert burst output *order*. See the
    /// "Acceptance-order diagnosis" comment below: the order in which
    /// concurrently-spawned tasks hop onto the actor's executor and `yield` into
    /// the channel is genuinely nondeterministic, so a burst-order assertion
    /// would be asserting on a nondeterministic input. The load-bearing
    /// FIFO / no-reorder proof lives in
    /// ``violation_submissionOrderPreserved()`` (serial submission with
    /// host-time order reversed → emission in exact submission order).
    ///
    /// The serially-submitted *prefix* (phase 1) is fully `await`-submitted and
    /// drained before the burst begins yielding, and the channel is FIFO, so the
    /// first `serialCount` emitted frames are the phase-1 frames in submission
    /// order — that prefix assertion is deterministic.
    ///
    /// Under the OLD per-`Task`-spawn design, independently-scheduled Tasks could
    /// drop or duplicate a frame under back-pressure; the `Set` membership +
    /// exact-count assertions below catch exactly that.
    @Test("C-T-VIOLATION-OUT-OF-ORDER-INGEST: concurrent burst loses no frame and is serialized whole")
    func violation_outOfOrderIngest_staysSerializedAndMonotonic() async {
        let actor = AudioCaptureActor()
        let (frames, _) = await actor.setupForTesting()

        let serialCount = 50
        let burstCount = 50
        let totalCount = serialCount + burstCount

        // Phase 1: serial submission in strictly increasing host-time order.
        // Host times 100, 200, ... keep gaps wide so any reorder is visible.
        for i in 0 ..< serialCount {
            let host = UInt64((i + 1) * 100)
            await actor.ingestForTesting(Self.frame(hostTime: host))
        }

        // Phase 2: a simultaneous burst — many concurrent submissions spawned
        // at once. The actor serializes the yields; the single consumer keeps
        // each one whole.
        //
        // Acceptance-order diagnosis (finding #2): the burst's acceptance order
        // into the channel is GENUINELY NONDETERMINISTIC. Each child task must
        // suspend to hop onto AudioCaptureActor's serial executor before its
        // `ingestForTesting` body (the `yield`) runs. The Swift runtime gives no
        // guarantee for which suspended task the actor's executor resumes first;
        // that depends on cross-thread enqueue timing in the cooperative pool.
        // So the `yield` order — and therefore the emission order — of the burst
        // is not deterministic. We deliberately do NOT assert burst output order
        // (that would be a flaky/fake assertion on a nondeterministic input).
        // We assert only no-loss / no-dupe via Set membership + count below.
        await withTaskGroup(of: Void.self) { group in
            for i in 0 ..< burstCount {
                let host = UInt64((serialCount + i + 1) * 100)
                group.addTask {
                    await actor.ingestForTesting(Self.frame(hostTime: host))
                }
            }
        }

        // Deterministic drain-complete handshake — no Task.sleep. Once this
        // returns, every submitted payload has flowed through the single drain
        // consumer and been yielded onto the (unbounded-buffered) public frame
        // stream, so collecting exactly `totalCount` frames cannot block.
        await actor.awaitFramesDrained()
        let emitted = await Self.collect(totalCount, from: frames)

        // Every submitted frame emitted exactly once (no loss, no duplication).
        #expect(emitted.count == totalCount)

        // The serially-submitted prefix is deterministic: phase 1 is fully
        // drained before the burst begins yielding, and the channel is FIFO, so
        // the first `serialCount` emitted frames are the phase-1 frames in their
        // exact (increasing) submission order.
        let serialPrefix = emitted.prefix(serialCount)
        let serialHosts = serialPrefix.map(\.hostTime)
        for (index, host) in serialHosts.enumerated() {
            #expect(host == UInt64((index + 1) * 100))
        }

        // The full set is order-blind: every expected host time present, none
        // extra, none missing — the no-loss / no-dupe contract for the burst.
        let allHosts = Set(emitted.map(\.hostTime))
        let expectedHosts = Set((1 ... totalCount).map { UInt64($0 * 100) })
        #expect(allHosts == expectedHosts)
    }

    /// Load-bearing FIFO / no-reorder + no-mis-anchor proof for
    /// `C-T-VIOLATION-OUT-OF-ORDER-INGEST`. When the *submission* order differs
    /// from host-time order, the single consumer must preserve **submission**
    /// order (FIFO at yield), NOT host-time order — and that emission order,
    /// fed end-to-end into a `RollingAudioBuffer`, must anchor the buffer to the
    /// first *submitted* (= first *emitted*) frame, NOT to the minimum host time.
    ///
    /// This is the real no-reorder discriminator: a pipe that sorted by host
    /// time would emit `[100, 200, 300, 400, 500]` (and anchor 100); a faithful
    /// FIFO pipe emits the decreasing submission order and anchors 500.
    @Test("C-T-VIOLATION-OUT-OF-ORDER-INGEST: submission order is preserved regardless of host-time order")
    func violation_submissionOrderPreserved() async {
        let actor = AudioCaptureActor()
        let (frames, _) = await actor.setupForTesting()

        // Submit serially with host times in DECREASING order. A faithful FIFO
        // pipe emits them in submission order (decreasing), proving the channel
        // does not sort and does not reorder.
        let submissionOrder: [UInt64] = [500, 400, 300, 200, 100]
        for host in submissionOrder {
            await actor.ingestForTesting(Self.frame(hostTime: host))
        }

        await actor.awaitFramesDrained()
        let emittedFrames = await Self.collect(submissionOrder.count, from: frames)
        let emitted = emittedFrames.map(\.hostTime)
        #expect(emitted == submissionOrder)

        // No-mis-anchor, end-to-end through emit (finding #3): feed the actor's
        // EMISSION-ORDER output (decreasing) into a RollingAudioBuffer. The
        // buffer anchors to its FIRST non-empty append, so a faithful FIFO
        // emission anchors to 500 (the first submitted/emitted frame). If the
        // actor had reordered or sorted by host time, the first emitted would be
        // 100 and the anchor would wrongly be 100 — so this assertion genuinely
        // discriminates against a mis-anchoring reorder, unlike feeding an
        // already-ascending prefix (which would test only the buffer's own
        // first-append logic).
        var buffer = RollingAudioBuffer(capacitySeconds: 100, sampleRate: 16000)
        for frame in emittedFrames {
            buffer.append(frame)
        }
        let firstEmittedHost = submissionOrder[0] // 500
        #expect(buffer.anchorHostTime == firstEmittedHost)
    }

    /// Collects exactly `count` frames from `stream`, then returns. Safe only
    /// after a deterministic drain handshake (``AudioCaptureActor/awaitFramesDrained()``)
    /// has guaranteed all `count` frames are already buffered on the stream, so
    /// the bounded loop never blocks waiting for a frame that will not arrive.
    /// This avoids the never-terminating `for await` over an unfinished public
    /// stream that ``stop()`` (not ``awaitFramesDrained()``) would close.
    ///
    /// - Note: this bounded-collect pattern relies on ``frameStream()``'s
    ///   UNBOUNDED buffering retaining all `count` frames between
    ///   `awaitFramesDrained()` and this drain. A future change to the public
    ///   frame stream's buffering policy (e.g. bounded / drop-oldest) would let
    ///   frames be dropped before they are collected and must revisit this.
    private static func collect(
        _ count: Int,
        from stream: AsyncStream<AudioFrame>
    ) async -> [AudioFrame] {
        var collected: [AudioFrame] = []
        guard count > 0 else { return collected }
        for await frame in stream {
            collected.append(frame)
            if collected.count == count { break }
        }
        return collected
    }

    // MARK: - Lifecycle teardown

    /// After ``stop()`` the single drain consumer must be cancelled and the
    /// internal continuation finished, so a subsequent capture cycle starts
    /// exactly one fresh drain task with no prior task racing over actor state.
    ///
    /// This test exercises the ``stop()`` teardown path directly via the DEBUG
    /// seam (which installs the same internal channel + single drain task the
    /// production tap uses). The route-change reconfiguration teardown shares
    /// the same ``teardownDrain()`` primitive but cannot be driven here without
    /// a live `AVAudioEngine` posting `.AVAudioEngineConfigurationChange`; that
    /// gap is logged as a V3 entry (see the suite-level note below).
    @Test("stop() cancels the single drain task and finishes the internal channel")
    func stop_tearsDownDrainTask() async {
        let actor = AudioCaptureActor()
        let (frames, _) = await actor.setupForTesting()

        // Drain in the background so the stream can finish on stop().
        let collector = Task<Void, Never> {
            for await _ in frames {}
        }

        #expect(await actor.hasActiveDrainTask() == true)

        // Submit one frame, then stop. stop() must finish the internal channel
        // (drain loop falls out of `for await`) and cancel + nil the task.
        await actor.ingestForTesting(Self.frame(hostTime: 100))
        await actor.stop()

        #expect(await actor.hasActiveDrainTask() == false)

        // The public frame stream is finished, so the collector completes
        // without hanging — a second drain task is not left racing.
        await collector.value

        // A fresh setup installs exactly one new drain task.
        _ = await actor.setupForTesting()
        #expect(await actor.hasActiveDrainTask() == true)
        await actor.stop()
    }

    // MARK: - Reconfiguration contract (violation tests)

    /// Polls `predicate` every 50ms for up to `maxMillis`. Local helper —
    /// the ViewModel suite's `waitFor` is file-private to that file.
    private static func eventually(
        maxMillis: Int = 2000,
        _ predicate: () async -> Bool
    ) async -> Bool {
        for _ in 0 ..< (maxMillis / 50) {
            if await predicate() { return true }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return await predicate()
    }

    /// Violation test named in ``AudioCaptureActor``'s reconfiguration
    /// doc-comment: a TRANSIENT rebuild failure (the input reporting an
    /// unusable format mid-route-change) must recover on the single
    /// scheduled retry — capture stays running, no teardown happens, and
    /// the rebuilt channel still delivers frames to the public stream.
    @Test("reconfiguration: transient rebuild failure recovers on retry")
    func reconfiguration_transientFailure_recoversOnRetry() async {
        let actor = AudioCaptureActor()
        let (frames, _) = await actor.setupForTesting()

        let collector = Task<[UInt64], Never> {
            var hostTimes: [UInt64] = []
            for await frame in frames {
                hostTimes.append(frame.hostTime)
            }
            return hostTimes
        }

        await actor.setForcedInstallFailuresForTesting(1)
        await actor.triggerReconfigurationForTesting()

        // Attempt 1 fails (forced); the retry fires after ~300ms and
        // succeeds via the test-mode rebuild branch.
        let recovered = await Self.eventually {
            await actor.hasActiveDrainTask()
        }
        #expect(recovered, "Retry should have rebuilt the drain channel")
        #expect(await actor.isRunningForTesting == true)
        #expect(await actor.fullTeardownCountForTesting == 0)

        // The rebuilt channel is live end-to-end: a frame submitted after
        // recovery reaches the public stream.
        await actor.ingestForTesting(Self.frame(hostTime: 42))
        await actor.awaitFramesDrained()
        await actor.stop()

        let collected = await collector.value
        #expect(collected.contains(42))
    }

    /// Violation test named in ``AudioCaptureActor``'s reconfiguration
    /// doc-comment: a PERSISTENT rebuild failure (both attempts fail) must
    /// wind capture down through the single teardown nucleus — exactly one
    /// clean teardown, `isRunning` false, and both public streams finished
    /// (the downstream consumer sees end-of-stream, never silence-forever).
    /// The forbidden zombie shape — `isRunning == false` with the engine
    /// left running — is exactly the 2026-06-10 on-device bug.
    @Test("reconfiguration: persistent rebuild failure tears down cleanly and finishes streams")
    func reconfiguration_persistentFailure_tearsDownCleanly_streamsFinish() async {
        let actor = AudioCaptureActor()
        let (frames, _) = await actor.setupForTesting()

        let collector = Task<Int, Never> {
            var count = 0
            for await _ in frames {
                count += 1
            }
            return count
        }

        await actor.setForcedInstallFailuresForTesting(2)
        await actor.triggerReconfigurationForTesting()

        let toreDown = await Self.eventually {
            await actor.fullTeardownCountForTesting == 1
        }
        #expect(toreDown, "Second failed attempt must tear capture down")
        #expect(await actor.isRunningForTesting == false)
        #expect(await actor.hasActiveDrainTask() == false)

        // The public stream finished — the collector completes instead of
        // hanging on a silent, dead stream.
        _ = await collector.value
    }

    /// Violation test named in ``AudioCaptureActor``'s reconfiguration
    /// doc-comment, driving the documented stop-vs-retry race: a `stop()`
    /// landing INSIDE the retry window must win — one teardown from
    /// `stop()`, and the pending retry neither fires a second teardown nor
    /// resurrects capture after its delay elapses.
    @Test("reconfiguration: stop() during the retry window wins; retry does not resurrect")
    func reconfiguration_stopDuringRetryWindow_stopWins_retryDoesNotResurrect() async {
        let actor = AudioCaptureActor()
        _ = await actor.setupForTesting()

        await actor.setForcedInstallFailuresForTesting(1)
        await actor.triggerReconfigurationForTesting()

        // Stop while the retry is pending (attempt 1 failed synchronously,
        // the retry sleeps ~300ms).
        await actor.stop()
        #expect(await actor.isRunningForTesting == false)
        #expect(await actor.fullTeardownCountForTesting == 1)

        // Wait out the retry window: the cancelled/no-op retry must not
        // tear down again or restart anything.
        try? await Task.sleep(for: .milliseconds(700))
        #expect(await actor.fullTeardownCountForTesting == 1)
        #expect(await actor.isRunningForTesting == false)
        #expect(await actor.hasActiveDrainTask() == false)
    }

    /// Violation test named in ``AudioCaptureActor``'s reconfiguration
    /// doc-comment, driving the documented latest-pass-wins rule: when a
    /// SECOND reconfiguration supersedes a first pass whose retry is still
    /// pending, the stale retry must no-op on its generation re-check —
    /// never tearing down, never double-installing over the newer pass's
    /// rebuilt channel. Exactly one live channel survives, end-to-end:
    /// one submitted frame arrives exactly once.
    @Test("reconfiguration: back-to-back passes — stale retry no-ops, single channel survives")
    func reconfiguration_backToBackPasses_staleRetryNoOps_singleChannelSurvives() async {
        let actor = AudioCaptureActor()
        let (frames, _) = await actor.setupForTesting()

        let collector = Task<[UInt64], Never> {
            var hostTimes: [UInt64] = []
            for await frame in frames {
                hostTimes.append(frame.hostTime)
            }
            return hostTimes
        }

        // Pass 1 fails its first attempt and schedules a retry…
        await actor.setForcedInstallFailuresForTesting(1)
        await actor.triggerReconfigurationForTesting()

        // …and pass 2 lands inside the retry window, rebuilding cleanly
        // (forced failures are exhausted, so its first attempt succeeds).
        await actor.triggerReconfigurationForTesting()
        #expect(await actor.hasActiveDrainTask() == true)

        // Wait out the stale retry's window: it must neither tear down nor
        // disturb pass 2's channel.
        try? await Task.sleep(for: .milliseconds(700))
        #expect(await actor.fullTeardownCountForTesting == 0)
        #expect(await actor.isRunningForTesting == true)
        #expect(await actor.hasActiveDrainTask() == true)

        // Exactly one live channel: one frame in, exactly one frame out.
        await actor.ingestForTesting(Self.frame(hostTime: 7))
        await actor.awaitFramesDrained()
        await actor.stop()

        let collected = await collector.value
        #expect(collected == [7])
    }

    // NOT unit-tested: `start()`'s partial-failure rollback. Driving real
    // `start()` requires `configureSession()` to activate a live
    // `AVAudioSession` with the `.record` category, which ABORTS the
    // headless test process (verified 2026-06-10: SIGABRT took the whole
    // parallel suite down). The rollback body is the same idempotent
    // teardown primitives (`removeTap` on untapped bus, `engine.stop()`
    // when stopped, best-effort deactivate, idempotent `teardownDrain()`)
    // that `stop()`/`teardownCapture()` tests cover. Integration trigger:
    // same simulated-audio-route harness as the coverage note below.
}

// MARK: - Coverage note (updated 2026-06-10)

//
// The reconfiguration CONTRACT (retry-then-teardown, stop-wins-race, no
// zombie state) is now unit-covered by the three violation tests above via
// the `triggerReconfigurationForTesting()` seam — this closes the V3 note
// that previously lived here. What remains integration-only: driving the
// handler from a REAL `.AVAudioEngineConfigurationChange` notification with
// live audio hardware (simulator cannot synthesize a route change). Trigger
// for that integration test: a route-change regression suspected on device,
// or CI gaining a simulated-audio-route harness.
