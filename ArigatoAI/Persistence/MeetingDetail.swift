//
//  MeetingDetail.swift
//  ArigatoAI
//
//  Created by Jose Castell on 2026/05/16.
//

import Foundation
import SwiftData

/// Full `Sendable` projection of a ``Meeting`` and its sentences for
/// the detail view (decision #5 — transcript stays on screen after
/// STOP — and Context B of the export flow, decision #9).
///
/// Per `docs/PHASE_5_GROUP_D_DOC_RESEARCH.md` DR-1 §2 — `@Model` types
/// are not `Sendable` under Swift 6 strict concurrency. Cross-actor
/// return shapes from ``MeetingStore`` must be plain `Sendable`
/// structs. This DTO is constructed inside the actor's isolation
/// context (where touching `meeting.sentences` is legal) and handed
/// across the actor boundary as a value type.
///
/// Step 2 defines the shape; Step 11 consumes it from a forthcoming
/// `MeetingStore.fetchDetail(id:)` method.
struct MeetingDetail: Equatable {
    /// Stable persistent identifier — the only safe cross-actor handle
    /// to the underlying `Meeting`.
    let id: PersistentIdentifier
    /// Wall-clock time the meeting began.
    let startedAt: Date
    /// Wall-clock time the meeting ended. `nil` while still active.
    let endedAt: Date?
    /// Auto-derived display title (decision #12).
    let title: String
    /// Sentences belonging to this meeting, sorted by timestamp ascending.
    let sentences: [SentenceProjection]

    /// `Sendable` projection of a single ``Sentence``. Mirrors the
    /// `@Model` shape minus the back-reference to `Meeting`, which is
    /// already represented by the enclosing ``MeetingDetail/id``.
    struct SentenceProjection: Equatable {
        /// Stable persistent identifier for the underlying `Sentence`.
        let id: PersistentIdentifier
        /// Wall-clock timestamp the sentence was produced.
        let timestamp: Date
        /// ISO 639-1 source language tag — `"ja"` or `"en"`.
        let sourceLanguage: String
        /// Original transcribed text.
        let sourceText: String
        /// Translated text in the opposite language.
        let translatedText: String
        /// Upstream Whisper segment identifier.
        let sourceSegmentID: UUID
    }

    /// Builds a `MeetingDetail` from a live `Meeting` model.
    ///
    /// Must be called from within ``MeetingStore``'s isolation context
    /// because reading `Meeting.sentences` is a SwiftData relationship
    /// traversal and is not safe to touch across actor boundaries.
    init(from meeting: Meeting) {
        id = meeting.persistentModelID
        startedAt = meeting.startedAt
        endedAt = meeting.endedAt
        title = meeting.title
        sentences = meeting.sentences
            .sorted(by: { $0.timestamp < $1.timestamp })
            .map { sentence in
                SentenceProjection(
                    id: sentence.persistentModelID,
                    timestamp: sentence.timestamp,
                    sourceLanguage: sentence.sourceLanguage,
                    sourceText: sentence.sourceText,
                    translatedText: sentence.translatedText,
                    sourceSegmentID: sentence.sourceSegmentID
                )
            }
    }
}
