//
//  StorageStatsProviderTests.swift
//  ArigatoAITests
//
//  Created by Jose Castell on 2026/05/17.
//

@testable import ArigatoAI
import Foundation
import SwiftData
import Testing

/// Step 15 — tests for ``FileManagerStorageStatsProvider``.
///
/// Each test uses a fresh temp directory scoped via UUID so state never
/// leaks across tests or test runs. The `MeetingStore` is in-memory so
/// transcript-count reads don't hit any persistent store.
@Suite("FileManagerStorageStatsProvider")
@MainActor
struct StorageStatsProviderTests {
    private static func makeStore() throws -> (ModelContainer, MeetingStore) {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Meeting.self, Sentence.self,
            configurations: config
        )
        return (container, MeetingStore(modelContainer: container))
    }

    private static func makeTempDirectory() -> URL {
        return FileManager.default
            .temporaryDirectory
            .appendingPathComponent("StorageStatsProviderTests-\(UUID().uuidString)", isDirectory: true)
    }

    /// Absent cache directory returns zero bytes, not a throw. The LEAP
    /// SDK creates the directory on first cache write per
    /// ``LFM2CachePathResolver``'s comment, so "no directory" simply
    /// means "no cache yet" — a graceful zero is the contract.
    @Test
    func currentStats_emptyCacheDir_returnsZeroBytes() async throws {
        let (_, meetingStore) = try Self.makeStore()
        let cacheDir = Self.makeTempDirectory()
        // Don't create the directory — verify the absent-dir path returns 0.

        let provider = FileManagerStorageStatsProvider(
            cachesDirectory: cacheDir,
            meetingStore: meetingStore
        )

        let stats = try await provider.currentStats()
        #expect(stats.lfm2CacheBytes == 0)
        #expect(stats.transcriptCount == 0)
    }

    /// **Concurrency design discipline — violation test for the
    /// off-main walk assumption.**
    ///
    /// Populates a temp directory with synthetic files, spawns
    /// `currentStats()` from the main actor, and concurrently runs a
    /// main-actor `Task.yield()` heartbeat loop. If the directory walk
    /// blocks main, the heartbeat counter cannot advance during the
    /// call; with the `Task.detached` dispatch documented on
    /// ``StorageStatsProviding/currentStats()``, the heartbeat ticks
    /// freely while the walk runs.
    ///
    /// Uses 10K synthetic files per the test ID named in
    /// ``StorageStatsProviding/currentStats()``'s doc-comment. Each file
    /// is one byte so total disk usage is bounded at ~10KB.
    @Test
    func currentStats_walkDoesNotBlockMainThread_under10kSyntheticFiles() async throws {
        let (_, meetingStore) = try Self.makeStore()
        let cacheDir = Self.makeTempDirectory()
        let fm = FileManager.default
        try fm.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: cacheDir) }

        // Seed 10K one-byte files. `Data([0x41]).write(to:)` is cheap.
        let payload = Data([0x41])
        for index in 0 ..< 10000 {
            let fileURL = cacheDir.appendingPathComponent("file-\(index).bin")
            try payload.write(to: fileURL)
        }

        let provider = FileManagerStorageStatsProvider(
            cachesDirectory: cacheDir,
            meetingStore: meetingStore
        )

        // Main-actor heartbeat. Counts how many times we get to run during
        // the walk. If main is blocked, this stays at 0 (or near it).
        let heartbeat = HeartbeatCounter()
        let heartbeatTask = Task { @MainActor in
            // Run until cancelled — each Task.yield gives the walk a
            // chance to progress and lets us tick.
            while !Task.isCancelled {
                heartbeat.tick()
                await Task.yield()
            }
        }

        let stats = try await provider.currentStats()
        heartbeatTask.cancel()
        _ = await heartbeatTask.value

        // Total bytes = 10K × 1 byte = 10_000.
        #expect(stats.lfm2CacheBytes == 10000)
        // Heartbeat advanced during the walk → main wasn't blocked.
        // We expect at least a handful of ticks; the exact count depends
        // on scheduler timing, but the floor of 2 is a generous lower
        // bound (one before the await, at least one during).
        #expect(heartbeat.count >= 2, "heartbeat was \(heartbeat.count) — main appears blocked during walk")
    }
}

/// Main-actor-only counter for the heartbeat test. Plain class —
/// mutations happen exclusively on the main actor inside the heartbeat
/// task, so no synchronisation is required.
@MainActor
private final class HeartbeatCounter {
    private(set) var count = 0
    func tick() {
        count += 1
    }
}
