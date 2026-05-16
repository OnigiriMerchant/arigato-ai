//
//  TranscriptSplitScreenViewModel.swift
//  ArigatoAI
//
//  Created by Jose Castell on 2026/05/16.
//

import Foundation
import SwiftData
import SwiftUI

/// Observable view model that owns ``TranscriptSplitScreenView``'s
/// reload pipeline, per-column scroll state, and "at bottom" booleans.
///
/// Extracted from the view body per the Phase-2 trio pattern
/// (``MeetingListViewModel``, ``MeetingControlsViewModel``) so the
/// reload logic + scroll-state composition is directly testable without
/// the SwiftUI runtime. Tests construct the model with a fetcher
/// closure, call ``reload()``, and inspect the published ``sentences``,
/// ``loadError``, ``jaAtBottom``, ``enAtBottom``, and ``arrowVisible``
/// derived values.
///
/// `@MainActor` because every published property mutates from SwiftUI's
/// render context. The fetcher closure itself crosses to the store's
/// actor; the post-`await` assignment hops back to the main actor by
/// virtue of the model's isolation.
///
/// ## Scheduling assumption (Concurrency design discipline)
///
/// Reload assumes ``MeetingStore`` is reachable across an actor hop and
/// returns a `Sendable` `[MeetingDetail.SentenceProjection]`. Concurrent
/// reloads — produced by rapid `sentencesDidUpdate` callbacks
/// (``MeetingSession``) bumping ``refreshTrigger`` faster than the
/// fetcher can complete — are serialized by SwiftUI's `.task(id:)`
/// cancellation: a previous in-flight reload is cancelled when
/// ``refreshTrigger`` changes, and only the last call's result lands.
/// Named violation test:
/// `viewModel_rapidSentencesDidUpdate_lastReloadWins`.
///
/// ## scrollBothToBottom animation transaction
///
/// ``scrollBothToBottom()`` mutates both ``jaPosition`` and
/// ``enPosition`` inside a single `withAnimation(.easeInOut(duration:
/// 0.35))` block per DR-4. The two scroll-position writes therefore
/// share one animation transaction and produce a coordinated
/// dual-column animation. A precise "single transaction" assertion
/// requires hooking into SwiftUI's animation surface, which has no
/// stable test seam in the current target. See **V3 entry** "Scroll
/// animation timing tuning" — a physical-device check on iPhone 17 Pro
/// Max during MVP-1 confirms the curve + duration feel right. Pre-
/// authorized STOP #2 in the dispatch brief deferred the strict
/// single-transaction test; the floor contract (both positions land at
/// the bottom edge) is enforced by
/// `viewModel_scrollBothToBottom_setsBothPositionsToBottomEdge`.
@MainActor
@Observable
final class TranscriptSplitScreenViewModel {
    // MARK: - Dependencies

    /// Async sentence fetcher. Stored as a `@Sendable` closure so the
    /// production wiring closes over ``MeetingStore/fetchSentences(meetingID:)``
    /// while tests inject ad-hoc closures (success / throw /
    /// sleep-then-return).
    private let fetcher: @Sendable () async throws -> [MeetingDetail.SentenceProjection]

    // MARK: - Observable state

    /// Last-loaded sentences, oldest-first by timestamp. Empty on
    /// initial construction; populated on the first ``reload()``.
    private(set) var sentences: [MeetingDetail.SentenceProjection] = []

    /// Most recent reload error, or `nil` on success. SwiftUI views
    /// cannot throw, so errors land here for inline rendering rather
    /// than bubbling out of the view body.
    private(set) var loadError: Error?

    /// Mutating this UUID triggers SwiftUI's `.task(id:)` to re-run
    /// ``reload()``. ``ContentView`` wires
    /// ``MeetingSession/sentencesDidUpdate`` to ``requestReload()``,
    /// which bumps this. Rapid mutations are serialized last-query-wins
    /// by SwiftUI's task-cancellation behavior (see scheduling
    /// assumption above).
    private(set) var refreshTrigger: UUID = .init()

    /// Programmatic scroll position for the Japanese column. Mutated by
    /// the view via `.scrollPosition($vm.jaPosition)` (DR-4 §iOS 18
    /// canonical API).
    var jaPosition: ScrollPosition = .init()

    /// Programmatic scroll position for the English column. Mutated by
    /// the view via `.scrollPosition($vm.enPosition)`.
    var enPosition: ScrollPosition = .init()

    /// `true` when the Japanese column is scrolled to the bottom edge.
    /// Updated by ``setJaAtBottom(_:)``, which the view drives from
    /// `.onScrollGeometryChange(for: Bool.self, of: { ... })`. Initial
    /// value is `true` because an empty column has no scrollback —
    /// auto-follow should kick in immediately on the first sentence.
    private(set) var jaAtBottom: Bool = true

