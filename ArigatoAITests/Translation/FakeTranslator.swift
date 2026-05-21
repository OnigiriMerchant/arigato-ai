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
/// stream without throwing AND awaits the producer task's full tear-down
/// before returning. By the time `await translator.cancel()` returns, the
/// prior session is guaranteed to be fully done — the next
/// ``translate(segments:direction:)`` call cannot race with a stale
/// producer-task hop that would otherwise finish the new session's stream
/// empty. The configured failure is preserved across cancel — callers
/// that want a follow-up ``translate(segments:direction:)`` call to
/// succeed must explicitly invoke ``setConfiguredFailure(_:)`` with
/// `nil` between calls.
///
/// **Scheduling assumption.** The producer task body owns its
/// `AsyncThrowingStream.Continuation` via closure capture and finishes
/// the stream directly from the task — it does NOT re-enter the actor
/// to do so. This is deliberate: re-entering the actor from inside the
/// producer would deadlock against `cancel()` (which holds the actor
/// while awaiting `task.value`). Actor-held refs (`activeTask`,
/// `activeContinuation`) are cleared by `cancel()` only; the producer
/// never mutates actor state after spawn.
///
/// **Named violation test:**
/// `translate_burstThenCancelFinishesStreamWithoutError` exercises the
/// reusability contract under cancel — drives a burst, cancels mid-stream,
/// then issues a fresh `translate(...)` and asserts the new session emits
/// its `.completed` event. Without the deterministic `cancel()`-awaits-tear-down
/// contract above, the new session's continuation can be finished by the
/// prior session's stale task hop under suite-level scheduler pressure.
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
        let task = Task {
            // The producer owns the continuation via closure capture and
            // finishes the stream directly — it does NOT re-enter the
            // actor. See the type-level scheduling-assumption note.
            if let failure {
                continuation.finish(throwing: failure)
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

            continuation.finish()
        }
        activeTask = task

        return stream
    }

    func cancel() async {
        activeContinuation?.finish()
        let task = activeTask
        activeContinuation = nil
        activeTask = nil
        task?.cancel()
        // Await the producer task's full tear-down before returning so
        // callers (and any follow-up `translate(...)` call) cannot race
        // a stale post-cancel hop. Safe because the producer task body
        // does not re-enter the actor — no deadlock against this hold.
        await task?.value
    }
}
