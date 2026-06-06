//
//  WhisperBundledModelTests.swift
//  ArigatoAITests
//
//  Created by Jose Castell on 2026/06/06.
//

@testable import ArigatoAI
import Foundation
import Testing

// MARK: - Suite

/// Locks the offline-packaging contract enforced by ``WhisperBundledModel``.
///
/// **The contract.** WhisperKit v1.0.0 loads the model offline only when the
/// app bundle physically contains, at its resource root, both tokenizer
/// files (`tokenizer.json`, `tokenizer_config.json`) AND the three CoreML
/// model packages WhisperKit loads by name (`MelSpectrogram.mlmodelc`,
/// `AudioEncoder.mlmodelc`, `TextDecoder.mlmodelc`). `download: false` does
/// **not** cover the tokenizer: WhisperKit's tokenizer loader carries an
/// unconditional HuggingFace fallback that fires silently when either
/// tokenizer file is absent. ``WhisperBundledModel/resolve(resourcePath:fileExists:)``
/// converts that silent network degradation into a typed
/// ``WhisperBundledModelError`` at construction time, and this suite locks
/// both halves of that guarantee:
///
/// - The pure-resolver tests drive
///   ``WhisperBundledModel/resolve(resourcePath:fileExists:)`` with an
///   injected `fileExists` stub (network-free, filesystem-free) so each
///   required asset's absence maps to its specific typed error.
/// - The single bundle-resolvability lock test (mirroring
///   `LFM2ModelLoaderTests` `T-migration-1`) asserts all five assets actually
///   resolve from the unit-test host bundle — the exact precondition the
///   production ``WhisperClientFactory/make`` depends on.
///
/// No concurrency/violation test is included: this code introduces no actor,
/// `AsyncStream`, `Task` spawn, async sequence, or new scheduling
/// assumption. The pure resolver is a synchronous value computation.
@Suite("WhisperBundledModel")
struct WhisperBundledModelTests {
    // MARK: Fixtures

    /// The bundle resource root used by the pure-resolver tests. Arbitrary —
    /// the resolver never touches the filesystem; presence is decided
    /// entirely by the injected `fileExists` stub.
    private static let resourceRoot = "/fake/bundle/resources"

    /// Builds a `fileExists` stub backed by a set of present asset *names*
    /// (relative to ``resourceRoot``). The returned closure answers `true`
    /// only for the absolute paths formed by appending a present name to the
    /// resource root, exactly as the resolver constructs them.
    private static func fileExistsStub(present names: Set<String>) -> (String) -> Bool {
        let presentPaths = Set(
            names.map { (resourceRoot as NSString).appendingPathComponent($0) }
        )
        return { presentPaths.contains($0) }
    }

    /// The full set of asset names that must be present for the resolver to
    /// succeed: both tokenizer files plus all three model packages. Drawn
    /// from the production source of truth so the test and resolver cannot
    /// drift.
    private static var allRequiredNames: Set<String> {
        Set(WhisperBundledModel.requiredTokenizerFiles)
            .union(WhisperBundledModel.requiredModelPackages)
    }

    // MARK: Pure-resolver branch tests

    @Test("W-bundled-1 all required assets present returns the resource path")
    func resolve_allAssetsPresent_returnsResourcePath() throws {
        let resolved = try WhisperBundledModel.resolve(
            resourcePath: Self.resourceRoot,
            fileExists: Self.fileExistsStub(present: Self.allRequiredNames)
        )
        #expect(resolved == Self.resourceRoot)
    }

