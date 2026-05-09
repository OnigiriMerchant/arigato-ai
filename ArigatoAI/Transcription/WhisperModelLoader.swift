//
//  WhisperModelLoader.swift
//  ArigatoAI
//
//  Created by Jose Castell on 2026/05/10.
//

import Foundation

/// Snapshot of ``WhisperModelLoader``'s lifecycle, returned by
/// ``WhisperModelLoader/currentState()``.
///
/// The states are observed by `AppBootstrapper` (Step 7) and any
/// diagnostic UI that wants to surface load progress without having to
/// `await loadIfNeeded(variant:)` itself.
///
/// Marked `nonisolated` because it is a pure value type. The associated
/// `any WhisperEngine` reference is `Sendable` by protocol conformance, so
/// the enum is safe to ferry across actor boundaries.
///
/// Access level is `internal` because the associated payload of
/// ``loaded(_:)`` is the internal ``WhisperEngine`` protocol; this type
/// cannot be `public` without first promoting `WhisperEngine` to
/// `public`. Both stay internal so the test target keeps `@testable`
/// access and no app boundary is exposed prematurely.
nonisolated enum LoaderState {
    /// No load has been requested, or ``WhisperModelLoader/unload()`` was
    /// just called.
    case idle

    /// A load is in flight. Concurrent ``WhisperModelLoader/loadIfNeeded(variant:)``
    /// callers are coalescing against it.
    case loading

    /// The model is loaded and the wrapped engine is ready for inference.
    case loaded(any WhisperEngine)

    /// The most recent load attempt failed. The next call to
    /// ``WhisperModelLoader/loadIfNeeded(variant:)`` retries.
    case failed(TranscriptionError)
}

/// Owns the lifecycle of the underlying Whisper engine and coalesces
/// concurrent load requests into a single in-flight task.
///
/// The loader is the single point of contact between the rest of the app
/// and the Whisper-backed engine. It is an actor so the underlying
/// engine — which is not `Sendable` in WhisperKit v1.0.0 — can be held
/// safely across async boundaries.
///
/// Only one engine instance exists per loader at a time. Variant choice
/// is recorded by the caller of the first successful load; subsequent
/// callers requesting a different variant receive the already-loaded
/// engine without a reload (see ``loadIfNeeded(variant:)`` for details).
///
/// The actor and its API surface are `internal`. ``loadIfNeeded(variant:)``
/// returns `any WhisperEngine` (an internal protocol) and ``currentState()``
/// returns ``LoaderState`` (also internal), so the actor cannot be
/// promoted to `public` without first promoting both. All consumers
/// (`AppBootstrapper` and the test target via `@testable`) live inside
/// the `ArigatoAI` module, so internal access is sufficient.
actor WhisperModelLoader {
    private var state: LoaderState = .idle
    private var inFlight: Task<any WhisperEngine, Error>?
    private let factory: WhisperEngineFactory

    /// Production initializer. Wires the loader to the real WhisperKit
    /// factory at ``ArgmaxOSSWhisperFactory/make``.
    init() {
        factory = ArgmaxOSSWhisperFactory.make
    }

    /// Test seam. Allows the test target (via `@testable import
    /// ArigatoAI`) to inject a custom factory; production callers must
    /// use ``init()``.
    init(factory: @escaping WhisperEngineFactory) {
        self.factory = factory
    }

    /// Loads the requested ``WhisperModelVariant`` if no engine is already
    /// loaded; coalesces concurrent calls into a single in-flight task.
    ///
    /// Behaviour:
    /// - If the loader is already in ``LoaderState/loaded(_:)``, the
    ///   wrapped engine is returned immediately. **Variant mismatch is
    ///   silently ignored**: callers requesting a different variant after
    ///   one is loaded receive the already-loaded engine. This matches
    ///   the single-engine ownership invariant; phase-4 ships only one
    ///   variant so this is academic, but the contract is documented so
    ///   the future variant-switching story is explicit.
    /// - If a load is already in flight (``LoaderState/loading``), the
    ///   caller awaits the same task. No second load is started.
    /// - Otherwise, a fresh `Task` is started against ``factory`` and
    ///   ``state`` transitions to ``LoaderState/loading``. On success,
    ///   ``state`` becomes ``LoaderState/loaded(_:)`` and the engine is
    ///   returned. On failure, ``state`` becomes ``LoaderState/failed(_:)``
    ///   and the error is rethrown as
    ///   ``TranscriptionError/modelLoadFailed(_:)``. The next call to
    ///   ``loadIfNeeded(variant:)`` retries.
    /// - **Cancellation**: if a caller's outer task is cancelled while it
    ///   awaits the in-flight load, only that caller's await throws
    ///   `CancellationError`. The shared in-flight task continues so
    ///   other coalescing callers still receive their result.
    ///
    /// - Parameter variant: The variant to load. Defaulted to
    ///   ``WhisperModelVariant/default``.
    /// - Returns: The loaded ``WhisperEngine`` instance.
    /// - Throws: ``TranscriptionError/modelLoadFailed(_:)`` wrapping any
    ///   underlying factory error.
    func loadIfNeeded(
        variant: WhisperModelVariant = .default
    ) async throws -> any WhisperEngine {
        if case let .loaded(engine) = state {
            return engine
        }

        if let inFlight {
            return try await inFlight.value
        }

        let task = Task<any WhisperEngine, Error> { [factory] in
            try await factory(variant)
        }
        inFlight = task
        state = .loading

        do {
            let engine = try await task.value
            state = .loaded(engine)
            inFlight = nil
            return engine
        } catch {
            let wrapped = TranscriptionError.modelLoadFailed(error.localizedDescription)
            state = .failed(wrapped)
            inFlight = nil
            throw wrapped
        }
    }

    /// Returns a snapshot of the loader's lifecycle. Cheap; safe to poll
    /// from UI on every render pass.
    func currentState() -> LoaderState {
        state
    }

    /// Resets the loader to ``LoaderState/idle``, releasing the engine
    /// reference so the underlying CoreML resources can be reclaimed.
    ///
    /// Does **not** interrupt an in-flight load: any task spawned by
    /// ``loadIfNeeded(variant:)`` continues to run, and its eventual
    /// success or failure is recorded back into ``state`` overriding the
    /// idle reset. Callers that want to truly cancel an in-flight load
    /// should cancel their own awaiting task instead.
    func unload() {
        state = .idle
    }
}
