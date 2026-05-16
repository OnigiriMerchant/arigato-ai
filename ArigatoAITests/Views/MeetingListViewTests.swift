//
//  MeetingListViewTests.swift
//  ArigatoAITests
//
//  Created by Jose Castell on 2026/05/16.
//

@testable import ArigatoAI
import Foundation
import os
import SwiftData
import Testing

/// Tests for ``MeetingListView`` and ``MeetingListViewModel``.
///
/// ViewInspector is not a project dependency, so view-level behavior is
/// exercised via the extracted `@Observable` ``MeetingListViewModel``:
/// tests drive the model with closure-based fetchers (success, failure,
/// sleep-then-return), call ``MeetingListViewModel/reload()``, and
/// inspect the resulting `meetings` / `loadError` state. This is the
/// "lightest-weight approach that gives behavioral coverage" path
/// authorized by the dispatch brief's pre-flight STOP #2.
///
/// Row formatting is tested via the pure-value helper
/// ``MeetingListRowFormatter``.
///
/// Marked `@MainActor` because ``MeetingListViewModel`` is `@MainActor`
/// and the project convention is `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`.
@Suite("MeetingListView")
@MainActor
struct MeetingListViewTests {
    /// Builds an in-memory container fresh for each test that needs a
    /// real ``MeetingStore`` to drive ordering / row-projection
    /// assertions.
    private static func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: Meeting.self, Sentence.self,
            configurations: config
        )
    }

    // MARK: - Empty state

    /// **D6-T-1** — When the underlying fetcher returns an empty array
    /// (no meetings yet), the view model leaves ``meetings`` empty and
    /// ``loadError`` nil. The view body's empty-state branch is the
    /// branch SwiftUI will pick under that state.
    @Test func meetingListView_whenStoreIsEmpty_rendersEmptyState() async {
        // Step 12: fetcher signature is `(String) async throws -> [MeetingSummary]`.
        // The Step-6 contract is unaffected by the parameter — return-shape
        // remains the same — so existing tests adapt with a `_` wrapper.
        let model = MeetingListViewModel(fetcher: { _ in [] })
        await model.reload()
        #expect(model.meetings.isEmpty)
        #expect(model.loadError == nil)
    }

    // MARK: - One meeting

    /// **D6-T-2** — A single meeting in the store yields a single
    /// summary in ``MeetingListViewModel/meetings``. The row factory in
    /// the view iterates this array via `ForEach`, so the count is the
    /// behavioral contract here.
    @Test func meetingListView_whenStoreHasOneMeeting_rendersOneRow() async throws {
        let container = try Self.makeContainer()
        let store = MeetingStore(modelContainer: container)
        _ = try await store.startMeeting(
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            title: "Only one"
        )

        let model = MeetingListViewModel(fetcher: { _ in try await store.fetchAllUnfiltered() })
        await model.reload()

        #expect(model.meetings.count == 1)
        #expect(model.meetings.first?.title == "Only one")
        #expect(model.loadError == nil)
    }

    // MARK: - Ordering

    /// **D6-T-3** — Three meetings inserted out of `startedAt` order
    /// must surface in **descending** order (newest-first) per Group D
    /// UI decision #13 — driven by
    /// ``MeetingStore/fetchAllUnfiltered()``'s sort descriptor.
    @Test func meetingListView_whenStoreHasMultipleMeetings_rendersNewestFirst() async throws {
        let container = try Self.makeContainer()
        let store = MeetingStore(modelContainer: container)

        // Insert OUT of chronological order to prove the sort is the
        // store's, not the insertion order's.
        let middleDate = Date(timeIntervalSince1970: 1_700_001_000)
        let oldestDate = Date(timeIntervalSince1970: 1_700_000_000)
        let newestDate = Date(timeIntervalSince1970: 1_700_002_000)

        _ = try await store.startMeeting(startedAt: middleDate, title: "Middle")
        _ = try await store.startMeeting(startedAt: oldestDate, title: "Oldest")
        _ = try await store.startMeeting(startedAt: newestDate, title: "Newest")

        let model = MeetingListViewModel(fetcher: { _ in try await store.fetchAllUnfiltered() })
        await model.reload()

        #expect(model.meetings.map(\.title) == ["Newest", "Middle", "Oldest"])
        // Cross-check by date, not just title, so a title typo in the
        // setup couldn't hide a real ordering bug.
        #expect(model.meetings.map(\.startedAt) == [newestDate, middleDate, oldestDate])
    }

    // MARK: - Row projection

    /// **D6-T-4** — Row formatter projects title verbatim, the date in
    /// POSIX en-US short style, and the duration in whole minutes. The
    /// projection is the contract the view binds to via
    /// ``MeetingListRow``.
    @Test func meetingListView_rowDisplaysTitleDateAndDuration() {
        let started = Date(timeIntervalSince1970: 1_700_000_000)
        // 50 minutes later → 50 min duration in the row.
        let ended = started.addingTimeInterval(50 * 60)

        let date = MeetingListRowFormatter.formattedDate(started)
        let duration = MeetingListRowFormatter.formattedDuration(
            startedAt: started,
            endedAt: ended
        )

        // Verify a stable POSIX rendering of a known epoch so this test
        // is locale-independent.
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        #expect(date == formatter.string(from: started))
        #expect(duration == "50 min")
    }

    // MARK: - Em-dash for active meetings

    /// **D6-T-5** — When ``MeetingSummary/endedAt`` is `nil` (active
    /// meeting), the duration string is the em-dash sentinel `"—"` per
    /// the locked row contract.
    @Test func meetingListView_endedAtNil_rendersEmDashForDuration() {
        let started = Date(timeIntervalSince1970: 1_700_000_000)
        let duration = MeetingListRowFormatter.formattedDuration(
            startedAt: started,
            endedAt: nil
        )
        #expect(duration == "—")
    }

    // MARK: - Store failure on reload

    /// **D6-T-6** — A thrown error inside the fetcher is captured into
    /// ``MeetingListViewModel/loadError`` rather than propagated out of
    /// the view body. The empty-state branch flips off (because
    /// `loadError != nil`), so the list branch renders even with no
    /// meetings — the type-level "errors surface inline" contract.
    @Test func meetingListView_storeFailureDuringReload_setsLoadError() async {
        struct Boom: Error, Equatable {}
        let model = MeetingListViewModel(fetcher: { _ in
            throw Boom()
        })

        await model.reload()

        #expect(model.meetings.isEmpty)
        #expect(model.loadError is Boom)
    }

    // MARK: - Concurrency violation: last-query-wins

    /// **D6-T-7 (concurrency violation test)** — Two rapid invocations
    /// of ``MeetingListViewModel/reload()`` against a fetcher whose first
    /// call sleeps must result in the second call's payload being the
    /// one that lands in ``MeetingListViewModel/meetings``.
    ///
    /// This is the named violation test referenced by the type-level
    /// scheduling-assumption doc-comment on ``MeetingListView``:
    /// "Concurrent reloads … are serialized by SwiftUI's `.task(id:)`
    /// cancellation — a previous in-flight reload is cancelled when
    /// `refreshTrigger` changes." Because Step 6 does not wire
    /// `refreshTrigger` into a SwiftUI runtime, this test exercises the
    /// equivalent semantics at the model layer: the second `reload()`
    /// call returns first (the synchronous-success path), then the
    /// first `reload()` returns and overwrites with its stale-but-still-
    /// shipped data. The contract under SwiftUI runtime would be:
    /// `.task(id:)` cancels the first task before it can overwrite. This
    /// test documents the layer below that cancellation — the model
    /// itself is last-write-wins on `meetings`. The doc-comment is honest
    /// about this: "Concurrent invocations are serialized last-query-wins
    /// by `.task(id:)` cancellation" — i.e. via cancellation, not via
    /// in-model serialization. The test asserts the cancellation-honored
    /// path: when the first call is **cancelled** (via `Task.cancel`),
    /// only the second call's result lands.
    ///
    /// Implementation: spawn the first `reload()` in a Task, cancel it
    /// before its sleep elapses, then await the second `reload()` which
    /// returns synchronously. After both, only the second call's payload
    /// must be in `meetings`.
    @Test func meetingListView_rapidRefreshTriggerChanges_lastQueryWins() async throws {
        // Build two distinct DTOs via a real container, since
        // `MeetingSummary`'s only public init is `init(from: Meeting)`
        // (per DR-1: DTOs cross actor boundaries; `@Model` instances
        // never do). Each payload is built from a separate `Meeting`
        // inside an in-memory context.
        let container = try Self.makeContainer()
        let context = ModelContext(container)
        let firstMeeting = Meeting(
            startedAt: Date(timeIntervalSince1970: 1000),
            title: "First-call (should be cancelled)"
        )
        let secondMeeting = Meeting(
            startedAt: Date(timeIntervalSince1970: 2000),
            title: "Second-call (last query wins)"
        )
        context.insert(firstMeeting)
        context.insert(secondMeeting)
        try context.save()
        let firstPayload = [MeetingSummary(from: firstMeeting)]
        let secondPayload = [MeetingSummary(from: secondMeeting)]

        // A small dispatcher that returns `firstPayload` for the first
        // call (after a sleep we expect to be cancelled) and
        // `secondPayload` for the second call (immediately).
        let dispatcher = FetcherDispatcher(
            slowResult: firstPayload,
            fastResult: secondPayload
        )

        let model = MeetingListViewModel(fetcher: dispatcher.makeFetcher())

        // Spawn the first reload; cancel it before its sleep elapses so
        // its post-sleep assignment to `meetings` never fires (the sleep
        // throws `CancellationError`, which the model converts into a
        // captured `loadError`).
        let firstReloadTask = Task { await model.reload() }
        // Allow the first call to enter its sleep.
        try? await Task.sleep(nanoseconds: 10_000_000)
        firstReloadTask.cancel()
        // Wait for the cancelled first task to actually finish first —
        // we want the first call's `catch` (CancellationError) to run
        // before the second call's `meetings = next` line so the test
        // is deterministic. Without this `await`, the model is still
        // @MainActor-serialized so we can't get into a true data race,
        // but the order of `meetings` writes could vary between runs.
        await firstReloadTask.value

        // Drive the second reload to completion.
        await model.reload()

        // The second call's payload is the one that landed; the first
        // call (cancelled) never wrote to `meetings`. Step 12 silently
        // swallows `CancellationError`, so the cancelled first call did
        // not set `loadError`, and the second call's success path leaves
        // it `nil`.
        #expect(model.meetings.map(\.title) == ["Second-call (last query wins)"])
        #expect(model.loadError == nil)
    }
}

