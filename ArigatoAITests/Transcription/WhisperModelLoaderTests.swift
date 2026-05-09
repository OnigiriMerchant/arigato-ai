//
//  WhisperModelLoaderTests.swift
//  ArigatoAITests
//
//  Created by Jose Castell on 2026/05/10.
//

@testable import ArigatoAI
import Foundation
import os
import Testing

/// Test-local fake conformer to ``WhisperEngine``. Stateless; every call
/// to ``prewarmModels()`` returns immediately. Reference identity (`===`)
/// is used by the loader tests to assert that coalesced callers receive
/// the same instance.
private final class FakeWhisperEngine: WhisperEngine, @unchecked Sendable {
    func prewarmModels() async throws {
        // Intentionally empty — the loader tests only care about lifecycle,
        // not pre-warm side effects.
    }
}

/// Test-local error used to drive the failure-path behaviour of
/// ``WhisperModelLoader``. Distinct from ``TranscriptionError`` so the
/// loader's wrapping behaviour (raw error -> ``TranscriptionError/modelLoadFailed(_:)``)
/// is observable.
private enum TestError: Error {
    case bang
}

/// Counts factory invocations under a lock so concurrent callers can
/// assert "factory called exactly once" without data races. Uses
/// `OSAllocatedUnfairLock` per the CLAUDE.md Swift 6 rule that bans
/// `NSLock` from async contexts.
private final class CallCounter: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: 0)

    func increment() {
        lock.withLock { $0 += 1 }
    }

    var value: Int {
        lock.withLock { $0 }
    }
}

/// Holds a `CheckedContinuation` so a test can release a blocked factory
/// at a chosen moment. Allows the coalescing test to fan out 50 callers
/// before the single in-flight load is permitted to complete.
private final class ContinuationGate: @unchecked Sendable {
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

@Suite("WhisperModelLoader")
struct WhisperModelLoaderTests {
    @Test("first call loads via the factory and transitions to .loaded")
    func loadIfNeeded_firstCall_loadsViaFactoryAndTransitionsToLoaded() async throws {
        let counter = CallCounter()
        let engine = FakeWhisperEngine()
        let loader = WhisperModelLoader(factory: { _ in
            counter.increment()
            return engine
        })

        _ = try await loader.loadIfNeeded()

        let state = await loader.currentState()
        guard case .loaded = state else {
            Issue.record("Expected .loaded after successful load, got \(state)")
            return
        }
        #expect(counter.value == 1)
    }

    @Test("second call after success returns the same engine without re-invoking the factory")
    func loadIfNeeded_secondCallAfterSuccess_returnsSameEngineWithoutCallingFactoryAgain() async throws {
        let counter = CallCounter()
        let engine = FakeWhisperEngine()
        let loader = WhisperModelLoader(factory: { _ in
            counter.increment()
            return engine
        })

        let first = try await loader.loadIfNeeded()
        let second = try await loader.loadIfNeeded()

        #expect(counter.value == 1)
        let firstFake = first as? FakeWhisperEngine
        let secondFake = second as? FakeWhisperEngine
        #expect(firstFake === engine)
        #expect(secondFake === engine)
        #expect(firstFake === secondFake)
    }

    @Test("concurrent calls coalesce into a single load")
    func loadIfNeeded_concurrentCalls_coalesceToSingleLoad() async {
        let counter = CallCounter()
        let gate = ContinuationGate()
        let engine = FakeWhisperEngine()
        let loader = WhisperModelLoader(factory: { _ in
            counter.increment()
            await gate.wait()
            return engine
        })

        let callerCount = 50

        async let releaseAfterFanout: Void = {
            // Give the task group a beat to fan out all 50 callers and
            // bind them to the in-flight task before releasing the gate.
            try? await Task.sleep(for: .milliseconds(50))
            gate.release()
        }()

        let results = await withTaskGroup(of: (any WhisperEngine)?.self, returning: [any WhisperEngine].self) { group in
            for _ in 0 ..< callerCount {
                group.addTask {
                    try? await loader.loadIfNeeded()
                }
            }
            var collected: [any WhisperEngine] = []
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
            let fake = result as? FakeWhisperEngine
            #expect(fake === engine)
        }
    }

    @Test("a failing factory transitions the loader to .failed and rethrows as TranscriptionError")
    func loadIfNeeded_factoryThrows_transitionsToFailedAndRethrowsAsModelLoadFailed() async {
        let loader = WhisperModelLoader(factory: { _ in
            throw TestError.bang
        })

        await #expect(throws: TranscriptionError.self) {
            _ = try await loader.loadIfNeeded()
        }

        let state = await loader.currentState()
        guard case let .failed(error) = state else {
            Issue.record("Expected .failed state, got \(state)")
            return
        }
        if case .modelLoadFailed = error {
            // Match — wrapped string detail can be anything.
        } else {
            Issue.record("Expected .modelLoadFailed, got \(error)")
        }
    }

    @Test("a load attempt after a failure retries via the factory")
    func loadIfNeeded_afterFailure_retries() async throws {
        let attempts = CallCounter()
        let engine = FakeWhisperEngine()
        let loader = WhisperModelLoader(factory: { _ in
            attempts.increment()
            if attempts.value == 1 {
                throw TestError.bang
            }
            return engine
        })

        await #expect(throws: TranscriptionError.self) {
            _ = try await loader.loadIfNeeded()
        }

        let result = try await loader.loadIfNeeded()
        let fake = result as? FakeWhisperEngine
        #expect(fake === engine)

        let state = await loader.currentState()
        guard case .loaded = state else {
            Issue.record("Expected .loaded after retry, got \(state)")
            return
        }
        #expect(attempts.value == 2)
    }

    @Test("unload after a successful load returns the loader to .idle")
    func unload_afterLoaded_returnsToIdle() async throws {
        let engine = FakeWhisperEngine()
        let loader = WhisperModelLoader(factory: { _ in engine })

        _ = try await loader.loadIfNeeded()

        let loadedState = await loader.currentState()
        guard case .loaded = loadedState else {
            Issue.record("Expected .loaded before unload, got \(loadedState)")
            return
        }

        await loader.unload()

        let idleState = await loader.currentState()
        guard case .idle = idleState else {
            Issue.record("Expected .idle after unload, got \(idleState)")
            return
        }
    }

    @Test("unload while a load is in flight does not interrupt the in-flight task")
    func unload_doesNotInterruptInFlightLoad() async throws {
        let gate = ContinuationGate()
        let engine = FakeWhisperEngine()
        let loader = WhisperModelLoader(factory: { _ in
            await gate.wait()
            return engine
        })

        let loadTask = Task {
            try await loader.loadIfNeeded()
        }

        // Let the loader bind the task before unloading.
        try? await Task.sleep(for: .milliseconds(50))

        await loader.unload()

        gate.release()

        let result = try await loadTask.value
        let fake = result as? FakeWhisperEngine
        #expect(fake === engine)
    }
}
