//
//  TranscriptSplitScreenViewModel.swift
//  ArigatoAI
//
//  Created by Jose Castell on 2026/05/16.
//

import Foundation
import SwiftData
import SwiftUI

/// Identifies one of the two transcript columns in the split-screen
/// surface. Used to thread per-column intent reads through
/// ``TranscriptSplitScreenViewModel/shouldFollow(column:)``.
///
/// `nonisolated` value type — carries no main-actor UI state, so it can
/// cross actor boundaries freely.
nonisolated enum TranscriptColumn {
    /// The top (Japanese) column.
    case japanese
    /// The bottom (English) column.
    case english
}

/// Snapshot of the auto-follow decision for both columns, captured at the
/// instant a reload's new sentence payload is about to land.
///
/// The auto-follow contract (UI decision #2) is: a column scrolls to its
/// bottom edge when new content arrives **only if** the user was already
/// at the bottom when that content landed. The "was already at the
/// bottom" answer must be read from the at-bottom flags *as they stood
/// before* the new `sentences` value mutates — the geometry callback can
/// flip an at-bottom flag `false` (new `contentSize`, old `contentOffset`)
/// the instant `sentences` changes, and there is no documented ordering
/// between that geometry callback and the view's `.onChange(of:
/// sentences)` follow check. Capturing the decision before the mutation
/// removes the ordering dependency.
///
/// `nonisolated` value type, `Equatable` so the tests can assert the
/// captured snapshot directly.
nonisolated struct FollowIntent: Equatable {
    /// `true` if the Japanese column should auto-follow on the paired
    /// `sentences` change.
    let japanese: Bool
    /// `true` if the English column should auto-follow on the paired
    /// `sentences` change.
    let english: Bool
}

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
/// ### Auto-follow capture-before-mutation invariant
///
/// The auto-follow decision (``FollowIntent``) is captured into
/// ``pendingFollowIntent`` from the current at-bottom flags in the *same
/// synchronous run* that assigns the new `sentences` value — there is NO
/// `await` between capturing the intent and assigning `sentences` (see
/// ``reload()``). This is load-bearing: SE-0306 serialises main-actor
/// work *between* suspension points, so any suspension inserted between
/// the capture and the assignment would let the geometry callback flip an
/// at-bottom flag (new `contentSize` against the old `contentOffset`)
/// before the intent is captured — exactly the ordering bug this design
/// removes. The capture and the assignment must stay in one
/// non-suspending window.
///
/// Under rapid reloads, **last snapshot wins**: each landed reload
/// overwrites ``pendingFollowIntent`` wholesale. An older intent that was
/// never consumed by a view observer is silently discarded — which is
/// correct, because the `sentences` value it was paired with was also
/// discarded by the same last-write-wins overwrite. The intent and its
/// paired `sentences` value always advance together. Named violation
/// test: `viewModel_rapidReloads_followIntentReflectsLatestPreMutationState`.
///
/// Scope note (2026-06-12 gate review): the named test enforces the
/// *last-snapshot-wins* consequence observable at the `shouldFollow`
/// seam. The no-suspension window itself is enforced *structurally* —
/// the two writes are adjacent with no `await` between them — and has
/// no reentrancy window a test could drive; a violation would require
/// editing `reload()` to insert a suspension, which the ``reload()``
/// doc-comment forbids.
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

    /// Tolerance, in points, applied to the at-bottom geometry predicate
    /// in the view's `.onScrollGeometryChange`.
    ///
    /// Apple documents no resting-`contentOffset` exactness guarantee for
    /// `ScrollView`, so the bottom-edge comparison
    /// (`contentOffset.y + containerSize.height >= contentSize.height -
    /// contentInsets.bottom`) can land a fraction of a point short of
    /// equality at rest and read "not at bottom" when the user is, for
    /// all practical purposes, at the bottom. A 2pt slack absorbs that
    /// float-exactness. The bias direction is deliberate: 2pt makes the
    /// predicate read at-bottom slightly *more* readily, which biases
    /// toward auto-following — the correct failure direction for a live
    /// caption feed (a caption feed that occasionally over-follows is far
    /// less harmful than one that strands the user one pixel from the
    /// bottom and stops following).
    ///
    /// `nonisolated static` so the view's geometry predicate (which runs
    /// outside the VM's isolation in the `.onScrollGeometryChange`
    /// transform closure) can read it without a hop.
    nonisolated static let atBottomEpsilon: CGFloat = 2

    /// The auto-follow decision captured at the instant the most recent
    /// landed reload's `sentences` value was assigned.
    ///
    /// Initialised to `(japanese: true, english: true)` to mirror the
    /// ``jaAtBottom`` / ``enAtBottom`` initial values: an empty column has
    /// no scrollback, so the very first sentence must auto-follow on both
    /// sides. Written by ``reload()`` (success path only) in the same
    /// non-suspending window that assigns `sentences`; read — without
    /// clearing — by ``shouldFollow(column:)``.
    private(set) var pendingFollowIntent = FollowIntent(japanese: true, english: true)

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
    ///
    /// ## Auto-follow capture-before-mutation window (load-bearing)
    ///
    /// On the success path, ``pendingFollowIntent`` is captured from the
    /// current ``jaAtBottom`` / ``enAtBottom`` flags **immediately before**
    /// `sentences` is assigned, with **no `await` and no suspension
    /// point** between the two writes. The ordering and adjacency are the
    /// fix: the geometry callback can flip an at-bottom flag the instant
    /// `sentences` changes (it recomputes against the new `contentSize`
    /// with the still-old `contentOffset`), and SwiftUI documents no
    /// ordering between that callback and the view's
    /// `.onChange(of: sentences)` follow check. Capturing the intent in
    /// the same non-suspending run as the assignment makes the follow
    /// decision independent of that callback ordering. **Reordering these
    /// two writes, or inserting any `await` between them, reintroduces the
    /// bug** (SE-0306: isolation serialises between suspension points, not
    /// across a whole method). The catch path is intentionally left
    /// untouched — a failed reload does not change `sentences`, so no
    /// follow should fire and no intent is written.
    func reload() async {
        do {
            let next = try await fetcher()
            // After the await, isolation has hopped back to the main
            // actor (Self is @MainActor). Safe to mutate published
            // properties directly.
            //
            // Capture the follow intent from the at-bottom flags as they
            // stand RIGHT NOW, then assign `sentences` — no await, no
            // suspension between these two writes (see the doc-comment).
            pendingFollowIntent = FollowIntent(japanese: jaAtBottom, english: enAtBottom)
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

    /// Returns whether the given column should auto-follow on the most
    /// recent landed `sentences` change.
    ///
    /// Reads ``pendingFollowIntent`` — the follow decision captured by
    /// ``reload()`` in the same non-suspending window that assigned the
    /// current `sentences` value (see the type-level capture-before-
    /// mutation invariant). The snapshot therefore reflects the at-bottom
    /// state *before* the new content landed, which is exactly the
    /// auto-follow contract (UI decision #2).
    ///
    /// The read is **non-clearing and idempotent**: both per-column view
    /// observers (`.onChange(of: sentences)` on the JA column and on the
    /// EN column) fire on the same `sentences` change and each reads this
    /// snapshot independently. Clearing the intent on read would starve
    /// whichever observer ran second. Calling this any number of times for
    /// either column returns the same answer until the next reload lands a
    /// fresh intent. Named test:
    /// `viewModel_shouldFollow_readsPerColumnIntent_nonClearing`.
    ///
    /// - Parameter column: The column whose follow decision to read.
    /// - Returns: `true` if that column should scroll to its bottom edge
    ///   on the paired `sentences` change.
    func shouldFollow(column: TranscriptColumn) -> Bool {
        switch column {
        case .japanese: pendingFollowIntent.japanese
        case .english: pendingFollowIntent.english
        }
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
