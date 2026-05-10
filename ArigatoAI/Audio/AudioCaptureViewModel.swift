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
/// ``AudioCaptureActor``), a ``MicrophonePermissionServicing``, and an
/// optional ``LanguageRouter`` for the Phase-4 transcription pipeline.
///
/// The view model is `@MainActor` because it publishes state for SwiftUI;
/// it talks to the actor via async hops. Public state mutates only from the
/// main actor, so SwiftUI observation is safe.
///
/// ## Frame-consumption modes
///
/// Two modes are supported:
///
/// 1. **Phase-3 fallback** (`router == nil`). Frames are drained with a
///    no-op `for await _ in frames {}` so the upstream `AsyncStream`
///    keeps flowing without backpressure. Used by tests and any caller
///    that has not yet wired a router. No transcription occurs.
/// 2. **Phase-4 router pipeline** (`router != nil`). Frames are routed
///    through ``LanguageRouter/transcribe(frames:)``; routed history
///    accumulates on the router's ``LanguageRouter/routedHistory``
///    surface. The view model only drains the returned segment stream
///    to keep the pipeline flowing — it does not retain segments.
///    ``LanguageRouter/routedHistory`` is the source of truth for UI
///    bindings.
///
/// ## Scheduling assumption (Concurrency design discipline)
///
/// When a router is injected, this view model assumes
/// ``LanguageRouter/transcribe(frames:)`` finishes its returned stream
/// within bounded time after ``LanguageRouter/cancel()`` is awaited (the
/// LanguageRouter / TranscriptionActor C29 propagation contract). The
/// view model awaits `router.cancel()` before `capture.stop()` in
/// ``stopRecording()`` so the router's session ends before the upstream
/// frame stream finishes, matching the documented C29 ordering.
///
/// **Violation behaviour.** If the segment stream does not finish after
/// `cancel()` (a contract violation upstream), `drainTask?.cancel()` is
/// the safety net: the cooperative cancellation point inside the
/// router's `for try await` loop will exit promptly. Segments published
/// before `cancel()` may still appear in
/// ``LanguageRouter/routedHistory`` and that is intentional — the
/// router preserves history across cancellation; only
/// ``LanguageRouter/resetSession()`` clears it.
///
/// **Violation test.** ``AudioCaptureViewModelTests`` test **D3-T3**
/// (`stopRecording_withRouter_underBurstUpstream_finishesCleanly`)
/// drives a greedy upstream — yielding many frames synchronously into
/// the stream before calling `stopRecording()` — and asserts clean
/// shutdown (`isRecording == false`, no errorMessage, drain task
/// finished within a bounded wait).
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
    private let router: LanguageRouter?

    private var levelTask: Task<Void, Never>?
    private var drainTask: Task<Void, Never>?

    /// Creates a new view model.
    ///
    /// - Parameters:
    ///   - capture: The audio capture pipeline. Pass `nil` to use a fresh
    ///     ``AudioCaptureActor``.
    ///   - permissionService: The microphone permission service. Pass `nil`
    ///     to use the production ``MicrophonePermissionService``.
    ///   - router: Optional ``LanguageRouter`` driving the Phase-4
    ///     transcription pipeline. When non-`nil`, audio frames are
    ///     drained through ``LanguageRouter/transcribe(frames:)`` and
    ///     routed history accumulates on the router. When `nil`, frames
    ///     are drained as a no-op (Phase-3 mode). Defaults to `nil`;
    ///     production wire-up at the UI layer (Step 5) injects the
    ///     bootstrapper's shared router. The optional-then-required
    ///     cleanup is tracked in V3 entry #37.
    init(
        capture: AudioCapturing? = nil,
        permissionService: MicrophonePermissionServicing? = nil,
        router: LanguageRouter? = nil
    ) {
        self.capture = capture ?? AudioCaptureActor()
        self.permissionService = permissionService ?? MicrophonePermissionService()
        self.router = router
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

        if let router {
            // Phase-4 mode: drain frames through the language router. The
            // view model only iterates the segment stream to keep the
            // pipeline flowing; routed history accumulates on the
            // router's @Observable surface, which UI binds to directly.
            let segmentStream = await router.transcribe(frames: frames)
            drainTask = Task { [weak self] in
                do {
                    for try await _ in segmentStream {}
                } catch {
                    self?.handleTranscriptionError(error)
                }
            }
        } else {
            // Phase-3 fallback: no transcription wired. Drain to keep the
            // upstream stream from blocking on backpressure.
            drainTask = Task {
                for await _ in frames {}
            }
        }

        isRecording = true
    }

    private func stopRecording() async {
        // Cancel the router's session BEFORE stopping the capture engine.
        // This honours the C29 propagation contract: the router finishes
        // its segment stream cleanly when its upstream transcriber's
        // session is cancelled, which lets the drain task exit before
        // the frame stream goes away. drainTask?.cancel() below is the
        // safety net.
        await router?.cancel()

        levelTask?.cancel()
        drainTask?.cancel()
        levelTask = nil
        drainTask = nil

        await capture.stop()

        isRecording = false
        level = 0
    }

    /// Publishes a user-facing error message when the router pipeline
    /// throws. ``TranscriptionError`` values render their
    /// `LocalizedError.errorDescription`; non-typed errors fall back to
    /// a stringified description.
    private func handleTranscriptionError(_ error: any Error) {
        if let typed = error as? TranscriptionError {
            errorMessage = typed.errorDescription ?? "Transcription failed: \(typed)"
        } else {
            errorMessage = "Transcription failed: \(error)"
        }
    }
}
