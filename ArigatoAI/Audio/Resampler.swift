//
//  Resampler.swift
//  ArigatoAI
//
//  Created by Jose Castell on 2026/05/09.
//

@preconcurrency import AVFAudio
import Foundation

/// Resamples a source `AVAudioPCMBuffer` into a flat `[Float]` matching the
/// caller's target format using the supplied `AVAudioConverter`.
///
/// The work is wrapped in `autoreleasepool { }` because
/// `AVAudioConverter.convert(to:error:withInputFrom:)` is documented to
/// over-retain its output buffer (Apple Developer Forums thread 727705).
/// Without the pool, memory grows unboundedly across multi-hour sessions.
///
/// - Parameters:
///   - source: The input PCM buffer captured from the microphone tap.
///   - converter: A pre-constructed converter. The caller owns its lifecycle
///     so it can be reused across many calls.
///   - targetFormat: The format to resample into (typically 16 kHz mono float32).
/// - Returns: A flat `Float` array containing the resampled mono PCM samples.
/// - Throws: ``AudioCaptureError/converterCreationFailed`` when the system
///   cannot allocate an output buffer, or any underlying conversion error.
public nonisolated func resample(
    _ source: AVAudioPCMBuffer,
    using converter: AVAudioConverter,
    targetFormat: AVAudioFormat
) throws -> [Float] {
    try autoreleasepool {
        // Estimate output capacity: ratio of sample rates × source frames,
        // padded by 1 frame to absorb fractional remainders.
        let ratio = targetFormat.sampleRate / source.format.sampleRate
        let estimatedCapacity = AVAudioFrameCount(Double(source.frameLength) * ratio) + 1

        guard let output = AVAudioPCMBuffer(
            pcmFormat: targetFormat,
            frameCapacity: estimatedCapacity
        ) else {
            throw AudioCaptureError.converterCreationFailed
        }

        var consumed = false
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) { _, inputStatus in
            if consumed {
                inputStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            inputStatus.pointee = .haveData
            return source
        }

        if let conversionError {
            throw conversionError
        }

        // .haveData and .inputRanOut are both expected outcomes when the
        // entire input was consumed; .endOfStream is unexpected but harmless
        // here. Treat .error as a hard failure.
        if status == .error {
            throw AudioCaptureError.converterCreationFailed
        }

        let frameLength = Int(output.frameLength)
        guard frameLength > 0, let channelData = output.floatChannelData else {
            return []
        }

        let pointer = channelData[0]
        return Array(UnsafeBufferPointer(start: pointer, count: frameLength))
    }
}
