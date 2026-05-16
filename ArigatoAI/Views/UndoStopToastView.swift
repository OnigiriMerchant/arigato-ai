//
//  UndoStopToastView.swift
//  ArigatoAI
//
//  Created by Jose Castell on 2026/05/16.
//

import Foundation
import SwiftUI

/// Undo-stop toast shown over the meeting controls surface during
/// ``MeetingSessionPhase/stoppingWithUndoWindow``.
///
/// Per UI decision #8: when the user taps STOP, a 5-second toast appears
/// at the bottom of the screen reading "Meeting ended. Tap to resume."
/// Tap → meeting resumes. Window expires → STOP is final.
///
/// ## Ownership of dismissal
///
/// This view has **no internal dismissal logic** — it does not run its
/// own deadline timer to remove itself from the hierarchy. Dismissal is
/// owned by the parent (``MeetingControlsView``) which conditionally
/// renders the toast only when the session phase is
/// ``MeetingSessionPhase/stoppingWithUndoWindow``. When ``MeetingSession``
/// exits that phase (via undo or finalize), SwiftUI rebuilds the parent
/// without the toast.
///
/// This single-source-of-truth design prevents the two-timer race that
/// would otherwise emerge if the toast also armed its own dismissal
/// clock alongside ``MeetingSession``'s undo-window timer.
///
/// ## Countdown rendering
///
/// The body wraps the countdown text in `TimelineView(.periodic)` at
/// 1Hz so the remaining-seconds value updates without manual timer
/// state. The `deadline` parameter is the absolute `Date` at which the
/// undo window closes; `TimelineView`'s `context.date` is subtracted
/// from it to derive remaining seconds.
struct UndoStopToastView: View {
    /// Absolute wall-clock time at which the undo window expires.
    /// Sourced directly from the
    /// ``MeetingSessionPhase/stoppingWithUndoWindow(meetingID:startedAt:deadline:)``
    /// payload.
    let deadline: Date

    /// Tap handler. Production wiring routes this to
    /// ``MeetingControlsViewModel/tapUndo()``.
    let onUndo: () -> Void

    var body: some View {
        Button(action: onUndo) {
            TimelineView(.periodic(from: Date(), by: 1.0)) { context in
                HStack(spacing: 8) {
                    Image(systemName: "arrow.uturn.backward.circle.fill")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.tint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Meeting ended.")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(secondaryText(now: context.date))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.meterTrack)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 0.5)
                )
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Tap to resume the meeting before the undo window closes.")
        .accessibilityIdentifier("meeting.controls.undoToast")
    }

    /// Builds the secondary text — "Tap to resume (Ns)" — based on
    /// remaining seconds. When the deadline has passed (i.e., the
    /// parent has not yet torn the toast down because SwiftUI hasn't
    /// re-rendered), the text falls back to "Tap to resume" without a
    /// negative countdown.
    private func secondaryText(now: Date) -> String {
        let remaining = max(0, Int(deadline.timeIntervalSince(now).rounded(.up)))
        if remaining > 0 {
            return "Tap to resume (\(remaining)s)"
        }
        return "Tap to resume"
    }
}

// MARK: - Previews

#if DEBUG

    #Preview("Light — 5s remaining") {
        UndoStopToastView(
            deadline: Date(timeIntervalSinceNow: 5),
            onUndo: {}
        )
        .padding()
        .preferredColorScheme(.light)
    }

    #Preview("Dark — 5s remaining") {
        UndoStopToastView(
            deadline: Date(timeIntervalSinceNow: 5),
            onUndo: {}
        )
        .padding()
        .preferredColorScheme(.dark)
    }

    #Preview("Light — past deadline") {
        UndoStopToastView(
            deadline: Date(timeIntervalSinceNow: -1),
            onUndo: {}
        )
        .padding()
        .preferredColorScheme(.light)
    }

#endif
