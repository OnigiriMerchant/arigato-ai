//
//  SettingsViewModelTests.swift
//  ArigatoAITests
//
//  Created by Jose Castell on 2026/05/17.
//

@testable import ArigatoAI
import Foundation
import os
import SwiftData
import Testing

/// Step 15 — tests for ``SettingsViewModel``.
///
/// Covers the load round-trip, request/cancel/confirm state machine,
/// destructive-op routing, and the re-entry guard documented as
/// Assumption 1 on ``SettingsViewModel``.
@Suite("SettingsViewModel")
@MainActor
struct SettingsViewModelTests {
    /// Builds an in-memory `ModelContainer` + ``MeetingStore``. Returned
    /// pair stays in test scope so the actor is not deallocated mid-call.
    private static func makeStore() throws -> (ModelContainer, MeetingStore) {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Meeting.self, Sentence.self,
            configurations: config
        )
        return (container, MeetingStore(modelContainer: container))
    }

    /// On success, ``load()`` populates ``SettingsViewModel/stats`` with
    /// the provider's snapshot and clears any prior error.
    @Test
    func load_success_publishesStats() async throws {
        let (_, meetingStore) = try Self.makeStore()
        let provider = FakeStorageStatsProvider()
        await provider.setStats(StorageStats(lfm2CacheBytes: 4096, transcriptCount: 7))

        let model = SettingsViewModel(statsProvider: provider, meetingStore: meetingStore)
        await model.load()

        #expect(model.stats?.lfm2CacheBytes == 4096)
        #expect(model.stats?.transcriptCount == 7)
        #expect(model.loadError == nil)
    }

    /// A throwing provider sets ``loadError`` and leaves ``stats``
    /// untouched (per the doc-comment: prior figure survives transient
    /// post-destructive-op reloads).
    @Test
    func load_throwingProvider_setsLoadError_statsRemainsNil() async throws {
        let (_, meetingStore) = try Self.makeStore()
        let provider = FakeStorageStatsProvider()
        await provider.setError(FakeStatsError.boom)

        let model = SettingsViewModel(statsProvider: provider, meetingStore: meetingStore)
        await model.load()

        #expect(model.stats == nil)
        #expect(model.loadError != nil)
        #expect((model.loadError as? FakeStatsError) == .boom)
    }

    /// ``requestClearCache()`` sets ``pending`` to ``.clearCache`` so the
    /// confirmation dialog presents.
    @Test
    func requestClearCache_setsPendingClearCache() throws {
        let (_, meetingStore) = try Self.makeStore()
        let provider = FakeStorageStatsProvider()
        let model = SettingsViewModel(statsProvider: provider, meetingStore: meetingStore)

        model.requestClearCache()

        #expect(model.pending == .clearCache)
    }

    /// Cancel-pending zeroes out ``pending``. Idempotent.
    @Test
    func cancelPending_resetsPendingToNil() throws {
        let (_, meetingStore) = try Self.makeStore()
        let provider = FakeStorageStatsProvider()
        let model = SettingsViewModel(statsProvider: provider, meetingStore: meetingStore)

        model.requestDeleteAll()
        #expect(model.pending == .deleteAll)

        model.cancelPending()
        #expect(model.pending == nil)

        // Idempotent — a second cancel is a no-op rather than a throw.
        model.cancelPending()
        #expect(model.pending == nil)
    }

    /// Clear-cache happy path: provider is invoked once, stats are
    /// reloaded post-clear, and ``lastActionResult`` carries
    /// ``ActionResult/cleared(reclaimedBytes:)`` populated from the
    /// pre-clear ``StorageStats/lfm2CacheBytes``.
    @Test
    func confirmPending_clearCache_callsProvider_reloadsStats_publishesResult() async throws {
        let (_, meetingStore) = try Self.makeStore()
        let provider = FakeStorageStatsProvider()
        await provider.setStats(StorageStats(lfm2CacheBytes: 512, transcriptCount: 0))

        let model = SettingsViewModel(statsProvider: provider, meetingStore: meetingStore)
        await model.load()
        #expect(model.stats?.lfm2CacheBytes == 512)

        // After clear, the provider's stats are mutated to "post-clear"
        // so reload reflects the new figure.
        model.requestClearCache()
        await provider.setStats(StorageStats(lfm2CacheBytes: 0, transcriptCount: 0))
        await model.confirmPending()

        let clearCount = await provider.clearCallCount
        #expect(clearCount == 1)
        #expect(model.pending == nil)
        #expect(model.isClearingCache == false)
        if case let .cleared(reclaimedBytes) = model.lastActionResult {
            #expect(reclaimedBytes == 512)
        } else {
            Issue.record("Expected .cleared, got \(String(describing: model.lastActionResult))")
        }
        // Reload after clear → cache size now 0.
        #expect(model.stats?.lfm2CacheBytes == 0)
    }

    /// Delete-all happy path: store is hit, reload runs, result carries
    /// the deletion count.
    @Test
    func confirmPending_deleteAll_callsStore_reloadsStats_publishesResult_withCount() async throws {
        let (_, meetingStore) = try Self.makeStore()
        _ = try await meetingStore.startMeeting(startedAt: Date(), title: "One")
        _ = try await meetingStore.startMeeting(startedAt: Date(), title: "Two")
        _ = try await meetingStore.startMeeting(startedAt: Date(), title: "Three")

        let provider = FakeStorageStatsProvider()
        await provider.setStats(StorageStats(lfm2CacheBytes: 0, transcriptCount: 3))

        let model = SettingsViewModel(statsProvider: provider, meetingStore: meetingStore)
        await model.load()

        model.requestDeleteAll()
        // After delete, the provider's stats are mutated to reflect zero
        // transcripts so the post-action reload publishes the new figure.
        await provider.setStats(StorageStats(lfm2CacheBytes: 0, transcriptCount: 0))
        await model.confirmPending()

        #expect(model.pending == nil)
        #expect(model.isDeletingAll == false)
        if case let .deleted(count) = model.lastActionResult {
            #expect(count == 3)
        } else {
            Issue.record("Expected .deleted, got \(String(describing: model.lastActionResult))")
        }
        #expect(model.stats?.transcriptCount == 0)

        // Durability: the store actually no longer has rows.
        let remaining = try await meetingStore.fetchAllUnfiltered()
        #expect(remaining.isEmpty)
    }

    /// **Concurrency design discipline — violation test for Assumption 1.**
    ///
    /// Spawns two concurrent ``confirmPending()`` calls against a fake
    /// whose `clearPromptCache` blocks on a signal. The first call wins
    /// the re-entry guard and reaches the await; the second call sees
    /// `isClearingCache == true` and returns immediately. Result: the
    /// provider records exactly one invocation regardless of timing.
    @Test
    func confirmPending_whileInFlight_isNoOp() async throws {
        let (_, meetingStore) = try Self.makeStore()
        let provider = FakeStorageStatsProvider()
        await provider.setStats(StorageStats(lfm2CacheBytes: 1024, transcriptCount: 0))
        await provider.blockClear()

        let model = SettingsViewModel(statsProvider: provider, meetingStore: meetingStore)
        model.requestClearCache()

        // Spawn the first confirm in a detached task — its `clearPromptCache`
        // will block on the gate.
        let first = Task { await model.confirmPending() }

        // Wait briefly for the first task to enter `performClearCache` and
        // flip `isClearingCache = true` so the second invocation observes
        // the busy flag. Polling against `model.isClearingCache` is
        // race-free because we're on the same main actor.
        try await waitUntilTrue(timeout: .seconds(1)) {
            await MainActor.run { model.isClearingCache }
        }

        // Re-request before signaling — second confirm hits the re-entry
        // guard.
        model.requestClearCache()
        await model.confirmPending()

        // Now release the first task.
        await provider.releaseClear()
        await first.value

        let clearCount = await provider.clearCallCount
        #expect(clearCount == 1)
    }

    /// Helper: polls until `predicate()` returns true, throwing on timeout.
    /// Used by ``confirmPending_whileInFlight_isNoOp`` to wait for the
    /// busy flag to flip without a fixed sleep.
    private func waitUntilTrue(
        timeout: Duration,
        predicate: @escaping @Sendable () async -> Bool
    ) async throws {
        let start = ContinuousClock.now
        while ContinuousClock.now - start < timeout {
            if await predicate() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        Issue.record("waitUntilTrue timed out after \(timeout)")
    }
}

