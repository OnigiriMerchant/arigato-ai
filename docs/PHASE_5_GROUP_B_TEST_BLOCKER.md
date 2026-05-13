# Phase 5 Group B — Test Verification Blocker

**Session:** 2026-05-13 → 2026-05-14 (overnight stop)
**Status:** Group B build GREEN. Test suite verification BLOCKED across multiple attempts.
**Resume tomorrow with full context preserved.**

---

## TL;DR

Tonight's diagnostic ladder uncovered a real test bug (V3 deadlock) and shipped a fix
for it. The fix is sound on paper, but the **post-fix re-run failed in a different
mode** — `xcodebuild` did not even reach test execution. We are stopping for the night
before pushing anything. Tomorrow's session resumes from a clean head with the V3 fix
preserved.

---

## Attempts tonight

### Attempt 4a — full suite, default flags

- **Command:** `mcp__XcodeBuildMCP__test_sim` against sim `930EC6EA-DA72-4A38-ABFF-583AD70B28D4`.
- **Outcome:** HUNG. PID 3149 (orphan `xcodebuild` from the *prior* session at 23:11)
  and PID 4804 (the current session's process from 23:32) both sat at 0.0% CPU for
  5+ minutes.
- **Resolution:** Manually `kill -9` on both PIDs from a separate shell. Verified no
  `xcodebuild` processes remaining after.
- **Diagnosis at the time:** unclear — initially attributed to the known "Xcode 26
  `testmanagerd` hang" but later proved to be a downstream symptom of the V3 deadlock
  (see 4b).

### Attempt 4b — full suite, sequential

- **Setup:** All sims shut down via `xcrun simctl shutdown all`.
- **Command:** `mcp__XcodeBuildMCP__test_sim` with `extraArgs ["-parallel-testing-enabled", "NO"]`
  against sim `930EC6EA`. (First passed the wrong flag `-disable-test-parallelization`
  which is the `swift test` form; xcodebuild rejected it. Re-issued with the
  xcodebuild-correct `-parallel-testing-enabled NO`.)
- **Outcome:** Completed in 335.8s with `❌ 0 tests failed, 27 passed, 0 skipped`. Only
  27 of 167 expected tests ran. xcodebuild was killed by an external 5-minute timeout.
- **Root cause (diagnosed):** the sequential runner reached the `LFM2ModelLoader` suite,
  started test `V3 loadIfNeeded after cancellation does not strand the loader`, and
  deadlocked inside the test. Every test alphabetically after V3 in the suite never
  executed.

### V3 deadlock diagnosis

Test source: `ArigatoAITests/Translation/LFM2ModelLoaderTests.swift:296-325` (original).

Execution trace:

1. `cancellingTask` is spawned, which calls `loader.loadIfNeeded(quantization: "Q5_K_M")`.
2. The loader spawns an inner Task that runs the test's factory. The factory calls
   `attempts.increment()` then `await gate.wait()`. The inner task parks on the gate.
3. `cancellingTask.cancel()` marks the outer task cancelled. The await inside the
   loader (`try await task.value`) throws `CancellationError`. The loader's catch
   block wraps it as `.modelLoadFailed`, clears `inFlightLoad`, rethrows.
4. `cancellingTask` exits; `try? await cancellingTask.value` swallows the error.
5. `gate.release()` is called — it pops the **one** stored continuation, resumes the
   orphan inner task (which returns engine into the void; the loader's
   `loadIfNeeded` already exited).
6. The retry call `let result = try await loader.loadIfNeeded(...)` finds
   `loadedEngine == nil` and `inFlightLoad == nil`, so it spawns a **fresh** factory
   invocation. That invocation calls `await gate.wait()` a second time.
7. `LFM2ContinuationGate` is a single-shot continuation slot. After step 5 the slot is
   `nil`, no waiter is parked, and no second `release()` is ever called in the test.
   The retry parks forever.
8. `withCheckedContinuation` does **not** honor cancellation, so the test cannot
   self-rescue. The test hangs until xcodebuild's external timeout kills it.

**Classification:** test bug, not a production-code contract violation. The loader's
cancellation-recovery path (clear `inFlightLoad`, re-invoke the factory on retry) is
sound. V3's *mechanism* — single-shot gate, single `release()`, but the test path
parks on the gate twice — is broken.

### Fix applied — Option B (counter-aware factory)

Working-tree change to `ArigatoAITests/Translation/LFM2ModelLoaderTests.swift`,
lines ~296–333.

The factory now parks on the gate only for the **first** invocation (the load that
will be cancelled). Subsequent invocations — the post-cancellation retry — return
the engine immediately. This isolates the cancellation hand-off from the retry's
success path so the test asserts only what V3 claims: a cancelled in-flight load
does not strand the loader.

```swift
let loader = LFM2ModelLoader(factory: { _, _ in
    let isFirstCall = (attempts.value == 0)
    attempts.increment()
    if isFirstCall {
        await gate.wait()
    }
    return engine
})
```

`CallCounter` is `OSAllocatedUnfairLock`-backed and safe for the
`attempts.value == 0` then `attempts.increment()` read–modify sequence; the two
factory invocations are serialized by the gate so there is no concurrent observer
problem either way.

The fix is **NOT a discard**. V3 is preserved as an active violation test for the
loader's cancellation-recovery contract, exactly as the original suite intended.
Per CLAUDE.md "discarded tests require diagnosis" rule, this is a mechanism fix, not
a discard.

### Attempt — post-fix re-run

- **Setup:** All sims shut down.
- **Command:** same `mcp__XcodeBuildMCP__test_sim` with `extraArgs ["-parallel-testing-enabled", "NO"]`.
- **Outcome:** UNRESOLVED. Full re-build + re-test ran for 1509.3s total.

**Updated reading of the log after a second pass** (supersedes the earlier
"test execution never started" reading, which was wrong — I had skipped past the
build-phase output and misread the missing trailing log as missing leading log):

- **The test bundle WAS rebuilt with the V3 fix.** Log line 246:
  `SwiftCompile normal arm64 Compiling LFM2ModelLoaderTests.swift`. Line 272:
  `Ld ... ArigatoAITests.xctest/ArigatoAITests`. Line 329:
  `** TEST BUILD SUCCEEDED **`. Then line 332 invokes
  `xcodebuild ... test-without-building` against that freshly-built bundle.
  `test-without-building` is XcodeBuildMCP's standard two-phase flow (build first,
  then test-without-building reuses the freshly-built bundle); it is not evidence
  of a stale build.
