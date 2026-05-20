//
//  ActiveMeetingShareViewModelTests.swift
//  ArigatoAITests
//
//  Created by Jose Castell on 2026/05/21.
//

@testable import ArigatoAI
import Foundation
import os
import SwiftData
import Testing

/// Tests for ``ActiveMeetingShareViewModel`` — the VM that backs the
/// B1.4 active-view toolbar `ShareLink` (UI #9 Context A).
///
/// ViewInspector is not a project dependency, so view-level rendering
/// is exercised indirectly via the VM's `reload()` contract +
/// snapshot-presence predicate. Tests construct the VM with
/// closure-injected fetchers, call ``ActiveMeetingShareViewModel/reload()``,
/// and inspect ``ActiveMeetingShareViewModel/snapshot`` /
/// ``ActiveMeetingShareViewModel/loadError``.
///
/// Marked `@MainActor` because the VM is `@MainActor` and the project
/// convention is `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`.
@Suite("ActiveMeetingShareViewModel")
@MainActor
struct ActiveMeetingShareViewModelTests {
    // MARK: - Helpers

    private static func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: Meeting.self, Sentence.self,
            configurations: config
        )
    }

    /// Mints a real `PersistentIdentifier` by inserting a throwaway
    /// `Meeting` into an in-memory container. `PersistentIdentifier`
    /// has no public initializer; the only legal source is a
    /// SwiftData-managed model instance.
    private static func mintIdentifier() throws -> PersistentIdentifier {
        let container = try makeContainer()
        let context = ModelContext(container)
        let m = Meeting(
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            title: "mint"
        )
        context.insert(m)
        try context.save()
        return m.persistentModelID
    }

    /// Builds a `MeetingSummary` value with the supplied identifier so
    /// the summary fetcher can return a deterministic payload.
    private static func makeSummary(
        id: PersistentIdentifier,
        title: String = "Test meeting",
        startedAt: Date = Date(timeIntervalSince1970: 1_700_000_000),
        endedAt: Date? = Date(timeIntervalSince1970: 1_700_001_800),
        sentenceCount: Int = 3
    ) throws -> MeetingSummary {
        // `MeetingSummary` has no public memberwise init — production
        // path is `init(from: Meeting)` which requires a live row.
        // We mint a row in a per-summary container so each test owns
        // an independent state slice.
        let container = try makeContainer()
        let context = ModelContext(container)
        let meeting = Meeting(startedAt: startedAt, title: title)
        meeting.endedAt = endedAt
        context.insert(meeting)
        for index in 0 ..< sentenceCount {
            let sentence = Sentence(
                timestamp: startedAt.addingTimeInterval(Double(index)),
                sourceLanguage: "ja",
                sourceText: "src \(index)",
                translatedText: "tr \(index)",
                sourceSegmentID: UUID(),
                searchableText: "src \(index) tr \(index)"
            )
            sentence.meeting = meeting
            context.insert(sentence)
        }
        try context.save()
        // Use the live row's projected summary so `sentenceCount`
        // matches what the production fetcher would produce. Tests
        // that need a specific `id` still pass `id` for the VM's
        // construction; the projection's `.id` may differ but the VM
        // only inspects the value it stores as `snapshot.summary`.
        _ = id
        return MeetingSummary(from: meeting)
    }

    /// Builds a fixed-shape projection without going through SwiftData.
    private static func makeProjection(
        id: PersistentIdentifier,
        timestamp: Date = Date(timeIntervalSince1970: 1_700_000_000),
        sourceLanguage: String = "ja",
        sourceText: String = "source",
        translatedText: String = "translated"
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

    // MARK: - 1. Initial state

    /// **B1.4-T-vm-1** — A freshly-constructed VM has a `nil` snapshot
    /// and `nil` loadError. The toolbar `ShareLink` keys off
    /// `snapshot != nil && snapshot.sentences.isEmpty == false`, so a
    /// fresh VM must NOT render a share button (UI #4 "buttons exist
    /// only when usable").
    @Test func viewModel_initialState_snapshotAndErrorAreNil() throws {
        let id = try Self.mintIdentifier()
        let vm = ActiveMeetingShareViewModel(
            meetingID: id,
            summaryFetcher: { _ in nil },
            sentenceFetcher: { _ in [] }
        )

        #expect(vm.snapshot == nil)
        #expect(vm.loadError == nil)
    }

    // MARK: - 2. Successful reload populates snapshot

    /// **B1.4-T-vm-2** — A successful reload populates ``snapshot``
    /// with the summary + sentence projections returned by the
    /// injected fetchers. Clears any prior ``loadError``.
    @Test func viewModel_reload_populatesSnapshotFromBothFetchers() async throws {
        let id = try Self.mintIdentifier()
        let summary = try Self.makeSummary(id: id, title: "ABC")
        let sentences = [
            Self.makeProjection(id: id, sourceText: "alpha"),
            Self.makeProjection(id: id, sourceText: "beta"),
        ]
        let vm = ActiveMeetingShareViewModel(
            meetingID: id,
            summaryFetcher: { _ in summary },
            sentenceFetcher: { _ in sentences }
        )

        await vm.reload()

        #expect(vm.snapshot != nil)
        #expect(vm.snapshot?.summary == summary)
        #expect(vm.snapshot?.sentences.count == 2)
        #expect(vm.snapshot?.sentences.first?.sourceText == "alpha")
        #expect(vm.loadError == nil)
    }

    // MARK: - 3. Summary fetcher returning nil clears snapshot

    /// **B1.4-T-vm-3** — When the summary fetcher returns `nil` (the
    /// meeting was deleted between phase transition and reload), the
    /// VM clears ``snapshot`` to `nil` so the toolbar item hides. The
    /// `loadError` remains `nil` because this is a "no data" outcome,
    /// not an error.
    @Test func viewModel_reload_summaryFetcherReturnsNil_clearsSnapshot() async throws {
        let id = try Self.mintIdentifier()
        let vm = ActiveMeetingShareViewModel(
            meetingID: id,
            summaryFetcher: { _ in nil },
            sentenceFetcher: { _ in [] }
        )

        await vm.reload()

        #expect(vm.snapshot == nil)
        #expect(vm.loadError == nil)
    }

    // MARK: - 4. Summary fetcher throw lands in loadError

    /// **B1.4-T-vm-4** — A throw from the summary fetcher records the
    /// error in ``loadError``. ``snapshot`` is preserved from the prior
    /// successful reload (atomic-fail-safe contract: a transient store
    /// error does not collapse the toolbar item if a usable snapshot
    /// was already loaded). Sentence fetcher is not called when the
    /// summary fetcher throws first.
    @Test func viewModel_reload_summaryFetcherThrows_recordsLoadError_preservesSnapshot() async throws {
        let id = try Self.mintIdentifier()
        let summary = try Self.makeSummary(id: id, title: "stable")
        let sentences = [Self.makeProjection(id: id, sourceText: "stable-row")]

        struct ProbeError: Error {}
        let throwOnNextCall = OSAllocatedUnfairLock(initialState: false)

        let vm = ActiveMeetingShareViewModel(
            meetingID: id,
            summaryFetcher: { _ in
                let shouldThrow = throwOnNextCall.withLock { $0 }
                if shouldThrow {
                    throw ProbeError()
                }
                return summary
            },
            sentenceFetcher: { _ in sentences }
        )

        // First reload — happy path lands a snapshot.
        await vm.reload()
        #expect(vm.snapshot != nil)
        #expect(vm.loadError == nil)

        // Flip the lock and reload again — the throw must NOT collapse
        // the prior snapshot.
        throwOnNextCall.withLock { $0 = true }
        await vm.reload()
        #expect(vm.snapshot != nil, "Snapshot should be preserved across a transient summary-fetcher throw")
        #expect(vm.loadError is ProbeError)
    }

    // MARK: - 5. Sentence fetcher throw lands in loadError

    /// **B1.4-T-vm-5** — A throw from the sentence fetcher records the
    /// error in ``loadError``. ``snapshot`` is preserved from the prior
    /// successful reload — mirrors the summary-fetcher throw path.
    @Test func viewModel_reload_sentenceFetcherThrows_recordsLoadError_preservesSnapshot() async throws {
        let id = try Self.mintIdentifier()
        let summary = try Self.makeSummary(id: id, title: "stable")
        let sentences = [Self.makeProjection(id: id, sourceText: "stable-row")]

        struct ProbeError: Error {}
        let throwOnNextCall = OSAllocatedUnfairLock(initialState: false)

        let vm = ActiveMeetingShareViewModel(
            meetingID: id,
            summaryFetcher: { _ in summary },
            sentenceFetcher: { _ in
                let shouldThrow = throwOnNextCall.withLock { $0 }
                if shouldThrow {
                    throw ProbeError()
                }
                return sentences
            }
        )

        // First reload populates the snapshot.
        await vm.reload()
        #expect(vm.snapshot != nil)
        #expect(vm.loadError == nil)

        // Flip the lock; the next reload throws inside the sentence
        // fetcher and must not collapse the prior snapshot.
        throwOnNextCall.withLock { $0 = true }
        await vm.reload()
        #expect(vm.snapshot != nil, "Snapshot should be preserved across a transient sentence-fetcher throw")
        #expect(vm.loadError is ProbeError)
    }

    // MARK: - 6. Successful reload after error clears loadError

    /// **B1.4-T-vm-6** — Once a reload succeeds after a prior throw,
    /// ``loadError`` is cleared. ``snapshot`` reflects the latest
    /// payload.
    @Test func viewModel_reload_successAfterError_clearsLoadError() async throws {
        let id = try Self.mintIdentifier()
        let summary = try Self.makeSummary(id: id, title: "recovered")
        let sentences = [Self.makeProjection(id: id, sourceText: "row")]

        struct ProbeError: Error {}
        let throwOnNextCall = OSAllocatedUnfairLock(initialState: true)

        let vm = ActiveMeetingShareViewModel(
            meetingID: id,
            summaryFetcher: { _ in
                let shouldThrow = throwOnNextCall.withLock { $0 }
                if shouldThrow {
                    throw ProbeError()
                }
                return summary
            },
            sentenceFetcher: { _ in sentences }
        )

        await vm.reload()
        #expect(vm.snapshot == nil)
        #expect(vm.loadError is ProbeError)

        // Flip the lock so the next call succeeds.
        throwOnNextCall.withLock { $0 = false }
        await vm.reload()
        #expect(vm.snapshot != nil)
        #expect(vm.loadError == nil)
    }

    // MARK: - 7. ShareLink visibility predicate (snapshot + non-empty sentences)

    /// **B1.4-T-vm-7** — The toolbar `ShareLink` visibility predicate
    /// reads `vm.snapshot != nil && !snapshot.sentences.isEmpty`. A VM
    /// whose summary fetcher returns a summary but whose sentence
    /// fetcher returns `[]` must NOT cause the toolbar item to render
    /// (UI #4 "buttons exist only when usable"). The VM exposes a
    /// non-nil snapshot in that case (atomicity contract — both fetches
    /// landed), and the caller-side guard `!snapshot.sentences.isEmpty`
    /// is what hides the button. This test locks the contract by
    /// asserting the snapshot's sentence count.
    @Test func viewModel_reload_emptySentenceFetcher_snapshotHasEmptySentences() async throws {
        let id = try Self.mintIdentifier()
        let summary = try Self.makeSummary(id: id, title: "empty")
        let vm = ActiveMeetingShareViewModel(
            meetingID: id,
            summaryFetcher: { _ in summary },
            sentenceFetcher: { _ in [] }
        )

        await vm.reload()

        #expect(vm.snapshot != nil, "Summary fetched successfully so snapshot exists.")
        #expect(vm.snapshot?.sentences.isEmpty == true, "Toolbar caller-side guard hides the ShareLink in this state.")
        #expect(vm.loadError == nil)
    }

    // MARK: - 8. requestReload bumps refreshTrigger

    /// **B1.4-T-vm-8** — ``ActiveMeetingShareViewModel/requestReload()``
    /// must mutate ``ActiveMeetingShareViewModel/refreshTrigger`` to a
    /// fresh `UUID`. Provided for trio symmetry with the other VMs;
    /// ``ContentView``'s toolbar wiring drives reload via `.task(id:)`
    /// on a phase-derived identity, so this code path is for future
    /// callers (notably any "refresh after delete-and-restore" gesture).
    @Test func viewModel_requestReload_bumpsRefreshTrigger() throws {
        let id = try Self.mintIdentifier()
        let vm = ActiveMeetingShareViewModel(
            meetingID: id,
            summaryFetcher: { _ in nil },
            sentenceFetcher: { _ in [] }
        )

        let initialTrigger = vm.refreshTrigger
        vm.requestReload()
        #expect(vm.refreshTrigger != initialTrigger)

        let secondTrigger = vm.refreshTrigger
        vm.requestReload()
        #expect(vm.refreshTrigger != secondTrigger)
    }

    // MARK: - 9. meetingID is captured by the closure-injected fetcher

    /// **B1.4-T-vm-9** — The injected fetchers receive the exact
    /// `meetingID` the VM was constructed with on every reload. Locks
    /// the contract that the VM's identifier is the source of truth
    /// for the fetcher (not a global, not a phase read, not a stale
    /// capture from a prior VM).
    @Test func viewModel_reload_passesMeetingIDToFetchers() async throws {
        let id = try Self.mintIdentifier()
        let observedSummaryID = OSAllocatedUnfairLock<PersistentIdentifier?>(initialState: nil)
        let observedSentenceID = OSAllocatedUnfairLock<PersistentIdentifier?>(initialState: nil)

        let vm = ActiveMeetingShareViewModel(
            meetingID: id,
            summaryFetcher: { identifier in
                observedSummaryID.withLock { $0 = identifier }
                return nil
            },
            sentenceFetcher: { identifier in
                observedSentenceID.withLock { $0 = identifier }
                return []
            }
        )

        await vm.reload()

        #expect(observedSummaryID.withLock { $0 } == id)
        #expect(observedSentenceID.withLock { $0 } == id)
    }
}
