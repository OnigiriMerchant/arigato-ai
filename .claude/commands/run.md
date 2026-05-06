---
description: Build, install, and launch the app on iPhone 17 Pro simulator. Captures runtime logs.
allowed-tools: mcp__xcodebuildmcp__*
---

Build and run ArigatoAI on the iPhone 17 Pro simulator:

1. List simulators via `mcp__xcodebuildmcp__list_sims`
2. Boot iPhone 17 Pro if not already booted
3. Build via `mcp__xcodebuildmcp__build_sim_name_proj`
4. Install and launch via `mcp__xcodebuildmcp__build_run_sim_name_proj`
5. Capture logs via `mcp__xcodebuildmcp__capture_logs`

Report any build failures or runtime crashes with file:line precision.
