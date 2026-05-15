//
//  LFM2ModelLoader.swift
//  ArigatoAI
//
//  Created by Jose Castell on 2026/05/12.
//

import Foundation
import LeapSDK

// MARK: - Lifecycle state

/// Snapshot of ``LFM2ModelLoader``'s lifecycle, returned by
/// ``LFM2ModelLoader/currentState()``.
///
/// The states are observed by `AppBootstrapper` (Step 6) and any diagnostic
/// UI that wants to surface load progress without having to
/// `await loadIfNeeded(quantization:)` itself. The shape mirrors Phase 4's
/// ``LoaderState`` so consumers can apply the same observation pattern
/// across both pipelines, but the enum is intentionally distinct so each
/// pipeline's diagnostics evolve independently.
///
/// Marked `nonisolated` because it is a pure value type. The associated
/// `any LFM2Engine` reference is `Sendable` by protocol conformance, so
/// the enum is safe to ferry across actor boundaries.
public nonisolated enum LFM2LoaderState: Sendable {
    /// No load has been requested, or ``LFM2ModelLoader/unload()`` was
    /// just called.
    case idle

    /// A load is in flight and no progress fraction has yet been
    /// reported by the underlying SDK. Concurrent
    /// ``LFM2ModelLoader/loadIfNeeded(quantization:)`` callers are
    /// coalescing against the single in-flight task.
    case loading

    /// A load is in flight and the SDK has reported a download-progress
    /// fraction in the closed interval `[0.0, 1.0]`. Distinct from
    /// ``loading`` so UI can render a determinate progress bar only when
    /// real progress data is available.
    case downloading(Double)

    /// The model is loaded but no warmup canary has yet succeeded.
    /// ``LFM2ModelLoader/warmup()`` transitions from here to either
    /// ``warming`` or ``failed(_:)``.
    case loaded(any LFM2Engine)

    /// A warmup is in flight. The two direction canaries (EN-to-JA first,
    /// JA-to-EN second) are running sequentially; on success the state
    /// transitions to ``ready``.
    case warming

    /// The model is loaded and both warmup canaries have completed
    /// successfully. The translator is ready for production inference.
    case ready

    /// The most recent lifecycle attempt failed. The payload distinguishes
    /// load failures from warmup failures via the ``TranslationError``
    /// case so callers can route the error appropriately.
    case failed(TranslationError)
}

// MARK: - Engine seam

/// Internal seam isolating the LEAP iOS SDK's non-`Sendable`
/// ``LeapSDK.ModelRunner`` behind a protocol that ``LFM2ModelLoader`` and
/// the test target can both hold.
///
/// `LFM2Engine` is the LFM2 analogue of Phase 4's ``WhisperClient`` /
/// ``WhisperEngine`` pattern: the production wrapper holds the SDK
/// instance and is marked `@unchecked Sendable`, while
/// ``LFM2ModelLoader`` (an actor) serialises every method call against
/// the wrapper. The protocol exposes only the surface the loader needs,
/// which lets tests inject a fake without linking `LeapSDK`.
///
/// **Why a sync `Sendable` protocol over a non-`Sendable` SDK class?**
/// `ModelRunner` is a plain protocol with no `Sendable` inheritance and
/// `Conversation` is a plain class — neither is safe to ferry across
/// actor boundaries directly. Wrapping both behind one actor-owned
/// `@unchecked Sendable` adapter is the established Phase 4 mitigation;
/// the same shape is reused here so the test target keeps its no-LeapSDK
/// posture.
///
/// **Scope.** Group B exposes only ``warmupCanary(direction:)`` because
/// warmup is the only inference surface the loader exercises during app
/// launch. Group C will add ``createConversation(systemPrompt:)`` and
/// related methods needed by the `TranslationActor`; adding them now
/// would be premature scope.
public protocol LFM2Engine: Sendable {
    /// Runs a single short dummy inference using the supplied translation
    /// direction's system prompt, so subsequent translation calls do not
    /// pay cold-start cost.
    ///
    /// The canary message is intentionally short ("Hello." for EN-to-JA;
    /// "こんにちは。" for JA-to-EN) so the inference completes quickly.
    /// The implementation creates a fresh ``LeapSDK.Conversation`` using
    /// ``LeapSDK.ModelRunner/createConversation(systemPrompt:)`` and
    /// drains the response stream until it sees ``LeapSDK.MessageResponse/complete(_:)``.
    ///
    /// - Parameter direction: The translation direction whose system
    ///   prompt drives the canary. Both directions are warmed up
    ///   sequentially by ``LFM2ModelLoader/warmup()``.
    /// - Throws: ``TranslationError/warmupFailed(_:)`` wrapping any
    ///   underlying SDK error.
    func warmupCanary(direction: TranslationDirection) async throws
}

