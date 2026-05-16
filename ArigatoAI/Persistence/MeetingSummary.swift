//
//  MeetingSummary.swift
//  ArigatoAI
//
//  Created by Jose Castell on 2026/05/16.
//

import Foundation
import SwiftData

/// Lightweight `Sendable` projection of a ``Meeting`` for the history
/// list view (decision #13).
///
/// Per `docs/PHASE_5_GROUP_D_DOC_RESEARCH.md` DR-1 §2 — `@Model` types
/// are not `Sendable` under Swift 6 strict concurrency. Cross-actor
/// return shapes from ``MeetingStore`` must be plain `Sendable`
/// structs. This DTO is constructed inside the actor's isolation
/// context (where reading `meeting.sentences.count` is legal) and
/// handed across the actor boundary as a value type.
///
/// Step 2 defines the shape; Step 12 produces these from
/// `MeetingStore.fetchAll(searchText:)`.
struct MeetingSummary: Equatable {
    /// Stable persistent identifier — the only safe cross-actor handle
    /// to the underlying `Meeting`.
    let id: PersistentIdentifier
    /// Wall-clock time the meeting began.
    let startedAt: Date
    /// Wall-clock time the meeting ended. `nil` while still active.
    let endedAt: Date?
    /// Auto-derived display title (decision #12).
    let title: String
    /// Number of sentences captured in this meeting.
    let sentenceCount: Int

    /// Builds a `MeetingSummary` from a live `Meeting` model.
    ///
    /// Must be called from within ``MeetingStore``'s isolation context
    /// because `Meeting.sentences` is a SwiftData relationship and is
    /// not safe to touch across actor boundaries.
    init(from meeting: Meeting) {
        id = meeting.persistentModelID
        startedAt = meeting.startedAt
        endedAt = meeting.endedAt
        title = meeting.title
        sentenceCount = meeting.sentences.count
    }
}
