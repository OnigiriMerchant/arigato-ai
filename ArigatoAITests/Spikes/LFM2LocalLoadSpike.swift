//
//  LFM2LocalLoadSpike.swift
//  ArigatoAITests/Spikes
//
//  PHASE 1 SPIKE — DISPOSABLE. Gets deleted in the B1.1 production
//  implementation commit. Do NOT add helpers, extract shared utilities,
//  or grow this file. It is a one-shot empirical probe.
//
//  Purpose
//  -------
//  Verify the single load-bearing unknown for B1.1 per
//  `docs/PHASE_5_B1_1_PRE_FLIGHT.md`:
//
//      Does `Leap.load(manifestURL:)` in LEAP SDK v0.9.4 accept a
//      `file://` URL pointing at a locally-constructed manifest JSON?
//
//  The pre-flight identified this as the only viable v0.9.4 chain that
//  avoids the broken LEAP-portal path:
//
//      Hugging Face direct download (URLSession)
//          → write LFM2-350M-ENJP-MT-Q5_K_M.gguf to tmp
//          → write a leap-format manifest JSON next to it
//          → `Leap.load(manifestURL: file://.../Q5_K_M.json)`
//          → `runner.createConversation(systemPrompt:)`
//          → single short inference, assert at least one `.chunk` and a
//            terminal `.complete`
//
//  If this PASSes, B1.1 production code can implement that chain. If it
//  FAILs (SDK rejects `file://`, or rewrites to `https://` and 404s),
//  the only remaining v0.9.4 paths are forking the SDK or waiting for
//  a future release; both require human gate.
//
//  Gating
//  ------
//  This test is environment-variable-gated. It does NOT run in normal
//  full-suite verification. To run:
//
//      RUN_NETWORK_SPIKES=1 xcodebuild test ...
//      or pass `testRunnerEnv: { "RUN_NETWORK_SPIKES": "1" }` via the
//      XcodeBuildMCP `test_sim` tool.
//
//  Rationale: downloads ~260 MB from HF, takes minutes, hits the
//  network — none of which belong in CI.
//
//  Manifest schema source
//  ----------------------
//  The exact field names and string values used by this spike are taken
//  from the maintainer-published manifest at:
//
//      https://huggingface.co/LiquidAI/LFM2-350M-ENJP-MT-GGUF/resolve/main/leap/Q5_K_M.json
//
//  Verified content (fetched 2026-05-17):
//
//      {
//        "inference_type": "llama.cpp/text-to-text",
//        "schema_version": "1.0.0",
//        "load_time_parameters": {
//          "model": "../LFM2-350M-ENJP-MT-Q5_K_M.gguf"
//        },
//        "generation_time_parameters": {
//          "sampling_parameters": {
//            "temperature": 0.3,
//            "min_p": 0.15,
//            "repetition_penalty": 1.05
//          }
//        }
//      }
//
//  This OVERRIDES the pre-flight Q3 example, which guessed
//  `inference_type: "gguf"` and `schema_version: "1"` — both incorrect.
//  Keys are snake_case in the published JSON (matching what the SDK's
//  decoder must consume).
//
//  This spike pins both files (manifest JSON + GGUF) into a single
//  temp subdirectory. The `model` path in the manifest is the bare
//  filename (`LFM2-350M-ENJP-MT-Q5_K_M.gguf`) — kept colocated with
//  the manifest so any relative-vs-absolute resolution debate is moot.
//
//  Verdict
//  -------
//  Printed at the end of the test body. One of:
//    SPIKE PASS / SPIKE FAIL / SPIKE INCONCLUSIVE
//

import Foundation
import LeapSDK
import Testing

