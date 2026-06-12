//
//  WhisperDecodeOptionsTests.swift
//  ArigatoAITests
//
//  Created by Jose Castell on 2026/06/12.
//

@testable import ArigatoAI
import Testing
import WhisperKit

/// Contract tests for ``ArgmaxOSSWhisperClient/decodeOptions()`` — the
/// shared decode options every production transcription request uses.
///
/// Both flags are load-bearing and were silently wrong under WhisperKit
/// v1.0.0's defaults before this bundle:
///   - `skipSpecialTokens` controls whether `<|...|>` control tokens leak
///     into per-segment text (breaking `SentenceBuffer` boundary detection
///     and polluting the LFM2 translation input).
///   - `detectLanguage` controls whether `LanguageRouter` receives a real
///     per-window language prediction or WhisperKit's default forced-`en`
///     prefill.
///
/// These tests pin the factory's output so a future default change or an
/// accidental flag flip is caught at unit-test time rather than in a live
/// meeting.
@Suite("WhisperDecodeOptions")
struct WhisperDecodeOptionsTests {
    /// Asserts the factory requests per-segment special-token stripping, so
    /// the `<|...|>` control tokens never reach `SentenceBuffer`'s boundary
    /// detector or the LFM2 translator.
    @Test func decodeOptions_requestsSpecialTokenStripping() {
        let options = ArgmaxOSSWhisperClient.decodeOptions()

        #expect(options.skipSpecialTokens == true)
    }

    /// Asserts the factory requests the language-detection pass.
    ///
    /// `DecodingOptions.detectLanguage` is a **non-optional** `Bool` after
    /// init resolution (the init takes `Bool?` and resolves it as
    /// `detectLanguage ?? !usePrefillPrompt`). Passing `true` explicitly
    /// enables detection regardless of `usePrefillPrompt`, so we assert the
    /// resolved stored value is `true`.
    @Test func decodeOptions_requestsLanguageDetection() {
        let options = ArgmaxOSSWhisperClient.decodeOptions()

        #expect(options.detectLanguage == true)
    }
}
