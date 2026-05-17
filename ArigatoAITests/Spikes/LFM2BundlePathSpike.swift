//
//  LFM2BundlePathSpike.swift
//  ArigatoAITests/Spikes
//
//  PHASE 1 SECOND SPIKE — DISPOSABLE. Gets deleted in the B1.1 production
//  implementation commit. Do NOT add helpers, extract shared utilities,
//  or grow this file. It is a one-shot empirical probe.
//
//  Purpose
//  -------
//  Second empirical probe for B1.1, testing a DIFFERENT API surface than
//  the first spike (`LFM2LocalLoadSpike.swift`). New external research from
//  Liquid AI's official Quick Start Guide (docs.liquid.ai) indicates
//  `Leap.load(options: LiquidInferenceEngineOptions(bundlePath:))` is the
//  primary recommended pattern for bundle-as-resource loading.
//
//  Pre-flight Q1 (commit 398ed2c) concluded this API was "ExecuTorch-only"
//  based on field-name inference (`bundlePath` sounded ExecuTorch-shaped).
//  The first spike (commit 6512662) already invalidated one pre-flight
//  inference (manifest schema — `inference_type: "llama.cpp/text-to-text"`,
//  not `"gguf"`), so we re-empirically-verify Q1 against the real SDK.
//
//  The dispatching session pre-verified API existence by reading the
//  `.swiftinterface` for LeapSDK v0.9.4 — `Leap.load(options:)` exists,
//  `LiquidInferenceEngineOptions` exists with a public init that takes
//  `bundlePath: String` as its only required parameter. The deprecated
//  `Leap.load(url:)` overload's message reads `"Use load(options:)
//  instead"` — explicitly directing callers to this API. The call is
//  `throws`, NOT `async throws` (synchronous overload).
//
//  Chain under test:
//
//      Hugging Face direct download (URLSession)
//          → write LFM2-350M-ENJP-MT-Q5_K_M.gguf to tmp
//          → Leap.load(options: LiquidInferenceEngineOptions(
//                bundlePath: localGGUFURL.path))
//          → runner.createConversation(systemPrompt: "Translate to Japanese.")
//          → single short inference, assert at least one .chunk and a
//            terminal .complete
//
//  Cross-references
//  ----------------
//  - First spike (file://-manifest path):
//    `LFM2LocalLoadSpike.swift` (preserved as historical record of
//    `Leap.load(manifestURL:)` rejecting `file://` URLs).
//  - Pre-flight Q1 corrigendum: commit 16d9eff
//  - First spike's V3 closure: commit d3b621c
//
//  Gating
//  ------
//  This test is environment-variable-gated. It does NOT run in normal
//  full-suite verification. Same env-var name as the first spike so a
//  future cleanup pass can delete the directory in one shot:
//
//      RUN_NETWORK_SPIKES=1 xcodebuild test ...
//      or pass `testRunnerEnv: { "RUN_NETWORK_SPIKES": "1" }` via the
//      XcodeBuildMCP `test_sim` tool.
//
//  Rationale: downloads ~260 MB from HF, takes minutes, hits the
//  network — none of which belong in CI.
//
//  Verdict
//  -------
//  Printed at the end of the test body. One of:
//    SPIKE PASS / SPIKE PARTIAL / SPIKE FAIL / SPIKE BLOCKED / SPIKE INCONCLUSIVE
//

import Foundation
import LeapSDK
import Testing