/// Production adapter wrapping a real ``LeapSDK.ModelRunner`` instance.
///
/// Marked `@unchecked Sendable` because ``LeapSDK.ModelRunner`` itself is
/// not `Sendable` in LEAP iOS SDK v0.9.4. The unchecked annotation is
/// sound only because ``LFM2ModelLoader`` (an actor) is the sole owner of
/// the adapter and serialises every method call against it; do not share
/// an `LFM2EngineAdapter` reference across other actors directly.
///
/// Conforms to ``LFM2Engine`` so consumers downstream of the loader can
/// drive warmup against a real LEAP-backed runner. The adapter performs
/// the conversation-construction step and drains the response stream,
/// translating any underlying SDK error into ``TranslationError/warmupFailed(_:)``.
final nonisolated class LFM2EngineAdapter: LFM2Engine, @unchecked Sendable {
    private let modelRunner: any ModelRunner

    /// Creates the adapter from an already-constructed ``LeapSDK.ModelRunner``
    /// instance. Construction is delegated to ``LFM2ClientFactory/make`` so
    /// the adapter never needs to know the model identifier directly.
    init(modelRunner: any ModelRunner) {
        self.modelRunner = modelRunner
    }

    /// Drives one short dummy inference against the supplied direction's
    /// system prompt and returns when the SDK emits its `.complete`
    /// response, mapping any error onto ``TranslationError/warmupFailed(_:)``.
    func warmupCanary(direction: TranslationDirection) async throws {
        let conversation = modelRunner.createConversation(systemPrompt: direction.systemPrompt)
        let canaryText: String
        switch direction {
        case .enToJa:
            canaryText = "Hello."
        case .jaToEn:
            canaryText = "こんにちは。"
        }
        let message = ChatMessage(role: .user, content: [.text(canaryText)])
        let stream = conversation.generateResponse(message: message, generationOptions: nil)

        do {
            for try await response in stream {
                if case .complete = response {
                    return
                }
            }
        } catch {
            throw TranslationError.warmupFailed(error.localizedDescription)
        }
    }
}

// MARK: - Factory

/// A factory closure that resolves a quantization slug into a fully
/// constructed ``LFM2Engine``.
///
/// The closure is `@Sendable` so ``LFM2ModelLoader`` can hold it across
/// actor boundaries. Production wiring uses ``LFM2ClientFactory/make``;
/// tests inject their own closure that returns a fake engine without
/// linking `LeapSDK`.
///
/// The optional `progressHandler` receives raw download progress in the
/// closed interval `[0.0, 1.0]` as reported by the SDK. The handler is
/// invoked on whatever queue/thread the SDK uses for its callback; the
/// loader is responsible for hopping back to the main actor before
/// touching observable state.
public typealias LFM2EngineFactory = @Sendable (
    _ quantization: String,
    _ progressHandler: (@Sendable (Double) -> Void)?
) async throws -> any LFM2Engine

