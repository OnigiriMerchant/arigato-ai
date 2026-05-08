//
//  AudioCaptureError.swift
//  ArigatoAI
//
//  Created by Jose Castell on 2026/05/09.
//

import Foundation

/// Errors thrown by ``AudioCaptureActor`` while configuring or running the
/// microphone pipeline.
///
/// Underlying system errors are stringified rather than wrapped so the type
/// can be `Sendable` without leaking non-`Sendable` `NSError` references
/// into actor messages.
public enum AudioCaptureError: Error, Sendable, Equatable {
    /// Microphone permission has not been granted; capture cannot proceed.
    case permissionDenied
    /// Configuring the shared `AVAudioSession` failed.
    case sessionConfigurationFailed(String)
    /// Starting the underlying `AVAudioEngine` failed.
    case engineStartFailed(String)
    /// `AVAudioConverter` could not be constructed for the requested formats.
    case converterCreationFailed
    /// `start()` was called while the actor was already running.
    case alreadyRunning
    /// `stop()` was called while the actor was not running.
    case notRunning
}

extension AudioCaptureError: LocalizedError {
    /// Human-readable description suitable for logs and diagnostic UI.
    public var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Microphone permission denied."
        case let .sessionConfigurationFailed(detail):
            return "Audio session configuration failed: \(detail)"
        case let .engineStartFailed(detail):
            return "Audio engine failed to start: \(detail)"
        case .converterCreationFailed:
            return "Failed to create audio resampler."
        case .alreadyRunning:
            return "Audio capture is already running."
        case .notRunning:
            return "Audio capture is not running."
        }
    }
}
