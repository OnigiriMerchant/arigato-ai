---
description: Build the project for iPhone 17 Pro simulator. Reports errors with file:line precision.
allowed-tools: mcp__xcodebuildmcp__*
---

Build ArigatoAI for the iPhone 17 Pro simulator using `mcp__xcodebuildmcp__build_sim_name_proj`.

Project path: `~/AI-projects/arigato-ai/ArigatoAI.xcodeproj`
Scheme: ArigatoAI

If the build succeeds, output a short success line.
If the build fails, list each error in this format:
- file:line — error message
- root cause hypothesis (1 sentence)

Then ask: "Invoke @build-doctor to fix?"