/// Production factory wiring for the LEAP-backed LFM2 engine.
///
/// Kept as a namespace (`enum` with a single static let) rather than a
/// free function so the production factory and any future variants live
/// next to each other in the type system. Mirrors Phase 4's
/// ``WhisperClientFactory`` shape.
///
/// **Cache strategy** (Phase 5 Decision 4, revised 2026-05-15 after
/// xcframework inspection — see PHASE_5_HANDOFF.md commit `842c156`):
/// ``LeapSDK.Leap/load(model:quantization:options:downloadProgressHandler:)``
/// is called with a ``LeapSDK.LiquidCacheOptions`` rooted under iOS's
/// user Caches directory (``LFM2CachePathResolver/resolve()``) with
/// `maxEntries: 1000`. The originally-locked "in-memory only" framing
/// was impossible to implement: ``LeapSDK.LiquidCacheOptions`` in LEAP
/// iOS SDK v0.9.4 is a struct requiring both `path: String` and
/// `maxEntries: Int` — no `.inMemory` case exists. Privacy stance is
/// preserved at the architecture level because iOS's Caches directory
/// is NOT iCloud-backed and is OS-managed (auto-purged under storage
/// pressure). Performance > privacy on-device per revised D4 reasoning:
/// capture any prompt-cache speedup the SDK delivers; flipping back to
/// `cacheOptions: nil` is one-line trivial if Phase 6 diagnostics show
/// the cache is irrelevant. V3 entry "LFM2 prompt cache effectiveness
/// benchmark" tracks that revisit.
///
/// **What happens if cache path resolution throws.** ``LFM2CachePathResolver/resolve()``
/// throws ``TranslationError/cachePathResolutionFailed(_:)`` only when
/// `FileManager.urls(for: .cachesDirectory, in: .userDomainMask)`
/// returns an empty array, which the sandbox guarantees never happens
/// on real iOS. If it ever does, the factory's `try` propagates the
/// error to the loader, which wraps it in
/// ``TranslationError/modelLoadFailed(_:)`` per its standard error path.
public nonisolated enum LFM2ClientFactory {
    /// The maximum number of prompt-cache entries retained on disk
    /// before the SDK applies its internal eviction policy (undocumented
    /// beyond this cap — see swiftinterface for v0.9.4). Tuned downward
    /// or upward per the V3 entry "LFM2 prompt cache effectiveness
    /// benchmark" once Phase 6 diagnostics produce real-meeting data.
    public static let cacheMaxEntries: Int = 1000

    /// The production ``LFM2EngineFactory``. Constructs a real
    /// ``LeapSDK.ModelRunner`` via the GGUF manifest path
    /// (``LeapSDK.Leap/load(model:quantization:options:downloadProgressHandler:)``),
    /// supplies a ``LeapSDK.LiquidCacheOptions`` rooted under iOS's user
    /// Caches directory (see the type-level "Cache strategy" doc), and
    /// wraps the resulting runner in ``LFM2EngineAdapter``. The model
    /// identifier is pinned to `"lfm2-350m-enjp-mt"` per Phase 5
    /// Decision 1.
    public static let make: LFM2EngineFactory = { quantization, progressHandler in
        let cachePath = try LFM2CachePathResolver.resolve()
        let cacheOptions = LiquidCacheOptions(
            path: cachePath,
            maxEntries: cacheMaxEntries
        )
        let manifestOptions = LiquidInferenceEngineManifestOptions(
            cacheOptions: cacheOptions
        )
        let runner = try await Leap.load(
            model: "lfm2-350m-enjp-mt",
            quantization: quantization,
            options: manifestOptions,
            downloadProgressHandler: { progress, _ in
                progressHandler?(progress)
            }
        )
        return LFM2EngineAdapter(modelRunner: runner)
    }
}

// MARK: - Loader actor

