//
//  TranscriptionActorTests.swift
//  ArigatoAITests
//
//  Created by Jose Castell on 2026/05/10.
//

@testable import ArigatoAI
import Darwin.Mach
import Foundation
import os
import Testing

// MARK: - Test infrastructure

/// Fake implementation of ``WhisperClient`` that records every
/// transcription call and offers a deterministic block-and-release
/// handshake driven by the actor-backed ``BlockGate``.
///
/// `OSAllocatedUnfairLock` is the project standard for `@unchecked
/// Sendable` test fakes (see ``WhisperModelLoaderTests``); `NSLock` is
/// banned from async contexts under Swift 6.
private final nonisolated class RecordingFakeWhisperClient: WhisperClient, @unchecked Sendable {
    /// Snapshot of one ``transcribe(audio:anchorHostTime:)`` invocation.
    /// Captures only the values the tests assert on.
    struct CallRecord: Equatable {
        let audioCount: Int
        let anchorHostTime: UInt64
    }

    private struct State {
        var calls: [CallRecord] = []
        var blockOnCall: [Int: BlockGate] = [:]
        var throwOnCall: Set<Int> = []
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    /// Configures the fake to park inside ``transcribe(audio:anchorHostTime:)``
    /// on the `n`-th call (1-based) until ``releaseBlock(nthCall:)`` is
    /// called for the same `n`.
    func setBlockOnCall(_ n: Int) {
        state.withLock { snapshot in
            snapshot.blockOnCall[n] = BlockGate()
        }
    }

    /// Configures the fake to throw `FakeWhisperError.bang` on the
    /// `n`-th call (1-based).
    func setThrowOnCall(_ n: Int) {
        state.withLock { snapshot in
            snapshot.throwOnCall.insert(n)
        }
    }

    /// Releases the block previously set via ``setBlockOnCall(_:)`` for
    /// the `n`-th call. Safe to call before the call has been reached;
    /// the call resumes immediately when it arrives.
    func releaseBlock(nthCall n: Int = 1) {
        let gate = state.withLock { snapshot in
            snapshot.blockOnCall[n]
        }
        Task { await gate?.release() }
    }

    /// Awaits a deterministic handshake confirming the `n`-th call has
    /// reached the parked state. Used by tests in place of `Task.sleep`
    /// to synchronise without polling.
    ///
    /// Implementation note: this awaits the underlying ``BlockGate``'s
    /// ``BlockGate/waitUntilParked()`` method, which fires only once a
    /// caller has registered its continuation inside ``BlockGate/wait()``.
    /// That is strictly stronger than "transcribe entered" — it
    /// guarantees the parking call is now suspended, which removes the
    /// release-before-park race that broke C30 in the prior attempt.
    func waitForBlockToBeReached(nthCall n: Int = 1) async {
        let gate = state.withLock { snapshot in
            snapshot.blockOnCall[n]
        }
        await gate?.waitUntilParked()
    }

    var calls: [CallRecord] {
        state.withLock { $0.calls }
    }

    var callCount: Int {
        state.withLock { $0.calls.count }
    }

    func prewarmModels() async throws {
        // Lifecycle is exercised separately; transcription tests do not
        // care about pre-warm side effects here.
    }

    func transcribe(
        audio: [Float],
        anchorHostTime: UInt64
    ) async throws -> WhisperWindowResult {
        let (callIndex, blockGate, shouldThrow): (Int, BlockGate?, Bool) =
            state.withLock { snapshot in
                snapshot.calls.append(
                    CallRecord(audioCount: audio.count, anchorHostTime: anchorHostTime)
                )
                let index = snapshot.calls.count
                let gate = snapshot.blockOnCall[index]
                let throwing = snapshot.throwOnCall.contains(index)
                return (index, gate, throwing)
            }

        if let blockGate {
            await blockGate.wait()
        }

        if shouldThrow {
            throw FakeWhisperError.bang(callIndex: callIndex)
        }

        return WhisperWindowResult(
            language: "ja",
            windowAnchorHostTime: anchorHostTime,
            segments: []
        )
    }
}

/// Test-local error injected by ``RecordingFakeWhisperClient`` so the
/// actor's wrapping behaviour (raw error -> ``TranscriptionError/decodeFailed(_:)``)
/// is observable.
private enum FakeWhisperError: Error, CustomStringConvertible {
    case bang(callIndex: Int)

    var description: String {
        switch self {
        case let .bang(index):
            return "FakeWhisperError.bang(call=\(index))"
        }
    }
}

/// Actor-backed gate whose `wait()` blocks the caller until `release()`
/// is invoked. Used by the fake client to deterministically park a
/// transcription call until the test releases it.
///
/// In addition to the standard wait/release pattern, the gate exposes
/// `waitUntilParked()` which lets a peer task observe the moment a
/// caller has registered its continuation and is suspended on
/// `wait()`. The fake's deterministic handshake uses this so the test
/// is guaranteed that the parking call has actually parked before
/// `releaseBlock(nthCall:)` is permitted to fire — without it, a
/// release that fires before the parking continuation is registered
/// would simply set `released = true`, and the parking call would
/// short-circuit on its next entry into `wait()`. That race is the
/// exact failure mode that produced the C30 regression in the prior
/// attempt; making "parked" observable removes it.
private actor BlockGate {
    private var released = false
    private var waiting: [CheckedContinuation<Void, Never>] = []
    private var parkedCount = 0
    private var parkObservers: [CheckedContinuation<Void, Never>] = []

    func release() {
        released = true
        for continuation in waiting {
            continuation.resume()
        }
        waiting.removeAll()
    }

    func wait() async {
        if released { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            waiting.append(continuation)
            parkedCount += 1
            for observer in parkObservers {
                observer.resume()
            }
            parkObservers.removeAll()
        }
    }

    /// Returns once at least one caller has reached the suspension
    /// point inside `wait()`. If a caller has already parked when this
    /// is invoked, returns immediately; otherwise suspends until the
    /// first park event.
    func waitUntilParked() async {
        if parkedCount > 0 { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            parkObservers.append(continuation)
        }
    }
}

/// Counts factory invocations under a lock. Mirrors the
/// ``WhisperModelLoaderTests`` `CallCounter` so the warmup-coalescing
/// assertions look the same shape.
private final class FactoryCallCounter: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: 0)

    func increment() {
        lock.withLock { $0 += 1 }
    }

    var value: Int {
        lock.withLock { $0 }
    }
}

