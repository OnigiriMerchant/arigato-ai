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
8. Stage CURRENT_STATE.md and decide commit-new vs amend per the self-reference-suppression rule:
   1. Run `git diff --staged docs/CURRENT_STATE.md` to inspect the staged diff. Identify which fields actually changed (Last updated date, Most recent commit, Phase status, Next planned action, Active prerequisites for next phase, V3 backlog priority items, Working tree).
   2. If the **only** changed field is "Most recent commit" (the line referencing the previous commit's SHA/subject — treat a same-day "Last updated date" tick as not a meaningful change for this rule), check the previous commit on `HEAD`:
      - Run `git log -1 --pretty=format:"%s"` to read the previous commit's subject.
      - Run `git rev-list origin/main..HEAD` to confirm the previous commit has not been pushed to origin.
      - If the previous commit's subject starts with `docs: refresh current state for chat migration continuity` or `docs(state): refresh after`, AND the previous commit is in the `origin/main..HEAD` range (i.e., not yet pushed), then run `git commit --amend --no-edit` to fold the refresh into the previous commit. Skip step 8.3.
   3. Otherwise (any other field changed, OR previous commit is not a self-refresh, OR previous commit is already at origin/main), run `git commit -m "docs: refresh current state for chat migration continuity"` to create a new commit.
   4. The amend branch applies **only** when the previous commit is a `/update-state` self-refresh as identified by the message prefixes above. Never amend a production / feature / fix commit, even if the staged diff is small. Production commits use `feat:`, `fix:`, `checkpoint(...)`, or other non-`docs: refresh`/`docs(state): refresh` prefixes — those are out of scope for this rule.
   5. The amend branch also requires the previous commit to be local-only (`origin/main..HEAD`). If it is already at origin/main, amending would require a force-push, which the project rejects — fall through to step 8.3 and commit normally.
9. Report what changed since last update, and whether step 8 amended the previous commit or created a new one.

Do not modify docs/CLAUDE_AI_MIGRATION_PROMPT.md — that file is evergreen.
Do not push — leave that to the user's normal session-end flow.
