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

    /// Drives the commit-on-background edge case (MVP-1 feature #8). When
    /// the scene leaves the foreground (`.background` / `.inactive`) any
    /// pending deletion is committed immediately so an app-switch / lock
    /// does not leave an un-committed delete dangling.
    @Environment(\.scenePhase) private var scenePhase

    /// The actor-backed read source. Retained as a stored property so
    /// the Step 11 `.navigationDestination(for: MeetingSummary.self)` can
    /// hand it through to ``MeetingDetailView``'s production init.
    /// Optional because the test-only `init(model:)` does not need a
    /// live store — when `nil`, the destination resolves to an empty
    /// view (tap-navigation is a render-time-only concern under tests).
    private let store: MeetingStore?

    /// Bootstrapper threaded in from ``ArigatoAIApp`` via the SwiftUI
    /// environment. Used by Step 15's gear toolbar item to resolve the
    /// ``StorageStatsProviding`` + the live ``MeetingStore`` for
    /// ``SettingsView``. Mirrors ``ContentView``'s
    /// `@Environment(AppBootstrapper.self)` precedent so the destination
    /// stays out of ``ContentView``'s scope (MAY-NOT-modify per the
    /// dispatch brief). The test-only `init(model:)` callers do not
    /// render the toolbar item (no `store`, gear gated on
    /// `bootstrapper.meetingStore != nil`).
    @Environment(AppBootstrapper.self) private var bootstrapper

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
            fetcher: { needle in try await store.fetchAll(searchText: needle) },
            deleter: { id in try await store.deleteMeeting(meetingID: id) }
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
            if model.visibleMeetings.isEmpty && model.loadError == nil {
                // Step 12: when the user has typed a query that produced
                // zero results, the native iOS pattern is
                // `ContentUnavailableView.search`. Step 6's "No meetings yet"
                // empty state wins only when there are no meetings AND no
                // active search. `searchText` is the trimmed-untrimmed raw
                // bind value; the contract here is "user has typed
                // anything" so the raw isEmpty check is correct (not the
                // post-trim emptiness used by the store).
                //
                // Feature #8: the check uses `visibleMeetings` (not
                // `meetings`) so swiping away the last row flips to the
                // empty state behind the still-visible undo toast. That is
                // intentional — the toast overlay below renders regardless
                // of which branch this `Group` picks.
                if model.searchText.isEmpty {
                    emptyState
                } else {
                    ContentUnavailableView.search(text: model.searchText)
                }
            } else {
                listContent
            }
        }
        // Feature #8: the undo toast is overlaid on the whole screen so it
        // shows over both the list branch and the empty-state branch (last
        // row swiped). The toast is dumb — it owns no timer; dismissal is
        // driven by the model clearing `pendingDeletion`.
        .overlay(alignment: .bottom) {
            if let pending = model.pendingDeletion {
                PendingDeletionToast(
                    deadline: pending.deadline,
                    window: model.undoWindowForToast,
                    message: deletionMessage(for: pending.summary),
                    onUndo: { model.undoPendingDeletion() }
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: model.pendingDeletion)
        // Feature #8: commit any pending deletion when the scene leaves the
        // foreground so an app-switch / lock does not strand the delete.
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background || newPhase == .inactive {
                Task { await model.commitPendingDeletionNow() }
            }
        }
        // Feature #8: leaving History (pop, or starting a new meeting,
        // which requires leaving History) commits the pending deletion.
        .onDisappear {
            Task { await model.commitPendingDeletionNow() }
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
        // Step 15: gear toolbar that pushes ``SettingsView``. Gated on
        // `bootstrapper.meetingStore != nil` so the gear is absent
        // during pre-warmup (when Settings has no live store to read
        // the transcript count from) and during the test-only
        // `init(model:)` path (which renders the list without
        // installing a bootstrapper). Placement is `.topBarLeading`
        // per UI #19 so the existing trailing slots stay available
        // for Step 13's swipe-action surface and any future affordances.
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if let store = bootstrapper.meetingStore {
                    NavigationLink {
                        SettingsView(
                            statsProvider: bootstrapper.storageStatsProvider,
                            meetingStore: store
                        )
                    } label: {
                        Image(systemName: "gear")
                            .accessibilityLabel("Settings")
                    }
                }
            }
        }
    }

    /// Builds the undo-toast message for a pending deletion. Uses the
    /// meeting title in quotes when non-empty, else a generic fallback.
    private func deletionMessage(for summary: MeetingSummary) -> String {
        let trimmed = summary.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "Meeting deleted"
        }
        return "Deleted \"\(trimmed)\""
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
            ForEach(model.visibleMeetings, id: \.id) { summary in
                // Step 11: row-tap pushes the detail destination. The
                // value-based form (over the closure-label form) lets
                // SwiftUI route the value through `.navigationDestination`
                // below so destination construction is centralized.
                NavigationLink(value: summary) {
                    MeetingListRow(summary: summary)
                }
                // Feature #8: trailing swipe → soft-delete with a 5s undo
                // window. `allowsFullSwipe` lets a long swipe trigger
                // delete directly. The actual store delete is deferred by
                // the model until the window closes (or another swipe
                // supersedes it); see ``MeetingListViewModel/requestDelete(_:)``.
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        model.requestDelete(summary)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
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
    /// A single in-flight swipe-to-delete awaiting its undo window
    /// (MVP-1 feature #8). Holds the removed summary so undo can restore
    /// the row and commit can resolve the store delete, plus the absolute
    /// `deadline` at which the window closes (consumed by
    /// ``PendingDeletionToast`` for its shrinking progress bar).
    struct PendingDeletion: Equatable {
        /// The summary swiped away — still present in ``meetings`` but
        /// filtered out of ``visibleMeetings`` until commit drops it.
        let summary: MeetingSummary
        /// Absolute wall-clock time the undo window closes. `.now +
        /// undoWindow` at arming time.
        let deadline: Date
    }

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

    // MARK: - Swipe-to-delete + undo (MVP-1 feature #8)

    /// The single in-flight swipe-to-delete awaiting its undo window, or
    /// `nil` when nothing is pending. **At most one** — a fresh swipe
    /// commits any prior pending deletion immediately (last-wins) before
    /// installing itself here. The view renders ``PendingDeletionToast``
    /// while this is non-nil and iterates ``visibleMeetings`` so the
    /// pending row stays hidden.
    private(set) var pendingDeletion: PendingDeletion?

    /// The single undo-window timer. Sleeps ``undoWindow`` then commits
    /// the pending deletion. Cancelled by ``undoPendingDeletion()``,
    /// ``commitPendingDeletionNow()``, and by a superseding
    /// ``requestDelete(_:)``. Stored separately from ``pendingDeletion``
    /// so cancellation is cheap and the value type stays `Equatable`.
    private var deletionTimer: Task<Void, Never>?

    /// Resolves the store-side delete when a pending deletion commits.
    /// `nil` in fetcher-only test construction — committing then updates
    /// only local state (drops the ID from ``meetings``) and skips the
    /// store call. Production wiring closes over
    /// ``MeetingStore/deleteMeeting(meetingID:)``.
    private let deleter: (@Sendable (PersistentIdentifier) async throws -> Void)?

    /// IDs whose store-side commit is currently in flight. Used as an
    /// idempotency guard so the same ID is never handed to ``deleter``
    /// twice when overlapping triggers (the 5s timer, the
    /// `scenePhase`→background handler, and `.onDisappear`) all race to
    /// commit the same pending deletion. An ID is inserted before the
    /// `await deleter` and removed via `defer` after it returns;
    /// ``visibleMeetings`` also filters on this set so the row stays
    /// continuously hidden for the full duration of the in-flight commit
    /// (the `pendingDeletion` slot is cleared synchronously before the
    /// await, so the in-flight set is what keeps the row out of view
    /// during the window between clear and store-completion).
    private var committingIDs: Set<PersistentIdentifier> = []

    /// Length of the undo window. Production leaves the 5-second default;
    /// tests inject a short window to exercise the timeout-commit path
    /// without a real 5-second wait.
    private let undoWindow: Duration

    /// Read-only view of ``undoWindow`` for ``PendingDeletionToast`` to
    /// size its shrinking progress bar (`remaining / window`). Exposed
    /// because the bar's denominator is the full window, and the toast is
    /// dumb — it computes nothing about timing it isn't handed.
    var undoWindowForToast: Duration {
        undoWindow
    }

    /// Summaries the view should render: ``meetings`` with the
    /// currently-pending deletion's ID filtered out AND any IDs whose
    /// store-side commit is in flight (``committingIDs``). The view
    /// iterates **this**, not ``meetings``, so a ``reload()`` fired by the
    /// auto-save subscriber that re-fetches the not-yet-committed meeting
    /// does NOT make the swiped row reappear — the row is hidden purely by
    /// the pending-ID filter regardless of what ``meetings`` contains.
    ///
    /// The ``committingIDs`` term keeps the row hidden continuously while
    /// ``commitPendingDeletionNow()`` clears ``pendingDeletion``
    /// synchronously *before* its `await deleter`: without it, the row
    /// would briefly reappear in the window between clearing the pending
    /// slot and the store delete completing.
    var visibleMeetings: [MeetingSummary] {
        meetings.filter { $0.id != pendingDeletion?.summary.id && !committingIDs.contains($0.id) }
    }

    /// Designated initializer.
    ///
    /// - Parameters:
    ///   - fetcher: The Sendable async closure called by ``reload()``.
    ///     Production wiring closes over the ``MeetingStore`` actor handle
    ///     (Step 12 wires ``MeetingStore/fetchAll(searchText:)``).
    ///   - deleter: Optional Sendable async closure called when a pending
    ///     deletion commits. Production wires
    ///     ``MeetingStore/deleteMeeting(meetingID:)``; `nil` in
    ///     fetcher-only test construction (commit then updates local
    ///     state only).
    ///   - undoWindow: Length of the undo window. Defaults to 5 seconds
    ///     (the UI contract); tests inject a short window to drive the
    ///     timeout-commit path quickly.
    init(
        fetcher: @escaping @Sendable (String) async throws -> [MeetingSummary],
        deleter: (@Sendable (PersistentIdentifier) async throws -> Void)? = nil,
        undoWindow: Duration = .seconds(5)
    ) {
        self.fetcher = fetcher
        self.deleter = deleter
        self.undoWindow = undoWindow
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

    // MARK: - Swipe-to-delete + undo state machine

    /// Handles a swipe-to-delete on `summary`. Installs `summary` as the
    /// sole ``pendingDeletion`` and arms a single ``undoWindow`` timer
    /// that commits the delete when it fires. The row vanishes
    /// immediately (it is excluded from ``visibleMeetings``) but is not
    /// committed to the store until the window closes or
    /// ``commitPendingDeletionNow()`` runs; ``undoPendingDeletion()``
    /// restores it.
    ///
    /// ## Scheduling assumption (Concurrency design discipline)
    ///
    /// This design assumes **at most one** pending deletion and **at most
    /// one** timer `Task`. The armed `undoWindow` `Task` assumes no second
    /// `requestDelete(_:)` arrives before it fires.
    ///
    /// **When that assumption is violated** (a second swipe arrives while
    /// one is still pending), the policy is **last-wins**: the prior
    /// pending deletion is committed *immediately* (its store delete is
    /// awaited and its ID dropped from ``meetings`` on success), its timer
    /// cancelled, and only the newest swipe becomes the undoable
    /// ``pendingDeletion`` with a fresh window. Only the newest is ever
    /// undoable; older swipes are already gone. ``undoPendingDeletion()``
    /// and ``commitPendingDeletionNow()`` both cancel the timer so it
    /// cannot double-fire.
    ///
    /// **Concurrent-trigger idempotency.** Beyond a superseding swipe, the
    /// same pending deletion can be driven to commit by three overlapping
    /// triggers — the undo-window timer, the `scenePhase`→background
    /// handler, and `.onDisappear`. ``commitPendingDeletionNow()`` clears
    /// ``pendingDeletion`` synchronously before its await (so a second
    /// trigger early-outs on its `guard`) and ``commit(_:)`` guards on the
    /// in-flight ``committingIDs`` set, so ``deleter`` fires **at most once
    /// per ID** regardless of how the triggers interleave. The row stays
    /// hidden continuously because ``visibleMeetings`` filters on
    /// ``committingIDs`` for the in-flight duration. See
    /// ``MeetingListDeleteTests/meetingListDelete_concurrentCommitNow_deletesExactlyOnce``.
    ///
    /// Named violation test:
    /// ``MeetingListDeleteTests/meetingListDelete_rapidDoubleSwipe_firstCommitsImmediately_secondPends``
    /// — issues two `requestDelete(_:)` calls back-to-back and asserts the
    /// first ID is committed (recorded by the test deleter) while the
    /// second is the sole `pendingDeletion`, not yet committed, with both
    /// excluded from `visibleMeetings`.
    func requestDelete(_ summary: MeetingSummary) {
        // Last-wins: capture any prior pending deletion, then synchronously
        // install the new one and arm its window so `visibleMeetings`
        // hides the new row immediately and no commit-Task ordering race
        // can leave the wrong row pending. The prior deletion's store
        // commit is performed off the captured value (not via the live
        // `pendingDeletion`, which now holds the new row).
        let prior = pendingDeletion
        deletionTimer?.cancel()
        deletionTimer = nil
        pendingDeletion = nil

        armPendingDeletion(summary)

        if let prior {
            Task { [weak self] in
                guard let self else { return }
                await self.commit(prior)
            }
        }
    }

    /// Installs `summary` as the pending deletion and arms the single
    /// undo-window timer. Separated from ``requestDelete(_:)`` so the
    /// supersede-then-arm ordering reads in one place.
    private func armPendingDeletion(_ summary: MeetingSummary) {
        let window = undoWindow
        let deadline = Date.now.addingTimeInterval(Self.seconds(from: window))
        pendingDeletion = PendingDeletion(summary: summary, deadline: deadline)
        deletionTimer = Task { [weak self] in
            try? await Task.sleep(for: window)
            guard !Task.isCancelled else { return }
            guard let self else { return }
            await self.commitPendingDeletionNow()
        }
    }

    /// Converts a `Duration` to a `TimeInterval` (seconds) for `Date`
    /// math. Uses the `Duration`'s attoseconds-precision components.
    private static func seconds(from duration: Duration) -> TimeInterval {
        let components = duration.components
        return TimeInterval(components.seconds)
            + TimeInterval(components.attoseconds) / 1e18
    }

    /// Cancels the pending deletion before its window closes. The timer
    /// `Task` is cancelled and ``pendingDeletion`` cleared; the row
    /// reappears via ``visibleMeetings`` because it was never dropped from
    /// ``meetings``. No store delete is performed.
    func undoPendingDeletion() {
        deletionTimer?.cancel()
        deletionTimer = nil
        pendingDeletion = nil
    }

    /// Commits the pending deletion right now — used by the timeout path,
    /// by scene-backgrounding / view-disappear, and by a superseding
    /// ``requestDelete(_:)``. Cancels the timer, clears ``pendingDeletion``
    /// **synchronously** (so a second concurrent trigger early-outs on the
    /// `guard`), then awaits the store commit via ``commit(_:)``.
    ///
    /// ## Concurrent-trigger convergence (Concurrency design discipline)
    ///
    /// Three triggers can fire for the same pending deletion: the 5-second
    /// undo-window timer, the `scenePhase`→`.background`/`.inactive`
    /// handler, and `.onDisappear`. Before this hardening they overlapped:
    /// each cleared ``pendingDeletion`` only *after* its `await commit`
    /// returned, so two could both pass the `guard let pending` and hand
    /// the same ID to ``deleter`` twice. Now the slot is cleared
    /// synchronously here (a second call early-outs on the `guard`) and
    /// ``commit(_:)`` additionally guards on ``committingIDs`` so the
    /// store delete fires **at most once per ID**. The row stays hidden
    /// continuously because ``visibleMeetings`` filters on
    /// ``committingIDs`` for the in-flight duration even after the pending
    /// slot is cleared. All three triggers therefore converge
    /// idempotently. Named violation test:
    /// ``MeetingListDeleteTests/meetingListDelete_concurrentCommitNow_deletesExactlyOnce``.
    ///
    /// Idempotent and safe when nothing is pending — returns immediately.
    /// On a store-side throw, the ID is **not** dropped from ``meetings``
    /// (local state stays consistent with the store, where the meeting
    /// still exists) and the error surfaces through ``loadError``; the row
    /// reappears once ``committingIDs`` clears.
    func commitPendingDeletionNow() async {
        guard let pending = pendingDeletion else { return }
        deletionTimer?.cancel()
        deletionTimer = nil
        // Clear the pending slot SYNCHRONOUSLY before the await so a second
        // concurrent trigger (timer / background / disappear) early-outs on
        // the `guard let pending` above. The row stays hidden across the
        // in-flight commit because `commit(_:)` inserts the ID into
        // `committingIDs` and `visibleMeetings` filters on that set.
        pendingDeletion = nil
        await commit(pending)
    }

    /// Performs the store-side commit for a captured ``PendingDeletion``:
    /// awaits the ``deleter`` (skipped when `nil`) and, **on success**,
    /// drops the committed ID from ``meetings``. Does **not** touch
    /// ``pendingDeletion`` — the caller owns the pending slot, which lets
    /// ``requestDelete(_:)`` commit a *prior* deletion while a newer one
    /// already occupies the slot.
    ///
    /// ## Idempotency under concurrent triggers
    /// Guards on ``committingIDs``: if this ID's commit is already in
    /// flight the call returns immediately, so overlapping triggers never
    /// invoke ``deleter`` twice for the same ID. The ID is inserted before
    /// the await and removed via `defer` after it returns; ``visibleMeetings``
    /// filters on this set so the row stays hidden for the in-flight
    /// duration.
    ///
    /// ## Failure handling
    /// On a ``deleter`` throw the ID is **left in** ``meetings`` (local
    /// state stays consistent with the store, where the meeting still
    /// exists) and the error is surfaced through ``loadError``. The row
    /// reappears in ``visibleMeetings`` once the `defer` clears
    /// ``committingIDs``. The `deleter == nil` (fetcher-only test) path
    /// has no store to fail, so it drops the ID locally as a clean no-op.
    private func commit(_ pending: PendingDeletion) async {
        let id = pending.summary.id
        // Idempotency guard: bail if this ID's commit is already in flight
        // so overlapping triggers cannot double-invoke the deleter.
        guard committingIDs.insert(id).inserted else { return }
        defer { committingIDs.remove(id) }

        guard let deleter else {
            // Fetcher-only test path: no store to fail, drop locally.
            meetings.removeAll { $0.id == id }
            return
        }

        do {
            try await deleter(id)
            // Success: reconcile local state to match the store.
            meetings.removeAll { $0.id == id }
        } catch {
            // The store delete failed — the meeting still exists. Keep it
            // in `meetings` (consistent with the store) and surface the
            // error. `pendingDeletion` is already cleared and the `defer`
            // clears `committingIDs`, so the row reappears with the error
            // shown through the existing `loadError` channel.
            loadError = error
        }
    }
}
