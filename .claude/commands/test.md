---
description: Run the test suite. Reports pass/fail per test, surfaces failures with file:line.
allowed-tools: mcp__xcodebuildmcp__*
---

Run all tests in ArigatoAI via `mcp__xcodebuildmcp__test_sim_name_proj`.

Output format:
- ✅ N passed / ❌ N failed (summary line)
- For each failure: TestSuiteName.testName — file:line — assertion message

If any tests fail, ask: "Investigate failures? Invoke @swift-implementer or fix manually?"
