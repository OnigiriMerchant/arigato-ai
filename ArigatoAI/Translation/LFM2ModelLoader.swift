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
/// **Cache strategy.** ``LeapSDK.Leap/load(model:quantization:options:downloadProgressHandler:)``
/// is called with `options: nil`. Phase 5 Decision 4 ("in-memory only,
/// no persistent disk cache") cannot be honored literally in LEAP iOS
/// SDK v0.9.4 because ``LeapSDK.LiquidCacheOptions`` is disk-only and
/// has no in-memory variant. Passing `nil` disables the KV cache
/// entirely, which is acceptable for LFM2's single-turn translation
/// semantics: each ``LeapSDK.Conversation`` is throwaway per direction,
/// so KV-cache hits across calls are inherently near zero. The D4
/// strategic re-walk happens before Group C; Group B is unaffected.
public nonisolated enum LFM2ClientFactory {
    /// The production ``LFM2EngineFactory``. Constructs a real
    /// ``LeapSDK.ModelRunner`` via the GGUF manifest path
    /// (``LeapSDK.Leap/load(model:quantization:options:downloadProgressHandler:)``)
    /// and wraps it in ``LFM2EngineAdapter``. The model identifier is
    /// pinned to `"lfm2-350m-enjp-mt"` per Phase 5 Decision 1.
    public static let make: LFM2EngineFactory = { quantization, progressHandler in
        let runner = try await Leap.load(
            model: "lfm2-350m-enjp-mt",
            quantization: quantization,
            options: nil,
            downloadProgressHandler: { progress, _ in
                progressHandler?(progress)
            }
        )
        return LFM2EngineAdapter(modelRunner: runner)
    }
}
