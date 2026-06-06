//
//  LFM2ModelLoader.swift
//  ArigatoAI
//
//  Created by Jose Castell on 2026/05/12.
//

import Foundation
import LeapModelDownloader

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
    /// fraction in the closed interval `[0.0, 1.0]`.
    ///
    /// **Currently unreachable (leap-sdk v0.10.9 migration).** The LFM2
    /// model now ships bundled in the app as a GGUF resource, so there is
    /// no download phase and nothing ever transitions the loader into this
    /// state. The case is retained — rather than deleted — so the
    /// determinate-progress UI surface (onboarding copy, UI #16) and any
    /// diagnostic observer can pattern-match it without a source break if
    /// portal downloads are reintroduced (V3 trigger "LFM2 portal download
    /// path"). Until then it is dead but harmless: an unreachable arm in
    /// every `switch` over ``LFM2LoaderState``.
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
/// `ModelRunner` behind a protocol that ``LFM2ModelLoader`` and
/// the test target can both hold.
///
/// `LFM2Engine` is the LFM2 analogue of Phase 4's ``WhisperClient`` /
/// ``WhisperEngine`` pattern: the production wrapper holds the SDK
/// instance and is marked `@unchecked Sendable`, while
/// ``LFM2ModelLoader`` (an actor) serialises every method call against
/// the wrapper. The protocol exposes only the surface the loader needs,
/// which lets tests inject a fake without linking `LeapModelDownloader`.
///
/// **Why a sync `Sendable` protocol over a non-`Sendable` SDK class?**
/// `ModelRunner` is a SKIE/Kotlin-Native-bridged protocol with no
/// `Sendable` inheritance and `Conversation` is a plain class — neither is
/// safe to ferry across actor boundaries directly. Wrapping both behind
/// one actor-owned `@unchecked Sendable` adapter is the established
/// Phase 4 mitigation; the same shape is reused here so the test target
/// keeps its no-LeapSDK posture.
public protocol LFM2Engine: Sendable {
    /// Runs a single short dummy inference using the supplied translation
    /// direction's system prompt, so subsequent translation calls do not
    /// pay cold-start cost.
    ///
    /// The canary message is intentionally short ("Hello." for EN-to-JA;
    /// "こんにちは。" for JA-to-EN) so the inference completes quickly.
    /// The implementation creates a fresh `Conversation` using
    /// `ModelRunner.createConversation(systemPrompt:)` and drains the
    /// response stream until it sees the `.complete` response.
    ///
    /// - Parameter direction: The translation direction whose system
    ///   prompt drives the canary. Both directions are warmed up
    ///   sequentially by ``LFM2ModelLoader/warmup()``.
    /// - Throws: ``TranslationError/warmupFailed(_:)`` wrapping any
    ///   underlying SDK error.
    nonisolated func warmupCanary(direction: TranslationDirection) async throws

