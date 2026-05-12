//
//  TranslationProtocolTests.swift
//  ArigatoAITests
//
//  Created by Jose Castell on 2026/05/12.
//

@testable import ArigatoAI
import Foundation
import Testing

@Suite("Translating protocol contract")
struct TranslationProtocolTests {
    // MARK: - Helpers

    private func makeSegment(
        id: UUID = UUID(),
        text: String = "hello",
        language: SpokenLanguage = .ja
    ) -> TranscriptSegment {
        TranscriptSegment(
            id: id,
            text: text,
            language: language,
            startHostTime: 0,
            endHostTime: 16000,
            startSeconds: 0,
            endSeconds: 1,
            isFinal: true,
            wasLanguageFallback: false
        )
    }

    // MARK: - Warmup state

    @Test("warmupState starts as .cold for a fresh conformer")
    func warmupState_startsCold() async {
        let translator = FakeTranslator()
        let state = await translator.warmupState()
        #expect(state == .cold)
    }

    @Test("warmup transitions the state to .ready")
    func warmup_transitionsToReady() async throws {
        let translator = FakeTranslator()
        try await translator.warmup()
        let state = await translator.warmupState()
        #expect(state == .ready)
    }

    @Test("TranslationWarmupState.failed carries an Equatable TranslationError")
    func warmupState_failedCarriesError() {
        let a: TranslationWarmupState = .failed(.modelNotReady)
        let b: TranslationWarmupState = .failed(.modelNotReady)
        #expect(a == b)
    }

    // MARK: - Error typing (D2 contract)

    /// Locks the D2 doc-comment contract on
    /// ``Translating/translate(segments:direction:)``: errors thrown onto
    /// the returned stream are ``TranslationError`` values, never
    /// non-typed errors.
    @Test("Errors emitted by translate are TranslationError values")
    func translate_errorsAreTranslationError() async {
        let translator = FakeTranslator()
        await translator.setConfiguredFailure(.generationFailed("test"))

        let segments = AsyncStream<TranscriptSegment> { _ in
            // Never finish; the configured failure drives termination.
        }
        let stream = await translator.translate(segments: segments, direction: .jaToEn)

        do {
            for try await _ in stream {
                Issue.record("Expected stream to throw before yielding any event")
            }
            Issue.record("Expected stream to throw rather than finish cleanly")
        } catch let error as TranslationError {
            #expect(error == .generationFailed("test"))
        } catch {
            Issue.record("Expected TranslationError, got \(type(of: error))")
        }
    }

    // MARK: - T6.4 — greedy producer FIFO (D4 contract)

    /// **T6.4 scheduling-violation test.** Drives the conformer with a
    /// greedy producer that yields three ``TranscriptSegment`` values
    /// back-to-back inside a single synchronous closure with no awaits
    /// between yields, then finishes upstream. Asserts that the conformer
    /// emits three ``TranslationEvent/completed(_:)`` events whose
    /// `sourceSegmentID` values appear in the same order as the input
    /// segments. Locks the FIFO-serial scheduling assumption documented
    /// on ``Translating/translate(segments:direction:)``.
    @Test("Greedy producer emits FIFO .completed events in input order")
    func translate_greedyProducerEmitsFifoCompletedEvents() async throws {
        let translator = FakeTranslator()

        let firstID = UUID()
        let secondID = UUID()
        let thirdID = UUID()

        let segments = AsyncStream<TranscriptSegment> { continuation in
            // Greedy producer: no awaits between yields.
            continuation.yield(makeSegment(id: firstID, text: "one"))
            continuation.yield(makeSegment(id: secondID, text: "two"))
            continuation.yield(makeSegment(id: thirdID, text: "three"))
            continuation.finish()
        }

        let stream = await translator.translate(segments: segments, direction: .jaToEn)

        var completedSourceIDs: [UUID] = []
        for try await event in stream {
            if case let .completed(translated) = event {
                completedSourceIDs.append(translated.sourceSegmentID)
            }
        }

        #expect(completedSourceIDs == [firstID, secondID, thirdID])
    }

