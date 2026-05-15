//
//  TranslationActorTests.swift
//  ArigatoAITests
//
//  Created by Jose Castell on 2026/05/16.
//

@testable import ArigatoAI
import Foundation
import os
import Testing

@Suite("TranslationActor")
struct TranslationActorTests {
    // MARK: - FakeLFM2Engine

    /// Test-local fake conformer to ``LFM2Engine``. Records every
    /// `warmupCanary(direction:)` invocation; ignores `translate(...)`
    /// (Step 5 doesn't exercise the translation path).
    ///
    /// `@unchecked Sendable` because the recording array is mutated
    /// under an `OSAllocatedUnfairLock` — concurrent calls are safe
    /// for the test's purposes (counting invocations under
    /// coalescing-warmup load).
    fileprivate final class FakeLFM2Engine: LFM2Engine, @unchecked Sendable {
        private let canaryInvocations = OSAllocatedUnfairLock<[TranslationDirection]>(initialState: [])

        var recordedCanaries: [TranslationDirection] {
            canaryInvocations.withLock { $0 }
        }

        func warmupCanary(direction: TranslationDirection) async throws {
            canaryInvocations.withLock { $0.append(direction) }
        }

        func translate(userText _: String, direction _: TranslationDirection) -> AsyncThrowingStream<TranslationEngineEvent, any Error> {
            AsyncThrowingStream { continuation in
                continuation.finish()
            }
        }
    }

    // MARK: - Segment helper

    private static func segment(
        text: String,
        startHost: UInt64 = 100,
        endHost: UInt64 = 200,
        language: SpokenLanguage = .en
    ) -> TranscriptSegment {
        TranscriptSegment(
            id: UUID(),
            text: text,
            language: language,
            startHostTime: startHost,
            endHostTime: endHost,
            startSeconds: 0,
            endSeconds: 0.5,
            isFinal: true,
            wasLanguageFallback: false
        )
    }

    // MARK: - Coalescing

    @Test("warmup: concurrent calls coalesce to a single engine resolution")
    func warmup_concurrentCallsCoalesceToSingleEngineLoad() async {
        let factoryCallCount = OSAllocatedUnfairLock<Int>(initialState: 0)
        let factory: @Sendable () async throws -> any LFM2Engine = {
            factoryCallCount.withLock { $0 += 1 }
            // Small artificial delay so concurrent callers actually
            // race against the in-flight task.
            try await Task.sleep(for: .milliseconds(50))
            return FakeLFM2Engine()
        }
        let actor = TranslationActor(engineFactory: factory)

        await withTaskGroup(of: Void.self) { group in
            for _ in 0 ..< 5 {
                group.addTask {
                    try? await actor.warmup()
                }
            }
            await group.waitForAll()
        }

        #expect(factoryCallCount.withLock { $0 } == 1)
        let state = await actor.warmupState()
        #expect(state == .ready)
    }

    // MARK: - Idempotence after success

    @Test("warmup: call after success is a no-op")
    func warmup_afterSuccess_isNoOp() async throws {
        let factoryCallCount = OSAllocatedUnfairLock<Int>(initialState: 0)
        let factory: @Sendable () async throws -> any LFM2Engine = {
            factoryCallCount.withLock { $0 += 1 }
            return FakeLFM2Engine()
        }
        let actor = TranslationActor(engineFactory: factory)

        try await actor.warmup()
        try await actor.warmup()

        #expect(factoryCallCount.withLock { $0 } == 1)
        let state = await actor.warmupState()
        #expect(state == .ready)
    }

    // MARK: - Retry after failure

    @Test("warmup: call after failure can retry")
    func warmup_afterFailure_canRetry() async throws {
        let attempt = OSAllocatedUnfairLock<Int>(initialState: 0)
        let factory: @Sendable () async throws -> any LFM2Engine = {
            let n = attempt.withLock { state -> Int in
                state += 1
                return state
            }
            if n == 1 {
                throw TranslationError.modelLoadFailed("first attempt fails")
            }
            return FakeLFM2Engine()
        }
        let actor = TranslationActor(engineFactory: factory)

        // First call: throws.
        do {
            try await actor.warmup()
            Issue.record("Expected first warmup to throw")
        } catch let error as TranslationError {
            #expect(error == .modelLoadFailed("first attempt fails"))
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }

        let failedState = await actor.warmupState()
        #expect(failedState == .failed(.modelLoadFailed("first attempt fails")))

        // Second call: succeeds.
        try await actor.warmup()
        let readyState = await actor.warmupState()
        #expect(readyState == .ready)
    }

    // MARK: - warmupState transitions

    @Test("warmupState: before warmup is .cold")
    func warmupState_beforeWarmup_isCold() async {
        let actor = TranslationActor(engineFactory: { FakeLFM2Engine() })
        let state = await actor.warmupState()
        #expect(state == .cold)
    }

    @Test("warmupState: during warmup is .warming")
    func warmupState_duringWarmup_isWarming() async throws {
        let started = OSAllocatedUnfairLock<Bool>(initialState: false)
        let proceed = OSAllocatedUnfairLock<Bool>(initialState: false)
        let factory: @Sendable () async throws -> any LFM2Engine = {
            started.withLock { $0 = true }
            // Spin until the test releases us.
            while !proceed.withLock({ $0 }) {
                try await Task.sleep(for: .milliseconds(5))
            }
            return FakeLFM2Engine()
        }
        let actor = TranslationActor(engineFactory: factory)

        let warmupTask = Task {
            try await actor.warmup()
        }

        // Wait for the factory to be invoked.
        while !started.withLock({ $0 }) {
            try await Task.sleep(for: .milliseconds(5))
        }

        let state = await actor.warmupState()
        #expect(state == .warming)

        proceed.withLock { $0 = true }
        try await warmupTask.value
    }

