# Name & Trademark — "Arigato AI"

> **Status:** Advisory reference. **Not legal advice.** This is a quick public-source check
> (focused on Apple App Store name availability + Japan), not a formal clearance search. The only
> authoritative answer comes from a direct USPTO/JPO search and a trademark attorney. Several
> official databases (USPTO TSDR, arigatoai.com) blocked automated access during the check, so a
> few specifics below are explicitly flagged **unverified**.
>
> _Last checked: 2026-06-06._

## TL;DR

The name **"Arigato AI" is _not clearly open_.** You can *probably ship* under it (reserve the
App Store name string now), but you likely **cannot fully _own_** it — an existing **"ARIGATO AI"
does the exact same Japanese↔English translation**, and "Arigato" is a crowded software brand
while "AI" is unprotectable. The dominant risk is **prior use**, not the word "arigato" being
generic.

- **Personal-first launch:** practically low risk.
- **App Store release / registration:** treat the name as **contested** — reserve the string,
  accept residual risk, or pick a more distinctive name you can actually defend.

---

## 1. Can I use "Arigato AI" on the Apple App Store?

Two **separate** gates — they're often confused:

### Gate 1 — the App Store *name string* (easy; act now)
- Apple requires every app name to be **unique** on the App Store, allocated **first-come** in
  App Store Connect.
- No iOS app is currently named **exactly** "Arigato AI", so the string looks **free today**.
- ⚠️ Someone else could claim it first. You can **reserve it now without a finished app** — create
  the app record in App Store Connect. Requires Apple Developer Program membership ($99/yr).
- **This is the single most effective concrete step.** (User-side action — Apple account.)

### Gate 2 — trademark rights (the real risk)
- Reserving the string in App Store Connect is **not** owning the name.
- App Review (guidelines 5.2.x) makes you **attest you have rights** to the name, and a trademark
  holder can later force removal via Apple's dispute process.