/// Owns the lifecycle of the underlying LFM2 engine and coalesces
/// concurrent load and warmup requests into single in-flight tasks.
///
/// The loader is the single point of contact between the rest of the app
/// and the LEAP-backed translation engine. It is an actor so the
/// underlying engine — which is not `Sendable` in LEAP iOS SDK v0.9.4 —
/// can be held safely across async boundaries.
///
/// Mirrors Phase 4's ``WhisperModelLoader`` shape closely: a single
/// loading state, a single in-flight task, and a single `factory`
/// dependency injected for testability. The LFM2 path adds the
/// download-progress channel and the two-canary warmup step.
///
/// ## Concurrency contract
///
/// **A1 — Load coalescing.** Concurrent
/// ``loadIfNeeded(quantization:)`` callers coalesce against the single
/// in-flight task. The factory is invoked exactly once per fresh-load
/// epoch; subsequent callers receive the resolved engine without
/// re-invoking the factory. Locked by
/// ``LFM2ModelLoaderTests/loadIfNeeded_concurrentCalls_coalesceToSingleLoad``.
///
/// **A2 — Unload non-interruption.** ``unload()`` resets state to
/// ``LFM2LoaderState/idle`` synchronously but does **not** cancel an
/// in-flight load. Any task spawned by ``loadIfNeeded(quantization:)``
/// continues to run and its eventual success or failure overrides the
/// idle reset. Callers that want to truly cancel an in-flight load
/// should cancel their own awaiting task. Locked by
/// ``LFM2ModelLoaderTests/unload_doesNotInterruptInFlightLoad``.
///
/// **A3 — Warmup sequential + idempotent.** ``warmup()`` runs the two
/// direction canaries (EN-to-JA first, JA-to-EN second) **sequentially**
/// inside a single coalesced task. Concurrent ``warmup()`` callers
/// coalesce against that task — exactly two canaries fire per warmup
/// epoch regardless of how many callers concurrently await. A
/// ``warmup()`` call against an already-``LFM2LoaderState/ready`` loader
/// is a no-op. Locked by
/// ``LFM2ModelLoaderTests/warmup_concurrentCallsCoalesce`` and
/// ``LFM2ModelLoaderTests/warmup_calledAfterReady_isNoOp``.
///
/// **A4 — Progress on SDK's thread.** The `progressHandler` closure
/// passed into ``init(factory:progressHandler:)`` is invoked on
/// whichever queue/thread the LEAP SDK uses for its download callback.
/// The loader itself does not hop the handler onto the main actor;
/// consumers that bind to UI state (e.g. ``AppBootstrapper``) are
/// responsible for the main-actor hop in their own handler.
///
/// Access level is `internal` because the associated payload of
/// ``LFM2LoaderState/loaded(_:)`` is the internal ``LFM2Engine`` protocol;
/// this actor cannot be `public` without first promoting ``LFM2Engine``
/// to `public`. (``LFM2Engine`` is declared `public` already; the
/// loader API stays `internal` to match Phase 4's
/// ``WhisperModelLoader`` access posture so tests retain `@testable`
/// reach without exposing a wider module boundary.)
actor LFM2ModelLoader {
    private var state: LFM2LoaderState = .idle
    /// Strong reference to the loaded engine, held independently of
    /// ``state``. This decouples engine identity from the lifecycle
    /// state machine so warmup transitions
    /// (``LFM2LoaderState/loaded(_:)`` → ``LFM2LoaderState/warming`` →
    /// ``LFM2LoaderState/ready``) do not drop the engine reference —
    /// only ``unload()`` clears it.
    private var loadedEngine: (any LFM2Engine)?
    private var inFlightLoad: Task<any LFM2Engine, Error>?
    private var inFlightWarmup: Task<Void, Error>?
    private let factory: LFM2EngineFactory
    private let progressHandler: (@Sendable (Double) -> Void)?

    /// Designated initializer.
    ///
    /// - Parameters:
    ///   - factory: The factory closure that resolves a quantization
    ///     slug into an ``LFM2Engine``. Defaulted to the production
    ///     wiring at ``LFM2ClientFactory/make``. Tests inject a custom
    ///     closure that returns a fake.
    ///   - progressHandler: Optional download-progress sink invoked with
    ///     the SDK's reported fraction in `[0.0, 1.0]`. Per contract
    ///     **A4**, this closure runs on the SDK's callback thread;
    ///     consumers that touch main-actor state must hop themselves.
    init(
        factory: @escaping LFM2EngineFactory = LFM2ClientFactory.make,
        progressHandler: (@Sendable (Double) -> Void)? = nil
    ) {
        self.factory = factory
        self.progressHandler = progressHandler
    }

    /// Loads the LFM2 model for the requested quantization slug if no
    /// engine is already loaded; coalesces concurrent calls into a
    /// single in-flight task.
    ///
    /// Behaviour:
    /// - If the loader is already in ``LFM2LoaderState/loaded(_:)``,
    ///   ``LFM2LoaderState/warming``, or ``LFM2LoaderState/ready``, the
    ///   already-loaded engine is returned immediately. Quantization
    ///   mismatch is silently ignored: callers requesting a different
    ///   slug after one is loaded receive the already-loaded engine.
    ///   This matches the single-engine ownership invariant.
    /// - If a load is already in flight, the caller awaits the same
    ///   task. No second load is started (contract **A1**).
    /// - Otherwise a fresh `Task` is started against ``factory`` and
    ///   ``state`` transitions to ``LFM2LoaderState/loading``. On
    ///   success, ``state`` becomes ``LFM2LoaderState/loaded(_:)`` and
    ///   the engine is returned. On failure, ``state`` becomes
    ///   ``LFM2LoaderState/failed(_:)`` and the error is rethrown as
    ///   ``TranslationError/modelLoadFailed(_:)``. The next call retries.
    /// - **Cancellation**: if a caller's outer task is cancelled while
    ///   it awaits the in-flight load, only that caller's await throws
    ///   `CancellationError`. The shared in-flight task continues so
    ///   other coalescing callers still receive their result.
    ///
    /// - Parameter quantization: The quantization slug to request.
    ///   Defaulted to `"Q5_K_M"` per Phase 5 Decision 1.
    /// - Returns: The loaded ``LFM2Engine`` instance.
    /// - Throws: ``TranslationError/modelLoadFailed(_:)`` wrapping any
    ///   underlying factory error.
    func loadIfNeeded(quantization: String = "Q5_K_M") async throws -> any LFM2Engine {
        // Engine identity is decoupled from state: any state at or past
        // ``loaded`` retains ``loadedEngine`` until ``unload()`` clears
        // it. Return the cached engine regardless of warmup progress.
        if let loadedEngine {
            return loadedEngine
        }

        if let inFlightLoad {
            return try await inFlightLoad.value
        }

        let factory = self.factory
        let progressHandler = self.progressHandler
        let quantizationSlug = quantization
        let task = Task<any LFM2Engine, Error> {
            try await factory(quantizationSlug, progressHandler)
        }
        inFlightLoad = task
        state = .loading

        do {
            let engine = try await task.value
            loadedEngine = engine
            state = .loaded(engine)
            inFlightLoad = nil
            return engine
        } catch {
            let wrapped = TranslationError.modelLoadFailed(error.localizedDescription)
            state = .failed(wrapped)
            inFlightLoad = nil
            throw wrapped
        }
    }

    /// Drives the two-canary warmup against an already-loaded engine.
    ///
    /// Precondition: the loader is in ``LFM2LoaderState/loaded(_:)``.
    /// Calling ``warmup()`` against ``LFM2LoaderState/idle``,
    /// ``LFM2LoaderState/loading``, ``LFM2LoaderState/downloading(_:)``,
    /// or ``LFM2LoaderState/failed(_:)`` throws
    /// ``TranslationError/modelNotReady``. Calling against
    /// ``LFM2LoaderState/ready`` is a no-op (contract **A3**); calling
    /// against ``LFM2LoaderState/warming`` coalesces onto the existing
    /// task.
    ///
    /// Behaviour:
    /// - On the first call from ``LFM2LoaderState/loaded(_:)``, ``state``
    ///   transitions to ``LFM2LoaderState/warming`` and a fresh task is
    ///   spawned that runs the two canaries **sequentially**: EN-to-JA
    ///   first, JA-to-EN second. Order is locked by
    ///   ``LFM2ModelLoaderTests/warmup_afterLoad_runsBothCanariesSequentially``.
    /// - On both-canary success, ``state`` transitions to
    ///   ``LFM2LoaderState/ready``.
    /// - On any canary failure, ``state`` transitions to
    ///   ``LFM2LoaderState/failed(_:)`` carrying
    ///   ``TranslationError/warmupFailed(_:)`` and the error is rethrown.
    ///
    /// - Throws: ``TranslationError/modelNotReady`` if no engine is
    ///   loaded; ``TranslationError/warmupFailed(_:)`` on canary failure.
    func warmup() async throws {
        if case .ready = state {
            return
        }

        if let inFlightWarmup {
            try await inFlightWarmup.value
            return
        }

        guard let engine = loadedEngine else {
            throw TranslationError.modelNotReady
        }

        let task = Task<Void, Error> {
            do {
                try await engine.warmupCanary(direction: .enToJa)
                try await engine.warmupCanary(direction: .jaToEn)
            } catch let error as TranslationError {
                throw error
            } catch {
                throw TranslationError.warmupFailed(error.localizedDescription)
            }
        }
        inFlightWarmup = task
        state = .warming

        do {
            try await task.value
            state = .ready
            inFlightWarmup = nil
        } catch let error as TranslationError {
            state = .failed(error)
            inFlightWarmup = nil
            throw error
        } catch {
            let wrapped = TranslationError.warmupFailed(error.localizedDescription)
            state = .failed(wrapped)
            inFlightWarmup = nil
            throw wrapped
        }
    }

    /// Returns a snapshot of the loader's lifecycle. Cheap; safe to
    /// poll from UI on every render pass.
    func currentState() -> LFM2LoaderState {
        state
    }

    /// Resets the loader to ``LFM2LoaderState/idle``, releasing the
    /// engine reference so the underlying LEAP resources can be
    /// reclaimed.
    ///
    /// Does **not** interrupt an in-flight load or warmup (contract
    /// **A2**): any task spawned by ``loadIfNeeded(quantization:)`` or
    /// ``warmup()`` continues to run, and its eventual success or
    /// failure is recorded back into ``state`` overriding the idle
    /// reset. Callers that want to truly cancel must cancel their own
    /// awaiting task.
    func unload() {
        state = .idle
        loadedEngine = nil
    }
}
