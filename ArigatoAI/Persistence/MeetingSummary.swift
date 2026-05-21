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
///
/// ## Step 12 addition — `firstMatchSnippet`
/// Step 12 adds the optional ``firstMatchSnippet`` projection. The store
/// populates this with the first body-matched sentence's
/// ``Sentence/translatedText`` when ``MeetingStore/fetchAll(searchText:)``
/// has a non-empty needle and the meeting matched via body (not title).
/// Title-only matches and the empty-needle path leave it `nil`. The view
/// row formatter (``MeetingListRowFormatter/snippet(_:maxLength:)``)
/// owns ellipsis / truncation; the DTO carries the raw matching sentence.
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
    /// First body-matched sentence's translated text when this summary was
    /// produced by ``MeetingStore/fetchAll(searchText:)`` with a non-empty
    /// needle and the match qualified via the sentence body (not via the
    /// title). `nil` otherwise — including for title-only matches, the
    /// empty-needle path, and any caller that goes through the
    /// no-snippet ``init(from:)`` overload.
    let firstMatchSnippet: String?

    /// Builds a `MeetingSummary` from a live `Meeting` model with no
    /// snippet attached (the Step 6 empty-needle / Step 11 detail path).
    ///
    /// Must be called from within ``MeetingStore``'s isolation context
    /// because `Meeting.sentences` is a SwiftData relationship and is
    /// not safe to touch across actor boundaries.
    ///
    /// Marked `nonisolated` for the same reason as the snippet-bearing
    /// sibling below — the nonisolated ``MeetingStore`` `@ModelActor`
    /// calls this from within its own isolation context, and all stored
    /// properties are `Sendable`. Without `nonisolated` the project-default
    /// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` makes this init
    /// MainActor-isolated, which produced the Swift 6 language-mode warning
    /// at ``MeetingStore/fetchAllUnfiltered()``'s `MeetingSummary(from:)` call site.
    nonisolated init(from meeting: Meeting) {
        self.init(from: meeting, firstMatchSnippet: nil)
    }

    /// Builds a `MeetingSummary` from a live `Meeting` model with an
    /// optional body-match snippet. Step 12's search path uses this
    /// overload; the no-snippet ``init(from:)`` is the convenience that
    /// passes `nil`.
    ///
    /// Must be called from within ``MeetingStore``'s isolation context
    /// because `Meeting.sentences` is a SwiftData relationship and is
    /// not safe to touch across actor boundaries.
    ///
    /// Marked `nonisolated` so the nonisolated ``MeetingStore`` `@ModelActor`
    /// can construct these projections without crossing an actor boundary.
    /// All stored properties are `Sendable`; the `@Model` read against
    /// `meeting` itself is the caller's responsibility (the store calls
    /// this only from within its own isolation context). The Step-6
    /// counterpart ``init(from:)`` is also marked `nonisolated` for the
    /// same reason — both inits run on the store's isolation context.
    ///
    /// - Parameters:
    ///   - meeting: Live model — read on the actor's isolation context.
    ///   - firstMatchSnippet: First body-matched sentence's translated
    ///     text, or `nil` for title-only / empty-needle / Step-6 / Step-11
    ///     callers.
    nonisolated init(from meeting: Meeting, firstMatchSnippet: String?) {
        id = meeting.persistentModelID
        startedAt = meeting.startedAt
        endedAt = meeting.endedAt
        title = meeting.title
        sentenceCount = meeting.sentences.count
        self.firstMatchSnippet = firstMatchSnippet
    }
}