- Your exposure: the existing **[arigatoai.com / "ARIGATO AI" (Heysho)](https://arigatoai.com/en/agent/translation.html)**
  that already offers JA↔EN translation, plus unverified **Arigato Machine Inc.** USPTO filings.
- **Personal use / small launch:** low practical risk (many indie apps ship on unregistered names).
- **Owning the name:** uncertain and weak — "AI" gets disclaimed and "Arigato" is crowded, and a
  prior identical-field user makes a clean registration genuinely doubtful.

---

## 2. Existing "Arigato" names (prior-use findings)

Trademark risk is highest when **name *and* field of use both overlap**. Sorted by overlap:

| Name | What it is | Field overlap | Source |
|---|---|---|---|
| **ARIGATO AI / Heysho** | AI tool whose headline feature is **JA↔EN translation** — same name, same function | 🔴 **Direct** (identical name + field) | [arigatoai.com](https://arigatoai.com/en/agent/translation.html) |
| **Arigato App** (Arigato Cloud Services LLC) | AI e-commerce platform; owns the **arigato.ai** domain | 🟠 Different field, owns key domain | [arigato.ai](https://www.arigato.ai/en/) |
| **Arigato Automation** (Bonify / "Mr. Arigato") | Shopify workflow automation app | 🟡 Different field | [Shopify App Store](https://apps.shopify.com/mr-arigato-task-automator) |
| **Arigato Machine Inc.** | Holds ~3 USPTO trademark filings — **wording/classes unverified** | ⚠️ Unknown — needs direct USPTO check | [uspto.report](https://uspto.report/company/Arigato-Machine-Inc) |
| **Arigato: Academies & Classes** | Class-management app (live on the App Store) | 🟡 Different field | [App Store](https://apps.apple.com/us/app/arigato-academies-classes/id6463771189) |

**Domains:** `arigato.ai` and `arigatoai.com` are both **taken** (by the two products above).

---

## 3. Japan (JPO) note

- "ありがとう / arigato" = "thank you", a common word. Japan (and the US) reject **generic/descriptive**
  marks — but "thank you" does **not describe** translation software, so in this field it reads as
  **suggestive / arbitrary → registrable in principle.** The word itself isn't the obstacle.
- The descriptive part is **"AI"**, which is routinely **disclaimed** (no exclusive rights to "AI").
  That leaves a mark resting effectively on **"ARIGATO"** — exactly where the prior users sit.
- **Conclusion:** the real obstacle in Japan (as in the US) is **prior use**, not genericness.

Source: [JPO — Outline of the Trademark System](https://www.jpo.go.jp/e/system/trademark/gaiyo/chizai08.html),
[Japan trademark overview (PatentPC)](https://patentpc.com/blog/a-deep-dive-into-japans-trademark-system-what-foreign-businesses-should-know).

---

## 4. Action checklist (prioritized)

1. **Reserve the App Store name now** — create the app record in App Store Connect to lock the
   "Arigato AI" string against other iOS developers (no finished app needed). *(Apple account.)*
2. **Decide own-vs-accept-risk:**
   - *Accept residual risk* (reasonable for a personal-first launch), **or**
   - *Secure it:* commission a **clearance search** and, if it comes back clean enough, file your
     own mark in **Class 9** (downloadable software) and/or **Class 42** (SaaS). *(Attorney + USPTO/JPO.)*
3. **If clearance looks bad / you want a defensible brand:** consider a **more distinctive coined
   name** — far easier to both clear and own than "Arigato + AI".

---

## 5. Repo IP protection (separate from the name)

**A license does not _protect_ your code — it _gives rights away_.**

- **Copyright is automatic.** You own the code the moment you write it — no license, registration,
  or notice required.
- **No license = "all rights reserved"** by default → your code is already at *maximum* legal
  restriction. An **OSS license (MIT/Apache/GPL) does the opposite** of protection: it grants
  strangers permission to copy and reuse.
- **But legal rights ≠ technical prevention.** A public repo can be viewed, cloned, and forked
  (GitHub ToS allows on-platform forking), and scraped/archived. **This repo has already been
  public — assume snapshots may exist.** Going private only stops *future* exposure.

**What actually protects each kind of IP:**

| Protecting | Real lever |
|---|---|
| Source code (stop copying) | **Make the repo private** — copyright already covers legal reuse |
| Signal "no reuse" while public | A **proprietary "All Rights Reserved"** notice + copyright headers (*not* an OSS license) |
| The **name** "Arigato AI" | **Trademark** (see above) — copyright/licenses don't cover names |
| Third-party parts (LFM2, WhisperKit, Geist) | Already permissive (Apache-2.0 / OFL-1.1); they don't force you to open-source your code |

**Showcasing while private** (private ≠ invisible):
1. **Invite specific people** as read-only collaborators (a friend, hackathon judges) — remove them
   after. Free GitHub allows unlimited collaborators on private repos.
2. **Show the running app** — TestFlight build, screen recording, or on-device demo. For a
   translator, the demo is the impressive part and exposes no IP.
3. **A separate public "showcase" repo / Devpost page** — README, screenshots, demo video,
   architecture write-up, a few non-core snippets; full source stays private.
4. **Temporarily flip public for a hackathon, then private again** — *highest exposure*; only if the
   rules require a public repo. Check the specific hackathon's rules first; prefer #1 if judges can
   be invited to a private repo.

---

### Sources
- App Store / product landscape: [arigatoai.com](https://arigatoai.com/en/agent/translation.html),
  [arigato.ai](https://www.arigato.ai/en/),
  [Arigato Automation (Shopify)](https://apps.shopify.com/mr-arigato-task-automator),
  [Arigato: Academies & Classes (App Store)](https://apps.apple.com/us/app/arigato-academies-classes/id6463771189)
- USPTO: [Arigato Machine Inc. (uspto.report)](https://uspto.report/company/Arigato-Machine-Inc),
  [USPTO trademark search](https://www.uspto.gov/trademarks/search),
  [TSDR](https://tsdr.uspto.gov/)
- Japan: [JPO trademark system](https://www.jpo.go.jp/e/system/trademark/gaiyo/chizai08.html)
