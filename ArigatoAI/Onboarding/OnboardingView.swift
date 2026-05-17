//
//  OnboardingView.swift
//  ArigatoAI
//
//  Created by Jose Castell on 2026/05/17.
//

import SwiftUI

/// Two-screen first-launch onboarding per UI #16.
///
/// **Screen 1 — Welcome.** Value-prop screen with the privacy promise
/// locked verbatim by D14-4. Single primary action ("Get Started")
/// fires ``OnboardingViewModel/advance()``.
///
/// **Screen 2 — Setup.** Reactive status screen bound to the shared
/// ``AppBootstrapper``'s `@Observable` loader state. The status line,
/// progress bar, and continue-button label all derive from
/// ``OnboardingFormatter``. The continue button's enablement comes
/// from ``OnboardingViewModel/continueButtonEnabled(whisperReady:lfm2State:)``.
///
/// ## Routing contract
///
/// Rendered by ``ContentView`` only when the
/// ``OnboardingCompletionStoring`` flag is `false`. The view does NOT
/// own its own dismissal — ``OnboardingViewModel/finish()`` flips the
/// completion flag via the store and invokes the `onComplete`
/// callback, which the parent uses to re-evaluate its routing.
///
/// ## Navigation
///
/// No `NavigationStack` — onboarding is a self-contained two-screen
/// flow with no back affordance per UI #16 (the welcome screen is the
/// kill-restart anchor; a kill mid-onboarding restarts at Screen 1).
/// The two screens swap inside a single `Group` with a
/// `.animation(.default, value: viewModel.step)` cross-fade.
///
/// ## Styling
///
/// Stock SwiftUI: system fonts (UI decision #18), semantic colors
/// (UI decision #17). The disabled continue-button rendering uses
/// `.tint(.secondary)` + `.disabled(true)` per UI #16's explicit
/// exception to the button-morphing-no-disabled-states principle.
@MainActor
struct OnboardingView: View {
    @State private var viewModel: OnboardingViewModel

    /// Shared bootstrapper threaded in from ``ArigatoAIApp`` via the
    /// SwiftUI environment. Drives Screen 2's reactive status line,
    /// progress bar, and continue-button enablement.
    @Environment(AppBootstrapper.self) private var bootstrapper

    /// Creates a new onboarding view.
    ///
    /// - Parameters:
    ///   - store: Persistent completion flag store. Production wiring
    ///     passes ``AppBootstrapper/onboardingStore``; tests inject
    ///     an in-memory fake.
    ///   - permissionRequester: Async closure that fires the
    ///     microphone-permission prompt. Defaulted to a closure that
    ///     closes over a fresh ``MicrophonePermissionService``. Tests
    ///     inject a closure that simulates grant/deny synchronously.
    ///   - onComplete: Main-actor callback invoked exactly once from
    ///     the first successful ``OnboardingViewModel/finish()`` call.
    ///     ``ContentView`` flips a `@State` flag to re-route to the
    ///     main app.
    init(
        store: any OnboardingCompletionStoring,
        permissionRequester: (() async -> MicrophonePermissionStatus)? = nil,
        onComplete: @escaping @MainActor () -> Void
    ) {
        let resolvedRequester: () async -> MicrophonePermissionStatus
        if let permissionRequester {
            resolvedRequester = permissionRequester
        } else {
            let service = MicrophonePermissionService()
            resolvedRequester = { @MainActor in
                await service.requestAccess()
            }
        }
        _viewModel = State(
            wrappedValue: OnboardingViewModel(
                store: store,
                permissionRequester: resolvedRequester,
                onComplete: onComplete
            )
        )
    }

    var body: some View {
        Group {
            switch viewModel.step {
            case .welcome:
                welcomeScreen
            case .setup:
                setupScreen
            }
        }
        .animation(.default, value: viewModel.step)
    }

    // MARK: - Screen 1: Welcome

