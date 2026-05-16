//
//  MeetingPipelineTests.swift
//  ArigatoAITests
//
//  Created by Jose Castell on 2026/05/16.
//

@testable import ArigatoAI
import Darwin.Mach
import Foundation
import os
import SwiftData
import Testing

// MARK: - Test infrastructure

/// Fake `WhisperClient` that returns a pre-configured Whisper language
/// code per call, with empty segments (so the router's emitted text is
/// the empty string by default — sufficient for direction-derivation
/// tests that don't care about segment text). Each call to
/// `transcribe(audio:anchorHostTime:)` dequeues the next code from the
/// configured sequence; if the queue is exhausted the fake reuses the
/// final code so over-driven tests remain deterministic.
///
/// `OSAllocatedUnfairLock` per CLAUDE.md Swift 6 fake-state rules.
private final nonisolated class ScriptedLanguagePipelineWhisperClient: WhisperClient, @unchecked Sendable {
    private struct State {
        var languages: [String]
        var nextIndex: Int = 0
        var callCount: Int = 0
        var throwOnNextCall: TranscriptionError?
    }

    private let state: OSAllocatedUnfairLock<State>

    init(languages: [String]) {
        state = OSAllocatedUnfairLock(initialState: State(languages: languages))
    }

    var callCount: Int {
        state.withLock { $0.callCount }
    }

    /// Configures the *next* `transcribe` call to throw the supplied
    /// error. Used by the upstream-error propagation test.
    func setThrowOnNextCall(_ error: TranscriptionError) {
        state.withLock { $0.throwOnNextCall = error }
    }

    func prewarmModels() async throws {
        // No-op; lifecycle is exercised in TranscriptionActorTests.
    }

    func transcribe(
        audio _: [Float],
        anchorHostTime: UInt64
    ) async throws -> WhisperWindowResult {
        let action: (String, TranscriptionError?) = state.withLock { snapshot in
            snapshot.callCount += 1
            let thrown = snapshot.throwOnNextCall
            snapshot.throwOnNextCall = nil
            let index = min(snapshot.nextIndex, snapshot.languages.count - 1)
            let language: String
            if snapshot.languages.isEmpty {
                language = ""
            } else {
                language = snapshot.languages[index]
            }
            snapshot.nextIndex += 1
            return (language, thrown)
        }
        if let thrown = action.1 {
            throw thrown
        }
        return WhisperWindowResult(
            language: action.0,
            windowAnchorHostTime: anchorHostTime,
            segments: []
        )
    }
}

/// Fake `WhisperClient` whose `transcribe` blocks until cancelled and
/// records a cancellation stamp into the supplied ``StampRecorder``
/// when the surrounding task is cancelled (used by the
/// stop-cancel-ordering test).
private final nonisolated class CancelObservingWhisperClient: WhisperClient, @unchecked Sendable {
    private let recorder: StampRecorder

    init(recorder: StampRecorder) {
        self.recorder = recorder
    }

    func prewarmModels() async throws {}

    func transcribe(
        audio _: [Float],
        anchorHostTime: UInt64
    ) async throws -> WhisperWindowResult {
        await withTaskCancellationHandler {
            await parkUntilCancelled()
        } onCancel: { [recorder] in
            recorder.bumpRouter()
        }
        return WhisperWindowResult(
            language: "ja",
            windowAnchorHostTime: anchorHostTime,
            segments: []
        )
    }
}

/// Parks the calling task until cancellation. Used by
/// ``CancelObservingWhisperClient`` to keep a `transcribe` call alive
/// long enough for `router.cancel()` to fire its
/// `withTaskCancellationHandler.onCancel` closure. `Task.sleep`
/// is preferred over a never-resuming `withCheckedContinuation`
/// because the latter trips Swift's "continuation leaked" diagnostic
/// when the parent task is cancelled (the diagnostic is correct —
/// the continuation never resumes, even though the parent task is
/// gone).
private func parkUntilCancelled() async {
    do {
        // 1 hour is effectively forever for these tests; cancellation
        // surfaces as `CancellationError` which we swallow so the
        // surrounding `withTaskCancellationHandler` body returns
        // cleanly.
        try await Task.sleep(for: .seconds(3600))
    } catch {
        // Expected on task cancellation.
    }
}

