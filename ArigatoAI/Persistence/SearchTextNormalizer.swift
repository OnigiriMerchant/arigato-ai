//
//  SearchTextNormalizer.swift
//  ArigatoAI
//
//  Created by Jose Castell on 2026/05/16.
//

import Foundation

/// Normalizes strings for cheap substring search across mixed
/// Japanese / English transcript content.
///
/// The pipeline is:
/// 1. Hiragana → Katakana via `CFStringTransform` (`.hiraganaToKatakana`)
///    so that "とうきょう" and "トウキョウ" collide.
/// 2. Locale-independent folding with `.diacriticInsensitive`,
///    `.caseInsensitive`, and `.widthInsensitive` so that "café" matches
///    "cafe", "ABC" matches "abc", and "１２３" matches "123".
///
/// Used by `MeetingStore.appendSentence` (Step 2) to populate
/// ``Sentence/searchableText`` at insert time, and by
/// `MeetingStore.fetchAll(searchText:)` (Step 12) to normalize the
/// search needle before matching.
///
/// ## Rationale (DR-3 §A)
/// `localizedStandardContains` is case- and diacritic-insensitive but
/// is **not** documented to match hiragana ↔ katakana — that transform
/// is a separate `StringTransform`. Pre-normalizing both sides closes
/// the correctness gap and additionally drops the per-row locale call,
/// which makes the full-table scan cheaper.
///
/// See `docs/PHASE_5_GROUP_D_DOC_RESEARCH.md` Amendment 1.
enum SearchTextNormalizer {
    /// Returns a search-normalized form of `s` suitable for substring
    /// comparison against another value produced by this method.
    ///
    /// The transform is idempotent: `normalize(normalize(x)) == normalize(x)`.
    ///
    /// - Parameter s: Arbitrary mixed-script input.
    /// - Returns: A folded, katakana-normalized string. Returns `s`
    ///   unchanged on the `applyingTransform` path only if the
    ///   transform itself produces `nil` (which is not expected for the
    ///   built-in `.hiraganaToKatakana` transform but is defensively handled).
    static func normalize(_ s: String) -> String {
        let katakana = (s as NSString)
            .applyingTransform(.hiraganaToKatakana, reverse: false) ?? s
        return katakana.folding(
            options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
    }
}
