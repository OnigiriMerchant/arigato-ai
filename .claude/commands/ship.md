---
description: Tests pass + code review passes + commit + push. The final gate before code lands on main.
allowed-tools: Bash, mcp__xcodebuildmcp__*, Read
---

Ship pipeline:

1. Run all tests via `mcp__xcodebuildmcp__test_sim_name_proj`. STOP if any fail.
2. Invoke @code-reviewer to review the staged + unstaged diff. STOP if it returns BLOCKED.
3. Invoke @git-historian to write a Conventional Commits message based on the diff.
4. Show the commit message to the user. Ask: "Commit with this message? (yes / revise)"
5. On approval: `git add -A && git commit -m "<message>"`. Pre-commit hooks (detect-secrets, force-unwrap guard) will fire automatically.
6. Push: `git push origin main`.
7. Confirm: "Shipped — commit <SHA> on origin/main."

NEVER bypass the code-reviewer block. NEVER commit without user approval of the message.
