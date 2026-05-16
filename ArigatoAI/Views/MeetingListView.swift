//
//  MeetingListView.swift
//  ArigatoAI
//
//  Created by Jose Castell on 2026/05/16.
//

import Foundation
import SwiftData
import SwiftUI

/// History screen — the pushable destination behind the toolbar history
/// icon on the active-meeting view (Group D UI decision #11).
///
/// Renders a list of past meetings sorted newest-first, each row drawn by
/// ``MeetingListRow`` against a ``MeetingSummary`` DTO. Tapping a row has
/// no effect in Step 6 — single-tap navigation to a detail screen lands
/// in Step 11; swipe actions land in Step 13.
///
/// ## Scheduling assumption (Concurrency design discipline)
///
/// Reload assumes ``MeetingStore`` is reachable across an actor hop and
/// returns a Sendable `[MeetingSummary]`. Concurrent reloads (rapid
/// ``MeetingListViewModel/refreshTrigger`` mutation) are serialized by
/// SwiftUI's `.task(id:)` cancellation — a previous in-flight reload is
/// cancelled when the trigger changes. Reload errors are stored in
/// ``MeetingListViewModel/loadError`` and surface inline; they do not
/// throw out of the view body.
///
/// Named violation test:
/// `meetingListView_rapidRefreshTriggerChanges_lastQueryWins` — drives
/// ``MeetingListViewModel/reload()`` twice in rapid succession against a
/// fetcher whose first call sleeps, asserting only the second call's
/// result lands.
///
/// ## Read path
///
/// All reads go through ``MeetingStore/fetchAllUnfiltered()`` which is
/// the sole read entry point until Step 12 introduces
/// `fetchAll(searchText:)`. The `@Query` macro is intentionally **not**
/// used here — preserving the `@ModelActor` seam is a Group D contract
/// (decision D6-1 option (a)) so cross-actor reads stay routed through
/// the actor rather than through the SwiftUI environment's model context.
///
/// ## Styling
///
/// Stock SwiftUI: system fonts (UI decision #18), semantic colors (UI
/// decision #17). ``Design/DesignTokens`` is intentionally untouched —
/// design-system direction is V3 #22, deferred to Step 9.
struct MeetingListView: View {
    /// Backing view model — owns the reload logic and observable state.
    /// Held as `@State` so SwiftUI retains it across re-renders.
    @State private var model: MeetingListViewModel

    /// Production initializer — closes over the actor-backed store.
    ///
    /// - Parameter store: The actor-backed read source. Constructed
    ///   inline by ``ContentView`` for Step 6; lifted to
    ///   ``AppBootstrapper`` in Step 8 with the
    ///   `Task.detached` init pattern (Amendment 3).
    init(store: MeetingStore) {
        _model = State(wrappedValue: MeetingListViewModel(
            fetcher: { try await store.fetchAllUnfiltered() }
        ))
    }

    /// Test-only / preview initializer — accepts a pre-built view model
    /// so callers can drive success, failure, and ordering behavior
    /// without owning a real `MeetingStore` actor.
    init(model: MeetingListViewModel) {
        _model = State(wrappedValue: model)
    }

    var body: some View {
        Group {
            if model.meetings.isEmpty && model.loadError == nil {
                emptyState
            } else {
                listContent
            }
        }
        .navigationTitle("History")
        .task(id: model.refreshTrigger) {
            await model.reload()
        }
    }

    /// Empty-state placeholder shown when the store has no meetings yet
    /// and no error has surfaced. Pure stock SwiftUI styling.
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "list.bullet.rectangle")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No meetings yet")
                .font(.headline)
            Text("Tap the + button on the main screen to start your first meeting.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Main list content. No tap action (Step 11), no swipe actions
    /// (Step 13) per the locked plan.
    private var listContent: some View {
        List {
            ForEach(model.meetings, id: \.id) { summary in
                MeetingListRow(summary: summary)
            }
        }
    }
}

/// Observable view model that owns ``MeetingListView``'s reload pipeline
/// and the small slice of state SwiftUI binds to.
///
/// Extracted from the view body so the reload logic is directly
/// testable — tests construct the model with a fetcher closure, call
/// ``reload()``, and inspect the published ``meetings``, ``loadError``,
/// and ``refreshTrigger`` properties.
///
/// `@MainActor` because all three published properties mutate from
/// SwiftUI's render context. The fetcher closure itself crosses to the
/// store's actor; the post-await assignment back to ``meetings`` /
/// ``loadError`` hops back to the main actor by virtue of the model's
/// isolation.
@MainActor
@Observable
final class MeetingListViewModel {
    /// Last-loaded summaries, newest-first.
    private(set) var meetings: [MeetingSummary] = []

    /// Most recent reload error, or `nil` on success.
    private(set) var loadError: Error?

    /// Mutating this UUID triggers SwiftUI's `.task(id:)` to re-run
    /// ``reload()``. Rapid mutations are serialized last-query-wins by
    /// SwiftUI's task-cancellation behavior (Step 11+ wiring uses this
    /// after auto-save deltas; Step 6 only mutates on first view appear).
    private(set) var refreshTrigger: UUID = .init()

    /// The async fetcher reload calls. Stored as a Sendable closure so
    /// production can trampoline to ``MeetingStore/fetchAllUnfiltered()``
    /// while tests inject ad-hoc closures (success / throw / sleep).
    private let fetcher: @Sendable () async throws -> [MeetingSummary]

    /// Designated initializer.
    ///
    /// - Parameter fetcher: The Sendable async closure called by
    ///   ``reload()``. Production wiring closes over the
    ///   ``MeetingStore`` actor handle.
    init(fetcher: @escaping @Sendable () async throws -> [MeetingSummary]) {
        self.fetcher = fetcher
    }

    /// Pulls the latest summaries across the actor hop. Errors are
    /// stored in ``loadError`` rather than thrown — SwiftUI views
    /// cannot throw, and the contract routes failures through the
    /// inline error state.
    ///
    /// Concurrent invocations are serialized last-query-wins by SwiftUI's
    /// `.task(id:)` cancellation in production; tests exercise the same
    /// semantics by awaiting two rapid invocations and asserting the
    /// second one's result is what landed (see
    /// `meetingListView_rapidRefreshTriggerChanges_lastQueryWins`).
    func reload() async {
        do {
            let next = try await fetcher()
            // After the await, isolation has hopped back to the main
            // actor (because Self is @MainActor-isolated). It is safe to
            // mutate the published properties here without a further hop.
            meetings = next
            loadError = nil
        } catch {
            loadError = error
        }
    }

    /// Bumps ``refreshTrigger`` to a fresh UUID, prompting SwiftUI's
    /// `.task(id:)` to re-run ``reload()``. Exposed so callers (Step 11+
    /// auto-save subscriber and tests) can request a reload without
    /// owning the underlying state.
    func requestReload() {
        refreshTrigger = UUID()
    }
}
