//
//  AudioCaptureView.swift
//  ArigatoAI
//
//  Created by Jose Castell on 2026/05/09.
//

import SwiftUI

/// Microphone capture surface for Phase 3. Renders a record button and a
/// VU meter, and handles the four permission states (notDetermined, granted,
/// denied, restricted).
///
/// The view is intentionally minimal: Phase 4 will replace it with the live
/// caption surface; this build is for verifying the audio pipeline.
public struct AudioCaptureView: View {
    @State private var viewModel: AudioCaptureViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Creates a view bound to the supplied view model. Pass `nil` to build
    /// a production view model on the main actor.
    public init(viewModel: AudioCaptureViewModel? = nil) {
        _viewModel = State(initialValue: viewModel ?? AudioCaptureViewModel())
    }

    public var body: some View {
        VStack(spacing: 32) {
            header

            Spacer()

            content

            Spacer()

            footer
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.surfaceBackground)
        .task {
            await viewModel.onAppear()
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Arigato AI")
                .font(.title2)
                .fontWeight(.semibold)
            Text("Microphone check")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.permissionStatus {
        case .notDetermined:
            notDeterminedContent
        case .granted:
            grantedContent
        case .denied:
            deniedContent
        case .restricted:
            restrictedContent
        }
    }

    private var notDeterminedContent: some View {
        VStack(spacing: 20) {
            Text("Microphone access")
                .font(.title3.weight(.semibold))
            Text("Arigato AI uses your microphone to transcribe and translate meeting audio entirely on your device.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button("Allow microphone") {
                Task { await viewModel.toggleRecording() }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(.horizontal, 32)
    }

    private var grantedContent: some View {
        VStack(spacing: 24) {
            VUMeter(level: viewModel.level)
                .frame(height: 12)
                .padding(.horizontal, 8)

            RecordButton(
                isRecording: viewModel.isRecording,
                reduceMotion: reduceMotion
            ) {
                Task { await viewModel.toggleRecording() }
            }

            if let message = viewModel.errorMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
            }
        }
    }

    private var deniedContent: some View {
        VStack(spacing: 16) {
            Text("Microphone access denied")
                .font(.headline)
            Text("Arigato AI needs the microphone to transcribe and translate your meetings on-device. You can enable it in Settings.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
            Button("Open Settings") {
                viewModel.openSettings()
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var restrictedContent: some View {
        VStack(spacing: 16) {
            Text("Microphone unavailable")
                .font(.headline)
            Text("Microphone access is restricted on this device. Check Screen Time or device-management settings.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
        }
    }

    private var footer: some View {
        Text("Audio never leaves your iPhone.")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .lineLimit(2)
            .minimumScaleFactor(0.9)
            .frame(maxWidth: .infinity, alignment: .center)
    }
}

// MARK: - Record button

private struct RecordButton: View {
    let isRecording: Bool
    let reduceMotion: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(isRecording ? Color.recordingActive : Color.meterTrack)
                    .frame(
                        width: isRecording ? 80 : 64,
                        height: isRecording ? 80 : 64
                    )

                Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                    .font(.system(size: isRecording ? 28 : 24, weight: .semibold))
                    .foregroundStyle(isRecording ? Color.white : Color.primary)
                    .symbolEffect(.pulse, options: .repeating, isActive: shouldPulse)
            }
        }
        .buttonStyle(.plain)
        .contentShape(Circle())
        .accessibilityLabel(isRecording ? "Stop recording" : "Start recording")
        .accessibilityAddTraits(.isButton)
    }

    private var shouldPulse: Bool {
        isRecording && !reduceMotion
    }
}

// MARK: - VU meter

private struct VUMeter: View {
    let level: Float

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.meterTrack)
                Capsule()
                    .fill(Color.recordingActive.opacity(0.85))
                    .frame(width: max(0, CGFloat(level) * proxy.size.width))
                    .animation(.easeOut(duration: 0.08), value: level)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Input level")
        .accessibilityValue("\(Int((level * 100).rounded())) percent")
    }
}

// MARK: - Previews

#Preview("Light — undetermined") {
    AudioCaptureView()
        .preferredColorScheme(.light)
}

#Preview("Dark — undetermined") {
    AudioCaptureView()
        .preferredColorScheme(.dark)
}

#Preview("Light — denied") {
    AudioCaptureView(viewModel: AudioCaptureViewModel.previewDenied())
        .preferredColorScheme(.light)
}

#Preview("Dark — denied") {
    AudioCaptureView(viewModel: AudioCaptureViewModel.previewDenied())
        .preferredColorScheme(.dark)
}

#Preview("Light — restricted") {
    AudioCaptureView(viewModel: AudioCaptureViewModel.previewRestricted())
        .preferredColorScheme(.light)
}

// MARK: - Preview helpers

private extension AudioCaptureViewModel {
    @MainActor
    static func previewDenied() -> AudioCaptureViewModel {
        AudioCaptureViewModel(
            capture: PreviewCapture(),
            permissionService: PreviewPermissionService(status: .denied)
        )
    }

    @MainActor
    static func previewRestricted() -> AudioCaptureViewModel {
        AudioCaptureViewModel(
            capture: PreviewCapture(),
            permissionService: PreviewPermissionService(status: .restricted)
        )
    }
}

private final class PreviewCapture: AudioCapturing, @unchecked Sendable {
    func start() async throws {}
    func stop() async {}
    func frameStream() async -> AsyncStream<AudioFrame> {
        AsyncStream { $0.finish() }
    }

    func levelStream() async -> AsyncStream<Float> {
        AsyncStream { $0.finish() }
    }
}

private final class PreviewPermissionService: MicrophonePermissionServicing, @unchecked Sendable {
    let status: MicrophonePermissionStatus
    init(status: MicrophonePermissionStatus) {
        self.status = status
    }

    func currentStatus() async -> MicrophonePermissionStatus {
        status
    }

    func requestAccess() async -> MicrophonePermissionStatus {
        status
    }
}
