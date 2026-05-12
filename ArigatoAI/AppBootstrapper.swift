//
//  AppBootstrapper.swift
//  ArigatoAI
//
//  Created by Jose Castell on 2026/05/10.
//

import Foundation
import os
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
/// enum whose payload is the internal ``WhisperClient`` protocol). The
/// bootstrapper cannot be `public` without first promoting both. The
/// SwiftUI views and the test target (via `@testable import ArigatoAI`)
/// live inside the `ArigatoAI` module, so internal access is sufficient.
///
/// ## Construction-order assumption (Concurrency design discipline)
/// Three pieces of shared infrastructure are built in a fixed order during
/// `init`:
///
/// 1. ``loader`` — the ``WhisperModelLoader`` is constructed (or
///    injected) first.
/// 2. ``transcriber`` — the ``TranscriptionActor`` is constructed
///    second, depending on ``loader``.
/// 3. ``router`` — the ``LanguageRouter`` is constructed third,
///    depending on ``transcriber``.
///
/// The bootstrapper's `init` runs synchronously on the MainActor.
/// ``TranscriptionActor/init(loader:windowSeconds:hopSeconds:clock:)`` is
/// `nonisolated` and synchronous;
/// ``LanguageRouter/init(transcriber:confirmationsRequired:)`` is
/// `@MainActor`-isolated and synchronous; both are callable from this
/// `init` without `await`. Re-ordering the three steps above would break
/// the dependency chain at compile time (each step's input is the
/// previous step's output), so no runtime violation test is required —
/// the type system enforces the order.
@MainActor
@Observable
final class AppBootstrapper {
    /// Snapshot of the Whisper loader's state, mirrored from the actor.
    /// Updated each time pre-warm progresses. Drives the record-button
    /// gating and any "model failed" UI.
    private(set) var loaderState: LoaderState = .idle

    /// Snapshot of the LFM2 loader's state, mirrored from the actor.
    /// Drives translation-dependent UI gating and the LFM2 failure
    /// branch of ``StartupErrorView`` selection. Distinct from
    /// ``loaderState`` so the two pipelines' diagnostics evolve
    /// independently.
    private(set) var lfm2LoaderState: LFM2LoaderState = .idle

    /// Most recent LFM2 download-progress fraction in `[0.0, 1.0]`, or
    /// `nil` if no progress has been reported yet (either the model is
    /// already cached on disk or download has not begun). UI can render
    /// a determinate progress indicator only when this is non-nil.
    private(set) var lfm2DownloadProgress: Double?

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

    /// Shared LFM2 loader. Held here so the translation actor (Group C)
    /// and any other consumer can coalesce loads against a single
    /// in-flight task.
    let lfm2Loader: LFM2ModelLoader

    /// Shared ``TranscriptionActor`` for the app's lifetime.
    ///
    /// Constructed once in ``init(loader:containerError:transcriberFactory:routerFactory:)``
    /// from the same ``loader`` field above so the actor and any other
    /// loader caller (e.g. ``startPrewarm(variant:)``) coalesce against a
    /// single in-flight model load. The actor survives across recording
    /// sessions; one ``TranscriptionActor/windowStream(frames:)`` call
    /// per session is initiated through ``router``.
    ///
    /// **Warmup goes through ``loader`` (and ``startPrewarm(variant:)``),
    /// not through this property.** Calling
    /// ``TranscriptionActor/warmup()`` directly would still work but
    /// duplicates the bootstrapper's lifecycle responsibility; production
    /// code should drive warmup via ``startPrewarm(variant:)``.
    let transcriber: TranscriptionActor

    /// Shared ``LanguageRouter`` for the app's lifetime — the
    /// `@MainActor @Observable` source of truth for
    /// ``LanguageRouter/routedHistory`` and
    /// ``LanguageRouter/currentLanguage``. UI binds directly here.
    ///
    /// View models that need to drain pipeline output call
    /// ``LanguageRouter/transcribe(frames:)`` on this property; the
    /// router internally uses ``transcriber`` so a single shared actor
    /// owns one window-stream session at a time.
    let router: LanguageRouter

