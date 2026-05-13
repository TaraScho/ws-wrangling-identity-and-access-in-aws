# Wrangling Identity & Access in AWS — Full-Day Workshop (B-Sides Tampa)

8-hour scenario-based version of the workshop. Each scenario covers identify → exploit → defend; iam-recon is the single recon tool across all hands-on work.

## Day at a glance

| Time | Block |
|---|---|
| 9:00 – 9:40 | Lecture 1 — IAM fundamentals + iam-recon intro |
| 9:40 – 10:00 | Warmup ("baby's first lab") |
| 10:00 – 11:30 | Morning attack scenarios 1–5 (15 min each, with break 10:30–10:45) |
| 11:30 – 12:00 | Kiro + MCP teaser |
| 12:00 – 1:00 | Lunch |
| 1:00 – 1:30 | Gamification (Jeopardy / Millionaire) |
| 1:30 – 2:00 | Lecture 2 — defense + IAM Spy + provers |
| 2:00 – 2:30 | Scenario 2 defense (harden trust policy + Andrew's Kiro lab) |
| 2:30 – 2:45 | Afternoon break |
| 2:45 – 4:00 | Defense scenarios — permissions boundary, Lambda, PassRole+EC2, optional PutGroupPolicy |
| 4:00 – 4:30 | Flex (trivia / extra lab time) |
| 4:30 – 5:00 | Cleanup, Q&A, feedback |

## Scenario index

- `warmup/` — first iam-recon scan
- `scenario-1-create-policy-version/` — CreatePolicyVersion self-escalation ↔ permissions boundary
- `scenario-2-trust-policy-root/` — AssumeRole trust `:root` ↔ hardened trust policy + Kiro lab
- `scenario-3-passrole-ec2/` — PassRole+EC2 ↔ `iam:PassedToService` condition
- `scenario-4-lambda-updatefunctioncode/` — Lambda UpdateFunctionCode ↔ resource constraint
- `scenario-5-lambda-secrets/` — Lambda GetFunctionConfiguration secrets ↔ Secrets Manager
- `scenario-optional-putgrouppolicy/` — PutGroupPolicy ↔ group ARN constraint

## Slide updates

- `slide-updates/lecture-1-iam-recon-intro.md` — bullets to replace awspx/pmapper demo in Lecture 1
- `slide-updates/lecture-2-additions.md` — bullets for IAM Spy, provers, and iam-recon-as-verification narrative in Lecture 2

## Infrastructure

Reuses Terraform from `../labs-two-hour-workshop/terraform/`. Same vulnerable IAM principals; no infra changes required for this round. Outline TODO: convert Terraform → CloudFormation for one-click deploy (separate task).

## iam-recon command cheatsheet

```bash
iam-recon graph create --profile <name>                                          # scan
iam-recon --account $ACCOUNT_ID pathfinding                                      # primary recon — maps to pathfinding.cloud (universal)
iam-recon --account $ACCOUNT_ID argquery --preset privesc                        # graph-edge view — catches edge-based privesc (subset of pathfinding)
iam-recon --account $ACCOUNT_ID argquery --principal user/X --action Y[ --resource Z]   # per-permission ALLOW/DENY check
iam-recon --account $ACCOUNT_ID query "who can do iam:CreateUser with *"         # NL query (form: "who can do <action> with <resource>")
iam-recon --account $ACCOUNT_ID analysis                                         # full preset audit (incl. env-var findings)
iam-recon --account $ACCOUNT_ID visualize --interactive-viz                      # browser at dynamic port (printed in terminal)
iam-recon --tui --account $ACCOUNT_ID                                            # terminal dashboard
```

**Recon coverage notes** (validated against `src/edges/` and `src/cli/argquery.rs`):

| Scenario | Caught by `argquery --preset privesc`? | Caught by `pathfinding`? |
|---|---|---|
| 1 — CreatePolicyVersion | ❌ no edge checker | ✅ `[iam-001]` |
| 2 — AssumeRole `:root` | ✅ STS edge | ✅ `[sts-001]` |
| 3 — PassRole+EC2 | ✅ EC2 edge | ✅ `[ec2-001]` |
| 4 — UpdateFunctionCode | ❌ lambda checker short-circuits on missing `iam:PassRole` | ✅ `[lambda-003]`/`[lambda-004]` |
| 5 — Env-var secrets | n/a (credential access, not privesc) — use `analysis` | n/a |
| Optional — PutGroupPolicy | ❌ no edge checker | ✅ `[iam-011]` |

**Default to `pathfinding` for both recon and post-defense verification.** `argquery --preset privesc` is a supplemental view that fires on Scenarios 2 and 3.

## Open questions

1. Afternoon scenario ordering — keep outline order (trust policy first) or re-sort to match morning?
2. Outline mentions "UpdateFunctionConfiguration" — typo for **Get**FunctionConfiguration (current E7), or a new attack vector?
3. Kiro lab in Scenario 2 defense — need Andrew's content.
4. Lecture 2 IAM Spy + provers — fold into existing deck or new deck?
