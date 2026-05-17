//
//  StorageStatsProvider.swift
//  ArigatoAI
//
//  Created by Jose Castell on 2026/05/17.
//

import Foundation

/// Immutable snapshot of on-device storage state surfaced by Settings (UI #19).
///
/// Built lazily in ``StorageStatsProviding/currentStats()`` so the
/// directory walk and the SwiftData fetch happen off the main actor.
///
/// ## Isolation
/// `nonisolated` because the project's default isolation is
/// `MainActor` (set via `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`).
/// `Settings` consumers hold this value across actor hops; the explicit
/// annotation makes the isolation contract unambiguous.
nonisolated struct StorageStats: Equatable {
    /// Cumulative byte size of the LFM2 prompt cache directory
    /// (`Caches/leap-cache/`). Includes every regular file under the
    /// root, recursively. Zero when the directory is absent or empty.
    let lfm2CacheBytes: Int64

    /// Count of ``Meeting`` rows currently persisted via
    /// ``MeetingStore``. Per D15-3 this is read by calling
    /// `MeetingStore.fetchAllUnfiltered().count` rather than via a
    /// dedicated count-only method.
    let transcriptCount: Int
}

/// Reads + clears storage state for the Settings surface (UI #19).
///
/// Mirrors the ``OnboardingCompletionStoring`` shape from Step 14 — a
/// `nonisolated` `Sendable` protocol with a production
/// `@unchecked Sendable` conformer that holds a thread-safe
/// `Foundation` reference. Tests inject lightweight fakes.
///
/// ## Isolation
/// `nonisolated` because consumers cross actor boundaries (the
/// ``MeetingStore`` `@ModelActor` resolves the transcript count
/// off-main, then the result returns to the main-actor
/// ``SettingsViewModel``).
nonisolated protocol StorageStatsProviding: Sendable {
    /// Returns current storage stats — directory walk + transcript count.
    ///
    /// ## Scheduling assumption
    /// Walks `Caches/leap-cache/` **off the main thread**. The
    /// production conformer dispatches the walk via
    /// `Task.detached(priority: .userInitiated)` so SwiftUI render
    /// remains responsive while ``SettingsViewModel/load()``
    /// awaits the result.
    ///
    /// Named violation test:
    /// `currentStats_walkDoesNotBlockMainThread_under10kSyntheticFiles`
    /// — seeds a temp directory with 10K small files, spawns
    /// `currentStats()` from the main actor, and asserts the main
    /// actor's `Task.yield()` heartbeat keeps advancing during the
    /// walk.
    ///
    /// - Throws: Re-throws any error raised by `FileManager` or by
    ///   the backing `MeetingStore` fetch. Missing cache directory is
    ///   NOT an error — that is reported as zero bytes.
    func currentStats() async throws -> StorageStats

    /// Removes the LFM2 prompt cache directory and re-creates an empty
    /// one in its place.
    ///
    /// Re-creating the directory after deletion preserves the invariant
    /// that downstream LEAP-SDK code (which creates intermediate
    /// directories on first cache write per
    /// ``LFM2CachePathResolver``'s comment) is operating against a
    /// stable parent directory at all times.
    ///
    /// ## Filesystem metadata cache lag
    /// The first ``currentStats()`` call **immediately** after this
    /// returns may still report non-zero bytes — APFS metadata
    /// counters are not synchronously consistent with directory
    /// deletion at the syscall layer. The lag clears within a few
    /// hundred milliseconds; ``SettingsViewModel/confirmPending()``
    /// documents this as a transient state.
    func clearPromptCache() async throws
}