    @Test("W-bundled-2 nil resource path throws bundleResourcePathUnavailable")
    func resolve_nilResourcePath_throwsBundleResourcePathUnavailable() {
        #expect(throws: WhisperBundledModelError.bundleResourcePathUnavailable) {
            _ = try WhisperBundledModel.resolve(
                resourcePath: nil,
                // Predicate is irrelevant: the nil-path guard fires first.
                fileExists: { _ in true }
            )
        }
    }

    @Test("W-bundled-3 missing tokenizer.json throws missingTokenizer")
    func resolve_missingTokenizerJSON_throwsMissingTokenizer() {
        let present = Self.allRequiredNames.subtracting(["tokenizer.json"])
        #expect(throws: WhisperBundledModelError.missingTokenizer) {
            _ = try WhisperBundledModel.resolve(
                resourcePath: Self.resourceRoot,
                fileExists: Self.fileExistsStub(present: present)
            )
        }
    }

    @Test("W-bundled-4 missing tokenizer_config.json throws missingTokenizerConfig")
    func resolve_missingTokenizerConfig_throwsMissingTokenizerConfig() {
        let present = Self.allRequiredNames.subtracting(["tokenizer_config.json"])
        #expect(throws: WhisperBundledModelError.missingTokenizerConfig) {
            _ = try WhisperBundledModel.resolve(
                resourcePath: Self.resourceRoot,
                fileExists: Self.fileExistsStub(present: present)
            )
        }
    }

    @Test("W-bundled-5 a missing model package throws missingModelPackage with its name")
    func resolve_missingModelPackage_throwsMissingModelPackageWithName() {
        let absent = "AudioEncoder.mlmodelc"
        let present = Self.allRequiredNames.subtracting([absent])
        #expect(throws: WhisperBundledModelError.missingModelPackage(absent)) {
            _ = try WhisperBundledModel.resolve(
                resourcePath: Self.resourceRoot,
                fileExists: Self.fileExistsStub(present: present)
            )
        }
    }

    // MARK: Bundle-resolvability lock test

    /// **W-bundled-6 — offline packaging lock.** Mirrors
    /// `LFM2ModelLoaderTests` `T-migration-1`: asserts that every one of the
    /// five assets the production ``WhisperClientFactory/make`` depends on for
    /// an offline load actually resolves from the bundle root in the
    /// unit-test host. This is the filesystem-backed half of the contract the
    /// pure-resolver tests cover by injection — if the model is dropped from
    /// the bundle, the build that runs this test fails loudly here rather than
    /// shipping an app that silently phones home on first transcription.
    ///
    /// Network-free: it only resolves bundle URLs (no SDK load, no
    /// transcription). It asserts two things:
    ///
    /// 1. Each asset is *resolvable* from the bundle
    ///    (`bundle.url(forResource:withExtension:)`).
    /// 2. **Flat-layout lock.** Each asset exists FLAT at the bundle resource
    ///    *root* (`resourcePath + "/" + name`) — the exact path
    ///    ``WhisperBundledModel/resolve(resourcePath:fileExists:)`` checks.
    ///    Step 1 alone is insufficient: `url(forResource:withExtension:)`
    ///    searches the bundle *recursively*, so it would pass even if a future
    ///    synchronized-group change nested the assets one level down — which
    ///    would break the production resolver and silently re-open the network
    ///    fallback. The flat check catches that regression.
    @Test("W-bundled-6 all five offline assets resolve flat at the bundle resource root")
    func bundle_resolvesAllFiveOfflineAssets() throws {
        // In the unit-test host process `Bundle.main` is the test runner; the
        // WhisperKit resources are flattened into the app bundle. Probe both
        // `Bundle.main` and the app bundle (reached via a test-defined anchor
        // type) so the assertion is robust to how the resources are hosted.
        let appBundle = Bundle(for: BundleProbe.self)

        func requireResolved(_ resource: String, _ ext: String) throws {
            let url = Bundle.main.url(forResource: resource, withExtension: ext)
                ?? appBundle.url(forResource: resource, withExtension: ext)
            let resolved = try #require(
                url,
                "Expected bundled WhisperKit asset \(resource).\(ext) to be resolvable from the bundle; the production offline-load factory guards on exactly this presence."
            )
            #expect(resolved.lastPathComponent == "\(resource).\(ext)")
        }

        try requireResolved("tokenizer", "json")
        try requireResolved("tokenizer_config", "json")
        try requireResolved("MelSpectrogram", "mlmodelc")
        try requireResolved("AudioEncoder", "mlmodelc")
        try requireResolved("TextDecoder", "mlmodelc")

        // Flat-layout lock: find the bundle whose resource ROOT holds
        // tokenizer.json directly (mirroring `Bundle.main.resourcePath` in
        // production), then assert ALL required assets are flat there. Names
        // are drawn from the production source of truth so the test cannot
        // drift from what `resolve` enforces.
        let hostRoot = try #require(
            [Bundle.main, appBundle].compactMap(\.resourcePath).first { root in
                FileManager.default.fileExists(
                    atPath: (root as NSString).appendingPathComponent("tokenizer.json")
                )
            },
            "Expected a bundle whose resource ROOT contains tokenizer.json flat — the layout WhisperBundledModel.resolve requires."
        )
        for name in WhisperBundledModel.requiredTokenizerFiles + WhisperBundledModel.requiredModelPackages {
            let flatPath = (hostRoot as NSString).appendingPathComponent(name)
            #expect(
                FileManager.default.fileExists(atPath: flatPath),
                "Expected \(name) flat at the bundle resource root; production WhisperBundledModel.resolve checks exactly this path and would silently fall back to the network if it moved."
            )
        }
    }
}

/// Empty anchor type whose defining bundle is the test bundle. Used by
/// ``WhisperBundledModelTests/bundle_resolvesAllFiveOfflineAssets`` to reach
/// the app bundle's resources under the unit-test host, mirroring
/// `LFM2ModelLoaderTests`' `BundleProbe`.
private final class BundleProbe {}
