# Next-Session Plan — App completion + model delivery

_Prepared 2026-06-06 (evening, while you were away). Backed by a multi-agent investigation + research workflow with adversarial verification, then hands-on simulator diagnosis. Three of four research claims came back CONFIRMED; the mic-fix claim came back UNCERTAIN and I resolved it by running the app._

## TL;DR — what I did tonight, and the one thing that changes everything

1. **Fixed the dead mic button** (committed `411d97d`, simulator-verified). It was literally a block of text with no button — now it's a real "Allow microphone" button. I proved it renders + is tappable in the running iPhone 17 Pro Max simulator. 26/26 affected tests pass.
2. **Diagnosed the "warming up never finishes" — it is NOT a hang.** I ran the bundled app in the simulator and it loaded everything cleanly: **Whisper in ~33 s, LFM2 in 0.44 s**, warmup completed in ~40 s, reached the "ready" state. The device "warming forever" is the **one-time first-launch Neural-Engine compilation** of the ~600 MB Whisper model — the simulator skips that (CPU only), so the device's first launch is slow (minutes) then fast/cached forever after. **The bundled offline model load works — no regression.**
3. **Researched bundle-vs-download.** Recommendation below: **keep the bundle for now, fix the app, defer the delivery change.** It is not on the critical path to a testable app.

**The thing that changes everything:** your two complaints were two *different* problems, and neither means the app is broken. The mic button is now fixed. The "hang" is just a slow first-compile that needs a progress indicator (and is one-time). So the path to a working, testable app is short.

---

## Blocker 1 — Dead mic button ✅ FIXED (sim-verified, committed)

**Root cause:** `MeetingControlsView.notDeterminedContent` was a `VStack` of two `Text` views — no `Button`, no tap gesture. The only working "Allow microphone" button lived in dead code (`AudioCaptureView`, referenced only in `#Preview`). So a user whose mic permission was `.notDetermined` had no way to grant it from the main screen.

**Fix (committed `411d97d`):**
- `AudioCaptureViewModel.requestPermission()` — prompts (once) and publishes the result.
- `MeetingControlsViewModel.onRequestPermission` closure, wired in `wiring()` → `coordinator.captureViewModel.requestPermission()`.
- `notDeterminedContent` is now a real `Button("Allow microphone")`.
- Tests: publishes-granted, publishes-denied, + a simultaneous-double-tap consistency test.

**Verified:** simulator run with mic privacy reset → after warmup the screen exposes a tappable "Allow microphone" button (snapshot target `e24`) where before the only tap target was the History button.

**One nuance for the device:** the button only goes live once warmup completes (the screen shows a frozen placeholder during warmup). On the device, warmup is slow (Blocker 2), so during that window you'd still see the not-yet-live screen. That's addressed by the warmup progress UI in Blocker 2, not by more mic work.

---

## Blocker 2 — "Warmup never finishes" 🔬 DIAGNOSED (it's a slow first-compile, not a hang)

**What I proved in the simulator (machine idle, clean run):**
- `Loaded models for whisper size: large-v3 in 32.68s` (os_log), then LFM2 loaded (`Model Load Time: 0.44s`) and its warmup canary ran a successful inference. Warmup reached **"ready"** in ~40 s total.

**Why the device looks hung:** the simulator runs Whisper on CPU (`.cpuOnly`) and never does Neural-Engine specialization. The **device** must ANE-compile ~600 MB of weights on **first launch** — a documented multi-minute cold start — and the app has **no progress UI, no timeout, and no instrumentation**, so it's indistinguishable from a hang. It is one-time: the OS caches the specialization, so the 2nd launch is fast.

**Confidence:** HIGH (adversarial-verifier CONFIRMED). Residual risk: it could be a genuine device-side failure rather than slow compile — the device-log check below disambiguates. **Note:** switching to download-on-launch would NOT help — it's the same `.mlmodelc`, same compile.

**Next-session fix (needs the device; ready to implement):**
1. **Diagnose (no code):** Console.app → select the iPhone → filter by **process `ArigatoAI`** (not subsystem `com.argmax.whisperkit` — that string is unused; the live logger uses bundle id `com.jose.ArigatoAI`, category `Argmax`). Cold-launch, watch for `Loaded models for whisper … in X.XXs`. Also **time a 2nd launch** — if "warming" clears fast, ANE first-compile is confirmed. (Alt: `brew install libimobiledevice` → `idevicesyslog | grep -i whisper`.)
2. **Instrument + guard (small code change):** add `os_log` with timing around the Whisper load in `WhisperModelLoader`/`WhisperClientFactory`; add a **generous** timeout (set the threshold ABOVE the measured device compile time, e.g. 5 min — not the 120 s the research suggested, which would false-fire on a 3-min compile) that converts a true infinite hang into a visible error; add a **"Preparing models — first launch can take a minute or two"** progress message so a slow compile reads as progress, not a hang.
3. **(Optional) Isolation test:** temporarily set `ModelComputeOptions(audioEncoderCompute: .cpuAndGPU, textDecoderCompute: .cpuAndGPU)` — if "warming" then clears quickly on device, ANE first-compile is confirmed as the cause. Decide separately whether to ship `.cpuAndGPU` (may raise live-caption latency) or keep ANE + a progress UI.

