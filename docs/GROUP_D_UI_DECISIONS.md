# Group D UI Decisions — Locked Intent

**Status:** Locked intent from the Phase 5 Group D strategic walkthrough (2026-05-16). These decisions feed directly into @feature-planner dispatch.

Subject to revision after MVP 1 device testing in real meetings reveals what actually works vs what sounded good on paper.

---

## Foundational UX principle (drives everything below)

**Buttons exist only when they can be used. They morph contextually rather than appear/disable.**

The screen shows exactly one *primary* action at any moment. Secondary actions appear contextually. Disabled/grayed-out buttons are avoided — they add visual noise without giving the user anything actionable.

This matches Apple's own pattern in Voice Memos, Music, Notes, and other first-party apps. Reduces cognitive load. Prevents UI-level bugs (e.g., double-tap on STOP triggering duplicate cancel paths).

---

## Locked decisions

### 1. Transcript layout — split top/bottom, timestamps for correlation

Japanese transcript fills the top half of the screen. English translation fills the bottom half. Each half is its own independent scroll region. Sentence pairs are correlated via timestamps shown alongside text in both halves.

**Rejected alternatives:**
- Interleaved sentence pairs (better for post-meeting review, worse for live glance)
- Side-by-side columns (iPhone portrait too narrow for comfortable reading of either language)

**Rationale:** Primary use case is live meeting glance. Users look up for Japanese (source verification) or down for English (understanding). Timestamps let users mentally pair sentences when scrolling back.

### 2. Scroll behavior — auto-follow at bottom, stay-put when scrolled up, unified return arrow

When user is at the bottom of either half, new sentences scroll into view automatically.
When user scrolls up to re-read past content, incoming sentences arrive in the data layer but the view does NOT yank back to the bottom.
A unified "scroll to bottom" arrow appears whenever **either** half is scrolled up from bottom. Tapping the arrow smoothly scrolls **both** halves to the bottom simultaneously, resuming auto-follow.

**Implementation note:** track scroll position per-half independently for "am I at bottom?" detection. Arrow visibility = OR across both halves. Arrow action = scroll both to bottom in a single coordinated animation.

**Rationale:** Industry-standard pattern (iMessage, Slack, Discord). User control during scrollback + one-tap return to live.

### 3. Recording indicator — status badge with state + elapsed time

