# Full-Day Workshop — Slide Audit (existing vs. needed)

Audit last updated: **2026-05-13** *(end of build session — 6 new decks landed)*. Compares everything in `labs-full-day/slides/` and the markdown source in `slide-updates/`, every per-scenario folder, and the new `kiro-iam-hardening/` lab against the **Formalized Outline** in the BSides Tampa planning Google Doc.

> **Authoritative running order: the Google Doc's "Formalized Outline w/ Links to Materials" table.** When this audit references a slot, the time and topic come from there.

> **Status legend in the running-order table below: ✅ deck built and in repo · 🚧 modify-only (deck exists, needs edits) · ❌ no deck yet · 🚫 explicitly out of scope.**

---

## 1. Authoritative running order (current state)

| Time | Topic | Speaker | Deck on disk | Status |
|---|---|---|---|---|
| 9:00–9:40 | Welcome and Introduction to IAM | Tara | `Lecture-layin-down-the-law.pptx` (23 slides) | 🚧 Solid base; needs the iam-recon enrichment from `slide-updates/lecture-1-iam-recon-intro.md` (5 new slides) |
| 9:40–10:00 | Lab Setup | Andrew | `Lecture-Lab-Setup-And-First-Scenario.pptx` (11 slides) | 🚧 Setup half is good; remove slide 11 (Scenario 1 intro now lives in its own deck) and rename to `Lab-Setup.pptx` |
| 10:00–10:15 | Scenario 1 — CreatePolicyVersion self-escalation | Tara | `Scenario-1-CreatePolicyVersion.pptx` (5 slides) | ✅ Built this session. Title: "Self-Service Admin." Real v1 → v2 transformation of `iamws-developer-tools-policy`. |
| 10:15–10:30 | Scenario 2 — Trust `:root` | Tara | `Scenario-2-AssumeRole-Root.pptx` (5 slides) | ✅ Built this session. Title: "The :root That Isn't." Pulls the actual trust policy + identity policy from `iamws-privileged-role.tf`. |
| 10:30–10:45 | Morning break | — | — | — |
| 10:45–11:15 | Lecture — Guardrails and Validation | Andrew | `Lecture-Fencin-the-Frontier.pptx` (20 slides) | 🚧 Concept slides exist; ~9 placeholder/blank slides need to be filled or deleted |
| 11:15–11:30 | Lab — Apply permissions boundaries and condition keys | Tara | None | ❌ **Need new deck.** Source: `apply-permissions-boundaries-and-condition-keys.md` (currently a single monolithic file covering Scenario 1 boundary + Scenario 2 condition key). This is where the S1 + S2 *defenses* live (per the locked decision that scenario decks are attack-only). |
| 11:30–12:00 | Lecture: Kiro + MCP | Andrew | `Kiro_for_Cloud_Security.pptx` (13 slides) | 🚧 Self-contained; **aspect ratio mismatch** (10×5.625 in vs 20×11.25 in for everything else). Resize, optionally add 1–2 transition slides bridging into the afternoon Kiro lab. |
| 12:00–1:00 | Lunch | — | — | — |
| 1:00–1:30 | Knowledge Refresh Game | Andrew | None | 🚫 **Out of scope** for this build effort (Andrew owns) |
| 1:30–2:00 | Lab — Kiro IAM Hardening | Andrew | `Lab-Kiro-IAM-Hardening.pptx` (6 slides) | ✅ Built this session. Title: "Specs Before Statements." Includes IaC + CloudFormation primer. |
| 2:00–2:30 | Scenario 3 — PassRole + EC2 | Tara | `Scenario-3-PassRole-EC2.pptx` (7 slides) | ✅ Built this session. Title: "Pass to Lambda, Land in EC2." Includes 2 concept slides (PassRole + EC2/IMDS); slide 3 lists all *three* PassRole gates (corrected from initial draft). |
| 2:30–2:45 | Afternoon break | — | — | — |
| 2:45–3:15 | Scenarios 4 + 5 — Lambda attacks | Tara | `Scenario-4-Lambda-UpdateFunctionCode.pptx` (6 slides) + `Scenario-5-Lambda-Secrets.pptx` (5 slides) | ✅ Built this session. S4 title: "Their Lambda, Your Code." S5 title: "Read-Only Isn't." Both decks revamped against the updated lab markdown (ChatGPT-overly-broad framing for S4, pen-test-finding framing for S5). |
| 3:15–3:30 | Lecture — IAM Spy and Provers | Andrew | None | ❌ **Need new deck.** Source: `slide-updates/lecture-2-additions.md`. **Two open TODOs in that file** must be answered first (see §5). |
| 3:30–4:30 | Flex / Game 2 | Andrew | None | 🚫 **Out of scope** for this build effort |
| 4:30–5:00 | Wrap up | Both | None | ❌ **Need new deck.** Cleanup commands, recap, feedback link, "where to go next." |

