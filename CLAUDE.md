# Arigato AI — Project Context

## What this is
On-device bidirectional Japanese↔English meeting translator for iPhone 17 Pro Max.
Personal use first, App Store later if it earns its way there.

## Stack
- iOS 26.4+, Swift 6, SwiftUI, SwiftData, Swift Testing
- WhisperKit (Apache-2.0) — Japanese + English ASR with auto language detection
- LFM2-350M-ENJP-MT via LEAP iOS SDK — bidirectional JA↔EN translation
- Apple Foundation Models (free, on-device) — Tier 1 post-meeting cleanup
- Anthropic API (Claude Opus 4.7) — Tier 2 post-meeting cleanup
- Bundle ID: com.jose.ArigatoAI

## Architecture rules
- All real-time inference is on-device. No network calls during meetings.
- Audio capture → Whisper streaming with language tag → router → LFM2 translate (JA→EN or EN→JA) → SwiftData persist → SwiftUI render.
- Each pipeline stage is its own actor or class. No god objects.
- Whisper language confidence below 0.7 → fall back to previous chunk's language.
- Pre-warm both models at app launch to avoid cold-start glitches.

## Coding standards
- SwiftUI for all views. UIKit only when wrapping a system API that requires it.
- @Observable for view models (not @ObservableObject — this is Swift 6).
- SwiftData for persistence. No Core Data.
- async/await everywhere. No completion handlers in new code.
- Public types and methods get DocC doc comments.
- No force-unwraps in production code. Use guard/if-let.
- No fatalError to silence errors. Find the real cause.

## Build workflow
- Use XcodeBuildMCP for all build/test/run/deploy. Never raw xcodebuild.
- Use Apple's xcode MCP for documentation search, SwiftUI preview screenshots, live diagnostics.
- After every Swift edit, run mcp__xcodebuildmcp__build_sim_name_proj to verify.
- Run tests with mcp__xcodebuildmcp__test_sim_name_proj before committing.

## Privacy and data rules
- No analytics. No tracking. No telemetry.
- No cloud sync of transcripts. iCloud / CloudKit explicitly disabled.
- API keys live in iOS Keychain or .env (gitignored). Never in source files.
- Transcripts never leave the device unless user explicitly exports or chooses Tier 2 cleanup.

## Don't
- Don't add cloud features without explicit instruction.
- Don't add force-unwraps.
- Don't commit until I approve via "ship it" or "/ship".
- Don't use deprecated APIs. If unsure, invoke @doc-researcher.

## Project rhythm
- Plan first via @feature-planner. Implement second via @swift-implementer.
- Review every diff via @code-reviewer before commit.
- Use @swift-tutor whenever I ask "what does this do?" or "why this way?".
- Use @doc-researcher anytime an API/SDK detail is uncertain.
