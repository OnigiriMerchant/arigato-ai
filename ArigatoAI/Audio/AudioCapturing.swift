//
//  AudioCapturing.swift
//  ArigatoAI
//
//  Created by Jose Castell on 2026/05/09.
//

import Foundation

/// Minimal protocol describing the audio-capture surface the view model
/// depends on. Conform a fake to this protocol in tests to drive the view
/// model without booting a real `AVAudioEngine`.
public protocol AudioCapturing: Sendable {
    /// Starts capture. Throws when the session, tap, or engine fail to start.
    func start() async throws

    /// Stops capture and finishes any in-flight streams.
    func stop() async

    /// Returns a fresh `AsyncStream` of audio frames for the current capture
    /// cycle. Must be called once per ``start()`` because ``stop()`` finishes
    /// the previous continuation.
    func frameStream() async -> AsyncStream<AudioFrame>

    /// Returns a fresh `AsyncStream` of normalized levels in `[0, 1]`.
    func levelStream() async -> AsyncStream<Float>
}

extension AudioCaptureActor: AudioCapturing {}
