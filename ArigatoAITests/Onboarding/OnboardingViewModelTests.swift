//
//  OnboardingViewModelTests.swift
//  ArigatoAITests
//
//  Created by Jose Castell on 2026/05/17.
//

@testable import ArigatoAI
import Foundation
import os
import Testing

/// Tests for ``OnboardingViewModel`` — the step machine + permission
/// gate + truth-table + idempotent finish.
///
/// ViewInspector is not a project dependency, so view-level behaviour
/// is exercised through the extracted `@Observable` view model: tests
/// construct the VM with closure-injected dependencies (in-memory
/// completion store, simulated permission requester, recording
/// onComplete) and inspect the resulting state.
///
/// Marked `@MainActor` because the VM is `@MainActor` and the project
/// convention is `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`.
@Suite("OnboardingViewModel")
@MainActor
struct OnboardingViewModelTests {
    // MARK: - Helpers

    /// In-memory ``OnboardingCompletionStoring`` fake. Records the
    /// number of ``markCompleted()`` calls under an
    /// `OSAllocatedUnfairLock` so tests can verify idempotency
    /// contracts without relying on `UserDefaults` global state.
    private final class InMemoryStore: OnboardingCompletionStoring, @unchecked Sendable {
        private let state = OSAllocatedUnfairLock(initialState: State())

        private struct State {
            var completed: Bool = false
            var markCallCount: Int = 0
        }

        var hasCompletedOnboarding: Bool {
            state.withLock { $0.completed }
        }

        var markCallCount: Int {
            state.withLock { $0.markCallCount }
        }

        func markCompleted() {
            state.withLock {
                $0.completed = true
                $0.markCallCount += 1
            }
        }
    }

    /// Counts permission-requester invocations under a lock so the
    /// single-fire violation test can assert exactly one prompt.
    private final class PromptCounter: @unchecked Sendable {
        private let count = OSAllocatedUnfairLock(initialState: 0)

        var value: Int {
            count.withLock { $0 }
        }

        func increment() {
            count.withLock { $0 += 1 }
        }
    }

    /// Counts onComplete invocations so the finish-idempotency
    /// violation test can assert exactly one callback.
    private final class CompletionCounter: @unchecked Sendable {
        private let count = OSAllocatedUnfairLock(initialState: 0)

        var value: Int {
            count.withLock { $0 }
        }

        func increment() {
            count.withLock { $0 += 1 }
        }
    }

    // MARK: - advance

    /// Verifies the welcome → setup transition and that the permission
    /// requester is fired exactly once as a side effect.
    @Test
    func advance_transitionsToSetup_andFiresPermissionRequest() async {
        let store = InMemoryStore()
        let counter = PromptCounter()
        let vm = OnboardingViewModel(
            store: store,
            permissionRequester: {
                counter.increment()
                return .granted
            },
            onComplete: {}
        )

        #expect(vm.step == .welcome)
        #expect(vm.didRequestPermission == false)
        #expect(vm.permissionStatus == .notDetermined)

        await vm.advance()

        #expect(vm.step == .setup)
        #expect(vm.didRequestPermission == true)
        #expect(vm.permissionStatus == .granted)
        #expect(counter.value == 1)
    }

    // MARK: - Violation test #1: single-permission-fire

    /// Named violation test for the "single permission request in
    /// flight" scheduling assumption documented on
    /// ``OnboardingViewModel/requestMicrophonePermission()``.
    ///
    /// Calls ``advance()`` twice in sequence and asserts the
    /// permission requester fired exactly once. The re-entry guard is
    /// `didRequestPermission` — once set, the second call observes the
    /// flag and short-circuits.
    @Test
    func requestMicrophonePermission_calledTwice_firesPromptOnce() async {
        let store = InMemoryStore()
        let counter = PromptCounter()
        let vm = OnboardingViewModel(
            store: store,
            permissionRequester: {
                counter.increment()
                return .granted
            },
            onComplete: {}
        )

        await vm.advance()
        await vm.advance()

        #expect(counter.value == 1)
        #expect(vm.didRequestPermission == true)
        #expect(vm.step == .setup)
    }

    // MARK: - Truth table