---

## 2. What's currently on disk

### 2.1 Slide decks in `labs-full-day/slides/`

| Deck | Slides | Aspect | Built/Modified |
|---|---|---|---|
| `Lecture-layin-down-the-law.pptx` | 23 | 20×11.25 in | Pre-existing |
| `Lecture-Lab-Setup-And-First-Scenario.pptx` | 11 | 20×11.25 in | Pre-existing |
| `Lecture-Fencin-the-Frontier.pptx` | 20 | 20×11.25 in | Pre-existing |
| `Kiro_for_Cloud_Security.pptx` | 13 | 10×5.625 in | Pre-existing |
| `Scenario-1-CreatePolicyVersion.pptx` | 5 | 20×11.25 in | **Built this session** |
| `Scenario-2-AssumeRole-Root.pptx` | 5 | 20×11.25 in | **Built this session** |
| `Scenario-3-PassRole-EC2.pptx` | 7 | 20×11.25 in | **Built this session** |
| `Scenario-4-Lambda-UpdateFunctionCode.pptx` | 6 | 20×11.25 in | **Built this session** |
| `Scenario-5-Lambda-Secrets.pptx` | 5 | 20×11.25 in | **Built this session** |
| `Lab-Kiro-IAM-Hardening.pptx` | 6 | 20×11.25 in | **Built this session** |

**10 decks total, 6 newly built this session.**

### 2.2 Locked design template (used for every new deck)

Captured here so future sessions can reproduce or extend the look/feel without re-deriving it.

- **Aspect:** 20×11.25 in (matches the Lecture 1 deck the others are seeded from)
- **Background:** dark gradient picture, inherited from `Lecture-layin-down-the-law.pptx`'s slide master
- **Title font:** Assistant Bold, ~58–66pt for slide titles, ~120–140pt for cover titles
- **Body font:** Assistant Bold, 22–30pt
- **Code font:** Consolas, 18–24pt
- **Semantic code colors:**
  - Default: `#CBD5E1` (slate)
  - Cyan `#22D3EE`: principals, identities, AWS service identifiers
  - Red `#F87171`: condition keys, dangerous bits, missing-gate callouts
  - Purple `#A78BFA`: scoped resources / ARNs
  - Orange `#FC6D26`: section accents, key terms
  - Green `#86EF AC`: hardened/safe values
