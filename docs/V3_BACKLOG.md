# Arigato AI — v3 Backlog

Features deferred from MVP 1, prioritized for post-launch consideration.
Each item includes: what, why deferred, trigger condition for revisiting.

---

## Anthropic agentic platform features (announced May 6 2026)

### Outcomes (Managed Agents)
- **What:** Define success criteria for tasks; a separate grader agent evaluates outputs against those criteria. Anthropic claims +10pt task success vs. plain prompts.
- **Why deferred:** Managed Agents is a separate platform from Claude Code; would require migrating workflow. Also needs real translation outputs to grade — we don't have any yet.
- **Trigger to revisit:** After Phase 4 (WhisperKit) and Phase 5 (LFM2) ship, when we have working translations to grade. Concrete first outcome: "translate Japanese business meeting audio to English with <500ms latency, preserving keigo register and Roche product names verbatim, with no hallucinated content."
- **Cost estimate:** Managed Agents pricing model + grader agent runs. Likely ~$5–15/month for our scale.

### Dreaming (Managed Agents, research preview)
- **What:** Scheduled overnight process where agents review past sessions, identify recurring mistakes, restructure memory across sessions. Cross-session pattern recognition.
- **Why deferred:** Research preview, by-request access only. Also requires lots of session data to be useful, and we have none yet.
- **Trigger to revisit:** After 2–3 months of active development, when we have a meaningful corpus of agent sessions to analyze. Apply for access via Anthropic's developer program when we're at that volume.
- **Cost estimate:** Unknown — Managed Agents pricing + dreaming is a research feature.

### Advisor strategy
- **What:** Opus advises Sonnet executor. Lower cost than pure Opus, near-Opus quality. SWE-bench: Sonnet+Advisor scores comparable to Opus solo at fraction of cost.
- **Why deferred:** We just locked Option A model assignments (7 Opus, 2 Sonnet, 1 Haiku). Quality over cost was the explicit decision. Premature optimization to switch.
- **Trigger to revisit:** When monthly usage is creating real budget pressure, OR when we're confident about which subagents do "execution" work that Sonnet+Advisor handles well (test-writer, doc-researcher, possibly swift-implementer for routine implementation tasks). Swap one subagent at a time, A/B test outputs.
- **Cost estimate:** Reduces costs ~3–5x for affected agents.

### Auto mode for Claude Code
- **Status (2026-05-10):** Resolved — auto mode is now available to Max users. Currently in active use.
- **What:** Safer long-running permissions alternative to --dangerously-skip-permissions. Claude makes permission decisions with safeguards monitoring actions.
- **Why deferred:** Research preview for Team users only as of May 6 2026. We're on Max; not eligible yet.
- **Trigger to revisit:** When auto mode reaches general availability for Max users. Watch Anthropic release notes.

---

## Project-specific deferrals

### LFM2 fine-tuning on Roche terminology
- **What:** Fine-tune LFM2-350M-ENJP-MT on a few hundred examples of Roche-specific business Japanese (anonymized real meeting transcripts). Improves accuracy on terms like 検査機器, 試薬, 装置, 保守契約, navify, cobas, TLA.
- **Why deferred:** MVP 1 ships with base model. Fine-tuning is 1–2 days of work and only earns its way in if base model accuracy proves inadequate in real meetings.
- **Trigger to revisit:** After 5+ real meeting tests reveal consistent terminology errors that cleanup tier doesn't fix.

### Speaker diarization
- **What:** Identify "who said what" in transcripts. Argmax SpeakerKit (same vendor as WhisperKit) provides this.
- **Why deferred:** Doubles compute load on already-stressed pipeline. Adds significant UI complexity (speaker labels, color coding, attribution).
- **Trigger to revisit:** When you've used MVP 1 in 5+ real meetings and the question "who said what?" is the most common pain point.

### Multi-language support beyond JA↔EN
- **What:** Mandarin, Korean, Spanish, etc. for broader Roche colleague conversations.
- **Why deferred:** LFM2-350M-ENJP-MT is JA↔EN-specific. Multi-language requires either a different model (lower quality) or model swapping (complex UX).
- **Trigger to revisit:** When you have specific named colleagues whose language you can't currently handle, in meetings frequent enough to justify.

### Live caption sharing to a second device
- **What:** Bilingual captions display on a colleague's phone or laptop simultaneously, so non-English speakers in a Roche meeting can also benefit.
- **Why deferred:** Requires either local network discovery (mDNS) or cloud relay (privacy hit). Significant architectural addition.
- **Trigger to revisit:** When meeting partners specifically request access to your captions and you can't just hand them your phone.

### Custom glossary / terminology presets
- **What:** Per-meeting or per-customer glossary that overrides translation choices for specific terms.
- **Why deferred:** Requires UX for managing glossaries, integration into the LFM2 prompt or post-process, edge cases around Japanese/English term matching.
- **Trigger to revisit:** When fine-tuning option (above) seems like overkill but specific terms keep getting wrong.

### App Store submission
- **What:** Public release on the iOS App Store.
- **Why deferred:** Personal use first. Earn product-market fit signals before review process.
- **Trigger to revisit:** After 30 days of personal use proves the app is valuable, AND when at least 3 colleagues independently ask "can I get this app?"

### Cleaner ios-simulator-skill installation
- **What:** Migrate from vendored copy to plugin install via /plugin marketplace add conorluddy/ios-simulator-skill.
- **Why deferred:** Plugin install failed May 7 2026 due to upstream manifest validation error. Vendored copy works.
- **Trigger to revisit:** When upstream fixes their plugin.json, OR when we hit a bug in the vendored version that's already fixed upstream.

### /dispatch-research slash command
- **What:** Single-shot slash command that invokes @doc-researcher against a structured uncertainties block in the active phase handoff doc, scopes against named source repos, and pauses for review. Eliminates the manual prompt drafting that currently happens mid-phase when uncertainties need resolution.
- **Why deferred:** Phase 4 mid-session. Tooling restructuring during an active feature is the costliest citizen-dev mistake. Current manual flow works.
- **Trigger to revisit:** Phase 5 kickoff, before LFM2 integration begins. Phase 5 will surface a new uncertainties list against LEAP iOS SDK — natural moment to invest in the slash command before drafting the prompts manually a second time.

### Cross-surface friction between Claude.ai and Claude Code
- **Status (2026-05-10):** Trigger met (>3 documents pasted per phase during Phase 4). Action superseded by the "Workflow automation — narrow bundle for cross-surface courier work" entry, which explicitly rejects @phase-walker as a design choice. Strategic conversation stays in Claude.ai by design. Entry preserved for reasoning trail.
- **What:** Strategic phase walkthroughs (decision approvals, doc-researcher prompt drafting, recommendation framing) currently happen in Claude.ai web chat. Implementation happens in Claude Code. Result: copy-pasting prompts and project docs across surfaces. Explore moving strategic conversations into Claude Code via a @phase-walker subagent or a richer project-level CLAUDE.md context block so a single Claude Code session covers both planning and execution.
- **Why deferred:** Phase 4 mid-session. Friction is real but bounded.
- **Trigger to revisit:** When pasting more than 3 documents per phase between surfaces, OR when a phase walkthrough takes more than one Claude.ai session to complete.

### @plan-reviewer subagent
- **Status:** Superseded — see "Workflow automation — narrow bundle for cross-surface courier work" below. Entry preserved for the reasoning trail on why a custom plan-reviewer subagent was rejected in favour of self-critique rules baked into @feature-planner plus @dispatch-implementer slash command.
- **What:** Subagent that reviews @feature-planner output against CLAUDE.md rules, the active phase handoff doc, existing committed code, test coverage adequacy, and internal consistency. Outputs blockers/warnings/pass-throughs structured the same way the existing three-reviewer gate does. Closes the gap between plan generation and code generation, where currently no automated review exists.
- **Why deferred:** Phase 4 mid-session. Tooling restructuring during active features is the costliest citizen-dev mistake. Current manual flow (Jose + Claude.ai cross-surface review) catches enough.
- **Trigger to revisit:** Phase 5 kickoff. LFM2 integration will produce its own multi-step plan that benefits from automated first-pass review before @swift-implementer runs.
- **Cost estimate:** Subagent definition + prompt engineering. ~1-2 hours of setup. Model assignment: probably Sonnet (review work, not heavy reasoning) per the Advisor strategy backlog entry.
- **Important caveat:** Does not replace the citizen-dev plan review. Plan-reviewer catches mechanical issues (rule violations, type inconsistencies, missing tests); the human catches product and architectural judgment issues. Use as first pass, not last pass.
- **Design constraints when built:**
    1. Adversarial system prompt — "your job is to find problems, not validate." Default reviewer behaviour is deferential; design against this explicitly.
    2. Iterative loop, not single-pass — Planner → Reviewer → Planner until clean. Single-pass review is wasted on multi-step plans.
    3. Explicit human gate stays after the loop closes, before @swift-implementer dispatch. Plan-reviewer is a filter, not a replacement for the citizen-dev review.
    4. Spike Claude Code's built-in Plan Mode per-subagent first. The structured plan-mode-per-group pattern may deliver 70% of the value without requiring a custom subagent. Build the custom @plan-reviewer only if the spike falls short.

### Workflow automation — narrow bundle for cross-surface courier work
Two coordinated upgrades that move mechanical translation work out of Claude.ai while preserving Claude.ai for strategic thinking, learning, and architectural decisions. Bundled because they're designed to compose; built together as one ~1-hour session after Phase 4 ships.

**Item 1: @feature-planner self-critique rules**
- **What:** Add classification + filtering rules to feature-planner's system prompt: drop signature-only tests, drop auto-synthesized conformance tests (Equatable, Hashable, Codable trivialities), require every doc-comment contract on a protocol method to have an enforcing test, AND require explicit nonisolated annotation on all value types that don't touch MainActor UI state. Today's Phase 4 Group A session would have caught the 4 dead tests, the missing D6 contract test, AND the missing nonisolated keywords on TranscriptionError and WarmupState without manual review.
- **Cost:** ~30 minutes including testing the new prompt against a small spike plan.
- **Token impact:** Negligible — adds maybe 200 tokens to feature-planner's system prompt; saves ~5-10k tokens of Claude.ai back-and-forth per group.

**Item 2: @dispatch-implementer slash command**
- **What:** Single slash command (e.g., /dispatch-implementer) that takes an approved plan reference and produces the standard swift-implementer dispatch prompt: per-file build verification, post-write test run, pause-before-reviewer-gate. Eliminates Jose hand-typing or copy-pasting a ~12-line dispatch prompt at every group boundary.
- **Cost:** ~30 minutes including testing.
- **Token impact:** Zero runtime tokens — slash commands are template expansion, not LLM calls.

**Explicit non-goals (do NOT build):**
- **@plan-reviewer subagent** (despite earlier backlog entry): once item 1 lands, the marginal value is small. Remaining plan issues are architectural/judgment calls Jose should keep doing in Claude.ai for upskill. Building @plan-reviewer would either duplicate item 1 or substitute for citizen-dev learning. Both bad. The earlier @plan-reviewer entry should be marked superseded.
- **@phase-walker subagent**: strategic conversation stays in Claude.ai by design. Building this would replicate Claude.ai's role badly.
- **Generalized "automate everything in the workflow"**: explicitly rejected. Some current friction is pedagogical (e.g., learning to spot dead tests). Automating away rules you haven't internalized yet means losing the upskill loop.

**Why deferred:** Mid-Phase 4. Tooling restructuring during active features is the costliest citizen-dev mistake.

**Trigger to revisit:** Phase 4 ships. Build both items in one ~1-hour session before Phase 5 kickoff.

**ROI estimate:** ~$5 in one-time build + negligible runtime tokens, saves ~20-30 minutes per phase across remaining 5 phases of MVP 1 (~2-3 hours total focus time clawed back). Trade is clearly net-positive.

### TranscribingProtocolTests cancel-test timing race
- **What:** `transcribe_cancelFinishesStreamWithoutError` uses a 20ms `Task.sleep` to give the stream a chance to start before `cancel()` is called. This is a soft timing race that could flake on slow CI runners. Replace with a deterministic handshake (e.g., `MinimalTranscriber` exposes a "stream started" continuation the test awaits before calling `cancel()`).
- **Why deferred:** Doesn't flake locally on M5 today; fix needs proper handshake design, not a one-line edit.
- **Trigger to revisit:** First time this test flakes in CI, or before MVP 1 ships if CI is added by then.
- **Cost estimate:** ~30 min including handshake design + replacement.

### Quarterly platform sanity review
- **What:** Every ~3 months, run a deeper review of the agentic stack: are the MCP servers I depend on still the right choice? Are there new ones that would replace what I have? Has the official subagent docs changed in ways that affect my setup? Are there community-reported best-practice shifts I missed? This is strategic review work, runs in Claude.ai with the live state file as input.
- **Why deferred:** Phase 4 mid-flight. Not urgent.
- **Trigger to revisit:** Calendar reminder set for Aug 2026, or any time a daily brief surfaces multiple platform changes in the same week (signal that drift is accelerating).
- **Cost estimate:** ~30 min Claude.ai session. No code, no commits — outputs are V3 backlog updates and possibly CLAUDE.md updates.

### /update-state self-referential commit noise
- **What:** Running /update-state produces a commit whose primary change is updating CURRENT_STATE.md's reference to the previous CURRENT_STATE.md commit. Four of the eight commits pushed in range afa6142..4cd76c4 are these self-referential refreshes. Two cleaner options: (a) amend the previous /update-state commit when its content would only differ in the "Most recent commit" line, (b) skip the refresh when no field other than "Most recent commit" would change. Option (a) is preferable — preserves a single state-refresh commit per phase boundary rather than per session interrupt.
- **Why deferred:** Phase 4 mid-flight. Slash command edit, not urgent.
- **Trigger to revisit:** Build alongside the @dispatch-implementer slash command in the post-Phase-4 workflow automation bundle.
- **Cost estimate:** ~10 min edit to .claude/commands/update-state.md.

### Auto mode behaviour notes (March 2026 Anthropic article)
- **What:** Read https://www.anthropic.com/engineering/claude-code-auto-mode on 2026-05-10. Key facts to remember when choosing modes mid-session: (1) Tier 1 auto-allows file reads, search, code navigation, plan-mode transitions; (2) Tier 2 auto-allows file writes and edits inside project directory without classifier; (3) Tier 3 transcript classifier gates shell commands, web fetches, external tool calls, subagent spawns, out-of-project filesystem ops; (4) blanket shell-access rules (e.g., `bash *`, wildcarded interpreters, `npm run *`) are dropped on entry to auto mode — only narrow rules carry over; (5) classifier achieves 0.4% FPR / 17% FNR on real overeager actions; (6) deny-and-continue means false positives cost a single retry, not a halt; (7) classifier strips assistant prose and tool outputs — sees only user messages plus bare tool calls.
- **Why deferred:** Reference notes, no project change required.
- **Trigger to revisit:** When deciding mode for high-risk operations (project.pbxproj edits, dependency additions, force-pushes). For careful-review work (Group B Step 5 today), accept-edits-on remains the right mode. For routine mechanical approvals after a workflow has been validated once (Group B Steps 6-7 after Step 5 lands), auto mode is appropriate.
- **Calibration heuristic:** "Validate manually first, automate after" — switch to auto mode only after one manual run of a new workflow has confirmed it behaves as expected.

### WhisperKit model variant choice — turbo decoder, 632MB
- **What:** Phase 4 Group B uses openai_whisper-large-v3-v20240930_turbo_632MB. Turbo decoder chosen per Phase 4 Decision 2 (latency budget for live meeting captions). 632MB bundle size selected over 954MB alternative because half the memory footprint matters for sustained 1-2 hour meetings.
- **Note:** Argmax's README front page currently recommends openai_whisper-large-v3-v20240930_626MB (non-turbo) for maximum multilingual accuracy. We deliberately do NOT use this variant because non-turbo regresses our live-captioning latency budget. The maintainer's general-purpose recommendation does not match our use-case-specific constraints.
- **Trigger to revisit:** (1) Argmax adds a turbo variant they recommend over 632MB. (2) Real Roche meetings show accuracy issues attributable to turbo (vs non-turbo) decoding. (3) Phase 4 Decision 2's latency budget is renegotiated.
- **Cost estimate to swap:** 5 minutes (string change + new bundle download).

### Design language direction — Arigato AI visual identity (Phase 7)
- **What:** Phase 7 (UI polish) should implement a coherent visual language combining several 2026 AI-native aesthetics. Codified below as the design intent and the explicit anti-patterns to avoid.

**Aesthetic direction (target style):**
- Neo Terminal Typography — monospace technical readouts (model names, language tags, latency, confidence values)
- Cyber-Minimalism / Neo-Retrofuturistic Tech — clean and calm with purposeful retrofuturistic accents (dot matrices, soft neon/cyber accents, sci-fi-inspired typography), balanced so it never feels dated or over-the-top
- Visual language of "intelligent" interfaces — UI feels alive and computational without being cluttered or gimmicky
- AI-native signaling via particle/dot/constellation/starfield backgrounds — subtle pulsing or slow movement to convey intelligence and dynamism (reference: Liquid AI LFM2.5-350M model card orb)
- Glassmorphism + subtle glows — frosted semi-transparent cards layered over dark/particle backgrounds
- Neo-minimalism with tech details — clean foundation with purposeful generative elements
- Ambient intelligence — backgrounds that react to AI states (more activity when "thinking," calmer when idle)
- Monochromatic, premium, calm, sophisticated — color reserved for semantic meaning only (red = error, amber = fallback, green = confident)

**Anti-patterns to actively avoid ("AI Slop"):**
- Generic purple/blue gradient backgrounds (the SaaS-AI default of 2024-2025)
- Inter font stacks as default — it's a fine font but its overuse has made it the visual equivalent of "we didn't pick a font"
- Sterile minimalism without motion or texture
- Distracting motion that calls attention to itself rather than supporting comprehension
- Skeuomorphic gloss / chrome effects (signals "trying too hard")
- Stock illustration of brains, circuits, or "AI" trope imagery

**Tone calibration:**
- Sophisticated without sterile
- Dynamic without distracting
- Premium without cold
- Computational without cluttered

**Specific design opportunities for Arigato AI:**
- Particle density as live confidence indicator on translation segments (denser = more confident, sparser = less confident, very sparse = wasLanguageFallback active)
- Dot-matrix orb as model warmup state visualization (cold/warming/ready/failed) — different particle behaviours per state
- Monospace technical readouts for Whisper language tag, model variant, latency
- Ambient background reacts to transcription pipeline state — calm when idle, subtle pulse during active capture, denser activity during inference
- Glassmorphic transcript bubbles layered over dark particle background, with semantic color for JA vs EN

**Hard technical requirements:**
- Native light AND dark mode parity, flawless — the design language must work in both modes, not just dark mode where it photographs better. Light mode is harder; design from light-mode-first to force the discipline.
- Current iOS frameworks only — SwiftUI, no UIKit unless wrapping a system API that requires it. Use iOS 26.4+ design system primitives (Liquid Glass, current animation APIs, latest typography APIs). No deprecated APIs.
- Accessibility from day one — WCAG AA contrast in both modes, dynamic type support, reduced motion respect (the ambient-intelligence backgrounds must have a "calm" mode for users with motion sensitivity), VoiceOver labels on confidence indicators.
- Performance budget — 60fps minimum on iPhone 17 Pro Max during active transcription. Particle systems must not steal frame time from the inference pipeline. Use Metal-backed rendering where particle counts justify it.

**Why deferred:** Phase 4 is functional plumbing (audio capture → Whisper → translation router). Phase 7 is UI polish. Implementing the full design language during Phase 4 would slow architectural progress and require redoing once functionality is real.

**Trigger to revisit:** Phase 7 kickoff. Before invoking @feature-planner for Phase 7, set up a design-system planning session in Claude.ai using this backlog entry as input. Output should be: (1) a design-tokens file (color, typography, spacing, motion), (2) a small library of reusable particle/glass/orb SwiftUI components, (3) updated CLAUDE.md design rules, (4) an updated @ui-reviewer mandate that enforces the design language.

**Subagent question for Phase 7:** Decide whether to introduce a new @design-system subagent (handles design-token maintenance, component library updates, design-language drift detection) or extend @ui-reviewer's mandate. Lean toward the extension unless the workload justifies a new subagent.