/// Lock-protected fake conforming to ``StorageStatsProviding`` for unit
/// tests. `actor` so reads + mutations of the canned stats / error /
/// counters don't need explicit synchronisation.
private actor FakeStorageStatsProvider: StorageStatsProviding {
    private var stats: StorageStats = .init(lfm2CacheBytes: 0, transcriptCount: 0)
    private var error: Error?
    private var clearError: Error?
    private(set) var clearCallCount = 0
    private(set) var currentStatsCallCount = 0
    private var clearGate: CheckedContinuation<Void, Never>?
    private var pendingBlockClear = false

    func setStats(_ stats: StorageStats) {
        self.stats = stats
    }

    func setError(_ error: Error?) {
        self.error = error
    }

    func setClearError(_ error: Error?) {
        clearError = error
    }

    /// Arms the clear-cache gate so the next `clearPromptCache()` call
    /// blocks until ``releaseClear()`` is called.
    func blockClear() {
        pendingBlockClear = true
    }

    func releaseClear() {
        if let cont = clearGate {
            clearGate = nil
            cont.resume()
        } else {
            pendingBlockClear = false
        }
    }

    nonisolated func currentStats() async throws -> StorageStats {
        try await currentStatsImpl()
    }

    private func currentStatsImpl() async throws -> StorageStats {
        currentStatsCallCount += 1
        if let error { throw error }
        return stats
    }

    nonisolated func clearPromptCache() async throws {
        try await clearPromptCacheImpl()
    }

    private func clearPromptCacheImpl() async throws {
        clearCallCount += 1
        if pendingBlockClear {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                clearGate = cont
            }
            pendingBlockClear = false
        }
        if let clearError { throw clearError }
    }
}

/// Local error used to populate ``FakeStorageStatsProvider``'s throw path.
private enum FakeStatsError: Error, Equatable {
    case boom
}