    /// Streams an LFM2 translation of `userText` in the requested
    /// `direction`.
    ///
    /// **Scheduling assumption.** Conformers serialize translation
    /// calls per instance: concurrent calls to this method on the same
    /// engine instance result in undefined ordering. The actor owning
    /// the engine (``LFM2ModelLoader`` for warmup; the Group C
    /// ``TranslationActor`` for production translation) is responsible
    /// for ensuring at most one call is in-flight at a time. The
    /// production adapter (``LFM2EngineAdapter``) constructs a fresh
    /// `Conversation` per call so cross-call mutable state from the SDK is
    /// avoided.
    ///
    /// **Violation behaviour.** If the owning actor violates the one-call
    /// invariant and drives two `translate(...)` streams against the same
    /// adapter concurrently, the leap-sdk v0.10.9 `ModelRunner` is not
    /// `Sendable` and its conversations are independent objects: the two
    /// streams interleave token generation on the SDK's internal executor
    /// with undefined output ordering. No data race is introduced (each
    /// `Conversation` is constructed per call), but neither stream's token
    /// order is guaranteed to be coherent. The serialisation contract is
    /// what keeps output coherent.
    ///
    /// **Cancellation.** The returned ``AsyncThrowingStream`` observes
    /// cooperative task cancellation per Swift Concurrency semantics. In
    /// leap-sdk v0.10.9 cancelling the spawned task both breaks the
    /// `for try await` loop and drops the only reference to the SDK
    /// generation, which the SDK surfaces as an `.interrupted` terminal —
    /// the adapter finishes the stream cleanly without yielding a partial
    /// `.complete`. At the protocol level the contract is "respond to
    /// `Task.cancel()` by finishing the stream — natural completion or
    /// cancellation, the stream finishes either way".
    ///
    /// - Parameters:
    ///   - userText: The source sentence to translate. Should be a
    ///     single sentence; ``TranslationActor`` is responsible for
    ///     sentence boundary detection upstream.
    ///   - direction: The translation direction whose system prompt
    ///     and generation parameters drive the inference.
    /// - Returns: An ``AsyncThrowingStream`` of
    ///   ``TranslationEngineEvent`` values. The stream yields zero or
    ///   more ``TranslationEngineEvent/chunk(_:)`` events followed by
    ///   exactly one ``TranslationEngineEvent/complete`` event and
    ///   then finishes. On error — including the SDK surfacing a
    ///   `MessageResponseError` — the stream finishes by throwing.
    nonisolated func translate(userText: String, direction: TranslationDirection) -> AsyncThrowingStream<TranslationEngineEvent, any Error>
}

