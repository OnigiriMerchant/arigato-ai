//
//  ActiveMeetingShareViewModel.swift
//  ArigatoAI
//
//  Created by Jose Castell on 2026/05/21.
//

import Foundation
import SwiftData

/// Observable view model backing the active-view toolbar `ShareLink`
/// (UI #9 Context A).
///
/// ## Why this exists
///
/// ``MeetingDetailView`` already has its ``MeetingSummary`` handed in as
/// the `NavigationLink` value, so its `exportURL` synthesizes the
/// export payload synchronously from the in-memory summary + the VM's
/// `sentences`. The **active-view** toolbar Share has no such injection
/// point — the in-progress meeting is referenced by `meetingID` only
/// (carried in ``MeetingSessionPhase`` associated values) and the
/// auto-derived title (and rewritten English-sentence title from
/// ``MeetingSession/finalizeStop(at:)``) lives in SwiftData.
///
/// This VM owns the small asynchronous bridge that resolves a
/// ``MeetingSummary`` (for the export header) and a fresh
/// `[MeetingDetail.SentenceProjection]` (for the export body) from the
/// store, so ``ContentView``'s toolbar `ShareLink` has a single
/// optional snapshot to read.
///
/// ## Data path
///
/// `reload()` issues two store fetches:
/// 1. ``MeetingStore/fetchAllUnfiltered()`` filtered to `meetingID` —
///    yields the ``MeetingSummary`` (title, startedAt, endedAt,
///    sentenceCount). The store has no `fetchSummary(meetingID:)`
///    primitive; the all-meetings fetch + Swift-side filter is fine for
///    MVP-1 scale (~ten meetings) and is what existing read paths do.
/// 2. ``MeetingStore/fetchSentences(meetingID:)`` — yields the body
///    rows, oldest-first.
///
/// Both results land on this VM atomically — either both succeed and
/// ``snapshot`` is non-nil, or any failure clears ``snapshot`` and
/// records the error in ``loadError`` for diagnostic surfacing.
///
/// ## Scheduling assumption (Concurrency design discipline)
///
/// Reload assumes ``MeetingStore`` is reachable across an actor hop and
/// returns Sendable DTOs. Concurrent reloads — produced by rapid phase
/// changes bumping ``refreshTrigger`` faster than the fetcher pair can
/// complete — are serialized last-query-wins by SwiftUI's `.task(id:)`
/// cancellation: a previous in-flight reload is cancelled when
/// ``refreshTrigger`` changes and only the last call's result lands.
///
/// In production the relevant trigger is `meetingID` changing on the
/// phase-derived `.task(id:)` modifier (a new meeting starts after the
/// previous one ended). Concurrent reloads for the same meeting are
/// essentially unreachable from the UI; the last-write-wins guarantee
/// is preserved for trio consistency with
/// ``TranscriptSplitScreenViewModel`` (see its scheduling assumption +
/// `viewModel_rapidSentencesDidUpdate_lastReloadWins`).
///
/// No new race surface is introduced. No bespoke violation test is
/// required for this VM beyond the existing trio coverage.
@MainActor
@Observable
final class ActiveMeetingShareViewModel {
    // MARK: - Snapshot

    /// Atomic export payload — both summary and sentences land together
    /// or not at all. Held as a single optional so ``ContentView``'s
    /// `ShareLink` toolbar item can render iff this is non-nil **and**
    /// sentences are non-empty (UI #4 "buttons exist only when usable").
    struct Snapshot: Equatable {
        /// Summary backing the export header (title, dates, duration).
        let summary: MeetingSummary
        /// Body rows, oldest-first by timestamp.
        let sentences: [MeetingDetail.SentenceProjection]
    }

    // MARK: - Dependencies

    /// Async summary fetcher closed over the target `meetingID`. Returns
    /// the matching ``MeetingSummary`` or `nil` if the meeting has been
    /// deleted between fetches.
    private let summaryFetcher: @MainActor (PersistentIdentifier) async throws -> MeetingSummary?

    /// Async sentence fetcher closed over the target `meetingID`.
    private let sentenceFetcher: @MainActor (PersistentIdentifier) async throws -> [MeetingDetail.SentenceProjection]

    /// The owning meeting's identifier — captured at init time and
    /// passed to every ``reload()`` call. Stable for the VM's lifetime;
    /// when the active meeting changes ``ContentView`` constructs a
    /// fresh VM (Option a re-construction pattern from Step 9a).
    private let meetingID: PersistentIdentifier

    // MARK: - Observable state

    /// Most recent successful snapshot, or `nil` until the first
    /// successful ``reload()`` lands. The toolbar `ShareLink` renders
    /// iff this is non-nil and `snapshot.sentences.isEmpty == false`
    /// (the UI #4 "buttons exist only when usable" gate).
    private(set) var snapshot: Snapshot?

