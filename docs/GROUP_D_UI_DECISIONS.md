# Group D UI Decisions — Working Intent

**Status:** Working intent captured during Phase 5 Group C walkthrough. NOT locked. Subject to revision after MVP 1 device testing in real meetings reveals what actually works vs what sounded good on paper.

**Use:** Input for the Group D strategic walkthrough. The walkthrough will expand each decision into concrete screen layouts, component shapes, and SwiftUI structure.

---

## Foundational UX principle (drives everything below)

**Buttons exist only when they can be used. They morph contextually rather than appear/disable.**

The screen shows exactly one *primary* action at any moment. Secondary actions appear contextually. Disabled/grayed-out buttons are avoided — they add visual noise without giving the user anything actionable.

This matches Apple's own pattern in Voice Memos, Music, Notes, and other first-party apps. Reduces cognitive load. Prevents UI-level bugs (e.g., double-tap on STOP triggering duplicate cancel paths).

---

## Captured decisions

### 1. Transcript stays on screen after STOP

The transcript view does NOT clear when the user taps STOP. Both Japanese (top) and English (bottom) panels remain visible and scrollable. The user can re-read what was just said or copy lines without losing visual context.

**Rationale:** Wiping the screen on STOP would feel hostile. People glance back at meeting content to verify a key point or extract a quote.

