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
/// ``MeetingListRow`` against a ``MeetingSummary`` DTO. Each row is wrapped
/// in a `NavigationLink(value: summary)` that pushes ``MeetingDetailView``
/// via the `.navigationDestination(for: MeetingSummary.self)` modifier
/// attached to the list content (Step 11). Swipe actions land in Step 13.
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
/// ## Step 12 — search
///
/// Step 12 adds a `.searchable` modifier two-way-bound to
/// ``MeetingListViewModel/searchText``. The view model's `didSet` on
/// `searchText` schedules a 300ms debounce that bumps
/// ``MeetingListViewModel/searchTrigger``. A second `.task(id:)` modifier
/// observes the search trigger and re-fires ``MeetingListViewModel/reload()``.
/// The reload reads the **current** `searchText` regardless of which
/// trigger source (auto-save → `refreshTrigger`, debounce → `searchTrigger`)
/// produced the bump, so filter state survives auto-save reloads. The
/// `ContentUnavailableView.search` branch renders when the user has typed
/// a query that produced zero matches; the original Step 6 empty-state
/// renders only when there are zero meetings AND no active search.
///
/// ## Read path
///
/// Reads route through ``MeetingStore/fetchAll(searchText:)``. The Step-6
/// ``MeetingStore/fetchAllUnfiltered()`` method is preserved as the
/// empty-needle code path of the new method, called internally when the
/// trimmed needle is empty (D12-3 — empty/whitespace contract). The
/// `@Query` macro is intentionally **not** used here — preserving the
/// `@ModelActor` seam is a Group D contract (decision D6-1 option (a)) so
/// cross-actor reads stay routed through the actor rather than through
/// the SwiftUI environment's model context.
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

    /// The actor-backed read source. Retained as a stored property so
    /// the Step 11 `.navigationDestination(for: MeetingSummary.self)` can
    /// hand it through to ``MeetingDetailView``'s production init.
    /// Optional because the test-only `init(model:)` does not need a
    /// live store — when `nil`, the destination resolves to an empty
    /// view (tap-navigation is a render-time-only concern under tests).
    private let store: MeetingStore?

    /// Production initializer — closes over the actor-backed store.
    ///
    /// - Parameter store: The actor-backed read source. Constructed
    ///   inline by ``ContentView`` for Step 6; lifted to
    ///   ``AppBootstrapper`` in Step 8 with the
    ///   `Task.detached` init pattern (Amendment 3). Retained for Step
    ///   11's row-tap navigation: the destination passes this same
    ///   store through to ``MeetingDetailView``.
    ///
    /// Step 12 changes the fetcher signature to take a `String` search
    /// text and trampoline to ``MeetingStore/fetchAll(searchText:)``.
    init(store: MeetingStore) {
        self.store = store
        _model = State(wrappedValue: MeetingListViewModel(
            fetcher: { needle in try await store.fetchAll(searchText: needle) }
        ))
    }

    /// Test-only / preview initializer — accepts a pre-built view model
    /// so callers can drive success, failure, and ordering behavior
    /// without owning a real `MeetingStore` actor.
    init(model: MeetingListViewModel) {
        store = nil
        _model = State(wrappedValue: model)
    }

    var body: some View {
        Group {
            if model.meetings.isEmpty && model.loadError == nil {
                // Step 12: when the user has typed a query that produced
                // zero results, the native iOS pattern is
                // `ContentUnavailableView.search`. Step 6's "No meetings yet"
                // empty state wins only when there are no meetings AND no
                // active search. `searchText` is the trimmed-untrimmed raw
                // bind value; the contract here is "user has typed
                // anything" so the raw isEmpty check is correct (not the
                // post-trim emptiness used by the store).
                if model.searchText.isEmpty {
                    emptyState
                } else {
                    ContentUnavailableView.search(text: model.searchText)
                }
            } else {
                listContent
            }
        }
        .navigationTitle("History")
        // Step 12: native iOS search bar two-way-bound to the VM's
        // `searchText`. Mutations there schedule a 300ms debounce that
        // ultimately bumps `searchTrigger`; SwiftUI's `.task(id:)` below
        // re-fires reload with the current search text.
        .searchable(
            text: $model.searchText,
            placement: .navigationBarDrawer(displayMode: .automatic),
            prompt: "Search meetings"
        )
        // Two `.task(id:)` modifiers, both calling reload(). SwiftUI manages
        // lifecycle per trigger; reload() reads the CURRENT `searchText`
        // regardless of which trigger fired, so auto-save reloads during
        // an active search keep the filter (see Assumption 2 violation
        // test `meetingListSearch_autoSaveReloadDuringActiveSearch_keepsFilter`).
        .task(id: model.searchTrigger) {
            await model.reload()
        }
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

    /// Main list content. Each row is a `NavigationLink(value:)` that
    /// pushes ``MeetingDetailView`` via the
    /// `.navigationDestination(for: MeetingSummary.self)` modifier
    /// attached below — the iOS 16+ "attach close to source" idiom keeps
    /// the destination resolution inside this view rather than at the
    /// `NavigationStack` root in ``ContentView`` (see
    /// ``ContentView`` for the stack root). Swipe actions land in
    /// Step 13.
    private var listContent: some View {
        List {
            ForEach(model.meetings, id: \.id) { summary in
                // Step 11: row-tap pushes the detail destination. The
                // value-based form (over the closure-label form) lets
                // SwiftUI route the value through `.navigationDestination`
                // below so destination construction is centralized.
                NavigationLink(value: summary) {
                    MeetingListRow(summary: summary)
                }
            }
        }
        // Step 11: the destination is attached inside ``MeetingListView``
        // (not on the ``NavigationStack`` in ``ContentView``) per the iOS
        // 16+ idiom — keeping the destination close to the source view
        // simplifies reasoning and avoids polluting the root with every
        // possible destination type. ``ContentView`` houses the stack
        // root only (cross-ref ``ContentView``).
        .navigationDestination(for: MeetingSummary.self) { summary in
            if let store {
                MeetingDetailView(summary: summary, store: store)
            } else {
                // Render-time fallback for the test-only `init(model:)`
                // path. Tests do not exercise navigation push; this
                // branch keeps the type system happy without forcing a
                // STOP on the test-only init shape.
                EmptyView()
            }
        }
    }
}

