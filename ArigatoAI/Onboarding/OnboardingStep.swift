//
//  OnboardingStep.swift
//  ArigatoAI
//
//  Created by Jose Castell on 2026/05/17.
//

import Foundation

/// The two-screen flow surfaced by ``OnboardingView`` per UI decision #16.
///
/// **Screen 1 — Welcome.** Value-prop screen with the privacy promise
/// locked verbatim by D14-4. Single primary action ("Get Started")
/// transitions to ``setup``.
///
/// **Screen 2 — Setup.** Reactive status screen that binds to the
/// ``AppBootstrapper``'s `@Observable` loader state and the
/// microphone-permission request fired by ``OnboardingViewModel/advance()``.
/// Completion advances out of onboarding entirely via
/// ``OnboardingViewModel/finish()``.
///
/// ## Isolation
///
/// Marked `nonisolated` because the project sets
/// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` and this is a pure value
/// type that must cross actor boundaries (e.g. `@MainActor` view-model
/// state read from `nonisolated` formatter tests). Equatable +
/// Sendable are both auto-synthesized.
nonisolated enum OnboardingStep: Equatable {
    /// Initial screen. Renders the privacy-promise value prop and a
    /// single "Get Started" primary action.
    case welcome

    /// Reactive setup screen. Renders model-load status, mic-permission
    /// explainer + status, and the morphing continue button.
    case setup
}