    @Test("warmupState: after success is .ready")
    func warmupState_afterSuccess_isReady() async throws {
        let actor = TranslationActor(engineFactory: { FakeLFM2Engine() })
        try await actor.warmup()
        let state = await actor.warmupState()
        #expect(state == .ready)
    }

    // MARK: - Queue: single sentence

    @Test("translate: single sentence upstream enqueues one")
    func translate_singleSentenceUpstream_enqueuesOne() async throws {
        let actor = TranslationActor(engineFactory: { FakeLFM2Engine() })
        try await actor.warmup()

        let (segments, continuation) = AsyncStream<TranscriptSegment>.makeStream()
        _ = await actor.translate(segments: segments, direction: .jaToEn)

        continuation.yield(Self.segment(text: "こんにちは。"))
        continuation.finish()
        await actor.awaitUpstreamDrained()

        let count = await actor.pendingSentenceCount()
        #expect(count == 1)
    }

    // MARK: - Queue: burst within cap

    @Test("translate: burst of sentences within cap enqueues all")
    func translate_burstOfSentences_enqueuesAllUpToCap() async throws {
        let actor = TranslationActor(engineFactory: { FakeLFM2Engine() })
        try await actor.warmup()

        let (segments, continuation) = AsyncStream<TranscriptSegment>.makeStream()
        _ = await actor.translate(segments: segments, direction: .enToJa)

        for i in 0 ..< 10 {
            continuation.yield(Self.segment(text: "Sentence \(i)."))
        }
        continuation.finish()
        await actor.awaitUpstreamDrained()

        let count = await actor.pendingSentenceCount()
        #expect(count == 10)
        let dropped = await actor.droppedNewestCount()
        #expect(dropped == 0)
    }

    // MARK: - Violation test (load-bearing)

    @Test("C-T-VIOLATION-GREEDY-UPSTREAM: burst exceeding cap drops newest and logs overflow")
    func translate_burstExceedingCap_dropsNewestAndLogsOverflow() async throws {
        let actor = TranslationActor(engineFactory: { FakeLFM2Engine() })
        try await actor.warmup()

        let (segments, continuation) = AsyncStream<TranscriptSegment>.makeStream()
        _ = await actor.translate(segments: segments, direction: .enToJa)

        let cap = TranslationActor.maxQueuedSentences
        // Feed cap + 5 sentences. First `cap` should be retained;
        // last 5 dropped.
        for i in 0 ..< (cap + 5) {
            continuation.yield(Self.segment(text: "Sentence \(i)."))
        }
        continuation.finish()
        await actor.awaitUpstreamDrained()

        let count = await actor.pendingSentenceCount()
        #expect(count == cap)
        let dropped = await actor.droppedNewestCount()
        #expect(dropped == 5)
    }

    // MARK: - Replacement on second translate call

    @Test("translate: second call replaces first session")
    func translate_secondCallReplacesFirstSession() async throws {
        let actor = TranslationActor(engineFactory: { FakeLFM2Engine() })
        try await actor.warmup()

        let (segments1, cont1) = AsyncStream<TranscriptSegment>.makeStream()
        let stream1 = await actor.translate(segments: segments1, direction: .jaToEn)

        cont1.yield(Self.segment(text: "First."))
        // Don't finish session 1 yet.

        let (segments2, cont2) = AsyncStream<TranscriptSegment>.makeStream()
        _ = await actor.translate(segments: segments2, direction: .enToJa)

        cont2.yield(Self.segment(text: "Second."))
        cont2.finish()
        await actor.awaitUpstreamDrained()

        // Stream 1 should have finished without throwing.
        var stream1FinishedNormally = true
        do {
            for try await _ in stream1 {}
        } catch {
            stream1FinishedNormally = false
        }
        #expect(stream1FinishedNormally)

        // Stream 2's queue has the second sentence.
        let count = await actor.pendingSentenceCount()
        #expect(count == 1)

        cont1.finish() // Cleanup.
    }

    // MARK: - Silence timeout uses TestClock

    @Test("translate: silence-timeout triggers flush via TestClock advance")
    func translate_silenceTimeoutTriggersFlush() async throws {
        let clock = TestClock()
        let actor = TranslationActor(
            engineFactory: { FakeLFM2Engine() },
            clock: clock
        )
        try await actor.warmup()

        let (segments, continuation) = AsyncStream<TranscriptSegment>.makeStream()
        _ = await actor.translate(segments: segments, direction: .enToJa)

        // Feed a punctuation-less segment.
        continuation.yield(Self.segment(text: "Hello world"))

        // Yield once so the actor's drain task has a chance to absorb
        // the segment into the buffer.
        try await Task.sleep(for: .milliseconds(50))

        // The buffer's *real* lastAppendInstant is now ~ContinuousClock.now.
        // For the silence-timeout test we ALSO need real wall time to
        // advance >= 2.0s — the SentenceBuffer is anchored to
        // ContinuousClock, not the injected TestClock. The injected
        // clock controls only the polling interval
        // (`clock.sleep(for: 500ms)`).
        // Strategy: real-sleep ~2.1s wall-clock so the next timer tick
        // detects staleness, AND advance(TestClock) to trigger the
        // next sleep cycle.
        try await Task.sleep(for: .milliseconds(2100))
        clock.advance(by: .milliseconds(600)) // wakes the next timer tick.

        // Give the timer-tick callback a moment to run.
        try await Task.sleep(for: .milliseconds(100))

        let count = await actor.pendingSentenceCount()
        #expect(count == 1)

        continuation.finish()
    }
}