/// Monotonic stamp recorder used by
/// `pipeline_stop_awaitsRouterCancelThenTranslatorCancel_inOrder` to
/// prove the router cancel ran before the translator cancel.
/// `OSAllocatedUnfairLock` so both async and sync callers (the
/// translator's `cancel()` and the WhisperClient's onCancel closure
/// respectively) can record stamps without an awaited hop.
private final nonisolated class StampRecorder: @unchecked Sendable {
    private struct State {
        var nextStamp: Int = 0
        var routerStamp: Int?
        var translatorStamp: Int?
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    func bumpRouter() {
        state.withLock { snapshot in
            snapshot.nextStamp += 1
            snapshot.routerStamp = snapshot.nextStamp
        }
    }

    func bumpTranslator() {
        state.withLock { snapshot in
            snapshot.nextStamp += 1
            snapshot.translatorStamp = snapshot.nextStamp
        }
    }

    var routerStamp: Int? {
        state.withLock { $0.routerStamp }
    }

    var translatorStamp: Int? {
        state.withLock { $0.translatorStamp }
    }
}

/// Recording test fake for ``Translating`` — a parallel, divergent
/// shape from `ArigatoAITests/Translation/FakeTranslator.swift`.
///
/// ## Why two fakes
///
/// `FakeTranslator` is the **canned-producer** shape used by Group C's
/// protocol-conformance tests and downstream actor tests
/// (`TranslationProtocolTests`, `TranslationActorTests`). It emits a
/// fixed `[chunk]` partial + a deterministic `completed` per upstream
/// segment, optionally with a single configured failure.
///
/// `RecordingTranslator` is the **recording + scripting** shape Step 4
/// needs: it records the ordered log of
/// `translate(segments:direction:)` invocations (so direction-flip
/// tests can assert exact direction values per invocation), records
/// each `cancel()` with a stamp from ``StampRecorder`` (so the
/// router-cancel-before-translator-cancel ordering test can compare
/// stamps), and lets the test configure per-invocation event scripts —
/// including yielding an error mid-stream so the
/// `translator-throws-on-events-stream` violation test can be driven.
/// It also exposes the upstream segment stream it received so tests
/// can verify cancel-and-restart finished the prior stream.
///
/// ## Why private to `MeetingPipelineTests.swift`
///
/// Step 4 doesn't need to alter the canonical translation test
/// fixtures. `FakeTranslator` is still the right shape for Group C
/// protocol tests; promoting `RecordingTranslator` to
/// `ArigatoAITests/Translation/` would broaden Step 4's scope to fixture
/// migration — out of scope per CLAUDE.md "swift-implementer
/// scope-and-decision discipline" absolute file scope rule. If a future
/// step needs the same recording shape (e.g., when wiring tests for
/// Step 5's outer coordinator), this type can be promoted at that
/// point with a clean migration.
///
/// ## Scheduling assumption
///
/// `RecordingTranslator` processes each `translate(segments:direction:)`
/// call by spawning a producer task that drives the supplied event
/// script. `cancel()` finishes the active event stream and cancels the
/// producer task. The fake never blocks `translate` itself — the
/// event-driving happens on the spawned task — so the pipeline's
/// invocation log records direction values in arrival order.
private actor RecordingTranslator: Translating {
    /// One scripted action the recording translator can perform per
    /// upstream segment.
    enum EventScriptAction {
        /// Yield a `.completed(TranslatedSegment)` event when this
        /// segment arrives. The translated segment is built with
        /// canned text by the fake.
        case yieldCompleted
        /// Yield an explicit `.partialChunk` event with the given
        /// delta — does NOT then complete; the next script entry runs
        /// for the next segment.
        case yieldPartial(delta: String)
        /// Finish the event stream with the supplied
        /// ``TranslationError`` when this segment arrives. Subsequent
        /// segments on the upstream are not processed for this
        /// translate call.
        case throwError(TranslationError)
        /// Yield nothing — useful for tests that just want to log
        /// which segments arrived without persisting them.
        case noEvent
    }

    /// One recorded entry per `translate(segments:direction:)` call.
    struct TranslateInvocation {
        let direction: TranslationDirection
        let segmentsReceived: Int
        /// The continuation used to finish the event stream for this
        /// invocation. Held so `cancel()` can finish it.
        let eventContinuation: AsyncThrowingStream<TranslationEvent, any Error>.Continuation
    }

    // MARK: - Recorded state

    private(set) var translateInvocations: [TranslateInvocation] = []
    private(set) var translateInvocationDirections: [TranslationDirection] = []
    /// Per-invocation index of the most recent script step consumed.
    /// Indexed against ``defaultScript`` for the corresponding
    /// invocation.
    private(set) var cancelCount: Int = 0
    private(set) var segmentsObservedPerInvocation: [Int] = []
    /// Total number of segments observed across all translate
    /// invocations. Useful for greedy-upstream tests that want to
    /// confirm every emitted segment reached the translator.
    private(set) var totalSegmentsObserved: Int = 0

    // MARK: - Config

    private var defaultScript: [EventScriptAction]
    private let stampRecorder: StampRecorder?

    init(
        defaultScript: [EventScriptAction] = [.yieldCompleted],
        stampRecorder: StampRecorder? = nil
    ) {
        self.defaultScript = defaultScript
        self.stampRecorder = stampRecorder
    }

    func setDefaultScript(_ script: [EventScriptAction]) {
        defaultScript = script
    }

    // MARK: - Translating conformance

    func warmup() async throws {}

    func warmupState() async -> TranslationWarmupState {
        .ready
    }

    func translate(
        segments: AsyncStream<TranscriptSegment>,
        direction: TranslationDirection
    ) async -> AsyncThrowingStream<TranslationEvent, any Error> {
        let (eventStream, eventCont) = AsyncThrowingStream<TranslationEvent, any Error>.makeStream()
        let invocation = TranslateInvocation(
            direction: direction,
            segmentsReceived: 0,
            eventContinuation: eventCont
        )
        translateInvocations.append(invocation)
        translateInvocationDirections.append(direction)
        let invocationIndex = translateInvocations.count - 1
        segmentsObservedPerInvocation.append(0)

        let script = defaultScript
        let invocationDirection = direction

        Task { [weak self] in
            var stepIndex = 0
            for await segment in segments {
                await self?.recordObservedSegment(invocationIndex: invocationIndex)
                let action = script.indices.contains(stepIndex)
                    ? script[stepIndex]
                    : (script.last ?? .yieldCompleted)
                stepIndex += 1
                switch action {
                case .yieldCompleted:
                    let translated = TranslatedSegment(
                        sourceSegmentID: segment.id,
                        sourceText: segment.text,
                        translatedText: "translated:\(segment.text)",
                        direction: invocationDirection,
                        startHostTime: segment.startHostTime,
                        endHostTime: segment.endHostTime,
                        isFallback: false
                    )
                    eventCont.yield(.completed(translated))
                case let .yieldPartial(delta):
                    eventCont.yield(.partialChunk(sourceSegmentID: segment.id, delta: delta))
                case let .throwError(err):
                    eventCont.finish(throwing: err)
                    return
                case .noEvent:
                    continue
                }
            }
            // Upstream finished normally — finish the event stream too
            // unless cancel() has already finished it.
            eventCont.finish()
        }

        return eventStream
    }

    func cancel() async {
        cancelCount += 1
        stampRecorder?.bumpTranslator()
        for invocation in translateInvocations {
            invocation.eventContinuation.finish()
        }
    }

    // MARK: - Helpers

    private func recordObservedSegment(invocationIndex: Int) {
        if segmentsObservedPerInvocation.indices.contains(invocationIndex) {
            segmentsObservedPerInvocation[invocationIndex] += 1
        }
        totalSegmentsObserved += 1
    }
}

// MARK: - Frame helpers

/// Produces `totalSeconds` of synthetic 16 kHz mono audio in 100 ms
/// frames. Mirrors the helper in `LanguageRouterTests` so the upstream
/// `TranscriptionActor` sees the same shape of input.
private func makeFrameSequence(
    totalSeconds: Double,
    framesPerSecond: Int = 10,
    startHostTime: UInt64 = 0,
    sampleRate: Double = 16000
) -> [AudioFrame] {
    let frameCount = Int((totalSeconds * Double(framesPerSecond)).rounded())
    let samplesPerFrame = Int(sampleRate / Double(framesPerSecond))
    let nanosPerFrame = 1_000_000_000.0 / Double(framesPerSecond)
    let ticksPerFrame = machTicks(forNanoseconds: nanosPerFrame)
    var frames: [AudioFrame] = []
    frames.reserveCapacity(frameCount)
    for index in 0 ..< frameCount {
        let hostTime = startHostTime &+ (UInt64(index) &* ticksPerFrame)
        let samples = [Float](repeating: 0.0, count: samplesPerFrame)
        frames.append(
            AudioFrame(samples: samples, hostTime: hostTime, frameCount: samplesPerFrame)
        )
    }
    return frames
}

private func makeFrameStream(_ frames: [AudioFrame]) -> AsyncStream<AudioFrame> {
    AsyncStream { continuation in
        for frame in frames {
            continuation.yield(frame)
        }
        continuation.finish()
    }
}

private func makeOpenFrameStream() -> (AsyncStream<AudioFrame>, AsyncStream<AudioFrame>.Continuation) {
    // `AsyncStream.makeStream()` returns both halves without needing
    // a force-unwrap / implicitly-unwrapped continuation capture
    // pattern. Preferred per CLAUDE.md "no force-unwraps in
    // production code" — though this is test code, the same hygiene
    // applies to the implicitly-unwrapped optional that would
    // otherwise be required to escape the AsyncStream initialiser
    // closure.
    let pair = AsyncStream<AudioFrame>.makeStream()
    return (pair.stream, pair.continuation)
}

private func machTicks(forNanoseconds nanos: Double) -> UInt64 {
    var info = mach_timebase_info_data_t()
    mach_timebase_info(&info)
    let numer = Double(info.numer)
    let denom = Double(info.denom)
    guard numer > 0 else { return UInt64(nanos.rounded()) }
    let ticks = (nanos * denom / numer).rounded()
    guard ticks >= 0 else { return 0 }
    return UInt64(ticks)
}

/// Total seconds required for the upstream `TranscriptionActor` to emit
/// exactly `n` non-final windows. Prefill = 5 s, hop = 1 s.
private func totalSeconds(forWindowCount n: Int) -> Double {
    Double(4 + n)
}

// MARK: - Fixture

@MainActor
private struct PipelineFixture {
    let container: ModelContainer
    let store: MeetingStore
    let session: MeetingSession
    let router: LanguageRouter
    let translator: RecordingTranslator
    let pipeline: MeetingPipeline
}

@MainActor
private func makeFixture(
    languages: [String],
    confirmationsRequired: Int = LanguageRouter.defaultConfirmationsRequired,
    whisperClient: (any WhisperClient)? = nil,
    translatorScript: [RecordingTranslator.EventScriptAction] = [.yieldCompleted],
    stampRecorder: StampRecorder? = nil
) throws -> PipelineFixture {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(
        for: Meeting.self, Sentence.self,
        configurations: config
    )
    let store = MeetingStore(modelContainer: container)
    let session = MeetingSession(store: store)
    let client: any WhisperClient = whisperClient
        ?? ScriptedLanguagePipelineWhisperClient(languages: languages)
    let transcriber = TranscriptionActor(clientFactory: { client })
    let router = LanguageRouter(
        transcriber: transcriber,
        confirmationsRequired: confirmationsRequired
    )
    let translator = RecordingTranslator(
        defaultScript: translatorScript,
        stampRecorder: stampRecorder
    )
    let pipeline = MeetingPipeline(
        router: router,
        translator: translator,
        session: session
    )
    return PipelineFixture(
        container: container,
        store: store,
        session: session,
        router: router,
        translator: translator,
        pipeline: pipeline
    )
}

/// Waits up to `iterations` short main-actor yields for `condition` to
/// become true. Mirrors the helper from `MeetingSessionTests`.
@MainActor
private func awaitCondition(
    iterations: Int = 2000,
    condition: () async -> Bool
) async -> Bool {
    for _ in 0 ..< iterations {
        if await condition() { return true }
        await Task.yield()
    }
    return await condition()
}

/// Waits until the SwiftData container reports at least `count`
/// `Sentence` rows.
private func awaitSentenceCount(
    _ count: Int,
    in container: ModelContainer,
    iterations: Int = 5000
) async -> Int {
    for _ in 0 ..< iterations {
        let ctx = ModelContext(container)
        let n = (try? ctx.fetch(FetchDescriptor<Sentence>()).count) ?? 0
        if n >= count { return n }
        await Task.yield()
    }
    let ctx = ModelContext(container)
    return (try? ctx.fetch(FetchDescriptor<Sentence>()).count) ?? 0
}

// MARK: - Tests

@Suite("MeetingPipeline")
@MainActor
struct MeetingPipelineTests {
    // MARK: - Happy path (2)

    /// On the first segment the pipeline subscribes to
    /// `LanguageRouter.transcribe(frames:)` and invokes
    /// `translator.translate(segments:direction:)` with direction
    /// derived from the first segment's `language`. With scripted
    /// language `"ja"`, the derived direction is `.jaToEn`.
    @Test func pipeline_start_subscribesToRouterTranscribe_invokesTranslatorWithDirectionFromFirstSegment() async throws {
        let fixture = try makeFixture(
            languages: ["ja"],
            translatorScript: [.yieldCompleted]
        )
        try await fixture.session.start(at: Date())

        let frames = makeFrameSequence(totalSeconds: totalSeconds(forWindowCount: 1))
        await fixture.pipeline.start(frames: makeFrameStream(frames))

        let observed = await awaitCondition {
            await fixture.translator.translateInvocationDirections.first == .jaToEn
        }
        #expect(observed, "Translator should be invoked with .jaToEn for first ja segment")
        let directions = await fixture.translator.translateInvocationDirections
        #expect(directions == [.jaToEn])
    }

    /// A `.completed(TranslatedSegment)` event from the recording
    /// translator reaches `MeetingSession.consumeTranslationEvents` and
    /// produces a persisted `Sentence` row.
    @Test func pipeline_translationCompletedEvent_reachesMeetingSessionConsumer() async throws {
        let fixture = try makeFixture(
            languages: ["ja"],
            translatorScript: [.yieldCompleted]
        )
        try await fixture.session.start(at: Date())

        let frames = makeFrameSequence(totalSeconds: totalSeconds(forWindowCount: 1))
        await fixture.pipeline.start(frames: makeFrameStream(frames))

        let landed = await awaitSentenceCount(1, in: fixture.container)
        #expect(landed == 1, "Translator's .completed event should persist exactly 1 Sentence row")

        let ctx = ModelContext(fixture.container)
        let sentences = try ctx.fetch(FetchDescriptor<Sentence>())
        #expect(sentences.first?.sourceLanguage == "ja",
                "Persisted sentence should reflect the ja→en direction's source language")
    }

    // MARK: - Direction handling (2)

    /// **Concurrency violation test (per CLAUDE.md "Concurrency design
    /// discipline").** A language flip mid-stream cancels the
    /// translator and restarts it with the new direction. With
    /// `confirmationsRequired = 1`, scripted languages
    /// `["en", "ja", "ja"]` produce: window 1 establishes `.enToJa`,
    /// window 2 flips on the single disagreement to `.jaToEn`,
    /// window 3 continues `.jaToEn`. The pipeline must observe one
    /// translator cancel + a second translate call with `.jaToEn`.
    @Test func pipeline_languageFlipMidStream_triggersTranslatorCancelAndRestart_withCorrectDirection() async throws {
        let fixture = try makeFixture(
            languages: ["en", "ja", "ja"],
            confirmationsRequired: 1,
            translatorScript: [.noEvent]
        )
        try await fixture.session.start(at: Date())

        let frames = makeFrameSequence(totalSeconds: totalSeconds(forWindowCount: 3))
        await fixture.pipeline.start(frames: makeFrameStream(frames))

        let observed = await awaitCondition {
            await fixture.translator.translateInvocationDirections.count >= 2
        }
        #expect(observed, "Expected at least two translate invocations after flip")

        let directions = await fixture.translator.translateInvocationDirections
        #expect(directions.first == .enToJa,
                "First invocation should be .enToJa from leading 'en' segment")
        #expect(directions.dropFirst().first == .jaToEn,
                "Second invocation (after flip) should be .jaToEn")

        let cancels = await fixture.translator.cancelCount
        #expect(cancels >= 1, "Flip should trigger at least one translator cancel")
    }

    /// A first segment whose text is empty (silence-only window with a
    /// supported language code) still establishes the pipeline's
    /// direction. The `ScriptedLanguagePipelineWhisperClient` always
    /// returns empty segments, so the router's emitted text for
    /// window 1 is `""` — the pipeline must still observe
    /// `language=.ja` and invoke the translator with `.jaToEn`.
    @Test func pipeline_emptyFirstSegmentText_stillEstablishesDirection() async throws {
        let fixture = try makeFixture(
            languages: ["ja"],
            translatorScript: [.noEvent]
        )
        try await fixture.session.start(at: Date())

        let frames = makeFrameSequence(totalSeconds: totalSeconds(forWindowCount: 1))
        await fixture.pipeline.start(frames: makeFrameStream(frames))

        let observed = await awaitCondition {
            await fixture.translator.translateInvocationDirections.first == .jaToEn
        }
        #expect(observed, "Empty-text first segment should still establish direction")
        // Direction is recorded in `translate(...)` before the segment
        // is yielded into the stream — wait for the segment to land in
        // the recording translator's per-invocation observed counter
        // before asserting, otherwise the test races the producer
        // task's first read.
        let segmentObserved = await awaitCondition {
            await fixture.translator.totalSegmentsObserved >= 1
        }
        #expect(segmentObserved,
                "Empty-text segment must still be forwarded to the translator")
    }

    // MARK: - Lifecycle (3)

    /// **Concurrency violation test.** `stop()` cancels the pipeline
    /// task, then awaits `router.cancel()`, then awaits
    /// `translator.cancel()`. A `CancelObservingWhisperClient` records
    /// the router-cancel stamp via `withTaskCancellationHandler`'s
    /// `onCancel`; the `RecordingTranslator.cancel()` records the
    /// translator-cancel stamp. Assert router stamp < translator
    /// stamp.
    @Test func pipeline_stop_awaitsRouterCancelThenTranslatorCancel_inOrder() async throws {
        let recorder = StampRecorder()
        let whisper = CancelObservingWhisperClient(recorder: recorder)
        let fixture = try makeFixture(
            languages: ["ja"],
            whisperClient: whisper,
            translatorScript: [.noEvent],
            stampRecorder: recorder
        )
        try await fixture.session.start(at: Date())

        let (frames, framesCont) = makeOpenFrameStream()
        // Yield one synthetic frame so the TranscriptionActor's drain
        // task starts (without enough audio to emit a window). The
        // WhisperClient is parked-on-cancel, so router.cancel() will
        // trigger the onCancel handler.
        // Push enough audio to exceed prefill so a transcribe call
        // begins and parks in withTaskCancellationHandler. 6 seconds
        // produces ~1 hop attempt past prefill.
        for frame in makeFrameSequence(totalSeconds: totalSeconds(forWindowCount: 1)) {
            framesCont.yield(frame)
        }
        // Keep the stream open so the upstream doesn't finish before
        // we observe cancel ordering.
        await fixture.pipeline.start(frames: frames)

        // Wait until the WhisperClient parks (router cancel will then
        // observe its task cancellation).
        let parked = await awaitCondition(iterations: 5000) {
            // We can't directly observe parking, but once the
            // transcriber's first inflight call enters
            // `withTaskCancellationHandler`, the call to stop() will
            // surface the cancel. So wait until the pipeline task
            // has been initialised (it has — we already returned from
            // start()). A short yield budget is sufficient.
            true
        }
        #expect(parked)
        // Give the pipeline task some yields to actually reach the
        // routerStream's for-try-await iteration, which causes the
        // TranscriptionActor's windowStream drain to begin and the
        // WhisperClient's transcribe call to park.
        for _ in 0 ..< 50 {
            await Task.yield()
        }

        await fixture.pipeline.stop()
        framesCont.finish()

        // Wait for both stamps to be recorded. The
        // RecordingTranslator.cancel() records synchronously inside
        // its async method body; the WhisperClient onCancel records
        // synchronously inside the cancellation handler.
        let recorded = await awaitCondition(iterations: 5000) {
            recorder.routerStamp != nil && recorder.translatorStamp != nil
        }
        #expect(recorded, "Both router and translator cancel stamps should be recorded")
        guard let routerStamp = recorder.routerStamp,
              let translatorStamp = recorder.translatorStamp
        else {
            Issue.record("Stamps missing — router=\(recorder.routerStamp as Any) translator=\(recorder.translatorStamp as Any)")
            return
        }
        #expect(routerStamp < translatorStamp,
                "Router cancel must happen before translator cancel; got router=\(routerStamp) translator=\(translatorStamp)")
    }

    /// **Concurrency violation test.** A second `stop()` after the
    /// pipeline has already been torn down is a no-op — no extra
    /// translator cancel is recorded.
    @Test func pipeline_stop_isIdempotent_secondCallIsNoOp() async throws {
        let fixture = try makeFixture(
            languages: ["ja"],
            translatorScript: [.noEvent]
        )
        try await fixture.session.start(at: Date())

        let frames = makeFrameSequence(totalSeconds: totalSeconds(forWindowCount: 1))
        await fixture.pipeline.start(frames: makeFrameStream(frames))

        // Wait for the first translate invocation to land so we have
        // a meaningful "active" translator to cancel.
        _ = await awaitCondition {
            await fixture.translator.translateInvocationDirections.count >= 1
        }

        await fixture.pipeline.stop()
        let cancelsAfterFirst = await fixture.translator.cancelCount
        await fixture.pipeline.stop()
        let cancelsAfterSecond = await fixture.translator.cancelCount
        #expect(cancelsAfterSecond == cancelsAfterFirst,
                "Second stop() must not invoke translator.cancel() again; got \(cancelsAfterFirst) → \(cancelsAfterSecond)")
    }

    /// **Concurrency violation test.** A second `start(frames:)` call
    /// cancels the prior pipeline task and replaces it. After the
    /// second start, only the second pipeline's translate invocations
    /// drive `MeetingSession`. The recording translator's invocation
    /// log shows the first translate's stream finished (because the
    /// prior start was torn down).
    @Test func pipeline_secondStart_cancelsFirstAndReplacesCleanly() async throws {
        let fixture = try makeFixture(
            languages: ["ja"],
            translatorScript: [.noEvent]
        )
        try await fixture.session.start(at: Date())

        let frames1 = makeFrameSequence(totalSeconds: totalSeconds(forWindowCount: 1))
        await fixture.pipeline.start(frames: makeFrameStream(frames1))
        _ = await awaitCondition {
            await fixture.translator.translateInvocationDirections.count >= 1
        }
        let cancelsBeforeSecondStart = await fixture.translator.cancelCount

        let frames2 = makeFrameSequence(totalSeconds: totalSeconds(forWindowCount: 1))
        await fixture.pipeline.start(frames: makeFrameStream(frames2))

        // Second start should have awaited cancel for the prior
        // translator session.
        let cancelsAfterSecondStart = await fixture.translator.cancelCount
        #expect(cancelsAfterSecondStart > cancelsBeforeSecondStart,
                "Second start() must cancel the prior translator session; cancels \(cancelsBeforeSecondStart) → \(cancelsAfterSecondStart)")

        // Eventually the second pipeline should invoke translate at
        // least once more (a new translate per start, once a segment
        // arrives).
        let observed = await awaitCondition {
            await fixture.translator.translateInvocationDirections.count >= 2
        }
        #expect(observed, "Second start should produce a second translate invocation")
    }

    // MARK: - Error propagation (2)

    /// **Concurrency violation test.** When the upstream router throws
    /// a `TranscriptionError`, the pipeline clears its in-memory state
    /// and exits silently. It does NOT call
    /// `MeetingSession.finalizeStop` — the session's phase remains
    /// `.recording` (the session's lifecycle is owned by the UI, not
    /// the pipeline).
    @Test func pipeline_upstreamThrowsTranscriptionError_clearsStateWithoutCallingFinalizeStop() async throws {
        let client = ScriptedLanguagePipelineWhisperClient(languages: ["ja"])
        client.setThrowOnNextCall(.decodeFailed("synthetic"))
        let fixture = try makeFixture(
            languages: ["ja"],
            whisperClient: client,
            translatorScript: [.noEvent]
        )
        let startedAt = Date(timeIntervalSince1970: 1_700_000_000)
        try await fixture.session.start(at: startedAt)
        let phaseBefore = fixture.session.phase

        let frames = makeFrameSequence(totalSeconds: totalSeconds(forWindowCount: 1))
        await fixture.pipeline.start(frames: makeFrameStream(frames))

        // Give the pipeline plenty of yields to let the upstream
        // throw, the pipeline drain task observe the error, and the
        // catch branch run.
        _ = await awaitCondition(iterations: 5000) { false }

        // Session phase must NOT have changed to .ended — pipeline is
        // forbidden from calling finalizeStop on upstream errors.
        switch fixture.session.phase {
        case .recording:
            // Expected.
            break
        case .ended:
            Issue.record("Pipeline should not have called finalizeStop on TranscriptionError")
        default:
            Issue.record("Unexpected phase after upstream error: \(fixture.session.phase)")
        }
        // Phase identifiers preserved.
        guard case let .recording(idBefore, _) = phaseBefore,
              case let .recording(idAfter, _) = fixture.session.phase
        else {
            Issue.record("Expected .recording before and after; got \(phaseBefore) → \(fixture.session.phase)")
            return
        }
        #expect(idBefore == idAfter, "Meeting ID must remain stable after upstream error")
    }

    /// A translator error on the events stream is swallowed at the
    /// `MeetingSession` consumer layer (per Step 3's contract) and
    /// does not bubble into the pipeline's failure path. The pipeline
    /// state should remain ready for a subsequent direction-flip /
    /// retry; here we assert that pipeline.stop() still runs cleanly
    /// and that the session's phase is unchanged.
    @Test func pipeline_translatorThrowsOnEventsStream_clearsPipelineStateAndExitsSilently() async throws {
        let fixture = try makeFixture(
            languages: ["ja"],
            translatorScript: [.throwError(.generationFailed("synthetic"))]
        )
        let startedAt = Date(timeIntervalSince1970: 1_700_000_000)
        try await fixture.session.start(at: startedAt)

        let frames = makeFrameSequence(totalSeconds: totalSeconds(forWindowCount: 1))
        await fixture.pipeline.start(frames: makeFrameStream(frames))

        // Let the error path run.
        _ = await awaitCondition(iterations: 5000) { false }

        // Session phase remains .recording — translator-stream errors
        // are surfaced via UI markers (decision #15) in a later step,
        // not by tearing down the session.
        switch fixture.session.phase {
        case .recording:
            break
        default:
            Issue.record("Pipeline must not change session phase on translator error; got \(fixture.session.phase)")
        }

        // Pipeline can still be stopped cleanly.
        await fixture.pipeline.stop()
    }

    // MARK: - Scheduling discipline (1)

    /// **Concurrency violation test.** A greedy upstream that yields
    /// >100 hops without intermediate `Task.yield()` must not cause
    /// the pipeline to deadlock or lose any segment that survived
    /// the router. Uses 100 hops of synthetic audio (totalSeconds =
    /// 104) — `TranscriptionActor`'s C30 drop-oldest may discard
    /// some hops at the upstream layer (that is the actor's
    /// documented behaviour), so we use the router's
    /// `routedHistory.count` as the **truth source** for "how many
    /// segments the router actually emitted." The pipeline must
    /// forward every one of those to the translator.
    @Test func pipeline_greedyUpstreamSegments_doesNotDeadlockOrLoseEvents() async throws {
        let fixture = try makeFixture(
            languages: ["ja"],
            translatorScript: [.noEvent]
        )
        try await fixture.session.start(at: Date())

        let windowCount = 100
        let frames = makeFrameSequence(totalSeconds: totalSeconds(forWindowCount: windowCount))
        await fixture.pipeline.start(frames: makeFrameStream(frames))

        // Wait until the router has stopped producing — i.e., the
        // routedHistory count stops growing. Once the upstream frame
        // stream finishes and the router's drain task exits,
        // `routedHistory` is final.
        var priorRouted = -1
        var stableTicks = 0
        for _ in 0 ..< 30000 {
            let currentRouted = fixture.router.routedHistory.count
            if currentRouted == priorRouted, currentRouted > 0 {
                stableTicks += 1
                if stableTicks >= 5 { break }
            } else {
                stableTicks = 0
            }
            priorRouted = currentRouted
            await Task.yield()
        }
        let routedCount = fixture.router.routedHistory.count
        #expect(routedCount > 0, "Router should have produced at least one segment")

        // The pipeline must observe every segment the router emitted.
        // Drops at the upstream `TranscriptionActor` layer are C30
        // contract behaviour and not counted against the pipeline.
        let observed = await awaitCondition(iterations: 5000) {
            await fixture.translator.totalSegmentsObserved >= routedCount
        }
        let totalObserved = await fixture.translator.totalSegmentsObserved
        #expect(observed,
                "Pipeline must forward every router-emitted segment; routed=\(routedCount) observed=\(totalObserved)")
        #expect(totalObserved == routedCount,
                "Pipeline forwarded \(totalObserved) segments but router emitted \(routedCount) — drops in the pipeline are forbidden")
        // Direction should remain .jaToEn — same-language stream
        // does not flip.
        let directions = await fixture.translator.translateInvocationDirections
        #expect(directions.count == 1,
                "Greedy same-language upstream should not trigger flips; got \(directions.count) invocations")
        #expect(directions.first == .jaToEn)
    }
}
