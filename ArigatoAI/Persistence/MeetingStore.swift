//
//  MeetingStore.swift
//  ArigatoAI
//
//  Created by Jose Castell on 2026/05/16.
//

import Foundation
import SwiftData

/// Owns all SwiftData reads and writes for ``Meeting`` / ``Sentence``
/// entities. First `@ModelActor` in the project — every other layer
/// in Group D talks to persistence through this actor.
///
/// ## Scheduling assumption
/// This actor runs on its own executor — **not** the main actor. Step 8
/// (AppBootstrapper wiring) must initialize this via
/// `Task.detached { ... }` per Apple Developer Forums 736226 /
/// FB13399899, which documents `@ModelActor` inheriting the main
/// thread when initialized from a `@MainActor` context. A
/// main-thread-not-blocked violation test will be added in Step 8
/// (per Amendment 3 in `docs/PHASE_5_GROUP_D_DOC_RESEARCH.md`) —
/// Step 2 does not include that test.
///
/// ## Sendable boundary
/// Returns DTOs (``MeetingSummary``, ``MeetingDetail``) — never raw
/// `@Model` instances. Per Apple DTS guidance (Apple Developer Forums
/// thread 805409): "Do not return SwiftData Models from your
/// ModelActor … Only return sole properties and the
/// `persistentModelID` to identify models." Returning a `@Model` across
/// actor boundaries fails Swift 6 strict concurrency at compile time
/// (see `docs/PHASE_5_GROUP_D_DOC_RESEARCH.md` DR-1 §2).
///
/// ## Group D step boundary
/// `fetchAll(searchText:)` is intentionally absent from Step 2 — it
/// lands in Step 12 with Amendment 2's flat-`Sentence`-fetch +
/// group-by-meeting projection. Step 2 covers only the write paths
/// plus deletion.
///
/// ## "Meeting not found" resolution
/// All mutating methods that take an existing meeting's
/// `PersistentIdentifier` resolve it via a `FetchDescriptor<Meeting>`
/// whose `#Predicate` matches on `persistentModelID`, **not** via
/// `ModelContext.model(for:)` or `ModelContext.registeredModel(for:)`.
/// `model(for:)` returns a non-optional `any PersistentModel` and
/// crashes inside SwiftData when handed a stale identifier (verified
/// empirically during Step 2 development against a deleted meeting's
/// ID). `registeredModel(for:)` returns optional but evicts entries
/// post-save, which is unsafe for the valid-ID case the actor must
/// support. The fetch-by-predicate pattern is the safe primitive:
/// returns `nil` on stale IDs (translated to
/// ``MeetingStoreError/meetingNotFound(_:)``) and returns the live
/// model on valid IDs. See
/// `MeetingStoreTests.appendSentence_meetingNotFound_throwsMeetingStoreError`
/// which exercises the stale-ID path. Diagnosis on 2026-05-16 by
/// @swift-implementer.
@ModelActor
actor MeetingStore {
    /// Inserts a new ``Meeting`` and returns its persistent identifier
    /// so callers can address the meeting on subsequent calls without
    /// holding a non-Sendable `@Model` reference across actor boundaries.
    ///
    /// - Parameters:
    ///   - startedAt: Wall-clock start time.
    ///   - title: Auto-derived display title (decision #12 — MVP 1
    ///     populates this from the first English sentence + timestamp;
    ///     Phase 6+ swaps in Foundation Models summarization).
    /// - Returns: The newly inserted meeting's `PersistentIdentifier`.
    /// - Throws: Re-throws any error raised by `ModelContext.save()`.
    func startMeeting(startedAt: Date, title: String) throws -> PersistentIdentifier {
        let meeting = Meeting(startedAt: startedAt, title: title)
        modelContext.insert(meeting)
        try modelContext.save()
        return meeting.persistentModelID
    }

    /// Appends a ``Sentence`` to an in-progress meeting and saves.
    ///
    /// `searchableText` is populated via
    /// ``SearchTextNormalizer/normalize(_:)`` over the concatenated
    /// source + translated text, per Amendment 1. This is the single
    /// authoritative insert path — production callers must not
    /// construct `Sentence` rows directly.
    ///
    /// - Parameters:
    ///   - meetingID: The owning meeting's `PersistentIdentifier`.
    ///   - timestamp: Wall-clock time the sentence was produced.
    ///   - sourceLanguage: ISO 639-1 source language tag, `"ja"` or `"en"`.
    ///   - sourceText: Original transcribed text.
    ///   - translatedText: Translated text in the opposite language.
    ///   - sourceSegmentID: Upstream Whisper segment identifier.
    /// - Throws: ``MeetingStoreError/meetingNotFound(_:)`` if the
    ///   identifier does not resolve to a `Meeting` in this context.
    ///   Re-throws any error raised by `ModelContext.save()`.
    func appendSentence(
        meetingID: PersistentIdentifier,
        timestamp: Date,
        sourceLanguage: String,
        sourceText: String,
        translatedText: String,
        sourceSegmentID: UUID
    ) throws {
        let descriptor = FetchDescriptor<Meeting>(
            predicate: #Predicate { $0.persistentModelID == meetingID }
        )
        guard let meeting = try modelContext.fetch(descriptor).first else {
            throw MeetingStoreError.meetingNotFound(meetingID)
        }
        let searchable = SearchTextNormalizer.normalize(sourceText + " " + translatedText)
        let sentence = Sentence(
            timestamp: timestamp,
            sourceLanguage: sourceLanguage,
            sourceText: sourceText,
            translatedText: translatedText,
            sourceSegmentID: sourceSegmentID,
            searchableText: searchable
        )
        sentence.meeting = meeting
        modelContext.insert(sentence)
        try modelContext.save()
    }

    /// Marks a meeting ended by setting ``Meeting/endedAt`` and saving.
    ///
    /// - Parameters:
    ///   - meetingID: The meeting to end.
    ///   - endedAt: Wall-clock end time.
    /// - Throws: ``MeetingStoreError/meetingNotFound(_:)`` if the
    ///   identifier does not resolve. Re-throws save errors.
    func endMeeting(meetingID: PersistentIdentifier, endedAt: Date) throws {
        let descriptor = FetchDescriptor<Meeting>(
            predicate: #Predicate { $0.persistentModelID == meetingID }
        )
        guard let meeting = try modelContext.fetch(descriptor).first else {
            throw MeetingStoreError.meetingNotFound(meetingID)
        }
        meeting.endedAt = endedAt
        try modelContext.save()
    }

    /// Rewrites the title of a meeting.
    ///
    /// Called from ``MeetingSession/finalizeStop(at:)`` to replace the
    /// placeholder title (set at ``MeetingSession/start(at:)``) with the
    /// auto-derived title from
    /// ``MeetingTitleGenerator/makeTitle(startedAt:firstEnglishSentence:)``.
    ///
    /// - Parameters:
    ///   - meetingID: The meeting to retitle.
    ///   - title: The new display title.
    /// - Throws: ``MeetingStoreError/meetingNotFound(_:)`` if the meeting
    ///   is not in the store. Uses the same `FetchDescriptor` +
    ///   `#Predicate` pattern as the other lookups per the V3 "SwiftData
    ///   ModelContext lookup primitive" entry — `model(for:)` and
    ///   `registeredModel(for:)` are unsafe on iOS 26.5.
    func updateTitle(meetingID: PersistentIdentifier, title: String) throws {
        let descriptor = FetchDescriptor<Meeting>(
            predicate: #Predicate { $0.persistentModelID == meetingID }
        )
        guard let meeting = try modelContext.fetch(descriptor).first else {
            throw MeetingStoreError.meetingNotFound(meetingID)
        }
        meeting.title = title
        try modelContext.save()
    }

    /// Returns all meetings as Summary DTOs, sorted newest-first by
    /// ``Meeting/startedAt``.
    ///
    /// Step 6 read pattern. Step 12 evolves this into
    /// `fetchAll(searchText:)` per Amendment 2 (flat ``Sentence`` fetch +
    /// Swift-side group-by-meeting). Until then, this method is the sole
    /// read entry point for ``MeetingListView``. Caller:
    /// ``MeetingListView/reload()``.
    ///
    /// - Returns: All meetings projected to ``MeetingSummary`` DTOs,
    ///   ordered descending by `startedAt`.
    /// - Throws: Re-throws any error raised by `ModelContext.fetch(_:)`.
    func fetchAllUnfiltered() throws -> [MeetingSummary] {
        let descriptor = FetchDescriptor<Meeting>(
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor).map { MeetingSummary(from: $0) }
    }

    /// Deletes a meeting and (via cascade) its sentences.
    ///
    /// The cascade is declared on ``Meeting/sentences`` and is exercised
    /// at the SwiftData layer by ``MeetingEntityTests/cascadeDelete_singleSave_removesOrphanSentences``
    /// and at the actor layer by
    /// ``MeetingStoreTests/deleteMeeting_cascadesSentences``.
    ///
    /// - Parameter meetingID: The meeting to delete.
    /// - Throws: ``MeetingStoreError/meetingNotFound(_:)`` if the
    ///   identifier does not resolve. Re-throws save errors.
    func deleteMeeting(meetingID: PersistentIdentifier) throws {
        let descriptor = FetchDescriptor<Meeting>(
            predicate: #Predicate { $0.persistentModelID == meetingID }
        )
        guard let meeting = try modelContext.fetch(descriptor).first else {
            throw MeetingStoreError.meetingNotFound(meetingID)
        }
        modelContext.delete(meeting)
        try modelContext.save()
    }
}

/// Errors thrown by ``MeetingStore``.
///
/// `Equatable` conformance is synthesized — `PersistentIdentifier` is
/// a Swift-level value type with `Equatable` conformance, so the case
/// associated value satisfies the synthesis requirement.
enum MeetingStoreError: Error, Equatable {
    /// The provided ``PersistentIdentifier`` did not resolve to a
    /// `Meeting` in the actor's `ModelContext`. Most commonly fires
    /// when the meeting was deleted in a previous call but the
    /// caller retained its identifier.
    case meetingNotFound(PersistentIdentifier)
}
