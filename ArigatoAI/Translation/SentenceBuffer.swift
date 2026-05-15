//
//  SentenceBuffer.swift
//  ArigatoAI
//
//  Created by Jose Castell on 2026/05/16.
//

import Foundation

/// One sentence drained out of ``SentenceBuffer``.
///
/// Carries enough provenance to attach the resulting translation back
/// to the original Whisper segments: the source segment IDs, the host-
/// time range, and the assembled sentence text. ``isFallback`` is
/// reserved for upstream signaling (a sentence boundary fired before
/// a sufficient amount of source text accumulated, etc.) — defaults to
/// `false`; Step 7's `TranslationActor` decides when to flag fallback.
///
/// `Sendable` because every stored property is a value type or an
/// array of value types.
nonisolated struct BufferedSentence: Hashable {
    /// The full assembled sentence text including the boundary
    /// punctuation character.
    let text: String

    /// IDs of the upstream ``TranscriptSegment`` instances whose text
    /// contributed to this sentence. The first ID is what
    /// ``TranslationActor`` will use as the `sourceSegmentID` on the
    /// emitted ``TranslationEvent`` events.
    let sourceSegmentIDs: [UUID]

    /// Host-time of the earliest upstream segment that contributed to
    /// this sentence. Source of truth for translation start timing.
    let startHostTime: UInt64

    /// Host-time of the latest upstream segment that contributed to
    /// this sentence. Source of truth for translation end timing.
    let endHostTime: UInt64
}