    /// Most recent reload error, or `nil` on success. SwiftUI views
    /// cannot throw, so errors land here for diagnostic logging. The
    /// toolbar item itself simply hides on error — mirroring
    /// ``MeetingDetailView``'s `exportURL` failure mode (UI #4
    /// "buttons exist only when usable").
    private(set) var loadError: Error?

    /// Mutating this UUID triggers SwiftUI's `.task(id:)` to re-run
    /// ``reload()``. Bumped by ``requestReload()`` if a caller wants to
    /// force a refresh without changing `meetingID`.
    private(set) var refreshTrigger: UUID = .init()

    // MARK: - Init

    /// Designated initializer — closure-injected fetchers for testing.
    ///
    /// - Parameters:
    ///   - meetingID: The active meeting's `PersistentIdentifier`.
    ///   - summaryFetcher: Async closure returning the matching summary
    ///     or `nil` when the meeting is absent.
    ///   - sentenceFetcher: Async closure returning sentence projections
    ///     oldest-first by timestamp.
    init(
        meetingID: PersistentIdentifier,
        summaryFetcher: @escaping @MainActor (PersistentIdentifier) async throws -> MeetingSummary?,
        sentenceFetcher: @escaping @MainActor (PersistentIdentifier) async throws -> [MeetingDetail.SentenceProjection]
    ) {
        self.meetingID = meetingID
        self.summaryFetcher = summaryFetcher
        self.sentenceFetcher = sentenceFetcher
    }

    /// Convenience initializer that closes over a live ``MeetingStore``
    /// + `meetingID`. Production wiring path; ``ContentView`` calls this
    /// when the active phase carries a non-nil meetingID.
    ///
    /// The summary fetcher delegates to ``MeetingStore/fetchAllUnfiltered()``
    /// + a Swift-side filter — the store has no `fetchSummary(meetingID:)`
    /// primitive and MVP-1 scale (~ten meetings) makes the full fetch a
    /// non-issue. Post-MVP optimization candidate: dedicated single-row
    /// lookup on ``MeetingStore``.
    ///
    /// - Parameters:
    ///   - store: The actor-backed read source.
    ///   - meetingID: The active meeting's `PersistentIdentifier`.
    convenience init(store: MeetingStore, meetingID: PersistentIdentifier) {
        self.init(
            meetingID: meetingID,
            summaryFetcher: { id in
                let all = try await store.fetchAllUnfiltered()
                return all.first { $0.id == id }
            },
            sentenceFetcher: { id in
                try await store.fetchSentences(meetingID: id)
            }
        )
    }

    // MARK: - Reload

    /// Pulls the summary + sentence projections across the actor hop.
    ///
    /// ## Atomicity
    ///
    /// Both fetchers must succeed for ``snapshot`` to land.
    ///
    /// - If either fetcher **throws**, the existing ``snapshot`` is
    ///   **preserved** and the error lands in ``loadError``. Preserving
    ///   the prior snapshot on failure prevents a transient store error
    ///   from collapsing the toolbar item; the next successful reload
    ///   reclaims the surface.
    /// - If the summary fetcher returns `nil` (the meeting was deleted
    ///   between phase transition and reload), ``snapshot`` is cleared
    ///   to `nil` and ``loadError`` remains `nil` — the toolbar item
    ///   hides cleanly because there is no transcript left to share.
    ///   This is a successful outcome of "nothing to share", not a
    ///   transient error.
    ///
    /// ## Error handling contract
    ///
    /// Errors are stored in ``loadError`` rather than thrown — SwiftUI
    /// views cannot throw, and the contract routes failures through
    /// the toolbar's render gate. The method **never throws out of the
    /// view body**. A successful reload clears ``loadError``.
    func reload() async {
        do {
            let summary = try await summaryFetcher(meetingID)
            let sentences = try await sentenceFetcher(meetingID)
            guard let summary else {
                // Meeting was deleted between phase transition and
                // reload. Treat as "no data to share" — clear the
                // snapshot so the toolbar item hides cleanly.
                snapshot = nil
                loadError = nil
                return
            }
            snapshot = Snapshot(summary: summary, sentences: sentences)
            loadError = nil
        } catch {
            loadError = error
        }
    }

    /// Bumps ``refreshTrigger`` to a fresh UUID, prompting SwiftUI's
    /// `.task(id:)` to re-run ``reload()``. Provided for symmetry with
    /// the other trio VMs; ``ContentView`` does not currently call this
    /// directly (the `.task(id:)` rebinds on `meetingID` change via the
    /// per-render VM re-derivation).
    func requestReload() {
        refreshTrigger = UUID()
    }
}
