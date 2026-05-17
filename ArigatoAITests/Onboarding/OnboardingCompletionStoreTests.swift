//
//  OnboardingCompletionStoreTests.swift
//  ArigatoAITests
//
//  Created by Jose Castell on 2026/05/17.
//

@testable import ArigatoAI
import Foundation
import Testing

/// Round-trip tests for ``UserDefaultsOnboardingCompletionStore``.
///
/// Uses a `UserDefaults(suiteName:)` scoped to the test invocation so
/// neither `UserDefaults.standard` nor any other test's state leaks in.
/// The suite is cleared via `removePersistentDomain(forName:)` after
/// each test.
///
/// Marked `@MainActor` for project convention parity — the store itself
/// is `nonisolated`, so calls are legal from any context.
@Suite("UserDefaultsOnboardingCompletionStore")
@MainActor
struct OnboardingCompletionStoreTests {
    private static func makeSuite() -> (UserDefaults, String) {
        let name = "OnboardingCompletionStoreTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: name) else {
            // Suite construction should never fail with a fresh UUID
            // name, but if it does we surface an Issue rather than
            // force-unwrapping.
            Issue.record("UserDefaults(suiteName:) returned nil for \(name)")
            return (.standard, name)
        }
        return (defaults, name)
    }

    /// Verifies the full round-trip: a fresh `UserDefaults` reports
    /// `false`, `markCompleted()` flips it to `true`, and a second
    /// store reading the same suite reports `true` (proving persistence
    /// across instances).
    @Test
    func userDefaultsOnboardingCompletionStore_roundTrip() {
        let (defaults, name) = Self.makeSuite()
        defer { defaults.removePersistentDomain(forName: name) }

        let store = UserDefaultsOnboardingCompletionStore(defaults: defaults)
        #expect(store.hasCompletedOnboarding == false)

        store.markCompleted()
        #expect(store.hasCompletedOnboarding == true)

        // Second store reading the same suite proves the flag persists
        // across instances (not just the in-memory `defaults` reference).
        let secondStore = UserDefaultsOnboardingCompletionStore(defaults: defaults)
        #expect(secondStore.hasCompletedOnboarding == true)
    }
}
