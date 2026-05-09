# /update-state

Refresh docs/CURRENT_STATE.md with the latest session state. Use this at end of every session before /exit.

Steps:
1. Run `git log -1 --pretty=format:"%H %s"` to get most recent commit SHA and subject
2. Run `git log -10 --pretty=format:"%H %s"` to find the most recent code commit (feat/fix prefix) if the head is a docs commit
3. Find the most recent docs/PHASE_*_HANDOFF.md and extract phase status from it
4. Run `git status --short` and `git rev-parse --abbrev-ref HEAD` to check working tree
5. Run `git rev-list --count origin/main..HEAD` and `git rev-list --count HEAD..origin/main` to check sync state
6. Read docs/V3_BACKLOG.md and identify items marked "relevant to upcoming work" or with active triggers
7. Rewrite docs/CURRENT_STATE.md with the structure: Last updated date, Most recent commit, Phase status, Next planned action, Active prerequisites for next phase, V3 backlog priority items, Working tree
8. Stage and commit with message "docs: refresh current state for chat migration continuity"
9. Report what changed since last update

Do not modify docs/CLAUDE_AI_MIGRATION_PROMPT.md — that file is evergreen.
Do not push — leave that to the user's normal session-end flow.