    /// `true` when the English column is scrolled to the bottom edge.
    /// Mirrors ``jaAtBottom`` for the English side.
    private(set) var enAtBottom: Bool = true

    /// `true` when **either** column is scrolled up from its bottom
    /// edge. Per UI decision #2: a single unified "return arrow"
    /// appears whenever either half is scrolled away from bottom, and
    /// tapping it scrolls both columns back. OR-across-halves is the
    /// locked composition rule.
    var arrowVisible: Bool {
        !jaAtBottom || !enAtBottom
    }

    // MARK: - Init

    /// Designated initializer.
    ///
    /// - Parameter fetcher: The Sendable async closure called by
    ///   ``reload()``. Production wiring closes over
    ///   ``MeetingStore/fetchSentences(meetingID:)`` against a captured
    ///   `meetingID`; tests inject closures that synthesize fixed
    ///   payloads, throw errors, or sleep to simulate cancellation.
    init(
        fetcher: @escaping @Sendable () async throws -> [MeetingDetail.SentenceProjection]
    ) {
        self.fetcher = fetcher
    }

    /// Convenience initializer that closes over a live ``MeetingStore``
    /// + `meetingID`. Production wiring path. ``ContentView`` calls
    /// this once per bootstrapper-published coordinator.
    ///
    /// - Parameters:
    ///   - store: The actor-backed read source.
    ///   - meetingID: The owning meeting's `PersistentIdentifier`.
    convenience init(store: MeetingStore, meetingID: PersistentIdentifier) {
        self.init(fetcher: { try await store.fetchSentences(meetingID: meetingID) })
    }

    // MARK: - Reload

    /// Pulls the latest sentence projections across the actor hop.
    ///
    /// Errors are stored in ``loadError`` rather than thrown — SwiftUI
    /// views cannot throw, and the contract routes failures through the
    /// inline error state (UI decision #15 inline-marker pattern).
    ///
    /// Concurrent invocations are serialized last-query-wins by
    /// SwiftUI's `.task(id:)` cancellation; see the type-level
    /// scheduling assumption + named violation test.
    func reload() async {
        do {
            let next = try await fetcher()
            // After the await, isolation has hopped back to the main
            // actor (Self is @MainActor). Safe to mutate published
            // properties directly.
            sentences = next
            loadError = nil
        } catch {
            loadError = error
        }
    }

    /// Bumps ``refreshTrigger`` to a fresh UUID, prompting SwiftUI's
    /// `.task(id:)` to re-run ``reload()``. The trampoline used by
    /// ``ContentView`` to bridge ``MeetingSession/sentencesDidUpdate``
    /// (synchronous, must-not-block) into an async reload (which
    /// `.task(id:)` cancellation gates).
    func requestReload() {
        refreshTrigger = UUID()
    }

    // MARK: - Scroll state mutators

    /// Records whether the Japanese column is scrolled to its bottom
    /// edge. Driven by `.onScrollGeometryChange(for: Bool.self,
    /// of: { geo in ... })` in the view body — the predicate computes
    /// at-bottom from `contentOffset.y + containerSize.height >=
    /// contentSize.height - contentInsets.bottom` per DR-4.
    ///
    /// - Parameter value: The new at-bottom status from the scroll
    ///   geometry callback.
    func setJaAtBottom(_ value: Bool) {
        jaAtBottom = value
    }

    /// Records whether the English column is scrolled to its bottom
    /// edge. Mirrors ``setJaAtBottom(_:)`` for the English side.
    ///
    /// - Parameter value: The new at-bottom status.
    func setEnAtBottom(_ value: Bool) {
        enAtBottom = value
    }

    /// Scrolls both columns back to their bottom edges in a single
    /// animation transaction.
    ///
    /// Driven by the unified return-arrow button (UI decision #2). Both
    /// ``jaPosition`` and ``enPosition`` are mutated inside one
    /// `withAnimation(.easeInOut(duration: 0.35))` block per DR-4 §
    /// "Synchronized dual-scroll animation" so the dual-column scroll
    /// shares one animation curve. The 0.35s easeInOut feel is
    /// V3-tracked (entry "Scroll animation timing tuning") — physical-
    /// device verification during MVP-1 confirms.
    func scrollBothToBottom() {
        withAnimation(.easeInOut(duration: 0.35)) {
            jaPosition.scrollTo(edge: .bottom)
            enPosition.scrollTo(edge: .bottom)
        }
        // After issuing the programmatic scroll, the geometry callbacks
        // will re-fire and set jaAtBottom/enAtBottom = true. We do NOT
        // pre-set them here — the actual scroll completion drives the
        // truth value, not the intent.
    }
}
