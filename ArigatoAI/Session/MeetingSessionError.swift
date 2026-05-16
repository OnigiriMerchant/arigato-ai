//
//  MeetingSessionError.swift
//  ArigatoAI
//
//  Created by Jose Castell on 2026/05/16.
//

import Foundation

/// Errors thrown by ``MeetingSession``.
///
/// The associated values are `String` descriptors rather than
/// ``MeetingSessionPhase`` values so the type stays trivially
/// `Equatable` and so we do not drag `PersistentIdentifier` /
/// `Date` payloads into error values that may be logged or compared.
///
/// - ``invalidStateTransition(from:attempted:)`` fires when a public
///   API on ``MeetingSession`` is invoked from a phase that does not
///   permit the transition (for example calling `pause(at:)` from
///   ``MeetingSessionPhase/idle``).
/// - ``storeFailure(underlying:)`` wraps the `localizedDescription` of
///   any error raised by the injected `MeetingStore`.
/// - ``noActiveMeeting`` is a safety net for paths that should only
///   run while a meeting is active but find the phase has changed
///   underneath them.
public nonisolated enum MeetingSessionError: Error, Sendable, Equatable {
    /// The state machine refused a requested transition. `from` is the
    /// label of the current ``MeetingSessionPhase``; `attempted` names
    /// the public API the caller invoked (for example `"pause"`,
    /// `"undoStop"`).
    case invalidStateTransition(from: String, attempted: String)

    /// The underlying `MeetingStore` raised an error during a
    /// persistence call. The original error's `localizedDescription`
    /// is captured as a `String` to keep the error trivially `Equatable`.
    case storeFailure(underlying: String)

    /// A code path that requires an active meeting found
    /// ``MeetingSessionPhase/idle`` (or ``MeetingSessionPhase/ended``).
    /// Used as a defensive guard in paths that are normally guarded by
    /// state-machine checks.
    case noActiveMeeting
}