    /// Designated initializer.
    ///
    /// - Parameters:
    ///   - loader: The Whisper loader to mirror state from. Defaulted to
    ///     a fresh production-wired ``WhisperModelLoader``. Tests inject
    ///     a fake.
    ///   - lfm2Loader: The LFM2 loader to mirror state from. Defaulted
    ///     to `nil`; when `nil` the initializer constructs a fresh
    ///     ``LFM2ModelLoader`` whose progress handler is wired through
    ///     a private trampoline to ``setLFM2Progress(_:)`` on the main
    ///     actor. Tests inject a custom loader so the factory closure
    ///     can be controlled.
    ///   - lfm2Factory: Optional override for the LFM2 engine factory
    ///     used when `lfm2Loader == nil`. Defaults to `nil`, in which
    ///     case production wiring ``LFM2ClientFactory/make`` is used.
    ///     Tests pass a factory that fires progress synthetically and
    ///     returns a fake engine, so V7 can exercise the production
    ///     trampoline path without hitting the LEAP SDK.
    ///   - containerError: Optional pre-seeded container error. Defaults
    ///     to `nil`. Production code uses ``recordContainerFailure(_:)``
    ///     instead; the parameter exists for tests that want to assert
    ///     the error-rendering branch in isolation.
    ///   - transcriberFactory: Test-only override for the
    ///     ``TranscriptionActor`` construction step. Defaults to `nil`,
    ///     in which case production wiring
    ///     `TranscriptionActor(loader: loader)` is used. When supplied,
    ///     the closure is invoked synchronously inside `init` with the
    ///     resolved ``loader``.
    ///   - routerFactory: Test-only override for the ``LanguageRouter``
    ///     construction step. Defaults to `nil`, in which case
    ///     production wiring `LanguageRouter(transcriber: transcriber)`
    ///     is used. When supplied, the closure is invoked synchronously
    ///     inside `init` with the resolved ``transcriber``.
    init(
        loader: WhisperModelLoader = WhisperModelLoader(),
        lfm2Loader: LFM2ModelLoader? = nil,
        lfm2Factory: LFM2EngineFactory? = nil,
        containerError: Error? = nil,
        transcriberFactory: ((WhisperModelLoader) -> TranscriptionActor)? = nil,
        routerFactory: (@MainActor (TranscriptionActor) -> LanguageRouter)? = nil
    ) {
        self.loader = loader
        self.containerError = containerError
        let resolvedTranscriber: TranscriptionActor
        if let transcriberFactory {
            resolvedTranscriber = transcriberFactory(loader)
        } else {
            resolvedTranscriber = TranscriptionActor(loader: loader)
        }
        transcriber = resolvedTranscriber
        if let routerFactory {
            router = routerFactory(resolvedTranscriber)
        } else {
            router = LanguageRouter(transcriber: resolvedTranscriber)
        }
        if let lfm2Loader {
            self.lfm2Loader = lfm2Loader
        } else {
            // Production wiring. We cannot capture `self` directly in
            // the progress handler closure here because `self` is not
            // yet fully initialised at this assignment line — Swift
            // forbids `self` references before all stored properties
            // are set.
            //
            // The workaround is a "trampoline" indirection: a small
            // box holds an optional handler that we mutate after init
            // completes. The closure passed to the loader captures
            // only the box (no `self`), and the box's stored handler
            // is rebound to a self-capturing closure by
            // ``installLFM2ProgressHandler(into:)`` once init returns.
            let trampoline = ProgressTrampoline()
            let progressForwarder: @Sendable (Double) -> Void = { progress in
                trampoline.forward(progress)
            }
            if let lfm2Factory {
                self.lfm2Loader = LFM2ModelLoader(
                    factory: lfm2Factory,
                    progressHandler: progressForwarder
                )
            } else {
                self.lfm2Loader = LFM2ModelLoader(progressHandler: progressForwarder)
            }
            installLFM2ProgressHandler(into: trampoline)
        }
    }

