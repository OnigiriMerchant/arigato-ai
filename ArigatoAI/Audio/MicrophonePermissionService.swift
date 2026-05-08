//
//  MicrophonePermissionService.swift
//  ArigatoAI
//
//  Created by Jose Castell on 2026/05/09.
//

import AVFAudio
import Foundation

/// Abstracts microphone-permission queries and prompts so view models can be
/// driven by fakes during tests and by the real system service in production.
///
/// All methods are safe to call from any actor; conforming types must be
/// `Sendable`. The concrete iOS implementation, ``MicrophonePermissionService``,
/// is `@MainActor`-isolated because it talks to `AVAudioApplication`, which
/// surfaces UI prompts.
public protocol MicrophonePermissionServicing: Sendable {
    /// Returns the cached system permission state without prompting the user.
    func currentStatus() async -> MicrophonePermissionStatus

    /// Returns the current state, prompting the user the first time only.
    ///
    /// If the user has already denied access, this returns the cached
    /// ``MicrophonePermissionStatus/denied`` value without re-prompting,
    /// because iOS will not show the prompt twice. Callers should route
    /// the user to Settings in that case.
    func requestAccess() async -> MicrophonePermissionStatus
}

/// Production microphone-permission service backed by `AVAudioApplication`.
///
/// This wrapper uses `AVAudioApplication.shared.recordPermission` for the
/// synchronous query and the iOS 17+ class method
/// `AVAudioApplication.requestRecordPermission()` for the async prompt.
/// The deprecated `AVAudioSession.requestRecordPermission(_:)` callback
/// API is intentionally avoided.
@MainActor
public final class MicrophonePermissionService: MicrophonePermissionServicing {
    /// Creates a new service. There is no per-instance state; multiple
    /// instances behave identically.
    public init() {}

    /// Returns the current cached microphone permission state.
    public func currentStatus() -> MicrophonePermissionStatus {
        MicrophonePermissionStatus(AVAudioApplication.shared.recordPermission)
    }

    /// Requests microphone access if undetermined, otherwise returns the
    /// cached state without re-prompting.
    public func requestAccess() async -> MicrophonePermissionStatus {
        let initialStatus = currentStatus()
        switch initialStatus {
        case .granted, .denied, .restricted:
            return initialStatus
        case .notDetermined:
            _ = await AVAudioApplication.requestRecordPermission()
            return currentStatus()
        }
    }
}
