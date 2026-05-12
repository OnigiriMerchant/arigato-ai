//
//  LFM2ModelLoaderTests.swift
//  ArigatoAITests
//
//  Created by Jose Castell on 2026/05/12.
//

@testable import ArigatoAI
import Foundation
import os
import Testing

// MARK: - Fakes

/// Test-local fake conformer to ``LFM2Engine``. Records every
/// ``warmupCanary(direction:)`` invocation under a lock so concurrent
/// warmup tests can assert exact canary counts and call ordering without
/// data races.
///
/// Uses `OSAllocatedUnfairLock` per the CLAUDE.md Swift 6 rule that bans
/// `NSLock` from async contexts. The class is `@unchecked Sendable`
/// because the lock provides all the necessary synchronisation around
/// the mutable state; the inherited rule mirrors Phase 4's
/// ``FakeWhisperClient`` placement.
///
/// Reference identity (`===`) is used by the loader tests to assert
/// that coalesced callers receive the same engine instance.
private final class FakeModelRunner: LFM2Engine, @unchecked Sendable {
    /// Test-injectable behaviour. When `warmupBehaviour(direction)` is
    /// non-nil, the closure decides whether to throw; returning `nil`
    /// from the closure means "succeed".
    var warmupBehaviour: (@Sendable (TranslationDirection) -> Error?)?

    private struct State {
        var directionsCalled: [TranslationDirection] = []
    }

    private let lock = OSAllocatedUnfairLock(initialState: State())

    /// Optional gate that, when set, causes ``warmupCanary(direction:)``
    /// to await the supplied stream's first element before proceeding.
    /// Used by tests that need to fan out concurrent warmup callers and
    /// hold the in-flight canary until they have all coalesced.
    var canaryGate: LFM2ContinuationGate?

    func warmupCanary(direction: TranslationDirection) async throws {
        if let canaryGate {
            await canaryGate.wait()
        }
        lock.withLock { state in
            state.directionsCalled.append(direction)
        }
        if let warmupBehaviour, let error = warmupBehaviour(direction) {
            throw error
        }
    }

    var directionsCalled: [TranslationDirection] {
        lock.withLock { $0.directionsCalled }
    }
}

/// Test-local error used to drive failure paths in the loader. Distinct
/// from ``TranslationError`` so the loader's wrapping behaviour
/// (raw error → ``TranslationError/modelLoadFailed(_:)`` /
/// ``TranslationError/warmupFailed(_:)``) is observable.
private enum LFM2TestError: Error {
    case bang
}

/// Counts factory invocations under a lock so concurrent callers can
/// assert "factory called exactly once" without data races. Mirrors
/// Phase 4's ``CallCounter``; duplicated locally so tests do not depend
/// on cross-suite visibility.
private final class CallCounter: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: 0)

    func increment() {
        lock.withLock { $0 += 1 }
    }

    var value: Int {
        lock.withLock { $0 }
    }
}

/// Records `Double` values supplied to the loader's progress handler
/// under a lock. Tests assert the recorded sequence to lock the
/// progress-routing contract.
private final class ProgressRecorder: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock<[Double]>(initialState: [])

    func record(_ value: Double) {
        lock.withLock { $0.append(value) }
    }

    var values: [Double] {
        lock.withLock { $0 }
    }
}

/// Holds a `CheckedContinuation` so a test can release a blocked task
/// at a chosen moment. Allows the coalescing tests to fan out callers
/// before the single in-flight task is permitted to complete. Public
/// so ``FakeModelRunner`` can hold one externally.
private final class LFM2ContinuationGate: @unchecked Sendable {
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

// MARK: - Pattern helpers

private func isLoaded(_ state: LFM2LoaderState) -> Bool {
    if case .loaded = state { return true }
    return false
}

private func isIdle(_ state: LFM2LoaderState) -> Bool {
    if case .idle = state { return true }
    return false
}

private func isReady(_ state: LFM2LoaderState) -> Bool {
    if case .ready = state { return true }
    return false
}

private func isFailedWithModelLoadFailed(_ state: LFM2LoaderState) -> Bool {
    guard case let .failed(error) = state else { return false }
    if case .modelLoadFailed = error { return true }
    return false
}

private func isFailedWithWarmupFailed(_ state: LFM2LoaderState) -> Bool {
    guard case let .failed(error) = state else { return false }
    if case .warmupFailed = error { return true }
    return false
}

// MARK: - Suite

@Suite("LFM2ModelLoader")
struct LFM2ModelLoaderTests {
    // MARK: loadIfNeeded