- **Per-scenario template (locked):**
  1. Title — story-style headline, API name in subtitle
  2. The setup — real-world scenario in prose (lifted from the lab's own "real-world scenario" framing where one exists)
  3. The misconfiguration — real source-code JSON, side-by-side or v1→v2 where it makes sense; **never invented**
  4. *(scenarios 3+ only)* Concept slide(s) — PassRole + EC2 instance profile mechanics (S3), Lambda execution roles + Existing PassRole (S4); S1, S2, S5 have no concept slide
  5. Privilege escalation path — numbered beats + a single CLI command anchor + pathfinding.cloud diagram placeholder
  6. Similar API actions / patterns / surfaces — extends the lesson beyond the specific verb
- **Scope rule (locked):** Scenarios 1 + 2 are attack-only (defenses live in the 11:15 boundaries+conditions deck); Scenarios 3, 4, 5 include attack + defense in the same deck.
- **Speaker notes:** intentionally empty in every new deck; presenter prompts can come from the corresponding `attack.md` / `defense.md` "Demo bullets" sections in a future pass.

### 2.3 Slide source markdown

| File | Status | Destination |
|---|---|---|
| `slide-updates/lecture-1-iam-recon-intro.md` | Drafted, **not yet folded into a deck** | Lecture 1 (9:00 slot) |
| `slide-updates/lecture-2-additions.md` | Drafted, blocked on TODOs | Lecture — IAM Spy and Provers (3:15 slot) |
| `lab-setup-instructions.md` | Live lab text, partially in deck | Lab Setup deck (9:40 slot) |
| `warmup/instructions.md` | Live lab text, no slides | Could fold 1 slide into Lab Setup deck or leave as instructor screen-share |
| Each scenario's `intro-slide.md` + `attack.md` + `defense.md` | All built into scenario decks ✅ | Scenarios 1–5 (done) |
| `apply-permissions-boundaries-and-condition-keys.md` | Live lab text, **no slides yet** | 11:15 boundaries+conditions deck |
| `kiro-iam-hardening/instructions.md` + `intro-slide.md` | Built into deck ✅ | Kiro IAM Hardening lab deck (1:30 slot) |
| `Lab_-_Hardening_IAM_Policies_with_Kiro.docx.md` | Pulled from Drive, **superseded** | The Kiro lab folder is now the source of truth — this docx export is redundant and could be deleted |

---

## 3. What's left to build

In running order. **5 decks remain** (3 to build, 2 to modify); 2 game decks excluded as out-of-scope.

| # | Deck | Slot | Action | Status / blockers |
|---|---|---|---|---|
| 1 | `Lecture-layin-down-the-law.pptx` | 9:00 | **Modify** — fold in 5 enriched iam-recon slides from `slide-updates/lecture-1-iam-recon-intro.md` | Ready |
| 2 | `Lecture-Lab-Setup-And-First-Scenario.pptx` | 9:40 | **Modify** — rename to `Lab-Setup.pptx`; remove slide 11 (Scenario 1 intro now in its own deck); optionally add 1 warmup slide | Ready |
| 3 | `Lecture-Fencin-the-Frontier.pptx` | 10:45 | **Modify** — fill or delete the ~9 blank/placeholder slides | Ready |
| 4 | `Lab-Apply-Boundaries-and-Condition-Keys.pptx` | 11:15 | **NEW** — covers S1 boundary + S2 condition key remediations. Source: `apply-permissions-boundaries-and-condition-keys.md`. ~6–8 slides. | Ready |
| 5 | `Kiro_for_Cloud_Security.pptx` | 11:30 | **Modify** — resize from 10×5.625 in to 20×11.25 in to match the rest; optionally add 1–2 transition slides bridging into the 1:30 hardening lab | Ready (transition needs Andrew's input) |
| 6 | `Lecture-IAM-Spy-and-Provers.pptx` | 3:15 | **NEW** — source: `slide-updates/lecture-2-additions.md`. ~5–7 slides. | **Blocked** on the two TODOs in that file: confirm IAM Spy origin/repo + name the specific provers being recommended (Zelkova? Access Analyzer policy validation? CloudSplaining variants?) |
| 7 | `Workshop-Wrap-Up.pptx` | 4:30 | **NEW** — cleanup commands, recap, feedback link, "where to go next." ~4–5 slides. | Ready (needs a quick outline) |

**Net for the next session: 3 modifications + 3 new decks + 1 new deck blocked.**

---

## 4. Repo-hygiene fixes still outstanding

These don't block decks but are easy wins to tidy up:

1. **Rename `scenario-1b-create-policy-version copy/`** — still has the literal " copy" suffix from a Finder duplicate. Pick a canonical name (`scenario-1-create-policy-version/` would match the Google Doc's slot) and rename. The Scenario 1 deck already references the right policy names, so the rename doesn't break the deck.
1. **Decide the fate of the optional PutGroupPolicy scenario.** Still in the in-repo README index (where one exists) but not in the Google Doc, and no folder on disk. Either drop the reference or stub a folder.
1. **Split the monolithic `scenario-2-trust-policy-root.md`** into `attack.md` / `defense.md` / `cleanup.md` to match Scenarios 3–5's layout. Cosmetic; doesn't block the Scenario 2 deck.
1. **`Lab_-_Hardening_IAM_Policies_with_Kiro.docx.md`** at the labs-full-day root is now redundant — the Kiro lab folder under `kiro-iam-hardening/` is the authoritative source. Safe to delete or move to a `reference/` folder.
1. **Sparse speaker notes** in the new decks — the corresponding `attack.md` / `defense.md` "Demo bullets" sections migrate well into speaker notes for whoever ends up presenting.

---

## 5. Open questions to resolve before remaining work

Carrying forward the unresolved questions from the previous audit. Most blockers fall on either Andrew or a quick decision from you.

1. **Lecture 2 TODOs** *(blocks deck #6)* — confirm the IAM Spy origin/repo and the specific "provers" being recommended. Open in `slide-updates/lecture-2-additions.md`.
1. **Kiro overview deck transition slides** — Andrew's call whether the existing Kiro deck needs bridging slides into the afternoon hardening lab, or if it stays standalone.
1. **Visual template carryover for the remaining new decks** — the locked template (§2.2) has been working well; any reason to deviate for the boundaries+conditions or wrap-up decks? Default is to keep the same look.
1. **Wrap-up deck contents** — what specifically goes in the recap? Open list candidates: agenda recap from Lecture 1, three "what to do next" pointers (scan your own org with iam-recon, blog/Slack, where the lab repo lives), feedback/survey URL, instructor contact.

---

## 6. Session log — 2026-05-13

What landed in this session, in order, for context when picking back up:

1. **Audit drafted** comparing existing decks against the README day-at-a-glance.
1. **Google Doc fetched** (after connector reconnect) — Formalized Outline became authoritative running order; audit revised.
1. **Visual template inspected** in `Lecture-layin-down-the-law.pptx` — confirmed Assistant Bold titles, Consolas semantic-color code blocks, picture-background slide master.
1. **Per-scenario deck template locked** (5 slides default, 6–7 with concept slides for PassRole / Lambda).
1. **Scenario 1 — Self-Service Admin** built, then revised twice: (a) restructured slides 1–5 after concept critique, (b) replaced fabricated hardened-JSON column with real v1 → v2 transformation pulled from `iamws-policy-developer.tf`.
1. **Scenario 2 — The :root That Isn't** built, real trust policy + identity policy from `iamws-privileged-role.tf`.
1. **Scenario 3 — Pass to Lambda, Land in EC2** built; PassRole concept slide revised after fact-check (added the 3rd gate — role's trust policy `Principal` — alongside `Resource` and `iam:PassedToService`).
1. **Scenario 4 — Their Lambda, Your Code** built, then revamped against the updated lab markdown (ChatGPT-overly-broad-policy framing, diversity of privileged Lambdas).
1. **Scenario 5 — Read-Only Isn't** built against the updated lab markdown (one-of-the-most-common-pen-test-findings framing, outside-AWS blast radius). Pathfinding placeholder replaced with the actual leaked JSON since this isn't a privesc category.
1. **Kiro IAM Hardening lab deck — Specs Before Statements** built, then revised: added IaC + CloudFormation primer slide, removed easter-egg + "don't hunt for the reference template" callouts.
1. **AUDIT updated** *(this commit)*.
