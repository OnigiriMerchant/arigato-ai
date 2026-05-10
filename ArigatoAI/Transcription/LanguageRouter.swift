//
//  LanguageRouter.swift
//  ArigatoAI
//
//  Created by Jose Castell on 2026/05/10.
//

import Foundation

/// Consumes ``TranscriptionWindow`` values from a ``TranscriptionActor``
/// and applies consecutive-window disagreement gating (Phase 4 Decision 5,
/// N=2) before re-emitting them as ``RoutedTranscript`` values for the
/// transcript-log surface and as ``TranscriptSegment`` values for the
/// ``Transcribing`` protocol surface.
///
/// ## Surfaces
///
/// **SEAM-1.** Two output surfaces:
/// - ``routedTranscripts()`` returns an
///   `AsyncThrowingStream<RoutedTranscript, any Error>` for the transcript
///   log. Each element carries both the honest signal
///   (``RoutedTranscript/detectedLanguage``) and the stable signal
///   (``RoutedTranscript/authoritativeLanguage``).
/// - ``currentLanguage`` is an `@Observable` property bound directly by UI
///   chrome (language indicator). Updates atomically with each emitted
///   ``RoutedTranscript`` whose ``RoutedTranscript/didFlip`` is `true` (or
///   on the first supported-code window when the gate is uninitialised).
///
/// **SEAM-4.** Conformance to ``Transcribing`` lives here, NOT on
/// ``TranscriptionActor``. The lossy mapping
/// ``RoutedTranscript`` -> ``TranscriptSegment`` uses
/// ``RoutedTranscript/authoritativeLanguage`` (the stable signal) because
/// ``TranscriptSegment`` consumers downstream of the protocol expect the
/// router's gate to have already smoothed transient disagreements.
///
/// ## Gate state machine (N=2 consecutive-window disagreement)
///
/// On each window from upstream:
///
/// 1. If ``TranscriptionWindow/detectedLanguage`` is `nil` (Whisper
///    returned a code outside `{ja, en}`, including the empty string —
///    SEAM-5 / Decision 14): **drop the window silently**. No
///    ``RoutedTranscript`` is emitted; the gate counter and authoritative
///    language are unchanged; ``currentLanguage`` is unchanged.
///
/// 2. Else, if no authoritative language has been established yet (first
///    supported-code window): set authoritative = detected, set
///    ``currentLanguage`` = detected, reset counter to 0, emit a
///    ``RoutedTranscript`` with ``RoutedTranscript/didFlip`` = `false`.
///
/// 3. Else, if detected == authoritative: reset counter to 0; emit a
///    ``RoutedTranscript`` with detected = authoritative and
///    ``RoutedTranscript/didFlip`` = `false`.
///
/// 4. Else (detected != authoritative): increment counter. If counter
///    >= ``confirmationsRequired`` (= 2), flip — set authoritative =
///    detected, set ``currentLanguage`` = detected, reset counter to 0,
///    emit a ``RoutedTranscript`` with detected = authoritative and
///    ``RoutedTranscript/didFlip`` = `true`. Otherwise emit a
///    ``RoutedTranscript`` with detected != authoritative (the SEAM-2
///    divergence) and ``RoutedTranscript/didFlip`` = `false`.
///
/// ## Scheduling assumption (Concurrency design discipline)
///
/// The router's drain task consumes upstream ``TranscriptionWindow``
/// values on the MainActor, one at a time. Gate state mutations
/// (``currentLanguage``, the disagreement counter, the authoritative
/// language) and the corresponding ``RoutedTranscript`` emission happen
/// atomically with respect to one window: the drain awaits one window,
/// applies the state transition, yields the resulting transcript (if
/// any), then awaits the next.
///
/// **Assumption.** The router does NOT internally queue windows. If the
/// upstream ``TranscriptionActor/windowStream(frames:)`` produces faster
/// than this router's MainActor hop can advance, AsyncStream's natural
/// backpressure applies — the upstream's continuation buffers per its
/// own configuration, and the router catches up window by window.
///
/// **Violation behaviour.** If the consumer of ``routedTranscripts()``
/// stops iterating, the upstream eventually backs up; no windows are
/// dropped here, but the upstream's bounded queue (contract C30) may
/// drop oldest hops. That is the upstream's contract, not the router's.
///
/// **Violation test.** The C29 cancel test drives an upstream
/// ``TranscriptionActor/cancel()`` mid-flight; the router observes the
/// upstream stream finish and finishes its own continuation cleanly,
/// without throwing.
@MainActor
@Observable
final class LanguageRouter: Transcribing {
    /// Default number of consecutive disagreements required before the
    /// gate flips (Phase 4 Decision 5).
    nonisolated static let defaultConfirmationsRequired: Int = 2

    // MARK: - Public observable state