/// Suspends until `release()` is called; exposes a single `CheckedContinuation`.
/// Used by the warmup-concurrency test to fan out N callers before
/// permitting the single in-flight load to complete.
private final class FactoryGate: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock<CheckedContinuation<Void, Never>?>(initialState: nil)

    func wait() async {
        await withCheckedContinuation { continuation in
            lock.withLock { stored in
                stored = continuation
            }
        }
    }

    func release() {
        let continuation = lock.withLock { stored -> CheckedContinuation<Void, Never>? in
            let captured = stored
            stored = nil
            return captured
        }
        continuation?.resume()
    }
}

// MARK: - Frame helpers

/// Produces `totalSeconds` of synthetic 16 kHz mono audio in 100 ms
/// frames (1600 samples each). The first frame's host time is
/// `startHostTime`; each subsequent frame's host time advances by the
/// mach-tick delta corresponding to 100 ms.
///
/// - Parameters:
///   - totalSeconds: Total duration to generate.
///   - framesPerSecond: Frames per second. Defaults to 10 (one frame
///     per 100 ms).
///   - startHostTime: Host time of the first sample. Defaults to 0.
///   - sampleRate: Sample rate in hertz. Defaults to 16000 to match
///     WhisperKit's required input.
private func makeFrameSequence(
    totalSeconds: Double,
    framesPerSecond: Int = 10,
    startHostTime: UInt64 = 0,
    sampleRate: Double = 16000
) -> [AudioFrame] {
    let frameCount = Int((totalSeconds * Double(framesPerSecond)).rounded())
    let samplesPerFrame = Int(sampleRate / Double(framesPerSecond))
    let nanosPerFrame = 1_000_000_000.0 / Double(framesPerSecond)
    let ticksPerFrame = machTicks(forNanoseconds: nanosPerFrame)
    var frames: [AudioFrame] = []
    frames.reserveCapacity(frameCount)
    for index in 0 ..< frameCount {
        let hostTime = startHostTime &+ (UInt64(index) &* ticksPerFrame)
        let samples = [Float](repeating: 0.0, count: samplesPerFrame)
        frames.append(
            AudioFrame(samples: samples, hostTime: hostTime, frameCount: samplesPerFrame)
        )
    }
    return frames
}

