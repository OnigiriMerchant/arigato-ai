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

@Suite("TranslationActor scaffold (Step 5)")
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
}
