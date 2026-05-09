//
//  WhisperModelVariant.swift
//  ArigatoAI
//
//  Created by Jose Castell on 2026/05/10.
//

import Foundation

/// The set of Whisper model variants Arigato AI is willing to load.
///
/// The raw value is the model identifier WhisperKit uses to resolve the
/// CoreML asset bundle on Hugging Face (the directory name under
/// `argmaxinc/whisperkit-coreml`). Pinning the identifier here keeps the
/// loader's behaviour predictable across WhisperKit releases — we do not
/// rely on `recommendedRemoteModels()` for MVP.
///
/// Phase 4 ships only the `large-v3-turbo` variant (Decision 2 in
/// `docs/PHASE_4_HANDOFF.md`). The turbo decoder trades a small accuracy
/// hit for substantially lower end-of-utterance latency, which is the
/// correct trade-off for live meeting captions even though Argmax's
/// front-page recommendation is the 626 MB non-turbo variant.
public nonisolated enum WhisperModelVariant: String, Sendable, Equatable, CaseIterable {
    /// `openai/whisper-large-v3` with the turbo decoder, 632 MB on disk.
    /// The exact raw value is the WhisperKit model identifier verified
    /// against `Sources/WhisperKit/Core/Models.swift` at the v1.0.0 tag.
    case largeV3Turbo = "openai_whisper-large-v3-v20240930_turbo_632MB"

    /// The variant Arigato AI loads by default when callers do not pass an
    /// explicit one to ``WhisperModelLoader/loadIfNeeded(variant:)``.
    public static var `default`: WhisperModelVariant {
        .largeV3Turbo
    }

    /// A short human-readable label suitable for diagnostic UI and logs.
    /// Does not localise — Arigato AI's diagnostic surface is English-only.
    public var displayName: String {
        switch self {
        case .largeV3Turbo:
            return "Whisper Large v3 Turbo (632MB)"
        }
    }
}