    @Test("T4.1 first call loads via the factory and transitions to .loaded")
    func loadIfNeeded_firstCall_loadsViaFactoryAndTransitionsToLoaded() async throws {
        let counter = CallCounter()
        let engine = FakeModelRunner()
        let loader = LFM2ModelLoader(factory: { _, _ in
            counter.increment()
            return engine
        })

        _ = try await loader.loadIfNeeded(quantization: "Q5_K_M")

        let state = await loader.currentState()
        #expect(isLoaded(state), "Expected .loaded after successful load, got \(state)")
        #expect(counter.value == 1)
    }

    @Test("T4.2 second call after success returns the same engine without re-invoking the factory")
    func loadIfNeeded_secondCallAfterSuccess_returnsSameEngineWithoutCallingFactoryAgain() async throws {
        let counter = CallCounter()
        let engine = FakeModelRunner()
        let loader = LFM2ModelLoader(factory: { _, _ in
            counter.increment()
            return engine
        })

        let first = try await loader.loadIfNeeded(quantization: "Q5_K_M")
        let second = try await loader.loadIfNeeded(quantization: "Q5_K_M")

        #expect(counter.value == 1)
        let firstFake = first as? FakeModelRunner
        let secondFake = second as? FakeModelRunner
        #expect(firstFake === engine)
        #expect(secondFake === engine)
        #expect(firstFake === secondFake)
    }

    /// **V1 — A1 violation test.** Drives many concurrent
    /// ``LFM2ModelLoader/loadIfNeeded(quantization:)`` callers against
    /// a blocked factory and asserts the factory is invoked exactly
    /// once. Violation: a greedy producer of load requests must not
    /// trigger duplicate factory work.
    @Test("V1 concurrent calls coalesce into a single load")
    func loadIfNeeded_concurrentCalls_coalesceToSingleLoad() async {
        let counter = CallCounter()
        let gate = LFM2ContinuationGate()
        let engine = FakeModelRunner()
        let loader = LFM2ModelLoader(factory: { _, _ in
            counter.increment()
            await gate.wait()
            return engine
        })

        let callerCount = 50

        async let releaseAfterFanout: Void = {
            // Give the task group a beat to fan out all callers and
            // bind them to the in-flight task before releasing.
            try? await Task.sleep(for: .milliseconds(50))
            gate.release()
        }()

        let results = await withTaskGroup(of: (any LFM2Engine)?.self, returning: [any LFM2Engine].self) { group in
            for _ in 0 ..< callerCount {
                group.addTask {
                    try? await loader.loadIfNeeded(quantization: "Q5_K_M")
                }
            }
            var collected: [any LFM2Engine] = []
            for await result in group {
                if let result {
                    collected.append(result)
                }
            }
            return collected
        }

        await releaseAfterFanout

        #expect(counter.value == 1)
        #expect(results.count == callerCount)
        for result in results {
            let fake = result as? FakeModelRunner
            #expect(fake === engine)
        }
    }

    @Test("T4.3 a failing factory transitions to .failed and rethrows as modelLoadFailed")
    func loadIfNeeded_factoryThrows_transitionsToFailedAndRethrowsAsModelLoadFailed() async {
        let loader = LFM2ModelLoader(factory: { _, _ in
            throw LFM2TestError.bang
        })

        await #expect(throws: TranslationError.self) {
            _ = try await loader.loadIfNeeded(quantization: "Q5_K_M")
        }

        let state = await loader.currentState()
        #expect(isFailedWithModelLoadFailed(state), "Expected .failed(.modelLoadFailed), got \(state)")
    }

    @Test("T4.4 a load attempt after a failure retries via the factory")
    func loadIfNeeded_afterFailure_retries() async throws {
        let attempts = CallCounter()
        let engine = FakeModelRunner()
        let loader = LFM2ModelLoader(factory: { _, _ in
            attempts.increment()
            if attempts.value == 1 {
                throw LFM2TestError.bang
            }
            return engine
        })

        await #expect(throws: TranslationError.self) {
            _ = try await loader.loadIfNeeded(quantization: "Q5_K_M")
        }

