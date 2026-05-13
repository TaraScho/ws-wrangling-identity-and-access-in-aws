# Polish prompt — copy/paste into a fresh Claude session

Convert the validated bullet outlines in `labs-full-day/` into polished participant-facing lab instructions. The bullets have been live-validated end-to-end against a real AWS account (see `labs-full-day/VALIDATION-LOG.md`); your job is presentation, not re-validation.

## Inputs

For each scenario in `labs-full-day/`:
- `intro-slide.md` — speaker bullets for the scenario intro slide. **Leave untouched.**
- `attack.md` — validated morning attack bullets (command sequences, expected outputs).
- `defense.md` — validated afternoon defense bullets.
- `cleanup.md` — validated revert steps.

Plus:
- `labs-full-day/VALIDATION-LOG.md` — the live validation results. Read the "Final summary" section to understand which commands work, which timing gotchas to preserve, and which iam-recon surface is the right one for each scenario.
- `labs-two-hour-workshop/lab-1-layin-down-the-law/exercises/exercise-{2..7}.md` — **style reference**. Match this structure (sections, voice, callout blocks, expected-output formatting).
- `labs-two-hour-workshop/lab-2-fencin-the-frontier/exercises/exercise-{1..6}.md` — style reference for defense flows.
- `.playwright-mcp/scenario-*.png` — screenshots from the validation pass. Reference where they add clarity (e.g., "Your graph should look like this"), but don't force one into every section.

## Deliverable per scenario

One polished `instructions.md` per scenario folder, plus a lightly-polished `cleanup.md`:

```
scenario-1-create-policy-version/
  intro-slide.md       ← unchanged
  instructions.md      ← NEW: polished participant doc (attack + defense + verify, one continuous narrative)
  cleanup.md           ← polished from the bullet version
  attack.md            ← keep as-is (validated bullets — source of truth)
  defense.md           ← keep as-is
```

Do **not** delete `attack.md` / `defense.md` — they remain the validated source. `instructions.md` is the participant-facing render.

## Section structure (match the 2-hour style, no padding)

Use these headings, in this order, for each scenario:

```markdown
## Scenario N: <attack name> — <one-line summary>

**Category:** <Self-Escalation | Principal Access | New PassRole | Existing PassRole | Credential Access>
**Starting Identity:** `iamws-<...>-user`
**Target:** <what the attacker reaches — crown jewels via X, secrets in Y, etc.>

**The Vulnerability:** <2-3 sentences, lifted/adapted from the 2-hour exercise>

**Real-world scenario:** <2-3 sentences, lifted/adapted from the 2-hour exercise>

### Part A: Identify with iam-recon

<recon commands from attack.md, with expected output blocks where the bullet shows them. Use ONLY the surface that the validation log confirms works for this scenario — do not show alternatives that don't fire. See "iam-recon surface per scenario" table below.>

### Part B: Understand the attack

<conceptual frame: category, root cause, impact, pathfinding.cloud link. Lift the bullet list from the 2-hour exercise's "Understand the Attack Category" section.>

### Part C: Exploit the vulnerability

<full command path from attack.md, broken into numbered steps with expected outputs. Match the 2-hour exercise's step style exactly: code block, then expected-output code block, then 1-line interpretation.>

**Pause here — your instructor will demo before moving on. In the afternoon we'll defend this attack.**

---

### Part D: Apply the defense

<defense commands from defense.md, broken into numbered steps. Include the IAM cache `sleep 60` (or `sleep 15` for Scenario 1) where the bullet has it, with the simple participant-facing explanation: "AWS IAM permission changes can take up to a minute to propagate — wait before re-testing.">

### Part E: Verify the remediation

<re-run the attack as the attacker user → confirm AccessDenied, confirm crown jewels still safe. Then the iam-recon or simulate-principal-policy verification command(s) per the table below.>

### What You Learned

<3-5 bullets synthesizing both halves. Lift from the 2-hour "What You Learned" sections of the relevant attack + defense exercises; consolidate without adding new content.>

### Cleanup

See `cleanup.md` for revert steps before moving to the next scenario.
```

## iam-recon surface per scenario (use the one that works — do NOT show alternatives that don't fire)

This is the most important content decision. The validator confirmed which iam-recon surface actually works for each scenario. Use only that one in Parts A and E. Do not call out the gaps — present the working command as THE answer.