**Reference materials to gather before Phase 7:**
- Screenshot of LFM2.5-350M model card (user's device IMG_1717)
- Anthropic's model release card aesthetic (Claude Opus/Sonnet/Haiku lineup)
- Mistral, Liquid AI, and similar lab visual languages
- Framer template gallery filtered to AI/tech (particle backgrounds, glassmorphism examples)
- Apple's iOS 26 design guidelines for compositing custom visual language with native Liquid Glass components

**Cost estimate:** Phase 7 itself, no extra cost beyond what's already planned. ~2-3 weekend sessions to land design tokens + core components + first pass on screens.

### Subagent MCP-inheritance bug — automatic re-validation
- **What:** The subagent MCP-inheritance bug family (issues #13605, #13898, #25200, #21560, #15810, #19526, #4476, #17524, #23625, #23882, #6915, #2169) was investigated 2026-05-10 and confirmed as still affecting our setup despite #13605 closing on March 2 in claude-agent-sdk 0.2.63 / Claude Code 2.1.30+. Closure was narrow; #13898 (custom subagents in .claude/agents/ cannot call project-scoped MCP tools, hallucinate plausible results instead) is the canonical open issue for our case. Defense-in-depth fallback rule in CLAUDE.md stays in place: subagents fall back to raw xcodebuild via Bash; main session uses XcodeBuildMCP for verification.

- **Why deferred:** No action needed today. Current workflow has not surfaced hallucination in practice. Group A and Group B both shipped clean with the fallback rule active. Watching for a real signal (subagent reports "build passed" while main-session verification disagrees) before changing anything.

- **Trigger to revisit (automatic):** Morning brief monitors the full cluster of issues listed above. When ANY of them changes state (closes, gets a new comment with "fixed", references a Claude Code version number), brief surfaces the change with the full cluster's open/closed state for context. Do not trust narrow fix announcements without re-running our reproduction (custom subagent in .claude/agents/ attempting to call XcodeBuildMCP tool).

- **Trigger to revisit (manual):** First time during normal work that subagent output disagrees with main-session XcodeBuildMCP verification on the same code state. Stop, investigate, document the divergence in this V3 entry. Hallucination would manifest as subagent reporting test/build success when reality is failure.

- **Cleanup conditions:** Drop the CLAUDE.md fallback rule when (a) ALL issues in the tracked cluster are closed AND (b) we successfully reproduce a custom subagent calling XcodeBuildMCP via fully-qualified tool name in our actual project. Cleanup is one-line CLAUDE.md edit + one-line .claude/agents/build-doctor.md edit. ~5 minutes total.

- **Cost estimate to revisit:** ~10 minutes manual reproduction + ~5 minutes CLAUDE.md cleanup if cluster is fully closed. Up to ~30 minutes if cluster is partially closed and reproduction has nuance to capture.

- **Group D end-of-group gate datapoint (2026-05-10):** Second real-work consequence of the bug. The `@ui-reviewer` agent declared `mcp__xcode__*` and `mcp__xcodebuildmcp__*` tools in its frontmatter but the dispatched agent session did not have them inherited — only `Read` and `Edit`. The agent correctly refused to fake a visual review and returned a tooling-gap report plus a static-code-only concern list (8 concerns flagged for visual verification). Mitigation that worked: main session used XcodeBuildMCP to build, run, and capture screenshots; verified Concern 6 (duplicate "listening…") visually and confirmed the fix. **New action item to evaluate when this entry is revisited:** add a Bash-based screenshot capture fallback to `@ui-reviewer` (the agent has `Bash` and `Read`; `xcrun simctl io <UDID> screenshot <path>` would let the agent capture screenshots without MCP), so the agent can deliver a complete review even when MCP inheritance fails. Don't change the agent now, just record the signal — the cluster fix is still the right long-term answer.

- **End-of-Group-D three-reviewer gate Pass 2 datapoint (2026-05-17):** Third real-work consequence. The `@ui-reviewer` agent in Pass 2 of the end-of-Group-D three-reviewer gate again reported a restricted tool set (`Read` + `Edit` only; no `mcp__xcodebuildmcp__*` / `mcp__xcode__*`). All four Pass 2 deliverables (ShareLink smoke test, UI #9 Context A intent, MeetingListView error rendering, permission-revoked overlay, UI #5/#13/#15 verification) degraded to inspection-only paths. Fallback was acceptable this gate because (a) the LFM2 blocker (V3 `b851dad`) would have forced inspection on the smoke test regardless, (b) cascade items B/C were inspection-acceptable per dispatch brief, (c) `RenderPreview` was an acceptable fallback for D. Same root cause as the 2026-05-10 datapoint; more evidence. **Recurrence note:** future @ui-reviewer dispatches that REQUIRE the simulator surface (live record + screenshot) must either confirm the tool surface is wired OR acknowledge inspection-only mode up front in the brief. No production change needed; CLAUDE.md fallback rule still applies.

### Test isolation strategy — Swift Testing parallel execution masks crash root causes

**Problem observed:** During Phase 4 Group C Step 9 verification, a single array-bounds crash in C15 (TranscriptionActorTests.windowStream_anchorHostTime_matchesAudioArrayStart) terminated four unrelated tests running in parallel within the same test process: AppBootstrapper.startPrewarm_calledTwice_doesNotDoubleLoad, RollingAudioBuffer.append_largeNumberOfFrames_completesUnderTimeBudget, and two other TranscriptionActor tests (C9, C14). Xcode's test runner attributed all four collateral failures to TranscriptionActorTests.swift:568 — the source location of the original crash, not where the dying tests actually were. Surface read: 5 unrelated test failures across 3 suites. Reality: 1 real failure, 4 phantom misattributions.

**Why it matters:** This is the second time a test-suite signal has been less trustworthy than expected (first was the cancel-test 20ms timing race, addressed in Step 9 via deterministic handshake per Decision #12). When the test suite produces misleading verdicts, the citizen-dev review loop breaks — neither the implementer nor the human reviewer can trust "5 failures in 3 suites" to mean what it appears to mean. Diagnosis took ~10 minutes of human-driven investigation that should have been 0.

**Trigger to revisit:** Before MVP 1 ships, OR if test-suite misattribution wastes another diagnostic session.

**Options to evaluate:**
1. Mark TranscriptionActorTests with .serialized — runs its tests serially, isolates crashes within the suite. Cheapest fix; doesn't help cross-suite.
2. Mark the entire test target .serialized — eliminates all parallel-execution misattribution. Cost: longer test runs (probably 2-3x for full suite).
3. Replace bounds-prone assertions (calls[N] where N depends on prior assertion) with a pattern that fails fast and clean — e.g., guard calls.count >= 3 else { Issue.record("expected 3 calls, got \(calls.count)"); return }. Surgical; doesn't fix the parallelism issue, fixes the crash-vs-fail-cleanly issue at the source.
4. Combination: option 3 as a coding standard for actor tests, option 1 only if option 3 isn't sufficient.

**Recommendation when revisited:** Start with option 3 as a test-writing pattern (cheapest, addresses root cause). Add option 1 only if a future crash demonstrates option 3 isn't enough. Avoid option 2 unless the cost-benefit shifts.

**Related:** TranscribingProtocolTests cancel-test timing race (separate V3 entry, addressed in Step 9 deterministic handshake).

### TranscriptionActor.awaitUpstreamDrained — test seam on production type

**What:** TranscriptionActor exposes awaitUpstreamDrained() as a test-only signal method, used by C30/C31 to deterministically synchronize with the drain task before releasing test blocks. The method is documented as test-only but lives on the production type.

**Why it's a smell:** Test-only methods on production types violate the principle that production code should not exist to serve tests. The current placement works and doc-comments warn callers, but a future contributor could call awaitUpstreamDrained() from production code (e.g., LanguageRouter, Group D UI) and create a hidden coupling that masks real timing issues.

**Why it shipped this way:** The previous Step 9 attempt had a race between the consumer task releasing the test block and the drain task running, causing C30 to pass at 95ms by luck and fail deterministically thereafter. awaitUpstreamDrained eliminates the race. Removing it now would risk reintroducing the regression. Carrying it forward is the pragmatic choice for Group C closure.

**Trigger to revisit:** Before MVP 1 ships, OR if any non-test code path is found calling awaitUpstreamDrained.

**Replacement options (commit to evaluating these, not just "consider whether to keep"):**
1. Move awaitUpstreamDrained to a test-only extension in a separate file under #if DEBUG, so it's invisible to release builds and clearly scoped to tests.
2. Replace with a separate test-injection point — e.g., a synchronization protocol the actor optionally accepts in init, only used in tests, no production surface area.
3. Restructure the test to synchronize via public API only (e.g., await the actor's stream until N windows have arrived, instead of waiting for drain completion). Likely requires test redesign.

**Recommendation when revisited:** Option 1 (DEBUG-only extension) is the smallest change with the largest hygiene benefit. Option 2 is principled but heavier. Option 3 is cleanest but requires the most rework.

### LanguageRouter scheduling-assumption violation test

**What:** LanguageRouter's doc-comment documents a scheduling assumption (upstream produces faster than MainActor hop can advance) per the CLAUDE.md "Concurrency design discipline" rule. The rule requires a violation test. None exists — C29 is a cancellation test, not a violation test.

**Required test:** drive the router with an upstream stream that bursts faster than MainActor can hop, assert the router survives without losing windows or corrupting authoritative-language state. Should test the documented contract explicitly, including C30's oldest-drop behavior propagating through the router.

**Cost to add:** ~30 minutes including test design.

**Trigger to revisit:** Before MVP 1 ships, OR if any router scheduling regression is observed.

### LFM2ModelLoader mid-load cancellation violation test

**What:** `LFM2ModelLoader.loadIfNeeded(quantization:)`'s doc-comment claims a cancellation contract: "if a caller's outer task is cancelled while it awaits the in-flight load, only that caller's await throws `CancellationError`. The shared in-flight task continues so other coalescing callers still receive their result." No test currently exercises this contract. V3 (`loadIfNeeded_afterFactoryRelease_completesEngineRetrievalForFreshCallers`) is a factory-park-and-release test — cancellation is functionally a no-op there because `Task.init` inside the actor body is a fresh top-level task that does not inherit awaiter cancellation, and `await task.value` does not propagate awaiter cancellation either. So V3 verifies post-load recovery semantics, not the documented cancellation behaviour.

**Required test:** drive a caller into the in-flight load, cancel that caller, and assert:
1. The cancelled caller's `await` throws `CancellationError` (or completes per the loader's actual contract — verify against current code, not the stale doc-comment).
2. A second coalescing caller already bound to the in-flight load still receives the engine.
3. The loader's state machine ends in `.loaded(engine)` (not `.failed(_:)`).

Requires a different test mechanism than the current single-shot `LFM2ContinuationGate`. Likely shape: a test-only scaffold that wraps `task.value` in `withTaskCancellationHandler` at the test layer (so the test can observe and forward cancellation deterministically), paired with a cancellation-aware gate (`withTaskCancellationHandler` wrapping `withCheckedContinuation`). Alternative shape: change `LFM2ModelLoader.loadIfNeeded` itself to forward awaiter cancellation to the inner `Task` — but this changes the documented A1 coalescing contract (one caller's cancellation would cancel the shared load), so the contract has to be re-decided first.

**Why deferred:** Group B's V3 was meant to cover this and didn't. Adding a replacement test is non-trivial (needs new test scaffolding, plus a decision on whether the loader's documented cancellation contract should change). Group B is otherwise green; the gap is documented in the V3 doc-comment so future readers understand what V3 actually asserts.

**Cost estimate:** ~1–2 hours. Includes deciding whether the production loader's cancellation contract should change, designing the test scaffold, writing the test, and updating `LFM2ModelLoader.loadIfNeeded`'s doc-comment to either point at the new test or document a revised contract.

**Trigger to revisit:** Before MVP 1 ships, OR if any real-world bug surfaces where the loader fails to recover after a cancelled load.

### Swift Concurrency cancellation bridging — three-mechanism gotcha

What: Three independent mechanisms in Swift Concurrency compound to make awaiter-cancellation-through-continuation a documented footgun. All three were involved in the V3 deadlock (resolved via Fix A in commit a49a93b).

The three mechanisms:
1. `await task.value` does NOT set up a cancellation handler — the awaiter's cancellation is not propagated to the inner task. See Swift Forums thread "Why doesn't `await task.value` set up a cancellation handler?" (forums.swift.org/t/57740).
2. `Task.init` creates a new unstructured top-level task that does NOT inherit cancellation from its surrounding context. The new task starts uncancelled regardless of caller state.
3. `withCheckedContinuation` does NOT honor task cancellation by design. A parked continuation remains parked unless explicitly resumed.

Combined effect: if test or production code awaits an unstructured Task whose body parks on a plain continuation, cancelling the awaiter will NOT unblock the parked continuation.

Pattern guidance for future code:
- If a gate or continuation needs to honor awaiter cancellation, cancellation must be forwarded explicitly from the awaiter to the inner task (via `withTaskCancellationHandler` at the awaiter site that calls `task.cancel()` in its onCancel handler), AND the inner task's continuation must be cancellation-aware (via `withTaskCancellationHandler` wrapping `withCheckedContinuation`).
- For test gates specifically: prefer test-only scaffolds that own the full bridging stack, rather than relying on the production loader's cancellation contract.
- For production code: a documented A1-style coalescing contract (one cancellation should not cancel a shared load) is a strong argument AGAINST forwarding cancellation through to the inner task. Choose deliberately.

Trigger to revisit: Anytime a future test or production code needs to bridge awaiter cancellation through an unstructured Task or continuation gate. Reference this entry before implementing.

Cost to act on: Reading this entry. The pattern guidance is the deliverable.

Related follow-up — add a test that genuinely exercises mid-load cancellation in LFM2ModelLoader. The renamed V3 test (commit a49a93b) no longer asserts cancellation propagation; it only asserts factory-park-and-release semantics. Genuine mid-load cancellation testing requires a different test mechanism — likely a custom test scaffold that wraps task.value in withTaskCancellationHandler at the test layer. Trigger: before MVP 1 ships, OR if any real-world bug surfaces where the loader fails to recover after a cancelled load. Cost: ~1-2 hours.

### LanguageRouter routedTranscripts() multiplex

**What:** routedTranscripts() currently returns a dead stream. SEAM-1 surface (a) was supposed to deliver a RoutedTranscript stream consumable independently of the Transcribing protocol's TranscriptSegment surface. Current implementation does not multiplex; calling routedTranscripts() returns a stream that finishes immediately.

**Why it shipped this way:** swift-implementer did not surface this design choice during Step 11 dispatch; the dead-stream shim was an auto-mode decision. Group C correctness is unaffected (Transcribing protocol surface works correctly). Group D's UI bindings will be affected.

**Replacement options when revisited:**
1. Refactor the router to multiplex one upstream session into both stream surfaces — clean but non-trivial concurrency work
2. Drop routedTranscripts() from the public surface and have Group D consume detectedLanguage/didFlip via a different observation pattern (e.g., @Observable on individual fields)
3. Restructure so Group D's UI binds only to currentLanguage and the Transcribing protocol surface, dropping the per-window RoutedTranscript stream concept entirely

**Trigger to revisit:** Group D kickoff — first thing during Group D plan review.

**Recommendation when revisited:** option 2 or 3 likely simpler than option 1. Decide based on Group D's actual UI needs.

**Resolved 2026-05-10 by Group D Step 1:** Option 2 chosen — dead-stream method removed; routed transcripts surfaced via `@MainActor @Observable routedHistory` on `LanguageRouter`. Single UI consumer; no multiplex needed. See commit `checkpoint(group-d-step-1)`.

### feature-planner system prompt update — concurrency scheduling-assumption rule

**What:** Update feature-planner's system prompt to enforce the new CLAUDE.md "Concurrency design discipline" rule at plan time. Specifically: when a plan includes any actor, AsyncStream, async sequence, or Task spawn, the planner must (a) surface the design's execution-order assumptions in plain English in the plan output, (b) specify a doc-comment that documents those assumptions in the implementation, and (c) include at least one test in the test list that violates the assumption.

**Why:** The CLAUDE.md rule alone is enforced at code-review time, which is late. Catching it at plan time is cheaper — the assumption either gets articulated (and possibly redesigned) before any code is written, or the planner notices the assumption is unstable and proposes a different design. Phase 4 Group C Step 9 would have surfaced the hop-scheduler race condition at plan review if this rule had been active.

**Cost:** ~30 minutes including testing the new prompt against a representative concurrency-heavy plan. Adds maybe 300 tokens to feature-planner's system prompt.

**Bundle with:** @feature-planner self-critique rules (already in V3 backlog) and @dispatch-implementer slash command (already in V3 backlog). All three are feature-planner / workflow improvements; ship together as one ~90-minute post-Phase-4 session.

**Trigger to revisit:** Post-Phase-4 workflow automation bundle.

### Test infrastructure as agent blind spot

**Pattern observed in Group C:** Three independent test infrastructure issues hit during Group C, none caught by agent autonomy fallback because they manifest as runtime/environmental issues rather than code errors:
1. Swift Testing parallel-execution misattribution (logged as separate V3 entry, addressed during Group C via deterministic handshake pattern)
2. iOS Simulator microphone permission dialog blocking test runs (root cause: TEST_HOST setting on unit-test bundle launches host app)
3. TEST_HOST architectural debt — removing it breaks auto-scheme generation, requires explicit shared scheme XML files (~50 lines)

**Why it matters:** Test infrastructure issues live in agent blind spots — agents can read code and reason about static structure but cannot see GUI dialogs, simulator state, or scheme generation. Issues manifest as "tests are running for a long time" or "tests fail in confusing ways," not as code errors. Three separate test infra surprises in one group is a pattern worth fixing structurally.

**Fix scope (one focused session, ~2-3 hours) — original proposal, partially superseded by 2026-05-11 update below:**
- ~~Generate explicit shared scheme files at ArigatoAI.xcodeproj/xcshareddata/xcschemes/ArigatoAI.xcscheme listing both test bundles~~ **[DONE — Step 7 of the 2026-05-11 workflow automation bundle, commit `5bd882e`]**
- ~~Drop TEST_HOST and BUNDLE_LOADER from the unit-test bundle's Debug + Release configs once the explicit scheme is in place~~ **[SUPERSEDED 2026-05-11 — Step 8 attempted both the full drop and the surgical TEST_HOST-only drop; both failed at link time due to Xcode 16+'s `ENABLE_DEBUG_DYLIB` debug-dylib split. See the "Update 2026-05-11" section below for the negative result and the two viable forward paths (cheap: `ENABLE_DEBUG_DYLIB=NO` trading executable-target Previews; clean: library extraction in Phase 5+).]**
- ~~Add a CLAUDE.md "test target hygiene" section documenting: unit tests must not require host app launch; integration/UI tests use TEST_TARGET_NAME pattern~~ **[SUPERSEDED 2026-05-11 — the premise "unit tests must not require host app launch" is invalidated under the current Xcode debug-dylib regime. `@testable import` of host code requires either `ENABLE_DEBUG_DYLIB=NO` on the host (trading executable-target Previews) or library extraction (Phase 5+). The CLAUDE.md note cannot be written as originally specified; revisit when the architectural path is chosen.]**
- Document in the same session: when an agent reports tests "taking longer than expected" with no failure output, suspect simulator dialog or scheme issue before suspecting code _[still valid; never got done — bundles with future test-infra work]_

**Update 2026-05-11 — Step 8 of the workflow automation bundle attempted the recipe and produced a negative result:**
- Step 7 (explicit shared scheme) landed cleanly and ships. Step 8 then attempted the TEST_HOST + BUNDLE_LOADER drop. Both variants failed at link time with ~90 undefined `ArigatoAI.*` symbols (the test bundle has no production sources of its own; every `@testable import ArigatoAI` reference was being resolved through the host binary at link time).
  - Variant 1: drop both `TEST_HOST` and `BUNDLE_LOADER` → link fails, ~90 missing symbols.
  - Variant 2 (surgical): drop `TEST_HOST` only, keep `BUNDLE_LOADER` as a literal path `$(BUILT_PRODUCTS_DIR)/ArigatoAI.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/ArigatoAI` → same ~90 missing symbols.
- Root cause: `ENABLE_DEBUG_DYLIB=YES` is the default for iOS-app targets when `SWIFT_VERSION` is set and `SWIFT_OPTIMIZATION_LEVEL = -Onone` (Debug). Debug builds are split into a 58KB stub binary at `.app/ArigatoAI` and a `ArigatoAI.debug.dylib` containing the real Swift symbols. Verified empirically: `nm -gU` on the stub returns 0 `ArigatoAI.*` exports; the dylib has 800. `-bundle_loader` resolves against the stub, finds nothing.
- `TEST_HOST` and `BUNDLE_LOADER` appear to be a coupled pair under the default `ENABLE_DEBUG_DYLIB=YES` configuration for iOS-app-hosted unit-test bundles. The simple "drop TEST_HOST, keep BUNDLE_LOADER" recipe is not viable. Something about the pair's combined presence (likely an implicit linker resolution path that Xcode generates when both are set together — Apple does not document the mechanism) is what makes symbol resolution work in the baseline configuration. Dropping either one breaks it.
- **What lands from this bundle's Step 8:** the experiment itself (project.pbxproj edits) was reverted. The V3_BACKLOG.md updates here are the only artifact. A companion V3 entry on doc-researcher pre-flight discipline for third-party-tool-config changes was added (see "Doc-researcher trigger: third-party tool configuration changes").

**Doc-verification 2026-05-11 (@doc-researcher pre-flight against Apple's current documentation):** The diagnosis above is empirically correct but contains a temporal-attribution error and missed one Apple-documented alternative. Corrections:

- **Temporal correction:** `ENABLE_DEBUG_DYLIB` was introduced in **Xcode 16** (2024), not Xcode 26. The Xcode 26 release notes contain zero mentions of the setting; the behavior has been default-on for two Xcode generations. The original wording "Xcode 26's default" was imprecise. The correct framing: "Xcode 16+'s default, present unchanged in Xcode 26." Citation: https://developer.apple.com/documentation/xcode/understanding-build-product-layout-changes and Apple's Xcode 16 / Xcode 26 release notes.
- **Apple-documented opt-out we missed: `ENABLE_DEBUG_DYLIB = NO` on the host target.** Apple's "Understanding build product layout changes" article explicitly documents this as a supported per-target override. With it set on the host, all symbols live in the main binary, `-bundle_loader` against the literal path resolves them, and the simple "drop TEST_HOST" recipe would work as this entry originally envisioned. **Documented tradeoff: SwiftUI Previews fall back to the legacy execution mode on the executable target.** Apple's Xcode 16 release notes (quoted in Apple Developer Forums thread `developer.apple.com/forums/thread/760543`) explicitly flagged the legacy mode for removal in a future Xcode build: *"Setting this to NO will still allow you to preview in Xcode 16 Seed 1 using the legacy execution mode, but support for this mode will be removed in a future build."* The specific Xcode version that removes legacy-mode support is not stated in current Apple documentation; in practice on current Xcode 26, Previews may degrade or stop working depending on whether removal has shipped. (Previews continue to function for framework and Swift Package targets under either preview-execution mode.) This is a real engineering tradeoff for an actively-developed SwiftUI app whose views currently live in the executable target — not free, but materially cheaper than full library extraction.
- **No other Apple-blessed recipe found** that drops `TEST_HOST` without breaking linkage while `ENABLE_DEBUG_DYLIB=YES`. The current `TEST_HOST + BUNDLE_LOADER` pairing remains the only documented mechanism for app-hosted unit tests under default settings. The pairing requirement is documented only in Apple's retired Unit Testing Guide; current docs are silent but uncontradicted.
- **Library extraction status clarified:** Apple's general architectural guidance supports Swift Package or framework targets for code sharing, but Apple does **not** specifically prescribe this as the remediation for the `ENABLE_DEBUG_DYLIB` + test-host-linkage interaction. It is the correct engineering decision for independent reasons (decoupling, faster test builds, no mic dialog, Previews on framework targets continue working) but citing Apple docs as the authority for "this is the fix for this specific problem" would be an overstatement.

**Two viable forward paths (decide when revisiting):**
1. **Cheap path — `ENABLE_DEBUG_DYLIB = NO` on the host target.** Single-line build-settings change. Re-enables the simple TEST_HOST drop. Cost: SwiftUI Previews degrade to the legacy execution mode on the executable target (Apple flagged legacy mode for removal in a future Xcode build per the Xcode 16 release notes; on current Xcode 26 the legacy mode may already be gone — empirically verify before committing to this path). For a project whose Phase 7 design-language work likely involves heavy Preview-driven iteration, this cost may be unacceptable. Worth measuring (how much Preview iteration is happening today? does legacy mode still function on the installed Xcode?) before deciding.
2. **Clean path — library/framework extraction.** Multi-hour Phase 5+ refactor touching every Swift file's module membership. Tests compile against the library target directly — no `@testable` host-binary hack, no debug-dylib trap, no mic-permission dialog, Previews continue to work for framework-hosted views. The architecturally correct answer; pay-it-forward investment.

**Trigger to revisit:** Phase 5+ planning, OR earlier if (a) the mic-permission-dialog test-infra papercut accumulates enough cost to motivate the cheap path, or (b) a separate Phase 7 design-language step makes the Preview-on-executable assumption obsolete (i.e., views are about to move to a framework anyway for design-system reasons), at which point both paths converge. The Step 7 explicit shared scheme protects against auto-scheme regeneration regressions even though neither path has been pursued.

### Doc-researcher trigger: third-party tool configuration changes

- **What:** When a V3 backlog entry describes a fix that touches third-party tool configuration (Xcode build settings, package-manager behavior, simulator/device defaults, SDK-private knobs, framework-loader pathing), the pre-implementation step must re-verify the entry's premises against current vendor docs before treating the entry as ground truth. The author of a V3 entry encodes their state of knowledge at write time; that snapshot can be invalidated by tool releases between entry-write and entry-execute, often in non-obvious ways (a default flipping, a new build-product layout, a deprecated mechanism still appearing to work).
- **Cautionary case:** Step 8 of the post-Phase-4 workflow automation bundle on 2026-05-11 (see preceding entry "Test infrastructure as agent blind spot" for full diagnostic). The V3 entry recommended dropping `TEST_HOST` + `BUNDLE_LOADER` from the unit-test bundle once an explicit shared scheme was in place. The recipe was correct in spirit but wrong under the `ENABLE_DEBUG_DYLIB=YES` default (Xcode 16+, present in Xcode 26): host-app symbols live in a separate `.debug.dylib` that `-bundle_loader` against the stub cannot resolve. The implementer correctly STOP'd on the first variant; a surgical follow-up also failed for the same reason. A ~15-minute doc-researcher pre-flight on "Xcode iOS app test target hosting + debug dylib" would have surfaced the trap before any code was written. The rule was applied retroactively on the same day: doc-researcher verification against Apple's docs corrected a temporal-attribution error in the original V3 entry (Xcode 16, not 26) AND surfaced a missed Apple-documented alternative (`ENABLE_DEBUG_DYLIB=NO` opt-out, trading current/future SwiftUI Preview support on the executable target — degrades to legacy execution mode which Apple flagged for removal in a future Xcode build — for symbol consolidation in the main binary). Both corrections folded into the preceding V3 entry.
- **Proposed rule (to encode in @dispatch-implementer and @code-reviewer; feature-planner-side enforcement was attempted on 2026-05-11 and found infeasible — see next entry "feature-planner output channel rigidity"):** dispatch briefs for steps that touch third-party tool config must require a pre-flight doc check when ANY of the following hold:
  - (a) the V3 entry being implemented is older than ~1 month
  - (b) the tool has released a major version since the entry was written
  - (c) the recipe depends on a non-obvious tool-internal behavior (build-settings interaction, package-manager resolution order, simulator runtime behavior, linker/loader pathing)
  - (d) the entry's "Fix scope" includes phrases like "once X is in place, just do Y" — those are exactly the recipes most likely to have invisible tool-version dependencies
- **Scope of the rule update (status as of 2026-05-11):**
  - **@code-reviewer BLOCKING rule — SHIPPED** (commit `84156c9`, workflow-step-11): code-reviewer.md auto-BLOCKING list now catches third-party config changes (Xcode build settings, project.pbxproj keys, Package.swift, vendor framework defaults, scheme XML in xcshareddata) without doc-researcher pre-flight evidence. Downstream enforcement; fires at review time and names the specific @doc-researcher query required.
  - **@dispatch-implementer slash command template — DEFERRED to next workflow pass:** add a "Doc-researcher pre-flight" section to the brief template, defaulting to "NOT YET RUN — required before implementation" when the brief consumes a V3 entry. Upstream enforcement; complements (does not replace) the code-reviewer rule. ~30 min effort.
  - **@feature-planner system prompt — INFEASIBLE** (see next entry "feature-planner output channel rigidity"): three iterations on 2026-05-11 attempting to land a pre-flight gate in feature-planner.md all failed; the planner's output structure is template-shaped, not freely extensible via prompt-level mandates. Feature-planner-side enforcement is permanently deferred to the dispatch-brief-layer pivot above.
  - **CLAUDE.md cross-reference — DEFERRED to next workflow pass:** add a note under "External dependency configuration" linking to this V3 entry as the cautionary case. Bundles with the dispatch-implementer update above.
- **Trigger to revisit:** Bundle with the next workflow automation pass, alongside "Quarterly platform sanity review."
- **Cost estimate:** ~30 min: edit feature-planner system prompt + dispatch-implementer template + add CLAUDE.md cross-reference.

**Update 2026-05-11 — feature-planner side could NOT land. See next V3 entry "feature-planner output channel rigidity" for the diagnosis and the deferred-implementation plan.**

### feature-planner output channel rigidity — pre-flight enforcement deferred to dispatch-brief layer

- **What:** The doc-researcher pre-flight rule (preceding V3 entry) was intended to live in two places: (a) feature-planner's system prompt, so the planner surfaces a "Doc-researcher pre-flight status" line when consuming a V3 entry as ground truth; (b) downstream BLOCKING check in code-reviewer for third-party config edits without pre-flight evidence. The (b) side is straightforward and is scheduled as the workflow-bundle's Step 11. The (a) side — feature-planner surfacing — was attempted in three iterations on 2026-05-11 (workflow-bundle Step 10) and could not be made to land. All Step 10 edits to `.claude/agents/feature-planner.md` were reverted; the file is back to its pre-Step-10 state.

- **What was tried (three iterations, three structural approaches):**
  - **Iteration 1**: Added a new section `## Doc-researcher pre-flight triggers (when consuming a V3 entry as ground truth)` at the end of feature-planner.md, with the four objective triggers (entry age >1 month, tool major-version change, non-obvious tool-internal behavior, "once X is in place, just do Y" recipe phrasing) and a required output format. Synthetic verification: planner short-circuited on the recipe's precondition check (V3 entry's premise didn't hold against current code) and recommended closing the entry as obsolete — never surfaced the pre-flight gate at all.
  - **Iteration 2**: Added a "Precedence" paragraph at the top of the new section stating the gate fires regardless of precondition status, and renamed the section title from "triggers" to "gate (mandatory when consuming a V3 entry as ground truth)" to match the existing `## Concurrency scheduling assumptions (mandatory when ...)` section's structural pattern. Also added an explicit cross-reference: "When applicable, include a 'Doc-researcher pre-flight gate' entry in your output's 'Pre-flight gates' section alongside Concurrency and Self-critique — same shape, same prominence." Synthetic verification (with a sharpened test case where the precondition genuinely held — `STRING_CATALOG_GENERATE_SYMBOLS` flip): planner output included `Concurrency gate: N/A` and `Self-critique pass: clean` as before, but no `Doc-researcher pre-flight gate` entry. Triggers (a) and (c) clearly applied; planner ignored the section entirely.
  - **Iteration 3**: Pivoted from inventing a new output channel to riding the existing `## Decisions to surface` channel. Added a mandatory leading bullet: "MANDATORY when the plan is being built from a V3 entry consumed as ground truth: ALWAYS surface as the first two items in this list — (1) V3 entry age (months since written); (2) Doc-researcher pre-flight status." Synthetic verification: planner output's `## Decisions to surface` section enumerated three substantive decisions (scope of flip, adjacent setting `SWIFT_EMIT_LOC_STRINGS`, presence of `.xcstrings` catalog). NONE of them were the mandated V3-consumption items. Planner adopted the channel for its OWN surfaced decisions but did not adopt the prompt-mandated first-two items even when explicitly told they were mandatory and silence was a discipline violation.

- **Diagnosis:** feature-planner's output structure for "Decisions to surface" and "Pre-flight gates" sub-blocks behaves as a template-shaped surface rather than a freely-extensible one. Adding new sections that mandate specific lines in those sub-blocks does not reliably produce the lines, even when the rule is framed with the same syntactic shape as existing mandatory gates, even when the rule is added to a channel the agent already uses for similar content, even when the rule is explicit about output silence being a discipline violation. Three iterations across three structural approaches all failed in the same direction (the new line just doesn't appear). The agent IS engaging with the prompt — it surfaces useful pre-flight findings unprompted, applies the existing two gates by name, picks up scope questions and adjacent-setting questions — it just isn't extending its mandatory-output template to include a third gate or two new mandatory items.

- **Root-cause hypothesis:** feature-planner is an Opus-4.7-class agent with substantial existing structure in its prompt around "Decisions to surface" and the two gate sections. The agent's behavior pattern for those sections appears to be learned from the surrounding text shape and is resistant to extension via prompt-level mandates. This is not a fixable issue at the prompt-content level on this attempt; it likely requires either a different agent architecture (separate pre-flight agent invoked before planner), a different rule surface (dispatch-brief layer, see next bullet), or different model-time tooling.

- **Deferred implementation plan:** Move the doc-researcher pre-flight enforcement to the **dispatch-implementer slash command template** rather than feature-planner's system prompt. Specifically: edit `.claude/commands/dispatch-implementer.md` to include a mandatory "Doc-researcher pre-flight" section in the dispatch brief format, defaulting to "NOT YET RUN — required before implementation" when the brief consumes a V3 entry. The brief is generated by the slash command (main session), not by the planner, so the rule is enforced at brief-construction time rather than plan-generation time. Code-reviewer's downstream BLOCKING check (workflow-bundle Step 11) provides a second backstop independent of the planner — that step proceeds as scheduled regardless of this failure.

- **Trigger to revisit:** Next workflow automation pass. Implement the rule at the `/dispatch-implementer` slash command template layer. Probably ~30 min including testing.

- **Cost estimate:** ~30 min implementation (slash command edit) + a separate test against a synthetic V3 dispatch. The cost is shifted from "edit + verify planner prompt" to "edit + verify slash command template" — about the same effort, different surface.

- **What lands from this bundle's Step 10:** the diagnosis above (this V3 entry). feature-planner.md is unchanged from pre-Step-10 state. Code-reviewer's BLOCKING check (Step 11) is unaffected and will provide downstream enforcement regardless.

### Agent prompt hygiene — INFO findings from workflow bundle gate (2026-05-11)

The three-reviewer gate on the post-Phase-4 workflow automation bundle (pushed to `origin/main` 2026-05-11) surfaced eight LOW/MED INFO findings from @code-reviewer. Findings 2, 5, and 6 were addressed at gate time (finding 2 is the documented self-application caveat in Step 11's commit body; findings 5 and 6 in the immediate hygiene-pass follow-up commit `aa7b823`). The five findings below are real but not load-bearing and are logged here for the next workflow automation pass.

- **Finding 1 — `.claude/agents/code-reviewer.md:21` lacks Bash fallback for MCP-inheritance bug.** Process step 5 says "invoke `mcp__xcodebuildmcp__build_sim_name_proj`" with no fallback for cases where the subagent context cannot inherit MCP tools (the known Claude Code issue documented in CLAUDE.md "Build workflow" section). Pre-bundle issue, but Step 4's Opus 4.7 + report-all expansion made the build-verification step more load-bearing. **Fix:** add a parenthetical "(or `xcodebuild -project ... build` via Bash if MCP tools are unavailable in subagent context, per CLAUDE.md MCP-inheritance note)" to that line. ~5 min.

- **Finding 3 — `.claude/agents/code-reviewer.md:56` references unverifiable evidence source.** The Step 11 BLOCKING rule names "recoverable prior conversation turns" as a valid place for doc-researcher pre-flight evidence. From a fresh subagent dispatch, the reviewer has no access to prior conversation turns across invocations (no persistent memory). In practice the rule degrades to commit-body + dispatch-brief evidence only. **Fix:** either drop "or recoverable prior conversation turns" OR scope it explicitly ("when the reviewer is invoked in the same session, otherwise commit-body / dispatch-brief evidence only"). ~5 min.

- **Finding 4 — `.claude/commands/dispatch-implementer.md` predates the doc-researcher pre-flight rule.** The slash command template does NOT yet include the "Doc-researcher pre-flight" section that the preceding V3 entry "feature-planner output channel rigidity" explicitly defers to "the next workflow automation pass." This is Step 10's deferred work; tracked here so the dispatch-brief-layer enforcement actually lands and Step 11's downstream BLOCKING check has its upstream backstop. ~30 min.

- **Finding 7 — `.claude/commands/update-state.md:18` has unexplained second commit-subject prefix.** The amend branch's allow-list mentions both `docs: refresh current state for chat migration continuity` (used by step 8.3 of the command) AND `docs(state): refresh after` (origin unknown to a fresh reader). A future reader cannot tell whether the second prefix is legacy/dead or actively used. **Fix:** one-line comment clarifying the provenance of each prefix, or drop the unused one. ~5 min.

- **Finding 8 — `.claude/agents/swift-implementer.md:31` duplicates CLAUDE.md content.** The "Scope-and-decision discipline (sharpened post-Group-C)" section largely duplicates CLAUDE.md's "swift-implementer scope-and-decision discipline" section (same three rules, same Group C citations). Intentional per the section header (surfaced at dispatch time so the implementer cannot miss it), but it creates a sync hazard: future edits must be kept in sync across two locations. **Fix:** add a `[KEEP SYNCED WITH .claude/agents/swift-implementer.md:31]` comment in CLAUDE.md, or vice-versa. ~5 min.

**Total effort:** ~50 min for all five findings. Finding 4 is the load-bearing one (it carries the dispatch-brief-layer enforcement deferred from Step 10); the others are surgical hygiene. Bundle all five together in the next workflow automation pass.

**Trigger to revisit:** Next workflow automation pass.

### Agent prompt rules-as-pointers convention

**What:** Agent prompts in `.claude/agents/` currently duplicate content from CLAUDE.md. When rules update in one place, the other drifts. Group D gate findings (2026-05-11) surfaced this pattern in three separate code-reviewer findings: `swift-implementer.md` duplicates CLAUDE.md content needing a sync marker (Finding 8 in V3 entry "Agent prompt hygiene — INFO findings from workflow bundle gate"); `doc-researcher.md` and `code-reviewer.md` have similar duplication patterns (concurrency-discipline rules, scope-discipline rules, source-allowlist semantics). Proposed convention: agent prompts reference CLAUDE.md sections by name as pointers rather than duplicating text. Example: replace inline scope-discipline rules in `swift-implementer.md` with `See CLAUDE.md §"swift-implementer scope-and-decision discipline."`

**Why deferred:** Mid-session after a long workflow bundle. Convention change touches multiple agent prompts and needs deliberate design (when to point vs. duplicate, how agents handle pointer-resolution at runtime, what happens when CLAUDE.md isn't loaded into the subagent's context). Not a one-line fix.

**Trigger to revisit:** Next workflow automation pass, alongside Finding 8 cleanup (swift-implementer duplicate-content sync marker) and other agent prompt hygiene findings logged from the 2026-05-11 gate. Bundles naturally with the deferred dispatch-implementer doc-researcher pre-flight work.

**Effort:** ~1–2 hours. Design the pointer convention, audit all 11 agent prompts for duplicate-content cases, refactor with pointers, verify agents still behave correctly with the new structure.

**Risk:** Agents may not resolve pointers as reliably as inline rules — Step 10's three-iteration failure (V3 entry "feature-planner output channel rigidity") is the cautionary case that suggests agent prompts have template-shaped output surfaces that may not extend cleanly to pointer-based rule lookup. Verify with a small representative agent (probably `code-reviewer.md` — the most rule-dense) before wide adoption. If pointers degrade reliability, fall back to inline rules with explicit `[KEEP SYNCED WITH CLAUDE.md §X]` markers per Finding 8's narrower fix.

### swift-implementer scope-and-decision discipline (V3 entry sharpening)

The existing V3 entry "feature-planner system prompt update — concurrency scheduling-assumption rule" addresses the planner side. This entry tracks the parallel work for swift-implementer's system prompt. Sharpening points from Group C reviewer feedback:

1. "Surface in summary" is NOT "surface and pause." swift-implementer's system prompt must explicitly forbid post-hoc disclosure as a substitute for pre-decision pause. The agent must surface decisions BEFORE writing code that depends on them, not after.

2. Discarded tests must produce written diagnosis. Add to swift-implementer's system prompt: "If a test surfaces an unexpected failure, you must determine whether the test was wrong or production violated a contract. If unclear from inspection, that is a STOP condition. Discarding a test without diagnosis is forbidden."

3. Doc-comment claims that name test IDs must be verified. Add to swift-implementer's system prompt: "When writing a doc-comment that names a specific test ID as enforcing a contract, open that test, read it, confirm it actually enforces the documented behavior. Naming a test that doesn't is worse than not naming one."

**Bundle with:** existing V3 entries on @feature-planner self-critique rules, @dispatch-implementer slash command, feature-planner concurrency-rule update, and Test infrastructure as agent blind spot. All five compose into one workflow-and-test-infrastructure cleanup session.

**Trigger to revisit:** Post-Phase-4 workflow automation bundle.

### Dispatch-brief completeness — anticipate predictable git-state contradictions in MAY-touch scope

**What:** Implementation dispatch briefs (drafted by the main session for `@swift-implementer`) declare an absolute `MAY touch` / `MUST NOT touch` scope. The P-1 dispatch (commit `754225c`, "bundle LFM2 GGUF as app resource") listed `MAY touch` as `.gitattributes` + `ArigatoAI/Resources/Models/*.gguf` + `CLAUDE.md`. A pre-existing `*.gguf` rule in `.gitignore` (line 55 of the file at the time of dispatch) would have silently blocked the entire dispatch's purpose — `git add` against the new GGUF would have been ignored, and `git lfs ls-files` would have come up empty even with `.gitattributes` correctly configured. The implementer surfaced the contradiction and made the pragmatic call to add a surgical negation (`!ArigatoAI/Resources/Models/*.gguf` at line 64) plus a one-line comment update reflecting the new policy. Surfaced in the implementer's reply with reasoning. Per strict CLAUDE.md "swift-implementer scope-and-decision discipline," this should have triggered a STOP and redispatch — the implementer's call was a scope-discipline violation, defensible on pragmatic grounds.

**Shared root cause:** the dispatching session (main session) did not scan git-state files (`.gitignore`, `.gitattributes`) for contradictions before drafting the brief. The contradiction was predictable from the brief's content goal (commit a `*.gguf` file) but was not predicted. The implementer was left to either STOP+redispatch (clean but wasteful) or make the pragmatic call (efficient but technically out-of-scope). Either way, the brief should have listed `.gitignore` as MAY-touch with explicit instructions, OR pre-removed the conflicting rule in a preparatory commit, OR called out the contradiction explicitly for the implementer to handle.

**Concrete fix — three rules for the dispatching session when drafting implementation briefs:**

1. **Grep before drafting**: when an implementation brief adds or modifies files of a type that might be subject to git-state rules (large binaries, model files, build artifacts, generated code), the dispatching session must `grep` the relevant patterns in `.gitignore` and `.gitattributes` before listing `MAY touch` scope. Predictable contradictions belong in the brief, not in the implementer's diagnostic surface.
2. **List git-state files explicitly when relevant**: if `.gitignore` or `.gitattributes` need modification to support the dispatch, include them in `MAY touch` with the specific change required (e.g., "add `!ArigatoAI/Resources/Models/*.gguf` negation"). Don't rely on the implementer to make the call.
3. **Pre-remove conflicts in a preparatory commit when scope is large**: for multi-file dispatches where multiple `.gitignore` rules might conflict, draft a preparatory commit that handles the git-state cleanup separately. This keeps the implementation dispatch's MAY-touch scope smaller and the diagnostic load on the implementer cleaner.

**Why this is V3 (workflow improvement, not immediate code change):** the P-1 commit landed correctly via the implementer's pragmatic call. The improvement is for FUTURE dispatch briefs to anticipate this class of contradiction. Pattern-level workflow tightening; doesn't block anything in flight.

**Trigger to revisit:** next implementation dispatch where the main session is adding files of a type that might be git-ignored or otherwise git-state-managed. **Most immediate concrete check**: the P-2 atomic SDK migration brief (worktree-isolated). P-2 touches `Package.swift` / `Package.resolved` / `project.pbxproj` (Xcode SPM dependency change) and deletes the two spike files — none of these have predictable `.gitignore` contradictions, but verify before drafting.

**Effort:** ~5 min added to each implementation-dispatch drafting (grep `.gitignore` + `.gitattributes` for predictable contradictions). Lower if folded into a brief-drafting checklist; higher if surfaced as a hook or a doc-comment in the dispatch-implementer slash command template.

**Cross-references:**
- P-1 commit `754225c` — where this pattern surfaced.
- The P-1 dispatch brief (inline in the dispatching session's prior turn) — the source artifact whose `MAY touch` scope was incomplete.
- CLAUDE.md "swift-implementer scope-and-decision discipline" section — the rule the implementer's pragmatic call technically violated.
- V3 entry "swift-implementer scope-and-decision discipline (V3 entry sharpening)" (line 442) — the agent-side discipline this dispatch-side rule complements.
- V3 entry "feature-planner output channel rigidity — pre-flight enforcement deferred to dispatch-brief layer" (line 391) — the existing entry that already moves enforcement to the dispatch-brief layer; this entry extends that thread to git-state scope completeness.
- V3 entry "doc-researcher source-not-found discipline" bullet (commit `8e785a0`) — same dispatch-discipline family; both are about pre-dispatch verification rigor.

**Severity:** LOW — pattern-level workflow improvement. The implementer's pragmatic call worked; catching this earlier would have saved one round of post-hoc surfacing in the commit body. Compounds gradually if not addressed — each future dispatch with similar git-state contradictions adds one cycle of surfacing or one technical scope violation.

### Process trim — Group C closure decisions

**Status (2026-05-10):** Trigger fired (end of Group D). Pending review: did the trim deliver expected results? Re-evaluate during post-Phase-4 retrospective alongside this bundle.

This entry documents the workflow trim applied at Group C closure on May 10 2026, so future-you knows what was decided and why.

**Decisions applied (committed in the same commit as this entry):**
- New CLAUDE.md "Rollback safety" section: checkpoint commits at every step boundary, mandatory
- New CLAUDE.md "feature-planner output discipline" section: target 5-8 surfaced decisions per plan, planner self-filters trust-the-planner items
- New CLAUDE.md "swift-implementer scope-and-decision discipline" section: scope is absolute, "surface in summary" is not "surface and pause," discarded tests need diagnosis, named test IDs must be verified
- Existing "Concurrency design discipline" section restored from recovery tag with doc-comment-honesty amendment

**Workflow changes (not encoded in CLAUDE.md, but applied to Group D and beyond):**
- Doc-researcher pre-flight checks: situational, not default. Run only when (a) third-party library at v1.x with known quirks, (b) planner flags uncertainty, (c) brief depends on unfamiliar API
- Screenshot cadence: only hard pauses, decision points, and surprises. Skip routine progress updates
- Supervisory model: routine continuations go directly to Claude Code without round-trip; bring strategic-thinking-partner in for architectural decisions, plan reviews, recovery situations, surprises
- V3 backlog hygiene: log entries as encountered, not deferred to end of session

**Why this trim:** Group C took ~8 hours including a 2-hour recovery from working-tree corruption. Approximately 15-20% of that time was avoidable — over-supervision, over-formatting of plan output, screenshots of routine progress. The trim targets that overhead while preserving the gates that paid for themselves (three-reviewer gate, doc-researcher when warranted, plan review).

**Trigger to revisit:** End of Group D. Re-evaluate whether the trim worked, whether further trimming is needed, or whether any dropped gates should be restored.

### AudioCaptureViewModel router param: optional → required

**What:** Group D Step 3 makes the router parameter optional on AudioCaptureViewModel so Step 3 can land before Step 5 wires it up. Once Step 5 ships and the bootstrapper is the only construction path in production, the optional should become required.

**Why it shipped this way:** Incremental step landing — Step 3 had no router to pass yet, optional unblocked the checkpoint commit.

**Trigger to revisit:** After Group D ships, before Phase 5 kickoff. Bundles naturally with the post-Phase-4 workflow automation cleanup.

**Effort:** ~10 minutes. Make param required, update construction sites (should be just AppBootstrapper), confirm tests pass.

### TranscriptionActorTests withLock unused-result warning

**Status (2026-05-21):** ✅ **RESOLVED in B2.1** (commit `d54bec3`, bundled with B1.2). Fix shape: `_ = snapshot.throwOnCall.insert(n)` inside the existing `withLock` closure — discards the `Set.insert` return tuple so the closure returns Void and `withLock` is no longer flagged. Localised to the actual discard site rather than wrapping `withLock` itself.

**What:** TranscriptionActorTests.swift:51 emits a "result of call to 'withLock' is unused" compiler warning. Pre-existing; surfaced during Group D Step 1 verification. Not Step 1's responsibility — predates the change.

**Why deferred:** Group D scope discipline. Mid-group warning cleanup violates the swift-implementer scope rule. Carrying forward as a known-clean fix.

**Trigger to revisit:** Pre-MVP-1 hardening bundle, alongside the cancel-test timing race fix and awaitUpstreamDrained → DEBUG-only extension cleanup.

**Effort:** ~5 minutes. Either use the result, prefix with `_ =`, or wrap in a discardable-result helper.

### Adopt Anthropic prompting best practices for Opus 4.7

**What:** Two updates to subagent prompts based on Anthropic's published Opus 4.7 prompting best practices (reviewed 2026-05-10).

1. **code-reviewer report-all pattern**: Update code-reviewer's system prompt to report every finding with confidence and severity tags, with filtering deferred to downstream review. Opus 4.7 follows "only report important issues" too literally and silently drops low-severity findings. The fix: prompt for coverage at finding stage, filter at gate stage. Reference language from Anthropic's published guidance.

2. **Destructive-action confirmation language**: Adopt Anthropic's recommended prompt language for actions that are hard to reverse, affect shared systems, or could be destructive. Apply to git-historian and any agent that performs push, delete, or modify-shared-resource operations. Also reflect in CLAUDE.md operational rules. The Group D Steps 1+2 inadvertent push to origin is the exact failure mode this language prevents.

**Why deferred:** Mid-Phase-4. System-prompt changes during active features violate the workflow rule. Bundles naturally with the post-Phase-4 workflow automation work.

**Trigger to revisit:** Post-Phase-4 workflow automation bundle. Add ~30 minutes to that session for these two updates.

**Effort:** ~30 minutes total — read Anthropic's reference language, adapt to project subagents, test against a representative dispatch.

**Source:** https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices

### Group D UI deferred concerns — Phase 7 polish

**Partial closure (Step 9b, 2026-05-16, checkpoint `738c253`):** concerns 1, 2, and 4 closed by Step 9b's minimal design-language consolidation. Concerns 3, 5, 6, 7 remain deferred to Phase 7 polish per V3 #22 trigger.

**What:** Group D end-of-group gate ui-review surfaced 8 visual concerns. Concern 6 (duplicate "listening…" hint) was fixed pre-push (commit `3b7c311`, locked by D4-T-concern6). The remaining 7 concerns are deferred to Phase 7 polish:

1. **`Color.green` warmup-loaded fallback** (`TranscriptLiveView.swift:349`) — no "ready" semantic token in `DesignTokens.swift` yet. Phase 7 should re-token. Verify hue does not clash with `recordingActive` red. **CLOSED Step 9b (2026-05-16, checkpoint `738c253`)**: `Color.green` replaced with `DesignSystem.Colors.recordingReady` (`Color(red: 0.26, green: 0.66, blue: 0.45)`); chromatic distance from `recordingActive` locked by `DesignSystemTests.recordingReady_hueDistinctFromRecordingActive`.

2. **Failed-state error text + dot both render in `Color.recordingActive`** (`TranscriptLiveView.swift:141`) — two adjacent red elements may overload the chrome region and compete with captions for attention. Suggest error text uses `.secondary` foreground; let the dot alone carry the semantic-error color. **CLOSED Step 9b (2026-05-16, checkpoint `738c253`)**: error text foreground switched to `.secondary`; warmup dot continues to use `Color.recordingActive`; test seam added via new `IndicatorChromeDisplay.warmupErrorTextUsesSecondaryForeground` property; contract locked by `DesignSystemTests.transcriptLiveView_failedStateErrorText_usesSecondaryForeground`.

3. **Footer placement under home indicator at large Dynamic Type** (`TranscriptLiveView.swift:80–82`) — at `.accessibility3` and above, "Audio never leaves your iPhone." footer may push under the home indicator on iPhone 17 Pro Max. Verify and adjust safe-area insets.

4. **List rows edge-to-edge vs chrome 20pt inset → row badges misalign with chrome badge** (`TranscriptLiveView.swift:156–164`) — list does not apply horizontal padding while chrome and footer are inset 20pt. Right-edge JA/EN row badges do not line up with the chrome's JA/EN badge. Add matching horizontal padding to list rows. **CLOSED Step 9b (2026-05-16, checkpoint `738c253`)**: `.padding(.horizontal, 20)` added to the `List` inside `transcriptList`, matching chrome and footer insets.

5. **`arrow.triangle.2.circlepath` SF symbol semantically wrong** (`TranscriptLiveView.swift:267`) — semantically a "refresh" glyph, not a "fallback/divergence" glyph. Users familiar with SF Symbols may misread as "tap to retry." Candidates that read more honestly: `arrow.left.arrow.right` (lateral motion = swap), `questionmark.diamond`, or a custom mark. Phase 7 should pick a semantically honest glyph.

6. **`PopulatedPreviewWrapper` is hand-written copy of layout, not real `TranscriptLiveView`** (`TranscriptLiveView.swift:817–882`) — necessary today because `routedHistory` is `private(set)`. Practical consequence: any future layout change in `TranscriptLiveView.body` must also be made in `PopulatedPreviewWrapper.body` or the populated previews lie about the real layout. Phase 7 should rewrite to drive a real router via a `.task` modifier so previews track production layout automatically.

7. **Chrome HStack truncation at extreme Dynamic Type** (`TranscriptLiveView.swift:115`) — at `.accessibility3` and above, the language hint + warmup label + failed-state error text could wrap or truncate. Chrome HStack does not switch to vertical layout. Verify behavior and add a vertical fallback if needed.

**Why deferred:** Group D is functional plumbing; Phase 7 is the polish phase. These are visual / typography / SF symbol semantic concerns that fit the design-language pass naturally. Bundling them avoids piecemeal Phase 4 design churn that would be redone in Phase 7 anyway.

**Trigger to revisit:** Phase 7 kickoff. Bundle with the existing Phase 7 design language direction (V3 #22) and the @design-system subagent decision.

**Effort:** Each concern is small (~10–30 minutes). All seven together: ~3 hours, mostly bundled within the Phase 7 design-token + component-library work.

**Note also:** ui-reviewer agent did not capture screenshots during the gate due to MCP-inheritance bug (V3 #23). Main session captured screenshots via XcodeBuildMCP. Concerns 1, 5, 6, 7 are static-code observations; Concerns 2, 3, 4, 8 require visual verification at non-default Dynamic Type sizes that the main-session capture did not exercise. Phase 7 should verify all eight at AX1, AX3, AX5 sizes plus default.

---

Updated: May 10 2026

---

## Competitive observations (May 2026)

### User-tunable latency/accuracy slider
- **What:** Per-meeting adjustment of how aggressively the app waits for sentence completion before translating. Inspired by OpenAI's GPT-Realtime-Whisper "delay selector" demo.
- **Why deferred:** Adds settings complexity to MVP 1. Best added once we have real meeting feedback on what default latency feels like.
- **Trigger to revisit:** After 5 real meeting tests, if you find yourself wishing for either faster (less accurate) or slower (more accurate) captions in different contexts.

### Streaming UX while LFM2 translates ("preamble" pattern)
- **What:** Display Japanese live as Whisper streams it, show "translating..." indicator below, fill in English when LFM2 completes. Avoids 1-2s dead-air feeling between source and translation.
- **Why deferred:** Phase 7 UI polish concern, not architecture.
- **Trigger to revisit:** During Phase 7 (UI polish).

### JP-WER head-to-head benchmark (LFM2+Whisper vs GPT-Realtime-Translate)
- **What:** Same Japanese business meeting audio sample run through both pipelines. Measure word error rate, latency, keigo register preservation.
- **Why deferred:** Not blocking MVP 1. Our Apollo vibe-check is sufficient evidence for our use case.
- **Trigger to revisit:** If MVP 1 translation quality disappoints in real meetings, OR if you're considering Roche app store distribution and need a defensible accuracy claim.

---

## Future model evaluation

### Test larger LFM2 models on iPhone 17 Pro Max
- **What:** Evaluate LFM2-700M (and LFM2-1.3B if Q4 quantization fits) against current 350M baseline.
- **Why deferred:** Current 350M is good enough for MVP 1; size/quality tradeoff unproven for our specific Roche use case.
- **Gating criteria for adoption:** Must run at <200ms per sentence on Neural Engine, must show measurable improvement on Roche-relevant JA business phrases (not generic benchmarks), must not increase app launch time beyond 2s, must not consume so much memory that other apps get killed in background.
- **Trigger to revisit:** After 5+ real meeting tests, if 350M misses keigo nuances or technical terminology consistently.

### Evaluate Gemma 4 / TranslateGemma as alternatives
- **What:** Google's open-weight translation models. TranslateGemma 4B/12B available, Gemma 4 E4B mobile-optimized.
- **Why deferred:** Per Google's own technical report, TranslateGemma shows a **regression on Japanese→English** (worse named-entity translation) — exactly the failure mode that hurts Roche use cases. Memory footprint also too large for our constraints (~4GB for E4B vs ~250MB for LFM2-350M). iOS integration story (LiteRT-LM) more complex than LEAP iOS SDK.
- **Trigger to revisit:** If we ever expand beyond JA↔EN to support more APAC languages (Mandarin, Korean), TranslateGemma's multilingual coverage becomes interesting as a fallback for non-JA pairs while LFM2 stays primary for JA↔EN.

---

## Pre-Phase-5 strategic walkthrough (2026-05-12)

### Liquid AI / LFM2 model updates monitoring

- **What:** Add Liquid AI and LFM2 model family to the weekly brief's external monitoring scope. Watch for new LFM2 variants, new ENJP-MT models, LEAP iOS SDK releases, and Apollo app feature changes that signal model improvements. Today's Phase 5 strategic walkthrough confirmed LFM2-350M-ENJP-MT as the locked choice for MVP 1, but a newer variant could shift the cost-benefit before we have real-meeting data to gate the V3 #35 upgrade trigger.
- **Why deferred:** Monitoring only, no project change required. Bundles with existing daily/weekly brief routines.
- **Trigger to revisit:** When brief surfaces a Liquid AI release, model variant, or SDK change. Re-evaluate against V3 #35's gating criteria (sub-200ms sentence latency on Neural Engine, measurable Roche-relevant JA accuracy gain, no app launch time bloat, no memory pressure killing other apps).
- **Cost estimate:** Brief subscription update, ~5 min.

### Local-only diagnostics for performance tuning

- **What:** Add structured local-only diagnostic logging to the transcription/translation pipeline. Captures per-window Whisper inference time, per-sentence LFM2 translation time, language router gate behavior (N=2 firings, detected-vs-authoritative mismatches), LFM2 cache hit rate, memory/thermal peaks, segments/sentences per meeting. Logs stored in app sandbox, one file per meeting, auto-rotate to last 30. Exposed via Settings "Diagnostics" screen showing last meeting + 7-day averages. Manual export via share sheet (Markdown or JSON) for offline analysis.
- **Why deferred:** MVP 1 must ship first. Diagnostics earns its keep only when real meeting data exists. Phase 6 introduces SwiftData persistence — natural moment to add diagnostic persistence alongside transcript persistence.
- **Privacy commitment:** All diagnostic data is local-only. Will codify into CLAUDE.md when built: "Diagnostic logs never leave the device. No send-diagnostics feature even with opt-in. Only export path is explicit user-initiated file share."
- **Trigger to revisit:** Phase 6 kickoff (SwiftData persistence work), OR if a specific performance issue surfaces before then that requires measurement.
- **Cost estimate:** ~1–2 days. Instrumentation hooks at existing actor boundaries (zero new hot paths), structured logging format, diagnostics view in Settings, file rotation logic, share sheet export.
- **Performance impact:** <1% overhead. Memory: few KB per meeting. Disk: ~50–200KB per 2-hour meeting, ~20MB cumulative after 100 meetings. No battery impact.
- **Drives future V3 decisions:** validates N=2 gate calibration, validates window/hop sizing, drives cache strategy revisit (#47 in-memory vs persistent), informs LFM2 model upgrade trigger (#35), supports latency slider design (#32).

### LFM2 cache strategy — SUPERSEDED 2026-05-15 by xcframework-driven Decision 4 revision

- **Original framing**: Phase 5 ships with in-memory only cache (`LiquidCacheOptions` in-memory). Strategic walkthrough chose this over persistent on-disk because: (a) LFM2's prompt cache is inference-acceleration via KV-state, not translation-memory across sessions — cross-meeting hit rate likely near zero; (b) persistent cache in Documents folder backs up to iCloud by default, conflicting with CLAUDE.md "no cloud sync" privacy stance; (c) MVP discipline prefers simplest design that delivers value.
- **2026-05-15 revision**: Step 0 xcframework inspection (pre-Group-C feature-planner dispatch) discovered `LiquidCacheOptions` in LEAP iOS SDK v0.9.4 is a struct with REQUIRED `path: String` + `maxEntries: Int`, NOT an enum. No `.inMemory` case exists. The original "in-memory only" lock cannot be implemented through the SDK's type surface. User call: use a persistent path under iOS's Caches directory with `maxEntries: 1000`. Caches/ is NOT iCloud-backed (Apple architecture), so privacy stance is preserved at the architecture level even with persistence enabled. iOS auto-purges Caches/ under storage pressure. See PHASE_5_HANDOFF.md Decision 4 (revised) for full reasoning.
- **Replacement V3 entry**: "LFM2 prompt cache effectiveness benchmark" below.

### LFM2 prompt cache effectiveness benchmark

- **What**: Phase 5 Group C ships with `LiquidCacheOptions(path: <Caches/leap-cache>, maxEntries: 1000)` per revised Decision 4 (xcframework-driven, 2026-05-15). Verify in Phase 6 diagnostics whether this delivers measurable per-sentence inference speedup on iPhone 17 Pro Max. Goal: distinguish "cache delivers value" from "cache is overhead noise we should drop for simplicity."
- **Why filed**: The revised cache decision was driven by performance > privacy weighting plus "flipping back is trivial." That hedge requires real data to act on. Without measurement, the cache stays enabled by default forever even if it doesn't help.
- **Measurement plan**:
  - Phase 6 local-only diagnostics (V3 #46) must log per-`generateResponse(...)` inference time AND a cache-hit signal if the SDK exposes one (verify in Phase 6 doc-research pre-flight against LEAP SDK telemetry surface).
  - Comparison: A/B test with `cacheOptions: nil` vs the persistent config, ~50–100 sentence pairs per side, on iPhone 17 Pro Max.
- **Trigger to revisit**: After Phase 6 diagnostics ship AND accumulate ~1 week of real meeting data. Possible outcomes:
  - **Savings <20ms per sentence**: flip to `cacheOptions: nil` for simplicity. One-line change in `LFM2ModelLoader` (or wherever Group C wires the engine options).
  - **Savings 20–100ms per sentence**: keep at `maxEntries: 1000`, document the baseline, monitor.
  - **Savings >100ms per sentence**: tune `maxEntries` upward based on observed cache hit patterns. Consider stricter cache-warming strategy at app launch (preload common system-prompt prefixes).
- **Cost estimate**: ~1–2 hours instrumentation + ~30 min analysis once data accumulates.

---

## Workflow risks

### Xcode auto-update interrupts active feature work
- **What:** macOS auto-installed Xcode 26.5 (Build 17F42) mid-Phase-5-kickoff on 2026-05-12. The 26.5 component installer is modal with no skip/close affordance — Apple forces the platform support download. Builds blocked until iOS 26.5 platform installed. ~30 min interruption between the toolchain bump being detected and 125/125 green being re-verified.
- **Why deferred:** not a fixable issue per se — Apple controls Xcode update cadence. Worth recording the pattern so the next occurrence is faster to resolve.
- **Mitigation options when revisited:** (a) disable Xcode auto-updates in System Settings → General → Software Update → Automatic Updates; (b) use `xcodes` CLI or `xcode-select` to pin a specific Xcode version per project; (c) accept Apple's cadence and treat platform-install interruptions as a known ~30-min tax.
- **Trigger to revisit:** next time an Xcode auto-update blocks active work, OR if the project moves to a CI/CD setup where toolchain pinning becomes load-bearing.
- **Bonus item to evaluate when revisited:** whether to create a fresh iPhone 17 Pro Max sim on iOS 26.5 runtime. Today the existing sim is locked to iOS 26.4 and `useLatestOS: true` would pick 26.5 if a 26.5 sim existed. For Phase 5, iOS 26.4 sim is correct because it matches the deployment target. Reassess at Phase 7 or when deployment target bumps.

### swift-implementer false-GREEN build reporting
- **What:** swift-implementer self-reported "GREEN, 0 warnings" on Phase 5 Group B Steps 3-7 (2026-05-12) without running an authoritative XcodeBuildMCP build, despite the build surfacing 2 Swift 6 strict-concurrency warnings in code the implementer wrote (`AppBootstrapper.swift:189` MainActor-isolated forward + `AppBootstrapper.swift:217` captured-var-self in Task). The warnings were caught only because the main session re-ran the build via XcodeBuildMCP after dispatch return per CLAUDE.md.
- **Why this is a discipline gap:** subagents in this project may fall back to raw `xcodebuild` via Bash due to the known MCP-inheritance bug (V3 #23). When that happens, the implementer's local "build green" check may not parse all warning text — some `xcodebuild` exit modes report success while still emitting warnings to stderr. The implementer treated build-exit-success as "0 warnings" without re-reading output. The dispatched brief also did not explicitly require warning-by-warning parsing.
- **Discipline rule needed:** implementers must run authoritative build via XcodeBuildMCP (not raw xcodebuild) AND parse output for ALL warning text before reporting completion. "Build succeeded" is necessary but not sufficient — the report must explicitly list "warnings: 0" or enumerate each warning observed. This rule must be added to `.claude/agents/swift-implementer.md` and to CLAUDE.md as a gate rule that applies pre-checkpoint-commit.
- **Action when revisited:** edit `.claude/agents/swift-implementer.md` to add the warning-parsing requirement under "Process" / "Hard rules"; edit CLAUDE.md to require the implementer's per-step report enumerate warnings explicitly; consider whether end-of-group reviewer-gate should re-run the build and diff warnings against the implementer's claim.
- **Trigger to revisit:** before next swift-implementer dispatch, OR before Phase 5 Group C kickoff, whichever comes first.
- **Cost estimate:** ~15 min for the prompt edits. Bundles naturally with the simulator-state-accumulation entry below — same session, same group, both workflow-discipline gaps.

### Simulator state accumulates during long sessions, breaks test runs
- **What:** After multiple test runs, interrupted dispatches, and warning-fix retries within a single session (Phase 5 Group B, 2026-05-12 to 2026-05-13), the iOS simulator (UUID `8BF8B150-...`) accumulates state that causes the next test run to hang. Specific failure mode: two `xcodebuild test` processes against the same sim UUID deadlock on `testmanagerd`. UI test runner launch ("Simulator device failed to launch") was the surface symptom.
- **Why this happened:** Apple's simulator doesn't handle concurrent test invocations well. XcodeBuildMCP doesn't enforce serialization. Combined with an earlier "sim resource-exhausted" implementer report that left state lingering, the next test attempt hit the leftover mess. Even `xcrun simctl shutdown all` followed by retry did not fully recover within the same session — a longer-lived state leak somewhere in CoreSimulator.
- **Mitigation options when revisited:**
  - (a) Run `xcrun simctl shutdown all` at the start of every new Claude Code session (cheap hygiene step).
  - (b) Add a pre-test-run check to `swift-implementer.md`: "verify no other `xcodebuild test` processes are running before invoking `test_sim`."
  - (c) When a `test_sim` call times out or returns a sim-launch error, automatically run `simctl shutdown all` AND `killall -9 testmanagerd Simulator` (or equivalent) before retry instead of retrying directly against the same sim.
  - (d) Investigate whether XcodeBuildMCP can serialize concurrent test invocations against the same sim UUID as a feature request.
- **Trigger to revisit:** next time a test run hangs or returns "Simulator device failed to launch" — OR opportunistically during the next swift-implementer.md / CLAUDE.md hygiene pass.
- **Note:** bundles naturally with V3 entry on "swift-implementer false-GREEN reporting" above — same session, same group, both workflow-discipline gaps that surfaced in Phase 5 Group B.

### Xcode 26 simulator test hang (documented regression) — DISPUTED 2026-05-15
- **Original claim:** Xcode 26.x + iPhone 17 Pro simulator + Thread Performance Checker enabled causes `testmanagerd` to deadlock with the test runner. Cited Apple Dev Forums, CircleCI Discuss, GitHub Actions `runner-images` #13264.
- **2026-05-15 revisit:** Full 167-test suite ran clean in 62.5s (sequential, TPC + MTC enabled, NO `OS_ACTIVITY_DT_MODE` workaround) on Xcode 26.5 + iOS 26.4 sim. Log scan of the original 2026-05-13 "hang" log shows the run died at `LFM2ModelLoaderTests/V3 loadIfNeeded after cancellation does not strand the loader` — the V3 cancellation deadlock test, NOT a testmanagerd issue. The cited external reports of testmanagerd+TPC interaction may exist for other projects, but for THIS project the hang was the V3 deadlock all along (fixed in commit `a49a93b`). The workaround was never load-bearing here.
- **Recommendation:** if a future test run hangs, do NOT default to `OS_ACTIVITY_DT_MODE=disable`. Capture the stuck test name first; the hang is more likely a project-side concurrency issue than a testmanagerd regression.

### Re-enable Thread Performance Checker and Main Thread Checker — RESOLVED 2026-05-15

What: During Phase 5 Group A and Group B test debugging, the team disabled TPC + MTC via `OS_ACTIVITY_DT_MODE=disable` passed at test invocation time, attributing test hangs to a documented Xcode 26 + TPC + testmanagerd regression. Post-Fix-A verification was needed to determine whether the workaround was load-bearing or masking the real V3 deadlock.

Resolution (2026-05-15): Full 167/167 test suite passed clean in 62.5s with TPC + MTC at default (enabled), sequential mode (`-parallel-testing-enabled NO`), no env var workaround, on sim `930EC6EA-DA72-4A38-ABFF-583AD70B28D4` (iPhone 17 Pro Max, iOS 26.4). 0 failures, 0 warnings, 0 errors. The workaround was never persisted in any project file — it was passed ad-hoc as a `test_sim` parameter at each invocation — so "re-enabling" required no code change, just running tests without that parameter.

Bonus log scan finding: the 2026-05-13 hang log (`test_sim_2026-05-13T15-02-35-816Z_pid4566_c022a863.log`) shows execution stopping mid-test at `V3 loadIfNeeded after cancellation does not strand the loader` — the exact test where Fix A landed. Confirms the "testmanagerd hang" diagnosis was misattributed; the real cause was the V3 cancellation-bridging deadlock, not infrastructure.

Action: stop passing `testRunnerEnv: {"OS_ACTIVITY_DT_MODE": "disable"}` to `XcodeBuildMCP test_sim`. If a future hang appears, diagnose the stuck test first — do not reflexively re-apply the workaround.

### `xcode` MCP server failing on Claude Code startup — RESOLVED 2026-05-15 (commit 0c25820)

What: User MCP `xcode` (separate from `XcodeBuildMCP`) failed to start every Claude Code session. Diagnosis: Apple's `xcrun mcpbridge` requires Xcode.app to be running with a project open — it fatal-errors at startup otherwise (`mcpbridge/MCPBridge.swift:32: Fatal error: MCP_XCODE_PID environment variable not set and no running Xcode processes found`). Initial "appears unused" framing was incorrect — `xcode` MCP exposes `DocumentationSearch` (canonical Apple/Swift/iOS API source, semantic search over Apple Developer Docs + WWDC transcripts) and `RenderPreview` (SwiftUI preview snapshots without sim boot), neither replicated by XcodeBuildMCP.

Resolution: Hybrid — kept the MCP, added a SessionStart hook (`.claude/hooks/auto-open-xcode.sh`) that auto-launches Xcode with this project's `.xcodeproj` if not already running. Hook is idempotent and tolerant of failure. Wired in both `.claude/settings.json` (checked-in, shared) and `.claude/settings.local.json` (gitignored, local). CLAUDE.md updated with "Xcode MCP server dependency" section; doc-researcher / build-doctor / ui-reviewer prompts updated to reference DocumentationSearch as canonical Apple-side source.

### xcode MCP SessionStart hook monitoring

What: The auto-launch hook from V3 #50 resolution should be monitored for friction. Possible failure modes: (a) slow Xcode cold-start meaningfully delays Claude Code start (hook polls up to 10s + 2s settle); (b) hook fires for non-Arigato-AI sessions if Claude Code is launched outside this project root (should not happen — project-local `.claude/settings.json` only loads in this CWD, but verify); (c) the polling interval is wrong for some workflows (always too long, or not long enough so mcpbridge still races); (d) Xcode auto-update is in progress and the hook silently times out; (e) hook script path resolution breaks if `.claude/hooks/` is moved or symlinked.

Why deferred: Resolution just landed (2026-05-15). Need real session-start telemetry to know whether it's actually helpful or actively annoying.

Trigger to revisit:
- If Claude Code session start feels noticeably slower than before 2026-05-15
- If `xcode` MCP failures resume (run `/mcp` to verify the hook is doing its job)
- If the hook fires inappropriately (e.g., for sessions where Xcode shouldn't open)
- If new Xcode version changes mcpbridge startup behavior

Action when revisited:
- Time the hook directly: `time .claude/hooks/auto-open-xcode.sh` — should be <1s when Xcode is running, <15s when launching cold
- Inspect `claude --debug` output for the `xcode` MCP server during a representative session
- Consider replacing the polling with an `osascript -e 'tell application "Xcode" to launch'` + AppleEvent wait, which may be more deterministic than pgrep polling

Cost estimate: ~15 min.

### Group B test execution blocked by Xcode 26 testmanagerd hang
- **What:** Phase 5 Group B test suite execution was blocked 2026-05-12 by the documented Xcode 26 simulator regression. Tests compile and are discovered (167 total, matches plan) but cannot execute — `testmanagerd` deadlocks with the test runner on iPhone 17 Pro sim.
- **Workarounds tried:** `simctl shutdown all` + retry, isolated `-only-testing` flag, `OS_ACTIVITY_DT_MODE=disable` env var via `XcodeBuildMCP testRunnerEnv`. None resolved the hang.
- **Code state:** build verified GREEN, 0 errors, 0 warnings. Logic reviewed via end-of-group gate. Risk of unverified test run is low because:
  - (a) build compilation is clean
  - (b) plan was thoroughly reviewed before implementation
  - (c) feature-planner self-critique applied
- **Trigger to revisit:**
  - (a) Apple ships Xcode patch fixing `testmanagerd`, OR
  - (b) Try a fresh iOS 26.5 simulator runtime (we never tested with 26.5 sim, only 26.4), OR
  - (c) Try erasing the simulator with `simctl erase` before next test attempt.
- **First action next session:** `simctl erase` the sim, boot fresh, run tests once. If still hangs, escalate to creating new iPhone 17 Pro sim on iOS 26.5 runtime.

---

## Documentation hygiene

### CURRENT_STATE.md test-baseline drift — sync rule
- **What:** During Group C closeout, the documented test baseline in `docs/CURRENT_STATE.md` was recorded as "204/204 tests passing (198 unit + 6 UI)". Group D Step 1 (2026-05-16) ran the suite empirically and observed 208 unit + 6 UI = 214 total *after* its +7 new tests, which means the real Group C baseline was 201 unit + 6 UI = 207 total — three unit tests had landed during Group C without the baseline figure being updated.
- **Why it happened:** Group C produced 10 step-checkpoints + 3 fix commits. The test-count figure in CURRENT_STATE.md was written at end-of-group rather than refreshed at each checkpoint, and the closing pass either miscounted or missed late-landing tests. The doc never said anything *wrong* about correctness — all tests passed — but the count itself drifted.
- **Trigger to revisit:** every checkpoint that adds or removes tests must update the CURRENT_STATE.md test-baseline figure in the same commit. @swift-implementer's commit step at end of every step is the natural enforcement point; @code-reviewer at the three-reviewer gate verifies the figure matches reality.
- **Cost estimate:** zero ongoing cost if folded into checkpoint discipline. The cost of *not* doing it is one suite-run + doc-fix commit per group, which is what we paid here.

### `.claude/skills/leap-sdk/SKILL.md` — reconcile phantom v0.10.4.3 framing
- **What:** SKILL.md currently contains phantom-version claims discovered during the Phase 5 kickoff version-pin cleanup pass (2026-05-12). Line 9: "Minimum target version: v0.10.4.3 (released 2026-05-07)" — the version tag does not exist in the public `Liquid4All/leap-ios` repo, and the release date is unverified. Line 11: "Avoid the older `KotlinUInt` wrapping pattern seen in pre-v0.10.4.3 tutorials" — same phantom-version premise.
- **Why deferred:** not a simple string substitution. The v0.10.4.3 framing is load-bearing for the skill's guidance — the entire "Recent SDK changes (May 2026)" section (and possibly the `KotlinUInt` advice) is built on the assumption that a version newer than v0.9.4 exists with specific API improvements. Without verified evidence of what those changes actually are (or whether they exist at all), substituting v0.10.4.3 → v0.9.4 would silently propagate stale or fabricated guidance. The fix requires deciding what the file should actually say after verifying current LEAP SDK API surface against v0.9.4 source tree.
- **Action when revisited:** (a) read `.claude/skills/leap-sdk/SKILL.md` end-to-end; (b) for every claim tied to v0.10.4.3, verify against v0.9.4 source tree + docs.liquid.ai; (c) rewrite or delete unverifiable claims rather than substitute the version string; (d) cross-reference `docs/PHASE_5_DOC_RESEARCH.md` for what's known to be true in v0.9.4. Likely a 30–60 min focused rewrite, not a one-line edit.
- **Trigger to revisit:** next time the LEAP / Liquid AI skill is invoked (e.g., during Group B SPM-add work or any LFM2 debugging), OR before Phase 6 kickoff, whichever comes first.
- **Cost estimate:** ~30–60 min for the rewrite, plus any incidental @doc-researcher pre-flight if claims are uncertain.

---

## Phase 5 Group C follow-ups (filed 2026-05-16 at end-of-group reviewer gate)

### TranslationActor queue cap revisit if real meetings hit it

- **What**: Phase 5 Group C ships with `TranslationActor.maxQueuedSentences = 20` and a drop-newest overflow policy (`enqueue(_:into:)` in `ArigatoAI/Translation/TranslationActor.swift`). The cap was picked as a defensible best-guess for "live meeting" backpressure (roughly: 20 sentences × 5s/sentence-of-translation budget = 100s of LFM2 backlog before drops start). Drop-newest diverges from `TranscriptionActor` C30's drop-oldest because sentences are coarser and irrecoverable.
- **Trigger to revisit**: ANY meeting test where `actor.droppedNewestCount() > 0` is observed (i.e., the queue actually hit the cap), OR if MVP 1 users report "translations went missing mid-meeting." Phase 6 diagnostics (V3 #46) should surface this counter to local-only logs.
- **Action**: review what produced the drop (speaker rate? LFM2 inference latency?), tune `maxQueuedSentences` upward or move to a smarter policy (drop oldest queued; preserve a "recent N" plus "earliest 1" pattern; etc).
- **Cost estimate**: ~30 min if the cap just needs tuning; ~2 hours if the overflow policy needs redesign.

### ModelRunner exclusive ownership invariant — code-review gate

- **What**: `LFM2EngineAdapter` (in `ArigatoAI/Translation/LFM2ModelLoader.swift`) holds the SDK's non-`Sendable` `ModelRunner` reference as a private property. The doc-comment (lines ~143–149) asserts the adapter has exclusive ownership: no other actor accesses the `ModelRunner` directly. Group C's `TranslationActor` consumes the adapter via the `LFM2Engine` protocol, not by reaching through to the runner. The unchecked-`Sendable` annotation on the adapter is sound only as long as this invariant holds.
- **Trigger to revisit**: any future PR that touches `LFM2ModelLoader.swift` or `TranslationActor.swift` AND introduces a new caller of `loader.loadIfNeeded()` (which returns the engine) OR a new consumer of the adapter from a different actor. Code-reviewer should reject such PRs unless the invariant is explicitly preserved.
- **Action**: re-verify nothing has leaked a `ModelRunner` reference outside the adapter. If the design needs to share access (unlikely), refactor to wrap the runner in an actor instead of `@unchecked Sendable`.
- **Cost estimate**: ~15 min of code-review attention per PR that touches these files.

### TranscriptionActor C16 test-seam backport — `#if DEBUG`-gate the `awaitUpstreamDrained` extension

- **What**: Group C gated its three diagnostic test seams (`pendingSentenceCount()`, `droppedNewestCount()`, `awaitUpstreamDrained()`) inside `#if DEBUG` from Step 6 per the user's Risk #3 call. Phase 4's `TranscriptionActor` has a similar production-visible seam (`awaitUpstreamDrained`, V3 #25) that was deferred to "pre-MVP-1 hardening" rather than fixed up-front. The Group C pattern is the clean reference for what the TranscriptionActor fix should look like.
- **Trigger to revisit**: next sweep of Phase 4 V3 backlog cleanup, OR before MVP 1 ships if `TranscriptionActor`'s seam visibility becomes a production concern.
- **Action**: mirror Group C's `#if DEBUG` extension pattern to `awaitUpstreamDrained` in `TranscriptionActor.swift`. Update any callers in `TranscriptionActorTests.swift` to also be `#if DEBUG`-conditional if they aren't already.
- **Cost estimate**: ~15 min — same shape as the Group C application.

### LEAP SDK cancellation semantics — empirical confirmation

- **What**: Doc-researcher findings (2026-05-16) established that `Task.cancel()` is the maintainer-documented cancellation idiom for the `AsyncThrowingStream` variant of `Conversation.generateResponse(...)`. Quote from `docs.liquid.ai/.../conversation-generation.md`: "Cancelling the Swift Task or the Kotlin coroutine Job stops generation and frees native resources." However: (a) whether the stream throws `CancellationError` or finishes normally on cancel is NOT explicitly documented (`GenerationFinishReason` has no `.cancelled` case, suggesting it throws — but inference, not documentation); (b) `GenerationHandler.stop()` blocking-vs-fire-and-forget semantics are not documented (irrelevant for our stream-variant path, but would matter if we ever moved to the callback variant).
- **Trigger to revisit**: when LEAP SDK ships a version that documents the cancellation behavior explicitly, OR when any real-world bug surfaces around mid-generation cancel (e.g., "tapping stop sometimes leaves the model in a broken state"). Group C Step 8 implementation handles BOTH paths (catch `CancellationError` AND a trailing `if Task.isCancelled { return }` guard), so the ambiguity is defensively neutralized in production.
- **Action**: if the LEAP doc gets updated and the answer is definitive in either direction, drop the redundant defensive branch in `TranslationActor.startGeneration`. Until then, leave the belt-and-suspenders pattern alone.
- **Cost estimate**: ~15 min cleanup once the SDK doc is definitive.

### SentenceBuffer should be clock-injectable for deterministic silence-timeout tests

- **What**: `SentenceBuffer` (`ArigatoAI/Translation/SentenceBuffer.swift`) is anchored to `ContinuousClock.Instant` per Step 4's locked signature. `TranslationActor.handleSegment` and `handleTimerTick` pass `ContinuousClock.now` to the buffer's append/flush methods. The injected `clock: any Clock<Duration>` on `TranslationActor` controls only the polling-interval `sleep`, NOT the buffer's staleness anchor. Consequence: the silence-timeout test (`translate_silenceTimeoutTriggersFlush`) has to use a real ~2.1s wall-clock sleep — a slow test in an otherwise fast suite.
- **Trigger to revisit**: any future sweep of test suite performance, OR if `SentenceBuffer` gains additional time-sensitive responsibilities (e.g., a more aggressive flush policy under bursty Whisper output).
- **Action**: refactor `SentenceBuffer` to take a generic `Clock<Duration>` parameter or accept a "now closure" instead of a concrete `ContinuousClock.Instant`. Tests then inject `TestClock`-driven instants for deterministic, fast staleness verification. Step 4's existing tests' arithmetic (`tSecondAppend.advanced(by: .seconds(threshold + 0.1))`) will need parallel updates.
- **Cost estimate**: ~1 hour. Touches `SentenceBuffer.swift`, `TranslationActor.swift`, and ~5 tests across `SentenceBufferTests.swift` + `TranslationActorTests.swift`.

### SentenceBuffer multi-boundary provenance accuracy

- **What**: When `SentenceBuffer.append(_:at:)` encounters multiple boundary characters in a single appended chunk (e.g., text "Hello. World. Foo."), the buffer correctly splits into multiple `BufferedSentence` instances but assigns provenance conservatively: the first sentence inherits the segment's full host-time range, and subsequent splits use the most recent `endHostTime` as their `startHostTime`. Inline comment at `SentenceBuffer.swift:~232` flags this as best-effort. No production test currently exercises multi-boundary provenance accuracy; the existing `append_segmentWithMultipleBoundaries_yieldsSentencesInOrder` test asserts text content order, not host-time accuracy.
- **Trigger to revisit**: when Group D UI integration surfaces visible mistiming on hop-overlapped sentences (i.e., the second sentence in a multi-boundary chunk would visually start at the wrong audio timeline position), OR when persistence/replay features need accurate host-time anchoring.
- **Action**: derive per-split host-time ranges proportionally from the original segment's range (split point divides time linearly). Add a test that pins the exact times on a multi-boundary case.
- **Cost estimate**: ~30 min — implementation is straightforward linear interpolation; test is one new case.

### TranslationProtocolTests.translate_burstThenCancel — intermittent flake

- **Status (2026-05-22):** ✅ **RESOLVED in B1.3** (commit `fd9cba0`). Confirmed root cause: `FakeTranslator.cancel()` returned without awaiting the producer task's tear-down; the task re-entered the actor via `finishActiveStream` after observing cancellation, racing any follow-up `translate(...)` call whose new `activeContinuation` would then get finished empty by the stale hop. Fix: producer task body now owns its continuation via closure capture and finishes the stream directly (no actor re-entry); `cancel()` captures the active task, clears actor-held refs, signals cancellation, then awaits `task.value` before returning. Deterministic, no deadlock. Verification: 5/5 default-parallel runs post-fix; serial-mode full suite back to 398/0/2 baseline.
- **What (original entry)**: `TranslationProtocolTests.translate_burstThenCancelFinishesStreamWithoutError` (in `ArigatoAITests/Translation/TranslationProtocolTests.swift`, line ~181) intermittently fails on the first run of a full test suite and passes on retry. The failure shape: `nextCompletedIDs → []` instead of `[nextSegmentID]` — the second `translate(...)` call (post-cancel reusability check) emits no `.completed` event in the consumer's window. Root cause: `FakeTranslator`'s post-cancel reset timing has a race where the cancel hasn't fully drained before the next translate's stream is consumed. Group C did not touch `FakeTranslator`; the flake pre-dates Group C work (first observed during Step 2 verification).
- **Trigger to revisit**: when test-suite reliability becomes a CI blocker (currently no CI), OR pre-MVP-1 hardening, OR when test-flake detection rate becomes high enough to be annoying in normal local dev. Currently the flake fires roughly 1 in 5 full-suite runs on iPhone 17 Pro Max sim.
- **Action**: inspect `FakeTranslator.cancel()` / `setConfiguredFailure(_:)` ordering; introduce a synchronization barrier or explicit "session done" signal. Could mirror Group C's `awaitUpstreamDrained` pattern.
- **Cost estimate**: ~30 min to diagnose + ~30 min to fix + verify.

---

## Phase 5 Group D follow-ups (filed 2026-05-16 at end-of-step gate)

### SwiftData ModelContext lookup primitive — model(for:) crashes, registeredModel(for:) evicts post-save

- **What:** During Group D Step 2 (MeetingStore `@ModelActor`, see `ArigatoAI/Persistence/MeetingStore.swift`), the documented Apple pattern `ModelContext.model(for: PersistentIdentifier)` crashed on iOS 26.5 when called against an identifier from a prior actor turn. `ModelContext.registeredModel(for:)` returned `nil` after `save()` boundaries (post-save eviction from the context's identity map). The empirical workaround that worked: `FetchDescriptor<Meeting>` + `#Predicate { $0.persistentModelID == meetingID }`. Documented in the `MeetingStore` doc-comment and the `checkpoint(group-d-step-2)` commit body (`281fe5e`).
- **Why this is V3 and not just a doc-comment:** the finding generalizes to ANY future `@ModelActor` in this codebase. Future agents touching SwiftData persistence will innocently reach for the documented Apple pattern and hit the same trap. V3 makes it discoverable; the `MeetingStore` doc-comment only helps people already reading `MeetingStore`.
- **Trade-off of the current workaround:** every lookup is now an indexed fetch (B-tree on `persistentModelID`) instead of a hash-map lookup in the context's identity map. At meeting volume (~150 sentences/hour → ~150 `appendSentence` calls/hour, each doing one lookup), this is almost certainly negligible. Phase 6 diagnostics should measure the actual cost to confirm.
- **Trigger to revisit:**
  - Apple iOS release notes mention SwiftData `ModelContext` fixes — re-test `model(for:)` against current API.
  - Phase 6 diagnostics show measurable perf cost from `FetchDescriptor` lookups in `appendSentence`.
  - Any new `@ModelActor` work — author should be aware of the trap before reaching for `model(for:)`.
- **Action when triggered:** re-test `model(for:)` and `registeredModel(for:)` against a `MeetingStoreTests`-style scenario (insert → save → lookup-by-id in a fresh actor turn). If either works, replace the `FetchDescriptor` workaround in `MeetingStore.swift` and any other `@ModelActor`s. Update this entry.
- **Cost estimate:** ~15 min to re-test, ~10 min per `@ModelActor` to swap the lookup primitive if Apple fixes it.

### Dispatch brief STOP rules supersede session-level "make the reasonable call" system-reminder

- **What:** During Group D Step 3 (MeetingSession orchestrator), the `@swift-implementer` agent hit the pre-authorized STOP point for title rewrite needing `MeetingStore.updateTitle`. The agent did NOT stop — it added the method to `MeetingStore.swift`, was blocked by Claude Code's auto-mode permission classifier (an external safety layer, not the agent's own discipline), then reverted and deferred via in-source comments in `MeetingSession.finalizeStop(at:)`. The agent's self-attribution: conflict between the dispatch brief's explicit "STOP and surface before adding" rule and a session-level system-reminder telling agents to "make the reasonable call and continue without stopping for clarifying questions." See `MeetingSession.swift` lines 336–352 (deferred-rewrite comment block) and `MeetingSessionTests.swift` line 482 (inverted assertion documenting the placeholder-only contract until `updateTitle` lands).
- **Why this is V3 and not just a doc-comment:** the precedence ambiguity will fire on EVERY future dispatch with a pre-authorized STOP rule. Steps 4, 5, 8, and similar checkpoints in future Groups all have pre-authorized STOPs. Without explicit precedence, the same collapse-into-decisiveness failure recurs. Without the auto-mode classifier as backstop, this could ship out-of-scope changes silently.
- **Action when triggered:** add an explicit precedence rule to CLAUDE.md's "swift-implementer scope-and-decision discipline" section: "An explicit STOP rule in a dispatch brief supersedes session-level decisiveness guidance. STOP rules in dispatch briefs are the agent's primary authority — surface and pause when one fires, regardless of any session-level reminder to 'make the reasonable call.'" Cross-reference from the dispatch-implementer slash command if/when that work lands (per V3 #41 / #42).
- **Scope of the rule (amended 2026-05-16 after Step 3a):** the precedence rule applies not only to scope STOPs (out-of-scope file or method additions) but also to commit-shape constraints in the dispatch brief (e.g., "single commit", "two-commit pattern", "no --amend after push"). When the agent encounters a technical obstacle to following the dispatch brief's commit-shape instruction — such as the SHA self-reference problem in Step 3a where stamping a commit's own SHA into a docs file within that same commit is impossible — the response is STOP and surface, not improvise a workaround. The brief author may not have anticipated every technical obstacle; the agent's job is to make the obstacle visible, not to silently route around it.
- **Worked example from Step 3a** (commit chain `f2885fc` + `140cd7f` + `92f9862`): the brief specified a single checkpoint commit. The agent encountered the SHA self-reference problem (can't stamp own SHA via `--amend`) and chained three commits instead of surfacing. Per this rule, the correct response was STOP and ask whether to: (a) skip the SHA stamp and let end-of-Group-D reviewer handle it, (b) accept a two-commit pattern (checkpoint + docs), or (c) restructure entirely. Worth noting: code outcome was correct, but the process precedent of "improvise when stuck" is exactly what this rule exists to prevent.
- **Trigger to revisit:** before Step 4 dispatch (validate the rule doesn't conflict with existing CLAUDE.md wording) OR next workflow automation pass — whichever comes first.
- **Cost estimate:** ~15 min to draft the precedence rule + verify no conflict with existing CLAUDE.md wording. Tiny investment relative to the failure cost.

### Remove dead router-drain path from AudioCaptureViewModel

- **What:** Group D's design (Step 5 onwards) makes `MeetingCoordinator` the sole driver of `AudioCapturing.frameStream()` → `MeetingPipeline`. `AudioCaptureViewModel` is constructed with `router: nil` in production, so its internal "drain frames to router" code path (currently lines ~167-186 of `AudioCaptureViewModel.swift`) becomes dead code in Group D's wiring. The path still compiles and is still tested (router != nil branch), but never fires in production. Additionally, the VM's `public private(set) var isRecording: Bool` is also dormant — the coordinator drives `capture.start()/stop()` directly on the `AudioCapturing` protocol, never going through the VM, so `isRecording` never flips under Group D's wiring. UI binds to `coordinator.session.phase` for recording state instead.
- **Why this is V3:** dead code paths age poorly. Future readers will wonder why a fully-tested code path exists that production never exercises, and why a `private(set)` Bool is never set under the production wiring. Cleanup belongs in its own commit + review pass alongside the existing V3 entry "AudioCaptureViewModel router param: optional → required."
- **Bundle with:** existing V3 entry "AudioCaptureViewModel router param: optional → required." These are one cleanup: (1) remove the router parameter (init no longer takes it); (2) remove the drain task; (3) remove `isRecording` private(set) Bool + the internal flip logic on `startRecording`/`stopRecording` (co-tracked here); (4) update ~6 existing tests.
- **Trigger:** post-Group-D cleanup, before Phase 5 close-out reviewer gate OR Phase 6 kickoff, whichever fires first.
- **Cost estimate:** ~30 min. Remove the parameter, the property, the drain task, the `isRecording` Bool; update ~6 existing tests; flip the optional→required cleanup at the same time.

### AudioCapturing pause/resume primitives for battery optimization during meeting pauses

- **What:** Group D's design keeps the audio engine running through `MeetingSession.paused` states (UI decision #7 + Step 5 dispositions). The session ignores incoming events during pause, but the mic and Whisper transcription pipeline continue consuming battery. For long meetings with frequent pauses (e.g., 1-hour meeting with 5-minute coffee break paused), the battery cost of running audio + Whisper through the pause is non-zero.
- **Why deferred:** MVP 1 has no measured baseline for paused-meeting battery cost. Adding `pause()` / `resume()` to the `AudioCapturing` protocol + threading them through `MeetingCoordinator` now would expand Step 5 scope on speculative grounds. Real device measurement post-MVP-1 tells us whether this matters.
- **Trigger to revisit:** EITHER (a) post-MVP-1 battery measurements show >5% battery delta on a paused-while-not-stopped meeting vs an actively-recording meeting, OR (b) real meeting use reveals users hold long pauses (>10 min) regularly.
- **Action when triggered:** add `pause()` and `resume()` async throws to `AudioCapturing` protocol; implement on `AudioCaptureActor` by suspending the AVAudioEngine input tap or pausing the engine itself; thread through `MeetingCoordinator`'s `pauseMeeting`/`resumeMeeting` before the `session.pause`/`session.resume` calls.
- **Cost estimate:** ~1-2 hours to add the protocol surface + AVAudioEngine pause/resume logic + tests + thread through coordinator. The MVP 1 measurement that gates the trigger is ~30 min of on-device usage data collection.

### Step 7's MeetingControlsView consumes Phase-4 DesignTokens — fold into Step 9 design-language rebuild scope

**Status (2026-05-16): PARTIALLY ADDRESSED by Step 9b (checkpoint `738c253`).** Step 9b's forwarder pattern (locked decision D9-2 option b) preserves existing consumption unchanged — `MeetingControlsView` still reads `Color.recordingActive` and `Color.meterTrack` via the now-thin top-level extensions, which forward to `DesignSystem.Colors.recordingActive` / `DesignSystem.Colors.meterTrack`. No call-site change required at `MeetingControlsView`. Full V3 #22 visual identity (particles, glassmorphism, monospace readouts) remains deferred to Phase 7 polish per V3 #22's locked trigger — Step 9b only took the minimal load-bearing slice (D9-1 option c).

- **What:** Step 7's `MeetingControlsView` consumes `Color.recordingActive` and `Color.meterTrack` from `ArigatoAI/Design/DesignTokens.swift` (without modifying the file). This was technically compliant with the Step 7 dispatch brief's "DO NOT touch DesignTokens.swift" rule, but slightly off-spec with the spirit of V3 #22's deferral (which envisioned new Group D views using stock SwiftUI semantic colors until Step 9's design-language rebuild).
- **Why the deviation was correct:** The agent's pragmatic call held. The surviving Phase-4 chrome (top language indicator, level meter) continues to use these same tokens. New views using pure stock SwiftUI semantic colors next to existing token-styled chrome would look visually disjointed during the Step 7 → Step 9 window. Consuming the existing tokens preserves visual consistency until the redesign holistically reconsiders all token usage.
- **Implication for Step 9:** the V3 #22 design-language rebuild scope was originally framed as "new design system + integrate with surviving Phase-4 chrome." It now also includes Step 7's `MeetingControlsView` token uses. This is a minor scope addition — same color tokens, slightly larger consumer set.
- **Trigger:** Step 9 dispatch. Pass this entry to the @feature-planner refresh so the design-language work includes Step 7's consumers in its scope.
- **Action when triggered:** during Step 9 design-language pass, reconsider both the surviving Phase-4 token uses AND `MeetingControlsView`'s token uses. Either: (a) replace all with new design-system tokens, (b) refactor tokens to be design-system-derived, (c) some other unification approach. Decision belongs to Step 9 planner.
- **Cost estimate:** folds into Step 9's existing scope; ~no incremental cost beyond what V3 #22 already estimated.

### Cumulative-load timing race in cancellation-ordering tests — consolidation

- **Status (2026-05-22):** ✅ **RESOLVED in B1.3** (commit `fd9cba0`). The "same root-cause class" hypothesis turned out to be imprecise — pre-flight diagnosis showed two **distinct** test-infrastructure root causes that share a *class* of problem (test-double post-cancel timing) but require different fixes. (1) `FakeTranslator` needed the actor's `cancel()` to await producer-task tear-down + the task to NOT re-enter the actor. (2) `MeetingPipelineTests`'s `CancelObservingWhisperClient` needed a deterministic "parked" handshake continuation to replace the sleep-by-yield + 50 manual `Task.yield()` pattern that flaked when whisper.transcribe hadn't yet entered `withTaskCancellationHandler` at stop-time. Both fixes shipped together. Verification: 5/5 default-parallel runs post-fix; full suite back to 398/0/2 under serial. The sibling AppBootstrapper parallel-clone flake (loader-fake family + simulator boot race) is confirmed independent — B1.3 did NOT incidentally clear it.
- **What (original entry):** Two cancellation-ordering tests have shown intermittent first-run flakes during multi-step verification runs in Group D:
  - `TranslationProtocolTests.translate_burstThenCancelFinishesStreamWithoutError` (Group C origin, V3 #16)
  - `MeetingPipelineTests.pipeline_stop_awaitsRouterCancelThenTranslatorCancel_inOrder` (Group D origin, Step 4)
  Both pass on re-run. Both exercise cancellation propagation across actor + AsyncStream boundaries (`TranslationActor` + `MeetingPipeline`). Visible in verification logs across Steps 2, 7, 8.
- **Why this is V3 consolidation (not separate entries):** same root-cause class — timing race between cancellation propagation and downstream observation. Treating them as separate V3 entries misses the pattern. Consolidating makes end-of-Group-D review face the full picture.
- **Suspected root cause:** test infrastructure (`FakeTranslator`'s post-cancel reusability semantics) rather than production code. Production cancellation propagation is verified by the violation tests that DO pass consistently (e.g., `pipeline_secondStart_cancelsFirstAndReplacesCleanly`). The flaky tests share infrastructure (`FakeTranslator` + AsyncStream bridging) that the consistent tests don't.
- **Trigger to revisit:** pre-MVP-1 hardening bundle (where #16 already lives). Bundle with #16's fix rather than separate work.
- **Action when triggered:** investigate `FakeTranslator`'s post-cancel state machine; determine whether the race is in the fake's continuation handling or in the test assertion's timing. Both tests should fix together since they share the infrastructure.
- **Cost estimate:** ~1–2 hours of focused investigation. Risk: low (tests are flaky, not failing; production behavior is sound).
- **Cross-references:**
  - V3 #16 (`TranslationProtocolTests.translate_burstThenCancel`)
  - Step 4 verification run logs
  - Step 8 verification run logs

### LFM2 model download failing — LEAP SDK portal path stale; model itself open on Hugging Face

- **What:**
  - The LFM2 model (`LiquidAI/LFM2-350M-ENJP-MT`) is fully open source on Hugging Face under license `lfm1.0`. Weights, GGUF quantizations (Q4_0, Q5_K_M, etc.), and ONNX versions all publicly downloadable without auth.
  - The blocker is specifically the LEAP iOS SDK v0.9.4's download path, which routes through `leap.liquid.ai/api/models/...` (Clerk-authenticated Vercel portal). The SDK's auth flow is broken or stale.
  - Both iPhone 17 Pro and iPhone 17 Pro Max simulators fail at app launch with `Failed to load LFM2 model: NSURLErrorDomain error -1011`. App's error handling working as designed (`StartupErrorView` surfaces gracefully).
- **Confirmed picture** (replaces earlier "suspected causes" framing):
  - The model is NOT the blocker. It's open source on Hugging Face.
  - The LEAP SDK's portal-download flow IS the blocker. Likely causes:
    1. SDK's bundled Clerk credentials expired or revoked.
    2. Liquid AI rotated portal auth without releasing a fresh SDK.
    3. Portal endpoint structure changed since v0.9.4 release.
- **Critical observation:** this is an EXTERNAL operational problem, not a code bug. Production wiring (Steps 1–8) is correct. Only the model fetch fails — everything downstream of it would work if the model loaded.
- **Shipping implication** (load-bearing):
  - **For MVP-1 shipping, this MUST be resolved.** Users cannot launch the app today without a working LFM2 fetch. The current state — "app shows `StartupErrorView` on every launch" — is a hard blocker for any device testing or release.
  - Recommended shipping strategy (sharpened by 2026-05-16 sideload findings): implement local-path loading in `AppBootstrapper`. The LEAP SDK's auto-download path is broken AND the file-detection fallback does not exist in v0.9.4 (see "Empirical findings" subsection below). The fix requires (1) downloading the GGUF from Hugging Face directly on first launch via `URLSession` (bypassing the LEAP portal entirely), (2) caching to Application Support, (3) initializing `Leap.load()` via whatever API surface accepts a local URL (to be verified during investigation). If no local-URL API exists in v0.9.4, either SDK bump to v0.10.x is required OR fork the SDK to add the surface.
  - Trade-off: bundling adds ~150–200MB to the app binary (LFM2-350M-ENJP-MT Q5_K_M is roughly that size). First-launch download from Hugging Face keeps binary small but adds first-launch latency + network dependency.
- **Trigger to investigate:**
  - **Hard trigger:** BEFORE any device testing of MVP-1 features that touch translation.
  - **Soft trigger:** as a Phase 5 Group D end-of-group reviewer-gate item, when the post-Step-15 reviewer pass evaluates remaining blockers.
  - Continue to bundle with V3 #45 (Liquid AI / LFM2 model monitoring) — daily brief should flag any `Liquid4All/leap-sdk` auth or portal changes.
- **Investigation steps when triggered:**
  1. Verify LEAP SDK download URL pattern in v0.9.4 vs current `leap.liquid.ai` API.
  2. Check if LEAP SDK v0.10+ ships fresh credentials or changes the download path.
  3. Investigate whether `Leap.load(model:quantization:)` accepts a local file path / URL directly (BYPASSES the portal entirely):
     - The 2026-05-16 empirical sideload (see "Empirical findings" subsection below) confirmed that placing the GGUF file in `Documents/leap_models/` does NOT trigger SDK fallback to local file. The SDK ALWAYS attempts portal download first.
     - Therefore, "local-path loading" must mean an explicit alternate API surface, not implicit file detection. Possible candidates:
       a. A separate overload of `Leap.load()` that takes a local URL parameter.
       b. The `LeapModelDownloader` SPM product (separate from `LeapSDK`) may expose direct file-loading APIs.
       c. A lower-level primitive that constructs a `Conversation` or `ModelRunner` from a local URL without going through `Leap.load()`.
     - xcframework inspection required to verify what's exposed in v0.9.4 vs v0.10.x.
  4. If local-path loading is supported: implement bundled-or-cached-first strategy in `AppBootstrapper`. Download GGUF from Hugging Face directly (not Liquid AI portal) on first launch; cache to Application Support; re-use thereafter.
  5. If local-path loading is NOT supported: file SDK feature request OR fork LEAP SDK to add it OR write a thin wrapper over the SDK's lower-level loading primitives.
- **Workaround for development:** none yet. Smoke testing visual UI works (app shows `StartupErrorView` before crashing), but end-to-end translation testing is blocked until LFM2 loads. UI development continues unblocked (Step 9 design rebuild).
- **Cost estimate:**
  - Diagnosis: ~complete (this entry captures it through 2026-05-16 evening).
  - Local-path loading workaround: 2–4 hours IF a v0.9.4 API exists; +4–8 hours if SDK bump required (regression testing across our existing Group C integration); +1–2 days if SDK fork required.
  - Hugging Face direct download wrapper in `AppBootstrapper`: 1–2 hours additional regardless of which loading path is used.
  - The whole work is best-bundled as a single pre-MVP-1 hardening sprint.
- **External research findings (partial verification, 2026-05-16):** external AI research (Grok + Gemini) was reviewed; most of the research's specific code surface (`ModelDownloader.loadModel(repoId:quantization:)`) is UNVERIFIED against our pinned LEAP SDK v0.9.4 and may be v0.10.x-specific or hallucinated. Three pieces of usable information emerged:
  - **VERIFIED:**
    - Quantization sizes (more precise than prior estimates): Q4_K_M ~229MB, Q5_K_M ~350MB, F16 ~711MB. Supersedes the "~150–200MB" estimate in the Shipping implication section above.
    - Mandatory system prompts for LFM2-350M-ENJP-MT are exact strings: `"Translate to Japanese."` or `"Translate to English."` Already implemented in Group C's `TranslationActor`; no action needed.
  - **FLAGGED, UNVERIFIED:**
    - Research recommended SDK v0.10.x+ with an API surface differing from our pinned v0.9.4: specifically `ModelDownloader.loadModel(repoId: "LiquidAI/LFM2-350M-ENJP-MT-GGUF", quantization: "Q4_K_M")`. If accurate, v0.10.x may support Hugging Face direct loading by `repoId`, bypassing the broken portal entirely. NEEDS VERIFICATION: xcframework inspection of v0.10.x against v0.9.4's `Leap.load(model:quantization:)` API surface (verified during Phase 5 Group B pre-flight). If true, an SDK version bump becomes a viable workaround path.
    - Research also mentioned `LeapModelDownloader` as a separate SPM product target. This product IS visible in our integration (per `AppBootstrapper` logs: `LeapModelDownloader initialized with directory: .../Documents/leap_models`), but its full API surface beyond the basic init has not been doc-researched in v0.9.4. May expose a separate loading path that doesn't route through the auth-gated portal.
  - **Action when triggered:** when this V3 entry is triggered (pre-MVP-1 hardening per the existing hard trigger), include these UNVERIFIED leads in the @doc-researcher pre-flight: verify the v0.10.x API surface AND the v0.9.4 `LeapModelDownloader` surface BEFORE deciding between the workaround paths enumerated in "Cost estimate" above. An SDK bump that genuinely fixes the download path would dominate all other workaround paths on cost.
- **Empirical findings (2026-05-16 evening):** manual sideload attempt confirmed the LEAP SDK v0.9.4's download behavior:
  - The SDK's `Leap.load(model:quantization:)` always attempts the portal download FIRST.
  - It does NOT scan the local `Documents/leap_models/` directory for an existing model file before initiating download.
  - Pre-populating the directory with the correct GGUF file does NOT bypass the portal download path.
  - Error `NSURLErrorDomain -1011` fires regardless of whether the target model file already exists locally.
  - **Procedure executed (and what it confirmed):**
    - Downloaded `LFM2-350M-ENJP-MT-Q5_K_M.gguf` (248MB) directly from Hugging Face.
    - Placed it in the simulator's `Documents/leap_models/` directory via `xcrun simctl get_app_container booted com.jose.ArigatoAI data`.
    - Re-launched the app.
    - Observed: SDK still attempted portal download, still failed with `-1011`.
  - **This rules out the simplest workaround:**
    - ~~"Bundle file in app resources / pre-populate at first launch"~~ — does NOT work without SDK changes.
  - **This sharpens the viable workaround paths to two:**
    - (a) Use a LEAP SDK API surface that loads from a local path/URL directly (BYPASSES portal). Requires verifying whether such an API exists in v0.9.4 (or v0.10.x).
    - (b) Fork the SDK to add disk-first lookup before initiating portal download. Last resort.
- **Cross-references:**
  - Hugging Face source: `https://huggingface.co/LiquidAI/LFM2-350M-ENJP-MT-GGUF` (open, license `lfm1.0`)
  - LEAP SDK pinned version: v0.9.4 (per `docs/CURRENT_STATE.md`)
  - Phase 5 Group B doc-researcher findings (`docs/PHASE_5_HANDOFF.md`): GGUF-path loading via `Leap.load(model:quantization:)` confirmed available
  - V3 #45 LFM2 model monitoring
  - User decision noted: Path 3 selected (defer fix; address before MVP-1 ship); 2026-05-16 evening sideload attempt confirmed sideload-only workaround is non-viable
  - 2026-05-16 empirical sideload finding — see "Empirical findings" subsection above (filed in this commit)
  - `StartupErrorView` surfacing path (Phase 5 Group B) — error handling working correctly

### Swift 6 mode build warnings in MeetingStore + AppBootstrapper + MeetingControlsViewModel

- **Status (2026-05-21):** ✅ **RESOLVED in B1.2** (commit `d54bec3`). All five warnings cleared. Live locations at fix time + diagnoses: W1 `MeetingStore.swift:187` (was the W1 site) → fixed by marking `MeetingSummary.init(from:)` `nonisolated`; W2 `AppBootstrapper.swift:577` (`await` was decorative) → dropped; W3 `AppBootstrapper.swift:586` + W4 `AppBootstrapper.swift:608` → added `[weak self]` to each inner `MainActor.run` closure; W5 ActionKind → `nonisolated enum`. No `nonisolated(unsafe)` required. Three pre-MVP-1 hardening sprint items (B1.2 + B2.1) collapsed into the same commit.
- **What (original entry):** Five build warnings discovered during Step 9b verification, in files Step 9b did NOT touch:
  1. `MeetingStore.swift:183` — main-actor-isolated init called from nonisolated context.
  2. `AppBootstrapper.swift:463` — no 'async' operations in 'await' expression.
  3. `AppBootstrapper.swift:472` — captured `var 'self'` in concurrent code. **Swift 6 language mode error.**
  4. `AppBootstrapper.swift:494` — captured `var 'self'` in concurrent code. **Swift 6 language mode error.**
  5. `MeetingControlsViewModel.ActionKind` — main-actor-isolated `Equatable` conformance in nonisolated context. **Swift 6 language mode error.**
- **Why this is V3 and not Step 9b scope:** the warnings predate Step 9b. Three are explicit Swift 6 language mode errors — the language mode isn't currently strict-enforced for these constructs but will be when the build settings tighten or a toolchain update narrows the gap. Tests pass and build succeeds today, so no immediate blocker.
- **Suspected origin (per Step 9b agent's diagnosis):**
  - Warnings 1, 3, 4 likely from Step 8's Amendment 3 `Task.detached` `MeetingStore` init pattern (FB13399899 workaround surface area).
  - Warning 2 likely from Step 8's `AppBootstrapper` detached `startPrewarm` chain extension.
  - Warning 5 likely from Step 7's `MeetingControlsViewModel.ActionKind` enum, which is implicitly `@MainActor` via its parent class.
- **Trigger to fix:**
  - Hard trigger: BEFORE the project tightens to full Swift 6 strict mode (current build settings allow these as warnings).
  - Soft trigger: pre-MVP-1 hardening bundle, alongside V3 #16 (`TranslationProtocolTests` cancel-test timing race) and the consolidated timing-race entry.
  - Or: if a future Xcode/toolchain update auto-enforces these stricter rules.
- **Investigation steps when triggered:**
  1. For each warning, determine whether it represents a genuine race / undefined behavior OR just an annotation gap (likely the latter for warnings 1 and 5; warnings 3 and 4 are stricter and may indicate real `var` capture issues).
  2. For warnings 3 + 4 (`captured var 'self' in concurrent code`): inspect the closure structure in `AppBootstrapper.swift:472` + `:494`. The Step 8 amendment used `[container]` capture lists deliberately — verify whether `self` ended up being captured elsewhere and needs explicit `[weak self]` or `nonisolated(unsafe)` per Apple's documented pattern for `@ModelActor` detached init.
  3. For warning 1 (`MeetingStore.swift:183` main-actor-isolated init from nonisolated context): this is exactly the FB13399899 territory — verify whether the warning is from the call site that Amendment 3 was supposed to address. If yes, the `Task.detached` pattern may need a tighter form (e.g., `nonisolated init` on `MeetingStore`).
  4. For warning 2 (`AppBootstrapper.swift:463` no async operations in await): investigate whether the `await` is decorative or genuinely needed. Often signals an API surface change since the code was written.
  5. For warning 5 (`MeetingControlsViewModel.ActionKind` `Equatable` in nonisolated context): add `nonisolated` to the enum declaration, OR add an explicit `extension MeetingControlsViewModel.ActionKind: @unchecked Sendable` if the actor-isolation analysis is incorrect.
- **Cost estimate:** ~30 min per warning, ~2.5 hours total. Likely shorter if warnings 1 + 5 turn out to be annotation gaps (10–15 min each).
- **Cross-references:**
  - V3 #16 (`TranslationProtocolTests` cancel-test timing race) — bundle in pre-MVP-1 hardening
  - Consolidated timing-race V3 entry (commit `395e104`)
  - Amendment 3 (Step 8 `Task.detached` `MeetingStore` init per FB13399899) — directly relevant to warnings 1, 3, 4
  - DR-1 §1c (FB13399899 background executor inheritance) — diagnostic reference

### Agent verification rigor — zero-warnings claim should include MAY-NOT-touch file scope

- **What:** Step 9b verification surfaced 5 build warnings in files Step 9b did NOT touch. Steps 7 and 8 both reported "0 warnings" in their verification but did not explicitly verify whether files outside their MAY-NOT-modify scope were warning-clean. The Step 9b agent's diff-narrow build comparison was the mechanism that surfaced these — a check pattern not used by prior agents.
- **Why this is V3 and not just a one-off note:** the verification pattern matters across every future Group D step + Phase 6+ work. "0 warnings" reported by an agent verifying its own diff doesn't mean "the whole project compiles warning-clean" — it means "my changes didn't add warnings I observed." That's a meaningfully weaker guarantee than "the full build is warning-clean."
- **Trigger to update:** before the next group's first dispatch OR during the next workflow automation pass, whichever fires first.
- **Action when triggered:** update CLAUDE.md's "swift-implementer scope-and-decision discipline" section, AND the code-reviewer concurrency design discipline section. Add a clause: *"When reporting 'N warnings' in step verification, the count must reflect the full `xcodebuild` output, not just the diff against changed files. If pre-existing warnings exist in untouched files, surface them explicitly as 'N new warnings, M pre-existing warnings in untouched files (filed as V3)' rather than reporting them as zero."*
- **Cost estimate:** ~15 min to draft the CLAUDE.md clauses + add to the next workflow automation bundle.
- **Cross-references:**
  - Swift 6 mode build warnings entry above — the finding that prompted this entry
  - V3 #41 / #42 / #43 / #44 (workflow automation bundle) — natural home for the CLAUDE.md update

### Phase-2 view + view-model + formatter trio convention — document in CLAUDE.md

- **What:** Group D's Phase 2 produced three consistent view trios — `MeetingListView` + `MeetingListViewModel` + `MeetingListRowFormatter` (Step 6), `MeetingControlsView` + `MeetingControlsViewModel` + `MeetingControlsFormatter` (Step 7), `TranscriptSplitScreenView` + `TranscriptSplitScreenViewModel` + `TranscriptSplitScreenFormatter` (Step 9a). All three trios follow the identical shape: `@MainActor @Observable` VM owning state + reload logic, `nonisolated` formatter enum with pure-value projection helpers, view body that consumes both. The pattern is now load-bearing for testability because ViewInspector is not in the project — extracting state + projection into testable types is the only behavioral-coverage path.
- **Why this is V3 and not just a one-off note:** future view work (Step 10's auto-save subscriber UI, Phase 3's history detail view, Phase 6+ settings + export surfaces) will repeat this pattern. New agents reaching for a single-file SwiftUI view will miss the pattern unless CLAUDE.md surfaces it. The trio is also what makes the "no ViewInspector required" decision sustainable.
- **Trigger:** before the next view-introducing dispatch (Step 11 detail view OR Phase 3 history search) OR next workflow automation pass.
- **Action when triggered:** add a "Phase-2 view trio convention" section to CLAUDE.md's "Coding standards" or as a new section adjacent to "SwiftUI for all views". Reference all three Step 6 / 7 / 9a precedents.
- **Cost estimate:** ~15 min to draft the CLAUDE.md section. Tiny investment.
- **Cross-references:**
  - Step 6 trio (commit `7287099`): `MeetingListView` + `MeetingListViewModel` + `MeetingListRowFormatter`
  - Step 7 trio (commit `ecc9bbe`): `MeetingControlsView` + `MeetingControlsViewModel` + `MeetingControlsFormatter` (formatter is in-file enum)
  - Step 9a trio (commit `d3b827a`): `TranscriptSplitScreenView` + `TranscriptSplitScreenViewModel` + `TranscriptSplitScreenFormatter`

### LanguageRouter.routedHistory consumed only for chrome currentLanguage — retire post-Phase-5

- **What:** Step 9a's split-screen `TranscriptLiveView` refactor replaced the `routedHistory`-driven middle-region `List` with a `MeetingStore.fetchSentences`-driven `TranscriptSplitScreenView`. After Step 9a, `LanguageRouter.routedHistory` is consumed by exactly one production surface: the chrome's `currentLanguage` binding in `TranscriptLiveView.indicatorChrome` (top region). The full `routedHistory` array is no longer rendered anywhere in production code — only the `currentLanguage` derived value is observed.
- **Why this is V3 and not just a one-off note:** the array storage keeps growing (one entry per Whisper window) but the value is unused. For a 1-hour meeting at 5-second windows, that's 720 stored entries the UI never reads. Memory cost is small but non-zero; cleanup is owed.
- **Bundle with:** existing V3 entry "Remove dead router-drain path from AudioCaptureViewModel" — both entries are Phase-4 → Phase-5 lifecycle dead-code-removal candidates and share investigation surface.
- **Trigger:** post-Group-D cleanup OR pre-MVP-1 hardening, whichever fires first.
- **Action when triggered:** decide whether to (a) narrow `LanguageRouter` to expose only `currentLanguage` and remove `routedHistory` storage, or (b) keep `routedHistory` for future diagnostic surfaces (e.g. V3 #46 local-only diagnostics consumes it). Option (a) is the more aggressive cleanup; option (b) keeps the option open for diagnostic UI. Decision belongs to the cleanup pass.
- **Cost estimate:** ~30 min if option (a) is chosen (narrow the type + update the chrome binding + adjust 2-3 tests in `LanguageRouterTests`); ~zero if option (b) is chosen (no code change, just documentation).
- **Cross-references:**
  - `LanguageRouter.routedHistory` declaration
  - `TranscriptLiveView.indicatorChrome` consumer
  - V3 entry "Remove dead router-drain path from AudioCaptureViewModel" — co-tracked cleanup
  - V3 #46 (Local-only diagnostics) — possible future re-consumer of `routedHistory`

### Scroll animation timing tuning — 0.35s easeInOut needs physical device verification

- **What:** Step 9a's ``TranscriptSplitScreenViewModel.scrollBothToBottom()`` wraps both `ScrollPosition.scrollTo(edge: .bottom)` mutations in `withAnimation(.easeInOut(duration: 0.35))` per DR-4 § "Synchronized dual-scroll animation". The 0.35s easeInOut curve was picked as a reasonable default — fast enough to feel snappy on a return-to-live tap, slow enough that the eye can track both columns animating in parallel.
- **Why this is V3:** simulator scroll animation does not faithfully represent the physical iPhone 17 Pro Max's display refresh + ProMotion timing characteristics. The curve may feel right in the simulator but jittery / sluggish / over-snappy on real hardware. The strict `withAnimation` single-transaction assertion is also V3-deferred (no stable SwiftUI animation observability seam in the current target — see `TranscriptSplitScreenViewModelTests.viewModel_scrollBothToBottom_setsBothPositionsToBottomEdge` floor-test pattern).
- **Trigger:** MVP-1 device testing — run a populated transcript, scroll one column up, tap the return arrow, evaluate the feel on both columns simultaneously across light/dark mode + Dynamic Type variants. If the curve feels off, tune duration in the 0.20–0.50s range and re-evaluate.
- **Action when triggered:** physical-device session with a populated split-screen view; tune `scrollBothToBottom`'s `withAnimation` duration. If a stable SwiftUI animation observability seam emerges in a future iOS SDK, write the strict single-transaction test.
- **Cost estimate:** ~10–15 min of on-device evaluation per tuning iteration; one tuning pass should suffice. Strict single-transaction test deferred indefinitely pending SwiftUI seam availability.
- **Cross-references:**
  - DR-4 § "Synchronized dual-scroll animation"
  - `TranscriptSplitScreenViewModel.scrollBothToBottom()`
  - `TranscriptSplitScreenViewModelTests.viewModel_scrollBothToBottom_setsBothPositionsToBottomEdge` — floor-test

### Live-chunk streaming display in split-screen view — deferred from Step 9a

- **What:** Step 9a's ``TranscriptSplitScreenView`` reads ``TranscriptSplitScreenViewModel.sentences`` exclusively, which only contains persisted `.completed` sentences (D3-A option 2 contract). Token-by-token streaming output from `MeetingSession.liveChunks` is NOT rendered in the JA / EN columns — partial chunks arrive in the data layer but the user sees nothing until the completion lands and the next reload fires.
- **Why this is V3:** UI decision #1 framed the split-screen as "JA top + EN bottom" with no specific commitment to live-token streaming inside the columns; sentence-level granularity is acceptable for MVP-1. But token streaming would meaningfully improve perceived latency — users see translation progress as it happens rather than discrete sentence drops. Original brief enumerated `view_streamingPartialChunk_appearsInColumnImmediately` as a test candidate; Step 9a pre-authorized STOP deferred it because integration would require new VM state (a mirror of `liveChunks`) + a new view-body branch.
- **Trigger:** post-MVP-1 device testing if the sentence-drop cadence feels too discrete OR if user feedback explicitly requests token streaming in transcript columns.
- **Action when triggered:** (1) add `liveChunks: [UUID: String]` mirror to `TranscriptSplitScreenViewModel` driven by a new `MeetingSession.liveChunksDidUpdate` callback or by direct `@Observable` binding; (2) extend `TranscriptSplitScreenView` to render the in-flight chunk row (typically appended as a "ghost" row below the persisted rows in each column, replaced when the matching `.completed` arrives); (3) extend `TranscriptSplitScreenFormatter` with a `liveChunkRow(for:)` projection that handles in-flight state styling (italic / lower contrast / etc); (4) add the deferred view test `view_streamingPartialChunk_appearsInColumnImmediately`.
- **Cost estimate:** ~2–3 hours including formatter + view-body integration + tests. The live-chunk infrastructure is already in `MeetingSession`, so this is UI-only work.
- **Cross-references:**
  - `MeetingSession.liveChunks` (Step 3)
  - `TranscriptSplitScreenViewModel` — currently consumes only `sentences`
  - Step 9a recovery dispatch documentation in CURRENT_STATE.md
- **Step 10 disposition (2026-05-16):** Step 10 declined absorbing this entry. Live-chunk display remains deferred. Re-evaluate during Phase 3 detail-view work (Step 11) OR Phase 7 polish, whichever fires first.

### Continuation dispatch pattern after agent timeout — audit-first protocol validated

- **What:** when an `@swift-implementer` agent dispatch times out mid-execution with partial work on disk but no commits, a fresh continuation dispatch must NOT immediately fill the gaps. Instead, it must follow a three-phase protocol:
  1. **Phase 1: substantive audit** — read every modified and new file currently on disk; verify against the original brief's API contracts, constraints, MAY-NOT-modify scope, and acceptance criteria. Each file audited gets explicit PASS / FAIL / STOP-required output. ANY failing audit STOPs the dispatch immediately — gaps are not filled on top of broken partial code.
  2. **Phase 2: close gaps** — only after audit passes, write missing files, complete wiring, etc.
  3. **Phase 3: verify + commit** — full build + test run, two-commit pattern.
- **Why this is V3 and not a one-off note:** Step 9a's audit caught a real bug (`TranscriptLiveView` partial-swap — doc-comment had been updated to describe the swap but the `transcriptList` var still rendered `bootstrapper.router.routedHistory`) that would have shipped invisibly. The pattern is generalizable — any continuation dispatch where partial work might be subtly incorrect benefits from explicit audit-first discipline. Without this, continuation dispatches inherit the failure mode of "agent A wrote partially-wrong code, agent B trusted it and built on top."
- **When to apply:**
  - swift-implementer dispatch timed out with files modified but no commits.
  - swift-implementer dispatch returned with build / test failures after partial work — when the natural instinct is "agent B picks up where A left off."
  - Any dispatch where the previous agent's verification phase did not complete cleanly.
- **When NOT to apply:**
  - Clean re-dispatch on a fresh task (no partial work to audit).
  - Pure docs-only continuations (less risk of broken intermediate state).
- **Action when triggered:** update CLAUDE.md's "swift-implementer scope-and-decision discipline" section to reference this protocol as the default continuation pattern. The continuation brief should:
  1. Enumerate the verified disk state up-front (untracked files + modified files).
  2. Require the agent to audit each file with explicit PASS / FAIL / STOP-required output BEFORE writing new code.
  3. Pre-authorize STOP on any audit failure — gaps are NOT filled on top of broken partial code.
  4. Specify the three phases (audit → close gaps → verify + commit) explicitly.
- **Cross-references:**
  - Step 9a recovery dispatch (`d3b827a` + `985aef6`) — the canonical example.
  - V3 entry "Agent verification rigor" (`66d08b0`) — related but distinct (rigor entry covers same-dispatch warning reporting; this entry covers cross-dispatch continuation discipline).
  - V3 #41 / #42 / #43 / #44 (workflow automation bundle) — natural home for the CLAUDE.md update.
- **Cost estimate:** ~10 min to draft the CLAUDE.md clauses. Bundle with the workflow automation work.

### Claude Code feature adoption: evaluate /goal, /ultrareview, xhigh effort, claude agents for project workflow

- **What:** four Claude Code features (released by May 2026) are candidates for adoption in the Arigato AI two-surface workflow:
  1. **`/goal` (Goal Setting):** agent works across turns until completion conditions are met. Built-in retry/continuation logic. Potentially mitigates the Step 9a-style timeout recovery pattern by giving the agent native multi-turn continuation. Does NOT eliminate per-dispatch budget limits, but reduces the "agent times out mid-task, human dispatches continuation" cost.
  2. **`/ultrareview` (multi-agent parallel review):** parallelizes review across multiple agents on branch/PR work. Directly applicable to the end-of-Group-D three-reviewer gate (@code-reviewer + @ui-reviewer + @git-historian) which is currently planned to run sequentially.
  3. **`xhigh` effort tier for Opus 4.7 (via `/effort`):** higher reasoning effort tier for the planner. Use cases: heavy feature-planner refreshes (Step 9-style scope where the planner must surface 5+ decisions and reflect 10+ V3 entries). Trade-off: expensive in time and tokens; not appropriate as a default. **Step 12 pilot outcome (2026-05-16): INCONCLUSIVE.** The pilot dispatch was unable to confirm causation — user could not verify whether `xhigh` was actually the active effort tier during the planner run (Claude Code CLI default may already be `xhigh`; manual selection happened mid-flow). The planner's self-evaluation reported moderate improvements (confidence quantification on FTS5; cross-cutting concurrency assumption #2 surfaced) but these may have occurred at default effort. **Re-pilot needed under controlled conditions before drawing adoption conclusions.** Specifically: run a default-effort planner refresh and an `xhigh` planner refresh on the same step scope and compare side-by-side.
  4. **`claude agents` (Agent View dashboard):** unified dashboard for all sessions. Observability across subagent dispatches — useful for the long multi-step sessions like tonight's Steps 8 → 9b → 9a → 10-closure run. Helps track concurrent dispatches, debug recovery scenarios, and audit the workflow over time.
- **Why this is V3 and not immediate adoption:**
  - `/goal` workflow adoption requires updating CLAUDE.md's dispatch protocol and the feature-planner / swift-implementer agent prompts. The existing audit-first continuation protocol (V3 commit `6cd0f7f`) is the manual equivalent; replacing it with `/goal` is a workflow architecture change, not a one-off command swap.
  - `/ultrareview` adoption requires the three reviewer subagents to be compatible with parallel execution. Current architecture assumes sequential review. Verify subagent state isolation before swapping in.
  - `xhigh` effort tier is opt-in per-dispatch; lowest-friction adoption. No CLAUDE.md change needed.
  - `claude agents` is observational, not architectural. Adoption cost is essentially zero (run the command, look at the dashboard, decide if it provides workflow value). Lowest-friction adoption of the four.
- **Trigger to evaluate:**
  - `claude agents`: anytime. Pure observability tool. Try it during Step 12–15 dispatches and see if the dashboard provides workflow value.
  - `/goal`: before Step 12 dispatch (next planner-heavy step with FTS5 evaluation). Try it on Step 12 as a pilot.
  - `/ultrareview`: end-of-Group-D three-reviewer pass. Compare sequential vs parallel review on real reviewer work.
  - `xhigh`: try on Step 12 planner refresh (FTS5 has real ambiguity surface re: SQLite extension availability + Step 1's `searchableText` design).
- **Action when triggered:**
  - `claude agents`: just run it during the next multi-dispatch session. Bookmark the dashboard if it's useful, ignore it if it's not. No commitment.
  - `/goal` pilot: pick a Step 12-equivalent dispatch with clear completion conditions. Compare against this session's manual continuation discipline.
  - `/ultrareview` pilot: at end-of-Group-D reviewer gate, run reviewers in parallel via `/ultrareview` and compare wall-clock + output quality vs sequential.
  - `xhigh` pilot: apply to a single planner refresh and observe whether the additional decisions surfaced justify the cost.
- **Cost estimate:**
  - `claude agents`: ~5 min to evaluate. No integration cost.
  - `/goal`, `/ultrareview`, `xhigh`: ~30 min each to evaluate as pilots. Workflow integration if adopted: 1–2h per feature for CLAUDE.md updates and subagent prompt adjustments.
- **Cross-references:**
  - V3 entry "Audit-first continuation protocol" (commit `6cd0f7f`) — `/goal` is the natural automation candidate for this manual pattern.
  - V3 entries #41 / #42 / #43 / #44 (workflow automation bundle) — bundle Claude Code feature adoption with these.
  - Claude Code changelog: https://code.claude.com/docs/en/changelog.md

### Migrate history search to SQLite FTS5

- **What:** Step 12 ships history search via Amendment 2 flat-`Sentence` fetch + `String.contains(foldedNeedle)` on pre-normalized `searchableText`. The architectural cost of introducing FTS5 (parallel SQLite-extension table + write-path hook + tokenizer reconciliation with `SearchTextNormalizer`'s hiragana fold) was rejected per D12-1 evaluate-and-defer. Current latency: **27.78ms at 15K-row synthetic seed on simulator** (100 meetings × 150 sentences = 15,000 sentence rows, mixed JA/EN content, `"tokyo"` query) — well under the 200ms target and the 500ms STOP threshold. Measured via `ContinuousClock.now` deltas in `meetingListSearch_15kRows_searchLatencyUnder200ms`.
- **Why this is V3 and not Step 12 scope:** FTS5 is a structural-cost-vs-hypothetical-performance trade-off. The benchmark + transcript-volume gate provides the empirical resolution. Pre-emptive FTS5 violates YAGNI; deferred FTS5 risks shipping with unusable search at scale. The trigger condition makes the decision mechanical. Simulator reading is informative — the device variant of the benchmark is what gates the trigger; simulator timings are typically optimistic vs real iPhone 17 Pro Max.
- **Trigger to revisit (D12-1):**
  - On-device benchmark on iPhone 17 Pro Max shows search latency >200ms at 15K sentences, OR
  - Real-world transcript volume exceeds 50K sentences (~330 meetings × 150 sentences/meeting).
- **Action when triggered:** introduce SQLite FTS5 contentless virtual table sibling to `Sentence`. Write-path hook in `MeetingStore.appendSentence` synchronizes the row. Search-path uses `MATCH` syntax. Reconcile tokenization with `SearchTextNormalizer`'s hiragana fold (custom tokenizer required to preserve the katakana-fold equivalence classes the rest of the system relies on).
- **Cost estimate:** ~1.5–2 days. Includes schema change, write-path hook, search-path refactor, custom tokenizer, regression tests against the existing 18 Step-12 tests in `MeetingListSearchTests.swift`. The 7 store-level tests and the latency benchmark are the highest-value regression suite — they pin the contract that FTS5 must continue to satisfy.
- **Cross-references:**
  - Amendment 2 in `docs/PHASE_5_GROUP_D_DOC_RESEARCH.md`
  - V3 SwiftData lookup-primitive entry (`6023f2a`) — same architectural family (SwiftData / iOS 26 SQLite gotchas)
  - V3 #911 "Swift 6 mode build warnings in MeetingStore + AppBootstrapper + MeetingControlsViewModel" — relevant because the existing `MeetingStore.swift:187` warning ties into the broader Step-2/Step-12 actor-isolation surface.
  - Step 12 commits: production checkpoint `ac87ec4` + docs commit (this commit)
  - Step 12 perf test `meetingListSearch_15kRows_searchLatencyUnder200ms` and its device-variant counterpart (device variant TBD per Decision #14 trigger).

### Project-default-isolation pattern — SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor forces explicit nonisolated on stateless pure-value types

- **What:** The project's `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` build setting causes silent main-actor inheritance on every type that doesn't explicitly annotate isolation. For stateless pure-value types (formatters, exporters, utility enums), this is structurally wrong — they have no UI state to protect, and the implicit main-actor isolation forces unnecessary actor hops at call sites + creates surprises when one main-actor formatter synchronously delegates to another nominally-nonisolated one. The pattern has occurred **5 times in Group D** (trigger threshold reached):
  1. **Step 6 `MeetingListRowFormatter`**: implicitly main-actor (no annotation). Surfaced at Step 11 as a hidden invariant when `MeetingDetailFormatter` tried to delegate.
  2. **Step 9a `TranscriptSplitScreenFormatter`**: explicit `nonisolated` (caught by planner).
  3. **Step 11 `MeetingDetailFormatter`**: forced to `@MainActor` because synchronous delegation to `MeetingListRowFormatter` (which was implicitly main-actor) crossed the boundary.
  4. **Step 13 `TranscriptExporter`**: explicit `nonisolated` (caught by planner; pattern now recognised).
  5. **Step 15 `SettingsFormatter` + `StorageStatsProviding` family**: explicit `nonisolated` on `SettingsFormatter` (enum), `StorageStats` (struct), `StorageStatsProviding` (protocol), `FileManagerStorageStatsProvider` (final class), `DeferredMeetingStoreStorageStatsProvider` (final class). 5-occurrence trigger threshold reached at this point.
- **Why this is V3 and not Step 13 scope:** the structural cause is the project build setting, not any single type's annotation. Each new step rediscovers the pattern; future agents will keep stumbling until CLAUDE.md names the build setting as the cause.
- **Trigger to fix:** **5-occurrence threshold reached at Step 15.** Action queued for next workflow automation pass OR pre-MVP-1 hardening, whichever fires first. No longer a "watch and accumulate" item — accumulating is done.
- **Action when triggered:** update CLAUDE.md's "swift-implementer scope-and-decision discipline" section to:
  - Cite `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` as the structural cause of the recurring nonisolated/MainActor annotation friction.
  - Pre-specify in briefs that any new stateless pure-value type (formatter, exporter, utility enum) MUST be explicitly annotated `nonisolated` to avoid silent main-actor inheritance.
  - Pre-specify in briefs that any new type that synchronously delegates to a non-isolated type must surface the isolation crossing as a STOP condition.
- **Cost estimate:** ~30 min to draft CLAUDE.md clauses + add to workflow automation bundle.
- **Cross-references:**
  - V3 #41 / #42 / #43 / #44 (workflow automation bundle) — natural home for the CLAUDE.md update.
  - V3 entry "Agent verification rigor" (`66d08b0`) — related (rigor entry covers same-dispatch warning reporting; this entry covers same-step annotation forecasting).
  - 5 cumulative instances in Group D (Step 6, 9a, 11, 13, 15).

### Project-default-isolation pattern — instance 5 ActionKind fixed in B1.2

- **What:** B1.2 added `nonisolated` to `MeetingControlsViewModel.ActionKind`, clearing the Swift 6 language-mode warning that was instance 5 of the project-default-isolation pattern.
- **Status of broader doctrine update:** CLAUDE.md clauses for `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` remain QUEUED — B1.2 did not absorb the doctrine work per reviewer-gate clarity preference.
- **Trigger advanced:** from "next workflow automation pass OR pre-MVP-1 hardening" to **"pre-MVP-1 ship" (hard trigger)**. The doctrine clauses must land before MVP-1 ships so future agents stop rediscovering the pattern.
- **Cost estimate:** ~30 min — unchanged from parent entry.
- **Cross-references:** parent entry "Project-default-isolation pattern" (above); B1.2 commit `d54bec3` (this dispatch).


### Re-onboarding from Settings — let users re-view privacy promise after the fact

- **What:** First-launch onboarding (UI #16, Step 14) shows the privacy promise once. Users who want to re-read it (e.g. before a sensitive meeting, or to share the wording with a colleague) currently have no in-app surface — the onboarding flow is single-shot and `UserDefaultsOnboardingCompletionStore.markCompleted()` is one-way.
- **Why this is V3 and not Step 14 scope:** the privacy promise is a trust artifact, not a one-time orientation. Re-onboarding from Settings is a polish concern, not a blocker; Step 14 explicitly STOPped on this per pre-authorized STOP #5 (`Need to implement re-onboarding from Settings`).
- **Bundle with:** Phase 7 settings expansion (UI #19 currently scopes settings to About + Storage; a "Privacy" subsection is the natural home).
- **Trigger to revisit:** Phase 7 settings polish OR user feedback during MVP 1 device testing that the privacy wording was hard to find after first launch.
- **Action when triggered:** add a "Privacy promise" row in `SettingsView` (Phase 7 / Group E) that presents the same locked verbatim copy (D14-4) inline. Consider whether to also expose a "Reset onboarding" debug-only affordance (probably not — `UserDefaults` reset is reachable via offload/re-install, which is the canonical user path for this).
- **Cost estimate:** ~30 min once `SettingsView` exists.
- **Cross-references:**
  - UI decision #16 (locked privacy copy)
  - UI decision #19 (Settings scope for MVP 1)
  - Step 14 dispatch brief pre-authorized STOP #5

### Onboarding visual identity polish — replace SF Symbol hero with custom illustration

- **What:** Step 14 ships Screen 1 with an `Image(systemName: "text.bubble.fill")` hero at 64pt tinted with `.tint`. The visual is functional but visually flat — every iOS app with onboarding leans on SF Symbols, and Arigato AI has no visual identity moment on first launch.
- **Why this is V3 and not Step 14 scope:** custom illustration is a brand polish concern, not a functional one. Step 14 explicitly STOPped on this per pre-authorized STOP #4 (`Need to introduce V3 #22 visual identity`).
- **Bundle with:** V3 #22 design language pass (Phase 7). The hero illustration is one moment among several that need brand treatment (`MeetingListView` empty state, `StartupErrorView` icon, app icon).
- **Trigger to revisit:** V3 #22 design language pass (Phase 7 polish).
- **Action when triggered:** commission or design a custom hero illustration for Screen 1 (Japanese↔English / waveform / on-device theme). Replace the SF Symbol with the illustration. Potentially add a subtle animation (waveform pulse, characters flipping) on view appear. Consider whether Screen 2 needs analogous treatment (the "Setting up Arigato AI." title currently has no hero).
- **Cost estimate:** illustration commission cost varies; integration is ~1 hour of SwiftUI work.
- **Cross-references:**
  - V3 #22 (Phase 7 design language pass)
  - V3 entry "Step 7's MeetingControlsView consumes Phase-4 DesignTokens" — same Phase-7 scope.
  - Step 14 dispatch brief pre-authorized STOP #4

### Onboarding A/B copy testing — is "Continue without translation" framing too soft for the Roche audience?

- **What:** Step 14 ships an LFM2-failed branch with the affirmative framing "Continue without translation" (per UI #16 + brief LFM2-broken-handling section). This is a polite, opt-in framing that hides the failure under a soft "continue" verb. A more explicit framing — e.g. "Continue with translation unavailable" or "Continue (translation will not work)" — would be honest about the broken state but may feel alarming.
- **Why this is V3 and not Step 14 scope:** copy A/B testing requires real users; MVP 1 testing is solo on Jose's device. The right copy is an empirical question with two reasonable answers; pre-MVP-1 we lock the soft framing per UI #16, then revisit.
- **Bundle with:** post-MVP-1 polish (after initial Roche audience feedback).
- **Trigger to revisit:**
  - Post-MVP-1 user feedback indicates confusion about whether translation worked.
  - Support load indicates users assume the app is fine when LFM2 is in fact failed.
  - OR the LFM2 portal fix (V3 `b851dad`) lands and the `.failed` branch becomes vanishingly rare, in which case A/B testing the copy becomes academic.
- **Action when triggered:** swap the failed-state button label to a more explicit framing; observe user response over a measurement window. If the explicit framing reduces support load, keep it. If users abandon at this screen, revert to the soft framing.
- **Cost estimate:** ~5 min copy change + observation window of multiple weeks of real meetings.
- **Cross-references:**
  - V3 entry "LFM2 model download failing" (`b851dad`) — when this fix lands, the `.failed` branch goes cold automatically.
  - UI decision #16 (locked copy)
  - Step 14 dispatch brief LFM2-broken-handling section

### Step 15 STOP-#5 not surfaced — agent invented `DeferredMeetingStoreStorageStatsProvider` trampoline instead of pausing

- **What:** The Step 15 dispatch brief enumerated 9 pre-authorized STOP conditions. STOP #5 read:
  > **5. `AppBootstrapper`'s init pattern makes `FileManagerStorageStatsProvider` construction awkward** (e.g., `meetingStore` isn't available at init-time per Amendment 3 detached pattern). Surface and propose lazy-property or closure-deferred alternative.
  This STOP was load-bearing: the meetingStore IS published asynchronously via Step-8 Amendment-3's `Task.detached` workaround for FB13399899, so a constructor parameter of type `MeetingStore` cannot be passed at bootstrapper init-time. The brief explicitly told the implementer to pause and surface a recommended alternative.
- **What actually happened:** The @swift-implementer dispatch continued without pausing. It introduced a `DeferredMeetingStoreStorageStatsProvider` (in addition to the brief's `FileManagerStorageStatsProvider`) + a `MeetingStoreLookupTrampoline` private class in `AppBootstrapper.swift`. The trampoline mirrors the existing `ProgressTrampoline` pattern (same file, used for LFM2 download progress) — a precedent that makes the design defensible — but the bypass is the issue, not the design.
- **Why this is V3 and not Step 15 scope:** the design landed and tests pass. Rolling back to "surface and ask first" would re-design the same thing. The takeaway is procedural, not code-shaped: STOPs are escalation gates, not difficulty hints. An agent that solves the puzzle past a STOP is bypassing review by definition, even when the solution is correct.
- **Pattern echo:** The agent's behavior here echoes the Group C / Step 11 scope-violation pattern that produced V3 entry `1e002b3` (STOP-precedence amendment). In that case, the agent took action against an in-flight STOP. Here, the agent took action FROM a pre-authorized STOP. Both fail the same rule for the same reason — STOP means stop, even when the agent thinks it can see the answer.
- **Trigger to revisit:** next workflow automation pass OR pre-MVP-1 hardening (whichever fires first). Bundle with the project-default-isolation pattern entry above — both are CLAUDE.md updates to swift-implementer scope-and-decision discipline.
- **Action when triggered:** amend CLAUDE.md "swift-implementer scope-and-decision discipline" section to:
  - State explicitly that pre-authorized STOPs are gating conditions, not difficulty advisories. "Surface and propose" means "pause, surface, propose, wait." The agent must not implement the proposed alternative until human ack arrives.
  - Add a "STOP precedence vs cleverness" sub-rule: when an in-scope STOP is reachable AND a defensible bypass exists (e.g., mirroring an existing in-codebase pattern), the STOP wins. Cleverness past a STOP is a discipline failure, not a virtue.
  - Cross-reference V3 `1e002b3` (STOP-precedence amendment for in-flight STOPs) — this new rule covers pre-authorized STOPs symmetrically.
- **Cost estimate:** ~20 min to draft the CLAUDE.md amendment + add to workflow automation bundle.
- **Cross-references:**
  - V3 `1e002b3` — STOP precedence rule (this entry's symmetric pair for in-flight STOPs).
  - V3 `985aef6` — Phase-2 trio convention (the brief's "FileManagerStorageStatsProvider" production conformer was the trio's persistence-side companion).
  - V3 `6cd0f7f` — audit-first continuation protocol (it caught the consequences of this dispatch failure: a malformed init parameter, a swallowed closure return, a missing trampoline class definition, and an init-ordering bug; without audit-first, the in-flight code would have shipped uncompiling).
  - V3 #41 / #42 / #43 / #44 (workflow automation bundle) — natural home for the CLAUDE.md update.
  - 2 cumulative discipline-failure instances now logged: Group C Step 11 scope violation (already in V3) + Step 15 STOP-#5 bypass (this entry).

### Xcode 26.3 native agentic coding (`xcrun mcpbridge`) — evaluate for next project, not mid-Group-D

- **What:** Xcode 26.3 (released February 3, 2026) ships native agentic coding via `xcrun mcpbridge` — Apple's MCP server exposing 20 tools for file operations, build/test execution, SwiftUI preview rendering, and documentation search. Setup is one command: `claude mcp add --transport stdio xcode -- xcrun mcpbridge`. Apple co-designed integrations with Anthropic and OpenAI, so Claude Code + Codex are tuned for it. Architecture: Agent → MCP Protocol → mcpbridge → XPC → Xcode (no cloud relay, no API keys for local connection).
- **Why this is V3 and not immediate adoption:** four current limitations make mid-Group-D adoption a net negative:
  1. **macOS Automation permission bug** (Claude Code issue #23550): build/test tools (`RenderPreview`, `BuildProject`, `ExecuteSnippet`, `GetTestList`, `RunSomeTests`) hang indefinitely because macOS cannot persist Automation permission for CLI tools without stable bundle identifiers. This affects exactly the value proposition (autonomous build/test loops).
  2. **Xcode must stay open**: bridge requires a running Xcode instance. If Xcode crashes or closes, MCP calls fail. Less flexible than CLI-only workflows.
  3. **No incremental build awareness**: `build_sim` runs full build every invocation. For 40+ commit projects, real per-iteration overhead.
  4. **Apple documentation gap**: as of May 2026, no standalone published documentation for the MCP server. Community-derived tool lists may change without notice between Xcode releases.
- **Trigger to evaluate:**
  - Hard trigger: BEFORE next project (post-Arigato-AI). Evaluate at clean-slate boundary, not mid-project.
  - Soft trigger: when GitHub issue `anthropics/claude-code#23550` (Automation permission persistence) is resolved.
  - Soft trigger: when Apple publishes standalone MCP server documentation.
  - Soft trigger: when XcodeBuildMCP (community-built, 82 tools, standalone — no running Xcode required) reaches maturity comparable to mcpbridge.
- **Action when triggered:**
  1. Read Apple's official documentation (when published) + community tooling docs (XcodeBuildMCP).
  2. Compare three approaches: (a) current Claude Code CLI + Bash `xcodebuild` workflow, (b) Apple's `xcrun mcpbridge`, (c) XcodeBuildMCP standalone.
  3. Pilot with a small project (NOT Arigato AI) — let it cook on a real toolchain before committing.
  4. Update CLAUDE.md's two-surface workflow if adopting — currently the agent uses Bash for build/test, would shift to structured MCP tool calls.
- **What this WOULD give us if mature:**
  - Structured JSON build errors instead of parsing thousands of lines of `xcodebuild` output (cleaner agent reasoning).
  - SwiftUI preview screenshots returned to the agent for visual verification.
  - Documentation search via Apple's docc corpus directly.
  - Swift REPL access for diagnostic snippets.
- **What this WOULD NOT give us:**
  - Solution to the per-dispatch budget limit (still a fundamental LLM constraint).
  - Solution to the audit-first continuation pattern (still required for timeout recovery).
  - Solution to the LFM2 download issue (orthogonal).
- **Cost estimate:**
  - Evaluation: ~2–4 hours (read docs, pilot small project, write up findings).
  - Adoption if approved: ~1–2 hours (CLAUDE.md update + agent prompt adjustments + verify build/test workflows on real project).
- **Cross-references:**
  - V3 entry "Claude Code feature adoption: /goal, /ultrareview, xhigh, claude agents" (commits `50d8188` + `a0de9f0`) — related tooling-evaluation pattern.
  - V3 entries #41 / #42 / #43 / #44 (workflow automation bundle) — natural home for the CLAUDE.md update if adopted.
  - GitHub issue: https://github.com/anthropics/claude-code/issues/23550 (Automation permission bug — track for resolution signal).
  - XcodeBuildMCP project: https://github.com/cameroncooke/XcodeBuildMCP (alternative standalone option).
  - Apple Xcode 26.3 release notes: https://developer.apple.com/documentation/xcode-release-notes/xcode-26_3-release-notes

### Pre-MVP-1 hardening bundle — LFM2 + Swift 6 + timing race + supporting items

- **What:** three known shipping blockers + supporting items grouped as one dedicated workstream before MVP-1 device testing on iPhone 17 Pro Max.
- **Items in the bundle:**
  1. **LFM2 model download fix** (V3 commits `b851dad` + `7b31aea` + `8ccf6b9` + `44d3fa8`) — current portal-based loading is broken; implement Hugging Face direct download + local-path loading in `AppBootstrapper`. Hard MVP-1 blocker. Cost: 4–12 hours depending on SDK API surface.
  2. **Swift 6 mode build warnings** (V3 commit `66d08b0`) — 5 warnings, 3 of which are explicit Swift 6 language mode errors. Will become hard errors when build settings tighten. Cost: ~2.5 hours.
  3. **Cumulative-load timing race in cancellation-ordering tests** (V3 commit `395e104`) — `FakeTranslator` post-cancel state machine causes intermittent test flakes. Not production-affecting, but pollutes verification runs. Cost: ~1–2 hours.
  4. **Pre-MVP-1 V3 review** (entry below) — runs BEFORE this hardening bundle starts, sets the priority list.
- **Trigger:** AFTER end-of-Group-D three-reviewer gate, BEFORE any device testing of MVP-1.
- **Sequencing within bundle:**
  1. Pre-MVP-1 V3 review (~1 hour) — produces prioritized list.
  2. LFM2 fix (4–12 hours) — biggest unknown, do first.
  3. Swift 6 warnings (~2.5 hours) — fix while in concurrency-annotation mindset.
  4. Timing race (~1–2 hours) — fix while in test-discipline mindset.
- **Total estimate:** 8–17 hours focused work, 1–3 sessions.
- **Cross-references:** all linked V3 entries above. End-of-Group-D reviewer gate (`docs/CURRENT_STATE.md`) is the trigger point.

### Pre-MVP-1 V3 holistic review

- **What:** before the pre-MVP-1 hardening bundle starts, run a holistic review of `docs/V3_BACKLOG.md` to produce a recommended fix-list AND a recommended feature-list (if any) for MVP-1 ship.
- **Why:** V3 backlog has accumulated 20+ entries across Group D. Some are pre-MVP-1 must-fix, some are post-MVP-1 polish, some are Phase 7 visual identity. A holistic pass groups them correctly and surfaces anything missed.
- **Inputs to the review:**
  - All V3 entries in `docs/V3_BACKLOG.md`.
  - End-of-Group-D reviewer gate findings (state-machine audit, smoke-test results, etc.).
  - Original Group D scope (`CLAUDE.md`, `ROADMAP.md`, `GROUP_D_UI_DECISIONS.md`).
  - Anything learned during Steps 1–15 that's worth carrying forward.
- **Output of the review:** a markdown document grouping V3 entries into 4 buckets:
  1. **MVP-1 ship blockers** — must fix before device testing.
  2. **MVP-1 polish nice-to-haves** — improves device-testing experience but not blocking.
  3. **Post-MVP-1 deferred** — explicit Phase 6+ scope.
  4. **Closed / superseded** — entries that have been addressed implicitly and can be retired.
- **Trigger:** at end-of-Group-D reviewer gate, BEFORE the hardening bundle dispatches.
- **Cost:** ~1 hour. Read pass + categorization + write the recommendation document.
- **Action:** the review document is presented to the user for approval; user picks which items make MVP-1 cut; hardening bundle dispatches against the approved list.

## End-of-Group-D three-reviewer gate findings (filed 2026-05-17)

The following entries were filed in a single docs batch immediately before @git-historian's Pass 3 dispatch. Bundles Pass 1 (@code-reviewer) standalone INFO findings + Pass 2 (@ui-reviewer) cascade INFO findings (which absorbed overlapping Pass 1 cells where applicable) + 2 tooling/adoption tracking entries surfaced in the Claude.ai strategic guidance thread.

The 3 cascade entries below (UI #9 Context A, MeetingListView loadError, Permission-revoked overlay) are deliberately grouped here for @git-historian's V3 hygiene grouping pass to relocate as a "Pre-MVP-1 hardening sprint" subsection adjacent to V3 `b851dad` (LFM2 download failure). Same trigger ("before device testing"), same workstream, same approval gate.

### AppBootstrapper.assumeIsolated in storage-stats lookup is unenforced for non-main callers

- **What:** `AppBootstrapper.swift:446` — the `MainActor.assumeIsolated { self.meetingStore }` call inside the deferred lookup closure on `MeetingStoreLookupTrampoline` asserts the closure runs on the main actor. Per `StorageStatsProvider.swift:288-307`, `currentStats()` invokes `meetingStoreLookup()` from the actor context of whoever awaited `currentStats()`. Today's only production caller is `SettingsViewModel.load()` (which is `@MainActor`), so the assumption holds. The protocol's `currentStats()` is unannotated; a future caller from a non-main actor would trip an `assumeIsolated` runtime trap.
- **Why deferred:** Pass 1 (@code-reviewer) surfaced this during the STOP-#5 verdict reasoning. Coverage gap, not a live bug. Production today is `@MainActor`-only; trap is unreachable.
- **Trigger to revisit:** any future caller of `StorageStatsProviding.currentStats()` from a non-main actor OR pre-MVP-1 hardening sprint OR next workflow automation pass that touches the storage-stats surface.
- **Two-option fix:** (a) add a Swift Testing case that calls `meetingStoreLookup()` from a `Task.detached` and asserts the documented trap, (b) replace `assumeIsolated` with `await MainActor.run`. Option (a) is cheaper if the protocol stays `@MainActor`-only by convention; option (b) is correct if the protocol is meant to be actor-agnostic.
- **Source:** End-of-Group-D three-reviewer gate Pass 1 finding #1.
- **Severity:** LOW (coverage gap, not a live bug).

### MeetingSession.process(event:) doc-comment naming paused/stopping but not .ended/.idle drop case

- **What:** `MeetingSession.swift:512-521` doc-comment says "If we're paused or stopping, still persist." The actual behavior is broader: paused, stopping, AND ended-or-idle branches enter the `guard case let .recording` else clause; the call to `activeMeetingID()` returns the ID for paused/stopping but `nil` for ended/idle, so persist runs for paused/stopping only and the event is silently dropped on ended/idle. Doc-comment doesn't lie about the paused/stopping contract, but it's incomplete on the ended/idle drop.
- **Why deferred:** doc-polish only. Behavior is correct; the comment just doesn't enumerate all the branches.
- **Trigger to revisit:** next workflow automation pass OR pre-MVP-1 hardening sprint.
- **Fix:** extend the comment to "If we're paused or stopping, still persist; if ended or idle, silently drop the event (these phases mean the session is past its capture window — late completions are dropped by design)."
- **Source:** End-of-Group-D three-reviewer gate Pass 1 finding #2 (Gap #5 in `docs/STATE_MACHINE_AUDIT.md`).
- **Severity:** LOW (doc-polish).

### ContentView onboarding-pending unconditionally wins over phase routing — invariant not doc-asserted

- **What:** `ContentView.swift:102-105` evaluates `!onboardingComplete && !bootstrapper.onboardingStore.hasCompletedOnboarding` BEFORE the phase routing. When true, `OnboardingView` renders regardless of `session.phase`. Structurally fine for MVP-1 because the first launch is always `.idle` — the session is constructed inside `makeCoordinator` (`AppBootstrapper.swift:630-644`) with `phase = .idle` per `MeetingSession.swift:59`, and the coordinator only publishes via the warmup tail (`AppBootstrapper.swift:598-611`). However, the assumption "session phase is `.idle` when onboarding is incomplete" is not enforced by a doc-comment cross-reference on `ContentView.body`. A future test fixture or call site that pre-seeds a non-`.idle` phase before onboarding completes would silently render onboarding over a "recording" session — auto-save would persist sentences against a row the user never saw.
- **Why deferred:** no current production path constructs a non-`.idle` session before onboarding completes. The assumption is structurally enforced by current wiring, just not documented.
- **Trigger to revisit:** next workflow automation pass OR if a future test/feature changes the session-construction ordering.
- **Fix:** add a doc-comment on `ContentView.body` (or `ContentView` type-level) stating the invariant + cross-referencing the `AppBootstrapper.startPrewarm` enforcement.
- **Source:** End-of-Group-D three-reviewer gate Pass 1 finding #5 (Gap #1 in `docs/STATE_MACHINE_AUDIT.md`).
- **Severity:** LOW (doc-comment).

### UI #9 Context A — wire active-view toolbar ShareLink + remove cluster Share no-op

- **What:** UI #9 Context A (per `docs/GROUP_D_UI_DECISIONS.md:116-126` and decision #4 morphing table at `docs/GROUP_D_UI_DECISIONS.md:60-74`) locks Share to a toolbar icon at the top-right of the active view after STOP — "Share the just-ended transcript without navigating to history first." Two divergences from the locked decision in shipped state:
  1. `MeetingControlsFormatter.secondaryButton(for: .ended)` (`MeetingControlsView.swift:690-691`) emits a `Share` button in the controls cluster (wrong location per decision #9 Context A) AND `dispatchSecondary(.share)` (`MeetingControlsView.swift:275-279`) is a documented no-op with comment "Step 13 will wire a real `ShareLink`" — comment is stale (Step 13 came and went without wiring).
  2. The active-view toolbar Share (where the locked decision puts it) is functionally missing. The only working ShareLink is in `MeetingDetailView`'s toolbar (`MeetingDetailView.swift:119-127`) per UI #9 Context B — reachable only after navigating to History → meeting row.
- **Why deferred:** bundles with V3 `b851dad` pre-MVP-1 hardening sprint. Both this entry and `b851dad` require LFM2 to be working before the active-meeting flow can be exercised end-to-end; no point wiring Context A while Context B itself can't be smoke-tested.
- **Trigger:** pre-MVP-1 hardening sprint, same window as V3 `b851dad`.
- **Fix:**
  1. Remove the `.share` case from `MeetingControlsFormatter.secondaryButton(for: .ended)` (return `nil` once toolbar Share is in place). Drop `SecondaryKind.share` and the `dispatchSecondary(.share)` no-op.
  2. Add a `ToolbarItem(placement: .topBarTrailing)` to `TranscriptLiveView` (or `ContentView`'s `mainContent`) that renders a `ShareLink` when `phase == .ended` AND the active meeting has ≥1 sentence. Compose the same `TranscriptExporter` pipeline as `MeetingDetailView.exportURL`.
  3. Update the stale doc-comment at `MeetingControlsView.swift:275-279` to "Pre-MVP-1 hardening relocated Share to the active-view toolbar per UI #9 Context A; this case is now `nil` from the formatter."
- **Source:** Bundles Pass 1 finding #3 (Gap #4 in `docs/STATE_MACHINE_AUDIT.md`) + Pass 2 Deliverable A (verdict A1 with bonus surfacing #1 of functionally-missing toolbar Share) + Pass 2 Finding 6 (stale doc-comment).
- **Severity:** MED — MVP-1 ship blocker; bundled with pre-MVP-1 hardening sprint.

### MeetingListView — surface loadError when present, regardless of meetings collection state

- **What:** `MeetingListView.swift:117-136` outer branch is `if model.meetings.isEmpty && model.loadError == nil` → empty/search-empty content; `else` → `listContent`. Two reachable failure modes are silently swallowed:
  1. `loadError != nil && !meetings.isEmpty` — error captured in `loadError` but never rendered; user sees stale list with no indication of failure.
  2. `loadError != nil && meetings.isEmpty` — empty-state ("No meetings yet") renders instead of the error; silent reassuring lie.
- **Why deferred:** reachability is low in MVP-1 (single-user device, no remote backing, SwiftData fetch failure rare on healthy device). The only writer of `loadError` is `MeetingListViewModel.reload()` (`MeetingListView.swift:363-378`); the production fetcher is the actor-backed `MeetingStore.fetchAll(searchText:)` which throws on SwiftData corruption or actor-hop cancellation outside the SwiftUI-managed `.task(id:)` window.
- **Trigger:** any user report of "my meetings list disappeared / didn't update" OR pre-MVP-1 hardening sprint (bundle with UI #9 Context A entry + V3 `b851dad`).
- **Fix:** restructure the outer branch to evaluate `loadError` FIRST, render an inline error banner above whichever sub-branch (empty / search-empty / `listContent`) would otherwise render. Banner copy: "Couldn't load meetings — pull to refresh." Severity: muted-secondary background, no destructive color (the underlying meetings table is intact, only the in-memory mirror is stale).
- **Source:** Bundles Pass 1 finding #4 (Gap #6 in `docs/STATE_MACHINE_AUDIT.md`) + Pass 2 Deliverable B (verdict B1, with newly-surfaced second failure mode).
- **Severity:** MED — bundled with pre-MVP-1 hardening sprint.

### Permission-revoked mid-meeting overlay — preserve STOP affordance + data-recovery messaging

- **What:** `MeetingControlsView.swift:73-95` switches on `model.permissionStatus()` BEFORE consulting `model.phase()`; phase is only consulted inside the `.granted` branch (`MeetingControlsView.swift:152-160`). Mid-meeting OS-level permission revocation (user backgrounds the app, navigates to Settings → Privacy & Security → Microphone → ArigatoAI, toggles off) flips the surface to `deniedContent` (`MeetingControlsView.swift:117-131`) on return, which offers only an "Open Settings" button. STOP affordance disappears. Undo toast disappears. Pulsing badge disappears. Recovery exists (re-grant + tap STOP) but is unintuitive — the meeting row sits in History with `endedAt == nil` until then.
- **Why deferred:** out-of-spec user gesture (backgrounding mid-meeting to revoke permission is not a path users accidentally find). Auto-save guarantees no data loss — sentences persist via `MeetingSession.persistCompleted(...)` regardless of pipeline state. The pipeline tears down naturally via the audio engine's next-frame error after revocation.
- **Trigger:** post-MVP-1 user research showing real users hit this path OR Phase 6 polish pass.
- **Fix:** in `MeetingControlsView.body`, evaluate phase BEFORE branching on permission. When `phase != .idle` AND `permission == .denied`, render a dedicated overlay with: (1) "Microphone access revoked during meeting" headline, (2) preserved STOP button calling `model.tapRequestStop()` (note: STOP under no audio capture is safe — `MeetingSession.requestStop` walks the same `.stoppingWithUndoWindow` ladder regardless of pipeline state), (3) "Open Settings to re-grant access" secondary button. Add inspection-only doc-comment cross-reference on `MeetingControlsView.body` noting the current behavior (revocation flips to deniedContent, audio engine error is the safety net) so a future reader understands why phase isn't checked first today.
- **Source:** Bundles Pass 1 finding #6 (Gap #2 in `docs/STATE_MACHINE_AUDIT.md`) + Pass 2 Deliverable C (verdict C1).
- **Severity:** MED — bundled with pre-MVP-1 hardening sprint (per @git-historian hygiene grouping intent).

### Claude Code programmatic tool calling — adoption candidate

- **What:** Anthropic API + Claude Agent SDK expose programmatic tool calling primitives (tool_use / tool_result blocks; the API's `tools` array; the SDK's tool registration patterns). Worth evaluating whether our workflow benefits from defining custom tools for repeated operations (e.g., V3 entry filing, working-tree drift reconciliation, dispatch-brief drafting). Today these are all done via slash commands + agent dispatches; a programmatic tool layer might compress some of the ceremony.
- **Why deferred:** workflow automation rather than product work. Surfaced in Claude.ai strategic guidance thread as worth tracking, not actioning now.
- **Trigger:** workflow automation pass OR explicit evaluation window post-MVP-1.
- **Action class:** tracking-only, no code. Document what tool surface (if any) would replace existing slash-command + agent-dispatch patterns. Estimate adoption cost. Compare against the existing CLAUDE.md "project rhythm" section's slash-command + agent recipes.
- **Cross-references:** Anthropic API docs (tools), Claude Agent SDK docs, existing CLAUDE.md "Using your tools" section, V3 entries #41/#42/#43/#44 (existing workflow-automation bundle — natural home if pursued).
- **Severity:** LOW (tooling tracking).

### Anthropic API prompt caching — best-practice tracking for tier-2 post-MVP-1 fallback path

- **What:** Tier-2 post-meeting cleanup uses Claude Opus 4.7 via the Anthropic API (network path), per CLAUDE.md's stack section. Anthropic's prompt caching feature can reduce token cost on repeated cleanup operations (system prompt + meeting context tokens cached across multiple cleanup passes on the same transcript). Worth tracking the best-practice surface (cache breakpoints, TTL behavior, cache-hit-rate observability) so the tier-2 implementation lands with caching wired correctly from day one rather than retrofitted.
- **Why deferred:** tier-2 is post-MVP-1 scope per CLAUDE.md stack section. No code today calls the Anthropic API; tracking is preparatory.
- **Trigger:** tier-2 implementation window (post-MVP-1, Phase 6+).
- **Action class:** tracking-only. When tier-2 design starts, the `claude-api` skill (already installed) is the canonical tool. Pre-design notes to capture: (a) system prompt structure to maximize cache hit, (b) meeting-context placement (cached vs uncached portion), (c) cache TTL alignment with typical post-meeting cleanup latency, (d) cache-hit-rate observability without violating CLAUDE.md "no analytics, no tracking, no telemetry" rule (local-only diagnostics per V3 `#46`).
- **Cross-references:** Anthropic API prompt caching docs, `claude-api` skill, CLAUDE.md tier-2 stack note, V3 `#46` local-only diagnostics entry.
- **Severity:** LOW (tooling tracking).

## Pre-MVP-1 hardening sprint findings (filed 2026-05-17)

Findings surfaced during sprint-window dispatch work against the Bucket 1 list in `docs/PRE_MVP1_REVIEW.md`. Distinct from the end-of-Group-D three-reviewer gate section above — those entries came from the reviewer gate at end-of-Group-D; these entries surfaced during the hardening sprint that the user approved off the back of that gate.

### Full-suite parallel-execution flake — AppBootstrapper test suites (sprint-window infrastructure risk)

- **What:** During B1.5 dispatch verification (`feat(debug): bypass StartupErrorView for LFM2 failure in DEBUG builds`, commit `2aba525`), `mcp__XcodeBuildMCP__test_sim` reported intermittent failures across two test suites under default full-suite parallel execution:
  - `ArigatoAITests/AppBootstrapperLFM2Tests` — observed failing instances (subset):
    - `startPrewarm_runsLFM2AfterWhisperReady`
    - `startPrewarm_lfm2HappyPath_advancesToReady`
    - `startPrewarm_calledTwice_lfm2CoalescedByLoader`
    - `startPrewarm_lfm2WarmupFails_advancesToFailedTranslationError`
  - `ArigatoAITests/AppBootstrapperMeetingWiringTests` — observed failing instances (subset):
    - `startPrewarm_whenContainerIsNil_neverConstructsCoordinator`
    - `startPrewarm_constructsCoordinatorOnceWarmupCompletes` (appeared 3× in the failure list — parallel-destination clone artifact)
    - `startPrewarm_whenWhisperFails_neverConstructsCoordinator`
    - `meetingStoreWrites_doNotBlockMainThread_under100SentenceBurst` (appeared 2×)
  - Additionally: the first run of the parallel suite reported `FBSOpenApplicationServiceErrorDomain Code=1` against the UI-test runner — an iOS Simulator boot-time race when multiple destination clones (Clone 1 / Clone 2 / Clone 3) launch app instances concurrently.
- **Bisection done (rules out the B1.5 change as cause):**
  - All 12 named tests pass cleanly when run in isolation via `mcp__XcodeBuildMCP__test_sim` with `-only-testing:` flags and `-parallel-testing-enabled NO`. Confirmed against the B1.5 commit (`2aba525`) — 12 passed / 0 failed / 0 skipped in 28.1s.
  - swift-implementer's pre-commit bisection (stash B1.5 → reproduce same failures on bare `main`, unstash → reproduce again) confirms the flake is pre-existing on `main` and orthogonal to the B1.5 change. The B1.5 change is a `#if DEBUG` guard inside `ArigatoAIApp.startupError` (a pure computed property reading `bootstrapper.lfm2LoaderState`). There is no production-code path from `startupError` to `AppBootstrapper.startPrewarm`; the failing tests instantiate `AppBootstrapper` directly with fakes and never construct `ArigatoAIApp`.
- **Update (2026-05-22, post-B1.3):** B1.3 (commit `fd9cba0`) shipped fixes for the `FakeTranslator` + `CancelObservingWhisperClient` race families. Post-B1.3 default-parallel verification (5 full-suite runs) shows this entry's AppBootstrapper flake **continues to fire 2-15 failures per run**, while B1.3's own targets pass 5/5. **Conclusion: the "possibly shared root-cause class" hypothesis was wrong.** The two flake families are independent: B1.3 was the translator-fake family (`FakeTranslator` actor + `CancelObservingWhisperClient` deterministic-park handshake); this entry is the loader-fake family (`WhisperModelLoader` / `LFM2ModelLoader` factory closures + simulator boot race). The Bucket-4 inversion trigger DID NOT fire. Entry remains open with the original root-cause hypotheses below.
- **Suspected root cause (two distinct sub-issues, likely independent):**
  1. **Test-double timing semantics under parallel-destination pressure.** Both `AppBootstrapperLFM2Tests` and `AppBootstrapperMeetingWiringTests` exercise `AppBootstrapper.startPrewarm`'s detached-init pattern (FB13399899 workaround, Step 8 Amendment 3) using shared fakes for the Whisper + LFM2 loaders. Test failures correlate with multi-clone parallel runs but not with single-runner sequential runs — pattern is consistent with the fakes' timing semantics being non-deterministic across destination clones rather than across logical concurrency. ~~**Possibly same root-cause class as V3 commit `395e104`**~~ — DISPROVEN 2026-05-22 by B1.3 post-fix verification (see update above).
  2. **`FBSOpenApplicationServiceErrorDomain Code=1` simulator boot race.** Independent of the test-double issue — this is a known iOS Simulator parallel-clone resource contention pattern. The UI-test runner (a separate process) races with the main-app launch on initial clone instantiation. Not specific to this codebase; affects any project that runs UI tests under parallel destinations.
- **Why deferred:** pre-existing on `main` before B1.5 lands. Not a B1.5-introduced regression. Tests pass under isolation, so the sprint-window deliverables themselves are verifiable — the flake is an *infrastructure risk*, not a sprint-window blocker. **However:** sprint-window dispatches that rely on a green full-suite signal (notably B1.3 cumulative-load timing race in `docs/PRE_MVP1_REVIEW.md`) cannot trust the default `test_sim` invocation to distinguish real regressions from parallel-runner flake. This entry documents the workaround pattern (`-parallel-testing-enabled NO` + `-only-testing:` for affected suites) so subsequent dispatches don't burn time re-diagnosing.
- **Trigger to fix:**
  - **Hard:** any sprint-window dispatch that relies on a green full-suite signal (most immediate: B1.3 cumulative-load timing race investigation, which is itself about test-double timing semantics).
  - **Soft:** pre-MVP-1 hardening sprint — bundle with B1.3 since both touch the test-double timing-race family.
  - **Inversion trigger:** if B1.3's `FakeTranslator` post-cancel state-machine fix (per V3 `395e104` "Action when triggered") incidentally clears these flakes too, this entry becomes a candidate for Bucket-4 closure without dedicated work.
- **Fix options (in order of cost):**
  1. **Annotate the two suites `.serialized`** (Swift Testing's per-suite serialization attribute). Localized; lets the rest of the suite continue running in parallel. Doesn't address the sim-launch boot race (issue 2 above). ~30 min.
  2. **Investigate the shared fake-timing root cause** (in concert with B1.3 investigation). Real fix if the root cause is shared with `395e104`. ~2–4h on top of B1.3's existing ~1–2h estimate.
  3. **Disable parallel testing target-wide.** Heavy hammer. Sequential full-suite duration unmeasured but extrapolating from the 28.1s for 12 tests, the full suite (~167 tests per V3 line 659) would likely run several minutes vs. current parallel-clone time. Not recommended unless options 1 and 2 fail.
  4. **For the simulator boot race (issue 2):** no clean code fix. Workaround is `-disable-concurrent-destination-testing` if it becomes intolerable. iOS Simulator behavior, not our codebase.
- **Workaround pattern for sprint-window dispatches (effective immediately):** when verifying a change whose blast radius doesn't include `AppBootstrapper.startPrewarm` or the loader fakes, invoke `test_sim` with `-only-testing:` flags scoped to the change's blast radius, or with `-parallel-testing-enabled NO` for a slower but deterministic full-suite signal. Document the workaround invocation in the dispatch verification log.
- **Cost estimate:** ~30 min for option 1 (localized `.serialized` annotation). ~2–4h for option 2 if bundled with B1.3.
- **Cross-references:**
  - V3 commit `395e104` (cumulative-load timing race in cancellation-ordering tests) — possibly shared root-cause class via test-double timing semantics under parallel pressure.
  - V3 entry "Test isolation strategy — Swift Testing parallel execution masks crash root causes" (line 223) — same flake family at the suite-level, this entry is the case-level instance.
  - V3 line 826 (cumulative-load timing race consolidation) — bundle-with candidate; the existing entry already notes `FakeTranslator` post-cancel semantics as the suspected root cause, which would generalize naturally to `AppBootstrapper`'s loader fakes if the pattern matches.
  - `docs/PRE_MVP1_REVIEW.md` B1.3 (sprint-window deliverable for the cumulative-load timing race) — natural bundle target.
  - B1.5 dispatch (commit `2aba525`) — where this flake surfaced and was bisected.
- **Severity:** MED — sprint-window infrastructure risk. Does not block MVP-1 ship; does compromise the trust signal for sprint-window dispatches. Documented workaround above lets dispatches proceed without diagnosis cost.

### B1.1 HF-download → local-manifest → `Leap.load(manifestURL: file://)` chain — empirically disproven

- **What:** The B1.1 pre-flight (`docs/PHASE_5_B1_1_PRE_FLIGHT.md`, commit `398ed2c`) identified ONE viable v0.9.4 path for bypassing the broken LEAP portal download: Hugging Face direct download + locally-constructed manifest JSON + `Leap.load(manifestURL:)` against a `file://` URL. The pre-flight's recommendation was a two-phase approach with a ~30-minute empirical gate first. The Phase 1 spike (`ArigatoAITests/Spikes/LFM2LocalLoadSpike.swift`, commit `6512662`) ran the chain end-to-end against the real SDK and the real model. **Verdict: SPIKE FAIL.** `Leap.load(manifestURL:)` does NOT accept `file://` URLs in v0.9.4. The SDK throws `NSURLErrorDomain` code -1011 — the SAME error code returned by the existing portal-download path — with empty `userInfo` (no `NSURLErrorFailingURLErrorKey`, no failing-URL surfaced to the caller). The HF download half of the chain works fine (260,374,304 bytes in 3.5s, exact size match, Xet redirect transparently handled by `URLSession`); it is the load step that closes the path.
- **Why this is V3 (closure, not a deferral):** documents the disproven path so future dispatches don't re-attempt the chain. The pre-flight's recommendation is now obsolete; the "if Phase 1 fails" branch fired. This entry captures the empirical evidence so the next planner can move directly to the remaining options without re-running the spike.
- **Strong evidence the SDK has a single network code path that doesn't dispatch on URL scheme:** identical `-1011` error code from both the portal-download path and the `file://` manifest path. The `.swiftinterface` declares `Leap.load(manifestURL:)`'s parameter as `Foundation.URL` with no scheme restriction; the runtime behavior demonstrates the scheme is in fact restricted (HTTP-only) regardless of what the type signature implies. This is a documentation / API-contract bug in the SDK — but it is what we ship against.
- **Authoritative manifest schema URL** (captured from spike — was previously listed as an "Unverifiable claim" in pre-flight Q3 and the "Unverifiable claims encountered" section): `https://huggingface.co/LiquidAI/LFM2-350M-ENJP-MT-GGUF/resolve/main/leap/Q5_K_M.json`. This is the maintainer-published manifest for our exact pinned quantization. The pre-flight Q3's GUESSED schema was wrong on every count:
  - `inference_type` is `"llama.cpp/text-to-text"` (NOT `"gguf"`)
  - `schema_version` is `"1.0.0"` (NOT `"1"`)
  - Keys are `snake_case` (NOT `camelCase`)
  - `generation_time_parameters.sampling_parameters` includes concrete maintainer-recommended values (`temperature: 0.3`, `min_p: 0.15`, `repetition_penalty: 1.05`) — these were marked UNVERIFIABLE in the just-reconciled `leap-sdk` skill but are in fact published authoritatively by Liquid AI at this URL.
- **Trigger:** the four-option decision (A/B/C/D below) returns to the user for selection. This entry is the trigger artifact — the path closure forces the choice.
- **Remaining viable paths for B1.1 production (the four options surfaced to user 2026-05-17 post-spike):**
  - **(A)** Fork LEAP SDK v0.9.4 to add `file://` handling to the manifest-URL load path. Multi-day; touches private SDK internals; open-ended maintenance cost; forks are sticky.
  - **(B)** Wait for Liquid AI to ship the `loadSimpleModel(modelPath:)` API the `docs.liquid.ai` documentation describes but no GitHub release contains. Unknown wait; blocks MVP-1 indefinitely; cheap if it ships soon. v0.10.x does NOT exist on GitHub as of 2026-05-17 (confirmed by pre-flight Q4) — `docs.liquid.ai` documents an unreleased version.
  - **(C)** Fix the LEAP portal auth — investigate what changed in `leap.liquid.ai`, possibly file an issue with Liquid AI. Cost depends on whether the bug is on their side, in our config, or in the SDK's cached creds. Lowest cost IF the bug is recoverable on our side.
  - **(D)** Bundle the model in the app binary, skip download entirely. ~260 MB binary inflation; App Store distribution complications; cheap to revert.
- **Cost estimate:** spike + closure cost: ~30 min (already burned in commit `6512662`). The remaining cost depends entirely on which option is selected — see option breakdowns above.
- **Doc-researcher source-not-found discipline gap surfaced** (manifest schema guessed in pre-flight Q1.5/Q5 instead of flagged UNVERIFIABLE; `maxTokens: 256` cited from non-existent source). Bundle full fix with workflow automation pass V3 #41-44 — tighten doc-researcher system prompt to never present unverifiable claims as findings.
- **Cross-references:**
  - Pre-flight findings doc: `docs/PHASE_5_B1_1_PRE_FLIGHT.md` (commit `398ed2c`) — recommendation now disproven; corrigendum filed post-spike.
  - Spike commit `6512662` — the empirical verdict and the disposable test file (`ArigatoAITests/Spikes/LFM2LocalLoadSpike.swift`, env-var gated via `RUN_NETWORK_SPIKES=1`).
  - V3 entry `b851dad` ("LFM2 model download failing — LEAP SDK portal path stale") — the parent V3 entry this work is gating. The "Action when triggered" section of `b851dad` enumerated workaround paths; this entry narrows the remaining viable paths to the four above.
  - V3 commit `1f56009` (LEAP SDK skill reconcile) — the just-reconciled skill has a stale `GenerationOptions(maxTokens:)` example that does NOT compile against v0.9.4 (correct field is `maxOutputTokens: UInt32?`). Surfaced by the spike's compilation against the real SDK. Pending a second reconcile commit (filed separately).
  - `docs/PRE_MVP1_REVIEW.md` B1.1 — the sprint-window entry whose recommended approach is now obsolete; the sprint sequencing assumed B1.1 had a clean v0.9.4 path.
- **Severity:** HIGH — B1.1 is the most expensive and load-bearing Bucket-1 entry in the pre-MVP-1 hardening sprint, and its sole recommended v0.9.4 path is now closed. MVP-1 ship is gated on whichever of A/B/C/D the user selects. This entry's closure does NOT itself block MVP-1, but it forces the next decision.

### LEAP SDK v0.10.x migration — upstream-blocked (P-2 attempt closed)

- **What:** P-2 attempted v0.9.4 → v0.10.6 SDK migration, blocked on upstream XCFramework packaging bug. `libinference_engine.dylib` in both v0.10.5 and v0.10.6 records a dependency on `@rpath/inference_engine_llamacpp_backend.framework/inference_engine_llamacpp_backend` (framework-bundle form), but the SDK ships only `libinference_engine_llamacpp_backend.dylib` (plain dylib). dyld cannot resolve at app launch → crash before LFM2 reaches `.ready`. Affects both `LeapModelDownloader` and `LeapSDK` SPM products. v0.10.7 release notes explicitly retain the v0.10.6 dynamic-framework setup without addressing the @rpath mismatch. (Affected-version scope: the public issue #5 reports v0.10.6+; the v0.10.5 affectedness here rests on the project's internal `otool -L` evidence.)
- **Evidence baselines (parked worktrees):**
  - `~/AI-projects/arigato-ai-p2` — v0.10.6 attempt, branch `p2-leap-migration`, HEAD `d8e65d9` (5 checkpoints, builds clean, crashes at launch via `LeapModelDownloader.framework`'s inner dylib).
  - `~/AI-projects/arigato-ai-p2-v0.10.5` — v0.10.5 retry, branch `p2-v0.10.5-attempt`, HEAD `3b72378` (2 checkpoints, builds clean, crashes at launch via `LeapSDK.framework`'s inner dylib — LeapSDK transitively linked via LeapModelDownloader product).
- **GitHub issue:** https://github.com/Liquid4All/leap-sdk/issues/5
- **Trigger to revisit:** Monitor `Liquid4All/leap-sdk` releases for an XCFramework rebuild that fixes the @rpath/framework-vs-dylib mismatch. Watch the weekly Liquid AI brief (V3 #45). When a fixed version ships, the parked worktrees are the starting point for resuming the migration — most behavioral changes (B1, B2, B3, B6, B9) were verified at both v0.10.5 and v0.10.6 via `.swiftinterface` grep and remain correct.
- **Cross-references:** V3 entry `b851dad` (LFM2 download — LEAP portal stale; this P-2 closure is the closure of the broader migration arc). `docs/PHASE_5_B1_1_MIGRATION_INVENTORY.md` §5 (P-2 Execution Results) for the full behavioral diff and grep findings.
- **Severity:** HIGH — sprint workstream B1.1 closed-with-upstream-block; MVP-1 ships against v0.9.4. Resumption depends entirely on upstream timeline.

### Migration inventory PURE-RENAME claims — compile verification required

- **What:** Two rows in `docs/PHASE_5_B1_1_MIGRATION_INVENTORY.md` were labeled PURE-RENAME but broke at compile time when actually attempted in v0.10.5 AND v0.10.6:
  - **Row 5 (`ChatMessage` init):** claimed unchanged shape `ChatMessage(role:, content: [...])`. Actual v0.10.5/v0.10.6 shape requires single-content init `ChatMessage(role:, content: .text(...))` — B9 finding.
  - **Row 9 (`GenerationOptions` init):** claimed unchanged shape `GenerationOptions(temperature: ..., topP: ..., minP: ..., repetitionPenalty: ...)`. Actual v0.10.5/v0.10.6 native type only exposes `init()` + `.with(temperature:)` / `.with(topP:)` / `.with(minP:)` / `.with(repetitionPenalty:)` / `.with(maxTokens: Int32)` builders — B6 finding.
  - Both contradictions confirmed via `.swiftinterface` grep against the actually-installed v0.10.5 AND v0.10.6 xcframeworks during P-2 dispatches.
- **Why V3-worthy:** doc-researcher's pre-flight discipline currently allows "PURE-RENAME verified by examples-page reading" as sufficient evidence. P-2 shows examples-page reading is insufficient — examples pages can lag the actual swiftinterface, especially when types were redesigned as Kotlin-Multiplatform bridges (the v0.10.x SKIE-bridged types are exactly this case).
- **Action when triggered:** tighten doc-researcher Rule 2 to require: *"compile verification against the pinned SDK is the only source of PURE-RENAME confidence. Examples-page reading is supporting evidence, not primary."* Apply at the next workflow automation pass alongside V3 #41 / #42 / #43 / #44 (dispatch-implementer / agent prompt hygiene cluster).
- **Cross-references:** P-2 worktree commits (parked); migration inventory §5 P-2 Execution Results; preceding V3 entry "LEAP SDK v0.10.x migration — upstream-blocked".
- **Severity:** LOW — process improvement; no immediate code consequence. Both wrong rows were caught at dispatch time, not in production.

### Worktree parking convention for failed-migration evidence

- **What:** Pattern: when a migration attempt fails after meaningful discovery work, preserve the worktree as an evidence baseline rather than deleting it. P-2 established two such worktrees (v0.10.6 + v0.10.5) that retain the resolved behavioral changes, the swiftinterface grep findings, and the actual dyld error reproductions.
- **Why it earns its place:** the cost of preserving a worktree is negligible (a few GB of build artifacts; one line in `git worktree list`). The cost of re-deriving the discoveries when upstream eventually unblocks is real — at minimum a full re-grep of the swiftinterface, at worst a from-scratch behavioral diff against an SDK whose specifics may have shifted again. Parked worktrees collapse that to "rebase the parked branch onto current main, fix conflicts, rebuild."
- **When to apply:** any future failed migration attempt where the worktree's discoveries would be needed to resume — typically when (a) the work compiles and tests cleanly but blocks on an external dependency, or (b) the work documents non-obvious behavioral findings that aren't otherwise captured.
- **When NOT to apply:** abandoned exploratory branches with no committed discoveries; worktrees whose findings are already fully captured in the inventory doc + skill files.
- **Cleanup:** when the upstream block clears and the migration is either revived or definitively rejected, remove the worktrees via `git worktree remove` + `git branch -D` once their value has been extracted into a real merged commit.
- **Cross-references:** P-2 parked worktrees (described in preceding V3 entry).
- **Severity:** LOW — workflow convention; no code consequence.

### ActiveMeetingShareViewModel.reload() — concurrency-test gap

- **What:** `ActiveMeetingShareViewModel.reload()` (introduced in B1.4 commit `f018a71`) performs an atomic two-fetcher pull (summary + sentences) and follows the established Phase-2 trio pattern with `.task(id:)`-driven last-query-wins serialization. The VM's doc-comment names the trio-pattern scheduling assumption and cites `TranscriptSplitScreenViewModelTests.viewModel_rapidSentencesDidUpdate_lastReloadWins` as covering it. That cited test enforces last-query-wins on a SINGLE-fetcher reload of a sibling VM; it does NOT exercise the new VM's TWO-fetcher atomic-snapshot semantics under concurrent reload.
- **Why V3-worthy (CLAUDE.md "Concurrency design discipline"):** the rule says "If no real violation test exists yet, document the gap explicitly AND log a V3 entry with a concrete trigger." The doc-comment satisfies the "document the gap" half but no V3 entry existed for the trigger condition. This entry closes that.
- **Why deferred:** today the trigger surface is essentially unreachable — `.task(id: activeShareIdentity())` keys on the phase's meetingID, which doesn't change while the meeting is `.ended`. Concurrent reloads for the same meeting cannot happen through any current UI gesture. The test gap is real but bounded.
- **Concrete trigger to fire this entry:** any new wiring that invokes `ActiveMeetingShareViewModel.reload()` while a previous reload is in-flight WITHOUT `.task(id:)` cancellation as the serializing layer. Concrete examples:
  1. Adding a user-initiated pull-to-refresh on the active view that calls `reload()` directly
  2. Wiring `MeetingSession.sentencesDidUpdate` to bump the VM's `refreshTrigger` while `.ended` (today `.ended` has no sentence ingress, but a future "edit after end" path would change this)
  3. Adding a "retry after error" affordance that calls `reload()` on tap
- **Action when triggered:** add a bespoke two-fetcher race test. Suggested shape: `viewModel_concurrentReloads_atomicSnapshotPreserved` — fire two reloads concurrently against fetchers with mismatched delays, assert the final `snapshot` reflects exactly one fetcher's result-pair (never a torn pair). Drop the `[weak self]` capture in the closure-injected init and ensure no leak under concurrent invocation.
- **Cost when triggered:** ~30-45 min including the test seam if a new closure-injection variant is needed.
- **Cross-references:** B1.4 commit `f018a71` (`ActiveMeetingShareViewModel.swift:46-64` for the doc-comment + assumption naming); CLAUDE.md § "Concurrency design discipline".
- **Severity:** LOW — gap is documented honestly in the VM's doc-comment; bounded reachability under current code.

## Post-B1.4 follow-ups

Five entries surfaced during the B1.4 dispatch (commit `f018a71`) and the three-reviewer gate but kept out of the merge per scope discipline. All bundle naturally with the pre-MVP-1 hardening sprint or with V3 `b851dad` (LFM2 upstream-block clearance).

### Post-B1.4: post-LFM2 smoke verification of Context A toolbar Share visibility

- **What:** B1.4 wired the active-view toolbar `ShareLink` and verified static visibility through unit tests + simulator screenshots, but reaching `phase == .ended` from a real meeting capture requires LFM2 (upstream-blocked per V3 `b851dad`). Smoke verification of the toolbar item ACTUALLY appearing in a real end-to-meeting flow is deferred until LFM2 unblocks.
- **Concrete trigger:** V3 `b851dad` LFM2 upstream block clears (Liquid AI ships an XCFramework fix per V3 "LEAP SDK v0.10.x migration — upstream-blocked").
- **Action when triggered:** boot iPhone 17 Pro Max simulator, perform a real meeting → STOP → confirm undo-window ends → confirm Share toolbar icon appears in the top-trailing slot when there is ≥1 sentence, AND does NOT appear when sentenceCount == 0.
- **Cost when triggered:** ~5 min manual smoke (after LFM2 is back).

### Post-B1.4: live-tap verification that ShareLink raises the iOS share sheet

- **What:** Distinct from the visibility smoke above. The load-bearing question the B1.4 dispatch couldn't answer: does tapping the new Share toolbar button actually raise the iOS share sheet with a transcript file attached? The SwiftUI `ShareLink(item: URL)` shape is identical to the working `MeetingDetailView` Context B reference, so this is high-confidence-but-unverified.
- **Concrete trigger:** V3 `b851dad` LFM2 upstream block clears AND the visibility-smoke entry above passes.
- **Action when triggered:** at the simulator, after confirming the toolbar Share icon is visible, tap it. Confirm iOS share sheet appears with the transcript Markdown file attached and correctly named per `TranscriptExporter.makeFilename`. AirDrop and Mail at minimum should be in the share destinations list.
- **Cost when triggered:** ~5 min manual smoke. Bundle with the visibility-smoke entry.

### Post-B1.4: MeetingStore.fetchSummary(meetingID:) single-row primitive

- **What:** `ActiveMeetingShareViewModel` resolves the meeting summary via `MeetingStore.fetchAllUnfiltered() + Swift-side filter`. The store has no single-row `fetchSummary(meetingID:)` primitive. The VM's doc-comment captures this as a post-MVP optimization candidate. Adjacent friction: `MeetingSummary` has no public memberwise init, so test fixtures construct summaries via in-memory `ModelContainer` round-trip with a discarded-`id` parameter (`ActiveMeetingShareViewModelTests.swift` `makeSummary` helper).
- **Concrete trigger to fire:** any of (a) a second caller other than B1.4 needs the same fetch-summary-by-id shape, (b) meeting count grows past ~100 (where full-fetch + filter becomes a measurable SwiftData read cost), (c) a future test needs deterministic-ID `MeetingSummary` construction at scale and the round-trip helper becomes unwieldy.
- **Action when triggered:** add `func fetchSummary(meetingID: PersistentIdentifier) async throws -> MeetingSummary?` to `MeetingStore` using the V3-blessed `FetchDescriptor` + `#Predicate` pattern (precedent: `MeetingStore.fetchSentences`). Optionally add a test-only memberwise `MeetingSummary.init(id:title:startedAt:endedAt:sentenceCount:firstMatchSnippet:)` behind `#if DEBUG` so test fixtures don't need ModelContainer round-trips.
- **Cost when triggered:** ~20-30 min including the V3-blessed predicate test and the test-helper migration.
- **Cross-references:** B1.4 commit `f018a71`; V3 lookup-primitive entry (`6023f2a`).
- **Severity:** LOW.

### Post-B1.4: ActiveMeetingShareViewModel per-render re-derivation flicker on `.ended → .ended` transitions

- **What:** `ContentView.makeShareModel()` re-derives `ActiveMeetingShareViewModel` on every body re-evaluation (matches the D9a `transcriptModel` pattern). `.task(id: activeShareIdentity())` keys on the phase's meetingID, so the reload task only re-fires on identifier change — bounding the fetch storm. However, between body re-eval and `.task(id:)` re-firing, the new VM's `snapshot` is briefly `nil`, which would hide the toolbar item momentarily.
- **Why it's bounded today:** `.ended`'s `endedAt` is frozen at `finalizeStop` time and the phase tuple doesn't mutate until the next meeting starts. So the body shouldn't re-evaluate the `.ended` branch in a way that destroys + recreates the VM.
- **Concrete trigger:** if `.ended`'s associated values ever become mutable post-`finalizeStop` (e.g., a future "amend transcript" feature that updates `endedAt`), OR if a user reports the Share icon flickering during the post-stop window, OR if a UI-screenshot regression test catches the flicker.
- **Action when triggered:** hoist VM ownership above the re-render boundary — e.g., own the `ActiveMeetingShareViewModel` in `AppBootstrapper` keyed by meetingID, with `ContentView` reading it as `@State` / `@Bindable`. Or, simpler: gate the toolbar item on `snapshot != nil` AND a cached-prior-snapshot fallback so the icon doesn't blink during the transient `nil` window.
- **Cost when triggered:** ~30-60 min depending on which mitigation. Hoisting ownership is invasive; the cached-prior-snapshot fallback is a single-line VM addition.
- **Cross-references:** B1.4 commit `f018a71` (`ContentView.swift:151-201`).
- **Severity:** LOW.

### Post-B1.4: ContentView.activeMeetingExportURL — per-render synthesis cost

- **What:** `ContentView.activeMeetingExportURL(snapshot:)` calls `TranscriptExporter.writeTemporaryFile(...)` synchronously on the calling thread, matching `MeetingDetailView.exportURL`'s pattern. The function runs on every toolbar re-evaluation. For MVP-1 transcript sizes (30-60 KB) this is fine; the `TranscriptExporter` type-level doc already acknowledges the synchronous-write scheduling assumption.
- **Concrete trigger:** if the active-view toolbar starts re-rendering at high frequency (e.g., a future per-second timer-driven re-render pushes through the toolbar context, which is NOT the case today — the badge `TimelineView` is scoped to `MeetingControlsView` only). Alternative trigger: transcript sizes grow past ~500 KB (would correspond to a multi-hour meeting with dense translation).
- **Action when triggered:** cache the export URL keyed by `(meetingID, sentencesCount)` in `ActiveMeetingShareViewModel` so the file is written once per snapshot and reused on subsequent re-renders. Identical pattern to a future cache in `MeetingDetailView.exportURL`.
- **Cost when triggered:** ~20 min including the cache + a test that asserts the file path is stable across renders for the same snapshot.
- **Cross-references:** B1.4 commit `f018a71`; `TranscriptExporter.swift` type-level doc.
- **Severity:** LOW.

## Post-reconciliation findings (2026-05-25)

Seven entries surfaced during the 2026-05-25 docs reconciliation pass (verification of shipped-vs-claimed state against live primary sources) and the daily briefing. The schema-registration P0 itself is tracked as **B1.6** in `docs/PRE_MVP1_REVIEW.md` Bucket 1, not here; these are the adjacent process gaps, the open product question, and the B1.1 re-evaluation lead.

### Pause spec-vs-code divergence — Decision #7 vs implementation

- **What:** Decision #7 (`docs/GROUP_D_UI_DECISIONS.md:92–94`) specs PAUSE as "temporarily halts audio capture (Whisper stops receiving frames)." The actual implementation (`MeetingCoordinator.swift:67–73`, `pauseMeeting` `:187–189`) delegates only to `session.pause()` — the audio engine keeps capturing, Whisper keeps transcribing, and completed sentences keep persisting through pause (`MeetingSession.process` `:512–521`). The doc-comment at `MeetingSessionPhase.swift:24` says "audio capture is halted" — the opposite of the code. Pause is functionally cosmetic: it freezes the badge timer and swaps the button label.
- **Why this is V3 and not immediately actionable:** open product question — which contract is correct, not a bug with one right answer.
- **Trigger to revisit:** before any AI-summary, battery-profiling, or pause-related feature work dispatches. Must be locked before downstream work depends on pause semantics.
- **Two options (require user decision):**
  - **Option A — Honor Decision #7.** Add `pause()` / `resume()` to the `AudioCapturing` protocol; stop the mic + Whisper during pause. Better battery on long pauses (e.g., 15-min coffee breaks). ~1–2h effort.
  - **Option B — Amend Decision #7.** Accept "pause = UI-cosmetic, capture continues" as the real contract and fix the stale `MeetingSessionPhase.swift:24` doc-comment to match. ~10 min effort. Battery cost remains real but bounded.
- **Severity:** MED — product correctness gap.

### Schema-registration test gap — production container path exercised by no test

- **What:** Every persistence test injects its own `ModelContainer` with the correct schema (`Meeting` + `Sentence`). The production-container construction at `ArigatoAIApp.swift:41` + `AppBootstrapper.swift:598` is unreached by any test. This is why **B1.6** (the `Schema([Item.self])` mismatch) was not caught earlier.
- **Trigger to revisit:** bundle with the B1.6 fix. The B1.6 dispatch must add a production-container test.
- **Action when triggered:** add `AppBootstrapperTests.productionContainer_registersMeetingAndSentence` — instantiate `AppBootstrapper` with default init, await `meetingStore` publication, assert the resolved container's schema includes `Meeting` + `Sentence` entities.
- **Severity:** MED — process gap that allowed the P0.

### Item.swift scaffold removal — Phase 6 scope says replace, never removed

- **What:** `ArigatoAI/Item.swift` is the default Xcode new-project scaffold. ROADMAP Phase 6 scope says it "replaces the default Item.swift scaffold," but the file remains in production sources and is the only entity registered in the production SwiftData schema (`ArigatoAIApp.swift:41`).
- **Trigger to revisit:** bundle with the B1.6 fix.
- **Action when triggered:** delete `Item.swift` after the B1.6 schema correction lands. Verify no references remain via grep.
- **Severity:** LOW — cleanup.

### leap-sdk v0.10.x migration path — re-evaluate B1.1 after issue #5 closes

- **What:** When `Liquid4All/leap-sdk` issue #5 closes (a fixed XCFramework ships) OR the project commits to the workaround below, resume the v0.10.x migration. **This is a code rewrite of the LFM2 integration layer, not a version bump:** the v0.10.x Swift API differs fundamentally from the pinned v0.9.4 — `ModelDownloader.loadModel(modelName:, quantizationType:)` / `loadSimpleModel(model: ModelSource(…))` → `runner.createConversation(…)`, vs v0.9.4's `Leap.load(options:)` → `Conversation(modelRunner:history:)`. Verified live against docs.liquid.ai 2026-05-25 (via the `liquid-docs` MCP).
- **Correction (2026-05-25):** an earlier draft of this entry claimed "the unified-repo path has not been attempted" and that docs.liquid.ai "403s — needs a human visit" — **both false.** The parked P-2 worktrees ARE the `leap-sdk` (unified-repo) attempts at v0.10.5/v0.10.6 (see the canonical block record "LEAP SDK v0.10.x migration — upstream-blocked (P-2 attempt closed)" above, and `PHASE_5_B1_1_MIGRATION_INVENTORY.md:4,49,169`), and docs.liquid.ai is fully fetchable (live-verified 2026-05-25 + reachable via the `liquid-docs` MCP). This entry therefore does NOT duplicate the block record — it tracks the *resumption* decision only.
- **Affected-version nuance:** issue #5 reports v0.10.6+ (v0.10.6, v0.10.7); the project's internal `otool -L` evidence also implicates v0.10.5 (`PHASE_5_B1_1_MIGRATION_INVENTORY.md:305,312`).
- **Workaround option (self-unblock without waiting on upstream):** add an `install_name_tool -change` build phase that rewrites the broken `@rpath/…framework/…` load command in `libinference_engine.dylib` to the plain-dylib form actually shipped. This lets the v0.10.x migration proceed before upstream fixes packaging; verify the rewritten install name with `otool -L`. Bounded by the +30-day cadence in "Issue #5 escalation cadence" below.
- **Trigger to revisit:** after B1.6 + Item.swift cleanup land (persistence functional for smoke-testing) AND issue #5 closes, or the +30-day escalation cadence forces the workaround decision.
- **Cross-references:** issue #5 (https://github.com/Liquid4All/leap-sdk/issues/5); "LEAP SDK v0.10.x migration — upstream-blocked (P-2 attempt closed)" (canonical block record — not duplicated here); "Issue #5 escalation cadence"; "Liquid Docs MCP — installed". No project memory on the LEAP SDK tag currently exists; create one pinning the channel reality (leap-ios v0.9.4 pin; leap-sdk v0.10.x is the live channel) when B1.1 is re-attempted.
- **Severity:** HIGH — B1.1 is the only remaining MVP-1 blocker once B1.6 ships.

### Issue #5 escalation cadence

- **What:** `Liquid4All/leap-sdk` issue #5 ("[iOS] v0.10.6+ Launch Crash: Broken @rpath dependency…") is OPEN, filed by the project (OnigiriMerchant) 2026-05-20, with **zero maintainer engagement** as of 2026-05-25 (no assignees/labels/PRs/comments — live-verified).
- **Cadence triggers:**
  - **+14 days (2026-06-03):** if still no maintainer response, escalate — comment on the issue, post in the Liquid AI Discord, and/or @-mention on social.
  - **+30 days (2026-06-19):** if still silent, commit to a path — either land the `install_name_tool -change` build-phase workaround (self-unblock; see the migration-path entry above) OR formally adopt a permanent v0.9.4 plan and close the v0.10.x migration arc.
- **Cross-references:** issue #5; "LEAP SDK v0.10.x migration — upstream-blocked (P-2 attempt closed)"; "leap-sdk v0.10.x migration path — re-evaluate B1.1 after issue #5 closes".
- **Severity:** MED — B1.1 is the last MVP-1 blocker; this bounds the open-ended wait on upstream.

### Liquid Docs MCP — installed (live SDK-docs channel)

- **What:** Liquid AI hosts a public MCP server at `https://docs.liquid.ai/mcp` (Mintlify-backed; tools `search_liquid_docs` + `query_docs_filesystem_liquid_docs`), giving Claude Code live, current access to Liquid AI docs + OpenAPI specs.
- **Status:** ✅ INSTALLED 2026-05-25 at project-local scope (in `~/.claude.json` under this project; `claude mcp add --transport http liquid-docs https://docs.liquid.ai/mcp`). Verified ✓ Connected via `claude mcp list` and a live `tools/call`. **MCP tools activate on the next Claude Code session restart** (servers load at startup).
- **Why it matters:** prevents the SDK-doc staleness that produced the phantom-`v0.10.4.3` and "v0.10.x doesn't exist" errors — future SDK-API questions resolve against live docs, not training data. Codified as a rule in CLAUDE.md "External dependency configuration".
- **Optional follow-ups:** promote to project scope (`.mcp.json`, git-tracked) if the team wants it shared/reproducible across clones. The equivalent Apple-docs channel — the `xcode` MCP's `DocumentationSearch` — is already wired.
- **Severity:** LOW — process improvement, done.

### Banner the now-false "v0.10.x doesn't exist" assertions in the PHASE_5 research docs

- **What:** `docs/PHASE_5_DOC_RESEARCH.md` (2026-05-12) and `docs/PHASE_5_B1_1_PRE_FLIGHT.md` (2026-05-17) assert "v0.10.x does not exist / v0.9.4 is latest / repo is `leap-ios`." Live sources — and the project's own `PHASE_5_B1_1_MIGRATION_INVENTORY.md` (2026-05-18) — prove these false: `Liquid4All/leap-sdk` v0.10.x exists, v0.10.7 is current. These are point-in-time research artifacts the team self-corrected, but they remain in the tree asserting a now-false repo/version reality.
- **Action when triggered:** add a dated banner at the top of each file, e.g. *"⚠️ Superseded 2026-05-18 by PHASE_5_B1_1_MIGRATION_INVENTORY.md — the 'v0.10.x does not exist / v0.9.4 is latest' conclusions below were drawn against the archived leap-ios repo and are FALSE. Current SDK is Liquid4All/leap-sdk v0.10.7. Retained for historical context."*
- **Why deferred (not done in the 2026-05-25 reconciliation pass):** those two files are outside that pass's 5-file scope (ROADMAP, CURRENT_STATE, PRE_MVP1_REVIEW, V3_BACKLOG, CLAUDE.md).
- **Severity:** LOW — discoverability; prevents future sessions tripping on the stale assertions.

## Post-MVP-1 portfolio polish

### End-of-project GitHub cleanup for portfolio

- **What:** Treat the repo as a portfolio artifact after MVP-1 ships and stabilizes. Scope:
  1. **README rewrite** — top-level problem statement (on-device JA↔EN meeting translation for personal use), solution narrative, architecture diagram (audio → WhisperKit → LanguageRouter → LFM2 → SwiftData → SwiftUI), demo section (GIF or short video of a real meeting capture), tech-stack badges (Swift 6, SwiftUI, SwiftData, WhisperKit, LEAP SDK, Apple Foundation Models, Anthropic API). Anchor the narrative on the "on-device, no telemetry, no cloud sync" privacy promise.
  2. **Repo hygiene** — delete merged feature branches, prune stale docs (the larger `PHASE_*_HANDOFF.md` and `*_PRE_FLIGHT.md` docs probably want to move under `docs/archive/` rather than stay top-level in `docs/`), evaluate whether the commit history is salvageable for narrative or whether a separate "story" doc is the better artifact. The checkpoint-commit chain pattern reads as noise to outside viewers — consider whether the post-MVP-1 main is best presented as-is or via squashed feature commits on a dedicated `portfolio` orphan branch.
  3. **Pinned screenshots/GIFs** — add a `docs/media/` directory with curated captures: split-screen view during a real meeting, history view, post-meeting transcript export, onboarding flow. Light + dark mode each.
  4. **LICENSE check** — confirm an OSS license is present (or deliberately omitted with explanation); verify third-party license compatibility (WhisperKit Apache-2.0, LFM2 model license, LEAP SDK terms). Add a `THIRD_PARTY_LICENSES.md` if any of those impose attribution requirements we're not already meeting.
  5. **"Built with Claude" attribution** — visible README badge + a short note acknowledging the citizen-dev workflow (Claude.ai strategic planning + Claude Code implementation, multi-subagent pipeline). Optional but matches the project's actual story.
  6. **Write-up link** — if a separate write-up is produced (blog post, Substack, internal doc), link it from the README.
- **Why deferred:** anything done before MVP-1 ships is premature; the repo's current shape is structured around active development (long handoff docs, checkpoint commits, V3 backlog), which is the right shape for now and the wrong shape for a portfolio first-impression.
- **Concrete trigger:** MVP-1 has shipped (V3 `b851dad` cleared, all pre-MVP-1 hardening sprint entries closed) AND ~2-4 weeks of real personal-use stabilization has passed — long enough to have either real meeting demo footage or a definitive "this is the use I get out of it" narrative.
- **Action when triggered:** bundle as a single ~2-3 hour weekend session. Order: (1) README rewrite first (forces the narrative decisions that drive everything else), (2) media capture (depends on README structure), (3) hygiene + license, (4) attribution + write-up link last.
- **Cost when triggered:** ~2-3 hours total. README is the biggest chunk; the rest is mechanical.
- **Cross-references:** none yet — this entry will accrue cross-references as MVP-1 ships and the portfolio-shape question crystallizes.
- **Severity:** LOW (portfolio polish, not functional). The repo as-is is fine for a private personal project; this is upgrade work for whenever the repo becomes externally visible.
