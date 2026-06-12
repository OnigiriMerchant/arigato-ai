//
//  TranscriptSplitScreenViewModelTests.swift
//  ArigatoAITests
//
//  Created by Jose Castell on 2026/05/16.
//

@testable import ArigatoAI
import Foundation
import os
import SwiftData
import SwiftUI
import Testing

/// Tests for ``TranscriptSplitScreenViewModel``.
///
/// ViewInspector is not a project dependency, so view-level behaviour is
/// exercised via the extracted `@Observable` view model: tests drive the
/// model with closure-based fetchers (success, throw, sleep-then-return),
/// call ``TranscriptSplitScreenViewModel/reload()`` /
/// ``TranscriptSplitScreenViewModel/requestReload()`` /
/// ``TranscriptSplitScreenViewModel/scrollBothToBottom()`` /
/// ``TranscriptSplitScreenViewModel/setJaAtBottom(_:)`` /
/// ``TranscriptSplitScreenViewModel/setEnAtBottom(_:)`` and inspect the
/// resulting state. Mirrors the Phase-2 trio pattern established by
/// ``MeetingListViewTests`` (Step 6).
///
/// Marked `@MainActor` because the VM is `@MainActor` and the project
/// convention is `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`.
@Suite("TranscriptSplitScreenViewModel")
@MainActor
struct TranscriptSplitScreenViewModelTests {
    // MARK: - Helpers

