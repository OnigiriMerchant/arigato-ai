//
//  RoutedTranscript.swift
//  ArigatoAI
//
//  Created by Jose Castell on 2026/05/10.
//

import Foundation

/// One ``TranscriptionWindow`` after passing through ``LanguageRouter``'s
/// consecutive-window disagreement gate.
///
/// `RoutedTranscript` is the unit of work the router emits for the
/// transcript-log surface (SEAM-1). It wraps the raw window with three
/// language-related fields so downstream consumers can choose between the
/// honest signal (``detectedLanguage``: what Whisper said for THIS window)
/// and the stable signal (``authoritativeLanguage``: what the router
/// believes after N=2 gating).
///
/// ## Group D bind targets (read this first)
///
/// - **Per-line transcript text styling**: bind ``detectedLanguage``
///   (honesty — show what was actually heard for this window).
/// - **Persistent language indicator chrome**: bind
///   ``authoritativeLanguage`` (or ``LanguageRouter/currentLanguage``
///   directly) — stability over momentary noise.
/// - **Translation routing** (Phase 5, downstream of router):
///   ``authoritativeLanguage`` — stable signal only.
///
/// Picking the wrong field surfaces as a one-window UI flicker during a
/// real language transition (the SEAM-2 contract below). Read the seam
/// detail before deciding.
///
/// **SEAM-2 (locked).** ``detectedLanguage`` and ``authoritativeLanguage``
/// DIVERGE by exactly one window during a language transition. When the
/// gate observes the first disagreement (counter = 1, below the N=2
/// confirmation threshold), this window's ``detectedLanguage`` is the new
/// language while ``authoritativeLanguage`` is still the old one. That
/// divergence is the contract — encoded in the C26 test, not a bug. UI
/// chrome should bind to ``authoritativeLanguage`` (or
/// ``LanguageRouter/currentLanguage`` directly); diagnostic / honesty
/// surfaces may consult ``detectedLanguage``.
///
/// **SEAM-3 (locked).** ``didFlip`` is `true` on exactly the window where
/// the gate trips (i.e. where ``authoritativeLanguage`` changes). It lives
/// on the window itself rather than on a separate event stream; Phase 7
/// may extract a flip-event stream if UX needs animation, but deciding now
/// is premature.
///
/// `nonisolated` is applied explicitly because the project sets
/// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`. The router is
/// `@MainActor`, but the value type itself can cross actor boundaries
/// when needed (it is `Sendable` by inference).
nonisolated struct RoutedTranscript: Equatable, Identifiable {
    /// Stable identity for SwiftUI / log-list rendering. A fresh `UUID`
    /// is assigned per emission; the router does not de-duplicate.
    let id: UUID

    /// Concatenated text from the underlying window's segments. The
    /// router preserves segment order and joins on a single space; empty
    /// segments are filtered out before joining.
    let text: String

    /// The language Whisper reported for this window after parsing the
    /// raw tag through ``SpokenLanguage/init(whisperCode:)``. Non-optional
    /// here because windows with unsupported (nil) codes are dropped at
    /// the router (SEAM-5) and never produce a `RoutedTranscript`.
    let detectedLanguage: SpokenLanguage

    /// The language the router believes is authoritative after applying
    /// N=2 consecutive-window disagreement gating. Equal to
    /// ``detectedLanguage`` except during a transition where the gate has
    /// observed the first disagreement but not yet flipped (SEAM-2
    /// divergence).
    let authoritativeLanguage: SpokenLanguage

    /// `true` on exactly the window where the gate trips (i.e. where
    /// ``authoritativeLanguage`` changes for this window relative to the
    /// previous emission). `false` everywhere else, including the first
    /// supported-code window after a session begins.
    let didFlip: Bool

    /// Mach host time of the first sample of the underlying window's
    /// audio array. Same clock as ``AudioFrame/hostTime``. Round-tripped
    /// from ``TranscriptionWindow/windowAnchorHostTime`` verbatim.
    let windowAnchorHostTime: UInt64

    /// Seconds offset of the first sample, measured from the start of
    /// the recording session. Round-tripped from
    /// ``TranscriptionWindow/windowStartSeconds``.
    let windowStartSeconds: Double

    /// Seconds offset of the last sample, measured the same way as
    /// ``windowStartSeconds``. Round-tripped from
    /// ``TranscriptionWindow/windowEndSeconds``.
    let windowEndSeconds: Double

    /// `false` for steady-state hops; `true` for the end-of-stream flush
    /// emitted when the upstream ``TranscriptionActor`` produces an
    /// `isFinal: true` window.
    let isFinal: Bool
}