/// `Hashable` conformance for ``MeetingSummary``, required by
/// `NavigationLink(value:)` (Step 11). Declared in this file rather
/// than alongside the DTO definition because Step 11's MAY-NOT-modify
/// scope covers ``MeetingSummary`` itself; the extension lives at the
/// consumer site.
///
/// `hash(into:)` is implemented explicitly because cross-file
/// extensions of `Hashable` cannot trigger Swift's automatic synthesis
/// (the compiler requires the conformance and stored properties to be
/// visible together). All hashed fields are themselves `Hashable`
/// value types; ``MeetingSummary/id`` (a `PersistentIdentifier`) is
/// sufficient for uniqueness in the navigation context, but we hash
/// the full DTO shape so two distinct summaries that happen to share
/// an identifier (a programmer error caught nowhere else) remain
/// distinguishable to SwiftUI's value-based navigation.
extension MeetingSummary: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(startedAt)
        hasher.combine(endedAt)
        hasher.combine(title)
        hasher.combine(sentenceCount)
        // Step 12: include the body-match snippet so two summaries that
        // differ only in snippet don't collide in SwiftUI's value-based
        // navigation. Title-only / empty-needle paths leave this `nil`.
        hasher.combine(firstMatchSnippet)
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
/// `@MainActor` because all four published properties mutate from
/// SwiftUI's render context. The fetcher closure itself crosses to the
/// store's actor; the post-await assignment back to ``meetings`` /
/// ``loadError`` hops back to the main actor by virtue of the model's
/// isolation.
///
/// ## Step 12 — search additions
/// - ``searchText`` is two-way bound by `.searchable` in the view. Its
///   `didSet` schedules a 300ms debounce.
/// - ``searchTrigger`` is bumped by the debounce task once the quiet
///   window elapses. SwiftUI's `.task(id:)` on the view observes it and
///   re-fires ``reload()``.
/// - ``reload()``'s fetcher signature now takes `String` (the current
///   `searchText`). Both auto-save (``requestReload()``) and debounce
///   trigger sources flow through the same `reload()` method, so an
///   auto-save reload during an active search preserves the filter.
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
    ///
    /// Step 12: this is the **auto-save** trigger. The **search** trigger
    /// is ``searchTrigger``. Both call into the same ``reload()``.
    private(set) var refreshTrigger: UUID = .init()

    /// Two-way bound by `.searchable` in ``MeetingListView``. Each
    /// mutation schedules a 300ms debounce that bumps ``searchTrigger``.
    /// `reload()` reads this value at call time.
    var searchText: String = "" {
        didSet { scheduleSearchReload() }
    }

    /// Bumped by the debounce task once the 300ms quiet window elapses.
    /// SwiftUI's `.task(id: searchTrigger)` on the view observes it and
    /// re-fires ``reload()``.
    private(set) var searchTrigger: UUID = .init()

    /// The async fetcher reload calls. Stored as a Sendable closure so
    /// production can trampoline to ``MeetingStore/fetchAll(searchText:)``
    /// while tests inject ad-hoc closures (success / throw / sleep).
    /// Step 12: signature changed from `() async throws ...` to
    /// `(String) async throws ...` so the fetcher receives the current
    /// search text on every call.
    private let fetcher: @Sendable (String) async throws -> [MeetingSummary]

    /// In-flight debounce task. Cancelled and replaced on every
    /// `searchText` mutation.
    private var pendingSearch: Task<Void, Never>?

    /// Designated initializer.
    ///
    /// - Parameter fetcher: The Sendable async closure called by
    ///   ``reload()``. Production wiring closes over the
    ///   ``MeetingStore`` actor handle (Step 12 wires
    ///   ``MeetingStore/fetchAll(searchText:)``).
    init(fetcher: @escaping @Sendable (String) async throws -> [MeetingSummary]) {
        self.fetcher = fetcher
    }

    /// Pulls the latest summaries across the actor hop, passing the
    /// current ``searchText``. Errors are stored in ``loadError`` rather
    /// than thrown — SwiftUI views cannot throw, and the contract routes
    /// failures through the inline error state.
    ///
    /// ## Auto-save during active search
    /// The auto-save subscriber bumps ``refreshTrigger`` (NOT
    /// ``searchTrigger``) and this method then reads the **current**
    /// ``searchText`` regardless of which trigger source fired. Filter
    /// state therefore survives auto-save reloads. Named violation test:
    /// ``meetingListSearch_autoSaveReloadDuringActiveSearch_keepsFilter``.
    ///
    /// ## Cancellation semantics
    /// `CancellationError` is silently swallowed — debounce cancels are
    /// intentional, not user-visible. Other errors are captured into
    /// ``loadError`` and the prior ``meetings`` array is preserved
    /// (Step-12 behavior; matches Step-6's "errors surface inline" promise).
    func reload() async {
        do {
            let next = try await fetcher(searchText)
            // After the await, isolation has hopped back to the main
            // actor (because Self is @MainActor-isolated). It is safe to
            // mutate the published properties here without a further hop.
            meetings = next
            loadError = nil
        } catch is CancellationError {
            // Intentional cancellation — leave state untouched. Debounce
            // and `.task(id:)` reuse this path; user-visible state should
            // not flicker when SwiftUI tears down a stale task.
        } catch {
            loadError = error
        }
    }

    /// Bumps ``refreshTrigger`` to a fresh UUID, prompting SwiftUI's
    /// `.task(id:)` to re-run ``reload()``. Exposed so callers (Step 11+
    /// auto-save subscriber and tests) can request a reload without
    /// owning the underlying state.
    ///
    /// Step 12: this bumps the auto-save trigger only — `searchText`
    /// is not touched, so an in-flight search filter is preserved.
    func requestReload() {
        refreshTrigger = UUID()
    }

    /// Cancels the pending debounce task (if any) and schedules a new one
    /// that will bump ``searchTrigger`` after 300ms of quiet. Invoked by
    /// ``searchText``'s `didSet`.
    ///
    /// ## Scheduling assumption (Concurrency design discipline)
    /// Rapid mutations of ``searchText`` cancel the previous pending task
    /// before it can bump ``searchTrigger``, so only the **last**
    /// `searchText` value produces a fetcher invocation. The
    /// `try? await Task.sleep(...)` swallows the `CancellationError` and
    /// the guard exits early. Named violation test:
    /// ``meetingListSearch_rapidTyping_onlyLastQueryFires`` — drives 5
    /// rapid `searchText` mutations within 100ms and asserts the fetcher
    /// recorded exactly one invocation.
    private func scheduleSearchReload() {
        pendingSearch?.cancel()
        pendingSearch = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            guard let self else { return }
            self.searchTrigger = UUID()
        }
    }
}
