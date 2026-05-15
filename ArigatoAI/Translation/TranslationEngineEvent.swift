//
//  TranslationEngineEvent.swift
//  ArigatoAI
//
//  Created by Jose Castell on 2026/05/15.
//

import Foundation

/// Internal seam event emitted by ``LFM2Engine/translate(userText:direction:)``.
///
/// The seam decouples the LEAP iOS SDK's ``LeapSDK.MessageResponse``
/// (which carries non-`Sendable` SDK payloads we do not surface to
/// callers) from the actor-facing translation pipeline. The production
/// adapter (``LFM2EngineAdapter``) maps each `MessageResponse` arriving
/// from `LeapSDK.Conversation.generateResponse(userTextMessage:...)`
/// onto the small enum below; tests construct values directly.
///
/// Two cases are surfaced: incremental token deltas via ``chunk(_:)``
/// and a terminal ``complete`` event. Other ``LeapSDK.MessageResponse``
/// cases (function-call payloads, telemetry stats, etc.) are
/// deliberately discarded — Group C only needs the streaming text
/// surface for sentence translation.
///
/// `Sendable` because both associated values are `String` (value type)
/// or absent. `Hashable` for cheap test equality assertions; the
/// conformance is auto-synthesized so no custom `==`/`hash(into:)` is
/// required.
public nonisolated enum TranslationEngineEvent: Sendable, Hashable {
    /// One incremental delta of generated text.
    ///
    /// The string carries only the new token(s) since the previous
    /// chunk — callers are responsible for accumulating across chunks
    /// if they want the full translation. The accumulator pattern is
    /// what ``TranslationActor`` will use when assembling each
    /// ``TranslatedSegment``.
    case chunk(String)

    /// Terminal event indicating the SDK has finished generating.
    ///
    /// Carries no payload — completion-stats from
    /// ``LeapSDK.MessageResponse/complete(_:)`` are intentionally
    /// dropped. Phase 6 diagnostics may revisit if per-call stats turn
    /// out to be load-bearing for the V3 "LFM2 prompt cache
    /// effectiveness benchmark".
    case complete
}
