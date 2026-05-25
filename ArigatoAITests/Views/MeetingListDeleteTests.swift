//
//  MeetingListDeleteTests.swift
//  ArigatoAITests
//
//  Created by Jose Castell on 2026/05/25.
//

@testable import ArigatoAI
import Foundation
import os
import SwiftData
import Testing

/// Tests for the swipe-to-delete + 5-second-undo state machine on
/// ``MeetingListViewModel`` (MVP-1 feature #8).
///
/// As with ``MeetingListViewTests``, ViewInspector is not a project
/// dependency, so behavior is exercised through the extracted
/// `@Observable` view model: tests build real ``MeetingSummary`` values
/// from an in-memory ``MeetingStore`` (the only public `MeetingSummary`
/// init is `init(from: Meeting)`), inject a recording `deleter`, drive
/// ``MeetingListViewModel/requestDelete(_:)`` /
/// ``MeetingListViewModel/undoPendingDeletion()`` /
/// ``MeetingListViewModel/commitPendingDeletionNow()``, and assert on
/// `meetings`, `visibleMeetings`, and `pendingDeletion`.
///
/// Marked `@MainActor` because ``MeetingListViewModel`` is `@MainActor`
/// and the project convention is `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`.
@Suite("MeetingListView delete + undo")
@MainActor
struct MeetingListDeleteTests {
    /// Builds an in-memory container fresh for each test, mirroring
    /// ``MeetingListViewTests``.
    private static func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: Meeting.self, Sentence.self,
            configurations: config
        )
    }

    /// Inserts `titles.count` meetings (newest-first by ascending index)
    /// into a fresh in-memory store and returns the store plus the
    /// `MeetingSummary` projections in fetch order (newest-first).
    private static func makeSummaries(
        titles: [String]
    ) async throws -> (store: MeetingStore, summaries: [MeetingSummary]) {
        let container = try makeContainer()
        let store = MeetingStore(modelContainer: container)
        // Insert with increasing `startedAt` so fetch order (newest-first)
        // is the reverse of insertion order; we sort the returned array by
        // the store's own descriptor via `fetchAllUnfiltered()`.
        var base = Date(timeIntervalSince1970: 1_700_000_000)
        for title in titles {
            _ = try await store.startMeeting(startedAt: base, title: title)
            base = base.addingTimeInterval(60)
        }
        let summaries = try await store.fetchAllUnfiltered()
        return (store, summaries)
    }

    // MARK: - Violation test (greedy / last-wins double swipe)

    /// **F8-T-1 (concurrency violation test)** — Two rapid
    /// ``MeetingListViewModel/requestDelete(_:)`` calls violate the
    /// single-pending-deletion scheduling assumption. Last-wins policy:
    /// the FIRST id commits immediately (recorded by the deleter and
    /// dropped from `meetings`) while the SECOND becomes the sole
    /// `pendingDeletion`, not yet committed. Both rows are excluded from
    /// `visibleMeetings` for the duration of the window.
    ///
    /// This is the test named by the scheduling-assumption doc-comment on
    /// ``MeetingListViewModel/requestDelete(_:)``. It drives the system in
    /// violation of "no second delete arrives before the timer fires" and
    /// asserts the last-wins recovery.
    @Test func meetingListDelete_rapidDoubleSwipe_firstCommitsImmediately_secondPends() async throws {
        let (store, summaries) = try await Self.makeSummaries(titles: ["Older", "Newer"])
        let newer = try #require(summaries.first)
        let older = try #require(summaries.last)
        #expect(newer.title == "Newer")
        #expect(older.title == "Older")

        let recorder = DeletionRecorder()
        // Long window so the SECOND deletion never commits via timeout
        // during the test — we only care about the immediate commit of
        // the FIRST.
        let model = MeetingListViewModel(
            fetcher: { _ in try await store.fetchAllUnfiltered() },
            deleter: recorder.makeDeleter(),
            undoWindow: .seconds(60)
        )
        await model.reload()
        #expect(model.visibleMeetings.count == 2)

        // Two rapid swipes: first `newer`, then `older` supersedes it.
        model.requestDelete(newer)
        model.requestDelete(older)

        // The second swipe is the sole pending deletion immediately
        // (armed synchronously inside requestDelete).
        #expect(model.pendingDeletion?.summary.id == older.id)

        // The first swipe's store commit runs on a spawned Task — wait for
        // the recorder to observe it.
        let firstCommitted = await waitUntil { recorder.committedIDs().contains(newer.id) }
        #expect(firstCommitted)

        // First id committed exactly once; second id not yet committed.
        #expect(recorder.committedIDs() == [newer.id])
        #expect(!recorder.committedIDs().contains(older.id))

        // `newer` dropped from `meetings`; `older` still present (pending).
        #expect(!model.meetings.contains { $0.id == newer.id })
        #expect(model.meetings.contains { $0.id == older.id })

        // Both excluded from what the view renders.
        #expect(!model.visibleMeetings.contains { $0.id == newer.id })
        #expect(!model.visibleMeetings.contains { $0.id == older.id })
        #expect(model.visibleMeetings.isEmpty)
    }

    // MARK: - Undo before timeout

    /// **F8-T-2** — Undo before the window closes must NOT call the
    /// deleter for that id, must restore the row to `visibleMeetings`, and
    /// must clear `pendingDeletion`.
    @Test func meetingListDelete_undoBeforeTimeout_restoresRow_noDelete() async throws {
        let (store, summaries) = try await Self.makeSummaries(titles: ["Keep me"])
        let target = try #require(summaries.first)

        let recorder = DeletionRecorder()
        // Long window so the timer cannot fire before we undo.
        let model = MeetingListViewModel(
            fetcher: { _ in try await store.fetchAllUnfiltered() },
            deleter: recorder.makeDeleter(),
            undoWindow: .seconds(60)
        )
        await model.reload()

        model.requestDelete(target)
        #expect(model.pendingDeletion?.summary.id == target.id)
        #expect(!model.visibleMeetings.contains { $0.id == target.id })

        model.undoPendingDeletion()

        #expect(model.pendingDeletion == nil)
        #expect(model.visibleMeetings.contains { $0.id == target.id })
        #expect(model.meetings.contains { $0.id == target.id })

        // Give any (incorrectly un-cancelled) timer a chance to fire, then
        // confirm the deleter was never called for this id.
        try? await Task.sleep(for: .milliseconds(100))
        #expect(recorder.committedIDs().isEmpty)
    }

    // MARK: - Timeout commit

    /// **F8-T-3** — When the undo window elapses with no undo, the timer
    /// commits: the deleter is called with the correct id, the row is
    /// dropped from `meetings`, and `pendingDeletion` clears.
    @Test func meetingListDelete_timeoutElapses_commitsDelete() async throws {
        let (store, summaries) = try await Self.makeSummaries(titles: ["Goodbye"])
        let target = try #require(summaries.first)

        let recorder = DeletionRecorder()
        // Short window so the timeout path fires quickly.
        let model = MeetingListViewModel(
            fetcher: { _ in try await store.fetchAllUnfiltered() },
            deleter: recorder.makeDeleter(),
            undoWindow: .milliseconds(50)
        )
        await model.reload()

        model.requestDelete(target)

        let committed = await waitUntil { recorder.committedIDs() == [target.id] }
        #expect(committed)
        #expect(model.pendingDeletion == nil)
        #expect(!model.meetings.contains { $0.id == target.id })
        #expect(!model.visibleMeetings.contains { $0.id == target.id })
    }

    // MARK: - Explicit immediate commit (background / disappear)

    /// **F8-T-4** — ``MeetingListViewModel/commitPendingDeletionNow()``
    /// (the background / view-disappear analogue) commits immediately and
    /// the armed timer must not double-fire: the id is recorded exactly
    /// once even after the original window would have elapsed.
    @Test func meetingListDelete_commitNow_committsOnce_timerDoesNotDoubleFire() async throws {
        let (store, summaries) = try await Self.makeSummaries(titles: ["Backgrounded"])
        let target = try #require(summaries.first)

        let recorder = DeletionRecorder()
        // Short window: after the explicit commit cancels the timer, we
        // wait PAST the original deadline to prove no second commit fires.
        let model = MeetingListViewModel(
            fetcher: { _ in try await store.fetchAllUnfiltered() },
            deleter: recorder.makeDeleter(),
            undoWindow: .milliseconds(50)
        )
        await model.reload()

        model.requestDelete(target)
        await model.commitPendingDeletionNow()

        #expect(model.pendingDeletion == nil)
        #expect(recorder.committedIDs() == [target.id])
        #expect(!model.meetings.contains { $0.id == target.id })

        // Wait well past the original 50ms window; a non-cancelled timer
        // would commit a second time here.
        try? await Task.sleep(for: .milliseconds(150))
        #expect(recorder.committedIDs() == [target.id])
    }

    // MARK: - Concurrent commit (idempotency under overlapping triggers)

    /// **F8-T-6 (concurrency violation test)** — Two overlapping
    /// ``MeetingListViewModel/commitPendingDeletionNow()`` calls on a
    /// single pending deletion violate the implicit "one trigger commits"
    /// assumption (production: the 5s timer + the
    /// `scenePhase`→background handler + `.onDisappear` can all fire for
    /// the same pending deletion). The hardened commit path must invoke
    /// the `deleter` **exactly once** for the id: `commitPendingDeletionNow`
    /// clears `pendingDeletion` synchronously before its await so the
    /// second call early-outs on the `guard`, and `commit(_:)` guards on
    /// the in-flight `committingIDs` set.
    ///
    /// This is the test named by the convergence doc-comment on
    /// ``MeetingListViewModel/commitPendingDeletionNow()`` and
    /// ``MeetingListViewModel/requestDelete(_:)``.
    @Test func meetingListDelete_concurrentCommitNow_deletesExactlyOnce() async throws {
        let (store, summaries) = try await Self.makeSummaries(titles: ["Doomed"])
        let target = try #require(summaries.first)

        let recorder = DeletionRecorder()
        // Slow deleter so the two commit calls genuinely overlap: the
        // first call is parked inside `await deleter` while the second
        // call reaches the `committingIDs` guard.
        let model = MeetingListViewModel(
            fetcher: { _ in try await store.fetchAllUnfiltered() },
            deleter: recorder.makeDelayingDeleter(delay: .milliseconds(80)),
            undoWindow: .seconds(60)
        )
        await model.reload()

        model.requestDelete(target)
        #expect(model.pendingDeletion?.summary.id == target.id)

        // Two overlapping commits on the same pending deletion.
        async let a: Void = model.commitPendingDeletionNow()
        async let b: Void = model.commitPendingDeletionNow()
        _ = await (a, b)

        // The store delete fired exactly once for the id.
        #expect(recorder.committedIDs() == [target.id])
        #expect(model.pendingDeletion == nil)
        #expect(!model.meetings.contains { $0.id == target.id })
        #expect(!model.visibleMeetings.contains { $0.id == target.id })

        // No straggler fires after the in-flight commit drains.
        try? await Task.sleep(for: .milliseconds(150))
        #expect(recorder.committedIDs() == [target.id])
    }

    // MARK: - Failed delete (store throw)

    /// **F8-T-7** — When the `deleter` throws, the row must NOT silently
    /// resurrect-then-vanish. The hardened commit path:
    /// (a) surfaces the store error through `loadError`,
    /// (b) keeps the id in `meetings`/`visibleMeetings` (local state stays
    ///     consistent with the store, where the meeting still exists), and
    /// (c) clears `pendingDeletion` (the toast is dismissed).
    /// This locks Fix 2.
    @Test func meetingListDelete_deleterThrows_surfacesError_keepsRow() async throws {
        let (store, summaries) = try await Self.makeSummaries(titles: ["Stubborn"])
        let target = try #require(summaries.first)

        // Throwing deleter: the store delete always fails.
        let model = MeetingListViewModel(
            fetcher: { _ in try await store.fetchAllUnfiltered() },
            deleter: { _ in throw DeleteFailure.boom },
            undoWindow: .seconds(60)
        )
        await model.reload()
        #expect(model.loadError == nil)

        model.requestDelete(target)
        #expect(model.pendingDeletion?.summary.id == target.id)

        // Drive the commit (the background/disappear/timeout analogue).
        await model.commitPendingDeletionNow()

        // (a) error surfaced.
        #expect(model.loadError != nil)
        #expect(model.loadError as? DeleteFailure == .boom)
        // (b) the id is still present locally — the meeting still exists.
        #expect(model.meetings.contains { $0.id == target.id })
        #expect(model.visibleMeetings.contains { $0.id == target.id })
        // (c) the toast is dismissed.
        #expect(model.pendingDeletion == nil)
    }

    // MARK: - Reload during pending deletion

    /// **F8-T-5** — A ``MeetingListViewModel/reload()`` firing while a
    /// deletion is pending (the auto-save subscriber re-fetching the
    /// not-yet-committed meeting) must NOT make the swiped row reappear:
    /// `visibleMeetings` filters it out by pending id regardless of what
    /// `meetings` contains.
    @Test func meetingListDelete_reloadWhilePending_rowStaysHidden() async throws {
        let (store, summaries) = try await Self.makeSummaries(titles: ["Survivor", "Pending one"])
        let pending = try #require(summaries.first)
        #expect(pending.title == "Pending one")

        let recorder = DeletionRecorder()
        // Long window so the reload happens well inside the pending window.
        let model = MeetingListViewModel(
            fetcher: { _ in try await store.fetchAllUnfiltered() },
            deleter: recorder.makeDeleter(),
            undoWindow: .seconds(60)
        )
        await model.reload()
        #expect(model.visibleMeetings.count == 2)

        model.requestDelete(pending)
        #expect(!model.visibleMeetings.contains { $0.id == pending.id })

        // Auto-save reload: the fetcher returns BOTH meetings (the pending
        // one is not yet deleted from the store), so `meetings` regains it.
        await model.reload()
        #expect(model.meetings.contains { $0.id == pending.id })

        // …but `visibleMeetings` keeps it hidden via the pending-id filter.
        #expect(!model.visibleMeetings.contains { $0.id == pending.id })
        #expect(model.visibleMeetings.count == 1)
        #expect(model.pendingDeletion?.summary.id == pending.id)
        // Deleter was not called — the deletion is still pending.
        #expect(recorder.committedIDs().isEmpty)
    }
}

