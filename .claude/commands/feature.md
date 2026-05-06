---
description: Plan and implement a feature end-to-end with full agent pipeline.
argument-hint: feature description (e.g., "live caption view with auto-scroll")
---

Implement feature: $ARGUMENTS

Pipeline:
1. Invoke @feature-planner to produce an implementation plan.
2. Surface the plan to the user. WAIT for explicit approval ("go" / "approved" / "looks good") OR plan revisions.
3. Once approved, invoke @swift-implementer to execute the plan.
4. After implementation, run `/build` to verify.
5. If any UI was added or changed, invoke @ui-reviewer.
6. Invoke @code-reviewer for the final diff review.
7. If all checks pass, ask: "Run /ship to commit?"

Do NOT skip the user-approval gate after planning. Citizen developer workflow requires explicit go-ahead.
