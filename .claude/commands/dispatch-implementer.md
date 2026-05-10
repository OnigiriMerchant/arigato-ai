---
description: Generate a swift-implementer dispatch brief for a specified plan step.
argument-hint: step name + scope + summary (e.g., "group-d-step-3 files:Foo.swift,Bar.swift adds RoutedTranscript persistence")
---

Produce a complete `@swift-implementer` dispatch brief for: $ARGUMENTS

Fill the variable parts of the template below from the user's arguments. If the arguments do not include a step name, file scope, and a one-line goal, STOP and ask the user to re-invoke with the missing pieces. Do NOT invent file scope.

Variable parts you must fill from $ARGUMENTS (or surface and ask):
- Step number / name (e.g., `group-d-step-3`)
- Prior commits that just landed (ask the user or read `git log -5 --oneline` if not provided)
- One-paragraph goal of the step
- Absolute file scope — bullet list of full paths the implementer may touch
- Required reading list — bullet list of files the implementer must read before editing
- Required changes — itemized list, the meat of the brief
- Surfaced concerns — anything the planner flagged for the implementer's attention

Hard-coded sections that MUST land verbatim (do not paraphrase, do not summarize):
- The `Constraints (CLAUDE.md, with teeth)` block
- The `Build and test verification` xcodebuild commands
- The `Final action — commit` checkpoint format
- The `Reporting back` numbered list
- The closing line `Do not push. Do not run /ship. Do not invoke other agents.`

Output the dispatch brief verbatim using this template, with variable parts filled:

---

# @swift-implementer dispatch — <STEP NAME>

## Context

<one paragraph: which group + step, what just landed (commit SHAs), what this step does>

## Goal

<one paragraph: the concrete deliverable of this step>

## Absolute file scope (do NOT touch any file outside this list)

<bullet list of absolute file paths>

That is the entire scope.

If you discover you need to edit any other file, **STOP** and surface.

## Required reading before editing

<bullet list of file paths the implementer must read>

## Required changes

<itemized list — the meat of the brief>

## Surfaced concerns

<anything the planner flagged, or "None.">

## Constraints (CLAUDE.md, with teeth)

- **Scope is absolute.** Files outside the listed scope must not be touched, including via formatter side effects, including via "consistency" renames, including for ostensibly minor reasons. STOP and surface if integration appears to require touching another file.
- **Surface in summary is NOT surface and pause.** Architectural decisions outside the brief must be raised before code is written that depends on them, with a recommended answer, and pause for human confirmation. Post-hoc lists in the completion summary do not satisfy the rule.
- **Discarded tests require written diagnosis.** If a test surfaces an unexpected failure, determine: was the test wrong, or did production code violate a contract? If unclear from inspection, that is a STOP condition — surface the test, the failure, the production code, and pause. Discarding a test without diagnosis is forbidden.
- **Doc-comment claims that name a specific test ID must be verified.** Open the named test, read it, confirm it actually enforces the documented contract. Naming a test that doesn't is worse than not naming one.
- **No force-unwraps in production code.** Use `guard`/`if-let`. No `fatalError` to silence errors.
- **Concurrency design discipline gate.** For any actor / AsyncStream / Task spawning work, the type or method must carry a doc-comment specifying the scheduler's external-pacing assumption AND what happens when that assumption is violated (drops, queues, blocks, deadlocks, retries). At least one test must drive the system in violation of those assumptions and assert correct behavior. Doc-comment claims naming a test ID must be verified against that test's actual behavior.

## Build and test verification

- **Build**: `xcodebuild -project /Users/josecastell/AI-projects/arigato-ai/ArigatoAI.xcodeproj -scheme ArigatoAI -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max,OS=latest' build 2>&1 | tail -50`
- **Test**: `xcodebuild -project /Users/josecastell/AI-projects/arigato-ai/ArigatoAI.xcodeproj -scheme ArigatoAI -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max,OS=latest' test 2>&1 | tail -100`

Both must succeed before commit.

## Final action — commit

After build + tests pass:

```
git add <files-in-scope>
git commit -m "checkpoint(<step-name>): <brief description>"
```

Do NOT push.

## Reporting back

When done, report:
1. Build status.
2. Test status (full count).
3. Commit hash.
4. Files changed (absolute paths).
5. Any decisions surfaced during implementation.
6. Any scope questions encountered.

Do not push. Do not run /ship. Do not invoke other agents.
