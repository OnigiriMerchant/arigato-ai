//
//  AppBootstrapper.swift
//  ArigatoAI
//
//  Created by Jose Castell on 2026/05/10.
//

import Foundation
import os
import SwiftData
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

    /// The SwiftData ``ModelContainer`` the app's persistence stack runs
    /// against. `nil` only when ``ArigatoAIApp/init()`` was unable to
    /// construct one (in which case ``containerError`` is non-nil and
    /// ``StartupErrorView`` renders instead of the meeting surface).
    ///
    /// Held privately because the only consumer outside this type is
    /// ``startPrewarm(variant:)``'s Step 8 extension, which uses the
    /// container to construct ``meetingStore`` off the main actor.
    private let container: ModelContainer?

    /// Shared ``MeetingStore`` for the app's lifetime. `nil` until the
    /// detached portion of ``startPrewarm(variant:)`` finishes Whisper
    /// + LFM2 warmup and constructs the store; thereafter non-nil for
    /// the remainder of the process.
    ///
    /// ## Off-main initialization (Amendment 3 — FB13399899)
    ///
    /// `@ModelActor`'s synthesized `init(modelContainer:)` constructs a
    /// `DefaultSerialModelExecutor`. When the synthesized init runs on
    /// the main actor, the executor binds to the main thread rather
    /// than a background queue, causing SwiftData writes to block the
    /// UI. **FB13399899 / Apple Developer Forums 736226** documents
    /// this; no iOS 26 fix has been confirmed by Apple.
    ///
    /// To work around this, ``startPrewarm(variant:)`` constructs the
    /// store **inside its detached task** (not inside `MainActor.run`),
    /// so the synthesized init runs off-main and the executor binds to
    /// a background queue. Only the `meetingStore = store` publication
    /// hops back to the main actor.
    ///
    /// ## Scheduling assumption
    ///
    /// Once published, `meetingStore`'s `appendSentence` and other
    /// write paths must not block the main thread under sustained
    /// load. Named violation test:
    /// `meetingStoreWrites_doNotBlockMainThread_under100SentenceBurst`
    /// (in `AppBootstrapperMeetingWiringTests`) fires 100 writes and
    /// asserts a main-actor `Task.yield()` heartbeat keeps advancing.
    private(set) var meetingStore: MeetingStore?

    /// Eagerly-constructed audio capture conformer driven directly by
    /// ``MeetingCoordinator``. Production wires this to
    /// ``AudioCaptureActor``; tests inject a fake via the `capture:`
    /// parameter on ``init(loader:lfm2Loader:lfm2Factory:container:containerError:capture:transcriberFactory:routerFactory:)``.
    let capture: any AudioCapturing

    /// Persistent onboarding-completion flag store. Read by
    /// ``ContentView`` at render time to gate the first-launch
    /// ``OnboardingView`` branch; written by
    /// ``OnboardingViewModel/finish()``.
    ///
    /// Defaulted to ``UserDefaultsOnboardingCompletionStore`` for
    /// production. Tests inject an in-memory fake so the flag can be
    /// pre-set, observed, and discarded without leaking to
    /// `UserDefaults.standard`.
    ///
    /// Held on the bootstrapper for the same reason ``meetingStore``
    /// is: a single instance threaded through the SwiftUI environment
    /// avoids constructing a fresh store on every render. The store
    /// itself is `Sendable` and contains no per-render state.
    let onboardingStore: any OnboardingCompletionStoring

    /// Eagerly-constructed audio capture view model, kept alongside
    /// ``capture`` for UI bindings only —
    /// ``AudioCaptureViewModel/permissionStatus`` and
    /// ``AudioCaptureViewModel/level``. The VM is built with
    /// `router: nil` per Group D's locked decision D5-A revised: the
    /// router-drain path stays dormant under Group D's wiring (the
    /// pipeline drives the router directly via ``MeetingPipeline``).
    /// The same instance is shared with ``coordinator`` so object
    /// identity is preserved across UI bindings.
    let captureViewModel: AudioCaptureViewModel

    /// Shared ``MeetingCoordinator`` for the app's lifetime. `nil`
    /// until the detached portion of ``startPrewarm(variant:)``
    /// publishes both ``meetingStore`` and the coordinator atomically
    /// on the main actor; thereafter non-nil for the remainder of the
    /// process.
    ///
    /// ## Single-instance invariant
    ///
    /// At most one coordinator is constructed for the app's lifetime.
    /// ``startPrewarm(variant:)``'s tail guard short-circuits on a
    /// second invocation so the live coordinator instance is **not**
    /// replaced — UI bindings and any in-flight session state remain
    /// attached to the original instance. Named violation test:
    /// `startPrewarm_secondInvocation_doesNotOverwriteLiveCoordinator`
    /// (in `AppBootstrapperMeetingWiringTests`).
    ///
    /// ## ContentView optional-ladder fallback (D8-1 option b)
    ///
    /// While `coordinator == nil`, ``ContentView`` falls back to
    /// ``MeetingControlsViewModel/disabled()`` — the controls surface
    /// is rendered but every action closure is empty. Once
    /// ``startPrewarm(variant:)`` publishes the coordinator, SwiftUI
    /// re-renders against ``MeetingControlsViewModel/wiring(coordinator:)``.
    /// The window is sub-50ms in production (detached store init +
    /// main-actor hop).
    private(set) var coordinator: MeetingCoordinator?

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
    ///   - container: The SwiftData ``ModelContainer`` the app owns.
    ///     Defaults to `nil`. ``ArigatoAIApp/init()`` forwards
    ///     ``ArigatoAIApp/sharedModelContainer`` here; tests construct
    ///     in-memory containers and forward them. When `nil`,
    ///     ``startPrewarm(variant:)`` short-circuits before
    ///     constructing ``meetingStore`` / ``coordinator`` — both
    ///     remain `nil` and the UI renders ``StartupErrorView`` from
    ///     ``containerError``.
    ///   - containerError: Optional pre-seeded container error. Defaults
    ///     to `nil`. Production code uses ``recordContainerFailure(_:)``
    ///     instead; the parameter exists for tests that want to assert
    ///     the error-rendering branch in isolation.
    ///   - capture: Test-only override for the ``AudioCapturing``
    ///     conformer. Defaults to `nil`, in which case production
    ///     wiring constructs a fresh ``AudioCaptureActor``. The
    ///     resolved value is shared with both ``coordinator`` and
    ///     ``captureViewModel`` so object identity is stable.
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
    ///   - onboardingStore: Persistent onboarding-completion flag
    ///     store. Defaulted to ``UserDefaultsOnboardingCompletionStore``
    ///     for production. Tests inject an in-memory fake so the flag
    ///     can be pre-set or observed without leaking to
    ///     `UserDefaults.standard`.
    init(
        loader: WhisperModelLoader = WhisperModelLoader(),
        lfm2Loader: LFM2ModelLoader? = nil,
        lfm2Factory: LFM2EngineFactory? = nil,
        container: ModelContainer? = nil,
        containerError: Error? = nil,
        capture: (any AudioCapturing)? = nil,
        transcriberFactory: ((WhisperModelLoader) -> TranscriptionActor)? = nil,
        routerFactory: (@MainActor (TranscriptionActor) -> LanguageRouter)? = nil,
        onboardingStore: any OnboardingCompletionStoring = UserDefaultsOnboardingCompletionStore()
    ) {
        self.loader = loader
        self.container = container
        self.containerError = containerError
        self.onboardingStore = onboardingStore
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
        // Eagerly construct the audio-capture pair so the shared
        // instance survives across renders (test #2 asserts object
        // identity between `bootstrapper.captureViewModel` and the
        // coordinator's `captureViewModel`).
        let resolvedCapture: any AudioCapturing = capture ?? AudioCaptureActor()
        self.capture = resolvedCapture
        // `router: nil` per D5-A revised — the VM's drain path is
        // dormant under Group D's wiring (V3 cleanup deferred).
        captureViewModel = AudioCaptureViewModel(
            capture: resolvedCapture,
            router: nil
        )
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
    /// **Meeting wiring ordering (Step 8 — Amendment 3).** After LFM2
    /// reaches ``LFM2LoaderState/ready``, the detached task short-circuits
    /// if ``container`` is `nil` (no persistence stack means no meeting
    /// surface). Otherwise an idempotency guard checks that
    /// ``coordinator`` has not already been published — a second call to
    /// `startPrewarm` after the first has reached this point is a no-op,
    /// preserving the live coordinator instance and any in-flight UI
    /// bindings. If both gates pass, the detached task constructs
    /// ``MeetingStore`` **inline (not inside `MainActor.run`)** so the
    /// `@ModelActor`'s synthesized `DefaultSerialModelExecutor` binds
    /// to a background queue per the Amendment 3 contract documented
    /// on ``meetingStore`` — see FB13399899 / Apple Developer Forums
    /// 736226. Both ``meetingStore`` and ``coordinator`` are then
    /// published atomically on a single main-actor hop.
    ///
    /// Sequential ordering (Whisper → LFM2 → meeting wiring) is
    /// enforced by Swift's async/await linearization within the
    /// detached task; no `async let` is used and no runtime violation
    /// test is needed for the ordering itself (the type system enforces
    /// it).
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
                return
            } catch {
                let wrapped = TranslationError.warmupFailed(error.localizedDescription)
                await self?.setLFM2LoaderState(.failed(wrapped))
                return
            }

            // ─── Step 8 — Meeting wiring (Amendment 3 / FB13399899) ───
            //
            // Step 9: short-circuit if no SwiftData container exists.
            // Without persistence the meeting surface cannot run, and
            // the UI is routed to StartupErrorView via containerError
            // instead.
            guard let container = await self?.container else { return }

            // Step 10: idempotency guard. A second invocation of
            // startPrewarm after the first has published coordinator
            // MUST NOT overwrite the live instance — see the
            // `coordinator` property's "Single-instance invariant"
            // note and the named violation test
            // `startPrewarm_secondInvocation_doesNotOverwriteLiveCoordinator`.
            let alreadyPublished = await MainActor.run {
                self?.coordinator != nil
            }
            if alreadyPublished == true { return }

            // Step 11: construct MeetingStore here on the **detached
            // task's executor**, NOT inside MainActor.run. The
            // @ModelActor-synthesized DefaultSerialModelExecutor binds
            // to the executor that runs its init; running this line
            // off-main is the FB13399899 / Apple Developer Forums
            // 736226 workaround. See the `meetingStore` property's
            // doc-comment for the full rationale + named violation
            // test `meetingStoreWrites_doNotBlockMainThread_under100SentenceBurst`.
            let store = MeetingStore(modelContainer: container)

            // Step 12: publish both atomically on the main actor.
            // Re-check the idempotency guard inside MainActor.run to
            // close the (vanishingly small) window between the
            // pre-construct check above and this hop — without this,
            // two concurrent `startPrewarm()` invocations could both
            // observe `coordinator == nil` and both proceed to
            // construct a store + coordinator.
            await MainActor.run {
                guard let strong = self, strong.coordinator == nil else { return }
                strong.meetingStore = store
                strong.coordinator = strong.makeCoordinator(store: store)
            }
        }
    }

    /// Builds a wired ``MeetingCoordinator`` against the supplied
    /// ``MeetingStore`` and the bootstrapper's shared dependencies.
    ///
    /// Invoked inside the `MainActor.run` block at the tail of
    /// ``startPrewarm(variant:)``. The helper exists so the
    /// detached-task body stays readable and the
    /// `MeetingSession` / `TranslationActor` / `MeetingPipeline` /
    /// `MeetingCoordinator` construction chain is documented in one
    /// place.
    ///
    /// - Precondition: ``lfm2Loader`` must be non-nil (warmup having
    ///   completed implies this; if reached otherwise the call is a
    ///   sequencing bug in the warmup chain).
    /// - Parameter store: The persistence actor returned by Step 11.
    /// - Returns: A coordinator with `session.phase == .idle`.
    private func makeCoordinator(store: MeetingStore) -> MeetingCoordinator {
        let session = MeetingSession(store: store)
        let translator = TranslationActor(loader: lfm2Loader)
        let pipeline = MeetingPipeline(
            router: router,
            translator: translator,
            session: session
        )
        return MeetingCoordinator(
            session: session,
            capture: capture,
            captureViewModel: captureViewModel,
            pipeline: pipeline
        )
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