/// Yields each element of `frames` to the returned stream then finishes.
private func makeFrameStream(_ frames: [AudioFrame]) -> AsyncStream<AudioFrame> {
    AsyncStream { continuation in
        for frame in frames {
            continuation.yield(frame)
        }
        continuation.finish()
    }
}

/// Creates an open `AsyncStream<AudioFrame>` and binds its continuation
/// out via `binding` so callers can push frames or finish the stream
/// asynchronously. The continuation outlives the function; the caller
/// is responsible for finishing it.
private func makeOpenFrameStream(
    binding: inout AsyncStream<AudioFrame>.Continuation?
) -> AsyncStream<AudioFrame> {
    var captured: AsyncStream<AudioFrame>.Continuation?
    let stream = AsyncStream<AudioFrame> { continuation in
        captured = continuation
    }
    binding = captured
    return stream
}

/// Converts a nanosecond duration into mach absolute ticks using the
/// system's `mach_timebase_info`. Mirrors the conversion used inside
/// ``RollingAudioBuffer`` so the test's expected anchors align with the
/// production code's anchor advancement.
private func machTicks(forNanoseconds nanos: Double) -> UInt64 {
    var info = mach_timebase_info_data_t()
    mach_timebase_info(&info)
    let numer = Double(info.numer)
    let denom = Double(info.denom)
    guard numer > 0 else { return UInt64(nanos.rounded()) }
    let ticks = (nanos * denom / numer).rounded()
    guard ticks >= 0 else { return 0 }
    return UInt64(ticks)
}

// MARK: - Tests

@Suite("TranscriptionActor")
struct TranscriptionActorTests {
    // MARK: Batch A - warmup lifecycle

    @Test("warmup is idempotent across repeated calls (C7)")
    func warmup_idempotent_loadsOnceAcrossRepeatedCalls() async throws {
        let counter = FactoryCallCounter()
        let client = RecordingFakeWhisperClient()
        let actor = TranscriptionActor(clientFactory: {
            counter.increment()
            return client
        })

        try await actor.warmup()
        try await actor.warmup()
        try await actor.warmup()

        #expect(counter.value == 1)
        let state = await actor.warmupState()
        #expect(state == .ready)
    }

    @Test("concurrent warmup calls coalesce into a single load (C7)")
    func warmup_concurrentCallsCoalesce() async {
        let counter = FactoryCallCounter()
        let gate = FactoryGate()
        let client = RecordingFakeWhisperClient()
        let actor = TranscriptionActor(clientFactory: {
            counter.increment()
            await gate.wait()
            return client
        })

        async let releaseAfterFanout: Void = {
            // Allow the task group below a beat to fan out and bind every
            // caller to the in-flight warmup task before the gate fires.
            try? await Task.sleep(for: .milliseconds(50))
            gate.release()
        }()

        await withTaskGroup(of: Void.self) { group in
            for _ in 0 ..< 50 {
                group.addTask {
                    try? await actor.warmup()
                }
            }
            for await _ in group {}
        }

        await releaseAfterFanout
        #expect(counter.value == 1)
        let state = await actor.warmupState()
        #expect(state == .ready)
    }

    @Test("warmupState before warmup reflects the cold state (C8)")
    func warmupState_idleMapsToCold() async {
        let actor = TranscriptionActor(clientFactory: {
            RecordingFakeWhisperClient()
        })
        let state = await actor.warmupState()
        #expect(state == .cold)
    }

    @Test("warmupState during warmup reflects the warming state (C8)")
    func warmupState_loadingMapsToWarming() async throws {
        let gate = FactoryGate()
        let client = RecordingFakeWhisperClient()
        let actor = TranscriptionActor(clientFactory: {
            await gate.wait()
            return client
        })

        let warmupTask = Task { try await actor.warmup() }

        // Allow the warmup task to enter the factory and publish .warming.
        // We cannot use BlockGate here because the publication path is the
        // one we are observing; a brief sleep is the simplest way to let
        // the publishWarmupState(.warming) hop run without racing the gate
        // release.
        try? await Task.sleep(for: .milliseconds(50))

        let stateMidLoad = await actor.warmupState()
        #expect(stateMidLoad == .warming)

        gate.release()
        try await warmupTask.value

        let stateAfterLoad = await actor.warmupState()
        #expect(stateAfterLoad == .ready)
    }

    @Test("warmupState after a successful warmup reflects ready (C8)")
    func warmupState_loadedMapsToReady() async throws {
        let client = RecordingFakeWhisperClient()
        let actor = TranscriptionActor(clientFactory: { client })

        try await actor.warmup()

        let state = await actor.warmupState()
        #expect(state == .ready)
    }