    /// Late-binds the LFM2 progress handler against `self` via the
    /// supplied trampoline so the SDK's callback hops to the main
    /// actor before mutating ``lfm2DownloadProgress``. Called once
    /// from ``init(...)`` after all stored properties are set.
    ///
    /// This is a workaround for Swift's stored-property initialisation
    /// ordering: a `[weak self]` capture inside the closure literal at
    /// the lfm2Loader assignment line would not compile because
    /// `self` is not yet fully initialised. The trampoline lets the
    /// loader's progress handler stay stable while the destination
    /// `self`-bound closure is installed post-init.
    private func installLFM2ProgressHandler(into trampoline: ProgressTrampoline) {
        trampoline.bind { [weak self] progress in
            guard let self else { return }
            Task { @MainActor in
                self.setLFM2Progress(progress)
            }
        }
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
    /// 1. ``LoaderState/loading`` is published before awaiting the
    ///    Whisper loader, so the UI can disable the record control
    ///    immediately.
    /// 2. On Whisper success, ``LoaderState/loaded(_:)`` carrying the
    ///    engine. The detached task then proceeds to LFM2 load and
    ///    warmup sequentially.
    /// 3. On Whisper failure, ``LoaderState/failed(_:)`` carrying the
    ///    ``TranscriptionError`` raised by the loader. **LFM2 is not
    ///    attempted**: the detached task returns without touching
    ///    ``lfm2LoaderState``, which stays at ``LFM2LoaderState/idle``.
    /// 4. After Whisper success, LFM2 ``LFM2LoaderState/loading`` is
    ///    published; on success ``LFM2LoaderState/loaded(_:)``; then
    ///    warmup transitions through ``LFM2LoaderState/warming`` to
    ///    ``LFM2LoaderState/ready``.
    /// 5. On LFM2 load or warmup failure,
    ///    ``LFM2LoaderState/failed(_:)`` carrying the
    ///    ``TranslationError`` raised by the loader. Whisper state is
    ///    unaffected.
    ///
    /// The detached task uses `[weak self]` so a torn-down bootstrapper
    /// does not keep the loaders alive past app lifetime.
    ///
    /// **Pipeline ordering (S6).** Whisper completes before LFM2 starts.
    /// This is the strict reading of the locked plan: parallel load
    /// would race for memory pressure during model materialisation, and
    /// the post-handoff design wants a clean Whisper-first observation
    /// for diagnostic clarity.
    ///
    /// - Parameter variant: The Whisper model variant to request.
    ///   Defaulted to ``WhisperModelVariant/default``.
    func startPrewarm(variant: WhisperModelVariant = .default) {
        let loader = self.loader
        let lfm2Loader = self.lfm2Loader
        Task.detached(priority: .userInitiated) { [weak self] in
            await self?.setLoaderState(.loading)

            let whisperEngine: any WhisperClient
            do {
                whisperEngine = try await loader.loadIfNeeded(variant: variant)
                await self?.setLoaderState(.loaded(whisperEngine))
            } catch let error as TranscriptionError {
                await self?.setLoaderState(.failed(error))
                return
            } catch {
                // The loader's contract is to wrap any underlying error in
                // ``TranscriptionError/modelLoadFailed(_:)`` before
                // rethrowing, so this branch is defensive. We still
                // surface the failure with the stringified detail rather
                // than dropping it on the floor.
                let wrapped = TranscriptionError.modelLoadFailed(error.localizedDescription)
                await self?.setLoaderState(.failed(wrapped))
                return
            }

            // Whisper succeeded. Run the LFM2 load → warmup chain.
            await self?.setLFM2LoaderState(.loading)

            let lfm2Engine: any LFM2Engine
            do {
                lfm2Engine = try await lfm2Loader.loadIfNeeded(quantization: "Q5_K_M")
                await self?.setLFM2LoaderState(.loaded(lfm2Engine))
            } catch let error as TranslationError {
                await self?.setLFM2LoaderState(.failed(error))
                return
            } catch {
                let wrapped = TranslationError.modelLoadFailed(error.localizedDescription)
                await self?.setLFM2LoaderState(.failed(wrapped))
                return
            }

            do {
                await self?.setLFM2LoaderState(.warming)
                try await lfm2Loader.warmup()
                await self?.setLFM2LoaderState(.ready)
            } catch let error as TranslationError {
                await self?.setLFM2LoaderState(.failed(error))
            } catch {
                let wrapped = TranslationError.warmupFailed(error.localizedDescription)
                await self?.setLFM2LoaderState(.failed(wrapped))
            }
        }
    }

    /// MainActor-isolated setter used by the detached pre-warm task to
    /// mirror Whisper loader state back onto the UI thread. Extracted
    /// from ``startPrewarm(variant:)`` so the detached task body has
    /// no nested closures capturing `self?`, which would trip Swift 6
    /// strict concurrency's "captured var in concurrently-executing
    /// code" rule.
    private func setLoaderState(_ newState: LoaderState) {
        loaderState = newState
    }

    /// MainActor-isolated setter for the LFM2 loader state mirror.
    /// Mirrors the Whisper setter pattern (``setLoaderState(_:)``).
    private func setLFM2LoaderState(_ newState: LFM2LoaderState) {
        lfm2LoaderState = newState
    }

    /// MainActor-isolated setter for the LFM2 download progress mirror.
    /// Invoked by the trampoline that wraps the loader's progress
    /// handler so SDK-thread callbacks hop onto the main actor before
    /// touching observable state.
    private func setLFM2Progress(_ progress: Double?) {
        lfm2DownloadProgress = progress
    }
}

/// Private trampoline that mediates the LFM2 loader's progress handler.
///
/// Purpose: the loader's `progressHandler` parameter wants a `@Sendable
/// (Double) -> Void` closure at construction time, but
/// ``AppBootstrapper/init(...)`` cannot capture `self` in such a closure
/// because `self` is not yet fully initialised at the loader's
/// assignment line. The trampoline holds a mutable inner handler that
/// `init` binds post-construction, while the loader sees a stable
/// closure for the lifetime of the bootstrapper.
///
/// Synchronised via `OSAllocatedUnfairLock` per the CLAUDE.md Swift 6
/// rule that bans `NSLock` from async contexts.
private final class ProgressTrampoline: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock<(@Sendable (Double) -> Void)?>(initialState: nil)

    /// Forwards a progress fraction to the currently-bound inner
    /// handler. Called by the loader's progress handler closure on the
    /// SDK's callback thread; the inner handler is responsible for
    /// hopping to the main actor.
    ///
    /// `nonisolated` because LEAP's `downloadProgressHandler` invokes
    /// the wrapping `@Sendable` closure from the SDK's internal
    /// callback thread — which is not main-actor — and Xcode 26.5 /
    /// Swift 6.3.1 infers MainActor isolation on top-level classes by
    /// default. Without the explicit `nonisolated`, the call from the
    /// SDK thread would fail Swift 6 strict concurrency.
    nonisolated func forward(_ progress: Double) {
        let handler = lock.withLock { $0 }
        handler?(progress)
    }

    /// Replaces the inner handler. Called once from
    /// ``AppBootstrapper/installLFM2ProgressHandler(into:)``.
    ///
    /// `nonisolated` for symmetry with ``forward(_:)``; this method
    /// is invoked from the MainActor-isolated bootstrapper `init`, but
    /// declaring it `nonisolated` keeps the trampoline callable from
    /// any context without forcing a hop.
    nonisolated func bind(_ handler: @escaping @Sendable (Double) -> Void) {
        lock.withLock { $0 = handler }
    }
}