/// Production adapter wrapping a real `ModelRunner` instance.
///
/// Marked `@unchecked Sendable` because `ModelRunner` is not `Sendable`
/// in leap-sdk v0.10.9 — it is a SKIE/Kotlin-Native-bridged protocol with
/// no Swift `Sendable` conformance. **Do not re-verify this against the
/// `.swiftinterface`:** the SKIE-generated Swift convenience overloads
/// (`createConversation(systemPrompt:)`, the `generateResponse(...)`
/// overloads, the `GenerationOptions().with(...)` builders) are emitted
/// *outside* the `.swiftinterface`, so grepping the interface gives false
/// negatives. The reference build `arigato-ai-p2` compiles clean against
/// this exact revision (leap-sdk 0.10.9, rev a83ca1e); every call shape
/// below is proven by that compilation.
///
/// The unchecked annotation is sound only because ``LFM2ModelLoader`` (an
/// actor) is the sole owner of the adapter and serialises every method
/// call against it; do not share an `LFM2EngineAdapter` reference across
/// other actors directly.
///
/// **Scheduling assumption.** The adapter assumes its owning actor drives
/// at most one inference (warmup canary or `translate(...)` stream) at a
/// time. It constructs a fresh `Conversation` per call so no cross-call
/// mutable SDK state exists, but it does not itself serialise concurrent
/// callers — that is the owning actor's job. Violating this assumption
/// interleaves two SDK generations with undefined token ordering (see the
/// ``LFM2Engine/translate(userText:direction:)`` doc).
///
/// **Cancellation behaviour (v0.10.9).** Cancelling the task spawned by
/// `translate(...)` drops the SDK generation reference; the SDK reports
/// the abandoned generation as `.interrupted`, and the adapter finishes
/// the stream without a trailing `.complete`. No partial result is
/// fabricated.
///
/// Conforms to ``LFM2Engine`` so consumers downstream of the loader can
/// drive warmup against a real LEAP-backed runner. The adapter performs
/// the conversation-construction step and drains the response stream,
/// translating any underlying SDK error into
/// ``TranslationError/warmupFailed(_:)`` (warmup) or a thrown stream
/// finish (translation).
final nonisolated class LFM2EngineAdapter: LFM2Engine, @unchecked Sendable {
    private let modelRunner: any ModelRunner

    /// Creates the adapter from an already-constructed `ModelRunner`
    /// instance. Construction is delegated to ``LFM2ClientFactory/make`` so
    /// the adapter never needs to know the model identifier directly.
    init(modelRunner: any ModelRunner) {
        self.modelRunner = modelRunner
    }

    /// Drives one short dummy inference against the supplied direction's
    /// system prompt and returns when the SDK emits its `.complete`
    /// response, mapping any error onto ``TranslationError/warmupFailed(_:)``.
    ///
    /// Mirrors the leap-sdk v0.10.9 conversation/generation call shapes
    /// proven by the `arigato-ai-p2` reference build: a `ChatMessage` with
    /// a single `.text(_:)` content, the no-options
    /// `generateResponse(message:generationOptions:)` overload, and
    /// `onEnum(of:)` case matching over the SKIE-bridged `MessageResponse`
    /// sealed type.
    func warmupCanary(direction: TranslationDirection) async throws {
        let conversation = modelRunner.createConversation(systemPrompt: direction.systemPrompt)
        let canaryText: String
        switch direction {
        case .enToJa:
            canaryText = "Hello."
        case .jaToEn:
            canaryText = "こんにちは。"
        }
        let message = ChatMessage(role: .user, content: .text(canaryText))
        let stream = conversation.generateResponse(message: message, generationOptions: nil)

        for await response in stream {
            switch onEnum(of: response) {
            case .complete:
                return
            case let .error(e):
                // `.error` is the SDK's failure channel: the v0.10.9
                // generation stream is non-throwing, so a warmup failure
                // surfaces here, never via a thrown error. Without this arm
                // a failed canary falls through to `default`, the loop ends
                // without `.complete`, and warmup falsely reports `.ready`
                // on a model that cannot generate — the mirror of the
                // translate-path `.error` fix below.
                throw TranslationError.warmupFailed(String(describing: e))
            default:
                continue
            }
        }
    }

    /// Production translation surface: creates a fresh `Conversation` per
    /// call, drives `generateResponse(userTextMessage:generationOptions:)`
    /// with ``TranslationGenerationParameters/recommended`` values, and
    /// maps each `MessageResponse` onto the ``TranslationEngineEvent`` seam.
    ///
    /// Mapping rules (leap-sdk v0.10.9):
    /// - `.chunk` (payload `MessageResponseChunk`) →
    ///   ``TranslationEngineEvent/chunk(_:)`` using the payload's
    ///   `text: String`.
    /// - `.complete` → ``TranslationEngineEvent/complete``
    /// - `.error` (payload `MessageResponseError`, **new in v0.10.9**) →
    ///   the stream finishes by throwing
    ///   ``TranslationError/generationFailed(_:)``. This is the one
    ///   behavioural divergence from the `arigato-ai-p2` reference, which
    ///   drops `.error`; here a generation error is surfaced as a stream
    ///   failure so callers do not silently receive a truncated
    ///   translation.
    /// - `.reasoningChunk`, `.functionCalls` (plural), `.audioSample` are
    ///   dropped per the seam's documented scope.
    ///
    /// Case-match uses `onEnum(of:)` because `MessageResponse` is a
    /// SKIE-bridged Kotlin sealed class exposed as a Swift protocol — the
    /// case patterns live on the SKIE-generated `__Sealed` enum, surfaced
    /// via the `onEnum(of:)` free function. **Do not re-verify the case
    /// names against the `.swiftinterface`:** the SKIE overloads are
    /// generated outside it (see the type-level note); these shapes are
    /// proven by the `arigato-ai-p2` compilation against rev a83ca1e.
    ///
    /// The generation options use the v0.10.9 builder form
    /// `GenerationOptions().with(temperature:)...` — the zero-arg
    /// initialiser plus chained `.with(...)` builders — because the
    /// value-init taking sampling params was removed after v0.9.4.
    ///
    /// Cancellation is cooperative: the continuation's `onTermination`
    /// closure cancels the spawned task, which both unblocks the
    /// `for try await` loop and drops the SDK generation reference (the
    /// SDK reports `.interrupted`; the stream finishes without a trailing
    /// `.complete`).
    func translate(userText: String, direction: TranslationDirection) -> AsyncThrowingStream<TranslationEngineEvent, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task { [modelRunner] in
                let conversation = modelRunner.createConversation(systemPrompt: direction.systemPrompt)
                let recommended = TranslationGenerationParameters.recommended
                // leap-sdk v0.10.9 exposes only the zero-arg
                // `GenerationOptions()` + `.with(...)` builders on the
                // native type; the v0.9.4 value-init is gone. Proven by
                // the arigato-ai-p2 build (rev a83ca1e).
                let options = GenerationOptions()
                    .with(temperature: Float(recommended.temperature))
                    .with(topP: Float(recommended.topP))
                    .with(minP: Float(recommended.minP))
                    .with(repetitionPenalty: Float(recommended.repetitionPenalty))
                // The v0.10.9 `generateResponse(...)` stream is
                // non-throwing; errors arrive via the `.error` case below,
                // not as thrown errors, so no `do/catch` is needed here.
                let stream = conversation.generateResponse(
                    userTextMessage: userText,
                    generationOptions: options
                )
                for await response in stream {
                    if Task.isCancelled { break }
                    switch onEnum(of: response) {
                    case let .chunk(chunk):
                        continuation.yield(.chunk(chunk.text))
                    case .complete:
                        continuation.yield(.complete)
                    case let .error(e):
                        // `.error` is new in v0.10.9. Surface it as a
                        // stream failure rather than silently dropping
                        // a truncated translation.
                        continuation.finish(
                            throwing: TranslationError.generationFailed(String(describing: e))
                        )
                        return
                    case .reasoningChunk, .functionCalls, .audioSample:
                        // Dropped per seam scope.
                        continue
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
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
/// linking `LeapModelDownloader`.
///
/// **No progress channel (leap-sdk v0.10.9 migration).** The LFM2 model is
/// bundled in the app as a GGUF resource, so the load path has no download
/// phase and no progress to report. The pre-migration `progressHandler`
/// parameter has been removed from this typealias; reintroducing portal
/// downloads (V3 trigger "LFM2 portal download path") would add it back
/// along with the ``LFM2LoaderState/downloading(_:)`` plumbing.
public typealias LFM2EngineFactory = @Sendable (
    _ quantization: String
) async throws -> any LFM2Engine

/// Production factory wiring for the LEAP-backed LFM2 engine.
///
/// Kept as a namespace (`enum` with a single static let) rather than a
/// free function so the production factory and any future variants live
/// next to each other in the type system. Mirrors Phase 4's
/// ``WhisperClientFactory`` shape.
///
/// **Cache strategy** (Phase 5 Decision 4, revised 2026-05-15 after
/// xcframework inspection — see PHASE_5_HANDOFF.md commit `842c156`;
/// updated 2026-06-06 for the leap-sdk v0.10.9 migration):
/// `Leap.shared.load(url:options:generationTimeParameters:autoDetectCompanionFiles:)`
/// is called against the bundled GGUF URL with a
/// `LiquidInferenceEngineOptions` whose `LiquidCacheOptions` is rooted
/// under iOS's user Caches directory (``LFM2CachePathResolver/resolve()``)
/// via the `LiquidCacheOptions.enabled(path:)` factory. The
/// originally-locked "in-memory only" framing was impossible in v0.9.4 and
/// remains impossible in v0.10.9: `LiquidCacheOptions` exposes only
/// `.enabled(path:)` (no `.inMemory` case). Privacy stance is preserved at
/// the architecture level because iOS's Caches directory is NOT
/// iCloud-backed and is OS-managed (auto-purged under storage pressure).
/// Performance > privacy on-device per revised D4 reasoning: capture any
/// prompt-cache speedup the SDK delivers; passing `cacheOptions: nil` is
/// one-line trivial if Phase 6 diagnostics show the cache is irrelevant.
/// V3 entry "LFM2 prompt cache effectiveness benchmark" tracks that
/// revisit.
///
/// **Sampling params stay per-call.** Temperature / topP / minP /
/// repetition-penalty are NOT moved to load-time
/// `generationTimeParameters` — they are applied per call via
/// `GenerationOptions().with(...)` in
/// ``LFM2EngineAdapter/translate(userText:direction:)``. The per-call path
/// is proven by the `arigato-ai-p2` build.
///
/// **What happens if cache path resolution throws.**
/// ``LFM2CachePathResolver/resolve()`` throws
/// ``TranslationError/cachePathResolutionFailed(_:)`` only when
/// `FileManager.urls(for: .cachesDirectory, in: .userDomainMask)` returns
/// an empty array, which the sandbox guarantees never happens on real iOS.
/// If it ever does, the factory's `try` propagates the error to the
/// loader, which wraps it in ``TranslationError/modelLoadFailed(_:)`` per
/// its standard error path.
public nonisolated enum LFM2ClientFactory {
    /// The production ``LFM2EngineFactory``. Resolves the bundled GGUF
    /// resource, constructs a real `ModelRunner` via
    /// `Leap.shared.load(url:options:generationTimeParameters:autoDetectCompanionFiles:)`,
    /// supplies a `LiquidCacheOptions` rooted under iOS's user Caches
    /// directory via `LiquidCacheOptions.enabled(path:)` (see the
    /// type-level "Cache strategy" doc), and wraps the resulting runner in
    /// ``LFM2EngineAdapter``.
    ///
    /// **Bundled GGUF, not a portal download.** The model file
    /// `LFM2-350M-ENJP-MT-Q5_K_M.gguf` is shipped in `Bundle.main`, so the
    /// URL-based `Leap.shared.load(url:)` entrypoint is used — there is no
    /// download phase. `autoDetectCompanionFiles: false` because the GGUF
    /// is self-contained (no sidecar projector/tokenizer files). The
    /// `quantization` slug is unused on this code path (the GGUF filename
    /// encodes `Q5_K_M`) and is documented as a no-op until the V3 trigger
    /// "LFM2 quant flexibility" lands.
    ///
    /// The `Leap.shared.load(...)` call shape, the
    /// `LiquidInferenceEngineOptions(bundlePath:...)` value-init, and the
    /// `LiquidCacheOptions.enabled(path:)` factory are all proven by the
    /// `arigato-ai-p2` build against leap-sdk 0.10.9 rev a83ca1e — they are
    /// NOT re-verified against the `.swiftinterface`, which omits the
    /// SKIE-generated overloads.
    public static let make: LFM2EngineFactory = { _ in
        let cachePath = try LFM2CachePathResolver.resolve()
        let cacheOptions = LiquidCacheOptions.enabled(path: cachePath)
        guard let ggufURL = Bundle.main.url(
            forResource: "LFM2-350M-ENJP-MT-Q5_K_M",
            withExtension: "gguf"
        ) else {
            throw TranslationError.modelLoadFailed(
                "Bundled GGUF resource LFM2-350M-ENJP-MT-Q5_K_M.gguf not found in Bundle.main"
            )
        }
        let options = LiquidInferenceEngineOptions(
            bundlePath: ggufURL.path,
            cacheOptions: cacheOptions,
            cpuThreads: nil,
            contextSize: nil,
            nGpuLayers: nil,
            mmProjPath: nil,
            audioDecoderPath: nil,
            chatTemplate: nil,
            audioTokenizerPath: nil,
            audioDecoderUseGpu: false,
            useMmap: nil,
            extras: nil
        )
        let runner = try await Leap.shared.load(
            url: ggufURL,
            options: options,
            generationTimeParameters: nil,
            autoDetectCompanionFiles: false
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
/// underlying engine — which remains not `Sendable` in leap-sdk v0.10.9
/// (`ModelRunner` is a SKIE/Kotlin-Native-bridged protocol with no Swift
/// `Sendable` conformance) — can be held safely across async boundaries.
///
/// Mirrors Phase 4's ``WhisperModelLoader`` shape closely: a single
/// loading state, a single in-flight task, and a single `factory`
/// dependency injected for testability. The LFM2 path adds the two-canary
/// warmup step.
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

    /// Designated initializer.
    ///
    /// - Parameter factory: The factory closure that resolves a
    ///   quantization slug into an ``LFM2Engine``. Defaulted to the
    ///   production wiring at ``LFM2ClientFactory/make``. Tests inject a
    ///   custom closure that returns a fake.
    init(
        factory: @escaping LFM2EngineFactory = LFM2ClientFactory.make
    ) {
        self.factory = factory
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
    ///   Defaulted to `"Q5_K_M"` per Phase 5 Decision 1. Unused on the
    ///   bundled-GGUF production path (the filename encodes the quant).
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
        let quantizationSlug = quantization
        let task = Task<any LFM2Engine, Error> {
            try await factory(quantizationSlug)
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
