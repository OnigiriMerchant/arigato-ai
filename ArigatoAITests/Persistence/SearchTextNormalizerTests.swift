//
//  SearchTextNormalizerTests.swift
//  ArigatoAITests
//
//  Created by Jose Castell on 2026/05/16.
//

@testable import ArigatoAI
import Foundation
import Testing

/// Tests for ``SearchTextNormalizer`` — Amendment 1 of the Group D
/// pre-flight doc-research findings.
///
/// The normalizer is the only thing that closes the documented
/// hiragana↔katakana correctness gap in `localizedStandardContains`,
/// so the suite asserts each piece of the transform independently
/// plus an idempotence property.
struct SearchTextNormalizerTests {
    /// Hiragana input must surface as katakana so that a search for
    /// "こんにちは" finds a document containing "コンニチハ".
    @Test func normalize_hiraganaInput_producesKatakanaOutput() {
        let output = SearchTextNormalizer.normalize("こんにちは")
        #expect(output.contains("コンニチハ"))
    }

    /// Full-width digits must fold to ASCII half-width digits via
    /// `.widthInsensitive`. The output is expected to be exactly the
    /// half-width form because there is no other transform applied to
    /// pure-digit input.
    @Test func normalize_fullWidthDigits_foldToHalfWidth() {
        let output = SearchTextNormalizer.normalize("１２３")
        #expect(output == "123")
    }

    /// Combining diacritics must be stripped by `.diacriticInsensitive`
    /// so that "café" matches "cafe".
    @Test func normalize_diacriticsStripped() {
        let output = SearchTextNormalizer.normalize("café")
        #expect(output == "cafe")
    }

    /// Applying the normalizer twice must produce the same result as
    /// applying it once — required because the same function is used
    /// both at insert time (against `Sentence.sourceText` / `translatedText`)
    /// and at query time (against the user's search needle).
    @Test func normalize_isIdempotent() {
        let input = "Café　東京 とうきょう １２３ ABC"
        let once = SearchTextNormalizer.normalize(input)
        let twice = SearchTextNormalizer.normalize(once)
        #expect(once == twice)
    }
}