// MARK: - Test infrastructure

/// Polls a `@MainActor` predicate with a bounded retry budget. Returns
/// `true` if it becomes `true` within `maxAttempts` short sleeps. Mirrors
/// the wait-and-poll helper in ``AudioCaptureViewModelTests`` — used here
/// to await the store commit that ``MeetingListViewModel/requestDelete(_:)``
/// performs on a spawned `Task` without coupling to its internal timing.
@MainActor
private func waitUntil(
    maxAttempts: Int = 60,
    sleepMillis: Int = 50,
    _ predicate: @MainActor () -> Bool
) async -> Bool {
    for _ in 0 ..< maxAttempts {
        if predicate() { return true }
        try? await Task.sleep(for: .milliseconds(sleepMillis))
    }
    return predicate()
}

/// Records the `PersistentIdentifier`s committed through the injected
/// `deleter`, in commit order. `nonisolated` + `OSAllocatedUnfairLock`
/// per the project's Swift 6 fake-state rules — `NSLock` is forbidden
/// from async contexts (CLAUDE.md "Test fakes").
private final nonisolated class DeletionRecorder: @unchecked Sendable {
    private let ids = OSAllocatedUnfairLock<[PersistentIdentifier]>(initialState: [])

    /// Returns the Sendable deleter closure to hand into
    /// ``MeetingListViewModel``. Each invocation appends its id to the
    /// recorded list under the lock.
    func makeDeleter() -> @Sendable (PersistentIdentifier) async throws -> Void {
        { [ids] id in
            ids.withLock { $0.append(id) }
        }
    }

    /// Like ``makeDeleter()`` but sleeps `delay` BEFORE recording the id,
    /// so two overlapping commit calls genuinely interleave: the first is
    /// parked in `await Task.sleep` (inside the model's `await deleter`)
    /// while the second reaches the model's `committingIDs` guard. Used by
    /// the concurrent-commit idempotency test (F8-T-6).
    func makeDelayingDeleter(
        delay: Duration
    ) -> @Sendable (PersistentIdentifier) async throws -> Void {
        { [ids] id in
            try? await Task.sleep(for: delay)
            ids.withLock { $0.append(id) }
        }
    }

    /// Snapshot of recorded ids in commit order.
    func committedIDs() -> [PersistentIdentifier] {
        ids.withLock { $0 }
    }
}

/// Error injected by the failed-delete test (F8-T-7) so the throwing
/// `deleter` produces a typed, assertable failure routed through
/// ``MeetingListViewModel/loadError``.
private enum DeleteFailure: Error, Equatable {
    case boom
}