    @Test("warmupState after a failed warmup reflects failed with the wrapped error (C8)")
    func warmupState_failedMapsToFailed() async {
        let actor = TranscriptionActor(clientFactory: {
            throw FakeWhisperError.bang(callIndex: 0)
        })

        await #expect(throws: TranscriptionError.self) {
            try await actor.warmup()
        }

        let state = await actor.warmupState()
        guard case let .failed(error) = state else {
            Issue.record("Expected .failed, got \(state)")
            return
        }
        guard case .modelLoadFailed = error else {
            Issue.record("Expected .modelLoadFailed, got \(error)")
            return
        }
    }

    // MARK: Batch B - windowStream emission

    @Test("windowStream emits nothing while the buffer holds less than one window (C10)")
    func windowStream_underprefill_emitsNothing() async throws {
        let client = RecordingFakeWhisperClient()
        let actor = TranscriptionActor(clientFactory: { client })

        let frames = makeFrameSequence(totalSeconds: 0.3)
        let stream = actor.windowStream(frames: makeFrameStream(frames))

        var collected: [TranscriptionWindow] = []
        for try await window in stream {
            collected.append(window)
        }

        #expect(collected.isEmpty)
        #expect(client.callCount == 0)
    }

    @Test("windowStream emits one window per hop boundary after the prefill threshold (C9)")
    func windowStream_emitsOnePerHopAfterPrefill() async throws {
        let client = RecordingFakeWhisperClient()
        let actor = TranscriptionActor(clientFactory: { client })

        let frames = makeFrameSequence(totalSeconds: 7.0)
        let stream = actor.windowStream(frames: makeFrameStream(frames))

        var collected: [TranscriptionWindow] = []
        for try await window in stream {
            collected.append(window)
        }

        #expect(collected.count == 3)
        let endSeconds = collected.map(\.windowEndSeconds)
        #expect(endSeconds == [5.0, 6.0, 7.0])
        for window in collected {
            #expect(window.isFinal == false)
        }
    }

    @Test("windowStream's windowAnchorHostTime matches the audio array's first sample (C15)")
    func windowStream_anchorHostTime_matchesAudioArrayStart() async throws {
        let client = RecordingFakeWhisperClient()
        let actor = TranscriptionActor(clientFactory: { client })

        let frames = makeFrameSequence(totalSeconds: 7.0, startHostTime: 1000)
        let stream = actor.windowStream(frames: makeFrameStream(frames))

        var collected: [TranscriptionWindow] = []
        for try await window in stream {
            collected.append(window)
        }

        #expect(collected.count == 3)
        #expect(client.calls.count == 3)
        for index in 0 ..< collected.count {
            #expect(
                collected[index].windowAnchorHostTime
                    == client.calls[index].anchorHostTime
            )
        }

        // First emission's audio array starts at sample 0 of the buffer's
        // current contents; the buffer's anchor is the first frame's host
        // time when the buffer has not yet rolled.
        #expect(collected.first?.windowAnchorHostTime == 1000)
    }

    @Test("end-of-stream flushes a final window when leftover is at least 0.5s (C11)")
    func windowStream_endOfStream_flushesPartialAsFinal() async throws {
        let client = RecordingFakeWhisperClient()
        let actor = TranscriptionActor(clientFactory: { client })

        let frames = makeFrameSequence(totalSeconds: 5.7)
        let stream = actor.windowStream(frames: makeFrameStream(frames))

        var collected: [TranscriptionWindow] = []
        for try await window in stream {
            collected.append(window)
        }

        #expect(collected.count == 2)
        #expect(collected.first?.isFinal == false)
        #expect(collected.first?.windowEndSeconds == 5.0)
        #expect(collected.last?.isFinal == true)
    }

    @Test("end-of-stream does not flush when leftover is below 0.5s (C11 negative)")
    func windowStream_endOfStream_belowMinimum_doesNotFlush() async throws {
        let client = RecordingFakeWhisperClient()
        let actor = TranscriptionActor(clientFactory: { client })

        let frames = makeFrameSequence(totalSeconds: 0.3)
        let stream = actor.windowStream(frames: makeFrameStream(frames))

        var collected: [TranscriptionWindow] = []
        for try await window in stream {
            collected.append(window)
        }

        #expect(collected.isEmpty)
        #expect(client.callCount == 0)
    }

    @Test("cancel finishes the stream cleanly without throwing (C12)")
    func windowStream_cancelFinishesCleanly() async throws {
        let client = RecordingFakeWhisperClient()
        client.setBlockOnCall(1)
        let actor = TranscriptionActor(clientFactory: { client })

        var continuation: AsyncStream<AudioFrame>.Continuation?
        let frameStream = makeOpenFrameStream(binding: &continuation)
        let stream = actor.windowStream(frames: frameStream)

        // Push enough frames to trigger one inference (5s prefill).
        for frame in makeFrameSequence(totalSeconds: 5.0) {
            continuation?.yield(frame)
        }

        // Wait deterministically for the inference call to enter the block.
        await client.waitForBlockToBeReached(nthCall: 1)

        // Cancel before releasing the block.
        await actor.cancel()

        // Release the block so the inference task can exit; the actor has
        // already discarded the session, so the result is ignored.
        client.releaseBlock(nthCall: 1)

        // Finishing the upstream stream allows the consumer iteration to
        // exit if it has not already.
        continuation?.finish()

        var collected: [TranscriptionWindow] = []
        var caughtError: Error?
        do {
            for try await window in stream {
                collected.append(window)
            }
        } catch {
            caughtError = error
        }

        #expect(caughtError == nil)
    }

    @Test("client errors propagate as decodeFailed via the throwing stream (C14)")
    func windowStream_clientFailure_deliversDecodeFailedAsync() async throws {
        let client = RecordingFakeWhisperClient()
        client.setThrowOnCall(3)
        let actor = TranscriptionActor(clientFactory: { client })

        let frames = makeFrameSequence(totalSeconds: 7.0)
        let stream = actor.windowStream(frames: makeFrameStream(frames))

        var collected: [TranscriptionWindow] = []
        var caughtError: TranscriptionError?
        do {
            for try await window in stream {
                collected.append(window)
            }
        } catch let error as TranscriptionError {
            caughtError = error
        } catch {
            Issue.record("Expected TranscriptionError, got \(error)")
        }

        #expect(collected.count == 2)
        guard let caughtError else {
            Issue.record("Expected an error, got none")
            return
        }
        guard case .decodeFailed = caughtError else {
            Issue.record("Expected .decodeFailed, got \(caughtError)")
            return
        }
    }

    @Test("a second windowStream call finishes the previous stream cleanly (C16)")
    func windowStream_secondCall_finishesFirstStream() async throws {
        let client = RecordingFakeWhisperClient()
        let actor = TranscriptionActor(clientFactory: { client })

        var firstContinuation: AsyncStream<AudioFrame>.Continuation?
        let firstFrameStream = makeOpenFrameStream(binding: &firstContinuation)
        let firstStream = actor.windowStream(frames: firstFrameStream)

        // Consumer task A drains the first stream until it finishes.
        let firstConsumer = Task<[TranscriptionWindow], any Error> {
            var windows: [TranscriptionWindow] = []
            for try await window in firstStream {
                windows.append(window)
            }
            return windows
        }

        // Push only a small prefix to the first stream — not enough to
        // emit a window. The second windowStream call below should
        // pre-empt the first one.
        for frame in makeFrameSequence(totalSeconds: 0.3) {
            firstContinuation?.yield(frame)
        }

        // Allow the actor a moment to bind the first session before we
        // open the second.
        try? await Task.sleep(for: .milliseconds(50))

        // Start the second stream with a complete recording.
        let secondFrames = makeFrameSequence(totalSeconds: 5.0)
        let secondStream = actor.windowStream(frames: makeFrameStream(secondFrames))

        var secondCollected: [TranscriptionWindow] = []
        for try await window in secondStream {
            secondCollected.append(window)
        }

        // Releasing the first stream's frames now lets the iteration
        // unblock if it is still waiting.
        firstContinuation?.finish()

        // The first consumer must finish without throwing.
        let firstWindows = try await firstConsumer.value
        #expect(firstWindows.isEmpty)
        #expect(secondCollected.count == 1)
    }

    // MARK: Batch C - C30 hop-queue overflow

    @Test("pending-hop overflow drops the oldest hop, not the newest (C30)")
    func windowStream_pendingQueueOverflow_dropsOldestNotNewest() async throws {
        let client = RecordingFakeWhisperClient()
        client.setBlockOnCall(1)
        let actor = TranscriptionActor(clientFactory: { client })

        var continuation: AsyncStream<AudioFrame>.Continuation?
        let frameStream = makeOpenFrameStream(binding: &continuation)
        let stream = actor.windowStream(frames: frameStream)

        // Consumer drains the windows.
        let consumer = Task<[TranscriptionWindow], any Error> {
            var collected: [TranscriptionWindow] = []
            for try await window in stream {
                collected.append(window)
            }
            return collected
        }

        // Push 5 s of frames to trigger hop 1 (the blocked inference).
        for frame in makeFrameSequence(totalSeconds: 5.0) {
            continuation?.yield(frame)
        }

        // Wait deterministically until hop 1 has reached the block.
        await client.waitForBlockToBeReached(nthCall: 1)

        // Now push 6 additional 1 s windows. With hop = 1.0 s these will
        // produce six more hop submissions:
        //   second 6 -> hop 2
        //   second 7 -> hop 3
        //   second 8 -> hop 4
        //   second 9 -> hop 5 (queue at cap 4)
        //   second 10 -> hop 6 (drop hop 2)
        //   second 11 -> hop 7 (drop hop 3)
        let extraFrames = makeFrameSequence(
            totalSeconds: 6.0,
            startHostTime: 0
        )
        // Re-base host times so they trail the prefill exactly. Not
        // strictly required for C30, but keeps anchor math deterministic
        // for any future assertions the test wants to add.
        for frame in extraFrames {
            continuation?.yield(frame)
        }

        // Finish upstream so the drain task transitions out of the
        // for-await loop. We MUST wait for the actor's drain task to
        // finish consuming every frame and submit every hop before
        // releasing the parked inference. Without this synchronisation,
        // the release Task races the drain task and inferenceCompleted
        // can flush the pending queue before drain has filled it,
        // which masks the C30 overflow behaviour. See
        // ``TranscriptionActor/awaitUpstreamDrained()`` for the
        // test-instrumented signal.
        continuation?.finish()
        await actor.awaitUpstreamDrained()

        // Release hop 1 so the chain can drain.
        client.releaseBlock(nthCall: 1)

        let collected = try await consumer.value

        // Hops 2 and 3 must have been dropped on overflow.
        // Surviving hops: 1, 4, 5, 6, 7 → 5 transcribe calls total.
        #expect(client.callCount == 5)
        #expect(collected.count == 5)
        let endSeconds = collected.map(\.windowEndSeconds)
        #expect(endSeconds == [5.0, 8.0, 9.0, 10.0, 11.0])
        for window in collected {
            #expect(window.isFinal == false)
        }
    }

    // MARK: Batch D - C31 end-of-stream chain drain

    @Test("end-of-stream drains both inflight and pending hops (C31)")
    func windowStream_endOfStream_drainsInflightAndPending() async throws {
        let client = RecordingFakeWhisperClient()
        client.setBlockOnCall(1)
        let actor = TranscriptionActor(clientFactory: { client })

        var continuation: AsyncStream<AudioFrame>.Continuation?
        let frameStream = makeOpenFrameStream(binding: &continuation)
        let stream = actor.windowStream(frames: frameStream)

        let consumer = Task<[TranscriptionWindow], any Error> {
            var collected: [TranscriptionWindow] = []
            for try await window in stream {
                collected.append(window)
            }
            return collected
        }

        // Push 5 s of frames to trigger hop 1 (the blocked inference).
        for frame in makeFrameSequence(totalSeconds: 5.0) {
            continuation?.yield(frame)
        }

        await client.waitForBlockToBeReached(nthCall: 1)

        // Push 2 s more to enqueue hops 2 and 3 behind the blocked call.
        for frame in makeFrameSequence(totalSeconds: 2.0) {
            continuation?.yield(frame)
        }

        // Finish upstream and wait deterministically for drain to have
        // consumed every frame before releasing. Same race-free
        // synchronisation pattern as the C30 test.
        continuation?.finish()
        await actor.awaitUpstreamDrained()

        // Release. The drain loop should now wait on inflight, then
        // dispatch hops 2 and 3 from the pending queue, then finish.
        client.releaseBlock(nthCall: 1)

        let collected = try await consumer.value

        #expect(client.callCount == 3)
        #expect(collected.count == 3)
        let endSeconds = collected.map(\.windowEndSeconds)
        #expect(endSeconds == [5.0, 6.0, 7.0])
        for window in collected {
            #expect(window.isFinal == false)
        }
    }
}