/// Production conformer backed by `FileManager` and a live ``MeetingStore``.
///
/// ## `@unchecked Sendable` rationale
/// `FileManager` is documented thread-safe by Apple but is not formally
/// `Sendable` in the SDK. Mirrors
/// ``UserDefaultsOnboardingCompletionStore``'s `@unchecked Sendable`
/// rationale (Step 14). Every `FileManager` accessor used here
/// (`urls(for:in:)`, `removeItem(at:)`, `createDirectory(...)`,
/// `enumerator(at:...)`, `attributesOfItem(atPath:)`,
/// `fileExists(atPath:)`) is safe from any thread per Apple's
/// documentation.
///
/// ## Isolation
/// `nonisolated final class`. The walk runs on a detached `userInitiated`
/// task per the protocol's scheduling assumption.
final nonisolated class FileManagerStorageStatsProvider: StorageStatsProviding, @unchecked Sendable {
    private let fileManager: FileManager
    private let cachesDirectory: URL
    private let meetingStore: MeetingStore

    /// Designated initializer.
    ///
    /// - Parameters:
    ///   - fileManager: Defaults to `.default`. Tests inject a fresh
    ///     `FileManager()` instance scoped to a temp directory.
    ///   - cachesDirectory: Defaults to `nil`, which resolves to
    ///     `<Caches>/leap-cache/` per the LEAP SDK convention captured
    ///     in ``LFM2CachePathResolver``. Tests inject a temp URL so
    ///     state never leaks across test invocations.
    ///   - meetingStore: The actor used to read transcript count per
    ///     D15-3.
    init(
        fileManager: FileManager = .default,
        cachesDirectory: URL? = nil,
        meetingStore: MeetingStore
    ) {
        self.fileManager = fileManager
        if let cachesDirectory {
            self.cachesDirectory = cachesDirectory
        } else {
            // Resolve manually — `LFM2CachePathResolver.resolve()`
            // returns a `String` and throws on the (in-practice
            // impossible) "Caches directory missing" case. Both
            // behaviors are inconvenient here: the protocol contract
            // is "missing dir → zero bytes", not throw, and Foundation
            // works in `URL` natively. Replicating the small lookup
            // inline preserves the same subdirectory name
            // (`leap-cache`) without a force-unwrap.
            let cachesParent = fileManager
                .urls(for: .cachesDirectory, in: .userDomainMask)
                .first
                ?? URL(fileURLWithPath: NSTemporaryDirectory())
            self.cachesDirectory = cachesParent.appendingPathComponent(
                LFM2CachePathResolver.cacheSubdirectoryName,
                isDirectory: true
            )
        }
        self.meetingStore = meetingStore
    }

    func currentStats() async throws -> StorageStats {
        // Pull transcript count first — the MeetingStore actor hop is
        // cheap and serializes against pending writes (per Step 8
        // Amendment 3, the store's executor is off-main).
        let summaries = try await meetingStore.fetchAllUnfiltered()
        let transcriptCount = summaries.count

        // Walk the cache directory off the main thread. The dispatch
        // is the scheduling assumption documented on the protocol:
        // SwiftUI's render thread must keep ticking while this walks.
        let directory = cachesDirectory
        let fm = fileManager
        let bytes = try await Task.detached(priority: .userInitiated) { [directory, fm] () -> Int64 in
            try Self.directorySizeInBytes(at: directory, fileManager: fm)
        }.value

        return StorageStats(
            lfm2CacheBytes: bytes,
            transcriptCount: transcriptCount
        )
    }

    func clearPromptCache() async throws {
        let directory = cachesDirectory
        let fm = fileManager
        // Move both calls off the main thread for parity with
        // `currentStats()`. `removeItem(at:)` is normally fast, but a
        // populated `leap-cache/` may hold hundreds of files post-V3
        // `b851dad`; doing it on the main actor would risk a UI hitch.
        try await Task.detached(priority: .userInitiated) { [directory, fm] in
            if fm.fileExists(atPath: directory.path) {
                try fm.removeItem(at: directory)
            }
            try fm.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        }.value
    }

    /// Recursively sums the byte sizes of every regular file under
    /// `directory`. A missing directory returns 0 (not an error) —
    /// the LEAP SDK creates the directory on first cache write per
    /// ``LFM2CachePathResolver``'s comment, so "no directory" simply
    /// means "no cache yet" rather than a fault.
    ///
    /// - Throws: Re-throws errors from `FileManager.attributesOfItem`
    ///   for individual files. Individual unreadable files inside an
    ///   otherwise-readable directory still throw — clearing surface
    ///   problems is preferable to silently undercounting.
    private static func directorySizeInBytes(
        at directory: URL,
        fileManager: FileManager
    ) throws -> Int64 {
        guard fileManager.fileExists(atPath: directory.path) else {
            return 0
        }
        let resourceKeys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey]
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: resourceKeys,
            options: [.skipsHiddenFiles],
            errorHandler: nil
        ) else {
            return 0
        }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: Set(resourceKeys))
            if values.isRegularFile == true, let size = values.fileSize {
                total += Int64(size)
            }
        }
        return total
    }
}

