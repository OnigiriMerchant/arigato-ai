//
//  OnboardingCompletionStore.swift
//  ArigatoAI
//
//  Created by Jose Castell on 2026/05/17.
//

import Foundation

/// Persists the "user has finished onboarding" flag across launches.
///
/// The protocol exists so the production `UserDefaults`-backed conformer
/// can be swapped for an in-memory fake in tests (no on-disk state, no
/// `UserDefaults(suiteName:)` cleanup across runs).
///
/// ## Idempotency contract (load-bearing)
///
/// ``markCompleted()`` MUST be idempotent — multiple calls have the same
/// observable effect as one. Onboarding's ``OnboardingViewModel/finish()``
/// is gated against re-entry but the protocol-level guarantee removes
/// the need for callers to defensively check
/// ``hasCompletedOnboarding`` before writing. Named violation test:
/// `finish_calledTwice_marksOnceAndInvokesOnCompleteIdempotently` (in
/// ``OnboardingViewModelTests``).
///
/// ## Isolation
///
/// `nonisolated` because the project's default isolation is
/// `MainActor` (set via `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`).
/// The protocol exposes `Sendable` conformance so conformers can be
/// held across actor hops without explicit `@MainActor` annotation.
/// Production reads + writes happen from main-actor view-model contexts,
/// but tests on a `nonisolated` value-type fake must remain callable
/// without forcing a main-actor hop.
nonisolated protocol OnboardingCompletionStoring: Sendable {
    /// `true` once ``markCompleted()`` has been called at least once.
    /// Read by ``ContentView`` at render time to gate the onboarding
    /// branch; also read by tests inspecting completion state.
    var hasCompletedOnboarding: Bool { get }

    /// Marks onboarding as complete. Idempotent — multiple calls have
    /// the same observable effect as one. Production wiring calls this
    /// from ``OnboardingViewModel/finish()``.
    func markCompleted()
}

/// Production conformer backed by `UserDefaults`.
///
/// Stores under the key ``UserDefaultsOnboardingCompletionStore/key``.
/// Defaults to `UserDefaults.standard`; tests inject a
/// `UserDefaults(suiteName:)` scoped to the test invocation so global
/// state never leaks between runs.
///
/// ## Isolation
///
/// `nonisolated` — pure value type. The only stored property is a
/// `UserDefaults` reference, which is documented thread-safe by Apple
/// but not formally `Sendable` in the SDK. The `@unchecked Sendable`
/// annotation reflects the documented thread-safety guarantee: every
/// `UserDefaults` accessor used here (`bool(forKey:)`,
/// `set(_:forKey:)`) is safe from any thread. Callable from any
/// actor.
nonisolated struct UserDefaultsOnboardingCompletionStore: OnboardingCompletionStoring, @unchecked Sendable {
    /// The `UserDefaults` key under which the completion flag is
    /// stored. Exposed `static` so tests can clear / inspect the
    /// underlying value directly.
    static let key = "hasCompletedOnboarding"

    private let defaults: UserDefaults

    /// Creates a new store.
    ///
    /// - Parameter defaults: The `UserDefaults` instance to read +
    ///   write against. Defaulted to `.standard` for production.
    ///   Tests inject a `UserDefaults(suiteName:)` whose contents are
    ///   discarded after the test completes via
    ///   `removePersistentDomain(forName:)`.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var hasCompletedOnboarding: Bool {
        defaults.bool(forKey: Self.key)
    }

    /// Idempotent. The underlying `UserDefaults.set(_:forKey:)` call
    /// is itself idempotent for the same `true` value.
    func markCompleted() {
        defaults.set(true, forKey: Self.key)
    }
}
