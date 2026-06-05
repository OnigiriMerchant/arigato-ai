---
description: Sweep the EXISTING codebase for concurrency-design-discipline violations (missing scheduling-assumption docs + missing violation tests). Complements @code-reviewer, which only sees the diff.
allowed-tools: Read, Grep, Glob, Bash, mcp__xcodebuildmcp__*
argument-hint: optional path to scope the sweep (default ArigatoAI/)
---

Audit scope: ${ARGUMENTS:-ArigatoAI/} (production code only — exclude ArigatoAITests/).

## Why this exists
@code-reviewer enforces the CLAUDE.md "Concurrency design discipline" but only on the
`git diff` at commit time. Code that landed before the rule — or that slipped past a
review — is never re-examined. `AudioCaptureActor`'s tap→Task hop (written 2026/05/09,
no ordering doc, no violation test) is the cautionary case that motivated this command.
This sweep reaches back into already-landed code that diff-time review structurally cannot.

## Procedure
1. **Inventory** every concurrency surface in scope. Grep for:
   - `actor ` declarations
   - `AsyncStream` / `AsyncThrowingStream` (creation and consumption)
   - `for await` / `for try await` (async-sequence consumers)
   - `Task {` / `Task.detached` / `Task<` (unstructured task spawns)
   - `.yield(` continuation producers
   - `withTaskGroup` / `async let`
   Record each as `file:line — surface kind`.

2. **Audit each surface** against the discipline. For every one, check:
   - **(a) Execution-order / pacing assumption doc-comment** — does the type or method
     have a doc-comment stating what the scheduler assumes about external pacing or
     ordering (e.g. "assumes the producer yields between iterations", "assumes one
     consumer drains FIFO", "assumes inflight completes before the next enqueue")?
   - **(b) Violation-behavior doc-comment** — does it state what happens when that
     assumption is violated (drop / queue / block / deadlock / overwrite / reorder)?
   - **(c) Violation test** — is there a test that drives the surface IN VIOLATION of
     its assumption (greedy producer, stalled consumer, simultaneous spawn, reordered
     submission) and asserts correct behavior? Find it by searching the test target for
     the surface's type name and for `VIOLATION` test IDs.
   - **(d) Test-ID integrity** — if a doc-comment NAMES a specific test ID, OPEN that
     test and confirm it actually enforces the documented contract. A doc-comment naming
     a test that does not enforce is a finding (false confidence — worse than naming none).

3. **Classify** each surface as one of:
   - `OK` — assumption documented, violation behavior documented, enforcing violation test exists.
   - `TRACKED` — gap exists but is honestly documented in-code AND has a V3 backlog entry
     with a concrete trigger (acceptable per CLAUDE.md "document the gap explicitly").
   - `VIOLATION` — missing (a), (b), or (c) with no documented gap; or a test-ID-integrity failure.

## Output
A tagged report, code-reviewer style:

```
Concurrency audit — <scope>
Surfaces examined: N

VIOLATIONS (M)
- file:line — <surface kind> in <Type> — missing: <assumption doc | violation doc | violation test | test-id integrity> — fix: <what to add>

TRACKED (K)
- file:line — <surface kind> — gap documented, V3 #<n>

OK (P)
- file:line — <surface kind> in <Type>
```

Then, for each `VIOLATION`, recommend the cheapest honest remediation: either
(i) add the missing doc-comment(s) + a named violation test, or (ii) if the design has a
latent correctness bug under reordering (not just a doc gap), flag it for a structural
fix via @feature-planner. Do NOT write production code from this command — it audits and
reports. End by asking whether to (a) plan fixes via @feature-planner, or (b) file the
gaps to docs/V3_BACKLOG.md with concrete triggers.