/// Deferred-store conformer that resolves the live ``MeetingStore`` at
/// call time rather than at construction time.
///
/// ## Why this exists
/// ``AppBootstrapper`` publishes ``AppBootstrapper/meetingStore`` only
/// after the detached warmup task finishes (Amendment 3 / FB13399899 —
/// the `@ModelActor`'s synthesized executor must bind to a background
/// queue). The bootstrapper's `init` therefore cannot hand a live
/// `MeetingStore` reference to a stored
/// ``FileManagerStorageStatsProvider``. This conformer accepts a
/// `@Sendable () -> MeetingStore?` lookup closure that the bootstrapper
/// closes over with `[weak self]`; the provider asks for the live store
/// each time ``currentStats()`` is called.
///
/// ## Pre-warmup behavior
/// Settings is reachable from ``MeetingListView``'s toolbar; that
/// toolbar is only rendered when ``AppBootstrapper/meetingStore`` is
/// non-nil. So in practice the lookup closure always returns a live
/// store when this provider's methods are called. The defensive
/// `nil`-return path falls through to "transcript count = 0, cache
/// bytes still walked" rather than throwing — the user reaching
/// Settings before warmup is structurally impossible per the toolbar
/// gate, so a graceful fallback is the safer contract than a throw.
///
/// ## Isolation + Sendable
/// `nonisolated final class`, `@unchecked Sendable` mirrors
/// ``FileManagerStorageStatsProvider``'s rationale — `FileManager`
/// thread-safe but not formally `Sendable`. The stored lookup closure
/// is itself `@Sendable`.
final nonisolated class DeferredMeetingStoreStorageStatsProvider: StorageStatsProviding, @unchecked Sendable {
    private let fileManager: FileManager
    private let cachesDirectory: URL
    private let meetingStoreLookup: @Sendable () -> MeetingStore?

    /// Designated initializer.
    ///
    /// - Parameters:
    ///   - fileManager: Defaults to `.default`.
    ///   - cachesDirectory: Optional override; resolves to
    ///     `<Caches>/leap-cache/` when `nil`.
    ///   - meetingStoreLookup: `@Sendable` closure returning the
    ///     bootstrapper's live ``MeetingStore``. Production wiring
    ///     closes over `[weak bootstrapper]` so the provider does not
    ///     keep the bootstrapper alive past app lifetime.
    init(
        fileManager: FileManager = .default,
        cachesDirectory: URL? = nil,
        meetingStoreLookup: @escaping @Sendable () -> MeetingStore?
    ) {
        self.fileManager = fileManager
        if let cachesDirectory {
            self.cachesDirectory = cachesDirectory
        } else {
            let cachesParent = fileManager
                .urls(for: .cachesDirectory, in: .userDomainMask)
                .first
                ?? URL(fileURLWithPath: NSTemporaryDirectory())
            self.cachesDirectory = cachesParent.appendingPathComponent(
                LFM2CachePathResolver.cacheSubdirectoryName,
                isDirectory: true
            )
        }
        self.meetingStoreLookup = meetingStoreLookup
    }

    func currentStats() async throws -> StorageStats {
        let transcriptCount: Int
        if let store = meetingStoreLookup() {
            let summaries = try await store.fetchAllUnfiltered()
            transcriptCount = summaries.count
        } else {
            // Pre-warmup defensive fallback. The MeetingListView gear
            // toolbar gates Settings on `meetingStore != nil` so this
            // branch is structurally unreachable in production; the
            // graceful zero keeps `StorageStats` `Sendable` + `Equatable`
            // intact without forcing a throw.
            transcriptCount = 0
        }

        let directory = cachesDirectory
        let fm = fileManager
        let bytes = try await Task.detached(priority: .userInitiated) { [directory, fm] () -> Int64 in
            try FileManagerStorageStatsProvider.bytesUnder(directory, fileManager: fm)
        }.value

        return StorageStats(
            lfm2CacheBytes: bytes,
            transcriptCount: transcriptCount
        )
    }

    func clearPromptCache() async throws {
        let directory = cachesDirectory
        let fm = fileManager
        try await Task.detached(priority: .userInitiated) { [directory, fm] in
            if fm.fileExists(atPath: directory.path) {
                try fm.removeItem(at: directory)
            }
            try fm.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        }.value
    }
}

extension FileManagerStorageStatsProvider {
    /// Internal helper exposing the directory-size walk so
    /// ``DeferredMeetingStoreStorageStatsProvider`` can share the
    /// implementation without re-stating it. Marked `internal static`
    /// so tests can call directly if needed.
    static func bytesUnder(_ directory: URL, fileManager: FileManager) throws -> Int64 {
        try directorySizeInBytes(at: directory, fileManager: fileManager)
    }
}