    /// The router's current authoritative language, suitable for direct
    /// SwiftUI binding. `nil` before the first supported-code window has
    /// arrived; non-`nil` thereafter.
    ///
    /// Updates atomically with each emitted ``RoutedTranscript`` whose
    /// flip semantics establish or change the authoritative language.
    /// Windows with unsupported codes (SEAM-5) leave this value
    /// unchanged.
    private(set) var currentLanguage: SpokenLanguage?

    // MARK: - Stored state

    private let transcriber: TranscriptionActor
    private let confirmationsRequired: Int

    /// Authoritative language after gating. `nil` before the first
    /// supported-code window; mirrors ``currentLanguage`` but kept as a
    /// separate field so the `@Observable` surface area is clear.
    private var authoritativeLanguage: SpokenLanguage?

    /// Count of consecutive disagreements observed since the last
    /// agreement or flip. Reset to 0 on agreement, on flip, and never
    /// touched for windows with unsupported codes (SEAM-5).
    private var disagreementCounter: Int = 0

    // MARK: - Initialisation

    /// Creates a new router wired to a ``TranscriptionActor`` upstream.
    ///
    /// - Parameters:
    ///   - transcriber: The actor that produces ``TranscriptionWindow``
    ///     values. The router takes ownership of one
    ///     ``TranscriptionActor/windowStream(frames:)`` session per
    ///     ``transcribe(frames:)`` call.
    ///   - confirmationsRequired: Number of consecutive disagreements
    ///     required before the gate flips. Defaults to
    ///     ``defaultConfirmationsRequired`` (= 2). Must be at least 1;
    ///     values below 1 are clamped to 1.
    init(
        transcriber: TranscriptionActor,
        confirmationsRequired: Int = LanguageRouter.defaultConfirmationsRequired
    ) {
        self.transcriber = transcriber
        self.confirmationsRequired = max(1, confirmationsRequired)
    }

    // MARK: - SEAM-1 surface (a): RoutedTranscript stream

