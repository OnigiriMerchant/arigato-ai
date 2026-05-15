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
    /// `warmupCanary(direction:)` and `translate(userText:direction:)`
    /// invocation; per-call chunks, errors, inter-chunk delay, and
    /// "emit no chunks before complete" mode are individually
    /// configurable.
    ///
    /// `@unchecked Sendable` because every mutable field is guarded
    /// by an `OSAllocatedUnfairLock` — concurrent calls are safe for
    /// the test's purposes.
    fileprivate final nonisolated class FakeLFM2Engine: LFM2Engine, @unchecked Sendable {
        /// Records every `translate()` call's `userText` in arrival
        /// order. Tests assert order against this.
        private let calls = OSAllocatedUnfairLock<[String]>(initialState: [])

        /// Per-call chunks to emit, keyed by `userText`. If absent for
        /// a given input, the fake's default behavior depends on
        /// ``defaultBehavior``: ``DefaultBehavior/hang`` produces an
        /// inflight stream that yields nothing and never completes (so
        /// the dispatch task starts but never advances past the first
        /// pop — used by Step 6 queue-shape tests);
        /// ``DefaultBehavior/reverseInput`` emits one chunk equal to
        /// the input reversed and then completes (used by the
        /// SLOW-DOWNSTREAM violation test, which relies on the reverse
        /// behavior to assert FIFO output ordering against fast input).
        private let configuredChunks = OSAllocatedUnfairLock<[String: [String]]>(initialState: [:])

        /// Selects what an unconfigured `translate()` call does.
        enum DefaultBehavior {
            /// The inflight stream yields no chunks and never completes
            /// until cancelled. The actor's dispatch task starts but
            /// never finishes, so subsequent enqueues observe the
            /// "first sentence consumed by dispatch, remainder queued"
            /// shape. Default; preserves Step 6 queue-shape tests.
            case hang
            /// The inflight stream yields exactly one chunk equal to
            /// the input reversed, then `.complete`s and finishes.
            /// Used by `C-T-VIOLATION-SLOW-DOWNSTREAM` to drive the
            /// dispatch loop forward against a slow downstream
            /// consumer.
            case reverseInput
        }

        private let defaultBehavior = OSAllocatedUnfairLock<DefaultBehavior>(initialState: .hang)

        func setDefaultBehavior(_ behavior: DefaultBehavior) {
            defaultBehavior.withLock { $0 = behavior }
        }

        /// Optional error to throw on the stream before completion.
        /// When set, applies to every subsequent `translate()` call.
        private let configuredError = OSAllocatedUnfairLock<TranslationError?>(initialState: nil)

        /// Optional artificial delay between chunks (e.g., to drive
        /// the slow-downstream test in a deterministic order).
        private let chunkDelay = OSAllocatedUnfairLock<Duration>(initialState: .zero)

        /// When `true`, the stream emits zero chunks before
        /// `.complete` — exercises the empty-completion fallback path.
        private let emitNoChunksBeforeComplete = OSAllocatedUnfairLock<Bool>(initialState: false)

        private let canaryInvocations = OSAllocatedUnfairLock<[TranslationDirection]>(initialState: [])

        var recordedCalls: [String] {
            calls.withLock { $0 }
        }

        var recordedCanaries: [TranslationDirection] {
            canaryInvocations.withLock { $0 }
        }

        func configureChunks(_ chunks: [String], for userText: String) {
            configuredChunks.withLock { $0[userText] = chunks }
        }

        func configureError(_ error: TranslationError?) {
            configuredError.withLock { $0 = error }
        }

        func configureChunkDelay(_ delay: Duration) {
            chunkDelay.withLock { $0 = delay }
        }

        func setEmitNoChunksBeforeComplete(_ value: Bool) {
            emitNoChunksBeforeComplete.withLock { $0 = value }
        }

        func warmupCanary(direction: TranslationDirection) async throws {
            canaryInvocations.withLock { $0.append(direction) }
        }

        func translate(
            userText: String,
            direction _: TranslationDirection
        ) -> AsyncThrowingStream<TranslationEngineEvent, any Error> {
            let configured = configuredChunks.withLock { $0[userText] }
            let behavior = defaultBehavior.withLock { $0 }
            let error = configuredError.withLock { $0 }
            let delay = chunkDelay.withLock { $0 }
            let emitNone = emitNoChunksBeforeComplete.withLock { $0 }
            calls.withLock { $0.append(userText) }

            return AsyncThrowingStream { continuation in
                let task = Task {
                    if let error {
                        continuation.finish(throwing: error)
                        return
                    }
                    if emitNone {
                        // Empty-completion fallback path: no chunks
                        // before complete.
                        continuation.yield(.complete)
                        continuation.finish()
                        return
                    }
                    if let configured {
                        for chunk in configured {
                            if Task.isCancelled { break }
                            if delay > .zero {
                                try? await Task.sleep(for: delay)
                            }
                            continuation.yield(.chunk(chunk))
                        }
                        continuation.yield(.complete)
                        continuation.finish()
                        return
                    }
                    switch behavior {
                    case .hang:
                        // Park until the consumer's onTermination
                        // closure cancels us. Yields no events. The
                        // actor's dispatch task starts but never
                        // advances past the first pop, so Step 6
                        // queue-shape tests observe "first popped,
                        // remainder queued".
                        while !Task.isCancelled {
                            try? await Task.sleep(for: .milliseconds(50))
                        }
                    case .reverseInput:
                        let chunk = String(userText.reversed())
                        if Task.isCancelled { return }
                        if delay > .zero {
                            try? await Task.sleep(for: delay)
                        }
                        continuation.yield(.chunk(chunk))
                        continuation.yield(.complete)
                        continuation.finish()
                    }
                }
                continuation.onTermination = { _ in
                    task.cancel()
                }
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

    @Test("translate: single sentence upstream enqueues one (dispatched immediately)")
    func translate_singleSentenceUpstream_enqueuesOne() async throws {
        let actor = TranslationActor(engineFactory: { FakeLFM2Engine() })
        try await actor.warmup()

        let (segments, continuation) = AsyncStream<TranscriptSegment>.makeStream()
        _ = await actor.translate(segments: segments, direction: .jaToEn)

        continuation.yield(Self.segment(text: "こんにちは。"))
        continuation.finish()
        await actor.awaitUpstreamDrained()

        // Step 7: the lone sentence is popped immediately by
        // `dispatchNextSentenceIfIdle()`; the default hanging fake
        // never completes, so it stays inflight. Pending queue is 0.
        let count = await actor.pendingSentenceCount()
        #expect(count == 0)
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

        // Step 7: first sentence is popped immediately by
        // `dispatchNextSentenceIfIdle()` and stays inflight against
        // the hanging fake; the remaining 9 stay queued.
        let count = await actor.pendingSentenceCount()
        #expect(count == 9)
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
        // Feed cap + 5 sentences. Step 7: the first sentence is
        // popped by `dispatchNextSentenceIfIdle()` and held inflight
        // against the hanging fake; subsequent enqueues then refill
        // the queue up to `cap`, after which the remaining 4 are
        // drop-newest victims. Final shape: pending=cap, dropped=4.
        for i in 0 ..< (cap + 5) {
            continuation.yield(Self.segment(text: "Sentence \(i)."))
        }
        continuation.finish()
        await actor.awaitUpstreamDrained()

        let count = await actor.pendingSentenceCount()
        #expect(count == cap)
        let dropped = await actor.droppedNewestCount()
        #expect(dropped == 4)
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

        // Stream 2's only sentence is popped immediately by
        // `dispatchNextSentenceIfIdle()` and held inflight against
        // the hanging fake; pending queue is empty.
        let count = await actor.pendingSentenceCount()
        #expect(count == 0)

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

        // Step 7: the silence-flushed sentence is popped immediately
        // by `dispatchNextSentenceIfIdle()` and held inflight against
        // the hanging fake; pending queue is empty.
        let count = await actor.pendingSentenceCount()
        #expect(count == 0)

        continuation.finish()
    }

    // MARK: - End-to-end dispatch tests (Step 7)

    @Test("translate: one sentence emits chunks then completed event")
    func translate_oneSentence_emitsChunksThenCompleted() async throws {
        let fake = FakeLFM2Engine()
        fake.configureChunks(["Hello", " world"], for: "Hello world.")

        let actor = TranslationActor(engineFactory: { fake })
        try await actor.warmup()

        let (segments, continuation) = AsyncStream<TranscriptSegment>.makeStream()
        let stream = await actor.translate(segments: segments, direction: .enToJa)

        continuation.yield(Self.segment(text: "Hello world."))
        continuation.finish()

        var events: [TranslationEvent] = []
        for try await event in stream {
            events.append(event)
        }

        var chunks: [String] = []
        var completed: [TranslatedSegment] = []
        for event in events {
            switch event {
            case let .partialChunk(_, delta):
                chunks.append(delta)
            case let .completed(translated):
                completed.append(translated)
            }
        }

        #expect(chunks == ["Hello", " world"])
        #expect(completed.count == 1)
        #expect(completed.first?.translatedText == "Hello world")
        #expect(completed.first?.isFallback == false)
    }

    @Test("translate: two sentences serialized order preserved in output")
    func translate_twoSentences_serializedOrderPreserved() async throws {
        let fake = FakeLFM2Engine()
        fake.configureChunks(["A"], for: "First.")
        fake.configureChunks(["B"], for: "Second.")
        fake.configureChunkDelay(.milliseconds(20)) // small ordered delay

        let actor = TranslationActor(engineFactory: { fake })
        try await actor.warmup()

        let (segments, continuation) = AsyncStream<TranscriptSegment>.makeStream()
        let stream = await actor.translate(segments: segments, direction: .enToJa)

        continuation.yield(Self.segment(text: "First."))
        continuation.yield(Self.segment(text: "Second."))
        continuation.finish()

        var completedOrder: [String] = []
        for try await event in stream {
            if case let .completed(translated) = event {
                completedOrder.append(translated.translatedText)
            }
        }

        #expect(completedOrder == ["A", "B"])
    }

    @Test("translate: engine throws → stream finishes with generationFailed wrapped")
    func translate_engineThrows_wrapsAsGenerationFailedAndFinishesStream() async throws {
        let fake = FakeLFM2Engine()
        fake.configureError(.generationFailed("simulated SDK error"))

        let actor = TranslationActor(engineFactory: { fake })
        try await actor.warmup()

        let (segments, continuation) = AsyncStream<TranscriptSegment>.makeStream()
        let stream = await actor.translate(segments: segments, direction: .enToJa)

        continuation.yield(Self.segment(text: "Hello."))
        continuation.finish()

        var thrownError: (any Error)?
        do {
            for try await _ in stream {}
        } catch {
            thrownError = error
        }

        #expect(thrownError != nil)
        if let translationError = thrownError as? TranslationError {
            if case let .generationFailed(detail) = translationError {
                #expect(detail == "simulated SDK error")
            } else {
                Issue.record("Expected .generationFailed, got \(translationError)")
            }
        } else {
            Issue.record("Expected TranslationError, got \(String(describing: thrownError))")
        }
    }

    @Test("translate: empty completion yields fallback segment preserving source text")
    func translate_emptyCompletion_yieldsFallbackSegmentPreservingSourceText() async throws {
        let fake = FakeLFM2Engine()
        fake.setEmitNoChunksBeforeComplete(true)

        let actor = TranslationActor(engineFactory: { fake })
        try await actor.warmup()

        let (segments, continuation) = AsyncStream<TranscriptSegment>.makeStream()
        let stream = await actor.translate(segments: segments, direction: .enToJa)

        continuation.yield(Self.segment(text: "Hello."))
        continuation.finish()

        var completed: [TranslatedSegment] = []
        for try await event in stream {
            if case let .completed(translated) = event {
                completed.append(translated)
            }
        }

        #expect(completed.count == 1)
        #expect(completed.first?.translatedText == "Hello.")
        #expect(completed.first?.isFallback == true)
        #expect(completed.first?.sourceText == "Hello.")
    }

    @Test("translate: end of upstream flushes remaining buffer before stream finishes")
    func translate_endOfUpstream_flushesRemainingBufferBeforeStreamFinishes() async throws {
        let fake = FakeLFM2Engine()
        fake.configureChunks(["TRANSLATED"], for: "incomplete sentence without punctuation")

        let actor = TranslationActor(engineFactory: { fake })
        try await actor.warmup()

        let (segments, continuation) = AsyncStream<TranscriptSegment>.makeStream()
        let stream = await actor.translate(segments: segments, direction: .enToJa)

        continuation.yield(Self.segment(text: "incomplete sentence without punctuation"))
        continuation.finish() // No punctuation, no silence timeout — relies on flushRemaining.

        var completed: [TranslatedSegment] = []
        for try await event in stream {
            if case let .completed(translated) = event {
                completed.append(translated)
            }
        }

        #expect(completed.count == 1)
        #expect(completed.first?.translatedText == "TRANSLATED")
    }

    @Test("C-T-VIOLATION-SLOW-DOWNSTREAM: consumer not draining → upstream continues enqueuing")
    func translate_consumerNotDraining_upstreamContinuesEnqueuing() async throws {
        let fake = FakeLFM2Engine()
        // Default fake behavior is `.hang` so Step 6 queue-shape
        // tests stay clean. The SLOW-DOWNSTREAM test needs the
        // dispatch loop to actually drive forward, so switch the
        // fake to `.reverseInput` for this test only — each
        // `translate(...)` then yields one chunk equal to the
        // input reversed and completes.
        fake.setDefaultBehavior(.reverseInput)

        let actor = TranslationActor(engineFactory: { fake })
        try await actor.warmup()

        let (segments, continuation) = AsyncStream<TranscriptSegment>.makeStream()
        let stream = await actor.translate(segments: segments, direction: .enToJa)

        // Fast upstream: 5 sentences in a burst.
        for i in 0 ..< 5 {
            continuation.yield(Self.segment(text: "Sentence \(i)."))
        }
        continuation.finish()

        // Slow downstream: sleep between iterations.
        var receivedCompleted: [TranslatedSegment] = []
        for try await event in stream {
            if case let .completed(translated) = event {
                receivedCompleted.append(translated)
                try await Task.sleep(for: .milliseconds(20)) // slow consumer
            }
        }

        #expect(receivedCompleted.count == 5)
        // Ordering: same as input arrival order.
        let expectedOrder = (0 ..< 5).map { ".\($0) ecnetneS" } // reverse of "Sentence \(i)."
        let actualOrder = receivedCompleted.map(\.translatedText)
        #expect(actualOrder == expectedOrder)
    }
}
