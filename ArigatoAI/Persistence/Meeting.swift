//
//  Meeting.swift
//  ArigatoAI
//
//  Created by Jose Castell on 2026/05/16.
//

import Foundation
import SwiftData

/// SwiftData entity representing a single recorded meeting session.
///
/// A `Meeting` is the top-level aggregate for the persistence layer.
/// It owns an ordered collection of ``Sentence`` rows representing the
/// JA↔EN transcript pairs produced during the session.
///
/// Schema is locked by Group D UI decision #20:
/// - ``id`` — primary key, generated client-side.
/// - ``startedAt`` — wall-clock time the session began.
/// - ``endedAt`` — wall-clock time the session was stopped, `nil` while active.
/// - ``title`` — auto-derived per decision #12 (MVP 1: first English sentence + timestamp).
/// - ``sentences`` — one-to-many relationship with cascade delete on the inverse.
///
/// ## Cascade delete contract
/// Deleting a `Meeting` removes every associated `Sentence` row in the same save.
/// The cascade is declared on this side of the relationship via
/// `@Relationship(deleteRule: .cascade, inverse: \Sentence.meeting)`.
///
/// Regression coverage for the FB13640004 cascade-delete failure mode
/// (Apple Developer Forums 740649) lives in
/// `MeetingEntityTests.cascadeDelete_afterExplicitPreDeleteSave_stillRemovesOrphanSentences`.
@Model final class Meeting {
    /// Stable, client-generated primary key.
    var id: UUID
    /// Wall-clock time the meeting began.
    var startedAt: Date
    /// Wall-clock time the meeting ended. `nil` while the meeting is active.
    var endedAt: Date?
    /// Auto-derived title (decision #12). Replaced by Foundation Models
    /// summarization in Phase 6+; storage shape unchanged.
    var title: String
    /// Ordered collection of transcript sentences. Cascade delete is
    /// enforced from the `Meeting` side via the inverse key path on
    /// ``Sentence/meeting``.
    @Relationship(deleteRule: .cascade, inverse: \Sentence.meeting)
    var sentences: [Sentence]

    /// Creates a new meeting entity.
    ///
    /// - Parameters:
    ///   - id: Stable primary key. Defaults to a fresh `UUID`.
    ///   - startedAt: Wall-clock start time.
    ///   - endedAt: Wall-clock end time, or `nil` if still active.
    ///   - title: Auto-derived display title (see decision #12).
    ///   - sentences: Initial sentence rows. Defaults to empty.
    init(
        id: UUID = UUID(),
        startedAt: Date,
        endedAt: Date? = nil,
        title: String,
        sentences: [Sentence] = []
    ) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.title = title
        self.sentences = sentences
    }
}