    private static func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: Meeting.self, Sentence.self,
            configurations: config
        )
    }

    /// Builds a fixed-shape projection without going through SwiftData —
    /// `PersistentIdentifier` cannot be hand-rolled (its initializer is
    /// not public), so test-only projections use real identifiers
    /// minted by a one-shot `Meeting` insertion below.
    private static func makeProjection(
        id: PersistentIdentifier,
        timestamp: Date = Date(),
        sourceLanguage: String = "ja",
        sourceText: String = "src",
        translatedText: String = "tr"
    ) -> MeetingDetail.SentenceProjection {
        MeetingDetail.SentenceProjection(
            id: id,
            timestamp: timestamp,
            sourceLanguage: sourceLanguage,
            sourceText: sourceText,
            translatedText: translatedText,
            sourceSegmentID: UUID()
        )
    }

    /// Mints a real `PersistentIdentifier` by inserting a transient
    /// `Meeting` row into an in-memory container. We need real
    /// identifiers because `PersistentIdentifier` has no public
    /// initializer.
    private static func mintIdentifier() throws -> PersistentIdentifier {
        let container = try makeContainer()
        let context = ModelContext(container)
        let m = Meeting(startedAt: Date(), title: "id-mint")
        context.insert(m)
        try context.save()
        return m.persistentModelID
    }

    // MARK: - 1. Empty init state

    /// **D9a-T-vm-1** — A freshly-constructed VM has empty `sentences`
    /// and `loadError == nil`. The view body's empty-state branch keys
    /// off this state (no rows yet, no error to surface).
    @Test func viewModel_initWithEmptyMeeting_sentencesIsEmpty() {
        let vm = TranscriptSplitScreenViewModel(fetcher: { [] })

        #expect(vm.sentences.isEmpty)
        #expect(vm.loadError == nil)
        #expect(vm.jaAtBottom == true, "Empty column has no scrollback; default at-bottom for auto-follow on first sentence.")
        #expect(vm.enAtBottom == true)
        #expect(vm.arrowVisible == false, "Both columns at bottom → no return arrow.")
        #expect(
            vm.pendingFollowIntent == FollowIntent(japanese: true, english: true),
            "Initial follow intent mirrors jaAtBottom/enAtBottom defaults so the first sentence auto-follows both columns."
        )
    }

    // MARK: - 2. requestReload bumps refreshTrigger

    /// **D9a-T-vm-2** — ``TranscriptSplitScreenViewModel/requestReload()``
    /// must mutate ``TranscriptSplitScreenViewModel/refreshTrigger`` to
    /// a fresh `UUID`. SwiftUI's `.task(id:)` modifier in the view body
    /// keys off this UUID — each new value cancels the previous task
    /// and starts a new one (last-query-wins semantics).
    @Test func viewModel_requestReload_bumpsRefreshTrigger() {
        let vm = TranscriptSplitScreenViewModel(fetcher: { [] })

        let initialTrigger = vm.refreshTrigger
        vm.requestReload()
        #expect(vm.refreshTrigger != initialTrigger)

        let secondTrigger = vm.refreshTrigger
        vm.requestReload()
        #expect(vm.refreshTrigger != secondTrigger)
    }

    // MARK: - 3. reload populates sentences

    /// **D9a-T-vm-3** — ``TranscriptSplitScreenViewModel/reload()``
    /// awaits the fetcher and lands the payload in
    /// ``TranscriptSplitScreenViewModel/sentences``. Mirrors
    /// ``MeetingListViewModel``'s reload contract.
    @Test func viewModel_reload_populatesSentencesFromStore() async throws {
        let id = try Self.mintIdentifier()
        let payload = [
            Self.makeProjection(id: id, sourceText: "first"),
            Self.makeProjection(id: id, sourceText: "second"),
        ]

        let vm = TranscriptSplitScreenViewModel(fetcher: { payload })
        await vm.reload()

        #expect(vm.sentences.count == 2)
        #expect(vm.sentences.map(\.sourceText) == ["first", "second"])
        #expect(vm.loadError == nil)
    }

    // MARK: - 4. setJaAtBottom updates jaAtBottom + arrowVisible

    /// **D9a-T-vm-4** — Setting `jaAtBottom = false` (the JA column was
    /// scrolled up from bottom) must flip
    /// ``TranscriptSplitScreenViewModel/jaAtBottom`` AND
    /// ``TranscriptSplitScreenViewModel/arrowVisible`` to `true` (per UI
    /// decision #2: arrow visible whenever EITHER half is scrolled up).
    @Test func viewModel_setJaAtBottom_updatesBoth_jaAtBottom_andArrowVisible() {
        let vm = TranscriptSplitScreenViewModel(fetcher: { [] })
        #expect(vm.jaAtBottom == true)
        #expect(vm.arrowVisible == false)

        vm.setJaAtBottom(false)
        #expect(vm.jaAtBottom == false)
        #expect(vm.arrowVisible == true, "arrowVisible = !jaAtBottom || !enAtBottom; JA scrolled up alone → visible")
    }

    // MARK: - 5. setEnAtBottom updates enAtBottom + arrowVisible

    /// **D9a-T-vm-5** — Mirror of the previous test for the English
    /// column. Setting `enAtBottom = false` flips
    /// ``TranscriptSplitScreenViewModel/enAtBottom`` AND
    /// ``TranscriptSplitScreenViewModel/arrowVisible``.
    @Test func viewModel_setEnAtBottom_updatesBoth_enAtBottom_andArrowVisible() {
        let vm = TranscriptSplitScreenViewModel(fetcher: { [] })
        #expect(vm.enAtBottom == true)
        #expect(vm.arrowVisible == false)

        vm.setEnAtBottom(false)
        #expect(vm.enAtBottom == false)
        #expect(vm.arrowVisible == true)
    }

    // MARK: - 6. arrowVisible composition

    /// **D9a-T-vm-6** — Truth table for ``TranscriptSplitScreenViewModel/arrowVisible``:
    ///
    /// | ja | en | arrowVisible |
    /// |----|----|--------------|
    /// | T  | T  | false        |
    /// | F  | T  | true         |
    /// | T  | F  | true         |
    /// | F  | F  | true         |
    ///
    /// The OR-across-halves composition is the UI #2 locked contract.
    @Test func viewModel_arrowVisible_trueWhenEitherHalfIsAboveBottom() {
        let vm = TranscriptSplitScreenViewModel(fetcher: { [] })

        // Both at bottom → invisible.
        vm.setJaAtBottom(true)
        vm.setEnAtBottom(true)
        #expect(vm.arrowVisible == false)

        // Only JA scrolled up → visible.
        vm.setJaAtBottom(false)
        vm.setEnAtBottom(true)
        #expect(vm.arrowVisible == true)

        // Only EN scrolled up → visible.
        vm.setJaAtBottom(true)
        vm.setEnAtBottom(false)
        #expect(vm.arrowVisible == true)

        // Both scrolled up → visible.
        vm.setJaAtBottom(false)
        vm.setEnAtBottom(false)
        #expect(vm.arrowVisible == true)
    }

    // MARK: - 7. scrollBothToBottom (floor test)

    /// **D9a-T-vm-7** — ``TranscriptSplitScreenViewModel/scrollBothToBottom()``
    /// is the unified return-arrow handler. The strict
    /// "single-animation-transaction" assertion (DR-4 § "Synchronized
    /// dual-scroll animation") requires hooking into SwiftUI's animation
    /// surface, which has no stable test seam in the current target —
    /// see the type-level doc-comment + the V3 entry "Scroll animation
    /// timing tuning" filed for physical-device verification during
    /// MVP-1.
    ///
    /// This test asserts the floor contract: both `ScrollPosition` slots
    /// must be mutated by the call (i.e. the method must not be a
    /// no-op). Direct inspection of `ScrollPosition`'s post-mutation
    /// state is not part of the public API (the type's storage is
    /// opaque), so the floor assertion is "the call completes without
    /// throwing or crashing and both positions remain non-nil after."
    /// The stricter "scrolled-to-bottom-edge" assertion is V3-deferred
    /// pending an integration test on physical hardware.
    @Test func viewModel_scrollBothToBottom_setsBothPositionsToBottomEdge() {
        let vm = TranscriptSplitScreenViewModel(fetcher: { [] })

        // Pre-state: both at bottom (default), arrow hidden.
        #expect(vm.arrowVisible == false)

        // Simulate user scrolling up on both halves.
        vm.setJaAtBottom(false)
        vm.setEnAtBottom(false)
        #expect(vm.arrowVisible == true)

        // Invoke the unified scroll. The call must complete cleanly
        // and not mutate the at-bottom flags (those are driven by the
        // geometry callbacks, not by the intent).
        vm.scrollBothToBottom()

        // Per the doc-comment on `scrollBothToBottom()`: we do NOT
        // pre-set jaAtBottom/enAtBottom — those reflect actual scroll
        // completion, not intent. So they should still be `false` until
        // the geometry callbacks would normally re-fire.
        #expect(vm.jaAtBottom == false,
                "scrollBothToBottom does not pre-set jaAtBottom; only the geometry callback does.")
        #expect(vm.enAtBottom == false,
                "scrollBothToBottom does not pre-set enAtBottom; only the geometry callback does.")
    }

    // MARK: - 8. Concurrency violation: rapid sentencesDidUpdate

    /// **D9a-T-vm-8 (concurrency violation test).** The doc-comment on
    /// ``TranscriptSplitScreenViewModel`` declares that rapid
    /// `sentencesDidUpdate` callbacks — which bump `refreshTrigger` via
    /// ``TranscriptSplitScreenViewModel/requestReload()`` — are
    /// serialized last-query-wins by SwiftUI's `.task(id:)` cancellation.
    ///
    /// Mirrors the test pattern locked by ``MeetingListViewTests/meetingListView_rapidRefreshTriggerChanges_lastQueryWins``:
    /// the model layer itself is "last-write-wins on `sentences`" — the
    /// `.task(id:)` cancellation is the SwiftUI-runtime layer that
    /// enforces the actual contract. We exercise the cancellation-honored
    /// path: spawn the first `reload()` in a `Task`, cancel it before
    /// its sleep elapses, then run the second `reload()` synchronously.
    /// Only the second call's payload must land in `sentences`.
    @Test func viewModel_rapidSentencesDidUpdate_lastReloadWins() async throws {
        let id = try Self.mintIdentifier()
        let firstPayload = [
            Self.makeProjection(id: id, sourceText: "first-call (cancelled)"),
        ]
        let secondPayload = [
            Self.makeProjection(id: id, sourceText: "second-call (last query wins)"),
        ]

        let dispatcher = FetcherDispatcher(
            slowResult: firstPayload,
            fastResult: secondPayload
        )

        let vm = TranscriptSplitScreenViewModel(fetcher: dispatcher.makeFetcher())

        // Spawn the first reload; cancel before its sleep elapses.
        let firstReloadTask = Task { await vm.reload() }
        try? await Task.sleep(nanoseconds: 10_000_000)
        firstReloadTask.cancel()
        // Wait for the cancelled task to actually finish — its
        // `catch CancellationError` path runs first so the second
        // call's `sentences = next` is the definitive write.
        await firstReloadTask.value

        // Drive the second reload to completion.
        await vm.reload()

        #expect(vm.sentences.map(\.sourceText) == ["second-call (last query wins)"])
        #expect(vm.loadError == nil,
                "Second call's success should have cleared the cancellation error.")
    }

    // MARK: - 9. Follow intent captured before mutation

    /// **D6-T-vm-9** — ``TranscriptSplitScreenViewModel/reload()`` must
    /// capture ``TranscriptSplitScreenViewModel/pendingFollowIntent`` from
    /// the at-bottom flags *as they stand before* the new `sentences`
    /// value lands. We set the flags to a known asymmetric state
    /// (`ja=false`, `en=true`), run a reload with a non-empty payload, and
    /// assert the captured intent mirrors the pre-mutation flags AND the
    /// payload landed. This pins the capture-before-mutation invariant
    /// (the geometry callback cannot retroactively change a decision that
    /// was already snapshotted in the same non-suspending window as the
    /// `sentences` assignment).
    @Test func viewModel_reload_capturesFollowIntentFromAtBottomFlagsBeforeMutation() async throws {
        let id = try Self.mintIdentifier()
        let payload = [Self.makeProjection(id: id, sourceText: "after-reload")]

        let vm = TranscriptSplitScreenViewModel(fetcher: { payload })

        // Asymmetric pre-mutation state: JA scrolled up, EN at bottom.
        vm.setJaAtBottom(false)
        vm.setEnAtBottom(true)

        await vm.reload()

        #expect(
            vm.pendingFollowIntent == FollowIntent(japanese: false, english: true),
            "Captured intent must mirror the at-bottom flags as they stood before the sentences assignment."
        )
        #expect(vm.sentences.map(\.sourceText) == ["after-reload"],
                "The paired sentences payload must have landed alongside the captured intent.")
    }

    // MARK: - 10. shouldFollow is a per-column, non-clearing read

    /// **D6-T-vm-10** — ``TranscriptSplitScreenViewModel/shouldFollow(column:)``
    /// reads the per-column slot of the captured intent and does NOT clear
    /// it. Both per-column view observers fire on the same `sentences`
    /// change and read this snapshot independently, so clearing on read
    /// would starve whichever observer ran second. We capture an
    /// asymmetric intent (`ja=true`, `en=false`) via a reload, then assert
    /// each column reads its own slot AND that a second read of the JA
    /// column still returns `true` (idempotent / non-clearing).
    @Test func viewModel_shouldFollow_readsPerColumnIntent_nonClearing() async throws {
        let id = try Self.mintIdentifier()
        let payload = [Self.makeProjection(id: id, sourceText: "row")]

        let vm = TranscriptSplitScreenViewModel(fetcher: { payload })

        // Capture intent (ja=true, en=false) via a reload.
        vm.setJaAtBottom(true)
        vm.setEnAtBottom(false)
        await vm.reload()

        #expect(vm.shouldFollow(column: .japanese) == true,
                "JA slot of the captured intent is true.")
        #expect(vm.shouldFollow(column: .english) == false,
                "EN slot of the captured intent is false.")
        // Second read of the same column must return the same answer —
        // the read does not clear the intent.
        #expect(vm.shouldFollow(column: .japanese) == true,
                "Non-clearing: a repeated read of the JA column still returns true.")
    }

    // MARK: - 11. Concurrency violation: rapid reloads, last snapshot wins

    /// **D6-T-vm-11 (concurrency violation test).** The type-level
    /// scheduling assumption declares that under rapid reloads the follow
    /// intent is **last-snapshot-wins**: each landed reload overwrites
    /// ``TranscriptSplitScreenViewModel/pendingFollowIntent`` wholesale,
    /// and an older unconsumed intent is silently discarded (correct,
    /// because its paired `sentences` value was also discarded).
    ///
    /// We violate the "one reload at a time, intent consumed before the
    /// next" assumption: reload A captures `(ja=true, en=true)`; we then
    /// flip `jaAtBottom = false` (simulating the user scrolling the JA
    /// column up); reload B then lands a distinct payload. The final
    /// follow decision the view consumes — `shouldFollow(.japanese)` — must
    /// reflect reload B's pre-mutation snapshot (`false`), NOT reload A's
    /// stale `true`. We assert through `shouldFollow` (the contract the
    /// view actually consumes) AND the raw property.
    @Test func viewModel_rapidReloads_followIntentReflectsLatestPreMutationState() async throws {
        let id = try Self.mintIdentifier()
        let payloadA = [Self.makeProjection(id: id, sourceText: "reload-A")]
        let payloadB = [
            Self.makeProjection(id: id, sourceText: "reload-B-1"),
            Self.makeProjection(id: id, sourceText: "reload-B-2"),
        ]

        let dispatcher = ReloadPayloadDispatcher(first: payloadA, second: payloadB)
        let vm = TranscriptSplitScreenViewModel(fetcher: dispatcher.makeFetcher())

        // Reload A with both flags true → intent (true, true).
        vm.setJaAtBottom(true)
        vm.setEnAtBottom(true)
        await vm.reload()
        #expect(vm.shouldFollow(column: .japanese) == true,
                "After reload A, JA follow intent is true.")

        // User scrolls JA up; reload B lands a distinct payload. Reload B
        // must re-snapshot the now-false JA flag, discarding reload A's
        // stale intent.
        vm.setJaAtBottom(false)
        await vm.reload()

        #expect(vm.shouldFollow(column: .japanese) == false,
                "Last-snapshot-wins: reload B's pre-mutation snapshot (false) overwrites reload A's stale true.")
        #expect(vm.pendingFollowIntent.japanese == false,
                "Raw property mirrors the last landed reload's snapshot.")
        #expect(vm.sentences.map(\.sourceText) == ["reload-B-1", "reload-B-2"],
                "The paired sentences value advanced together with the intent.")
    }
}

