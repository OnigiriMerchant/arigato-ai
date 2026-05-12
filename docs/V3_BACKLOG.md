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

**What:** Group D end-of-group gate ui-review surfaced 8 visual concerns. Concern 6 (duplicate "listening…" hint) was fixed pre-push (commit `3b7c311`, locked by D4-T-concern6). The remaining 7 concerns are deferred to Phase 7 polish:

1. **`Color.green` warmup-loaded fallback** (`TranscriptLiveView.swift:349`) — no "ready" semantic token in `DesignTokens.swift` yet. Phase 7 should re-token. Verify hue does not clash with `recordingActive` red.

2. **Failed-state error text + dot both render in `Color.recordingActive`** (`TranscriptLiveView.swift:141`) — two adjacent red elements may overload the chrome region and compete with captions for attention. Suggest error text uses `.secondary` foreground; let the dot alone carry the semantic-error color.

3. **Footer placement under home indicator at large Dynamic Type** (`TranscriptLiveView.swift:80–82`) — at `.accessibility3` and above, "Audio never leaves your iPhone." footer may push under the home indicator on iPhone 17 Pro Max. Verify and adjust safe-area insets.

4. **List rows edge-to-edge vs chrome 20pt inset → row badges misalign with chrome badge** (`TranscriptLiveView.swift:156–164`) — list does not apply horizontal padding while chrome and footer are inset 20pt. Right-edge JA/EN row badges do not line up with the chrome's JA/EN badge. Add matching horizontal padding to list rows.

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

### LFM2 cache strategy — revisit if cross-meeting hit rate proves valuable

- **What:** Phase 5 ships with in-memory only cache (`LiquidCacheOptions` in-memory). Strategic walkthrough chose this over persistent on-disk because: (a) LFM2's prompt cache is inference-acceleration via KV-state, not translation-memory across sessions — cross-meeting hit rate likely near zero; (b) persistent cache in Documents folder backs up to iCloud by default, conflicting with CLAUDE.md "no cloud sync" privacy stance; (c) MVP discipline prefers simplest design that delivers value.

  If real meeting data shows the cache assumption was wrong — i.e., within-meeting hit rate is high enough to suggest cross-meeting benefit would be material AND a way to handle iCloud-backup exclusion is identified — revisit. Liquid AI / Liquid SDK may also evolve the cache primitive in a future version.
- **Trigger to revisit:** After local-only diagnostics ships (see preceding entry) AND 5+ real meetings show within-meeting cache hit rate >50%. OR if Liquid SDK introduces a translation-memory layer in a future version. OR if CLAUDE.md privacy stance evolves.
- **Cost estimate to flip to persistent:** ~2 hours. Swap `LiquidCacheOptions` to disk path, add iCloud backup exclusion attribute on cache directory, add "Clear translation cache" button in Settings, codify size cap and eviction policy.

---

## Workflow risks

### Xcode auto-update interrupts active feature work
- **What:** macOS auto-installed Xcode 26.5 (Build 17F42) mid-Phase-5-kickoff on 2026-05-12. The 26.5 component installer is modal with no skip/close affordance — Apple forces the platform support download. Builds blocked until iOS 26.5 platform installed. ~30 min interruption between the toolchain bump being detected and 125/125 green being re-verified.
- **Why deferred:** not a fixable issue per se — Apple controls Xcode update cadence. Worth recording the pattern so the next occurrence is faster to resolve.
- **Mitigation options when revisited:** (a) disable Xcode auto-updates in System Settings → General → Software Update → Automatic Updates; (b) use `xcodes` CLI or `xcode-select` to pin a specific Xcode version per project; (c) accept Apple's cadence and treat platform-install interruptions as a known ~30-min tax.
- **Trigger to revisit:** next time an Xcode auto-update blocks active work, OR if the project moves to a CI/CD setup where toolchain pinning becomes load-bearing.
- **Bonus item to evaluate when revisited:** whether to create a fresh iPhone 17 Pro Max sim on iOS 26.5 runtime. Today the existing sim is locked to iOS 26.4 and `useLatestOS: true` would pick 26.5 if a 26.5 sim existed. For Phase 5, iOS 26.4 sim is correct because it matches the deployment target. Reassess at Phase 7 or when deployment target bumps.

---

## Documentation hygiene

### `.claude/skills/leap-sdk/SKILL.md` — reconcile phantom v0.10.4.3 framing
- **What:** SKILL.md currently contains phantom-version claims discovered during the Phase 5 kickoff version-pin cleanup pass (2026-05-12). Line 9: "Minimum target version: v0.10.4.3 (released 2026-05-07)" — the version tag does not exist in the public `Liquid4All/leap-ios` repo, and the release date is unverified. Line 11: "Avoid the older `KotlinUInt` wrapping pattern seen in pre-v0.10.4.3 tutorials" — same phantom-version premise.
- **Why deferred:** not a simple string substitution. The v0.10.4.3 framing is load-bearing for the skill's guidance — the entire "Recent SDK changes (May 2026)" section (and possibly the `KotlinUInt` advice) is built on the assumption that a version newer than v0.9.4 exists with specific API improvements. Without verified evidence of what those changes actually are (or whether they exist at all), substituting v0.10.4.3 → v0.9.4 would silently propagate stale or fabricated guidance. The fix requires deciding what the file should actually say after verifying current LEAP SDK API surface against v0.9.4 source tree.
- **Action when revisited:** (a) read `.claude/skills/leap-sdk/SKILL.md` end-to-end; (b) for every claim tied to v0.10.4.3, verify against v0.9.4 source tree + docs.liquid.ai; (c) rewrite or delete unverifiable claims rather than substitute the version string; (d) cross-reference `docs/PHASE_5_DOC_RESEARCH.md` for what's known to be true in v0.9.4. Likely a 30–60 min focused rewrite, not a one-line edit.
- **Trigger to revisit:** next time the LEAP / Liquid AI skill is invoked (e.g., during Group B SPM-add work or any LFM2 debugging), OR before Phase 6 kickoff, whichever comes first.
- **Cost estimate:** ~30–60 min for the rewrite, plus any incidental @doc-researcher pre-flight if claims are uncertain.
