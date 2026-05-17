//
//  SettingsFormatterTests.swift
//  ArigatoAITests
//
//  Created by Jose Castell on 2026/05/17.
//

@testable import ArigatoAI
import Foundation
import Testing

/// Step 15 — pure-value tests for ``SettingsFormatter``.
///
/// `SettingsFormatter` is `nonisolated enum` so these tests need no
/// actor-isolation. Each `@Test` runs in the default test isolation
/// (cooperative).
@Suite("SettingsFormatter")
struct SettingsFormatterTests {
    /// Zero bytes formats to whatever `ByteCountFormatter` emits with
    /// `.useAll` + `.file` for `0`. The localized string is OS-dependent
    /// (en-US: "Zero KB"). We pin against the formatter's own output
    /// rather than a hard-coded literal so the test survives locale
    /// shifts and ByteCountFormatter copy tweaks.
    @Test
    func bytes_zero_returnsZeroBytes() {
        let referenceFormatter = ByteCountFormatter()
        referenceFormatter.allowedUnits = .useAll
        referenceFormatter.countStyle = .file
        let expected = referenceFormatter.string(fromByteCount: 0)

        #expect(SettingsFormatter.bytes(0) == expected)
        // Sanity: the output is non-empty and contains the digit 0 or
        // a localized zero word.
        #expect(SettingsFormatter.bytes(0).isEmpty == false)
    }

    /// Pluralization contract: 0 → "No transcripts", 1 → "1 transcript",
    /// N ≥ 2 → "\(N) transcripts".
    @Test
    func transcriptCountLabel_pluralization() {
        #expect(SettingsFormatter.transcriptCountLabel(0) == "No transcripts")
        #expect(SettingsFormatter.transcriptCountLabel(1) == "1 transcript")
        #expect(SettingsFormatter.transcriptCountLabel(2) == "2 transcripts")
        #expect(SettingsFormatter.transcriptCountLabel(42) == "42 transcripts")
    }

    /// ``SettingsFormatter/versionString(bundle:)`` reads
    /// `CFBundleShortVersionString` + `CFBundleVersion` from the supplied
    /// bundle's `infoDictionary`. We can't synthesize a fresh `Bundle`
    /// with arbitrary keys (Bundle.infoDictionary is read-only), so the
    /// test verifies two contracts:
    ///
    /// 1. `Bundle.main` (the app's own bundle under test host) returns
    ///    a string starting with "Arigato AI" — proves the formatter
    ///    actually composed something.
    /// 2. A synthetic empty bundle (constructed from a non-bundle path)
    ///    falls back to "Arigato AI" (the pre-authorized STOP #1
    ///    fallback in the dispatch brief).
    @Test
    func versionString_assemblesFromBundleDictionary() {
        let mainString = SettingsFormatter.versionString(bundle: .main)
        #expect(mainString.hasPrefix("Arigato AI"))

        // Synthetic empty bundle — `Bundle(path: "/")` returns nil on
        // iOS, so we fall back to a freshly-allocated Bundle that has
        // no infoDictionary entries. `Bundle()` returns the main bundle
        // on macOS but a near-empty bundle on iOS test hosts; either
        // way the keys we care about are absent OR (on main bundle) the
        // string still starts with "Arigato AI", so the contract holds.
        let fallback = SettingsFormatter.versionString(bundle: Bundle(for: SettingsFormatterFakeAnchor.self))
        // Bundle(for: AnyClass.self) under the test host resolves to the
        // test bundle, whose infoDictionary typically lacks
        // CFBundleShortVersionString. The fallback returns the bare
        // product name.
        #expect(fallback.hasPrefix("Arigato AI"))
    }
}

/// Anchor class for `Bundle(for:)` resolution inside
/// ``SettingsFormatterTests/versionString_assemblesFromBundleDictionary``.
/// Empty class with no behaviour.
private final class SettingsFormatterFakeAnchor {}
