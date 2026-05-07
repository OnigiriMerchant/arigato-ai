---
name: whisperkit
description: Streaming audio capture and language-aware transcription with WhisperKit. Use whenever working on the audio pipeline, language detection, sentence chunking, or pause/resume logic.
---

> ⚠️ PACKAGE RENAME — Phase 4 alert
>
> As of May 1 2026, Argmax shipped argmax-oss-swift v1.0.0, which renamed the package from `WhisperKit` to `ArgmaxOSS`. Full Swift 6 Sendable support out of the box.
>
> When integrating this in Phase 4, use:
> - Package URL: https://github.com/argmaxinc/argmax-oss-swift (unchanged)
> - Product name: ArgmaxOSS (was: WhisperKit)
> - Import statement: `import ArgmaxOSS` (was: `import WhisperKit`)
>
> The general API surface is similar but verify against the v1.0.0 release notes when implementing.
> Detected by weekly upgrade survey routine — see issue #2 and issue #4.

# WhisperKit streaming integration

## Model recommendation
- `large-v3-turbo` — best quality/speed for our use case
- Stored in app sandbox after first download (~600MB)
- Supports both Japanese and English ASR with language auto-detection

## Initialization pattern
```swift
import WhisperKit

actor TranscriberEngine {
    private var whisper: WhisperKit?
    
    func warmup() async throws {
        guard whisper == nil else { return }
        whisper = try await WhisperKit(
            WhisperKitConfig(
                model: "large-v3-turbo",
                verbose: false,
                logLevel: .none
            )
        )
        // Pre-warm with dummy audio to avoid cold-start glitch
        // Generate 1s of silence and run a quick decode
        let silence = Array(repeating: Float(0.0), count: 16000)
        _ = try? await whisper?.transcribe(audioArray: silence)
    }
}
```

## Audio capture configuration
- Sample rate: **16,000 Hz mono** (WhisperKit's required input format)
- Buffer size: 4096 frames is a sane default
- AVAudioSession category: `.record`, mode: `.measurement`, options: `[.allowBluetooth]`

## Streaming with language auto-detection
```swift
let result = try await whisper.transcribe(
    audioArray: audioBuffer,
    decodeOptions: DecodingOptions(
        task: .transcribe,
        language: nil,  // auto-detect
        detectLanguage: true,
        temperatureFallbackCount: 0,
        usePrefillPrompt: true,
        skipSpecialTokens: true,
        withoutTimestamps: false
    )
)

for segment in result {
    let detectedLang = segment.language  // "ja" or "en"
    let confidence = segment.languageProbability ?? 0.0
    // Route to LFM2 with correct direction
}
```

## Language confidence threshold
Below 0.7 confidence, fall back to the previous segment's language. Real bilingual meetings have brief code-switches ("OK", "yes", "no") that confuse short-utterance language detection.

## Sentence-level chunking
LFM2 needs complete sentences. Don't translate per-word.
- Use Whisper's segment boundaries (which align with natural pauses)
- Or use VAD (Voice Activity Detection) to detect pause-of-N-ms
- Concatenate Whisper output until a sentence-ending punctuation appears (。 for JA, . ? ! for EN)

## Performance notes
- Whisper runs on Neural Engine via Core ML — extremely efficient
- Memory: ~1GB during inference
- Latency: 1-1.5s end-of-utterance to text on iPhone 17 Pro Max

## Common pitfalls
- Wrong sample rate (44.1kHz instead of 16kHz) silently produces gibberish — always resample
- Forgetting to release AudioEngine taps causes memory leaks over long sessions
- Running on main actor causes UI hitches — Whisper must run on background actor
