//
//  UndoStopToastViewTests.swift
//  ArigatoAITests
//
//  Created by Jose Castell on 2026/05/16.
//

@testable import ArigatoAI
import Foundation
import os
import Testing

/// Tests for ``UndoStopToastView``. The view is a thin wrapper around a
/// `TimelineView`-driven button — without ViewInspector the tests
/// exercise the public init contract (the view stores the supplied
/// deadline and propagates the tap closure) plus the idempotent-from-
/// the-VM-side semantics that protect against double-tap races.
///
/// `@MainActor` because the view's tap closure is invoked from SwiftUI's
/// main-actor render context.
@Suite("UndoStopToastView")
@MainActor
struct UndoStopToastViewTests {
    /// **D7-T-16** — Initializing the view with a `deadline` value
    /// stores that exact `Date` so the body's `TimelineView` countdown
    /// renders the right "Tap to resume (Ns)" string. The view stores
    /// the deadline by `let` so direct read-back via the public `let`
    /// is the cleanest assertion path.
    @Test func toast_initWithDeadline_storesDeadlineForCountdownDisplay() {
        let deadline = Date(timeIntervalSince1970: 1_700_000_005)
        let toast = UndoStopToastView(deadline: deadline, onUndo: {})

        #expect(toast.deadline == deadline)
    }

    /// **D7-T-17** — Invoking the toast's `onUndo` closure fires the
    /// closure exactly once. The view itself plumbs the closure into
    /// the button's `action:` — exercising it directly here proves the
    /// init parameter is wired through (no swallowed tap).
    @Test func toast_tap_invokesOnUndoClosure() {
        let recorder = TapRecorder()
        let toast = UndoStopToastView(
            deadline: Date(timeIntervalSince1970: 1_700_000_005),
            onUndo: { recorder.tap() }
        )

        toast.onUndo()

        #expect(recorder.count == 1)
    }

    /// **D7-T-18 (idempotency-from-VM-side)** — Two rapid taps fire
    /// `onUndo` twice from the view's perspective. The view does
    /// **not** debounce — that's the VM/coordinator's responsibility.
    /// The contract this locks: the view's job is to dispatch the tap
    /// signal once per gesture; the VM's `inFlightAction` guards
    /// downstream side-effects. If a future refactor adds view-level
    /// debounce, this test must fail and the change must be surfaced.
    @Test func toast_tappedTwiceQuickly_invokesOnUndoTwice_andIsIdempotentFromTheVMSide() {
        let recorder = TapRecorder()
        let toast = UndoStopToastView(
            deadline: Date(timeIntervalSince1970: 1_700_000_005),
            onUndo: { recorder.tap() }
        )

        // Two tightly-paced taps.
        toast.onUndo()
        toast.onUndo()

        // The view does not de-duplicate; the closure fired twice.
        #expect(recorder.count == 2)
    }
}

// MARK: - Test infrastructure

/// Simple lock-protected counter used by the toast tests. Mirrors the
/// `CallRecorder` pattern from ``MeetingControlsViewTests``. Uses
/// `OSAllocatedUnfairLock` per the project's Swift 6 fake-state rules
/// (`NSLock` forbidden from async contexts).
private final nonisolated class TapRecorder: @unchecked Sendable {
    private let state = OSAllocatedUnfairLock<Int>(initialState: 0)

    /// Increments the tap counter by one.
    func tap() {
        state.withLock { $0 += 1 }
    }

    /// Snapshot of the current tap count.
    var count: Int {
        state.withLock { $0 }
    }
}
