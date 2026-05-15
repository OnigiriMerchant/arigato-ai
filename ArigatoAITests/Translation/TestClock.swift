//
//  TestClock.swift
//  ArigatoAITests
//
//  Created by Jose Castell on 2026/05/16.
//

@testable import ArigatoAI
import Foundation
import os

/// Project-local `Clock` conformer for tests.
///
/// `Clock` protocol requirements: `Instant: InstantProtocol`, `now`,
/// `minimumResolution`, `sleep(until:tolerance:)`. We satisfy them
/// with a synthetic ``Instant`` (an offset from epoch zero) and a
/// continuation-based `sleep` that suspends until ``advance(by:)``
/// crosses the deadline.
///
/// Why not depend on swift-async-algorithms' TestClock? The user's
/// Risk #2 call (Group C plan, 2026-05-15): "Project-local TestClock
/// implementation. Reasons: avoid swift-clocks dependency overhead
/// for citizen-dev scope; flaky real-wait tests rejected; ~50 lines
/// in test target only, no production code impact."
final class TestClock: Clock, @unchecked Sendable {
    typealias Duration = Swift.Duration

    /// Synthetic instant. Stored as a `Duration` offset from an
    /// implicit epoch zero so the arithmetic stays inside the
    /// `Duration` type's well-tested overflow semantics.
    struct Instant: InstantProtocol {
        let offset: Duration

        func advanced(by duration: Duration) -> Instant {
            Instant(offset: offset + duration)
        }

        func duration(to other: Instant) -> Duration {
            other.offset - offset
        }

        static func < (lhs: Instant, rhs: Instant) -> Bool {
            lhs.offset < rhs.offset
        }
    }

    private struct State {
        var now: Instant = .init(offset: .zero)
        var pendingSleeps: [(deadline: Instant, continuation: CheckedContinuation<Void, any Error>)] = []
    }

    private let state = OSAllocatedUnfairLock<State>(initialState: State())

    var now: Instant {
        state.withLock { $0.now }
    }

    var minimumResolution: Duration {
        .milliseconds(1)
    }

    func sleep(until deadline: Instant, tolerance _: Duration?) async throws {
        try await withCheckedThrowingContinuation { continuation in
            let shouldFireImmediately = state.withLock { state -> Bool in
                if !(state.now < deadline) {
                    return true
                }
                state.pendingSleeps.append((deadline: deadline, continuation: continuation))
                return false
            }
            if shouldFireImmediately {
                continuation.resume()
            }
        }
    }

    /// Advances synthetic time; resumes any pending sleeps whose
    /// deadlines fell at or before the new ``now``.
    func advance(by duration: Duration) {
        let toFire = state.withLock { state -> [(deadline: Instant, continuation: CheckedContinuation<Void, any Error>)] in
            state.now = state.now.advanced(by: duration)
            var firing: [(deadline: Instant, continuation: CheckedContinuation<Void, any Error>)] = []
            var remaining: [(deadline: Instant, continuation: CheckedContinuation<Void, any Error>)] = []
            for sleep in state.pendingSleeps {
                if !(state.now < sleep.deadline) {
                    firing.append(sleep)
                } else {
                    remaining.append(sleep)
                }
            }
            state.pendingSleeps = remaining
            return firing
        }
        for sleep in toFire {
            sleep.continuation.resume()
        }
    }
}
