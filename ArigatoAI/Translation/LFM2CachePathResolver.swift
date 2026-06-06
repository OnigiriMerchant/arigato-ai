//
//  LFM2CachePathResolver.swift
//  ArigatoAI
//
//  Created by Jose Castell on 2026/05/15.
//

import Foundation

/// Resolves the on-disk path the LEAP iOS SDK uses for LFM2's prompt cache.
///
/// The path is computed at LFM2 load time and passed to
/// `LiquidCacheOptions.enabled(path:)`. Per Phase 5 Decision 4 (revised
/// 2026-05-15 after xcframework inspection — see PHASE_5_HANDOFF.md;
/// updated 2026-06-06 for the leap-sdk v0.10.9 migration, which retired the
/// `maxEntries`-bearing `LiquidCacheOptions(path:maxEntries:)` value-init in
/// favour of the `.enabled(path:)` factory), the cache lives in iOS's user
/// Caches directory: NOT iCloud-backed, may be purged by the OS under
/// storage pressure, and is rebuilt automatically on the next translation.
/// Privacy stance ("no cloud sync of transcripts") is preserved at
/// architecture level even with persistence enabled.
///
/// Scope:
/// - Caller-side concern is path string only; this resolver does NOT create
///   the directory. The LEAP SDK creates intermediate directories on first
///   cache write (Group C Step 2 verifies this — if it doesn't, the resolver
///   gains a `createDirectory(...)` call in a later checkpoint).
/// - This type is `nonisolated`. The OS Caches lookup is not actor-isolated
///   and the returned string is `Sendable`.
public nonisolated enum LFM2CachePathResolver {
    /// The trailing component appended to the Caches directory URL.
    public static let cacheSubdirectoryName = "leap-cache"

    /// Returns an absolute filesystem path under the user's Caches directory
    /// suitable for `LiquidCacheOptions.enabled(path:)`.
    ///
    /// - Throws: ``TranslationError/cachePathResolutionFailed(_:)`` if
    ///   `FileManager.urls(for:in:)` returns an empty array. On real iOS
    ///   devices this does not happen — the sandbox guarantees a Caches
    ///   directory exists. The case exists so callers can surface a typed
    ///   error instead of force-unwrapping.
    public static func resolve() throws -> String {
        let candidates = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)
        guard let cachesDirectory = candidates.first else {
            throw TranslationError.cachePathResolutionFailed(
                "FileManager.urls(for: .cachesDirectory, in: .userDomainMask) returned an empty array"
            )
        }
        return cachesDirectory
            .appendingPathComponent(cacheSubdirectoryName)
            .path
    }
}
