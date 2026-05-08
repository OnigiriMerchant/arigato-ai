//
//  LevelEmitter.swift
//  ArigatoAI
//
//  Created by Jose Castell on 2026/05/09.
//

import Foundation

/// Throttles audio-level updates so the UI is not flooded with high-rate
/// emissions from the audio actor.
///
/// The emitter is a tiny state machine: each call to ``shouldEmit(now:)``
/// records the timestamp of the last accepted emission and rejects calls
/// that arrive sooner than ``minimumInterval``. The struct is `Sendable` so
/// the audio actor can hold it as a stored property.
public nonisolated struct LevelEmitter: Sendable {
    /// The minimum elapsed time between accepted emissions.
    public let minimumInterval: Duration
    private var lastEmission: ContinuousClock.Instant?

    /// Creates a new emitter.
    ///
    /// - Parameter targetHz: Approximate desired emission rate. Defaults to
    ///   `12 Hz`, which keeps SwiftUI animations smooth without saturating
    ///   the main actor.
    public init(targetHz: Double = 12.0) {
        let seconds = 1.0 / max(targetHz, 1.0)
        minimumInterval = .seconds(seconds)
    }

    /// Returns `true` and records `now` when the call falls outside the
    /// throttle window. Otherwise returns `false` and leaves state untouched.
    ///
    /// - Parameter now: The current ``ContinuousClock`` instant. Injected so
    ///   tests can drive the emitter with a deterministic clock.
    public mutating func shouldEmit(now: ContinuousClock.Instant) -> Bool {
        guard let last = lastEmission else {
            lastEmission = now
            return true
        }
        if now - last >= minimumInterval {
            lastEmission = now
            return true
        }
        return false
    }
}
