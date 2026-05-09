# Arigato AI — Project Context

## What this is
On-device bidirectional Japanese↔English meeting translator for iPhone 17 Pro Max.
Personal use first, App Store later if it earns its way there.

## Stack
- iOS 26.4+, Swift 6, SwiftUI, SwiftData, Swift Testing
- WhisperKit via argmax-oss-swift v1.0.0+ (Apache-2.0) — Japanese + English ASR with auto language detection
- LFM2-350M-ENJP-MT via LEAP iOS SDK — bidirectional JA↔EN translation
- Apple Foundation Models (free, on-device) — Tier 1 post-meeting cleanup
- Anthropic API (Claude Opus 4.7) — Tier 2 post-meeting cleanup
- Bundle ID: com.jose.ArigatoAI

## Architecture rules
- All real-time inference is on-device. No network calls during meetings.
- Audio capture → Whisper streaming with language tag → router → LFM2 translate (JA→EN or EN→JA) → SwiftData persist → SwiftUI render.
- Each pipeline stage is its own actor or class. No god objects.
- Whisper language fallback uses consecutive-window disagreement gating (N=2). See LanguageRouter spec in PHASE_4_HANDOFF.md.
- Pre-warm both models at app launch to avoid cold-start glitches.
- Default simulator: iPhone 17 Pro Max (iOS 26.4 / 26.4.1 — XcodeBuildMCP picks latest patch automatically via useLatestOS: true). The physical target device is iPhone 17 Pro Max — different screen size, safe-area insets, Dynamic Island. Never test against iPhone 17 Pro.

## Coding standards
- SwiftUI for all views. UIKit only when wrapping a system API that requires it.
- @Observable for view models (not @ObservableObject — this is Swift 6).
- SwiftData for persistence. No Core Data.
- async/await everywhere. No completion handlers in new code.
- Public types and methods get DocC doc comments.
- No force-unwraps in production code. Use guard/if-let.
- No fatalError to silence errors. Find the real cause.

## Swift 6 concurrency
- New types default to `nonisolated` unless they touch main-actor UI state.
- Use `Sendable` for value types passed across actor boundaries.
- `@MainActor` only on view models bound to SwiftUI views, not on internal types.
- Test fakes: use `OSAllocatedUnfairLock` or actor-based fakes. Never `NSLock` — Swift 6 forbids it from async contexts.
- AVAudioPCMBuffer is non-Sendable. Copy to plain `[Float]` before crossing actor boundaries.
- When in doubt about isolation, invoke @doc-researcher rather than guessing.

## Build workflow
- Use XcodeBuildMCP for all build/test/run/deploy from the main session. Subagents may fall back to raw xcodebuild via Bash due to a known MCP-inheritance bug in Claude Code (see https://github.com/anthropics/claude-code/issues/25200). When this happens, the main session is responsible for verifying subagent build output via XcodeBuildMCP after subagent completion. Do not blanket-permit raw xcodebuild from the main session.
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
- Don't commit until the three-reviewer gate has run (@code-reviewer + @ui-reviewer + @git-historian) AND I have explicitly approved.
- Don't use deprecated APIs. If unsure, invoke @doc-researcher.

## External dependency configuration
- When picking configuration values for external dependencies (model identifiers, API endpoints, recommended defaults, tokenizer names, etc.), verify against BOTH the pinned version's source tree AND the maintainer's current README/docs.
- Source tree confirms what works in your pinned version. README confirms what the maintainer recommends. Locked architectural decisions in phase handoffs encode use-case-specific reasoning.
- When recommendations conflict with locked decisions, surface the collision before acting. The locked decision wins by default — it was made with full context. A recommendation overriding it requires explicit re-examination of the original reasoning.
- Pin specific values explicitly. Do not rely on dynamic-recommendation APIs (e.g., recommendedRemoteModels()) for MVP — explicit pinning is more predictable and easier to debug.
- Maintainer recommendations are general-purpose. Your use case may legitimately be in a niche the maintainer doesn't recommend on their front page. Phase 4 Decision 2 (large-v3-turbo) is an example — Argmax's README recommends 626MB non-turbo for accuracy, but our use case (live meeting captions) prioritizes latency, so turbo is the correct niche choice.

## Project rhythm
- Plan first via @feature-planner. Implement second via @swift-implementer.
- Review every diff via @code-reviewer before commit.
- Use @swift-tutor whenever I ask "what does this do?" or "why this way?".
- Use @doc-researcher anytime an API/SDK detail is uncertain.
