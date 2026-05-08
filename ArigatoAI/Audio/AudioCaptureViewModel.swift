//
//  AudioCaptureViewModel.swift
//  ArigatoAI
//
//  Created by Jose Castell on 2026/05/09.
//

import Foundation
import Observation
import SwiftUI
import UIKit

/// Drives ``AudioCaptureView``. Owns an ``AudioCapturing`` (defaulting to
/// ``AudioCaptureActor``) and a ``MicrophonePermissionServicing``.
///
/// The view model is `@MainActor` because it publishes state for SwiftUI;
/// it talks to the actor via async hops. Public state mutates only from the
/// main actor, so SwiftUI observation is safe.
@Observable
@MainActor
public final class AudioCaptureViewModel {
    /// Current cached microphone authorization state.
    public private(set) var permissionStatus: MicrophonePermissionStatus = .notDetermined

    /// `true` while the audio engine is running.
    public private(set) var isRecording: Bool = false

    /// Latest normalized RMS level in `[0, 1]` for the VU meter.
    public private(set) var level: Float = 0

    /// Localized error message, if the most recent operation failed.
    public private(set) var errorMessage: String?

    private let capture: AudioCapturing
    private let permissionService: MicrophonePermissionServicing

    private var levelTask: Task<Void, Never>?
    private var drainTask: Task<Void, Never>?

    /// Creates a new view model.
    ///
    /// - Parameters:
    ///   - capture: The audio capture pipeline. Pass `nil` to use a fresh
    ///     ``AudioCaptureActor``.
    ///   - permissionService: The microphone permission service. Pass `nil`
    ///     to use the production ``MicrophonePermissionService``.
    public init(
        capture: AudioCapturing? = nil,
        permissionService: MicrophonePermissionServicing? = nil
    ) {
        self.capture = capture ?? AudioCaptureActor()
        self.permissionService = permissionService ?? MicrophonePermissionService()
    }

    /// Refreshes the cached permission state. Call this from
    /// `View.task { await vm.onAppear() }`.
    public func onAppear() async {
        permissionStatus = await permissionService.currentStatus()
    }

    /// Single entry point for the recording button. Branches on the current
    /// state machine: prompt when undetermined, start when granted, stop when
    /// already running.
    public func toggleRecording() async {
        errorMessage = nil

        if isRecording {
            await stopRecording()
            return
        }

        switch permissionStatus {
        case .notDetermined:
            permissionStatus = await permissionService.requestAccess()
            if permissionStatus == .granted {
                await startRecording()
            }
        case .granted:
            await startRecording()
        case .denied, .restricted:
            // No-op: the view shows the Settings affordance.
            break
        }
    }

    /// Opens the iOS Settings app on the app's settings pane so a user can
    /// toggle microphone access after a denial.
    public func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    // MARK: - Private helpers

    private func startRecording() async {
        do {
            try await capture.start()
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        let levels = await capture.levelStream()
        let frames = await capture.frameStream()

        levelTask = Task { [weak self] in
            for await value in levels {
                guard let self else { return }
                self.level = value
            }
        }

        drainTask = Task {
            // Phase 4 will replace this drain with the transcription pipeline.
            for await _ in frames {}
        }

        isRecording = true
    }

    private func stopRecording() async {
        levelTask?.cancel()
        drainTask?.cancel()
        levelTask = nil
        drainTask = nil

        await capture.stop()

        isRecording = false
        level = 0
    }
}
