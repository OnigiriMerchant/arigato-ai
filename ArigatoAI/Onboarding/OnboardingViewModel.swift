//
//  OnboardingViewModel.swift
//  ArigatoAI
//
//  Created by Jose Castell on 2026/05/17.
//

import Foundation
import Observation

/// `@Observable` view model that owns ``OnboardingView``'s step
/// transition, microphone-permission request, completion gate, and
/// finish dispatch.
///
/// Extracted from the view body per the Phase-2 trio pattern
/// (``MeetingDetailViewModel`` Step 11, ``TranscriptSplitScreenViewModel``
/// Step 9a, etc.) so the step machine + truth-table logic are directly
/// testable. Tests construct the VM with injected closures (a
/// `permissionRequester` that simulates grant/deny, an
/// `OnboardingCompletionStoring` fake, an `onComplete` callback that
/// flips a recorded flag) and exercise ``advance()`` / ``finish()`` /
/// ``continueButtonEnabled(whisperReady:lfm2State:)`` directly.
///
/// `@MainActor` because every published property mutates from
/// SwiftUI's render context. The permission requester closure crosses
/// to whatever actor the underlying API lives on; the post-`await`
/// assignment hops back to the main actor by virtue of the VM's
/// isolation.
///
/// ## Scheduling assumption (Concurrency design discipline)
///
/// **Single permission request in flight.** The
/// ``OnboardingView/welcomeScreen`` "Get Started" button fires
/// ``advance()`` inside an `async` task. ``advance()`` calls
/// ``requestMicrophonePermission()`` exactly once because it is gated
/// by ``didRequestPermission`` — a second invocation observes the
/// flag and short-circuits silently. SwiftUI's gesture system never
/// produces concurrent taps on the same view, but the gating is
/// defence-in-depth against e.g. a "Get Started" button rendered twice
/// during a re-render race. Named violation test (verified to enforce
/// the contract): `requestMicrophonePermission_calledTwice_firesPromptOnce`.
///
/// **Idempotent `finish()`.** A second call to ``finish()`` after the
/// first MUST NOT invoke ``onComplete`` again — once `hasFinished` is
/// `true` the method is a no-op. Combined with the
/// ``OnboardingCompletionStoring`` protocol's idempotency contract on
/// ``OnboardingCompletionStoring/markCompleted()``, this means the
/// flow can survive accidental re-entry without double-routing through
/// the main app or double-writing UserDefaults. Named violation test:
/// `finish_calledTwice_marksOnceAndInvokesOnCompleteIdempotently`.
@MainActor
@Observable
final class OnboardingViewModel {
    // MARK: - Published state

    /// The current screen. Mutates only via ``advance()``.
    private(set) var step: OnboardingStep = .welcome

    /// `true` once ``requestMicrophonePermission()`` has been called at
    /// least once. Gates the permission-request re-entry guard and is
    /// part of the continue-button enablement truth table.
    private(set) var didRequestPermission: Bool = false

    /// The most recent microphone permission status. Defaults to
    /// `.notDetermined` until the prompt resolves. Drives the
    /// "Microphone: granted/denied/not yet requested" indicator on
    /// Screen 2.
    private(set) var permissionStatus: MicrophonePermissionStatus = .notDetermined

    // MARK: - Dependencies

    /// Persistent completion flag store. Production wiring uses
    /// ``UserDefaultsOnboardingCompletionStore``; tests inject an
    /// in-memory fake.
    private let store: any OnboardingCompletionStoring

    /// Async closure that fires the system microphone-permission
    /// prompt. Production wiring closes over
    /// ``MicrophonePermissionService/requestAccess()``; tests inject
    /// a closure that simulates grant/deny without driving the iOS
    /// permission machinery.
    ///
    /// Returning ``MicrophonePermissionStatus`` (the project-local
    /// `Sendable` mirror) rather than `AVAudioApplication.recordPermission`
    /// keeps onboarding decoupled from the audio stack and lets tests
    /// drive arbitrary statuses including `.restricted`.
    private let permissionRequester: () async -> MicrophonePermissionStatus

    /// Callback invoked once from ``finish()`` after the store has
    /// been marked complete. Production wiring flips a `@State` flag
    /// on ``ContentView`` so the routing branch re-evaluates and
    /// renders the main app. Tests inject a recorder.
    private let onComplete: @MainActor () -> Void

    /// Guards ``finish()`` against re-entry. The first call writes
    /// `true`; subsequent calls observe and short-circuit.
    private var hasFinished: Bool = false

