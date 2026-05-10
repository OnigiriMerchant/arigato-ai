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

### Subagent MCP tool inheritance — known Claude Code limitation
- **What:** Custom subagents in .claude/agents/ cannot reliably access MCP tools from frontmatter declarations or project-scope MCP servers. Affects XcodeBuildMCP and any other MCP server. Verified during Phase 4 Group A (case-mismatch and fully-qualified-name fixes both failed). Multiple GitHub issues open: #25200, #13898, #13605.
- **Why deferred:** Claude Code platform bug, not a project-side fix. Subagents falling back to raw xcodebuild via Bash is the documented community workaround. CLAUDE.md updated to reflect this.
- **Trigger to revisit:** When Anthropic ships a Claude Code release that fixes the MCP-inheritance bug. Watch the linked issues for resolution. Test subagent MCP access with `/agents` after each major Claude Code update.
- **Optional spike:** Try moving XcodeBuildMCP from project scope to user scope (`-s user` flag) — some reports suggest user-scope MCPs propagate to subagents better. ~5 min test, low risk.
- **No action required for current work.** Group B will proceed with subagents using Bash + raw xcodebuild for build verification; main session uses XcodeBuildMCP-wrapped tools.

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
