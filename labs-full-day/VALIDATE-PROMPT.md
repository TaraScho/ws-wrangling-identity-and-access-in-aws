# Validation prompt — copy/paste into a fresh Claude session

You are validating the bullet-form lab instructions for an 8-hour AWS IAM workshop by running every step in a live AWS account. Goal: prove each scenario is correct end-to-end so I can proceed to polished lab markdown with confidence.

## What's already in place

- Bullet-form scenarios live at `/Users/tara.schoenherr/repos/ws-wrangling-identity-and-access-in-aws/labs-full-day/`. Read `README.md` there first for the day structure.
- The vulnerable Terraform infrastructure is deployed in my AWS account. Principals/groups/Lambdas/S3 crown-jewels bucket from `labs-two-hour-workshop/terraform/` already exist.
- AWS profile **`taractf`** is the admin profile — use it for setup, teardown, and admin-side commands. It is configured in `~/.aws/credentials`.
- Per-user profiles created by `labs-two-hour-workshop/wwhf-setup.sh` already exist (e.g. `iamws-policy-developer-user`, `iamws-role-assumer-user`, etc.). Verify with `aws configure list-profiles`.
- An initial `iam-recon graph create` against the account has already been run; cached graph data exists. You'll re-scan after each policy change.
- iam-recon source at `~/repos/iam-recon` — read the README and `--help` output to confirm actual command syntax before running.

## Files to validate

- `labs-full-day/warmup/instructions.md`
- `labs-full-day/scenario-1-create-policy-version/{attack,defense}.md`
- `labs-full-day/scenario-2-trust-policy-root/{attack,defense}.md`
- `labs-full-day/scenario-3-passrole-ec2/{attack,defense}.md`
- `labs-full-day/scenario-4-lambda-updatefunctioncode/{attack,defense}.md`
- `labs-full-day/scenario-5-lambda-secrets/{attack,defense}.md`
- `labs-full-day/scenario-optional-putgrouppolicy/{attack,defense}.md`

Do **not** validate the `slide-updates/` files — they have no commands.

## The rule — no handwaving

**Every command in every bullet must be executed.** Not a representative sample. Not "this looks right." Run it. Capture output. Compare to the expected outcome the bullet states.

When a command fails:

1. First check whether the bullet has the wrong syntax. Look at `iam-recon <subcommand> --help`, the README at `~/repos/iam-recon/README.md`, and the Makefile. If syntax is wrong, **fix the bullet in place** so it matches what works.
2. If the syntax is right but the *behavior* doesn't match the bullet's prediction (e.g. iam-recon doesn't flag the edge the bullet predicts), that's a content-level issue. Leave the bullet as-is but insert a `> VALIDATION ISSUE: <what actually happened>` callout in the file.
3. If a command fails because underlying infrastructure is missing or different (e.g. `iamws-developer-tools-policy` doesn't exist), **don't paper over it**. Flag as infrastructure drift, stop that scenario, and continue to the next.

## Per-scenario workflow

For each scenario, in this exact order:

1. **Run the iam-recon recon commands** from `attack.md`. Confirm they identify the predicted path. Save raw output to `/tmp/validation/scenario-N-recon.txt`.
2. **Run the attack commands** one by one. Confirm: crown-jewels-denied → recon → exploit → crown-jewels-claimed (or for Scenario 5, secrets dumped).
3. **Run the defense commands** from `defense.md` as the `taractf` admin profile.
4. **Re-run the attack** to confirm it's blocked. Confirm crown jewels are still safe.
5. **Re-scan with iam-recon** (`graph create --profile taractf`, then `argquery privesc` / `pathfinding` / `analysis` as the bullets specify). Confirm the predicted edge disappears.
6. **Revert the defense** so the next scenario starts clean. This means:
   - Delete created policies, secrets, boundaries
   - Re-attach original managed policies that were detached
   - Restore trust policies that were updated
   - Terminate EC2 instances launched during the attack (Scenario 3)
   - Restore Lambda code and env vars to their original state (Scenarios 4 + 5)
   - If revert is non-trivial, document the revert steps in a new `cleanup.md` in the scenario folder — the polished lab will need cleanup instructions too.
7. **Update the bullet file in place** with any syntax corrections from steps 1–5.
8. **Append to `labs-full-day/VALIDATION-LOG.md`** — one section per scenario stating what was confirmed, what was corrected, and what was flagged.

## Things I specifically want you to check

- **iam-recon query grammar**. My bullets use `iam-recon --account $ACCOUNT query "can user/X do Y with Z"` — that's adapted from pmapper's syntax. Verify iam-recon's actual `query` grammar. If different, update every bullet across all scenarios consistently.
- **iam-recon flag positioning**. My bullets put `--account` before the subcommand (e.g. `iam-recon --account $ACCOUNT argquery privesc`). Confirm whether `--account` is a global flag or per-subcommand.
- **Variable consistency**. Bullets mix `$ACCOUNT` and `$ACCOUNT_ID`. Pick one and standardize.
- **Warmup profile name**. `warmup/instructions.md` references `--profile workshop` — there is no such profile. Replace with `taractf` (or whatever the right scan profile is) across all files.
- **Scenario 3 SSM session**. The session is interactive — you can't easily run `aws ssm start-session` inside a non-interactive shell. Either use `aws ssm send-command` instead, or document the manual interactive approach. Pick the one that actually works and update the bullet.
- **Scenario 2 hardened trust policy**. The defense uses `aws sts get-caller-identity` as the trusted principal — confirm that resolves to a usable ARN when run under `taractf`, not something like an STS-temporary session ARN that can't be put in a trust policy.

## Stop conditions

- Stop and update files after each scenario. Do **not** run all six in one shot.
- If two consecutive iam-recon commands return data that doesn't match the bullets' predictions, **stop** and surface the gap to me before continuing.
- If the Terraform infrastructure is meaningfully different from what the bullets expect, **stop and flag** — do not provision missing infrastructure yourself.

## Final report

When done, produce a per-scenario summary:

- ✅ Validated — no changes needed
- 🔧 Validated with corrections — list what changed
- ⚠️ Issues found — list what I need to fix manually
- ❌ Blocked — couldn't run, explain why

Plus a list of any cross-cutting fixes you applied (grammar/flag/variable consistency).

## What you should NOT do

- Don't polish prose or formatting — only correct factual errors.
- Don't add new scenarios or commands. If a step is missing, flag it; don't write it.
- Don't skip cleanup between scenarios.
- Don't modify Terraform or provision new AWS resources beyond what the lab steps explicitly create.
