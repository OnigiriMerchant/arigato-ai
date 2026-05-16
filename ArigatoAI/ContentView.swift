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
/// ## Group D Step 6 — temporary inline store construction
///
/// `ContentView` constructs a ``MeetingStore`` inline from the
/// SwiftUI-environment `ModelContext`'s container. This is temporary
/// scaffolding for Step 6 only — Step 8 lifts the store (and the rest of
/// the coordinator wiring) into ``AppBootstrapper`` using the
/// `Task.detached` init pattern (Amendment 3) so the `@ModelActor`'s
/// executor does not inherit the main thread.
///
/// The inline construction satisfies Group D's locked decision D6-2
/// option a-inline. ``MeetingListView`` only needs the store (not the
/// full ``MeetingCoordinator``), so the lighter-weight wiring described
/// in dispatch-brief STOP #1's "Specifically allowed alternative" path
/// is taken — the coordinator and its audio/router/translator deps stay
/// on the Step 8 dispatch, not this one.
struct ContentView: View {
    /// The SwiftData context plumbed in by ``ArigatoAIApp`` via the
    /// `.modelContainer(...)` modifier. The container is fished out of
    /// the context to build the per-view ``MeetingStore`` actor handle.
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        NavigationStack {
            TranscriptLiveView()
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink {
                            MeetingListView(store: MeetingStore(modelContainer: modelContext.container))
                        } label: {
                            Image(systemName: "clock")
                                .accessibilityLabel("History")
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
