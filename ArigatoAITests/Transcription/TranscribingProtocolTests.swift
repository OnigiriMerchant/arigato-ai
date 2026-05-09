//
//  TranscribingProtocolTests.swift
//  ArigatoAITests
//
//  Created by Jose Castell on 2026/05/09.
//

@testable import ArigatoAI
import Foundation
import Testing

/// Test-local minimal conformer to ``Transcribing``. Mirrors the actor
/// isolation expected of the production `TranscriptionActor` so the
/// protocol seam itself is exercised under realistic constraints.
///
/// Behaviour:
/// - ``warmup()`` transitions ``cold`` -> ``warming`` -> ``ready``.
/// - ``transcribe(frames:)`` drains `frames` and finishes the throwing
///   stream cleanly when the upstream stream finishes or ``cancel()`` is
///   called. If a failure mode is configured, finishes the stream with
///   that error instead.
/// - ``cancel()`` finishes the current stream without throwing
///   `CancellationError`, locking the doc-comment contract.
private actor MinimalTranscriber: Transcribing {
    private var state: WarmupState = .cold
    private var failure: TranscriptionError?
    private var continuation: AsyncThrowingStream<TranscriptSegment, any Error>.Continuation?

    func setFailure(_ failure: TranscriptionError?) {
        self.failure = failure
    }

    func warmup() async throws {
        state = .warming
        state = .ready
    }

    func warmupState() async -> WarmupState {
        state
    }

    func transcribe(
        frames: AsyncStream<AudioFrame>
    ) async -> AsyncThrowingStream<TranscriptSegment, any Error> {
        let configuredFailure = failure
        let (stream, continuation) = AsyncThrowingStream<TranscriptSegment, any Error>.makeStream()
        self.continuation = continuation

        Task { [weak self] in
            if let configuredFailure {
                await self?.finishCurrentStream(with: configuredFailure)
                return
            }
            for await _ in frames {
                // Discard frames; this minimal conformer does not produce segments.
            }
            await self?.finishCurrentStream(with: nil)
        }

        return stream
    }

    func cancel() async {
        finishCurrentStream(with: nil)
    }

    private func finishCurrentStream(with error: TranscriptionError?) {
        if let error {
            continuation?.finish(throwing: error)
        } else {
            continuation?.finish()
        }
        continuation = nil
    }
}

@Suite("Transcribing protocol contract")
struct TranscribingProtocolTests {
    @Test("warmupState starts as .cold for a fresh conformer")
    func warmupState_startsCold() async {
        let transcriber = MinimalTranscriber()
        let state = await transcriber.warmupState()
        #expect(state == .cold)
    }

    @Test("warmup transitions state to .ready")
    func warmup_transitionsToReady() async throws {
        let transcriber = MinimalTranscriber()
        try await transcriber.warmup()
        let state = await transcriber.warmupState()
        #expect(state == .ready)
    }

    @Test("WarmupState.failed carries an Equatable TranscriptionError")
    func warmupState_failedCarriesError() {
        let a: WarmupState = .failed(.modelNotReady)
        let b: WarmupState = .failed(.modelNotReady)
        #expect(a == b)
    }

    @Test("transcribe with an empty frame stream finishes cleanly with no elements")
    func transcribe_emptyFramesProducesEmptyStream() async throws {
        let transcriber = MinimalTranscriber()
        let frames = AsyncStream<AudioFrame> { continuation in
            continuation.finish()
        }
        let stream = await transcriber.transcribe(frames: frames)

        var elementCount = 0
        for try await _ in stream {
            elementCount += 1
        }
        #expect(elementCount == 0)
    }

    @Test("cancel() finishes the stream without throwing CancellationError")
    func transcribe_cancelFinishesStreamWithoutError() async {
        let transcriber = MinimalTranscriber()
        let frames = AsyncStream<AudioFrame> { _ in
            // Never finish; the stream stays open until cancel() is called.
        }
        let stream = await transcriber.transcribe(frames: frames)

        let consumer = Task {
            var elements = 0
            do {
                for try await _ in stream {
                    elements += 1
                }
                return (elements, nil as (any Error)?)
            } catch {
                return (elements, error as (any Error)?)
            }
        }

        // Give the consumer a moment to begin awaiting.
        try? await Task.sleep(for: .milliseconds(20))
        await transcriber.cancel()

        let (elements, error) = await consumer.value
        #expect(elements == 0)
        #expect(error == nil)
    }

    @Test("Errors emitted by transcribe are TranscriptionError values")
    func transcribe_errorsAreTranscriptionError() async {
        let transcriber = MinimalTranscriber()
        await transcriber.setFailure(.decodeFailed("test"))

        let frames = AsyncStream<AudioFrame> { _ in
            // Never finish; the conformer's configured failure drives termination.
        }
        let stream = await transcriber.transcribe(frames: frames)

        do {
            for try await _ in stream {
                Issue.record("Expected stream to throw before yielding any segment")
            }
            Issue.record("Expected stream to throw rather than finish cleanly")
        } catch let error as TranscriptionError {
            #expect(error == .decodeFailed("test"))
        } catch {
            Issue.record("Expected TranscriptionError, got \(type(of: error))")
        }
    }
}
