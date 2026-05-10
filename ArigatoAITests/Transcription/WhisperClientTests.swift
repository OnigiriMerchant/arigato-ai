//
//  WhisperClientTests.swift
//  ArigatoAITests
//
//  Created by Jose Castell on 2026/05/10.
//

@testable import ArigatoAI
import Foundation
import Testing

/// Hand-rolled fake conforming to ``WhisperClient``. Captures the
/// `anchorHostTime` argument supplied to
/// ``WhisperClient/transcribe(audio:anchorHostTime:)`` so the
/// round-trip test can assert it appears verbatim on the returned
/// ``WhisperWindowResult``.
///
/// The fake is intentionally minimal: the production
/// ``ArgmaxOSSWhisperClient`` adapter is integration-test territory
/// (Group D will exercise it against real WhisperKit), so unit-test
/// coverage here focuses on the protocol contract itself.
private final nonisolated class CapturingWhisperClient: WhisperClient, @unchecked Sendable {
    /// Segments to return on the next call. Defaults to an empty array
    /// so callers that only care about the round-trip can omit it.
    let segmentsToReturn: [WhisperRawSegment]

    /// Language tag to return. Defaults to `"ja"`.
    let languageToReturn: String

    init(
        segmentsToReturn: [WhisperRawSegment] = [],
        languageToReturn: String = "ja"
    ) {
        self.segmentsToReturn = segmentsToReturn
        self.languageToReturn = languageToReturn
    }

    func prewarmModels() async throws {
        // Intentionally empty — these tests do not exercise pre-warm.
    }

    func transcribe(
        audio _: [Float],
        anchorHostTime: UInt64
    ) async throws -> WhisperWindowResult {
        WhisperWindowResult(
            language: languageToReturn,
            windowAnchorHostTime: anchorHostTime,
            segments: segmentsToReturn
        )
    }
}

@Suite("WhisperClient")
struct WhisperClientTests {
    /// **C17.** The `anchorHostTime` argument supplied to
    /// ``WhisperClient/transcribe(audio:anchorHostTime:)`` must appear
    /// verbatim on the returned ``WhisperWindowResult/windowAnchorHostTime``.
    @Test("transcribe round-trips anchorHostTime onto the returned WhisperWindowResult")
    func transcribe_anchorHostTimeIsRoundTripped() async throws {
        let client = CapturingWhisperClient()
        let anchor: UInt64 = 12_345_678_901_234

        let result = try await client.transcribe(audio: [], anchorHostTime: anchor)

        #expect(result.windowAnchorHostTime == anchor)
        #expect(result.language == "ja")
        #expect(result.segments.isEmpty)
    }

    /// **C18.** ``WhisperRawSegment/startSeconds`` and
    /// ``WhisperRawSegment/endSeconds`` are relative to the start of the
    /// audio array, **not** absolute host time. A regression that
    /// silently re-derived these from `anchorHostTime` would inflate
    /// these values by ~1e9 ticks; the test asserts the literal Doubles
    /// come through unchanged.
    @Test("WhisperRawSegment seconds are relative to the audio array start, not host time")
    func whisperRawSegment_secondsAreRelativeToAudioArrayStart() async throws {
        let segments = [
            WhisperRawSegment(text: "first", startSeconds: 0.0, endSeconds: 0.5, avgLogprob: -0.1),
            WhisperRawSegment(text: "second", startSeconds: 0.5, endSeconds: 1.2, avgLogprob: -0.2),
            WhisperRawSegment(text: "third", startSeconds: 1.2, endSeconds: 4.9, avgLogprob: -0.3),
        ]
        let client = CapturingWhisperClient(segmentsToReturn: segments)
        // Deliberately huge anchor so any accidental host-time-derived
        // computation would push the seconds off by orders of magnitude.
        let anchor: UInt64 = 999_999_999_999

        let result = try await client.transcribe(audio: [], anchorHostTime: anchor)

        #expect(result.segments.count == 3)
        #expect(result.segments[0].startSeconds == 0.0)
        #expect(result.segments[0].endSeconds == 0.5)
        #expect(result.segments[1].startSeconds == 0.5)
        #expect(result.segments[1].endSeconds == 1.2)
        #expect(result.segments[2].startSeconds == 1.2)
        #expect(result.segments[2].endSeconds == 4.9)

        // Every segment offset must remain bounded by the (5-second) window
        // length per Phase 4 Decision 4. If a regression converted these
        // into host-time ticks, the values would be ~1e9 or larger.
        for segment in result.segments {
            #expect(segment.startSeconds < 60.0)
            #expect(segment.endSeconds < 60.0)
        }
    }
}