/// Accumulates ``TranscriptSegment/text`` deltas and emits one
/// ``BufferedSentence`` per detected sentence boundary.
///
/// **Scheduling assumption.** This buffer accumulates appended segment
/// text until a sentence-ending punctuation character (one of
/// ``boundaryCharacters`` — `。！？.!?`) is observed in the appended
/// text, OR until ``silenceTimeoutSeconds`` has elapsed since the last
/// append without a boundary char being seen. When either condition
/// fires, the corresponding `flush*` method returns a
/// ``BufferedSentence`` and the buffer's accumulator is cleared (the
/// post-boundary remainder, if any, is retained for the next
/// sentence).
///
/// **Violation behavior.** If neither condition fires — e.g. upstream
/// emits one giant sentence-less monologue chunk — the buffer
/// accumulates without bound. The 2-second timer is the only
/// guarantee against unbounded accumulation. In practice this means:
/// (1) a non-stop monologue with no audible pauses for 20s would
/// produce one 20s-long sentence at the next pause boundary;
/// (2) Whisper's hop emission cadence (~1Hz) is the lower bound on
/// timer-flush latency. The violation test
/// `C-T-VIOLATION-NO-PUNCT-WITH-SILENCE` in `SentenceBufferTests`
/// drives this path explicitly.
///
/// **Usage pattern.** When `append(_:at:)` returns a non-nil value
/// containing only part of a multi-boundary chunk, the caller should
/// drain the overflow queue via `drainNext()` after every append —
/// the implementation returns the FIRST sentence from `append`, retains
/// any additional split sentences internally, and requires subsequent
/// calls to `drainNext()` to drain them. The caller pattern in
/// ``TranslationActor`` will be a `while let sentence = buffer.drainNext()`
/// loop after every append.
///
/// **Non-`Sendable` on purpose.** This is a mutating value type. It
/// is held inside the owning actor (``TranslationActor`` in Step 5+);
/// no concurrent access is possible. Marking it `Sendable` would
/// imply value-type-immutable, which is not the case (`mutating
/// append`).
nonisolated struct SentenceBuffer {
    // MARK: - Configuration (statics)

    /// The CharacterSet used to detect sentence boundaries.
    /// Lazily-initialized static to avoid recomputing per-append.
    static let boundaryCharacters: CharacterSet = .init(charactersIn: "。！？.!?")

    /// The silence-timeout threshold used by `flushIfStaleSince(_:)`.
    static let silenceTimeoutSeconds: Double = 2.0

    // MARK: - Stored state

    private var accumulator: String = ""

    /// Pending sentences split out by `append(_:at:)` when multiple
    /// boundaries are encountered in one chunk. `drainNext()` empties
    /// this queue before returning any new appends.
    private var splitOverflow: [BufferedSentence] = []

    /// The `ContinuousClock.Instant` of the most recent non-empty
    /// `append(_:at:)`. `nil` when the buffer has been empty since
    /// the last drain. Used by `flushIfStaleSince(_:)` to compute
    /// staleness.
    private var lastAppendInstant: ContinuousClock.Instant?

    private var pendingSourceSegmentIDs: [UUID] = []
    private var pendingStartHostTime: UInt64?
    private var pendingEndHostTime: UInt64?

    // MARK: - Init

    init() {}

    // MARK: - API

    /// Returns whether the buffer holds no accumulator text and no
    /// pending split sentences. Provenance state may still be set if
    /// the caller has not drained yet — irrelevant for flush logic.
    var isEmpty: Bool {
        accumulator.isEmpty && splitOverflow.isEmpty
    }

    /// Appends the supplied segment's text to the accumulator.
    ///
    /// If the appended text contains one or more boundary characters,
    /// the accumulator is split at each boundary: the first split
    /// becomes the return value of this call; any additional splits
    /// are pushed into the internal `splitOverflow` queue to be
    /// returned by future `drainNext()` calls. The post-final-boundary
    /// remainder (if any) is retained as the new accumulator (a
    /// pending unfinished sentence).
    ///
    /// Empty-text segments are no-ops: they do not update
    /// `lastAppendInstant`, do not bump provenance, do not return
    /// anything.
    ///
    /// - Parameters:
    ///   - segment: The upstream `TranscriptSegment` whose `text`
    ///     contributes to the current sentence.
    ///   - instant: The `ContinuousClock.Instant` of this append.
    ///     Used to update `lastAppendInstant` for silence-timeout
    ///     computation.
    /// - Returns: A `BufferedSentence` if appending the supplied
    ///   text caused at least one boundary to be detected, else `nil`.
    ///   When multiple boundaries are detected in one append, the
    ///   first sentence is returned and the rest are queued for
    ///   `drainNext()`.
    mutating func append(_ segment: TranscriptSegment, at instant: ContinuousClock.Instant) -> BufferedSentence? {
        guard !segment.text.isEmpty else { return nil }

        if pendingStartHostTime == nil {
            pendingStartHostTime = segment.startHostTime
        }
        pendingEndHostTime = segment.endHostTime
        pendingSourceSegmentIDs.append(segment.id)
        lastAppendInstant = instant

        accumulator.append(segment.text)
        return drainBoundariesFromAccumulator()
    }

    /// If the buffer has unfinished accumulator text AND
    /// `instant` is at least `silenceTimeoutSeconds` past the last
    /// non-empty append, flush the accumulator as a single
    /// `BufferedSentence`. Otherwise returns `nil`.
    ///
    /// Used by the owning actor's timer task to flush slow speakers
    /// whose sentences don't end in canonical punctuation.
    mutating func flushIfStaleSince(_ instant: ContinuousClock.Instant) -> BufferedSentence? {
        guard !accumulator.isEmpty else { return nil }
        guard let lastAppendInstant else { return nil }
        let elapsed = lastAppendInstant.duration(to: instant)
        guard elapsed >= .seconds(Self.silenceTimeoutSeconds) else { return nil }
        return flushAccumulatorAsSentence()
    }

    /// Forces a flush of any accumulator text, ignoring the silence
    /// timeout. Used at end-of-upstream-stream to drain whatever
    /// remains.
    mutating func flushRemaining() -> BufferedSentence? {
        guard !accumulator.isEmpty else { return nil }
        return flushAccumulatorAsSentence()
    }

    /// Returns the next pending split sentence, if any.
    /// Used by the caller after an `append(_:at:)` that triggered
    /// multiple boundary splits to drain the overflow queue.
    mutating func drainNext() -> BufferedSentence? {
        guard !splitOverflow.isEmpty else { return nil }
        return splitOverflow.removeFirst()
    }

    // MARK: - Private

    private mutating func drainBoundariesFromAccumulator() -> BufferedSentence? {
        var sentences: [BufferedSentence] = []
        while let boundaryRange = accumulator.rangeOfCharacter(from: Self.boundaryCharacters) {
            let sentenceText = String(accumulator[accumulator.startIndex ... boundaryRange.lowerBound])
            sentences.append(makePendingSentence(text: sentenceText))
            accumulator.removeSubrange(accumulator.startIndex ... boundaryRange.lowerBound)
        }

        if sentences.isEmpty {
            return nil
        }

        // Reset provenance state for the next sentence. The remainder
        // (if any) belongs to the next sentence — provenance for that
        // future sentence will be filled by the next append.
        pendingSourceSegmentIDs.removeAll()
        pendingStartHostTime = accumulator.isEmpty ? nil : pendingEndHostTime
        // (After a split, pendingStartHostTime is best-effort — we
        // use the most recent endHostTime as the next sentence's
        // start. This is conservative; refine if a future test
        // surfaces accuracy issues.)

        let first = sentences.removeFirst()
        splitOverflow.append(contentsOf: sentences)
        return first
    }

    private mutating func flushAccumulatorAsSentence() -> BufferedSentence {
        let sentence = makePendingSentence(text: accumulator)
        accumulator = ""
        pendingSourceSegmentIDs.removeAll()
        pendingStartHostTime = nil
        pendingEndHostTime = nil
        lastAppendInstant = nil
        return sentence
    }

    private func makePendingSentence(text: String) -> BufferedSentence {
        BufferedSentence(
            text: text,
            sourceSegmentIDs: pendingSourceSegmentIDs,
            startHostTime: pendingStartHostTime ?? 0,
            endHostTime: pendingEndHostTime ?? 0
        )
    }
}
