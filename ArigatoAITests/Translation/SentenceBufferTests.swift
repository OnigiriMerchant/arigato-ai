//
//  SentenceBufferTests.swift
//  ArigatoAITests
//
//  Created by Jose Castell on 2026/05/16.
//

@testable import ArigatoAI
import Foundation
import Testing

@Suite("SentenceBuffer")
struct SentenceBufferTests {
    // MARK: - Helpers

    private static func segment(
        text: String,
        startHost: UInt64 = 100,
        endHost: UInt64 = 200,
        language: SpokenLanguage = .en
    ) -> TranscriptSegment {
        TranscriptSegment(
            id: UUID(),
            text: text,
            language: language,
            startHostTime: startHost,
            endHostTime: endHost,
            startSeconds: 0,
            endSeconds: 0.5,
            isFinal: true,
            wasLanguageFallback: false
        )
    }

    // MARK: - Single-segment boundary detection

    @Test("append: single segment ending in Japanese 。 flushes a sentence")
    func append_singleSegmentEndingInJapanesePeriod_flushesSentence() {
        var buffer = SentenceBuffer()
        let flushed = buffer.append(Self.segment(text: "こんにちは。"), at: .now)
        #expect(flushed?.text == "こんにちは。")
        #expect(buffer.isEmpty)
    }

    @Test("append: single segment ending in English . flushes a sentence")
    func append_singleSegmentEndingInEnglishPeriod_flushesSentence() {
        var buffer = SentenceBuffer()
        let flushed = buffer.append(Self.segment(text: "Hello."), at: .now)
        #expect(flushed?.text == "Hello.")
        #expect(buffer.isEmpty)
    }

    // MARK: - Accumulation without boundary

    @Test("append: segment without a boundary accumulates and returns nil")
    func append_segmentWithoutBoundary_accumulatesWithoutFlush() {
        var buffer = SentenceBuffer()
        let flushed = buffer.append(Self.segment(text: "Hello world"), at: .now)
        #expect(flushed == nil)
        #expect(!buffer.isEmpty)
    }

    // MARK: - Mid-chunk boundary

    @Test("append: segment with mid-chunk boundary flushes sentence and retains remainder")
    func append_segmentWithMidChunkBoundary_flushesSentenceAndRetainsRemainder() {
        var buffer = SentenceBuffer()
        let first = buffer.append(Self.segment(text: "Hello. World"), at: .now)
        #expect(first?.text == "Hello.")
        // The " World" remainder should be retained — buffer not empty
        #expect(!buffer.isEmpty)
        // No further sentences in overflow queue
        #expect(buffer.drainNext() == nil)
    }

    @Test("append: segment with multiple boundaries yields sentences in order")
    func append_segmentWithMultipleBoundaries_yieldsSentencesInOrder() {
        var buffer = SentenceBuffer()
        let first = buffer.append(Self.segment(text: "Hello. World. Foo."), at: .now)
        #expect(first?.text == "Hello.")
        let second = buffer.drainNext()
        #expect(second?.text == " World.")
        let third = buffer.drainNext()
        #expect(third?.text == " Foo.")
        let fourth = buffer.drainNext()
        #expect(fourth == nil)
        #expect(buffer.isEmpty)
    }

    // MARK: - Silence-timeout flush (VIOLATION TEST)

    @Test("C-T-VIOLATION-NO-PUNCT-WITH-SILENCE: segments without boundary, then silence elapsed, flushes accumulated")
    func append_segmentsWithoutBoundary_thenSilenceElapsed_flushesAccumulated() {
        var buffer = SentenceBuffer()
        let t0 = ContinuousClock.now
        let tSecondAppend = t0.advanced(by: .milliseconds(500))
        _ = buffer.append(Self.segment(text: "Hello "), at: t0)
        _ = buffer.append(Self.segment(text: "world"), at: tSecondAppend)
        // No boundary anywhere; advance past the silence timeout measured
        // from the MOST RECENT append (production contract: silence-since-
        // last-append, not silence-since-buffer-creation).
        let t2 = tSecondAppend.advanced(by: .seconds(SentenceBuffer.silenceTimeoutSeconds + 0.1))
        let flushed = buffer.flushIfStaleSince(t2)
        #expect(flushed?.text == "Hello world")
        #expect(buffer.isEmpty)
    }

    @Test("flushIfStaleSince: within timeout returns nil")
    func flushIfStaleSince_withinTimeout_returnsNil() {
        var buffer = SentenceBuffer()
        let t0 = ContinuousClock.now
        _ = buffer.append(Self.segment(text: "Hello"), at: t0)
        let tHalf = t0.advanced(by: .seconds(SentenceBuffer.silenceTimeoutSeconds - 0.1))
        let flushed = buffer.flushIfStaleSince(tHalf)
        #expect(flushed == nil)
        #expect(!buffer.isEmpty)
    }

    @Test("flushIfStaleSince: empty buffer returns nil even after timeout")
    func flushIfStaleSince_emptyBuffer_returnsNilEvenAfterTimeout() {
        var buffer = SentenceBuffer()
        let later = ContinuousClock.now.advanced(by: .seconds(10))
        let flushed = buffer.flushIfStaleSince(later)
        #expect(flushed == nil)
    }

    // MARK: - flushRemaining

    @Test("flushRemaining: non-empty buffer yields final sentence")
    func flushRemaining_nonEmptyBuffer_yieldsFinalSentence() {
        var buffer = SentenceBuffer()
        _ = buffer.append(Self.segment(text: "Hello world"), at: .now)
        let flushed = buffer.flushRemaining()
        #expect(flushed?.text == "Hello world")
        #expect(buffer.isEmpty)
    }

    @Test("flushRemaining: empty buffer returns nil")
    func flushRemaining_emptyBuffer_returnsNil() {
        var buffer = SentenceBuffer()
        let flushed = buffer.flushRemaining()
        #expect(flushed == nil)
    }

    // MARK: - Empty text

    @Test("append: empty segment text is a no-op (no flush, no timer bump)")
    func append_emptySegmentText_noFlushNoLastAppendBump() {
        var buffer = SentenceBuffer()
        let flushed = buffer.append(Self.segment(text: ""), at: .now)
        #expect(flushed == nil)
        #expect(buffer.isEmpty)
        // Verify the timer didn't move: a subsequent flushIfStaleSince
        // with an instant 10s later should still return nil (buffer is
        // empty, not "stale and full").
        let later = ContinuousClock.now.advanced(by: .seconds(10))
        let flushedLater = buffer.flushIfStaleSince(later)
        #expect(flushedLater == nil)
    }
}
