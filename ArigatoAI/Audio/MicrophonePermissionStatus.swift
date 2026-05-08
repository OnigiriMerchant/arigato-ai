//
//  MicrophonePermissionStatus.swift
//  ArigatoAI
//
//  Created by Jose Castell on 2026/05/09.
//

import AVFAudio
import Foundation

/// Represents the current microphone authorization state for Arigato AI.
///
/// This is a thin, ``Sendable`` mirror of `AVAudioApplication.RecordPermission`
/// that adds the explicit ``restricted`` case for parental / MDM-managed devices
/// (which Apple's enum models with `@unknown default` rather than a concrete case).
///
/// Use ``MicrophonePermissionStatus/init(_:)`` to convert from the system enum.
public nonisolated enum MicrophonePermissionStatus: Sendable, Equatable {
    /// The user has not yet been prompted for microphone access.
    case notDetermined
    /// The user has granted microphone access.
    case granted
    /// The user has explicitly denied microphone access.
    case denied
    /// Microphone access is restricted by parental controls or MDM policy,
    /// or the system reported an unrecognized record-permission case.
    case restricted
}

public nonisolated extension MicrophonePermissionStatus {
    /// Maps an `AVAudioApplication.RecordPermission` value to a
    /// ``MicrophonePermissionStatus``.
    ///
    /// - `.undetermined` becomes ``notDetermined``.
    /// - `.granted` becomes ``granted``.
    /// - `.denied` becomes ``denied``.
    /// - Any future case introduced by Apple is mapped to ``restricted`` so
    ///   the caller can degrade gracefully.
    ///
    /// - Parameter systemPermission: The value returned by
    ///   `AVAudioApplication.shared.recordPermission` or
    ///   `AVAudioApplication.requestRecordPermission()`.
    init(_ systemPermission: AVAudioApplication.recordPermission) {
        switch systemPermission {
        case .undetermined:
            self = .notDetermined
        case .granted:
            self = .granted
        case .denied:
            self = .denied
        @unknown default:
            self = .restricted
        }
    }
}