- **The fixed V3 still hung at the same signature.** Log ends at line 426 with
  exactly the same final two lines as Attempt 4b:
  ```
  ◇ Test "V3 loadIfNeeded after cancellation does not strand the loader" started.
  2026-05-14 00:03:00.238177+0900 ArigatoAI[8389:178235] [LeapModelDownloader]
    LeapModelDownloader initialized with directory: /Users/josecastell/Library/...
  ```
  …then nothing for ~22 minutes until xcodebuild's external timeout killed the run.
- **The Option B fix did not unstick V3.** This rules out my original diagnosis:
  the deadlock is not at the retry's second `gate.wait()`. If it were, the
  `isFirstCall` skip in the fixed factory would have let the retry return the engine
  immediately. The retry was never reached.
- **User decision:** stop the session here rather than escalate to Attempt 4c.

### Revised diagnosis — the deadlock is upstream of the retry

The most likely site is `_ = try? await cancellingTask.value` at
`LFM2ModelLoaderTests.swift:321`. The fix and the original test both assume
`cancellingTask.cancel()` propagates cancellation through `try await task.value`
inside the actor's `loadIfNeeded`, causing the actor's catch to clear
`inFlightLoad`, throw a wrapped error, and let cancellingTask exit. If that
propagation is unreliable in Swift 6.3.2:

1. `cancellingTask.cancel()` marks cancellingTask but does not unblock it.
2. The inner load Task remains parked at `gate.wait()` — single-shot,
   non-cancellable continuation.
3. cancellingTask cannot complete → `await cancellingTask.value` parks V3's
   task forever.
4. `gate.release()` (line 323) is unreachable.

Apple's docs on `Task.value` describe propagation of the inner task's *error*
to the awaiter; they do not unambiguously document propagation of the awaiter's
own cancellation into the suspension point. The hung behavior strongly suggests
the awaiter's cancellation is **not** propagated here, at least in this
actor-method-inside-Task pattern.

Every other test in this file that uses the same
"cancel-the-task-then-await-its-value" pattern (if any) is also suspect.

### Why Option B applied tonight is still likely the right shape

The `isFirstCall` skip in the retry's factory remains desirable: if a future
fix unblocks step 1's `cancellingTask` correctly, the retry needs to not deadlock
on a second `gate.wait()`. Don't `git restore` the Option B edit tonight; the
chosen fix tomorrow will likely build on it.

---

## Recommended next steps (fresh-session investigation tomorrow)

In order:

1. **Doc-research `Task.value` cancellation propagation in Swift 6.3.2.** Invoke
   `@doc-researcher` against Apple's `Task.value` documentation and the Swift
   Forums for definitive behavior. Question: when the awaiting task is cancelled
   while parked at `try await someTask.value`, does the await throw
   `CancellationError`, or does the await continue waiting for the inner task to
   complete on its own? The answer determines whether V3's mechanism is salvageable
   or fundamentally broken.
2. **Apply one of two candidate fixes for V3 (pick after the doc-research result):**
   - **Fix A — reverse the `gate.release()` ordering.** Call `gate.release()`
     BEFORE `await cancellingTask.value`. Trade-off: the load completes normally
     and cancellation never actually fires mid-load. V3's stated intent
     ("cancellation does not strand the loader") is no longer truly exercised —
     the test becomes "park, release, retrieve" with cancellation as a no-op.
     Possibly acceptable per V3's own doc-comment ("this test does not assert
     specific cancellation propagation semantics — it only asserts that the loader
     recovers cleanly so that fresh callers receive an engine"), but the test
     is then false-naming itself.
   - **Fix B — replace the gate with a cancellation-aware park.** Use
     `try? await Task.sleep(for: .seconds(60))` inside the factory's first-call
     branch. `Task.sleep` honors cancellation natively, so when cancellingTask
     is cancelled the inner task observes cancellation immediately, throws
     CancellationError out of the sleep, the factory's `try?` swallows it, the
     factory returns the engine, the actor's `task.value` returns the engine
     normally, and the load completes successfully. The retry's `loadedEngine`
     cache yields the same engine. Satisfies V3's stated intent without
     depending on `task.value`'s cancellation-propagation behavior. Recommended.
3. **Keep the Option B `isFirstCall` skip even with Fix B.** If a future re-think
   restructures cancellation handling so the load is genuinely interrupted, the
   retry path needs to not park on a single-shot gate. The skip is small,
   harmless, and useful as defensive scaffolding.
4. **After the V3 fix is applied, re-run the full 167-test suite** with the same
   `mcp__XcodeBuildMCP__test_sim` invocation (sim 930EC6EA, sequential). Hard
   timeout: if the fixed V3 hangs again, the diagnosis is still wrong — stop and
   re-investigate before any third fix attempt.
5. **Audit other tests in `LFM2ModelLoaderTests.swift` that use
   `cancel-then-await-task.value`.** If `Task.value` does not propagate
   awaiter cancellation, every such test is silently broken. Catalog them and
   apply the same `Task.sleep`-based fix.
6. **Process hygiene at session start.** Verify no orphan `xcodebuild`,
   `testmanagerd`, `Simulator`, `CoreSimulatorService` processes are leftover.
   `ps aux | grep -E '(xcodebuild|testmanagerd|Simulator|CoreSimulator)'` should
   be empty (except for the system's idle `CoreSimulatorService`). The orphan
   PID 3149 from a *prior* session this evening confirms cross-session state
   contamination is a real risk.

---

## Status snapshot (end of session 2026-05-13)

- **Branch:** `main`, 8 commits ahead of `origin/main`. Not pushed.
- **Working tree:** ONE modified file —
  `ArigatoAITests/Translation/LFM2ModelLoaderTests.swift` carries the Option B
  V3 fix. **The V3 fix is NOT yet committed.** Earlier dispatch implied it was
  "committed locally (one of the 8 ahead commits)"; in reality the fix lives in
  the working tree only. Tomorrow's first decision: commit it as a checkpoint
  (test-only change, build passed implicitly during the post-fix attempt's compile
  phase but tests were never verified) or hold it uncommitted until tests pass
  clean. CLAUDE.md's checkpoint rule requires "production code compiles, tests
  pass" — tests do **not** yet pass, so a strict reading says do not commit yet.
- **Test verification:** still NOT clean. 27/167 known passing from the 4b partial
  run; the remaining 140 are unverified. The V3 fix is unverified by execution.
- **Push:** explicitly DO NOT PUSH. The three-reviewer gate has not run; tests are
  not verified clean; user has not approved.
- **V3 fix preservation:** do not `git restore` or `git stash drop` the working-tree
  edit. It is the only artifact of tonight's diagnosis work.

---

## Files touched tonight

- `ArigatoAITests/Translation/LFM2ModelLoaderTests.swift` — V3 test mechanism fix
  (uncommitted, working tree only).
- `docs/PHASE_5_GROUP_B_TEST_BLOCKER.md` — this document (new).

No production code was modified. No `project.pbxproj`, no `.xcscheme`, no
`.xctestplan` was modified. No commits were pushed.