| Scenario | Recon command (Part A) | Verification command (Part E) |
|---|---|---|
| 1 — CreatePolicyVersion | `iam-recon --account $ACCOUNT_ID pathfinding` (filter for `[iam-001]`) | AWS `simulate-principal-policy` (iam-recon doesn't reflect boundaries) |
| 2 — Trust `:root` | `iam-recon --account $ACCOUNT_ID argquery --preset privesc` (shows the STS edge) | `iam-recon --account $ACCOUNT_ID argquery --preset privesc` (STS edge gone) |
| 3 — PassRole + EC2 | `iam-recon --account $ACCOUNT_ID argquery --preset privesc` | `iam-recon --account $ACCOUNT_ID argquery --principal user/iamws-ci-runner-user --action iam:PassRole --resource 'arn:aws:iam::*:role/iamws-prod-deploy-role'` (returns DENY) |
| 4 — UpdateFunctionCode | `iam-recon --account $ACCOUNT_ID pathfinding` (filter for `[lambda-003]`/`[lambda-004]`) | `iam-recon --account $ACCOUNT_ID argquery --principal user/iamws-lambda-developer-user --action lambda:UpdateFunctionCode --resource <privileged-function-arn>` (returns DENY) |
| 5 — Env-var secrets | `iam-recon --account $ACCOUNT_ID argquery --principal user/iamws-secrets-reader-user --action lambda:GetFunctionConfiguration` (returns ALLOW) | AWS `aws lambda get-function-configuration` (now returns `SECRET_NAME` pointer only) + `argquery` showing attacker user denied on `secretsmanager:GetSecretValue` |
| Optional — PutGroupPolicy | `iam-recon --account $ACCOUNT_ID pathfinding` (filter for `[iam-011]`) | `iam-recon --account $ACCOUNT_ID argquery --principal user/iamws-group-admin-user --action iam:PutGroupPolicy --resource 'arn:aws:iam::*:group/iamws-dev-team'` (returns DENY) |

## Critical things to preserve from the validation pass

These are non-obvious things the validator confirmed are necessary. Do not drop them from the polished doc:

1. **Sleep waits.** Scenario 1 attack has `sleep 15` (IAM eventual consistency). Scenarios 4 and Optional defenses have `sleep 60` (IAM permission cache). All others have their timing already absorbed by command latency. **Keep all sleeps.** Frame them simply: "Wait ~60 seconds for IAM to propagate the policy change."
2. **Scenario 1 defense Step 0 reset** (v2 → v1 on `iamws-developer-tools-policy`) before applying the boundary. Without this, the attack's escalated policy stays default and the defense looks like it failed.
3. **Scenario optional defense Step 3 reset** (`delete-group-policy iamws-dev-team-escalated`) for the same reason.
4. **Scenario 3 Step 2 and Step 5** must run under `--profile taractf`, not the attacker user (the attacker user lacks `iam:GetPolicyVersion` and `ssm:DescribeInstanceInformation`).
5. **Scenario optional cleanup line** that calls `delete-group-policy` must run under `--profile taractf` (`SecureGroupAdmin` lacks `iam:DeleteGroupPolicy`).
6. **Scenario 3 SSM session** — `start-session` is interactive. Frame as: "In your terminal, start an SSM session to the instance and run the following commands inside the session." Don't try to scriptify it.
7. **Scenario 3 + Optional "Going further" note**: defenses only scope the user; the same-named role (`iamws-ci-runner-role`, `iamws-group-admin-role`) still has the original managed policy. Include a short "Going further: apply the same fix to the role" subsection in each — the validator caught this and it's a legitimate defense improvement.

## Open TODOs to preserve as visible markers

These remain open; mark them clearly so they don't get lost:

- **Scenario 2 defense, Andrew's Kiro lab**: insert `> 🚧 **Kiro lab integration point — see Andrew.** A guided Kiro walkthrough for authoring the hardened trust policy slots in here.` between the defense application step and the verification step. Do not write Kiro content.
- **Warmup profile decision**: keep the "Profile decision (TODO)" section from `warmup/instructions.md` in the polished version. Don't pick an option yet.

## What to NOT do

- **Do not show alternative iam-recon surfaces that don't fire.** No "you might think to try `argquery --preset privesc` here, but..." callouts. Present the working surface as THE answer. The teaching gap is intentionally hidden per Tara's decision.
- **Do not add new pedagogical scaffolding.** No new diagrams, no new analogies, no new "Why does this matter?" sidebars beyond what the 2-hour exercises already have. Polish = render bullets into the existing 2-hour structure, no padding.
- **Do not re-validate commands.** Trust the bullets. If a command looks wrong, flag it back to Tara; don't change it.
- **Do not modify `intro-slide.md`, `attack.md`, `defense.md`.** Those are the source of truth.
- **Do not polish the `slide-updates/` files.** They're already in the right format (markdown bullets Tara will paste into .pptx).
- **Do not write a new top-level `instructions.md` or `lab-instructions.md`** that wraps all scenarios. The existing `labs-full-day/README.md` is the day-at-a-glance — leave it (or lightly polish it if you find rough edges).

## Style nits (match the 2-hour exercises)

- Ordered lists use `1.` for every item (per the project's CLAUDE.md style guide).
- Code blocks for every command, separate code block for expected output, then one short interpretation sentence.
- Use `> [!NOTE]` and `> [!TIP]` callout blocks where the 2-hour version uses them, sparingly.
- Use `**bold**` for inline emphasis the same way the 2-hour version does (key terms on first use, expected outputs in interpretation sentences).
- Each instruction file ends with a `---` then `**Next:** [<next scenario name>](../scenario-N-...)`.

## Workflow

1. Start with **Scenario 2** (it's the cleanest validation, simplest narrative — good calibration run for the format).
2. After Scenario 2, **pause and surface the rendered `instructions.md` to Tara** for a quick format-check before doing the other five. Don't polish all six and discover the format is wrong at scenario 6.
3. Once format is approved, do Scenarios 1, 3, 4, 5, optional in that order.
4. Then the warmup (simple) and a light pass over `cleanup.md` files (mostly already well-structured — just consistent voice and headers).
5. Final pass: walk every cross-reference (`Next:` links, file path references) to make sure they resolve.

## Final report

When done:
- List each scenario's `instructions.md` path
- List any places where you couldn't translate the bullet cleanly (e.g., a command sequence with no obvious narrative join)
- Flag anything you noticed during polish that the validation pass missed
- Confirm the 🚧 Kiro and Profile-decision markers are visible
