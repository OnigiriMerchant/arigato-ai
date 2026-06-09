# Handoff prompt — paste into a fresh Claude Code session

_Last updated 2026-06-10. Copy everything in the fenced block below as your first message to a new session. Everything described here is committed and pushed to `origin/main`._

---

```
You're picking up Arigato AI — an on-device bidirectional Japanese↔English meeting
translator for iPhone 17 Pro Max (iOS 26, Swift 6, SwiftUI, SwiftData). Read CLAUDE.md
first (architecture rules, build workflow, the three-reviewer gate, concurrency-design
discipline), then docs/CURRENT_STATE.md (top headline) and docs/NEXT_SESSION_PLAN.md.

WHERE WE ARE
The app is MVP-1 feature-complete in code. Two recent threads, both landed and pushed:
1. Offline Whisper: the WhisperKit model (~607MB) + tokenizer are bundled via Git LFS and
   load fully offline (WhisperKitConfig modelFolder/tokenizerFolder/download:false, guarded
   by WhisperBundledModel.resolve). Passed a three-reviewer gate incl. an adversarial pass
   that caught + fixed a Hub-cache-shadow silent-network hole. LFM2 (~260MB GGUF) was already
   bundled. App is ~893MB.
2. Mic-button fix: the live-meeting "Microphone access" surface
   (ArigatoAI/Views/MeetingControlsView.swift notDeterminedContent) was a block of TEXT with
   no button — a not-determined user could never grant mic access. Now it's a real "Allow
   microphone" Button → AudioCaptureViewModel.requestPermission(). Passed the three-reviewer
   gate. Verified in the iPhone 17 Pro Max simulator (button renders + is tappable). Tests green.

KEY DIAGNOSIS (don't re-investigate): the device "warming up never finishes" is NOT a hang
and NOT a regression. It's the one-time first-launch Neural-Engine compilation of the ~600MB
Whisper model. Proven in the simulator: bundled models load cleanly (Whisper ~33s, LFM2 0.44s,
warmup reaches "ready" in ~40s). The device is slow ONLY on first launch (ANE specializes
~600MB), then caches and is fast. The simulator skips ANE so it's always fast there.

STRATEGIC CONTEXT (from the user): de-prioritize strict airplane-mode offline. The goal is
"make the app work and finish the build." Users have internet; downloading models after
install is an App-Store-prep OPTION, not on the critical path (the user installs to their own
iPhone over the cable, which is not size-gated). The user is a citizen developer: give
plain-language recommendations, and they hold explicit gates on git push and agent-config.

THE NEXT STEP (highest priority): get the mic-fixed build onto the user's iPhone 17 Pro Max
and run it end-to-end WITH the user.
  - The mic fix only exists in the new build, so redeploy. Device build needs
    ENABLE_USER_SCRIPT_SANDBOXING=NO on the app target (already committed) — without it the
    "Re-sign nested LeapModelDownloader dylibs" phase fails. Use the @device-deployer agent;
    device UDID is in docs/CURRENT_STATE.md / NEXT_SESSION_PLAN.md. The ANE compile likely
    already ran on 2026-06-06, so warmup should be fast this time (it caches).
  - Then: user taps "Allow microphone" (now a real button), grants, and speaks one English +
    one Japanese line to confirm both directions transcribe + translate. That's the "app
    works" milestone.

THEN (planned, not yet done): add a warmup progress UI + a generous timeout in
WhisperModelLoader/WhisperClientFactory so the first-launch ANE compile reads as "Preparing
models — first launch can take a minute or two" instead of looking hung. (Set the timeout
ABOVE the measured device compile time, e.g. 5 min — NOT 120s.) See NEXT_SESSION_PLAN.md.

LATER (user decision, deferred): model delivery — keep the bundle (current) vs SDK-native
download-on-first-launch vs Apple Background Assets. Recommendation: keep the bundle now;
when prepping for the App Store, go SDK-native download-on-first-launch (both SDKs cache for
offline-after-first-run, so meetings stay offline). Not a blocker.

OPEN NON-BLOCKING NITS (from the mic-fix gate, optional, do if touching the files):
  - ui-reviewer: no committed SwiftUI #Preview covers the notDetermined/denied permission
    surface (all previews pin to .granted) — a permanent preview would catch visual regressions.
  - code-reviewer: a sub-50ms window at launch where the "Allow microphone" button shows under
    the disabled() placeholder VM and tapping is a no-op; self-corrects on next render. The
    warmup progress UI work is the natural place to address it.

RULES THAT BITE (from CLAUDE.md):
  - Build/test via XcodeBuildMCP after every Swift edit; default sim is iPhone 17 Pro Max
    (NEVER iPhone 17 Pro). Device target is iPhone 17 Pro Max only.
  - Do NOT push or commit-to-origin until the three-reviewer gate (@code-reviewer +
    @ui-reviewer + @git-historian) runs AND the user explicitly approves. The user holds the
    push gate.
  - No force-unwraps, no fatalError, DocC on public API, @Observable view models, async/await.
  - Concurrency-design-discipline: any new actor/async-stream/Task work needs a documented
    scheduling assumption + a REAL violation test. A doc-comment naming a test that doesn't
    enforce the contract is worse than naming none (this exact issue was just caught + fixed).
  - Verify SDK/API facts against PRIMARY sources (SPM source + official docs), not memory —
    use the xcode MCP DocumentationSearch (Apple) and liquid-docs MCP (LEAP). leap-sdk is
    SKIE/Kotlin-bridged: verify call shapes by COMPILING, not by grepping the .swiftinterface.

VERIFY THE STARTING STATE: `git -C /Users/josecastell/AI-projects/arigato-ai log --oneline -5`
should show 3d41090 (mic-test honesty fix) at or near HEAD, and `git status` should be clean
with origin/main up to date. Build: mcp__xcodebuildmcp__build_sim_name_proj. Tests:
mcp__xcodebuildmcp__test_sim_name_proj.

Start by confirming that state, then ask the user if their iPhone is connected so you can
build + deploy the mic-fixed app and test it together.
```
