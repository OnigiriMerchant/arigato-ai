//
//  WhisperModelVariantTests.swift
//  ArigatoAITests
//
//  Created by Jose Castell on 2026/05/10.
//

@testable import ArigatoAI
import Testing

@Suite("WhisperModelVariant")
struct WhisperModelVariantTests {
    @Test("default returns the large-v3-turbo variant")
    func default_isLargeV3Turbo() {
        #expect(WhisperModelVariant.default == .largeV3Turbo)
    }

    @Test("displayName for largeV3Turbo is human-readable and labels the model family")
    func displayName_largeV3Turbo_isHumanReadable() {
        let lowered = WhisperModelVariant.largeV3Turbo.displayName.lowercased()
        #expect(lowered.contains("large"))
        #expect(lowered.contains("v3"))
        #expect(lowered.contains("turbo"))
    }
}
