//
//  MeetingDetailViewModel.swift
//  ArigatoAI
//
//  Created by Jose Castell on 2026/05/16.
//

import Foundation
import SwiftData

/// Observable view model that owns ``MeetingDetailView``'s reload
/// pipeline and the small slice of state SwiftUI binds to.
///
/// Extracted from the view body per the Phase-2 trio pattern
/// (``MeetingListViewModel`` Step 6, ``MeetingControlsViewModel`` Step 7,
/// ``TranscriptSplitScreenViewModel`` Step 9a) so the reload logic is
/// directly testable — tests construct the model with a fetcher closure,
/// call ``reload()``, and inspect the published ``sentences`` /
/// ``loadError`` / ``refreshTrigger`` properties.
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
/// reloads — produced by rapid ``requestReload()`` calls bumping
/// ``refreshTrigger`` faster than the fetcher can complete — are
/// serialized last-query-wins by SwiftUI's `.task(id:)` cancellation: a
/// previous in-flight reload is cancelled when ``refreshTrigger`` changes
/// and only the last call's result lands.
///
/// In production, the detail view's reload is essentially unreachable
/// from this race (`.task(id:)` only re-fires on identifier change and
/// the identifier changes only on view appear / explicit refresh). The
/// pattern is preserved for trio consistency with Step 9a.
///
/// Named violation test (verified to enforce the contract):
/// `D11-T-vm-1-rapidRequestReload_lastQueryWins`.
@MainActor
@Observable
final class MeetingDetailViewModel {
    // MARK: - Dependencies

    /// Async sentence fetcher closed over the owning `meetingID`.
    /// Stored as `@MainActor` closure so production wiring closes over
    /// ``MeetingStore/fetchSentences(meetingID:)`` while tests inject
    /// ad-hoc closures (success / throw / sleep-then-return).
    private let fetcher: @MainActor (PersistentIdentifier) async throws -> [MeetingDetail.SentenceProjection]

    /// The owning meeting's identifier — captured at init time and
    /// passed to every ``reload()`` call. Stable for the VM's lifetime.
    private let meetingID: PersistentIdentifier

    // MARK: - Observable state

    /// Last-loaded sentences, oldest-first by timestamp. Empty on
    /// initial construction; populated on the first ``reload()``.
    private(set) var sentences: [MeetingDetail.SentenceProjection] = []

    /// Most recent reload error, or `nil` on success. SwiftUI views
    /// cannot throw, so errors land here for inline rendering rather
    /// than bubbling out of the view body. See ``reload()`` for the
    /// error-handling contract.
    private(set) var loadError: Error?

    /// Mutating this UUID triggers SwiftUI's `.task(id:)` to re-run
    /// ``reload()``. Bumped by ``requestReload()``. Rapid mutations are
    /// serialized last-query-wins by SwiftUI's task-cancellation
    /// behavior (see scheduling assumption above).
    private(set) var refreshTrigger: UUID = .init()

    // MARK: - Init

    /// Designated initializer — closure-injected fetcher for testing.
    ///
    /// - Parameters:
    ///   - meetingID: The owning meeting's `PersistentIdentifier`.
    ///   - fetcher: The async closure called by ``reload()``. Production
    ///     wiring closes over ``MeetingStore/fetchSentences(meetingID:)``;
    ///     tests inject closures that synthesize fixed payloads, throw
    ///     errors, or sleep to simulate cancellation.
    init(
        meetingID: PersistentIdentifier,
        fetcher: @escaping @MainActor (PersistentIdentifier) async throws -> [MeetingDetail.SentenceProjection]
    ) {
        self.meetingID = meetingID
        self.fetcher = fetcher
    }

    /// Convenience initializer that closes over a live ``MeetingStore``
    /// + `meetingID`. Production wiring path. ``MeetingDetailView``'s
    /// `init(summary:store:)` calls this once.
    ///
    /// - Parameters:
    ///   - store: The actor-backed read source.
    ///   - meetingID: The owning meeting's `PersistentIdentifier`.
    convenience init(store: MeetingStore, meetingID: PersistentIdentifier) {
        self.init(meetingID: meetingID, fetcher: { id in
            try await store.fetchSentences(meetingID: id)
        })
    }

    // MARK: - Reload

    /// Pulls the latest sentence projections across the actor hop.
    ///
    /// ## Error handling contract
    ///
    /// Errors are stored in ``loadError`` rather than thrown — SwiftUI
    /// views cannot throw, and the contract routes failures through
    /// inline error state. The method **never throws out of the view
    /// body**. A successful reload also clears ``loadError`` so a
    /// transient failure followed by a successful retry leaves the UI
    /// in the clean state.
    ///
    /// Concurrent invocations are serialized last-query-wins by
    /// SwiftUI's `.task(id:)` cancellation; see the type-level
    /// scheduling assumption + named violation test.
    func reload() async {
        do {
            let next = try await fetcher(meetingID)
            // After the await, isolation has hopped back to the main
            // actor (Self is @MainActor). Safe to mutate published
            // properties directly without a further hop.
            sentences = next
            loadError = nil
        } catch {
            loadError = error
        }
    }

    /// Bumps ``refreshTrigger`` to a fresh UUID, prompting SwiftUI's
    /// `.task(id:)` to re-run ``reload()``. Exposed for callers (and
    /// tests) that want to request a reload without owning the
    /// underlying state.
    func requestReload() {
        refreshTrigger = UUID()
    }
}
