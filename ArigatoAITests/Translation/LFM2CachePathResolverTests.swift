//
//  LFM2CachePathResolverTests.swift
//  ArigatoAITests
//
//  Created by Jose Castell on 2026/05/15.
//

@testable import ArigatoAI
import Foundation
import Testing

@Suite("LFM2CachePathResolver")
struct LFM2CachePathResolverTests {
    @Test("resolve returns a path under the user's Caches directory ending with the leap-cache subdirectory")
    func resolve_returnsPathInCachesDirectoryEndingWithLeapCache() throws {
        let path = try LFM2CachePathResolver.resolve()
        // The path must end with the documented subdirectory name.
        #expect(path.hasSuffix("/\(LFM2CachePathResolver.cacheSubdirectoryName)"))
        // On the simulator the Caches directory is "/Caches" inside the app
        // sandbox; on devices it is similarly named. Either way the path
        // must contain "Caches" — making the test portable across the two.
        #expect(path.contains("/Caches/"))
        // Sanity: the path must be non-empty and absolute.
        #expect(!path.isEmpty)
        #expect(path.hasPrefix("/"))
    }

    @Test("cacheSubdirectoryName is the literal 'leap-cache' constant the plan documents")
    func cacheSubdirectoryName_isStableString() {
        #expect(LFM2CachePathResolver.cacheSubdirectoryName == "leap-cache")
    }
}
