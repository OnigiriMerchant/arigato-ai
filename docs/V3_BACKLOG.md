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

---

Updated: May 7 2026

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