    // MARK: - Init

    /// Designated initializer.
    ///
    /// - Parameters:
    ///   - store: Persistent completion flag store. Tests inject an
    ///     in-memory fake; production wires
    ///     ``UserDefaultsOnboardingCompletionStore``.
    ///   - permissionRequester: Async closure that fires the
    ///     microphone-permission prompt and returns the resulting
    ///     ``MicrophonePermissionStatus``. Tests inject a closure that
    ///     simulates grant/deny synchronously.
    ///   - onComplete: Main-actor callback invoked exactly once from
    ///     the first successful ``finish()`` call.
    init(
        store: any OnboardingCompletionStoring,
        permissionRequester: @escaping () async -> MicrophonePermissionStatus,
        onComplete: @escaping @MainActor () -> Void
    ) {
        self.store = store
        self.permissionRequester = permissionRequester
        self.onComplete = onComplete
    }

    // MARK: - Actions

    /// Transitions from ``OnboardingStep/welcome`` to
    /// ``OnboardingStep/setup`` and fires the microphone-permission
    /// prompt as a side effect.
    ///
    /// Called from the "Get Started" button's `async` action closure.
    /// Idempotent against being called when ``step`` is already
    /// ``OnboardingStep/setup`` — the step assignment is a no-op write
    /// of the same value, and the permission request is itself
    /// re-entry-gated by ``didRequestPermission``.
    func advance() async {
        step = .setup
        await requestMicrophonePermission()
    }

    /// Fires the microphone-permission prompt exactly once across the
    /// VM's lifetime. A second call observes ``didRequestPermission``
    /// and short-circuits silently — see the type doc-comment's
    /// scheduling assumption for the contract + named violation test
    /// `requestMicrophonePermission_calledTwice_firesPromptOnce`.
    ///
    /// The mark-as-requested write happens BEFORE the `await` so a
    /// re-entrant call during the in-flight request observes the flag
    /// and short-circuits without queueing a second SDK prompt.
    private func requestMicrophonePermission() async {
        if didRequestPermission { return }
        didRequestPermission = true
        permissionStatus = await permissionRequester()
    }

    /// The continue-button enablement truth table.
    ///
    /// Returns `true` when EITHER:
    /// - Both loaders are ready (Whisper loaded AND LFM2 ready) AND
    ///   the permission prompt has already been fired (regardless of
    ///   the user's grant/deny choice — denial still completes the
    ///   prompt, and the existing in-context permission flow in
    ///   ``AudioCaptureViewModel`` will re-prompt or surface the
    ///   Settings affordance once recording is attempted), OR
    /// - LFM2 has failed AND the permission prompt has been fired.
    ///   The LFM2-broken branch surfaces "Continue without translation"
    ///   so the user can still mark onboarding complete and reach the
    ///   main app (which then routes to ``StartupErrorView`` via the
    ///   existing precedence in ``ArigatoAIApp``).
    ///
    /// All other combinations return `false`: any in-progress loader
    /// state (downloading, warming), a Whisper failure (terminal —
    /// onboarding can't complete), or a pre-permission-request render
    /// (the user hasn't seen the prompt yet).
    ///
    /// - Parameters:
    ///   - whisperReady: Convenience flag derived by the view from
    ///     the bootstrapper's ``AppBootstrapper/loaderState`` (the
    ///     view inspects `case .loaded`).
    ///   - lfm2State: The full LFM2 loader state (the truth table
    ///     branches on `.ready` vs `.failed` vs everything-else).
    /// - Returns: `true` if the continue button should be enabled.
    func continueButtonEnabled(whisperReady: Bool, lfm2State: LFM2LoaderState) -> Bool {
        guard didRequestPermission else { return false }
        if case .failed = lfm2State { return true }
        guard whisperReady else { return false }
        if case .ready = lfm2State { return true }
        return false
    }

    /// Marks onboarding complete and invokes ``onComplete``.
    ///
    /// Idempotent: a second call after the first short-circuits via
    /// ``hasFinished``. The protocol-level idempotency contract on
    /// ``OnboardingCompletionStoring/markCompleted()`` is a second
    /// layer of defence — even if the gate were removed, the store
    /// write itself would be safe. Named violation test:
    /// `finish_calledTwice_marksOnceAndInvokesOnCompleteIdempotently`.
    func finish() {
        if hasFinished { return }
        hasFinished = true
        store.markCompleted()
        onComplete()
    }
}