        let result = try await loader.loadIfNeeded(quantization: "Q5_K_M")
        let fake = result as? FakeModelRunner
        #expect(fake === engine)

        let state = await loader.currentState()
        #expect(isLoaded(state), "Expected .loaded after retry, got \(state)")
        #expect(attempts.value == 2)
    }

    /// **V3 — Cancellation-recovery violation test.** Drives one
    /// caller, cancels the caller's outer task while the load is
    /// in-flight, and verifies that a subsequent
    /// ``LFM2ModelLoader/loadIfNeeded(quantization:)`` call still
    /// succeeds. Violation: cancellation of one caller must not strand
    /// the loader or poison the engine cache. Note: this test does
    /// **not** assert specific cancellation propagation semantics —
    /// it only asserts that the loader recovers cleanly so that
    /// fresh callers receive an engine.
    @Test("V3 loadIfNeeded after cancellation does not strand the loader")
    func loadIfNeeded_afterCancellation_succeedsOnRetry() async throws {
        let gate = LFM2ContinuationGate()
        let attempts = CallCounter()
        let engine = FakeModelRunner()
        let loader = LFM2ModelLoader(factory: { _, _ in
            attempts.increment()
            await gate.wait()
            return engine
        })

        let cancellingTask = Task {
            try await loader.loadIfNeeded(quantization: "Q5_K_M")
        }
        try? await Task.sleep(for: .milliseconds(50))
        cancellingTask.cancel()
        _ = try? await cancellingTask.value

        gate.release()

        // After the in-flight work completes (regardless of whether
        // the cancellation propagated into the actor body), a fresh
        // call must yield an engine. The retry may re-invoke the
        // factory if the cancellation poisoned the in-flight task —
        // either way the loader must not be stranded.
        let result = try await loader.loadIfNeeded(quantization: "Q5_K_M")
        let fake = result as? FakeModelRunner
        #expect(fake === engine)
        #expect(attempts.value >= 1)
    }

    /// **V2 — A2 violation test.** Calls ``LFM2ModelLoader/unload()``
    /// while a load is in flight and asserts the in-flight task still
    /// completes. Violation: a synchronous unload must not interrupt
    /// async work that is already running.
    @Test("V2 unload while a load is in flight does not interrupt the in-flight task")
    func unload_doesNotInterruptInFlightLoad() async throws {
        let gate = LFM2ContinuationGate()
        let engine = FakeModelRunner()
        let loader = LFM2ModelLoader(factory: { _, _ in
            await gate.wait()
            return engine
        })

        let loadTask = Task {
            try await loader.loadIfNeeded(quantization: "Q5_K_M")
        }

        try? await Task.sleep(for: .milliseconds(50))
        await loader.unload()

        gate.release()

        let result = try await loadTask.value
        let fake = result as? FakeModelRunner
        #expect(fake === engine)
    }

    @Test("T4.5 unload after a successful load returns the loader to .idle")
    func unload_afterLoaded_returnsToIdle() async throws {
        let engine = FakeModelRunner()
        let loader = LFM2ModelLoader(factory: { _, _ in engine })

        _ = try await loader.loadIfNeeded(quantization: "Q5_K_M")
        let loadedState = await loader.currentState()
        #expect(isLoaded(loadedState), "Expected .loaded before unload, got \(loadedState)")

        await loader.unload()

        let idleState = await loader.currentState()
        #expect(isIdle(idleState), "Expected .idle after unload, got \(idleState)")
    }

    // MARK: warmup

    @Test("T4.6 warmup before load throws modelNotReady")
    func warmup_beforeLoad_throwsModelNotReady() async {
        let loader = LFM2ModelLoader(factory: { _, _ in FakeModelRunner() })

        await #expect(throws: TranslationError.modelNotReady) {
            try await loader.warmup()
        }
    }

    @Test("T4.7 warmup after load runs both canaries sequentially in order EN-to-JA then JA-to-EN")
    func warmup_afterLoad_runsBothCanariesSequentially() async throws {
        let engine = FakeModelRunner()
        let loader = LFM2ModelLoader(factory: { _, _ in engine })

        _ = try await loader.loadIfNeeded(quantization: "Q5_K_M")
        try await loader.warmup()

        #expect(engine.directionsCalled == [.enToJa, .jaToEn])

        let state = await loader.currentState()
        #expect(isReady(state), "Expected .ready after successful warmup, got \(state)")
    }

    /// **V4 — A3 violation test.** Drives multiple concurrent
    /// ``LFM2ModelLoader/warmup()`` callers against a fake engine and
    /// asserts the canary call count is exactly two (one per
    /// direction), not 2 × callerCount. Violation: a greedy producer
    /// of warmup requests must coalesce onto a single warmup epoch.
    @Test("V4 warmup concurrent calls coalesce — exactly two canaries fire total")
    func warmup_concurrentCallsCoalesce() async throws {
        let gate = LFM2ContinuationGate()
        let engine = FakeModelRunner()
        engine.canaryGate = gate
        let loader = LFM2ModelLoader(factory: { _, _ in engine })

        _ = try await loader.loadIfNeeded(quantization: "Q5_K_M")

        let callerCount = 25

        async let releaseAfterFanout: Void = {
            try? await Task.sleep(for: .milliseconds(50))
            // Release once for the EN-to-JA canary; once for JA-to-EN.
            gate.release()
            try? await Task.sleep(for: .milliseconds(50))
            gate.release()
        }()

        await withTaskGroup(of: Void.self) { group in
            for _ in 0 ..< callerCount {
                group.addTask {
                    try? await loader.warmup()
                }
            }
            for await _ in group {}
        }

        await releaseAfterFanout

        #expect(engine.directionsCalled == [.enToJa, .jaToEn])
    }

    /// **V5 — A3 idempotence violation test.** Calls
    /// ``LFM2ModelLoader/warmup()`` against an already-``ready``
    /// loader and asserts no new canaries fire. Violation: redundant
    /// warmup calls must not pay cold-start cost again.
    @Test("V5 warmup called after .ready is a no-op — no additional canaries fire")
    func warmup_calledAfterReady_isNoOp() async throws {
        let engine = FakeModelRunner()
        let loader = LFM2ModelLoader(factory: { _, _ in engine })

        _ = try await loader.loadIfNeeded(quantization: "Q5_K_M")
        try await loader.warmup()
        #expect(engine.directionsCalled == [.enToJa, .jaToEn])

        // Second warmup must not add canaries.
        try await loader.warmup()
        #expect(engine.directionsCalled == [.enToJa, .jaToEn])

        let state = await loader.currentState()
        #expect(isReady(state))
    }

    /// **V6 — A3 retry-after-failure violation test.** Drives one
    /// failing warmup, then a second warmup with the failure cleared,
    /// and asserts the second succeeds. Violation: a failed warmup
    /// must not strand the loader.
    @Test("V6 warmup after failure retries — second call succeeds when failure cleared")
    func warmup_afterFailure_retries() async throws {
        let engine = FakeModelRunner()
        engine.warmupBehaviour = { direction in
            // First call (EN-to-JA) fails; clear the behaviour after.
            direction == .enToJa ? LFM2TestError.bang : nil
        }
        let loader = LFM2ModelLoader(factory: { _, _ in engine })

        _ = try await loader.loadIfNeeded(quantization: "Q5_K_M")

        await #expect(throws: TranslationError.self) {
            try await loader.warmup()
        }

        let failedState = await loader.currentState()
        #expect(isFailedWithWarmupFailed(failedState), "Expected .failed(.warmupFailed), got \(failedState)")

        // Clear the failure injector and re-attempt warmup.
        engine.warmupBehaviour = nil
        try await loader.warmup()

        let readyState = await loader.currentState()
        #expect(isReady(readyState), "Expected .ready after warmup retry, got \(readyState)")
        #expect(engine.directionsCalled == [.enToJa, .enToJa, .jaToEn])
    }

    @Test("T4.8 progressHandler receives progress during load")
    func progressHandler_receivesProgressDuringLoad() async throws {
        let recorder = ProgressRecorder()
        let engine = FakeModelRunner()
        let factory: LFM2EngineFactory = { _, handler in
            handler?(0.25)
            handler?(0.5)
            handler?(1.0)
            return engine
        }

        let loader = LFM2ModelLoader(
            factory: factory,
            progressHandler: { value in recorder.record(value) }
        )

        _ = try await loader.loadIfNeeded(quantization: "Q5_K_M")

        #expect(recorder.values == [0.25, 0.5, 1.0])
    }
}