    /// Truth table for
    /// ``OnboardingViewModel/continueButtonEnabled(whisperReady:lfm2State:)``.
    ///
    /// The button is enabled when:
    /// - Both loaders ready AND permission requested, OR
    /// - LFM2 failed AND permission requested.
    ///
    /// Everything else is disabled. This test enumerates each
    /// load-bearing combination explicitly rather than via
    /// `@Test(arguments:)` for legibility — the dispatch brief
    /// authorizes either shape.
    @Test
    func continueButtonEnabled_truthTable() async {
        let store = InMemoryStore()

        // Helper: build a VM with the requested didRequestPermission state.
        // We can't set didRequestPermission directly (private(set)), so
        // for the "permission requested" case we call advance() which
        // flips it via the closure-injected requester.
        func makeVM(permissionRequested: Bool) async -> OnboardingViewModel {
            let vm = OnboardingViewModel(
                store: store,
                permissionRequester: { .granted },
                onComplete: {}
            )
            if permissionRequested {
                await vm.advance()
            }
            return vm
        }

        // Permission not yet requested: disabled regardless of loader state.
        let preVM = await makeVM(permissionRequested: false)
        #expect(preVM.continueButtonEnabled(whisperReady: false, lfm2State: .idle) == false)
        #expect(preVM.continueButtonEnabled(whisperReady: true, lfm2State: .ready) == false)
        #expect(preVM.continueButtonEnabled(whisperReady: false, lfm2State: .failed(.modelLoadFailed("x"))) == false)
        #expect(preVM.continueButtonEnabled(whisperReady: true, lfm2State: .failed(.modelLoadFailed("x"))) == false)

        // Permission requested: now branches on loader state.
        let postVM = await makeVM(permissionRequested: true)
        // Both ready → enabled.
        #expect(postVM.continueButtonEnabled(whisperReady: true, lfm2State: .ready) == true)
        // LFM2 failed → enabled (regardless of Whisper).
        #expect(postVM.continueButtonEnabled(whisperReady: true, lfm2State: .failed(.modelLoadFailed("x"))) == true)
        #expect(postVM.continueButtonEnabled(whisperReady: false, lfm2State: .failed(.modelLoadFailed("x"))) == true)
        // Whisper not ready, LFM2 ready → disabled.
        #expect(postVM.continueButtonEnabled(whisperReady: false, lfm2State: .ready) == false)
        // Both loading → disabled.
        #expect(postVM.continueButtonEnabled(whisperReady: false, lfm2State: .idle) == false)
        // Whisper ready, LFM2 downloading → disabled.
        #expect(postVM.continueButtonEnabled(whisperReady: true, lfm2State: .downloading(0.5)) == false)
        // Whisper ready, LFM2 warming → disabled.
        #expect(postVM.continueButtonEnabled(whisperReady: true, lfm2State: .warming) == false)
    }

    // MARK: - finish

    /// Happy path: ``finish()`` marks the store complete and invokes
    /// onComplete exactly once.
    @Test
    func finish_happyPath_marksCompleteAndCallsOnComplete() {
        let store = InMemoryStore()
        let completion = CompletionCounter()
        let vm = OnboardingViewModel(
            store: store,
            permissionRequester: { .granted },
            onComplete: { completion.increment() }
        )

        vm.finish()

        #expect(store.hasCompletedOnboarding == true)
        #expect(store.markCallCount == 1)
        #expect(completion.value == 1)
    }

    // MARK: - Violation test #2: finish idempotency

    /// Named violation test for the ``OnboardingViewModel/finish()``
    /// idempotency contract documented on the type. A second call after
    /// the first MUST NOT re-invoke onComplete (and SHOULD not double-
    /// write the store, though the protocol-level idempotency contract
    /// makes a double-write a no-op).
    @Test
    func finish_calledTwice_marksOnceAndInvokesOnCompleteIdempotently() {
        let store = InMemoryStore()
        let completion = CompletionCounter()
        let vm = OnboardingViewModel(
            store: store,
            permissionRequester: { .granted },
            onComplete: { completion.increment() }
        )

        vm.finish()
        vm.finish()

        #expect(store.hasCompletedOnboarding == true)
        #expect(store.markCallCount == 1)
        #expect(completion.value == 1)
    }

    // MARK: - LFM2-failed branch coverage

    /// Verifies the LFM2-failed branch of the truth table. Combined
    /// with `continueButtonEnabled_truthTable` above, this is the
    /// load-bearing assertion that the user can still complete
    /// onboarding when LFM2 cannot load — preventing the "Screen 1 on
    /// every launch" failure mode the brief's LFM2-broken-handling
    /// section describes.
    @Test
    func isReadyToFinish_lfm2Failed_returnsTrue_whenPermissionRequested() async {
        let store = InMemoryStore()
        let vm = OnboardingViewModel(
            store: store,
            permissionRequester: { .granted },
            onComplete: {}
        )

        // Pre-permission: disabled even when LFM2 is failed (the user
        // hasn't seen the explainer yet).
        #expect(vm.continueButtonEnabled(whisperReady: true, lfm2State: .failed(.modelLoadFailed("portal -1011"))) == false)

        await vm.advance()

        // Post-permission: enabled regardless of Whisper state.
        #expect(vm.continueButtonEnabled(whisperReady: true, lfm2State: .failed(.modelLoadFailed("portal -1011"))) == true)
        #expect(vm.continueButtonEnabled(whisperReady: false, lfm2State: .failed(.modelLoadFailed("portal -1011"))) == true)
    }
}