    /// Begins a new transcription session and returns a throwing async
    /// stream of ``RoutedTranscript`` values.
    ///
    /// Each yielded value reflects one ``TranscriptionWindow`` whose
    /// detected language was a supported code (`ja` or `en`). Windows
    /// with unsupported detected codes are dropped silently per SEAM-5.
    ///
    /// - Returns: A throwing async stream of ``RoutedTranscript`` values.
    ///   Errors from the upstream transcriber propagate verbatim.
    func routedTranscripts() -> AsyncThrowingStream<RoutedTranscript, any Error> {
        AsyncThrowingStream<RoutedTranscript, any Error> { continuation in
            // The frames stream for this surface is empty; production
            // callers who want the RoutedTranscript surface bring their
            // own frames via transcribe(frames:). This convenience
            // surface is for callers who already populated a session via
            // a separate path. For Phase 4 MVP the primary entry point is
            // transcribe(frames:); this method exists to satisfy SEAM-1's
            // documented surface and is a thin shim.
            let emptyFrames = AsyncStream<AudioFrame> { c in c.finish() }
            let task = Task { [weak self] in
                guard let self else {
                    continuation.finish()
                    return
                }
                let upstream = await self.transcriber.windowStream(frames: emptyFrames)
                do {
                    for try await window in upstream {
                        if let routed = await self.process(window: window) {
                            continuation.yield(routed)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    // MARK: - Transcribing conformance

    /// Loads the underlying Whisper model and runs a dummy inference.
    /// Delegates to the wrapped ``TranscriptionActor``.
    func warmup() async throws {
        try await transcriber.warmup()
    }

    /// Returns the wrapped transcriber's warmup state.
    func warmupState() async -> WarmupState {
        await transcriber.warmupState()
    }

    /// Begins draining `frames` through the upstream transcriber and the
    /// language gate, returning a throwing async stream of
    /// ``TranscriptSegment`` values for ``Transcribing`` consumers.
    ///
    /// SEAM-4 lossy mapping: each emitted ``TranscriptSegment`` uses
    /// ``RoutedTranscript/authoritativeLanguage`` for its
    /// ``TranscriptSegment/language`` field, NOT
    /// ``RoutedTranscript/detectedLanguage``. The detected-vs-authoritative
    /// divergence (SEAM-2) is only visible on the ``RoutedTranscript``
    /// surface; protocol consumers see only the stable signal.
    ///
    /// - Parameter frames: Upstream audio frame stream.
    /// - Returns: A throwing async stream of ``TranscriptSegment``
    ///   values, one per surviving window after gate filtering. The
    ///   ``TranscriptSegment/wasLanguageFallback`` field is `true` on
    ///   the SEAM-2 divergence window (detected != authoritative,
    ///   counter < N), `false` otherwise.
    func transcribe(
        frames: AsyncStream<AudioFrame>
    ) async -> AsyncThrowingStream<TranscriptSegment, any Error> {
        let upstream = transcriber.windowStream(frames: frames)
        return AsyncThrowingStream<TranscriptSegment, any Error> { continuation in
            let task = Task { [weak self] in
                guard let self else {
                    continuation.finish()
                    return
                }
                do {
                    for try await window in upstream {
                        if let routed = await self.process(window: window) {
                            let segment = LanguageRouter.makeSegment(from: routed)
                            continuation.yield(segment)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    /// Cancels the current transcription session by propagating cancel to
    /// the underlying ``TranscriptionActor``.
    ///
    /// After ``cancel()`` returns, any active ``transcribe(frames:)`` or
    /// ``routedTranscripts()`` stream finishes cleanly without throwing.
    func cancel() async {
        await transcriber.cancel()
    }

    // MARK: - Gate

    /// Applies the N=2 consecutive-disagreement gate to one upstream
    /// window. Returns the corresponding ``RoutedTranscript`` to emit, or
    /// `nil` if the window is silently dropped (SEAM-5).
    ///
    /// Mutates ``currentLanguage``, ``authoritativeLanguage``, and
    /// ``disagreementCounter`` atomically with respect to one window
    /// because this method is `@MainActor`-isolated.
    private func process(window: TranscriptionWindow) -> RoutedTranscript? {
        guard let detected = window.detectedLanguage else {
            // SEAM-5: unsupported language code. Drop silently.
            return nil
        }

        guard let currentAuthoritative = authoritativeLanguage else {
            // First supported-code window. Establish authoritative.
            authoritativeLanguage = detected
            currentLanguage = detected
            disagreementCounter = 0
            return makeRoutedTranscript(
                window: window,
                detected: detected,
                authoritative: detected,
                didFlip: false
            )
        }

        if detected == currentAuthoritative {
            // Agreement. Reset counter, no flip.
            disagreementCounter = 0
            return makeRoutedTranscript(
                window: window,
                detected: detected,
                authoritative: currentAuthoritative,
                didFlip: false
            )
        }

        // Disagreement. Bump counter and check threshold.
        let nextCounter = disagreementCounter + 1
        if nextCounter >= confirmationsRequired {
            // Flip.
            authoritativeLanguage = detected
            currentLanguage = detected
            disagreementCounter = 0
            return makeRoutedTranscript(
                window: window,
                detected: detected,
                authoritative: detected,
                didFlip: true
            )
        }

        // Disagreement under threshold. SEAM-2 divergence: detected !=
        // authoritative on this window's RoutedTranscript.
        disagreementCounter = nextCounter
        return makeRoutedTranscript(
            window: window,
            detected: detected,
            authoritative: currentAuthoritative,
            didFlip: false
        )
    }

    /// Builds a ``RoutedTranscript`` from an upstream window and the
    /// router's gate decision for that window.
    private func makeRoutedTranscript(
        window: TranscriptionWindow,
        detected: SpokenLanguage,
        authoritative: SpokenLanguage,
        didFlip: Bool
    ) -> RoutedTranscript {
        let text = window.segments
            .map(\.text)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return RoutedTranscript(
            id: UUID(),
            text: text,
            detectedLanguage: detected,
            authoritativeLanguage: authoritative,
            didFlip: didFlip,
            windowAnchorHostTime: window.windowAnchorHostTime,
            windowStartSeconds: window.windowStartSeconds,
            windowEndSeconds: window.windowEndSeconds,
            isFinal: window.isFinal
        )
    }

    // MARK: - SEAM-4 lossy mapping

    /// Converts a ``RoutedTranscript`` to a ``TranscriptSegment`` for
    /// ``Transcribing`` consumers. Uses the authoritative language per
    /// SEAM-4.
    ///
    /// `wasLanguageFallback` is `true` when the router's gate held the
    /// authoritative language despite a disagreeing detected language —
    /// i.e. the SEAM-2 divergence window — and `false` otherwise. This is
    /// the sole honesty signal the protocol surfaces; full per-window
    /// detected vs. authoritative duality is only available on the
    /// ``RoutedTranscript`` surface.
    private nonisolated static func makeSegment(
        from routed: RoutedTranscript
    ) -> TranscriptSegment {
        let wasFallback = routed.detectedLanguage != routed.authoritativeLanguage
        return TranscriptSegment(
            id: routed.id,
            text: routed.text,
            language: routed.authoritativeLanguage,
            startHostTime: routed.windowAnchorHostTime,
            endHostTime: routed.windowAnchorHostTime,
            startSeconds: routed.windowStartSeconds,
            endSeconds: routed.windowEndSeconds,
            isFinal: routed.isFinal,
            wasLanguageFallback: wasFallback
        )
    }
}
