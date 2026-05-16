//
//  Sentence.swift
//  ArigatoAI
//
//  Created by Jose Castell on 2026/05/16.
//

import Foundation
import SwiftData

/// SwiftData entity representing a single translated transcript pair
/// within a ``Meeting``.
///
/// Schema is locked by Group D UI decision #20, extended by Amendment 1
/// (`searchableText` field) per the pre-flight doc-research findings in
/// `docs/PHASE_5_GROUP_D_DOC_RESEARCH.md` §DR-3.
///
/// ## Search field rationale (Amendment 1)
/// `searchableText` is a pre-normalized projection of the source and
/// translated text used by ``MeetingStore/fetchAll(searchText:)`` in Step 2.
/// Normalization (hiragana→katakana + diacritic/case/width folding) fixes
/// the documented hiragana↔katakana gap in `localizedStandardContains`
/// and lets the predicate use plain `String.contains(_:)` against a
/// pre-folded needle (cheap full-table scan, no per-row locale call).
///
/// Per DR-3 §C, no `@Attribute(.spotlight)` or `#Index` annotation is
/// applied: SQLite's B-tree indexes cannot accelerate `%term%` substring
/// scans (sqlite.org optimizer overview), so an index would cost storage
/// and write speed for zero gain. FTS5 is the real fix if MVP search
/// feels slow, tracked under decision #14.
///
/// `searchableText` is populated at insert time by
/// `MeetingStore.appendSentence` (Step 2) via ``SearchTextNormalizer/normalize(_:)``.
@Model final class Sentence {
    /// Stable, client-generated primary key.
    var id: UUID
    /// Inverse side of the one-to-many relationship with ``Meeting``.
    /// Cascade delete is declared on the parent (`Meeting.sentences`).
    var meeting: Meeting?
    /// Wall-clock timestamp the sentence was produced.
    var timestamp: Date
    /// ISO 639-1 source language tag — `"ja"` or `"en"`.
    var sourceLanguage: String
    /// Original transcribed text in the source language.
    var sourceText: String
    /// Translated text in the opposite language.
    var translatedText: String
    /// Upstream Whisper segment identifier (debugging / correlation only).
    var sourceSegmentID: UUID
    /// Pre-normalized text for cheap substring search. Populated at
    /// insert time in Step 2 via ``SearchTextNormalizer/normalize(_:)``.
    /// See type-level comment for rationale.
    var searchableText: String

    /// Creates a new sentence entity.
    ///
    /// - Parameters:
    ///   - id: Stable primary key. Defaults to a fresh `UUID`.
    ///   - timestamp: Wall-clock time the sentence was produced.
    ///   - sourceLanguage: ISO 639-1 code, `"ja"` or `"en"`.
    ///   - sourceText: Original transcribed text.
    ///   - translatedText: Translated text in the opposite language.
    ///   - sourceSegmentID: Upstream Whisper segment identifier.
    ///   - searchableText: Pre-normalized text for search. Step 2 callers
    ///     pass `SearchTextNormalizer.normalize(sourceText + " " + translatedText)`.
    init(
        id: UUID = UUID(),
        timestamp: Date,
        sourceLanguage: String,
        sourceText: String,
        translatedText: String,
        sourceSegmentID: UUID,
        searchableText: String
    ) {
        self.id = id
        self.timestamp = timestamp
        self.sourceLanguage = sourceLanguage
        self.sourceText = sourceText
        self.translatedText = translatedText
        self.sourceSegmentID = sourceSegmentID
        self.searchableText = searchableText
    }
}
