//
//  AppBootstrapper.swift
//  ArigatoAI
//
//  Created by Jose Castell on 2026/05/10.
//

import Foundation
import SwiftUI

/// Owns app-launch warmup work and surfaces lifecycle state to SwiftUI.
///
/// Constructed once in ``ArigatoAIApp/init()``. Fires a detached task to
/// pre-warm the Whisper model in parallel with the mic-permission prompt
/// so the user can hit record without waiting on a cold start.
///
/// ## Isolation
/// Marked `@MainActor` because every property the UI binds to lives on the
/// main actor and is mutated from SwiftUI's render context. The pre-warm
/// work itself is dispatched off the main actor via `Task.detached`; only
/// the small "store the new state" hop runs on the main actor.
///
/// ## Access level
/// `internal` because ``loaderState`` carries ``LoaderState`` (an internal
/// enum whose payload is the internal ``WhisperEngine`` protocol). The
/// bootstrapper cannot be `public` without first promoting both. The
/// SwiftUI views and the test target (via `@testable import ArigatoAI`)
/// live inside the `ArigatoAI` module, so internal access is sufficient.
@MainActor
@Observable
final class AppBootstrapper {
    /// Snapshot of the Whisper loader's state, mirrored from the actor.
    /// Updated each time pre-warm progresses. Drives the record-button
    /// gating and any "model failed" UI.
    private(set) var loaderState: LoaderState = .idle

    /// Construction error from the SwiftData model container, if any.
    /// `nil` means the persistence stack came up cleanly. In production,
    /// the App initializer seeds this through ``init(loader:containerError:)``
    /// because the `_bootstrapper = State(wrappedValue:)` pattern requires
    /// the value to be set at construction time. ``recordContainerFailure(_:)``
    /// remains available for callers that need to record a failure after
    /// the bootstrapper exists (e.g., test setups).
    private(set) var containerError: Error?

    /// Shared loader. Held here so view models constructed during the
    /// app's lifetime can inject it without rebuilding the actor.
    let loader: WhisperModelLoader

    /// Designated initializer.
    ///
    /// - Parameters:
    ///   - loader: The loader to mirror state from. Defaulted to a fresh
    ///     production-wired ``WhisperModelLoader``. Tests inject a fake.
    ///   - containerError: Optional pre-seeded container error. Defaults
    ///     to `nil`. Production code uses ``recordContainerFailure(_:)``
    ///     instead; the parameter exists for tests that want to assert
    ///     the error-rendering branch in isolation.
    init(
        loader: WhisperModelLoader = WhisperModelLoader(),
        containerError: Error? = nil
    ) {
        self.loader = loader
        self.containerError = containerError
    }

    /// Records a SwiftData container failure after the bootstrapper exists.
    /// Production wires through ``init(loader:containerError:)`` instead;
    /// this method exists for tests and for callers that need to surface
    /// a late failure (e.g., a re-bootstrap path that doesn't exist today).
    /// Idempotent — repeated calls overwrite the stored error with the
    /// most recent value.
    ///
    /// - Parameter error: The error thrown by `ModelContainer.init`.
    func recordContainerFailure(_ error: Error) {
        containerError = error
    }

    /// Kicks off Whisper pre-warm on a detached task. Safe to call
    /// multiple times — ``WhisperModelLoader`` coalesces concurrent loads
    /// into a single in-flight request.
    ///
    /// State transitions, in order:
    /// 1. ``LoaderState/loading`` is published before awaiting the loader,
    ///    so the UI can disable the record control immediately.
    /// 2. On success, ``LoaderState/loaded(_:)`` carrying the engine.
    /// 3. On failure, ``LoaderState/failed(_:)`` carrying the
    ///    ``TranscriptionError`` raised by the loader.
    ///
    /// The detached task uses `[weak self]` so a torn-down bootstrapper
    /// does not keep the loader alive past app lifetime.
    ///
    /// - Parameter variant: The model variant to request. Defaulted to
    ///   ``WhisperModelVariant/default``.
    func startPrewarm(variant: WhisperModelVariant = .default) {
        let loader = self.loader
        Task.detached(priority: .userInitiated) { [weak self] in
            await self?.setLoaderState(.loading)

            do {
                let engine = try await loader.loadIfNeeded(variant: variant)
                await self?.setLoaderState(.loaded(engine))
            } catch let error as TranscriptionError {
                await self?.setLoaderState(.failed(error))
            } catch {
                // The loader's contract is to wrap any underlying error in
                // ``TranscriptionError/modelLoadFailed(_:)`` before
                // rethrowing, so this branch is defensive. We still
                // surface the failure with the stringified detail rather
                // than dropping it on the floor.
                let wrapped = TranscriptionError.modelLoadFailed(error.localizedDescription)
                await self?.setLoaderState(.failed(wrapped))
            }
        }
    }

    /// MainActor-isolated setter used by the detached pre-warm task to
    /// mirror loader state back onto the UI thread. Extracted from
    /// ``startPrewarm(variant:)`` so the detached task body has no nested
    /// closures capturing `self?`, which would trip Swift 6 strict
    /// concurrency's "captured var in concurrently-executing code" rule.
    private func setLoaderState(_ newState: LoaderState) {
        loaderState = newState
    }
}
