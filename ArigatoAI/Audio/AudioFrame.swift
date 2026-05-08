//
//  AudioFrame.swift
//  ArigatoAI
//
//  Created by Jose Castell on 2026/05/09.
//

import Foundation

/// A single chunk of resampled microphone audio ready to be fed to the
/// transcription pipeline.
///
/// `AudioFrame` is the unit of work that flows from
/// ``AudioCaptureActor`` to downstream consumers via `AsyncStream<AudioFrame>`.
///
/// Invariants:
/// - ``samples`` is interleaved-mono PCM `Float32` in the range `[-1.0, 1.0]`.
/// - The sample rate is **16,000 Hz** (WhisperKit's required input format).
/// - There is exactly one channel.
/// - ``frameCount`` equals ``samples``.count.
/// - ``hostTime`` is the host time of the first sample in the chunk, in
///   mach absolute units, suitable for aligning with other host-time clocks.
public nonisolated struct AudioFrame: Sendable, Equatable {
    /// 16 kHz mono float32 samples in `[-1.0, 1.0]`.
    public let samples: [Float]

    /// Mach host time of the first sample in this chunk.
    public let hostTime: UInt64

    /// Number of frames in this chunk; equal to `samples.count`.
    public let frameCount: Int

    /// Creates a new audio frame.
    ///
    /// - Parameters:
    ///   - samples: 16 kHz mono float32 PCM samples.
    ///   - hostTime: Mach host time of the first sample.
    ///   - frameCount: Sample count, which must equal `samples.count`.
    public init(samples: [Float], hostTime: UInt64, frameCount: Int) {
        self.samples = samples
        self.hostTime = hostTime
        self.frameCount = frameCount
    }
}
