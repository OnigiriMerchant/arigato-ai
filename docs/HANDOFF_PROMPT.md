# Handoff prompt — paste into a fresh Claude Code session

_Last updated 2026-06-12 (pre-OS-update session close). Copy everything in the fenced block below as your first message to a new session. Everything described here is committed and pushed to `origin/main` through `402c6ec`._

---

```
You're picking up Arigato AI — an on-device bidirectional Japanese↔English meeting
translator for iPhone 17 Pro Max (iOS 26, Swift 6, SwiftUI, SwiftData). Read CLAUDE.md
first (architecture rules, build workflow, three-reviewer gate, concurrency discipline),
then docs/CURRENT_STATE.md (top headline). Auto-memory also carries
device-debug-state-2026-06-11.

WHERE WE ARE (all committed AND pushed through 402c6ec; working tree clean except the
intentionally-untracked .claude/workflows/):
The 2026-06-10→12 device-debugging arc found and fixed the three bugs blocking the
"app works" milestone, each through the three-reviewer gate:
1. 46904c9 — single-flight requestPermission + launch permission refresh (.task(id:) across
   the placeholder→wired VM swap) + in-flight button gating. DEVICE-PROVEN.
2. b715f3e + 9a20aab — the zombie-capture pair: route-change reconfiguration teardown AND
   the actual root cause, the undo-deadline auto-finalize that never released the mic
   (MeetingSession.fireDeadline now routes through MeetingCoordinator.finalizeFromDeadline:
   phase flip FIRST to settle the undo race, then pipeline+capture teardown). DEVICE-PROVEN
   via log archive ("Deadline finalize complete: pipeline + capture released"; clean second
   meeting right after). Same bundle: error banner (MeetingControlsView.errorBanner renders
   lastError — before it NO screen rendered any error), undo-toast restack (was overlapping
   and eating NEW TRANSCRIPT taps), persisted os_log across AudioCapture / Transcription /
   Pipeline / Coordinator categories.
3. 402c6ec — THE LAST BLOCKER, found overnight 2026-06-11: silent translation. The
   pipeline's TranslationActor was never warmed (AppBootstrapper warms only the lfm2Loader
   at ~:523; makeCoordinator builds a fresh TranslationActor at ~:595 and nobody calls
   warmup() on it) → resolvedEngine nil → the FIRST sentence of every meeting killed the
   event stream with modelNotReady → swallowed by MeetingSession's pump catch →
   "No sentences yet" EVERY meeting, simulator and device alike. Whisper was always fine
   (device logs: ~1 'en' segment/sec the whole meeting). Fixed: lazy engine resolution in
   startGeneration via resolveEngineForGeneration (cached-loader no-op in production),
   loud typed failure path, regression tests
   (translate_withoutPriorWarmup_lazilyResolvesEngine_andCompletes — fails on the old
   code — and translate_lazyResolutionFails_streamThrowsModelNotReady), and an error-level
   log at the formerly-silent pump swallow.

THE IMMEDIATE NEXT STEP — NOT YET DONE: the iPhone still runs the 9a20aab build (deployed
2026-06-10 23:56). DEPLOY current main (402c6ec) via @device-deployer — device "Jose's
iPhone", iPhone 17 Pro Max (iPhone18,2), devicectl id E2D0E29B-D5B3-5EDE-BA3A-ACD9BD9E2268,
automatic signing known-good (team TVAS2P4CR4), ENABLE_USER_SCRIPT_SANDBOXING=NO already
committed, ~893MB bundle installs incrementally fast. Then run the MILESTONE TEST with the
user:
  - Ask how long warmup takes this launch (5 min on 2026-06-10 was hypothesized as the
    one-time post-install ANE compile; a fast launch confirms it).
  - START → one English sentence → pause → one Japanese sentence → stop, letting the undo
    countdown expire (the mic must release: orange dot clears within seconds).
  - Translations should appear in both panes. That is the "app works" milestone.
  - If ANYTHING misbehaves: the app now logs its entire pipeline at persisted levels
    (subsystem com.jose.ArigatoAI; categories AudioCapture, Transcription, Pipeline,
    Coordinator, Translation). Have the USER run in their own terminal (sudo needs a TTY):
      sudo log collect --device --last 30m --output /tmp/arigato.logarchive
    then query the archive with /usr/bin/log show — NOTE: plain `log` is shadowed by a
    shell function in this environment; ALWAYS use /usr/bin/log.

AFTER THE MILESTONE (planned order):
  1. Warmup progress UI + generous timeout (docs/NEXT_SESSION_PLAN.md; set the timeout
     ABOVE the measured device compile time, e.g. 5 min). This also properly fixes the
     visible-but-dead controls during warmup (the window is the FULL warmup — the old
     "sub-50ms" doc claim was corrected as false).
  2. Optional ultracode lifecycle audit: every meeting path that must release mic/pipeline,
     adversarially enumerated. User was advised this is the right place for ultracode.
  3. Fresh V3 entries from this arc's gates: flake-cluster re-baseline (combined-suite
     failure counts drifted 6→14→8+crash→17 while isolated runs stay green — judge by
     isolated suite runs ONLY), errorBanner .red contrast measurement (MVP-1 sign-off),
     undo-clobbered-by-in-flight-finalize pre-existing race, pipeline errors logged but not
     UI-surfaced, required onRequestPermission init param, dead AudioCaptureView deletion.

OPERATIONAL GOTCHAS LEARNED THIS ARC:
  - The simulator's audio server degrades after hours of test pounding → engine-touching
    tests abort (AURemoteIO RPC timeout). Unit tests no longer touch real AudioToolbox
    (AudioCaptureActor.skipEngineOpsForTesting), but if weird sim behavior appears, reboot
    the sim. Default sim: iPhone 17 Pro Max, UUID 930EC6EA-DA72-4A38-ABFF-583AD70B28D4.
    NEVER test against iPhone 17 Pro.
  - NEVER unit-test real AVAudioSession activation (.record category) — it aborts the
    whole test process.
  - devicectl launch --console captures stdout only (LEAP/llama.cpp logs); os_log needs
    log collect. info/debug levels are NOT persisted — instrument at .notice/.error.
  - .claude/workflows/code-review-xhigh.js is INTENTIONALLY untracked (user decision
    pending on whether review tooling belongs in the repo).

RULES THAT BITE (CLAUDE.md): three-reviewer gate (@code-reviewer + @ui-reviewer +
@git-historian) before commit AND explicit user approval; the user holds commit/push/deploy
gates — ask, don't assume; XcodeBuildMCP for all build/test (session defaults configured);
concurrency-design-discipline: scheduling assumptions documented + REAL violation tests —
a doc-comment naming a test that doesn't enforce the contract is the project's cardinal
sin (caught twice this arc, including a false "two main-actor calls cannot interleave"
claim; serialization claims must be audited against EVERY await). No force-unwraps. DocC
on public API. The user is a citizen developer: plain-language recommendations, lead with
what matters, they decide.

START: verify `git log --oneline -3` shows 402c6ec at HEAD with origin/main in sync and a
clean tree, build via XcodeBuildMCP to confirm the toolchain survived the OS update, then
ask the user to connect the iPhone for the deploy + milestone test.
```
