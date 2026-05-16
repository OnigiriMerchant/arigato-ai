//
//  ContentView.swift
//  ArigatoAI
//
//  Created by Jose Castell on 2026/05/06.
//

import SwiftData
import SwiftUI

/// Top-level app surface for Arigato AI. Phase 4 hosts the live
/// transcription experience via ``TranscriptLiveView``; the bootstrapper
/// flows in from ``ArigatoAIApp`` through the SwiftUI environment, so this
/// view is a thin wrapper.
///
/// ## Group D Step 6 — navigation
///
/// The body is wrapped in a `NavigationStack` so the active-meeting view
/// remains the root and a history icon in the top-right toolbar pushes
/// ``MeetingListView`` as a destination. This honors UI decision #11 —
/// active-meeting view is root; history is pushable, never reversed.
///
/// ## Group D Step 8 — bootstrapper-driven optional-coordinator ladder
///
/// Step 6's inline ``MeetingStore`` construction and Step 7's
/// ``MeetingControlsViewModel/disabled()`` placeholder are both lifted in
/// Step 8 — both surfaces now read from the shared ``AppBootstrapper``.
///
/// **Controls surface (D8-2 option a).** The view derives the controls
/// VM each render: `bootstrapper.coordinator.map { .wiring(coordinator: $0) } ?? .disabled()`.
/// Until ``AppBootstrapper/coordinator`` is published, the controls
/// surface falls back to ``MeetingControlsViewModel/disabled()`` — a no-op
/// stand-in whose action closures are all empty. Once
/// ``AppBootstrapper/startPrewarm(variant:)`` finishes warmup and
/// publishes the coordinator, SwiftUI re-renders against
/// ``MeetingControlsViewModel/wiring(coordinator:)``. The window is
/// sub-50ms in production (detached ``MeetingStore`` init + a single
/// main-actor hop per Amendment 3 / FB13399899).
///
/// **History destination.** The toolbar history icon is rendered only
/// when ``AppBootstrapper/meetingStore`` is non-nil. The detached-init
/// window is imperceptible because the idle-phase active-meeting view
/// has no transcript content to navigate away from yet.
struct ContentView: View {
    /// The shared bootstrapper threaded in from ``ArigatoAIApp`` via
    /// the SwiftUI environment. ``AppBootstrapper/coordinator`` drives
    /// the optional-coordinator ladder for the controls surface and
    /// ``AppBootstrapper/meetingStore`` gates the history toolbar item.
    @Environment(AppBootstrapper.self) private var bootstrapper

    var body: some View {
        // D8-2 option (a): derive the wired VM each render. SwiftUI
        // re-renders against `wiring(coordinator:)` once the
        // bootstrapper publishes the coordinator.
        let controlsModel = bootstrapper.coordinator.map {
            MeetingControlsViewModel.wiring(coordinator: $0)
        } ?? MeetingControlsViewModel.disabled()

        NavigationStack {
            TranscriptLiveView(controlsModel: controlsModel)
                .toolbar {
                    if let store = bootstrapper.meetingStore {
                        ToolbarItem(placement: .topBarTrailing) {
                            NavigationLink {
                                MeetingListView(store: store)
                            } label: {
                                Image(systemName: "clock")
                                    .accessibilityLabel("History")
                            }
                        }
                    }
                }
        }
    }
}

#Preview {
    ContentView()
        .environment(AppBootstrapper())
}