    /// The value-prop screen. Title + privacy-promise body (locked
    /// verbatim per D14-4) + a single "Get Started" primary action.
    private var welcomeScreen: some View {
        VStack(spacing: 32) {
            Spacer()

            Image(systemName: "text.bubble.fill")
                .font(.system(size: 64))
                .foregroundStyle(.tint)

            VStack(spacing: 16) {
                Text("Translate meetings in real time")
                    .font(.title)
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.center)

                Text(
                    "Japanese-English translation in real time, fully on-device. "
                        + "Your conversations stay on your iPhone. Nothing is sent to "
                        + "servers. No accounts, no logins, no analytics."
                )
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)

            Spacer()

            Button {
                Task { await viewModel.advance() }
            } label: {
                Text("Get Started")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .buttonBorderShape(.capsule)
            .padding(.horizontal, 32)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Screen 2: Setup

    /// The reactive setup screen. Status line + optional progress bar +
    /// mic-permission explainer + permission-status indicator +
    /// morphing continue button.
    private var setupScreen: some View {
        VStack(spacing: 24) {
            Spacer()

            Text("Setting up Arigato AI.")
                .font(.title)
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)

            VStack(spacing: 12) {
                Text(
                    OnboardingFormatter.statusText(
                        whisperState: bootstrapper.loaderState,
                        lfm2State: bootstrapper.lfm2LoaderState
                    )
                )
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

                if let fraction = OnboardingFormatter.progressFraction(
                    lfm2State: bootstrapper.lfm2LoaderState
                ) {
                    ProgressView(value: fraction)
                        .progressViewStyle(.linear)
                        .padding(.horizontal, 32)
                }

                if case .downloading = bootstrapper.lfm2LoaderState {
                    Text("Connect to Wi-Fi for faster setup.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
            }

            Spacer()

            VStack(alignment: .leading, spacing: 16) {
                Text(
                    "Arigato AI uses your microphone to capture meeting audio. "
                        + "Audio is processed on-device and never leaves your phone."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)

                HStack(spacing: 8) {
                    Image(systemName: permissionIconName)
                        .foregroundStyle(permissionIconTint)
                    Text(permissionStatusLabel)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 32)
            }

            let whisperReady: Bool = {
                if case .loaded = bootstrapper.loaderState { return true }
                return false
            }()
            let isEnabled = viewModel.continueButtonEnabled(
                whisperReady: whisperReady,
                lfm2State: bootstrapper.lfm2LoaderState
            )

            Button {
                viewModel.finish()
            } label: {
                Text(OnboardingFormatter.continueButtonLabel(
                    lfm2State: bootstrapper.lfm2LoaderState
                ))
                .font(.headline)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .buttonBorderShape(.capsule)
            .tint(isEnabled ? .accentColor : .secondary)
            .disabled(!isEnabled)
            .padding(.horizontal, 32)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Helpers

    /// The SF Symbol name for the permission-status indicator row.
    /// Mirrors the granted / denied / not-yet-requested branches of
    /// the label below.
    private var permissionIconName: String {
        switch viewModel.permissionStatus {
        case .granted:
            return "checkmark.circle.fill"
        case .denied, .restricted:
            return "exclamationmark.triangle.fill"
        case .notDetermined:
            return "circle.dotted"
        }
    }

    /// The semantic tint for the permission-status icon.
    private var permissionIconTint: Color {
        switch viewModel.permissionStatus {
        case .granted:
            return .green
        case .denied, .restricted:
            return .orange
        case .notDetermined:
            return .secondary
        }
    }

    /// The user-facing permission-status label.
    /// Locked verbatim per UI #16 + the Step 14 dispatch brief copy.
    private var permissionStatusLabel: String {
        switch viewModel.permissionStatus {
        case .granted:
            return "Microphone: granted"
        case .denied, .restricted:
            return "Microphone: denied — open Settings to enable"
        case .notDetermined:
            return "Microphone: not yet requested"
        }
    }
}

#Preview("Welcome") {
    OnboardingView(
        store: UserDefaultsOnboardingCompletionStore(),
        permissionRequester: { .granted },
        onComplete: {}
    )
    .environment(AppBootstrapper())
}
