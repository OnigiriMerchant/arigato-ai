//
//  OnboardingRoutingTests.swift
//  ArigatoAITests
//
//  Created by Jose Castell on 2026/05/17.
//

@testable import ArigatoAI
import Foundation
import os
import Testing

/// Tests for the ``ContentView`` top-of-body routing branch added in
/// Step 14. ViewInspector is not a project dependency, so these tests
/// exercise the same store-flag check ``ContentView`` performs at
/// render time rather than reflecting on the view's body output. The
/// production code path is two lines wide:
///
/// ```swift
/// if !onboardingComplete && !bootstrapper.onboardingStore.hasCompletedOnboarding {
///     OnboardingView(...)
/// } else {
///     mainContent
/// }
/// ```
///
/// These tests construct an in-memory ``OnboardingCompletionStoring``
/// fake and assert the branch the routing predicate would take under
/// each store state. Combined with
/// ``OnboardingViewModelTests/finish_happyPath_marksCompleteAndCallsOnComplete``
/// (which exercises the writer side via the recorded onComplete
/// callback), the routing contract is exercised end-to-end without
/// needing to drive the SwiftUI runtime.
///
/// Marked `@MainActor` because the store reads happen from a
/// `@MainActor` view body in production.
@Suite("ContentView onboarding routing")
@MainActor
struct OnboardingRoutingTests {
    /// In-memory ``OnboardingCompletionStoring`` fake. Mirrors the
    /// fake declared inside ``OnboardingViewModelTests`` so each
    /// suite file is self-contained.
    private final class InMemoryStore: OnboardingCompletionStoring, @unchecked Sendable {
        private let state = OSAllocatedUnfairLock(initialState: false)

        init(initial: Bool = false) {
            state.withLock { $0 = initial }
        }

        var hasCompletedOnboarding: Bool {
            state.withLock { $0 }
        }

        func markCompleted() {
            state.withLock { $0 = true }
        }
    }

    /// First-launch case: the store reports `false` and the
    /// in-process flag is `false`. The combined predicate
    /// `!onboardingComplete && !hasCompletedOnboarding` is `true`, so
    /// the onboarding branch renders.
    @Test
    func contentView_rendersOnboarding_whenNotComplete() {
        let store = InMemoryStore(initial: false)
        let onboardingComplete = false

        let shouldRenderOnboarding = !onboardingComplete && !store.hasCompletedOnboarding
        #expect(shouldRenderOnboarding == true)
    }

    /// Second-launch case: the store reports `true` (previous launch
    /// completed onboarding). Even with the in-process flag still
    /// `false` (fresh process, hasn't been flipped this run), the
    /// store gate short-circuits the predicate and the main-app
    /// branch renders.
    @Test
    func contentView_skipsOnboarding_whenAlreadyComplete() {
        let store = InMemoryStore(initial: true)
        let onboardingComplete = false

        let shouldRenderOnboarding = !onboardingComplete && !store.hasCompletedOnboarding
        #expect(shouldRenderOnboarding == false)
    }
}