    // MARK: - T6.5 — burst-then-cancel (D3 contract)

    /// **T6.5 scheduling-violation test.** Pushes three segments
    /// back-to-back, then immediately cancels. Asserts that the returned
    /// stream finishes normally (no `CancellationError`, no thrown error)
    /// and that the conformer remains usable for a subsequent
    /// ``Translating/translate(segments:direction:)`` call that itself
    /// completes one new segment. Locks the
    /// "terminal-for-stream, not-for-conformer" cancellation contract
    /// documented on ``Translating/cancel()``.
    @Test("Burst-then-cancel finishes the stream without error and leaves the conformer reusable")
    func translate_burstThenCancelFinishesStreamWithoutError() async {
        let translator = FakeTranslator()

        let segments = AsyncStream<TranscriptSegment> { continuation in
            continuation.yield(makeSegment(text: "one"))
            continuation.yield(makeSegment(text: "two"))
            continuation.yield(makeSegment(text: "three"))
            // Do not finish — the cancel below drives termination.
        }

        let stream = await translator.translate(segments: segments, direction: .jaToEn)

        let consumer = Task {
            var thrown: (any Error)?
            do {
                for try await _ in stream {
                    // Zero-or-more events may arrive before cancel takes effect.
                }
            } catch {
                thrown = error
            }
            return thrown
        }

        await translator.cancel()
        let thrown = await consumer.value
        #expect(thrown == nil)

        // Conformer must remain usable for the next translate(...) call.
        let nextSegmentID = UUID()
        let nextSegments = AsyncStream<TranscriptSegment> { continuation in
            continuation.yield(makeSegment(id: nextSegmentID, text: "after-cancel"))
            continuation.finish()
        }
        let nextStream = await translator.translate(segments: nextSegments, direction: .jaToEn)

        var nextCompletedIDs: [UUID] = []
        do {
            for try await event in nextStream {
                if case let .completed(translated) = event {
                    nextCompletedIDs.append(translated.sourceSegmentID)
                }
            }
        } catch {
            Issue.record("Reused conformer threw on follow-up translate: \(error)")
        }
        #expect(nextCompletedIDs == [nextSegmentID])
    }

    // MARK: - T6.6 — direction is per-call (D1 contract)

    /// **T6.6 D1-contract test.** Locks the doc-comment contract
    /// "Direction is fixed for the lifetime of this call" on
    /// ``Translating/translate(segments:direction:)``. Invokes translate
    /// twice on the same conformer with different directions; asserts the
    /// emitted ``TranslatedSegment/direction`` matches the direction
    /// passed into each respective call.
    @Test("Direction is fixed per translate(...) call and changes between calls")
    func directionLocked_perCall() async throws {
        let translator = FakeTranslator()

        // First call: jaToEn.
        let firstSegments = AsyncStream<TranscriptSegment> { continuation in
            continuation.yield(makeSegment(text: "japanese"))
            continuation.finish()
        }
        let firstStream = await translator.translate(
            segments: firstSegments,
            direction: .jaToEn
        )
        var firstDirections: [TranslationDirection] = []
        for try await event in firstStream {
            if case let .completed(translated) = event {
                firstDirections.append(translated.direction)
            }
        }
        #expect(firstDirections == [.jaToEn])

        // Second call: enToJa.
        let secondSegments = AsyncStream<TranscriptSegment> { continuation in
            continuation.yield(makeSegment(text: "english"))
            continuation.finish()
        }
        let secondStream = await translator.translate(
            segments: secondSegments,
            direction: .enToJa
        )
        var secondDirections: [TranslationDirection] = []
        for try await event in secondStream {
            if case let .completed(translated) = event {
                secondDirections.append(translated.direction)
            }
        }
        #expect(secondDirections == [.enToJa])
    }
}
