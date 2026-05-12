//
//  FakeTranslator.swift
//  ArigatoAITests
//
//  Created by Jose Castell on 2026/05/12.
//

@testable import ArigatoAI
import Foundation

/// Test seam for ``Translating``. Used by ``TranslationProtocolTests`` and
/// (later) by Group C's `TranslationActor` tests. Visibility is internal to
/// the test target — referenceable across test files in the same module.
///
/// **Design assumption.** This fake processes each upstream segment by
/// emitting one ``TranslationEvent/partialChunk(sourceSegmentID:delta:)``
/// followed by one ``TranslationEvent/completed(_:)`` — sequentially, in
/// arrival order. The "serial per conformer" protocol contract is enforced
/// here by the simple sequential `for await` loop over upstream; there is
/// no internal queue beyond the AsyncStream's own buffer because each
/// iteration awaits before pulling the next.
///
/// **Cancellation semantics.** ``cancel()`` finishes the current event
/// stream without throwing and cancels the producer task. The configured
/// failure is preserved across cancel — callers that want a follow-up
/// ``translate(segments:direction:)`` call to succeed must explicitly
/// invoke ``setConfiguredFailure(_:)`` with `nil` between calls.
actor FakeTranslator: Translating {
    /// The currently observable warmup state. Tests inspect this via
    /// ``warmupState()`` to assert state transitions.
    private(set) var currentWarmupState: TranslationWarmupState = .cold

    /// Optional failure to inject. When non-`nil`, ``warmup()`` throws this
    /// value and ``translate(segments:direction:)`` finishes the returned
    /// stream with this value instead of yielding events.
    private var configuredFailure: TranslationError?

    /// The active stream's continuation, held so ``cancel()`` can finish it.
    private var activeContinuation: AsyncThrowingStream<TranslationEvent, any Error>.Continuation?

    /// The active producer task, held so ``cancel()`` can stop it.
    private var activeTask: Task<Void, Never>?

    /// Configures the next ``warmup()`` or
    /// ``translate(segments:direction:)`` call to fail with the given
    /// ``TranslationError``. Passing `nil` clears the configured failure.
    ///
    /// - Parameter failure: The error to inject, or `nil` to clear.
    func setConfiguredFailure(_ failure: TranslationError?) {
        configuredFailure = failure
    }

    func warmup() async throws {
        if let failure = configuredFailure {
            currentWarmupState = .failed(failure)
            throw failure
        }
        currentWarmupState = .warming
        currentWarmupState = .ready
    }

    func warmupState() async -> TranslationWarmupState {
        currentWarmupState
    }

    func translate(
        segments: AsyncStream<TranscriptSegment>,
        direction: TranslationDirection
    ) async -> AsyncThrowingStream<TranslationEvent, any Error> {
        let (stream, continuation) = AsyncThrowingStream<TranslationEvent, any Error>.makeStream()
        activeContinuation = continuation

        let failure = configuredFailure
        let task = Task { [weak self] in
            if let failure {
                await self?.finishActiveStream(throwing: failure)
                return
            }

            for await segment in segments {
                if Task.isCancelled { break }

                continuation.yield(
                    .partialChunk(sourceSegmentID: segment.id, delta: "[chunk]")
                )

                let translated = TranslatedSegment(
                    sourceSegmentID: segment.id,
                    sourceText: segment.text,
                    translatedText: "translated:\(segment.text)",
                    direction: direction,
                    startHostTime: segment.startHostTime,
                    endHostTime: segment.endHostTime,
                    isFallback: false
                )
                continuation.yield(.completed(translated))
            }

            await self?.finishActiveStream(throwing: nil)
        }
        activeTask = task

        return stream
    }

    func cancel() async {
        activeContinuation?.finish()
        activeTask?.cancel()
        activeContinuation = nil
        activeTask = nil
    }

    /// Helper isolated to the actor so the producer task can finish the
    /// stream and clear the held continuation in one hop.
    private func finishActiveStream(throwing error: TranslationError?) {
        if let error {
            activeContinuation?.finish(throwing: error)
        } else {
            activeContinuation?.finish()
        }
        activeContinuation = nil
        activeTask = nil
    }
}
