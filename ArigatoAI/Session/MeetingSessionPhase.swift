//
//  MeetingSessionPhase.swift
//  ArigatoAI
//
//  Created by Jose Castell on 2026/05/16.
//

import Foundation
import SwiftData

/// The lifecycle phase of a ``MeetingSession``.
///
/// The phase is the single source of truth for "is a meeting active, and
/// if so in what mode?". It is exposed as an `@Observable` property on
/// ``MeetingSession`` so SwiftUI can drive button morphing (Group D UI
/// decision #4) and the status badge (decision #3) directly off the
/// observed value.
///
/// ## States
/// - ``idle``: no active meeting (first launch, after `newTranscript()`).
/// - ``recording``: audio capture + translation in progress.
/// - ``paused``: pause is a UI state only (decision #7) — audio capture
///   is halted, the translation actor stays alive, the SwiftData row
///   stays open.
/// - ``stoppingWithUndoWindow``: STOP was tapped; an undo toast (decision
///   #8, 5-second window) is on screen. If the user taps Undo we
///   transition back to ``recording``; if the deadline expires we
///   transition to ``ended``.
/// - ``ended``: meeting is finalized; transcript view stays mounted
///   (decision #5) so the user can share or start a new transcript.
///
/// `Equatable` synthesis applies because `PersistentIdentifier` and
/// `Date` are both `Equatable` value types.
public nonisolated enum MeetingSessionPhase: Sendable, Equatable {
    /// No active meeting.
    case idle

    /// Audio capture + translation in progress against the identified meeting row.
    case recording(meetingID: PersistentIdentifier, startedAt: Date)

    /// Meeting is paused — UI-only state per decision #7. The SwiftData
    /// row stays open; translation actor stays alive.
    case paused(meetingID: PersistentIdentifier, startedAt: Date, pausedAt: Date)

    /// STOP has been requested; the undo toast is showing until
    /// `deadline`. If the user calls `undoStop()` before `deadline` we
    /// return to ``recording``; if the deadline fires we transition to
    /// ``ended``.
    case stoppingWithUndoWindow(meetingID: PersistentIdentifier, startedAt: Date, deadline: Date)

    /// Meeting has been finalized.
    case ended(meetingID: PersistentIdentifier, startedAt: Date, endedAt: Date)

    /// Short, human-readable phase label used by
    /// ``MeetingSessionError/invalidStateTransition(from:attempted:)`` to
    /// avoid dragging non-`Equatable`-friendly payloads through the
    /// error type. Keep these strings stable — they appear in error
    /// values and are matched against in tests.
    var label: String {
        switch self {
        case .idle: return "idle"
        case .recording: return "recording"
        case .paused: return "paused"
        case .stoppingWithUndoWindow: return "stoppingWithUndoWindow"
        case .ended: return "ended"
        }
    }
}