/// One-shot empirical probe. Single self-contained Swift Testing
/// function, no helpers, no shared state. Deleted in B1.1 production.
@Test(
    "B1.1 second spike: HF download -> Leap.load(options: bundlePath:) -> infer",
    .enabled(if: ProcessInfo.processInfo.environment["RUN_NETWORK_SPIKES"] == "1"),
    .timeLimit(.minutes(10))
)
func lfm2BundlePathSpike() async throws {
    let startWallClock = Date()

    // -------- Workspace setup --------
    let workspaceRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("lfm2-bundlepath-spike-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(
        at: workspaceRoot,
        withIntermediateDirectories: true
    )
    print("[SPIKE] workspace: \(workspaceRoot.path)")

    // Defer cleanup so the simulator's tmp doesn't accumulate ~260 MB
    // per run. `try?` is acceptable here because cleanup-failure during
    // teardown should not mask the spike verdict.
    defer {
        try? FileManager.default.removeItem(at: workspaceRoot)
    }

    let ggufFilename = "LFM2-350M-ENJP-MT-Q5_K_M.gguf"
    let ggufURL = workspaceRoot.appendingPathComponent(ggufFilename)

    // -------- Step 1: Download GGUF from Hugging Face --------
    // Pattern per first spike's verified-working pattern. Public repo,
    // no auth required. URLSession follows the 302 to Xet CDN
    // automatically.
    let hfSourceURLString = "https://huggingface.co/LiquidAI/LFM2-350M-ENJP-MT-GGUF/resolve/main/\(ggufFilename)?download=true"
    guard let hfSourceURL = URL(string: hfSourceURLString) else {
        print("SPIKE INCONCLUSIVE: malformed HF source URL: \(hfSourceURLString)")
        Issue.record("Malformed HF source URL")
        return
    }

    print("[SPIKE] downloading \(hfSourceURL.absoluteString)")
    let downloadStart = Date()
    let downloadedLocation: URL
    let downloadResponse: URLResponse
    do {
        (downloadedLocation, downloadResponse) = try await URLSession.shared.download(from: hfSourceURL)
    } catch {
        print("SPIKE INCONCLUSIVE: HF download threw: \(error)")
        Issue.record("HF download failed: \(error)")
        return
    }

    if let http = downloadResponse as? HTTPURLResponse, !(200 ..< 300).contains(http.statusCode) {
        print("SPIKE INCONCLUSIVE: HF download HTTP \(http.statusCode); final URL: \(http.url?.absoluteString ?? "<nil>")")
        Issue.record("HF download non-2xx: \(http.statusCode)")
        return
    }

    do {
        // URLSession.download writes to a tmp file owned by the session;
        // move it into our workspace so the file outlives this call site.
        try FileManager.default.moveItem(at: downloadedLocation, to: ggufURL)
    } catch {
        print("SPIKE INCONCLUSIVE: could not move downloaded GGUF into workspace: \(error)")
        Issue.record("Move failed: \(error)")
        return
    }

    let downloadedSize: Int64
    do {
        let attrs = try FileManager.default.attributesOfItem(atPath: ggufURL.path)
        if let size = attrs[.size] as? Int64 {
            downloadedSize = size
        } else if let sizeNumber = attrs[.size] as? NSNumber {
            downloadedSize = sizeNumber.int64Value
        } else {
            print("SPIKE INCONCLUSIVE: could not read downloaded file size")
            Issue.record("Missing size attribute")
            return
        }
    } catch {
        print("SPIKE INCONCLUSIVE: attributesOfItem failed: \(error)")
        Issue.record("attributesOfItem failed: \(error)")
        return
    }

    let downloadElapsed = Date().timeIntervalSince(downloadStart)
    print("[SPIKE] downloaded \(downloadedSize) bytes in \(String(format: "%.1f", downloadElapsed))s")

    // Expected ~260,374,304 bytes per HF API listing. Allow a generous
    // 1% tolerance in either direction to absorb HF metadata drift.
    let expectedBytes: Int64 = 260_374_304
    let tolerance: Int64 = expectedBytes / 100
    if abs(downloadedSize - expectedBytes) > tolerance {
        print("SPIKE INCONCLUSIVE: GGUF size \(downloadedSize) outside expected ~\(expectedBytes) (±1%). Possible HF file change.")
        Issue.record("Unexpected GGUF size: \(downloadedSize)")
        return
    }

    // -------- Step 2: Leap.load(options: LiquidInferenceEngineOptions(bundlePath:)) --------
    // `bundlePath` is `String`, not `URL` (verified against .swiftinterface
    // by dispatching session). Use `URL.path` to convert.
    // The call is synchronous (`throws`, NOT `async throws`).
    print("[SPIKE] constructing LiquidInferenceEngineOptions(bundlePath: \(ggufURL.path))")
    let options = LiquidInferenceEngineOptions(bundlePath: ggufURL.path)
    print("[SPIKE] options constructed. Attempting Leap.load(options:)")

    let loadStart = Date()
    let runner: any ModelRunner
    do {
        runner = try Leap.load(options: options)
    } catch {
        let loadElapsed = Date().timeIntervalSince(loadStart)
        let totalElapsed = Date().timeIntervalSince(startWallClock)
        print("[SPIKE] Leap.load(options:) threw after \(String(format: "%.1f", loadElapsed))s")
        print("[SPIKE] error type: \(type(of: error))")
        print("[SPIKE] error: \(error)")
        print("[SPIKE] error reflecting: \(String(reflecting: error))")
        let nsError = error as NSError
        print("[SPIKE] NSError domain: \(nsError.domain)  code: \(nsError.code)")
        print("[SPIKE] NSError userInfo: \(nsError.userInfo)")
        print("[SPIKE] localizedDescription: \(error.localizedDescription)")
        print("SPIKE FAIL: Leap.load(options:) rejects GGUF with \(error). bundlePath requires .bundle format. Path requires format migration. HF download took \(String(format: "%.1f", downloadElapsed))s. Total wall-clock \(String(format: "%.1f", totalElapsed))s.")
        Issue.record("Leap.load(options:) rejected GGUF via bundlePath: \(error)")
        return
    }
    let loadElapsed = Date().timeIntervalSince(loadStart)
    print("[SPIKE] Leap.load(options:) succeeded in \(String(format: "%.1f", loadElapsed))s")

    // -------- Step 3: createConversation + single inference --------
    // System prompt MUST be one of the two exact strings from the
    // leap-sdk SKILL.md. Using EN->JA here ("Translate to Japanese.")
    // matched against an English user turn.
    let conversation = runner.createConversation(systemPrompt: "Translate to Japanese.")
    let userMessage = ChatMessage(role: .user, content: [.text("Hello.")])
    let inferenceStart = Date()
    // `maxOutputTokens` is the v0.9.4 field name (the leap-sdk SKILL.md
    // example uses `maxTokens` which does not exist in this SDK
    // version — first spike's confirmed finding).
    let stream: AsyncThrowingStream<MessageResponse, any Error> = conversation.generateResponse(
        message: userMessage,
        generationOptions: GenerationOptions(
            temperature: 0.3,
            minP: 0.15,
            repetitionPenalty: 1.05,
            maxOutputTokens: 256
        )
    )

    var observedChunkCount = 0
    var observedComplete = false
    var assembledChunks = ""
    do {
        for try await response in stream {
            switch response {
            case let .chunk(text):
                observedChunkCount += 1
                assembledChunks += text
            case .reasoningChunk:
                continue
            case .audioSample:
                continue
            case .complete:
                observedComplete = true
            case .functionCall:
                continue
            @unknown default:
                continue
            }
        }
    } catch {
        let inferenceElapsed = Date().timeIntervalSince(inferenceStart)
        let totalElapsed = Date().timeIntervalSince(startWallClock)
        print("[SPIKE] inference stream threw after \(String(format: "%.1f", inferenceElapsed))s: \(error)")
        print("SPIKE PARTIAL: Leap.load(options:) loads GGUF but warm/infer fails with \(error). Path viable but needs investigation. HF: \(String(format: "%.1f", downloadElapsed))s, load: \(String(format: "%.1f", loadElapsed))s, infer-attempt: \(String(format: "%.1f", inferenceElapsed))s. Total: \(String(format: "%.1f", totalElapsed))s. Chunks observed before failure: \(observedChunkCount).")
        Issue.record("Inference stream threw: \(error)")
        return
    }
    let inferenceElapsed = Date().timeIntervalSince(inferenceStart)
    print("[SPIKE] inference: \(observedChunkCount) chunks, complete=\(observedComplete), elapsed=\(String(format: "%.1f", inferenceElapsed))s")
    print("[SPIKE] assembled output: \(assembledChunks)")

    // -------- Step 4: Verdict --------
    #expect(observedChunkCount >= 1, "Expected at least one .chunk from the stream")
    #expect(observedComplete, "Expected a terminal .complete from the stream")

    let totalElapsed = Date().timeIntervalSince(startWallClock)
    if observedChunkCount >= 1, observedComplete {
        print("SPIKE PASS: Leap.load(options:) accepts GGUF via bundlePath. Full chain HF-download → bundlePath → load → warm → infer succeeded. HF: \(String(format: "%.1f", downloadElapsed))s, load: \(String(format: "%.1f", loadElapsed))s, infer: \(String(format: "%.1f", inferenceElapsed))s. Total: \(String(format: "%.1f", totalElapsed))s. Chunks=\(observedChunkCount).")
    } else {
        print("SPIKE PARTIAL: Leap.load(options:) loads GGUF but warm/infer yielded chunks=\(observedChunkCount) complete=\(observedComplete). HF: \(String(format: "%.1f", downloadElapsed))s, load: \(String(format: "%.1f", loadElapsed))s, infer: \(String(format: "%.1f", inferenceElapsed))s.")
    }
}
