//
//  PendingDeletionToast.swift
//  ArigatoAI
//
//  Created by Jose Castell on 2026/05/25.
//

import Foundation
import SwiftUI

/// Undo toast shown over ``MeetingListView`` after a swipe-to-delete
/// (MVP-1 feature #8). Reads "Deleted "<title>"" with a text-only "Undo"
/// affordance and a thin shrinking progress bar along the bottom edge
/// that tracks the remaining undo window.
///
/// ## Ownership of dismissal
///
/// This view has **no internal dismissal logic** — it does not run its
/// own deadline timer to remove itself from the hierarchy, and it does
/// not commit the deletion. Both are owned by ``MeetingListViewModel``,
/// which holds the single 5-second `Task` and conditionally renders this
/// toast only while ``MeetingListViewModel/pendingDeletion`` is non-nil.
/// When the model commits or undoes the deletion, SwiftUI rebuilds the
/// parent without the toast.
///
/// This single-source-of-truth design mirrors ``UndoStopToastView`` and
/// prevents the two-timer race that would otherwise emerge if the toast
/// also armed its own dismissal clock alongside the model's undo-window
/// timer.
///
/// ## Progress-bar rendering
///
/// The body wraps the bar in `TimelineView(.periodic)` at ~10Hz so the
/// bar shrinks smoothly without manual timer state. The bar's fractional
/// width is derived from the SAME deadline math the model uses: the
/// remaining interval (`deadline − context.date`) divided by the total
/// `window`. `start` is reconstructed as `deadline − window` so no
/// separate clock is needed. When the deadline has passed (i.e., the
/// model has not yet torn the toast down because SwiftUI hasn't
/// re-rendered), the fraction clamps to `0` rather than going negative.
struct PendingDeletionToast: View {
    /// Absolute wall-clock time at which the undo window expires. Sourced
    /// directly from ``MeetingListViewModel/PendingDeletion/deadline``.
    let deadline: Date

    /// Total length of the undo window. Used as the denominator for the
    /// progress bar's fractional width and to reconstruct the window's
    /// start (`deadline − window`). Sourced from
    /// ``MeetingListViewModel`` so the view stays dumb.
    let window: Duration

    /// User-facing message, e.g. `"Deleted "Standup""` or
    /// `"Meeting deleted"` when the title is empty. Built by the parent.
    let message: String

    /// Tap handler for the "Undo" button. Production wiring routes this
    /// to ``MeetingListViewModel/undoPendingDeletion()``.
    let onUndo: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // `ViewThatFits` picks the horizontal single-row layout at
            // normal Dynamic Type sizes and falls back to the vertical
            // layout (message stacked above the Undo control) once the row
            // can no longer fit at AX sizes. The vertical fallback keeps
            // the full title legible — at AX 3 the horizontal HStack would
            // squeeze the message to "Deleted…", losing the title, while
            // Undo stayed reachable. Both layouts keep Undo reachable.
            ViewThatFits(in: .horizontal) {
                horizontalContent
                verticalContent
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            progressBar
        }
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.meterTrack)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(message). Tap Undo to restore before the window closes.")
        .accessibilityIdentifier("meeting.list.undoDeleteToast")
    }

    /// Single-row layout used at normal Dynamic Type sizes: icon, message,
    /// and a trailing Undo control on one line. The message wraps to two
    /// lines before `ViewThatFits` gives up and switches to
    /// ``verticalContent``, so mid-range sizes stay on one row without
    /// truncating to "Deleted…".
    private var horizontalContent: some View {
        HStack(spacing: 8) {
            icon
            messageText
                .lineLimit(2)
            Spacer(minLength: 8)
            undoButton
        }
    }

    /// AX-size fallback: the message stacks above the Undo control so the
    /// full title stays legible instead of collapsing to "Deleted…". Undo
    /// remains reachable, trailing-aligned beneath the message.
    private var verticalContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                icon
                messageText
            }
            HStack {
                Spacer(minLength: 0)
                undoButton
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Leading trash glyph. Kept `.secondary` intentionally — a delete
    /// toast should not accent its icon; the accent stays on Undo.
    private var icon: some View {
        Image(systemName: "trash.circle.fill")
            .font(.body.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    /// The user-facing message Text. No fixed `lineLimit` here — the
    /// horizontal layout caps it at 2 lines, the vertical fallback lets it
    /// flow freely.
    private var messageText: some View {
        Text(message)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
    }

    /// The Undo affordance — the sole accented (`.tint`) element.
    private var undoButton: some View {
        Button(action: onUndo) {
            Text("Undo")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.tint)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("meeting.list.undoDeleteButton")
        .accessibilityLabel("Undo deletion")
    }

    /// Thin shrinking bar along the bottom edge. Driven by the same
    /// `TimelineView` deadline math the model uses — there is no separate
    /// timer here. Width = `remaining / total`, clamped to `[0, 1]`.
    ///
    /// The bar is masked to the card's **bottom** corner radius (12pt)
    /// via an ``UnevenRoundedRectangle`` so it never overshoots past the
    /// card's rounded corners. The mask is applied to the bar only — the
    /// card's own `RoundedRectangle` background/overlay stay byte-identical
    /// to ``UndoStopToastView``, so no border drift is introduced.
    private var progressBar: some View {
        TimelineView(.periodic(from: Date(), by: 0.1)) { context in
            GeometryReader { proxy in
                Capsule()
                    .fill(.tint)
                    .frame(width: proxy.size.width * fraction(now: context.date))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(height: 2)
        .mask(
            UnevenRoundedRectangle(
                bottomLeadingRadius: 12,
                bottomTrailingRadius: 12,
                style: .continuous
            )
        )
    }

    /// Remaining fraction of the undo window, clamped to `[0, 1]`.
    ///
    /// `remaining = deadline − now`; `total = window` in seconds. When
    /// `total` is non-positive (defensive — the model always passes a
    /// positive window) the fraction is `0` so the bar is empty rather
    /// than dividing by zero.
    private func fraction(now: Date) -> Double {
        let total = totalSeconds
        guard total > 0 else { return 0 }
        let remaining = deadline.timeIntervalSince(now)
        return min(1, max(0, remaining / total))
    }

    /// Total window length in seconds, derived from the `Duration`'s
    /// attoseconds-precision components.
    private var totalSeconds: Double {
        let components = window.components
        return Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}

// MARK: - Previews

#if DEBUG

    #Preview("Light — 5s remaining") {
        PendingDeletionToast(
            deadline: Date(timeIntervalSinceNow: 5),
            window: .seconds(5),
            message: "Deleted \"Q3 Planning Standup\"",
            onUndo: {}
        )
        .padding()
        .preferredColorScheme(.light)
    }

    #Preview("Dark — 5s remaining") {
        PendingDeletionToast(
            deadline: Date(timeIntervalSinceNow: 5),
            window: .seconds(5),
            message: "Deleted \"Q3 Planning Standup\"",
            onUndo: {}
        )
        .padding()
        .preferredColorScheme(.dark)
    }

    #Preview("Light — empty title") {
        PendingDeletionToast(
            deadline: Date(timeIntervalSinceNow: 2),
            window: .seconds(5),
            message: "Meeting deleted",
            onUndo: {}
        )
        .padding()
        .preferredColorScheme(.light)
    }

    #Preview("AX 3 — message stays legible") {
        PendingDeletionToast(
            deadline: Date(timeIntervalSinceNow: 5),
            window: .seconds(5),
            message: "Deleted \"Q3 Planning Standup\"",
            onUndo: {}
        )
        .padding()
        .preferredColorScheme(.light)
        .dynamicTypeSize(.accessibility3)
    }

#endif