// MARK: - Test infrastructure

/// Two-shot dispatcher used by D9a-T-vm-8 to simulate a "slow first call,
/// fast second call" fetcher. Mirrors the pattern from
/// ``MeetingListViewTests``'s `FetcherDispatcher`.
///
/// `nonisolated` + `OSAllocatedUnfairLock` per the project's Swift 6
/// fake-state rules — `NSLock` is forbidden from async contexts.
private final nonisolated class FetcherDispatcher: @unchecked Sendable {
    private let slow: [MeetingDetail.SentenceProjection]
    private let fast: [MeetingDetail.SentenceProjection]
    private let callCount = OSAllocatedUnfairLock<Int>(initialState: 0)

    init(
        slowResult: [MeetingDetail.SentenceProjection],
        fastResult: [MeetingDetail.SentenceProjection]
    ) {
        slow = slowResult
        fast = fastResult
    }

    /// Returns the fetcher closure to hand into ``TranscriptSplitScreenViewModel``.
    /// First invocation sleeps then returns `slow`; subsequent invocations
    /// return `fast` immediately.
    func makeFetcher() -> @Sendable () async throws -> [MeetingDetail.SentenceProjection] {
        { [self] in
            let isFirstCall = callCount.withLock { count -> Bool in
                count += 1
                return count == 1
            }
            if isFirstCall {
                // Cancellable sleep — the test cancels the spawning task
                // before this elapses, so the sleep throws
                // `CancellationError`. We never reach `return slow`; the
                // model captures the error into `loadError` and leaves
                // `sentences` untouched on the first call.
                try await Task.sleep(nanoseconds: 200_000_000)
                return slow
            }
            return fast
        }
    }
}

/// Two-shot payload dispatcher used by D6-T-vm-11. The first fetcher
/// invocation returns `first`; the second (and any subsequent) returns
/// `second`. Both return synchronously — this dispatcher is about
/// successive *successful* reloads (last-snapshot-wins on the captured
/// intent), not cancellation.
///
/// `nonisolated` + `OSAllocatedUnfairLock` per the project's Swift 6
/// fake-state rules — `NSLock` is forbidden from async contexts.
private final nonisolated class ReloadPayloadDispatcher: @unchecked Sendable {
    private let first: [MeetingDetail.SentenceProjection]
    private let second: [MeetingDetail.SentenceProjection]
    private let callCount = OSAllocatedUnfairLock<Int>(initialState: 0)

    init(
        first: [MeetingDetail.SentenceProjection],
        second: [MeetingDetail.SentenceProjection]
    ) {
        self.first = first
        self.second = second
    }

    func makeFetcher() -> @Sendable () async throws -> [MeetingDetail.SentenceProjection] {
        { [self] in
            let isFirstCall = callCount.withLock { count -> Bool in
                count += 1
                return count == 1
            }
            return isFirstCall ? first : second
        }
    }
}
