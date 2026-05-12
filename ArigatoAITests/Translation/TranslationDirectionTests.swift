//
//  TranslationDirectionTests.swift
//  ArigatoAITests
//
//  Created by Jose Castell on 2026/05/12.
//

@testable import ArigatoAI
import Foundation
import Testing

@Suite("TranslationDirection shape and locked values")
struct TranslationDirectionTests {
    @Test("systemPrompt for .jaToEn matches the locked HF model-card string")
    func systemPrompt_jaToEn_returnsLockedString() {
        #expect(TranslationDirection.jaToEn.systemPrompt == "Translate to English.")
    }

    @Test("systemPrompt for .enToJa matches the locked HF model-card string")
    func systemPrompt_enToJa_returnsLockedString() {
        #expect(TranslationDirection.enToJa.systemPrompt == "Translate to Japanese.")
    }

    @Test("from(source: .ja) returns .jaToEn")
    func from_source_ja_returnsJaToEn() {
        #expect(TranslationDirection.from(source: .ja) == .jaToEn)
    }

    @Test("from(source: .en) returns .enToJa")
    func from_source_en_returnsEnToJa() {
        #expect(TranslationDirection.from(source: .en) == .enToJa)
    }

    @Test("source and target are correct for both directions")
    func source_and_target_are_correct_for_both_directions() {
        #expect(TranslationDirection.jaToEn.source == .ja)
        #expect(TranslationDirection.jaToEn.target == .en)
        #expect(TranslationDirection.enToJa.source == .en)
        #expect(TranslationDirection.enToJa.target == .ja)
    }

    @Test("TranslationGenerationParameters.recommended carries the locked HF model-card values")
    func recommendedGenerationParameters_carryLockedValues() {
        let recommended = TranslationGenerationParameters.recommended
        #expect(recommended.temperature == 0.5)
        #expect(recommended.topP == 1.0)
        #expect(recommended.minP == 0.1)
        #expect(recommended.repetitionPenalty == 1.05)
    }
}