---

## Model delivery — bundle vs download-after-install

You asked about downloading the models after the app installs (since users have internet anyway). Here's the honest framing: **this is an App-Store-distribution optimization, not a blocker.** You install to your own iPhone over the cable, which is not size-gated, so the 893 MB bundle is fine for testing now. And the warmup behaves identically whether the model is bundled or downloaded (same CoreML compile).

| Option | How it works | Best for | Effort |
|---|---|---|---|
| **Keep the bundle** (now) | Both models ship in the app via Git LFS (893 MB). Offline always. | Smallest path to a testable app today; personal use. | None |
| **SDK-native download-on-first-launch** ⭐ (later) | Flip Whisper to `WhisperKit.download()` + LFM2 to LEAP's downloader; both **cache for offline-after-first-run**; show a progress bar on first launch. App ships tiny. | App Store / TestFlight without the size warning. Honors "no network during meetings" (download is at setup, cached after). | Moderate |
| **Apple Background Assets** (later, polished) | Apple-hosted Managed Asset Packs (new in iOS 26), system-managed downloads, free CDN, ML models are a blessed asset type. | A polished public App Store release. | Higher |

**My recommendation:** **Keep the bundle now; defer delivery to App-Store prep.** When you do prep for distribution, go **SDK-native download-on-first-launch** (both SDKs support it + cache; the app already has dormant progress-UI scaffolding). Move to Background Assets only for a polished public release. For personal-use-first, keeping the bundle forever is perfectly fine. _(All confirmed against primary Apple/WhisperKit/LEAP sources.)_

---

## Recommended order of operations (next session)

1. **Device-log diagnosis of warmup** (5 min, no code) — confirm it's the slow ANE first-compile (vs a real failure). Time a 2nd launch.
2. **Warmup instrumentation + generous timeout + "preparing models…" progress UI** — so the device never looks hung. _(This also makes the device mic-fix exercisable, since the screen will clearly show warmup vs ready.)_
3. **Build to the device, grant mic via the now-fixed button, run a real JA↔EN pass.** ← "the app works" milestone.
4. **Only then**, decide + implement delivery (keep bundle / download-on-launch / Background Assets).

---

## Decisions for you (my recommendation first)

1. **Sequencing — fix blockers first & keep the bundle, or change delivery now?** → **Fix blockers first, keep the bundle.** Delivery isn't on the critical path.
2. **Warmup log tooling** → **Console.app filtered by process `ArigatoAI`** (zero install), plus add the in-code `os_log` + timeout regardless.
3. **Mic-fix scope** → Already shipped the wired-path fix. The warmup-window placeholder is better solved by the progress UI (step 2) than by hacking the frozen placeholder VM.
4. **Eventual delivery mechanism** → **SDK-native download-on-first-launch** when you reach App-Store prep; Background Assets for a polished public release; bundle is fine for personal use. _Can wait until the app works._

## Open risks
- Warmup *might* be a real device failure, not a slow compile — the device-log check settles it; the timeout makes any true hang visible.
- ~~The `ENABLE_USER_SCRIPT_SANDBOXING=NO` device-build fix (commit `d208263`) + all offline-Whisper + this mic fix are on **local checkpoints** ... run the gate before the next push.~~ **Stale (reconciled 2026-06-10):** the mic fix passed the three-reviewer gate on 2026-06-10 and everything through `d971157` is pushed to `origin/main`. See CURRENT_STATE.md for the current state of record.
- LFS quota: the offline-Whisper push already used ~636 MB of GitHub LFS; staying on the bundle keeps adding to it. Switching to download-on-launch later would let us drop the Whisper LFS assets.

## Tonight's commits — ~~local, not pushed~~ all pushed as of 2026-06-10
- `411d97d` — mic-button fix (+ tests), simulator-verified. _(Gated + pushed 2026-06-10 together with `183116a` and the gate fix `3d41090`.)_
- _(Earlier today, already pushed: the offline-Whisper bundling chain `82093a4`→`73a37f2`.)_
