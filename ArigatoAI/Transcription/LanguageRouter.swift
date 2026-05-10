//
//  LanguageRouter.swift
//  ArigatoAI
//
//  Created by Jose Castell on 2026/05/10.
//

import Foundation

/// Consumes ``TranscriptionWindow`` values from a ``TranscriptionActor``
/// and applies consecutive-window disagreement gating (Phase 4 Decision 5,
/// N=2) before re-emitting them as ``RoutedTranscript`` values appended to
/// ``routedHistory`` and as ``TranscriptSegment`` values for the
/// ``Transcribing`` protocol surface.
///
/// ## Surfaces
///
/// **SEAM-1.** ``routedHistory`` is the per-window history of
/// ``RoutedTranscript`` values that survived the gate. It is a
/// `@MainActor`-isolated `@Observable` snapshot array suitable for direct
/// SwiftUI binding by the transcript-log view. Each element carries both
/// the honest signal (``RoutedTranscript/detectedLanguage``) and the
/// stable signal (``RoutedTranscript/authoritativeLanguage``).
/// ``currentLanguage`` is the parallel `@Observable` property bound by UI
/// chrome (language indicator). Updates to ``routedHistory`` and
/// ``currentLanguage`` happen atomically under MainActor isolation:
/// SwiftUI consumers (also MainActor-isolated) observe both updates
/// within the same render tick.
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
///    ``RoutedTranscript`` is emitted, no entry is appended to
///    ``routedHistory``, the gate counter and authoritative language are
///    unchanged, and ``currentLanguage`` is unchanged.
///
/// 2. Else, if no authoritative language has been established yet (first
///    supported-code window): set authoritative = detected, set
///    ``currentLanguage`` = detected, reset counter to 0, append a
///    ``RoutedTranscript`` with ``RoutedTranscript/didFlip`` = `false`.
///
/// 3. Else, if detected == authoritative: reset counter to 0; append a
///    ``RoutedTranscript`` with detected = authoritative and
///    ``RoutedTranscript/didFlip`` = `false`.
///
/// 4. Else (detected != authoritative): increment counter. If counter
///    >= ``confirmationsRequired`` (= 2), flip — set authoritative =
///    detected, set ``currentLanguage`` = detected, reset counter to 0,
///    append a ``RoutedTranscript`` with detected = authoritative and
///    ``RoutedTranscript/didFlip`` = `true`. Otherwise append a
///    ``RoutedTranscript`` with detected != authoritative (the SEAM-2
///    divergence) and ``RoutedTranscript/didFlip`` = `false`.
///
/// ## Scheduling assumption (Concurrency design discipline)
///
/// The router's drain task consumes upstream ``TranscriptionWindow``
/// values on the MainActor, one at a time. Gate state mutations
/// (``currentLanguage``, the disagreement counter, the authoritative
/// language) and the corresponding ``routedHistory`` append happen
/// atomically with respect to one window because both are MainActor
/// isolated: the drain awaits one window, applies the state transition,
/// appends to ``routedHistory`` (if any), then awaits the next.
///
/// **Assumption.** Routed-transcript history mutation
/// (``routedHistory`` append) is atomic with ``currentLanguage`` mutation
/// under MainActor isolation. SwiftUI consumers (also MainActor-isolated)
/// observe both updates within the same render tick. Cross-actor readers
/// must hop to MainActor before reading either; mid-mutation observation
/// is impossible from any other actor. The router does NOT internally
/// queue windows — if the upstream
/// ``TranscriptionActor/windowStream(frames:)`` produces faster than the
/// MainActor hop can advance, AsyncStream's natural backpressure applies
/// and the upstream's bounded queue (contract C30) may drop oldest hops.
///
/// **Violation behaviour.** If a non-MainActor consumer attempts to read
/// ``routedHistory`` or ``currentLanguage`` without hopping, the read is
/// rejected at compile time by Swift 6 strict concurrency. A real
/// violation test for upstream-bursts-vs-MainActor-hop-pacing is tracked
/// in the V3 backlog ("LanguageRouter scheduling-assumption violation
/// test").
///
/// **Violation test.** ``LanguageRouterTests`` test **D1-T1**
/// (`router_routedHistory_pairsDetectedAndAuthoritative_perWindow`) locks
/// the per-window detected/authoritative pairing in ``routedHistory``,
/// confirming that the per-window append is atomic with the per-window
/// gate state transition. C29
/// (`router_cancel_propagatesToTranscriber`) covers mid-flight
/// cancellation as a separate scheduling-assumption violation.
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

    /// Per-window history of ``RoutedTranscript`` values that survived
    /// the gate, in upstream emission order. SEAM-1 surface — bound
    /// directly by the SwiftUI transcript log.
    ///
    /// Mutated only on the MainActor by ``process(window:)``; appended
    /// once per surviving window, atomically with the corresponding
    /// ``currentLanguage`` mutation. Windows with unsupported codes
    /// (SEAM-5) leave this array unchanged. Cleared by
    /// ``resetSession()``.
    private(set) var routedHistory: [RoutedTranscript] = []

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
                        if let routed = self.process(window: window) {
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
    /// After ``cancel()`` returns, any active ``transcribe(frames:)``
    /// stream finishes cleanly without throwing. ``routedHistory`` is
    /// preserved across cancellation; use ``resetSession()`` to clear
    /// it explicitly when starting a fresh session.
    func cancel() async {
        await transcriber.cancel()
    }

    // MARK: - Session reset

    /// Clears all router-owned session state — ``routedHistory``,
    /// ``currentLanguage``, the authoritative language, and the
    /// disagreement counter — returning the router to its
    /// pre-first-window state.
    ///
    /// Caller is responsible for awaiting ``cancel()`` first if they
    /// need draining-then-reset semantics; calling ``resetSession()``
    /// while ``transcribe(frames:)`` is still draining causes in-flight
    /// windows to reseed the gate from scratch and pre-reset history is
    /// gone. The expected sequence to fully reset between meetings is:
    ///
    /// ```
    /// await router.cancel()
    /// router.resetSession()
    /// ```
    func resetSession() {
        routedHistory.removeAll()
        currentLanguage = nil
        authoritativeLanguage = nil
        disagreementCounter = 0
    }

    // MARK: - Gate

    /// Applies the N=2 consecutive-disagreement gate to one upstream
    /// window. Returns the corresponding ``RoutedTranscript`` to emit, or
    /// `nil` if the window is silently dropped (SEAM-5). When non-nil,
    /// the returned value is also appended to ``routedHistory`` before
    /// this method returns.
    ///
    /// Mutates ``currentLanguage``, ``authoritativeLanguage``,
    /// ``disagreementCounter``, and ``routedHistory`` atomically with
    /// respect to one window because this method is
    /// `@MainActor`-isolated. The ``routedHistory`` append is the
    /// last mutation before return so any synchronous MainActor observer
    /// of ``routedHistory.last`` sees a fully-consistent gate state.
    private func process(window: TranscriptionWindow) -> RoutedTranscript? {
        guard let detected = window.detectedLanguage else {
            // SEAM-5: unsupported language code. Drop silently.
            // routedHistory is intentionally NOT mutated here.
            return nil
        }

        let routed: RoutedTranscript

        if let currentAuthoritative = authoritativeLanguage {
            if detected == currentAuthoritative {
                // Agreement. Reset counter, no flip.
                disagreementCounter = 0
                routed = makeRoutedTranscript(
                    window: window,
                    detected: detected,
                    authoritative: currentAuthoritative,
                    didFlip: false
                )
            } else {
                // Disagreement. Bump counter and check threshold.
                let nextCounter = disagreementCounter + 1
                if nextCounter >= confirmationsRequired {
                    // Flip.
                    authoritativeLanguage = detected
                    currentLanguage = detected
                    disagreementCounter = 0
                    routed = makeRoutedTranscript(
                        window: window,
                        detected: detected,
                        authoritative: detected,
                        didFlip: true
                    )
                } else {
                    // Disagreement under threshold. SEAM-2 divergence:
                    // detected != authoritative on this window's
                    // RoutedTranscript.
                    disagreementCounter = nextCounter
                    routed = makeRoutedTranscript(
                        window: window,
                        detected: detected,
                        authoritative: currentAuthoritative,
                        didFlip: false
                    )
                }
            }
        } else {
            // First supported-code window. Establish authoritative.
            authoritativeLanguage = detected
            currentLanguage = detected
            disagreementCounter = 0
            routed = makeRoutedTranscript(
                window: window,
                detected: detected,
                authoritative: detected,
                didFlip: false
            )
        }

        routedHistory.append(routed)
        return routed
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
