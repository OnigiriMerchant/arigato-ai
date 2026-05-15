//
//  TranslationActor.swift
//  ArigatoAI
//
//  Created by Jose Castell on 2026/05/16.
//

import Foundation

/// Test-seam factory closure that resolves an ``LFM2Engine`` for
/// ``TranslationActor`` without going through ``LFM2ModelLoader``.
///
/// Declared at file scope (matching the ``LFM2EngineFactory`` and
/// ``WhisperEngineFactory`` patterns from Phase 4 / Group B) so the
/// closure type has a stable named home and the test-seam initializer
/// signature stays compact.
typealias TranslationActorEngineFactory = @Sendable () async throws -> any LFM2Engine

/// Actor that owns LFM2 inference for one bidirectional translation
/// session.
///
/// **Scheduling assumption** (Step 5 scaffold — full version surfaces
/// in Step 6+): this actor will enqueue at most one in-flight LFM2
/// generation at a time. A ``LeapSDK.Conversation`` instance is
/// created per direction call inside ``LFM2EngineAdapter.translate(_:_:)``,
/// retained for the lifetime of the active translate call, and never
/// shared across calls or actors. Concurrent upstream segments will
/// queue FIFO; the queue cap (`maxQueuedSentences = 20`) is enforced
/// in Step 6.
///
/// **Step 5 scope** (this file's current content): init, warmup,
/// warmupState. The `translate(segments:direction:)` and `cancel()`
/// methods are stubs that satisfy the protocol but emit no events
/// — Step 6 builds the sentence queue and drain task, Step 7 wires
/// LFM2 dispatch, Step 8 wires real cancellation.
///
/// **Violation behavior** (forward reference): documented in the
/// final Step 8 commit. For now: a translate call returns an
/// immediately-finished stream; cancel is a no-op.
actor TranslationActor {
    // MARK: - Stored state

    /// The production model loader. Optional because the test-seam
    /// initializer bypasses the loader and uses an engine factory
    /// directly. Exactly one of `loader` and `engineFactory` is
    /// non-nil at any time.
    private let loader: LFM2ModelLoader?

    /// The test-seam engine factory. Bypasses the loader entirely
    /// — used by ``TranslationActorTests`` to inject a fake
    /// ``LFM2Engine`` without linking LEAP SDK or constructing a real
    /// loader.
    private let engineFactory: TranslationActorEngineFactory?

    /// Resolved engine. Cached after first successful `warmup()`.
    private var resolvedEngine: (any LFM2Engine)?

    /// In-flight warmup task. Concurrent `warmup()` callers coalesce
    /// against this task.
    private var inFlightWarmup: Task<any LFM2Engine, Error>?

    /// Current warmup state. Mutated by `warmup()` transitions and
    /// observed by `warmupState()`.
    private var currentState: TranslationWarmupState = .cold

    // MARK: - Init

    /// Production initializer. Uses the supplied ``LFM2ModelLoader``
    /// for engine resolution.
    ///
    /// - Parameter loader: The shared ``LFM2ModelLoader`` whose
    ///   `loadIfNeeded(quantization:)` + `warmup()` pair drives
    ///   engine resolution.
    init(loader: LFM2ModelLoader) {
        self.loader = loader
        engineFactory = nil
    }

    /// Test-seam initializer. Bypasses the loader entirely and
    /// resolves the engine via the supplied factory closure.
    /// Used by ``TranslationActorTests`` to inject a fake engine
    /// without constructing a real `LFM2ModelLoader` or linking
    /// LEAP SDK.
    ///
    /// - Parameter engineFactory: Closure returning an ``LFM2Engine``
    ///   conformer. Invoked exactly once across all coalesced
    ///   `warmup()` callers per fresh-warmup epoch.
    init(engineFactory: @escaping TranslationActorEngineFactory) {
        loader = nil
        self.engineFactory = engineFactory
    }

    // MARK: - Translating (warmup + state)

    /// Resolves the engine and runs warmup canaries.
    ///
    /// **Behavior**:
    /// - First call from `.cold` transitions to `.warming`, spawns a
    ///   single task that runs the loader path (production) or the
    ///   engine-factory path (test), and transitions to `.ready` on
    ///   success or `.failed(_:)` on failure.
    /// - Concurrent callers coalesce against the in-flight task —
    ///   exactly one factory or loader invocation per fresh-warmup
    ///   epoch.
    /// - A call after success is a no-op (returns immediately).
    /// - A call after failure retries: the failed state does not
    ///   strand future warmup attempts.
    ///
    /// - Throws: ``TranslationError`` wrapping any underlying error.
    func warmup() async throws {
        if case .ready = currentState {
            return
        }

        if let inFlightWarmup {
            _ = try await inFlightWarmup.value
            return
        }

        let task = Task<any LFM2Engine, Error> { [loader, engineFactory] in
            if let loader {
                let engine = try await loader.loadIfNeeded()
                try await loader.warmup()
                return engine
            } else if let engineFactory {
                return try await engineFactory()
            } else {
                // Unreachable: one of the two is set per init.
                throw TranslationError.modelLoadFailed("TranslationActor has neither loader nor engineFactory")
            }
        }
        inFlightWarmup = task
        currentState = .warming

        do {
            let engine = try await task.value
            resolvedEngine = engine
            currentState = .ready
            inFlightWarmup = nil
        } catch let error as TranslationError {
            currentState = .failed(error)
            inFlightWarmup = nil
            throw error
        } catch {
            let wrapped = TranslationError.modelLoadFailed(error.localizedDescription)
            currentState = .failed(wrapped)
            inFlightWarmup = nil
            throw wrapped
        }
    }

    /// Returns the current warmup state. Cheap and safe to poll.
    func warmupState() async -> TranslationWarmupState {
        currentState
    }

    // MARK: - Translating (stubs for Steps 6/7/8)

    /// Stub — returns an immediately-finished stream. Step 6 builds
    /// the sentence queue + drain task; Step 7 wires LFM2 dispatch.
    func translate(
        segments _: AsyncStream<TranscriptSegment>,
        direction _: TranslationDirection
    ) async -> AsyncThrowingStream<TranslationEvent, any Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    /// Stub — no-op. Step 8 wires real cancellation against
    /// ``LeapSDK.GenerationHandler/stop()`` and the drain task.
    func cancel() async {
        // No-op at Step 5 scope.
    }
}

// MARK: - Translating conformance

/// Conformance is declared in an extension (rather than on the actor
/// declaration itself) to keep the actor's explicit designated
/// initializers from being inferred as `@MainActor`-isolated under the
/// project's ``SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`` setting. When
/// the conformance is declared inline (`actor TranslationActor:
/// Translating`), the compiler infers MainActor isolation on the
/// synchronous designated initializers, which then prevents test code
/// running outside the main actor from constructing the actor. Splitting
/// the conformance into an extension restores the actor's natural
/// nonisolated-init posture without changing runtime behavior — every
/// protocol requirement is satisfied by methods already declared on the
/// actor body above.
extension TranslationActor: Translating {}