A status badge at the top of the active meeting view morphs through meeting states. The same badge slot shows different content based on state (parallel to button morphing in decision #4).

| State | Badge content |
|---|---|
| Recording | `🔴 REC 03:42` (red dot pulses, timer updates every second) |
| Paused | `⏸ PAUSED 03:42` (timer frozen, no pulse) |
| Ended | `■ 50:12` (final duration, no pulse) |

**Visual design:** integrates with the final UI theme of the app — colors, font, padding all match the broader visual system. Not a standalone "stamp" but a coherent component.

**Rationale:** Combines state + elapsed time in one element. Glanceable. Battery cost negligible (text update once per second). Pulse cue maintains the iOS "live recording" affordance users expect.

**Rejected alternatives:**
- Pulsing dot only (no elapsed time, less informative)
- Live waveform (eats screen space, battery cost, visual noise)

### 4. Button morphing across meeting states

The primary button morphs through meeting states. The user always has exactly one primary action available, plus contextually relevant secondary actions.

| Meeting state | Primary button | Secondary button | Notes |
|---|---|---|---|
| Idle (first launch / after "New Transcript") | START | — | Clean slate, only one possible action |
| Recording | PAUSE | STOP | Two valid actions: pause for break, or end meeting |
| Paused | RESUME | STOP | Two valid actions: continue same session, or end meeting |
| Ended (post-STOP) | NEW TRANSCRIPT | Share icon (top-right) | Meeting is done; the only forward action is starting a new one |

**Key observations:**
- The same physical button position morphs label and action based on state.
- STOP only exists during Recording and Paused states. After the meeting ends, STOP is replaced by NEW TRANSCRIPT.
- You can't press STOP twice — STOP disappears the moment it's tapped.
- NEW TRANSCRIPT only exists post-STOP. Tapping it clears the transcript view, transitions to Idle state, and the button morphs back to START.

### 5. Transcript stays on screen after STOP

The transcript view does NOT clear when the user taps STOP. Both Japanese (top) and English (bottom) panels remain visible and scrollable. The user can re-read content or initiate export without losing visual context.

**Implementation note:** STOP halts the pipeline but does not unmount the transcript view. State stays in memory until "New Transcript" is tapped (button morphing in decision #4).

### 6. Auto-save continuously to SwiftData

Transcripts auto-save to SwiftData on every sentence as it's translated. NOT on STOP only. Continuous incremental save.

**Rationale:** App crashes happen. iOS backgrounds apps. Phone calls interrupt. A 1-hour meeting transcript should never vanish because of an environmental failure.

**Trade-off flagged:** Every sentence triggers a SwiftData write. At ~150 sentences/hour, this should be negligible. Monitor for UI hitching during Phase 6 diagnostics; if observed, V3 entry to batch writes or move off main actor.

### 7. Pause/Resume — keep single meeting intact across breaks

During active recording, tapping PAUSE:
- Temporarily halts audio capture (Whisper stops receiving frames)
- Any in-flight sentence finishes translating naturally (~sub-second)
- Translation actor stays alive, just idle
- Transcript view stays mounted
- Meeting session record in SwiftData stays open
- UI shows "PAUSED" indicator
- Primary button morphs to RESUME

Tapping RESUME:
- Restarts audio capture in the same meeting session
- Transcript continues in the same SwiftData record
- Primary button morphs back to PAUSE

**Technical note:** Pause is primarily a UI state. The translation actor pipelines don't need a special "paused" mode. The cancel mechanism (Group C Step 8) is reserved for STOP only.

### 8. Undo toast on STOP — 5-second window

When user taps STOP, a toast appears at the bottom of the screen: "Meeting ended. Tap to resume." with a 5-second visible window. Tap → meeting resumes as if STOP had not been pressed. After window expires → STOP is final, button morphs to NEW TRANSCRIPT.

**Rationale:** Recovers from accidental taps without adding confirmation friction. Modern iOS pattern (Gmail uses this for sent mail). Auto-save (decision #6) is the real safety net.

**Implementation note:** Hold meeting in a "stoppable but not yet stopped" state for the undo window. During the window, the primary button immediately morphs to NEW TRANSCRIPT, but the toast offers recovery — cleaner under decision #4's "one primary action" principle than holding the previous button state.

### 9. Export — scoped to completed transcripts only

Export is NOT available during Recording or Paused states. Available in three contexts, all using iOS Share Sheet:

**Context A — Ended state on active transcript view:** Share icon top-right after STOP. Share the just-ended transcript without navigating to history first.

**Context B — Single transcript detail view (opened from history):** Share icon top-right of detail view.

**Context C — History list multi-select mode:** Same UX as multi-select delete. Long-press to enter multi-select, pick one or multiple transcripts, "Share N" + "Delete N" actions in bottom action bar.

**Implementation note:** All three contexts use SwiftUI's `ShareLink` or `UIActivityViewController` with the appropriate file payload.

### 10. Export format — plain text or markdown, both languages, with timestamps

Exported transcripts are plain text or markdown (final choice TBD during implementation). Both Japanese original and English translation included sequentially with timestamps.

**Example format:**

```
Arigato AI Transcript
2026-05-16 14:22 - 15:12 (50 min)

[14:22:03] こんにちは、皆さん。
[14:22:03] Hello, everyone.

[14:22:08] 今日のアジェンダを確認しましょう。
[14:22:08] Let's review today's agenda.
```

**Trade-off flagged:** PDF export is a possible Phase 7 enhancement if users request formal documents. Plain text is universal — opens anywhere.

### 11. Navigation between active view and history — top-bar icon

History is accessed via a history icon (clock or list icon) in the top-right of the active meeting view (next to the export share icon if both are visible). Tap → push to history screen. Back button on history screen → return to active view.

**Rationale:** Switching between active meeting and history is NOT frequent. Optimizing for the rare action with a permanent tab bar would cost vertical real estate that the split-screen transcript layout needs. Top-bar icon is iOS-native, costs zero permanent space.

**Critical behavior:** Active meeting keeps recording in the background when user navigates to history. TranslationActor and Whisper stay alive regardless of which view is on screen. Auto-save continues. When user returns, transcript has caught up.

**Rejected alternatives:**
- Tab bar (eats ~50pt permanent vertical space)
- Hamburger menu (anti-pattern on iOS per Apple HIG)

### 12. Meeting title generation

**MVP 1:** Auto-derived from first English sentence + timestamp.
- Format: `[Day Time] — [First English sentence, truncated to ~40 chars]`
- Example: `Sat 2:22 PM — Hello, everyone. Let's review today's...`
- Fallback when no translation happened: just timestamp (`Sat 2:22 PM`)
- No edit affordance in MVP 1 (deferred to keep MVP scope tight)

**Phase 6+:** Apple Foundation Models on-device summarization.
- Run full English transcript through Foundation Models after STOP
- Prompt: "Generate a concise 5-8 word title summarizing this meeting's main topic"
- Replaces first-sentence title generation; storage shape unchanged
- Clean upgrade path: only the title-generation function swaps

**V3 entry to file:** "Migrate meeting title generation from first-sentence to Foundation Models summarization. Trigger: Phase 6 post-meeting cleanup features begin."

### 13. History — multi-select delete + share

History view shows past meetings as a list, sorted newest first. Long-press enters multi-select mode. User taps multiple meetings via checkboxes. Bottom action bar shows "Share N" + "Delete N" actions.

**Per-meeting card metadata to show in list:**
- Title (decision #12)
- Date + time
- Duration (e.g., "50 min")

**Deferred to implementation:**
- Sort options beyond newest-first (by duration, by language pair)
- Single-tap swipe actions (swipe-to-delete, swipe-to-share) alongside multi-select

### 14. History search — debounced, full-content, filter-in-place

Search icon in history view top bar. Tap → expands to search field. As user types:

- Search scope: meeting title + every English `translatedText` + every Japanese `sourceText` across all sentences in all meetings
- Implementation: SwiftData `#Predicate` with `localizedStandardContains` across title, sourceText, translatedText
- Debounce: 300ms after typing stops before query fires
- Display: filter the history list in-place — non-matching meetings hidden, matching meetings show a snippet preview of the matched text on the card

**V3 entry to file:** "Migrate history search to SQLite FTS5 — trigger: search latency exceeds ~200ms on real device with real data, OR transcript volume exceeds ~50K sentences and `LIKE`-based queries feel sluggish. Cost: ~1-2 days to add FTS5 virtual table alongside SwiftData schema."

**Deferred to Phase 6+:**
- Search results screen showing matching sentences with jump-to-sentence links (richer than in-place filter)
- Search across language directions (e.g., search English and find Japanese matches)

### 15. Error state UI

| Failure | UI surface |
|---|---|
| LFM2 translation error (transient) | Inline grey italic marker in English half: `[Translation failed — retrying]` |
| Whisper / mic failure | Toast at top + state badge changes color to red |
| Queue full (drop-newest fires) | Subtle inline marker `[...]` in English half |

**Rationale:** Inline markers contextualize WHERE the failure happened in the transcript. Toast + colored badge reserved for pipeline-blocking failures where the user must act.

**Trade-off flagged:** Inline markers will appear in exported transcripts. Acceptable — better than silent gaps. Future enhancement: filter at export time if users complain.

### 16. First-launch experience

**Strategy:** Models downloaded on first launch + 2-screen minimal onboarding.

**Screen 1 — Value prop:**
- Title: "Translate meetings in real time"
- Body: "Japanese-English, fully on-device. Your audio never leaves your phone."
- Primary button: "Get Started"

**Screen 2 — Permissions + model download:**
- "Setting up Arigato AI..."
- Microphone permission request fires here
- Model download progress bars (Whisper, then LFM2)
- Estimated time + tip: "Connect to Wi-Fi for faster setup"
- Primary button (grayed until done): "Start translating"

After Screen 2 → main app view in Idle state with START button.

**Model storage location:** `Application Support/` (not iCloud-backed, persists across app updates, not OS-purged like `Caches/`).

**Mitigations for slow networks:**
- Pause/resume download if user backgrounds the app
- Allow retry on download failure
- Show granular progress per-file

**V3 entry to file:** "First-launch download UX measurement — measure real download times on cellular vs Wi-Fi after MVP 1 testing; if >2 min on Wi-Fi feels too long, investigate bundling a smaller Whisper variant or showing more granular progress."

### 17. Theme — system-adaptive

App respects iOS-wide light/dark mode setting. No in-app theme picker for MVP 1. SwiftUI's semantic colors handle most of the adaptation automatically.

**Rejected alternatives:**
- Force one theme (ignores user preference)
- In-app theme picker (defer to Phase 6+)

### 18. Typography — system fonts, custom deferred

| Surface | Font |
|---|---|
| Transcript text (Japanese + English) | System — SF Pro for Latin, Hiragino Sans for Japanese (iOS handles language-aware fallback automatically) |
| App chrome (buttons, settings, labels) | System — SF Pro Display |
| Branding moments (app icon text, "ARIGATO AI" wordmark, status badge) | System for MVP 1, Geist or Geist Pixel deferred to Phase 6+ enhancement pass |

**Rationale:** CJK readability is non-negotiable. System fonts handle CJK better than any custom font we could bundle. Custom typography is a visual polish concern, not a functional one — defer to Phase 6+.

### 19. Settings — minimal for MVP 1

Two sections only:

**About:**
- Version number
- "Fully on-device" privacy reassurance
- Link to project info / GitHub repo

**Storage:**
- Show current LFM2 cache size + transcript count
- Button: "Clear cache" (with confirmation)
- Button: "Delete all transcripts" (with strong confirmation)

**Deferred to Phase 6+:**
- Diagnostic logs toggle (ships with V3 #46 diagnostic feature)
- Default export format selection
- History retention policy (auto-delete old transcripts)
- Model selection (when multiple models ship)

### 20. SwiftData schema — one-to-many with cascade delete

**Entity: `Meeting`**
- `id: UUID` — primary key
- `startedAt: Date`
- `endedAt: Date?` — nil while meeting is active
- `title: String` — auto-generated per decision #12
- `sentences: [Sentence]` — `@Relationship(deleteRule: .cascade)`

**Entity: `Sentence`**
- `id: UUID`
- `meeting: Meeting` — inverse relationship
- `timestamp: Date`
- `sourceLanguage: String` — "ja" or "en"
- `sourceText: String` — original Japanese or English
- `translatedText: String` — translation in the other language
- `sourceSegmentID: UUID` — upstream Whisper segment ID (debugging)

**Migration policy for MVP 1:** Wipe-on-schema-mismatch. No formal VersionedSchema. Acceptable because MVP 1 testing is solo on Jose's device — losing test transcripts on schema change is fine.

**Storage location:** SwiftData default — `Application Support/`. Backed up by iCloud Backup (encrypted, opt-in by user). Not synced live to iCloud (different from `Documents/`).

**Trade-off flagged:** SwiftData relationship access has Swift 6 Sendable wrinkles when crossing actor boundaries. Implementation will likely use a SwiftData-owning actor for writes. Doc-comment but not a blocker.

**V3 entry to file at end of Group D:** "SwiftData VersionedSchema migration — trigger: any external tester receives a build with persistent data they want preserved across schema changes. Cost: ~half-day to add VersionedSchema migration plan."

---

## Decisions NOT in scope for Group D (Phase 6+ or later)

- Real Apple Foundation Models title generation
- Diagnostic logs toggle
- Theme picker / custom typography polish pass
- Search results screen with jump-to-sentence links
- FTS5 search migration
- VersionedSchema migration support
- iCloud Backup exclusion option
- PDF export format
- History retention auto-delete policy
- Accessibility deep dive (VoiceOver labels, Dynamic Type validation, Reduced Motion)
- Speaker detection / speaker labels in transcript

---

## Revision policy

These decisions are **locked for Group D implementation** but **NOT contracts for MVP 1+**. After MVP 1 device testing in real meetings, expect to revise:

- Whether auto-save cadence is right (UI hitching)
- Whether pause is actually used or users prefer STOP-and-start-new
- Whether multi-select is right granularity or single-swipe is preferred
- Whether the undo toast window is long enough (3s vs 5s vs 10s)
- Whether the button morphing pattern feels right or persistent buttons would be clearer
- Whether the "no export during recording" decision holds up
- Whether search latency on real data triggers FTS5 migration sooner than expected

Treat this doc as the locked input for Group D feature-planner, but revisit after each MVP 1 usage cycle.

---

**Source:** Phase 5 Group D strategic walkthrough, Claude.ai conversation, 2026-05-16. User: Jose. Captures Q1-Q10 walkthrough decisions + decisions #1-#9 from the original captured-intent doc.
