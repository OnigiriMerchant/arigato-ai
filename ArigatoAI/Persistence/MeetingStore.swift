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
    /// **Visibility (Step 12)**: narrowed to `internal` and re-purposed as
    /// the empty-needle code path of ``fetchAll(searchText:)``. Step 6
    /// callers (``MeetingListView``) now route through `fetchAll(searchText:)`
    /// with the current search text; this method is preserved as the
    /// single-source-of-truth "no filter" implementation and is called
    /// from `fetchAll(searchText:)` when the trimmed needle is empty.
    /// Tests retain direct access to this method by virtue of the same
    /// module boundary (`@testable import ArigatoAI`).
    ///
    /// - Returns: All meetings projected to ``MeetingSummary`` DTOs,
    ///   ordered descending by `startedAt`. `firstMatchSnippet` is `nil`
    ///   on every projection (the empty-needle contract per D12-3).
    /// - Throws: Re-throws any error raised by `ModelContext.fetch(_:)`.
    func fetchAllUnfiltered() throws -> [MeetingSummary] {
        let descriptor = FetchDescriptor<Meeting>(
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor).map { MeetingSummary(from: $0) }
    }

    /// Returns meetings matching `searchText`, newest-first, projected to
    /// ``MeetingSummary`` DTOs.
    ///
    /// ## Empty-query semantics (D12-3)
    /// An empty or whitespace-only `searchText` (after trim) returns every
    /// meeting, newest-first, with ``MeetingSummary/firstMatchSnippet`` set
    /// to `nil`. Delegates to ``fetchAllUnfiltered()``.
    ///
    /// ## Match semantics
    /// 1. **Title match**: `meeting.title.localizedStandardContains(rawNeedle)` —
    ///    case + diacritic insensitive, locale-aware, raw needle (NOT folded).
    /// 2. **Body match**: `sentence.searchableText.contains(foldedNeedle)`
    ///    against the pre-normalized field populated by
    ///    ``SearchTextNormalizer/normalize(_:)`` at insert time. Query is
    ///    folded via the same normalizer to match the equivalence classes
    ///    (hiragana ↔ katakana, diacritic / case / width).
    ///
    /// Either match qualifies a meeting. The snippet projection is
    /// driven by the body-match map: any meeting that surfaces a body
    /// match (whether it also surfaces a title match or not) carries
    /// the earliest matching sentence's ``Sentence/translatedText`` as
    /// its ``MeetingSummary/firstMatchSnippet``. A meeting matched by
    /// title only (no body match) carries `nil`. The empty-needle path
    /// returns `nil` for every projection (D12-3).
    /// No truncation here — ``MeetingListRow`` handles ellipsis via
    /// ``MeetingListRowFormatter/snippet(_:maxLength:)``.
    ///
    /// ## Architecture (Amendment 2)
    /// Two-phase fetch:
    /// 1. Flat ``Sentence`` fetch with body predicate against the
    ///    pre-folded ``Sentence/searchableText`` field.
    /// 2. Separate ``Meeting`` fetch with title predicate.
    /// 3. Swift-side union by `PersistentIdentifier`, project to
    ///    ``MeetingSummary``, sort newest-first.
    ///
    /// To-many `contains-where` predicates are **not** used — DR-3 §B
    /// documents runtime failures on iOS 26.x (Apple Developer Forums
    /// 731609, 747226, 758449).
    ///
    /// Per V3 lookup-primitive entry (`6023f2a`): uses `FetchDescriptor` +
    /// `#Predicate` only. NO `model(for:)` / `registeredModel(for:)`.
    ///
    /// ## D12-1 (evaluate-and-defer FTS5)
    /// This is a substring scan over a pre-folded field. SQLite's B-tree
    /// indexes can't accelerate `%term%` substring scans (DR-3 §C). FTS5
    /// migration is V3-tracked under "Migrate history search to SQLite
    /// FTS5"; the trigger is on-device latency > 200ms at 15K sentences,
    /// or transcript volume > 50K sentences. See
    /// `meetingListSearch_15kRows_searchLatencyUnder200ms` for the
    /// benchmark.
    ///
    /// ## Scheduling assumption
    /// This actor's `@ModelActor` macro serializes concurrent calls onto a
    /// single executor. Two callers issuing
    /// `await store.fetchAll(searchText:)` simultaneously will be
    /// processed sequentially — no interleaving of `modelContext.fetch`
    /// reads, no shared mutable state. Each call computes its result
    /// independently and returns. Named violation test:
    /// ``meetingStore_fetchAll_concurrentCalls_serializedAndCorrect``
    /// (10 concurrent calls with 10 different queries — each must return
    /// its correct filtered set).
    ///
    /// - Parameter searchText: Raw user-typed needle. Trimmed of
    ///   surrounding whitespace before the emptiness check.
    /// - Returns: Newest-first array of ``MeetingSummary``. Empty when no
    ///   meeting matches (the view's
    ///   `ContentUnavailableView.search` branch renders that state).
    /// - Throws: Re-throws any error raised by `ModelContext.fetch(_:)`.
    func fetchAll(searchText: String) throws -> [MeetingSummary] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return try fetchAllUnfiltered()
        }

        let foldedNeedle = SearchTextNormalizer.normalize(trimmed)
        let rawNeedle = trimmed

        // Phase 1: title match (raw needle, localizedStandardContains).
        let titleDescriptor = FetchDescriptor<Meeting>(
            predicate: #Predicate<Meeting> { meeting in
                meeting.title.localizedStandardContains(rawNeedle)
            },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        let titleMatched = try modelContext.fetch(titleDescriptor)

        // Phase 2: body match (folded needle, flat Sentence fetch).
        // Per Amendment 2: avoid to-many `contains-where` on Meeting; fetch
        // Sentence rows directly and group up to the parent in Swift.
        let bodyDescriptor = FetchDescriptor<Sentence>(
            predicate: #Predicate<Sentence> { sentence in
                sentence.searchableText.contains(foldedNeedle)
            },
            sortBy: [SortDescriptor(\.timestamp, order: .forward)]
        )
        let bodyMatched = try modelContext.fetch(bodyDescriptor)

        // Group sentences by meeting; pick the first matching sentence per
        // meeting (earliest by timestamp because the fetch is sorted
        // ascending) for the snippet projection.
        var snippetByMeetingID: [PersistentIdentifier: String] = [:]
        var bodyMatchedMeetings: [Meeting] = []
        for sentence in bodyMatched {
            // To-one traversal `sentence.meeting` is allowed and is the
            // pattern DR-3 §B blesses (the documented failures are
            // to-many `contains-where`, not to-one navigation).
            guard let meeting = sentence.meeting else { continue }
            if snippetByMeetingID[meeting.persistentModelID] == nil {
                snippetByMeetingID[meeting.persistentModelID] = sentence.translatedText
                bodyMatchedMeetings.append(meeting)
            }
        }

        // Union by persistentModelID. Title-matched meetings are appended
        // first so their order (newest-first by startedAt) seeds the
        // collection; body-only meetings then fill in. The final sort
        // below re-imposes newest-first across the union, so order at
        // this stage is for de-dup correctness only.
        var seen: Set<PersistentIdentifier> = []
        var union: [Meeting] = []
        for meeting in titleMatched {
            if seen.insert(meeting.persistentModelID).inserted {
                union.append(meeting)
            }
        }
        for meeting in bodyMatchedMeetings {
            if seen.insert(meeting.persistentModelID).inserted {
                union.append(meeting)
            }
        }

        // Final sort: newest-first by startedAt (idempotent for the
        // title-matched prefix, sorts in the body-only suffix).
        union.sort { $0.startedAt > $1.startedAt }

        return union.map { meeting in
            MeetingSummary(
                from: meeting,
                firstMatchSnippet: snippetByMeetingID[meeting.persistentModelID]
            )
        }
    }

    /// Returns all sentences for a meeting, projected to Sendable DTOs and
    /// sorted ascending by ``Sentence/timestamp``.
    ///
    /// Step 9a read path for ``TranscriptSplitScreenView``. Symmetric with
    /// ``fetchAllUnfiltered()`` (Step 6) — both use the
    /// `FetchDescriptor` + `#Predicate` pattern per the V3 "SwiftData
    /// `ModelContext` lookup primitive" entry (`6023f2a`) to avoid the
    /// `model(for:)` / `registeredModel(for:)` pitfalls documented on
    /// iOS 26.5.
    ///
    /// Returns DTOs (``MeetingDetail/SentenceProjection``), not `@Model`
    /// instances — required by Swift 6 strict concurrency per
    /// `docs/PHASE_5_GROUP_D_DOC_RESEARCH.md` DR-1 §2 (`@Model` is not
    /// `Sendable`).
    ///
    /// ## "Meeting not found" contract
    ///
    /// When `meetingID` does not resolve to a `Meeting` in the actor's
    /// context the method returns an **empty array** rather than throwing
    /// ``MeetingStoreError/meetingNotFound(_:)``. This is parity with
    /// ``fetchAllUnfiltered()``'s pattern (read paths never throw on
    /// no-data) and matches the consumer contract in
    /// ``TranscriptSplitScreenViewModel/reload()``, which treats absence
    /// of rows as "nothing to display yet" rather than as an error. The
    /// write paths (``appendSentence(...)``, ``updateTitle(...)``,
    /// ``endMeeting(...)``, ``deleteMeeting(...)``) keep the
    /// `meetingNotFound` throw because writes against a stale ID are a
    /// programmer error worth surfacing.
    ///
    /// - Parameter meetingID: The owning meeting's `PersistentIdentifier`.
    /// - Returns: All sentences in the meeting, oldest-first by timestamp.
    ///   Empty when the meeting is absent or has no sentences yet.
    /// - Throws: Re-throws any error raised by `ModelContext.fetch(_:)`.
    func fetchSentences(meetingID: PersistentIdentifier) throws -> [MeetingDetail.SentenceProjection] {
        let descriptor = FetchDescriptor<Sentence>(
            predicate: #Predicate { $0.meeting?.persistentModelID == meetingID },
            sortBy: [SortDescriptor(\.timestamp, order: .forward)]
        )
        return try modelContext.fetch(descriptor).map { sentence in
            MeetingDetail.SentenceProjection(
                id: sentence.persistentModelID,
                timestamp: sentence.timestamp,
                sourceLanguage: sentence.sourceLanguage,
                sourceText: sentence.sourceText,
                translatedText: sentence.translatedText,
                sourceSegmentID: sentence.sourceSegmentID
            )
        }
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

    /// Deletes every ``Meeting`` record in the store and (via cascade)
    /// every associated ``Sentence``.
    ///
    /// Step 15's "Delete all transcripts" Settings action. The cascade
    /// is declared on ``Meeting/sentences`` via
    /// `@Relationship(deleteRule: .cascade)` (Step 1) and exercised at
    /// the actor layer by
    /// ``MeetingStoreDeleteAllTests/deleteAllMeetings_cascadesToSentences_freshFetchReturnsEmpty``.
    ///
    /// Uses the V3-blessed `FetchDescriptor` + per-row
    /// `modelContext.delete(_:)` pattern (`6023f2a`). Does NOT use
    /// `model(for:)` or `registeredModel(for:)`. Does NOT use a
    /// SwiftData batch-delete primitive — the cascade fires
    /// correctly via per-row delete + single save (per Step 1
    /// Amendment 4's FB13640004 regression test pattern).
    ///
    /// - Returns: Count of meetings deleted.
    /// - Throws: Re-throws any error raised by `ModelContext.fetch(_:)`
    ///   or `ModelContext.save()`.
    ///
    /// Named test: ``MeetingStoreDeleteAllTests/deleteAllMeetings_returnsCount_removesAllRows``.
    func deleteAllMeetings() throws -> Int {
        let descriptor = FetchDescriptor<Meeting>()
        let meetings = try modelContext.fetch(descriptor)
        let count = meetings.count
        for meeting in meetings {
            modelContext.delete(meeting)
        }
        try modelContext.save()
        return count
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
