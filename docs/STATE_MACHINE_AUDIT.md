# MeetingSessionPhase × UI Surface — State-Machine Audit

**Filed**: 2026-05-17. End-of-Group-D three-reviewer gate, Pass 1 (@code-reviewer). Gate queue item #1.

**Verdict**: 0 BLOCKING gaps, 6 INFO gaps (filing deferred to end-of-gate batch with @ui-reviewer + @git-historian findings).

**Cross-references**:

- `CLAUDE.md` § "Concurrency design discipline" — the controls VM's gesture-serialization scheduling assumption is documented on `MeetingControlsViewModel` and locked by named violation test `vm_concurrentTapStartAndTapPause_bothClosuresInvoked_lastInFlightActionWins`.
- `CLAUDE.md` § "Architecture rules" — pipeline-stage isolation: each phase × surface cell crosses at most one actor hop.
- `docs/GROUP_D_UI_DECISIONS.md` — locked UI decisions referenced per cell (UI #3, #4, #5, #6, #7, #9, #11, #13, #14, #15, #16, #17, #18).
- `docs/V3_BACKLOG.md:1137` — STOP-#5 process-discipline V3 entry (verdict (A) Pass 1: trampoline code accepted as-is).

## Authoritative phase enumeration

Verified against `ArigatoAI/Session/MeetingSessionPhase.swift:36-52`:

| # | Case | Associated values |
|---|------|------|
| 1 | `.idle` | — |
| 2 | `.recording` | `meetingID, startedAt` |
| 3 | `.paused` | `meetingID, startedAt, pausedAt` |
| 4 | `.stoppingWithUndoWindow` | `meetingID, startedAt, deadline` |
| 5 | `.ended` | `meetingID, startedAt, endedAt` |

## Phase × Surface matrix

Six UI surfaces, each cell citing file:line of source-of-truth:

| Phase | Controls badge | Controls primary button | Controls secondary button | Split-screen rendering | History rendering | ContentView routing branch |
|---|---|---|---|---|---|---|
| **`.idle`** | None — `badgeDisplay(for:.idle, now:)` returns `nil` (`MeetingControlsView.swift:622-623`); the `TimelineView` body emits no view. | `START` (`MeetingControlsView.swift:662-663`) | None — `secondaryButton(for:.idle)` returns `nil` (`MeetingControlsView.swift:682-683`) | Empty-state placeholder ("listening…" / "Spoken Japanese…") because `ContentView.makeTranscriptModel()` returns `nil` for `.idle` (`ContentView.swift:198`), so `TranscriptLiveView.transcriptList` falls back to `emptyState` (`TranscriptLiveView.swift:246-248`). | No row added — `start(at:)` is what creates the persisted `Meeting` row (`MeetingSession.swift:179-200`); list shows whatever was persisted before. | (onboarding-complete) `mainContent` → `NavigationStack { TranscriptLiveView(...) }` (`ContentView.swift:101-150`). (onboarding-pending) `OnboardingView` (`ContentView.swift:102-105`). |
| **`.recording(meetingID, startedAt)`** | `REC mm:ss`, pulsing red dot, recomputed from `context.date` at 1Hz (`MeetingControlsView.swift:624-629, 169-184`). | `PAUSE` (`MeetingControlsView.swift:664-665`) | `STOP` (`MeetingControlsView.swift:684-685`) | `TranscriptSplitScreenView` rendering persisted sentences for `meetingID`, with `sentencesDidUpdate` callback installed → reload trigger bumps refresh on each successful persist (`ContentView.swift:166-183`; `TranscriptSplitScreenView.swift:87-89`). Live partial chunks accumulate in `MeetingSession.liveChunks` but are NOT rendered by the split-screen view (it reads `MeetingDetail.SentenceProjection` only, not `liveChunks`). | Row appears in `MeetingListView` with `endedAt = nil` → duration column renders `"—"` (`MeetingListRow.swift:90-95`). Auto-save (per UI #6) means sentences land continuously; the row itself appears as soon as `start()` persists the `Meeting`. | Same as `.idle` row. |
| **`.paused(meetingID, startedAt, pausedAt)`** | `PAUSED mm:ss`, frozen at `pausedAt - startedAt`, ignores `context.date` (locked by `formatter_badgeDisplay_paused_freezesAtPauseTime_evenIfNowIsLater`; `MeetingControlsView.swift:630-637`). | `RESUME` (`MeetingControlsView.swift:666-667`) | `STOP` (`MeetingControlsView.swift:686-687`) | Same as `.recording` — `activeMeetingID(in:)` returns the `meetingID` for `.paused` (`ContentView.swift:195`); the same split-screen VM is alive. Audio engine keeps running through pause (UI #7; `MeetingCoordinator.swift:181-189`); completions arriving during `.paused` still persist via `MeetingSession.process(event:)` (`MeetingSession.swift:511-521`). | Row continues with `endedAt = nil` → `"—"`. Pause does not write a persistence side-effect (UI #7 — session-state-only). | Same as `.recording`. |
| **`.stoppingWithUndoWindow(meetingID, startedAt, deadline)`** | `REC mm:ss`, pulsing red — badge intentionally continues to signal "still recording" semantically until the deadline fires or undo lands (`MeetingControlsView.swift:638-646`). | `NEW TRANSCRIPT` (force-commit branch) (`MeetingControlsView.swift:668-671`). Tap path: VM detects `.stoppingWithUndoWindow` and runs `onFinalizeStop` then `onNewTranscript` in sequence (`MeetingControlsView.swift:577-597`). | None — `secondaryButton(for:.stoppingWithUndoWindow)` returns `nil` (`MeetingControlsView.swift:688-689`). The morphing table (UI #4) replaces the secondary slot with the undo overlay. | Same as `.recording` — `activeMeetingID(in:)` returns the `meetingID` (`ContentView.swift:196`); split-screen continues. `UndoStopToastView` overlays the controls cluster (`MeetingControlsView.swift:243-251`) with a 1Hz countdown from `deadline - context.date` (`UndoStopToastView.swift:50-83`). | Row continues with `endedAt = nil` → `"—"`. `finalizeStop` (the only writer of `endedAt`) has not run yet. | Same as `.recording`. |
| **`.ended(meetingID, startedAt, endedAt)`** | `mm:ss` final duration (no `REC` prefix, no pulse), `BadgeKind.ended` glyph (system stop square) (`MeetingControlsView.swift:647-653, 206-210`). | `NEW TRANSCRIPT` (`MeetingControlsView.swift:672-673`) | `Share` (`MeetingControlsView.swift:690-691`). The controls-cluster `Share` dispatch is a documented no-op (`MeetingControlsView.swift:275-279`); the functional `ShareLink` lives in `MeetingDetailView`'s toolbar (`MeetingDetailView.swift:119-127`) per UI #9 Context B. See Gap #4. | Split-screen still renders persisted sentences for `meetingID` because `activeMeetingID(in:)` returns the `meetingID` even for `.ended` (`ContentView.swift:197`). The split-screen VM stays mounted post-end per UI #5. `sentencesDidUpdate` callback is still installed but no new sentences arrive (pipeline torn down by `MeetingCoordinator.finalizeStop`, `MeetingCoordinator.swift:239-243`). | Row updates: `endedAt` now non-nil, duration column renders `"N min"` (`MeetingListRow.swift:90-95`). Title rewritten from `firstEnglishSentence` via `MeetingSession.finalizeStop` (`MeetingSession.swift:376-394`). | Same as `.recording`. |

## Cross-product analyses

### Onboarding-pending × each phase

`ContentView.body` (`ContentView.swift:101-108`) evaluates `!onboardingComplete && !bootstrapper.onboardingStore.hasCompletedOnboarding` BEFORE the phase routing. When true, **`OnboardingView` renders regardless of `session.phase`**. Structurally fine for MVP-1: the first launch is always `.idle` because the session is constructed inside `makeCoordinator` (`AppBootstrapper.swift:630-644`) with `phase = .idle` per `MeetingSession.swift:59`. See Gap #1 for the unenforced invariant.

### Pre-coordinator warmup window × each phase

While `bootstrapper.coordinator == nil`, `controlsModel` falls back to `MeetingControlsViewModel.disabled()` (`ContentView.swift:121-123`). `.disabled()` reports `permissionStatus: .notDetermined` (`MeetingControlsView.swift:444-457`), so the controls surface shows the `notDeterminedContent` branch (`MeetingControlsView.swift:103-113`) — **no phase-driven badge or button is reachable until coordinator publishes**. The history toolbar is also gated on `bootstrapper.meetingStore != nil` (`ContentView.swift:138`). Aligned with the documented sub-50ms warmup window.

### StartupErrorView routing

`ArigatoAIApp.body` (`ArigatoAIApp.swift:57-67`) checks `startupError == nil` BEFORE rendering `ContentView`. So `StartupErrorView` is reached on (a) container-init failure, (b) Whisper `LoaderState.failed`, or (c) LFM2 `LFM2LoaderState.failed`. In any of those branches, `ContentView` is never entered — none of the phase × surface cells above are rendered. Correct fail-closed behavior.

## Gap analysis

All 6 gaps classified INFO. Filing to V3 deferred until end-of-gate batch with @ui-reviewer + @git-historian outputs.

### Gap #1 — Onboarding-pending × non-`.idle` phase is structurally unreachable, but the assertion is implicit. **[LOW / INFO]**

`ContentView.swift:102-105` always wins the onboarding branch when the persistent flag is false, regardless of phase. If a test or future call site flips `session.phase` to non-`.idle` while onboarding has not completed (e.g., test fixture pre-seeds `phase = .recording`), the user would see `OnboardingView` while a meeting "is recording" behind it. The session would persist sentences against a row the user never saw. **Reachability**: no current production path constructs a non-`.idle` session before onboarding completes — the coordinator is only built inside `AppBootstrapper.startPrewarm`'s detached tail (`AppBootstrapper.swift:598-611`), and onboarding renders concurrently with prewarm but does not interact with the session. **Recommended action**: V3 doc-comment cross-reference on `ContentView.body` noting the assumption "session phase is `.idle` when onboarding is incomplete."

### Gap #2 — Controls surface in `.notDetermined` / `.denied` / `.restricted` permission states ignores phase entirely. **[LOW / INFO]**

`MeetingControlsView.body` (`MeetingControlsView.swift:74-85`) switches on `model.permissionStatus()` BEFORE consulting `model.phase()`. The `notDetermined`/`denied`/`restricted` branches render permission-flow content with no badge, no buttons, no phase-derived state. If the OS revokes microphone permission mid-meeting (a `.recording` or `.paused` or `.stoppingWithUndoWindow` phase), the controls surface flips to the denied content — the user loses the STOP affordance and the undo toast. The session would continue persisting events because no session method is called. **Reachability**: the permission-revoked mid-meeting case requires the user to background the app and revoke in Settings; on return, `AudioCaptureViewModel.permissionStatus` would re-read and report `.denied`. Audio engine would error on the next frame, breaking the pipeline naturally. **Recommended action**: V3 entry — add an explicit overlay path that surfaces "permission revoked — STOP to finalize" affordance when phase is non-`.idle` and permission is denied. Cascade-to-@ui-reviewer for visual-treatment severity.

### Gap #3 — `.ended` × split-screen: `sentencesDidUpdate` callback remains installed but pipeline is torn down. **[LOW / INFO]**

`MeetingCoordinator.finalizeStop` (`MeetingCoordinator.swift:239-243`) stops the pipeline before calling `session.finalizeStop`. After transition to `.ended`, the session's `sentencesDidUpdate` callback is still bound to the split-screen VM, but no `.completed` events are emitted because the pipeline is dead. **Impact**: none in practice. The slot is overwritten on the next render (`ContentView.swift:179-181`); `.idle` → next `.recording` will install a fresh `[weak vm]` closure for the new meeting's VM. **Recommended action**: none. Tracked here for matrix completeness.

### Gap #4 — Controls cluster `Share` placeholder vs MeetingDetailView functional ShareLink. **[MED / INFO]**

`MeetingControlsView.dispatchSecondary(.share)` is a no-op (`MeetingControlsView.swift:275-279`) with the comment "Step 13 will wire a real `ShareLink`." The functional share IS wired in `MeetingDetailView.swift:119-127`. In the `.ended` phase, the user sees a `Share` button on the controls cluster that does nothing. The "real" share is in History → meeting detail → toolbar. User-visible dead button. **Reachability**: real production path — every meeting that ends will show this. **Recommended action**: cascade to @ui-reviewer (UI #9 Context A intent — ship no-op intentionally OR hide until wired).

### Gap #5 — `MeetingSession.process(event:)` doc-comment on lines 513-515 is slightly misleading. **[LOW / INFO]**

`MeetingSession.swift:512-521` says "If we're paused or stopping, still persist." The actual behavior: paused, stopping, AND ended-or-idle branches enter the `guard case let .recording` else clause; the call to `activeMeetingID()` returns the ID for paused/stopping but `nil` for ended/idle, so persist runs for paused/stopping only. The comment names paused and stopping but the code also handles ended/idle (by silently dropping). Doc-comment doesn't lie about the contract, but it's incomplete. **Recommended action**: V3 doc-comment polish — extend the comment to "If we're paused or stopping, still persist; if ended or idle, silently drop the event."

### Gap #6 — `MeetingListView` error state has no rendered surface when meetings collection is non-empty. **[MED / INFO]**

`MeetingListView.swift:117-136`. The outer branch is `if meetings.isEmpty && loadError == nil` → empty/search-empty, `else` → `listContent`. When `loadError != nil`, neither branch renders the error. The error sits in `loadError` and is never surfaced to the user. Not strictly a state-machine cell but a UI rendering gap reachable during any phase that hits an actor-hop error mid-list (rare in MVP-1; main candidate is SwiftData fetch error). **Reachability**: low in MVP-1 (single-user device, no remote backing), but real. **Recommended action**: V3 entry — add an inline error banner above `listContent` when `loadError != nil`. Cascade-to-@ui-reviewer for visual-treatment severity.

## Concurrency-design-discipline coverage spot-check

Per `CLAUDE.md` § "Concurrency design discipline", each cell whose correctness depends on a scheduling assumption must have a named violation test enforcing it. Spot-check against the cells:

- **`.recording` × split-screen**: depends on `sentencesDidUpdate` synchronous-callback contract. Enforced by `meetingSession_sentencesDidUpdateBlocks_doesNotStallEventPump` (`MeetingSessionTests.swift:751-792`) — drives a 20ms CPU-spin callback against a 10-sentence burst, asserts all 10 land.
- **`.paused`/`.stoppingWithUndoWindow` × controls badge**: depends on `MeetingControlsFormatter`'s freeze-at-pause contract. Enforced by `formatter_badgeDisplay_paused_freezesAtPauseTime_evenIfNowIsLater`.
- **`.stoppingWithUndoWindow` × controls primary `NEW TRANSCRIPT`**: depends on tap-method ordering (`onFinalizeStop` then `onNewTranscript`). Enforced by named test on `MeetingControlsViewModel`.
- **`.recording` × history row append**: depends on auto-save subscriber chain. Covered by Step 8 wiring tests (`AppBootstrapperMeetingWiringTests.swift`).

No coverage gaps surfaced from the scheduling-assumption pass.