/// One-shot empirical probe. Single self-contained Swift Testing
/// function, no helpers, no shared state. Deleted in B1.1 production.
@Test(
    "B1.1 spike: HF download -> local manifest -> Leap.load(file://) -> infer",
    .enabled(if: ProcessInfo.processInfo.environment["RUN_NETWORK_SPIKES"] == "1"),
    .timeLimit(.minutes(10))
)
func lfm2LocalLoadSpike() async throws {
    let startWallClock = Date()

    // -------- Workspace setup --------
    let workspaceRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("lfm2-spike-\(UUID().uuidString)", isDirectory: true)
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
    let manifestURL = workspaceRoot.appendingPathComponent("Q5_K_M.json")

    // -------- Step 1: Download GGUF from Hugging Face --------
    // Pattern per pre-flight Q5. Public repo, no auth required.
    // URLSession follows the 302 to Xet CDN automatically.
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

    // -------- Step 2: Construct manifest JSON --------
    // Schema verified against the maintainer-published manifest
    // (see file header). Keys are snake_case; values are EXACT strings
    // pulled from the live HF JSON. `model` is the bare filename
    // because the GGUF sits in the same directory as the manifest.
    let manifestJSON = """
    {
      "inference_type": "llama.cpp/text-to-text",
      "schema_version": "1.0.0",
      "load_time_parameters": {
        "model": "\(ggufFilename)"
      },
      "generation_time_parameters": {
        "sampling_parameters": {
          "temperature": 0.3,
          "min_p": 0.15,
          "repetition_penalty": 1.05
        }
      }
    }
    """

    do {
        try manifestJSON.write(to: manifestURL, atomically: true, encoding: .utf8)
    } catch {
        print("SPIKE INCONCLUSIVE: manifest write failed: \(error)")
        Issue.record("Manifest write failed: \(error)")
        return
    }
    print("[SPIKE] wrote manifest at \(manifestURL.absoluteString)")
    print("[SPIKE] manifest scheme: \(manifestURL.scheme ?? "<nil>")  isFileURL: \(manifestURL.isFileURL)")

    // -------- Step 3: Leap.load(manifestURL:) with file:// URL --------
    let loadStart = Date()
    let runner: any ModelRunner
    do {
        runner = try await Leap.load(
            manifestURL: manifestURL,
            options: nil,
            downloadProgressHandler: nil
        )
    } catch {
        let loadElapsed = Date().timeIntervalSince(loadStart)
        let totalElapsed = Date().timeIntervalSince(startWallClock)
        print("[SPIKE] Leap.load threw after \(String(format: "%.1f", loadElapsed))s")
        print("[SPIKE] error type: \(type(of: error))")
        print("[SPIKE] error: \(error)")
        if let nsError = error as NSError? {
            print("[SPIKE] NSError domain: \(nsError.domain)  code: \(nsError.code)")
            print("[SPIKE] NSError userInfo: \(nsError.userInfo)")
            if let failingURL = nsError.userInfo[NSURLErrorFailingURLErrorKey] as? URL {
                print("[SPIKE] SDK-attempted URL: \(failingURL.absoluteString)  scheme: \(failingURL.scheme ?? "<nil>")")
            }
            if let failingURLString = nsError.userInfo[NSURLErrorFailingURLStringErrorKey] as? String {
                print("[SPIKE] SDK-attempted URL string: \(failingURLString)")
            }
        }
        print("SPIKE FAIL: Leap.load(manifestURL:) rejected file:// URL after \(String(format: "%.1f", totalElapsed))s. Error: \(error). Production path requires SDK fork or future release.")
        Issue.record("Leap.load rejected file:// manifest URL: \(error)")
        return
    }
    let loadElapsed = Date().timeIntervalSince(loadStart)
    print("[SPIKE] Leap.load succeeded in \(String(format: "%.1f", loadElapsed))s")

    // -------- Step 4: createConversation + single inference --------
    // System prompt MUST be one of the two exact strings from the
    // leap-sdk SKILL.md. Using EN->JA here ("Translate to Japanese.")
    // matched against an English user turn.
    let conversation = runner.createConversation(systemPrompt: "Translate to Japanese.")
    let userMessage = ChatMessage(role: .user, content: [.text("Hello.")])
    let inferenceStart = Date()
    // `maxOutputTokens` is the v0.9.4 field name (the leap-sdk SKILL.md
    // example uses `maxTokens` which does not exist in this SDK
    // version — side finding to surface).
    let stream: AsyncThrowingStream<MessageResponse, any Error> = conversation.generateResponse(
        message: userMessage,
        generationOptions: GenerationOptions(maxOutputTokens: 64)
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
                // Not expected for LFM2 translation but tolerate.
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
        print("SPIKE FAIL: Leap.load(manifestURL:) accepted file:// URL but inference failed after \(String(format: "%.1f", totalElapsed))s with: \(error). Loaded chunks so far: \(observedChunkCount). Treat the chain as not fully verified.")
        Issue.record("Inference stream threw: \(error)")
        return
    }
    let inferenceElapsed = Date().timeIntervalSince(inferenceStart)
    print("[SPIKE] inference: \(observedChunkCount) chunks, complete=\(observedComplete), elapsed=\(String(format: "%.1f", inferenceElapsed))s")
    print("[SPIKE] assembled output: \(assembledChunks)")

    // -------- Step 5: Verdict --------
    #expect(observedChunkCount >= 1, "Expected at least one .chunk from the stream")
    #expect(observedComplete, "Expected a terminal .complete from the stream")

    let totalElapsed = Date().timeIntervalSince(startWallClock)
    if observedChunkCount >= 1, observedComplete {
        print("SPIKE PASS: Leap.load(manifestURL:) accepts file:// URLs. Full chain HF-download -> local-manifest -> load -> warm -> infer succeeded in \(String(format: "%.1f", totalElapsed))s. Chunks=\(observedChunkCount). Manifest schema source: maintainer-published https://huggingface.co/LiquidAI/LFM2-350M-ENJP-MT-GGUF/resolve/main/leap/Q5_K_M.json")
    } else {
        print("SPIKE INCONCLUSIVE: Leap.load and createConversation both returned, but the inference stream produced chunks=\(observedChunkCount) complete=\(observedComplete). Recommend human gate review of stream protocol.")
    }
}