**Implementation note:** STOP halts the pipeline but does not unmount the transcript view. State stays in memory until "New Transcript" is tapped (decision #2 button morphing).

### 2. Button morphing across meeting states

The primary button morphs through meeting states rather than appearing/disappearing alongside other buttons. The user always has exactly one primary action available, plus contextually relevant secondary actions.

| Meeting state | Primary button | Secondary button | Notes |
|---|---|---|---|
| Idle (first launch / after "New Transcript") | START | — | Clean slate, only one possible action |
| Recording | PAUSE | STOP | Two valid actions: pause for break, or end meeting |
| Paused | RESUME | STOP | Two valid actions: continue same session, or end meeting |
| Ended (post-STOP) | NEW TRANSCRIPT | (Export icon — see decision #4) | Meeting is done; the only forward action is starting a new one |

**Key observations:**
- The same physical button position morphs label and action based on state.
- STOP only exists during Recording and Paused states. After the meeting ends, STOP would be meaningless — it's replaced by NEW TRANSCRIPT.
- You can't press STOP twice — by design, STOP disappears the moment it's tapped.
- NEW TRANSCRIPT only exists post-STOP. Tapping it clears the transcript view, transitions to Idle state, and the button morphs back to START.

**Rationale:** Cleaner screen, fewer visual elements competing for attention, and prevents a class of double-tap bugs (e.g., two cancel paths triggered by rapid STOP taps).

### 3. Auto-save continuously during meetings

Transcripts auto-save to SwiftData on every sentence as it's translated. NOT on STOP only. NOT on user action. Continuous incremental save.

**Rationale:** App crashes happen. iOS backgrounds apps. Phone calls interrupt. A 1-hour meeting transcript should never vanish because of an environmental failure. SwiftData incremental writes are cheap.

**Trade-off flagged:** Every sentence triggers a SwiftData write. At ~150 sentences/hour, this should be negligible. Monitor for UI hitching during Phase 6 diagnostics; if observed, V3 entry to batch writes or move off main actor.

### 4. Export — scoped to completed transcripts only (history flow)

Export is NOT available during Recording or Paused states. The active meeting transcript view stays focused on capture, not sharing. Export becomes available once a transcript is complete, in three contexts:

**Context A — Ended state on active transcript view (just stopped):**
A share icon appears in the top-right after STOP is tapped. User can share the just-ended transcript directly without first navigating to history. Convenient for the common case of "meeting ended, AirDrop to my Mac immediately."

**Context B — Single transcript detail view (opened from history):**
When a user opens a past transcript from history, the share icon is visible top-right of that view. Tap → iOS Share Sheet for that single transcript.

**Context C — History list view, multi-select mode:**
Same UX as multi-select delete. User long-presses to enter multi-select mode, picks one or multiple transcripts, taps "Share" (alongside "Delete") in the bottom action bar. Triggers iOS Share Sheet with one or multiple files attached.

**Rationale:** Recording-state UI stays minimal — focused entirely on capture. Export lives in the completed-transcript flow where it semantically belongs. The user mental model is clean: capture is one mode, review/share/delete is another.

**Implementation note:** All three contexts use the same Share Sheet primitive (`UIActivityViewController` or SwiftUI `ShareLink`) with a different file payload (single file in A and B, multiple files in C).

**TBD for Group D:**
- Whether the Ended-state share icon (Context A) lives in the top bar (consistent with B and C) or as a secondary button next to NEW TRANSCRIPT
- File naming convention for exported transcripts (e.g., `arigato-2026-05-16-1422.txt` vs user-customizable)

### 5. Export format — plain text or markdown, both languages, with timestamps

Exported transcripts are plain text or markdown (final choice TBD in Group D, but NOT PDF for MVP 1). Both Japanese original and English translation included. Each sentence pair carries a timestamp.

**Example format (sequential):**

```
Arigato AI Transcript
2026-05-16 14:22 - 15:12 (50 min)

[14:22:03] こんにちは、皆さん。
[14:22:03] Hello, everyone.

[14:22:08] 今日のアジェンダを確認しましょう。
[14:22:08] Let's review today's agenda.
```

**Rationale:** Plain text is universal — opens in Gmail compose, Slack, Notes, Apple Mail, anywhere. Markdown is light formatting upgrade if useful. PDF adds dependencies and complexity for marginal MVP 1 benefit.

**Trade-off flagged:** PDF export is a possible Phase 7 enhancement if users request formal documents. Until then, plain text/markdown.

### 6. Multi-select delete AND share in transcript history

History view shows past meetings as a list (sort order, title format TBD). Long-press enters multi-select mode. User taps multiple meetings via checkboxes. Bottom action bar shows "Share N transcripts" AND "Delete N transcripts" (or icons for each).

**Rationale:** Standard iOS pattern from Mail, Photos, Notes. Users already know it. SwiftData makes per-record delete trivial. Multi-select share is the natural pairing — same selection model, different action.

**TBD for Group D:**
- Title format (manual entry, auto from first sentence, timestamp, or some hybrid)
- Sort order (newest first, by duration, by language pair)
- Whether single-tap delete (swipe-to-delete from list) is also offered alongside multi-select
- Whether single-tap export (swipe-to-share) is offered alongside multi-select

### 7. Pause/Resume — keep single meeting intact across breaks

During active recording, the secondary STOP button is paired with a primary PAUSE button. Tapping PAUSE:

- Temporarily halts audio capture (Whisper stops receiving frames)
- Any in-flight sentence finishes translating naturally (~sub-second)
- Translation actor stays alive, just idle
- Transcript view stays mounted
- Meeting session record in SwiftData stays open and continues to grow when resumed
- UI shows "PAUSED" indicator
- Primary button morphs from PAUSE to RESUME

Tapping RESUME:
- Restarts audio capture in the same meeting session
- Transcript continues in the same SwiftData record
- Primary button morphs back to PAUSE

**Rationale:** Long meetings have natural breaks — coffee, agenda transitions, side conversations. Without pause, the user either keeps recording during the break (wastes battery, fills transcript with noise) or taps STOP (creates two separate transcripts for one logical meeting). Pause is the right primitive for the "5-min break in a 1-hour meeting" use case.

**Technical note:** Pause is primarily a UI state. The translation actor pipelines don't need a special "paused" mode — pause just means "stop feeding audio in." No queue drain, no state restoration logic needed. The cancel mechanism (Group C Step 8) is reserved for STOP only.

**Trade-off flagged:** If a sentence is mid-translation when pause is tapped, that sentence completes before audio stops. Sub-second delay, acceptable. If a future enhancement needs to also pause inference of an in-flight sentence (rare), that would need pipeline changes — defer until a real use case surfaces.

### 8. Undo toast on STOP — 3-5 second window

When user taps STOP, a toast appears at the bottom of the screen: "Meeting ended. Tap to resume." with a 3-5 second visible window. If the user taps the toast, the meeting resumes as if STOP had not been pressed (button morphs back to PAUSE+STOP for Recording state). After the window expires, the toast dismisses and STOP is final — the button morphs to NEW TRANSCRIPT.

**Rationale:** Recovers from genuine accidental taps without adding confirmation friction to every intentional STOP. Modern iOS pattern (Gmail uses this for sent mail). Auto-save (decision #3) is the real safety net — even if the undo window expires, the transcript is preserved in history.

**Trade-off flagged:** Implementation requires holding the meeting session in a "stoppable but not yet stopped" state for the undo window. Mild complexity, acceptable. Alternative considered and rejected: explicit confirmation dialog before STOP. Rejected because confirmation creates friction on every STOP, and intentional STOPs vastly outnumber accidental ones.

**Interaction with button morphing (decision #2):** During the undo window, the button could either (a) stay as PAUSE+STOP visually until the window expires, OR (b) immediately morph to NEW TRANSCRIPT but with the toast available for recovery. Group D walkthrough will decide.

---

## Decisions explicitly deferred to Group D walkthrough

These came up during the Group C discussion but need full Group D treatment, not just intent capture:

- **Transcript visual layout:** Split-screen (Japanese top, English bottom)? Vertically interleaved with timestamps? Side-by-side with horizontal scroll? Group D walkthrough will lock this.
- **Scroll behavior:** When new sentence arrives, auto-scroll to bottom? Or only auto-scroll if the user is already at the bottom? Floating "scroll to bottom" arrow when user has scrolled up?
- **Typography:** System fonts (SF Pro / Hiragino Sans for Japanese)? Custom (Geist family, possibly Geist Pixel for branding moments)? Reading priority on transcript text means CJK rendering takes precedence — pixel fonts likely reserved for branding/labels, not transcript content.
- **Color and theme:** Dark mode by default? Light mode? Adaptive to system setting?
- **Recording indicator:** What does "actively recording" look like? Pulsing dot? Waveform? Both?
- **History view design:** List vs grid? Per-meeting metadata visible (duration, sentence count, languages)? Search/filter?
- **Title generation for meeting history:** Auto-derived from first sentence (Japanese? English? Both?), or timestamp-only, or user-prompted at STOP, or editable post-meeting in history view?
- **Error states:** What does the UI show if LFM2 fails to load mid-meeting? If Whisper fails? If translation lags behind audio significantly?
- **Undo toast button morphing timing:** Does the primary button stay as PAUSE/STOP during the undo window, or immediately morph to NEW TRANSCRIPT? (decision #8 detail)
- **Ended-state share icon placement:** Top bar vs secondary button position? (decision #4 detail)

---

## Decisions NOT yet captured (worth raising in Group D walkthrough)

- **First-launch experience:** What happens when user opens the app for the first time? Model download progress? Microphone permission flow? Brief tutorial overlay?
- **Settings screen:** Cache size, model selection (if multiple models ever ship), default export format, retention policy for history?
- **Privacy reassurance:** Does the UI ever surface "on-device, no cloud" messaging? Where?
- **Accessibility:** VoiceOver labels on transcript? Dynamic Type support? Reduced Motion?
- **Navigation between active view and history:** Tab bar? Hamburger menu? Top-bar nav? How does the user get to history during/between meetings?

---

## Revision policy

These decisions are **working intent, not contracts.** After MVP 1 ships and the app is tested in real meetings, expect to revise. Real usage will reveal:

- Whether the auto-save cadence is right (or causes UI hitching)
- Whether pause is actually used or whether users prefer STOP-and-start-new
- Whether multi-select delete/share is the right granularity or if single-swipe actions are preferred
- Whether the undo toast window is long enough (3s vs 5s vs 10s)
- Whether export format needs more options (PDF, CSV, JSON for downstream tools)
- Whether the button morphing pattern feels right or whether persistent buttons would actually be clearer
- Whether the "no export during recording" decision holds up — users might request mid-meeting export

Treat this doc as the starting point for Group D, not the ending point. Update after each MVP usage cycle.

---

**Original source:** Captured from Claude.ai Group C walkthrough conversation, 2026-05-16. User: Jose. Revise during Group D walkthrough and after MVP 1 testing.