// MARK: - Test infrastructure

/// Two-shot dispatcher used by D6-T-7 to simulate a "slow first call,
/// fast second call" fetcher. The first call sleeps for ~200ms (long
/// enough that the test can cancel it before it completes); the second
/// call returns synchronously.
///
/// `nonisolated` + `OSAllocatedUnfairLock` per the project's Swift 6
/// fake-state rules — `NSLock` is forbidden from async contexts.
private final nonisolated class FetcherDispatcher: @unchecked Sendable {
    private let slow: [MeetingSummary]
    private let fast: [MeetingSummary]
    private let callCount = OSAllocatedUnfairLock<Int>(initialState: 0)

    init(slowResult: [MeetingSummary], fastResult: [MeetingSummary]) {
        slow = slowResult
        fast = fastResult
    }

    /// Returns the fetcher closure to hand into ``MeetingListViewModel``.
    /// First invocation sleeps then returns `slow`; subsequent
    /// invocations return `fast` immediately.
    ///
    /// Step 12: closure signature takes a `String` (search text) but the
    /// Step-6 violation test ignores it — the dispatch shape depends on
    /// call ordering, not on the needle.
    func makeFetcher() -> @Sendable (String) async throws -> [MeetingSummary] {
        { [self] _ in
            let isFirstCall = callCount.withLock { count -> Bool in
                count += 1
                return count == 1
            }
            if isFirstCall {
                // Sleep is cancellable — the test cancels the spawning
                // task before this elapses, so the sleep throws
                // `CancellationError`. We never reach the `return slow`
                // line; the model leaves `meetings` untouched on the
                // first call. Step 12 silently swallows
                // `CancellationError` (debounce/auto-cancel paths reuse
                // the same `reload()`), so `loadError` stays `nil`
                // through both calls; the post-second `loadError == nil`
                // assertion below verifies the steady state.
                try await Task.sleep(nanoseconds: 200_000_000)
                return slow
            }
            return fast
        }
    }
}
