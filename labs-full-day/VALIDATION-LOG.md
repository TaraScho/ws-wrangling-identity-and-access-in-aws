# Validation log — labs-full-day

Live validation run date: 2026-05-12. Account: `767397689800`. Admin profile: `taractf`.

Per-user attacker profiles configured locally from `labs-two-hour-workshop/terraform` outputs (the prompt asserted these "already exist" — they did not exist on this Mac; created from terraform state. No drift in IAM resources themselves.)

---

## ⚠️ STOPPED EARLY — surface cross-cutting recon gaps before continuing per-scenario validation

Two consecutive iam-recon recon commands diverged from bullet predictions, hitting the prompt's stop condition. Findings below; recommended decisions follow.

### Cross-cutting issue 1 — `argquery` syntax

- Bullets write `iam-recon --account $ACCOUNT argquery privesc` (positional `privesc`).
- Actual grammar: `iam-recon argquery --preset privesc` (or `argquery -a iam:X` / `argquery -p user/X`).
- `argquery` accepts no positional arguments; running it with `privesc` is silently ignored and yields an empty result.
- Applies to every `argquery privesc` invocation across `scenario-{1,2,3,4,5,optional}/{attack,defense}.md`.

### Cross-cutting issue 2 — natural-language `query` grammar

- Bullets write `iam-recon --account $ACCOUNT query "can user/iamws-X do iam:Y with *"`.
- iam-recon's `query` parser doesn't recognize the `can user/X do Y with Z` form. It consumes the entire string after "do" as one IAM action name, producing nonsense output like `ALLOW user/iamws-X can call can user/iamws-X do iam:Y with * with *`.
- Verified templates (`iam-recon query templates`) and the parser only accept these forms:
  - `who can do <action> with <resource>`
  - `what can <principal>`
  - `who can invoke lambda:InvokeFunction on *`
  - `compare <principal-a> and <principal-b>`
  - `preset <name>` (e.g. `preset privesc`)
- Recommended rewrite: replace `query "can user/iamws-X do iam:Y with *"` with `argquery --principal user/iamws-X --action iam:Y` (which gives a clean "ALLOW user/X can call iam:Y with *" line). Or rewrite as `query "who can do iam:Y with *"` and tell the participant to grep for their user.

### Cross-cutting issue 3 — flag positioning

- Confirmed: `--account` and `--profile` are **global** flags (registered on the root `iam-recon` clap parser). They can appear before OR after the subcommand. The bullets' style of `iam-recon --account $ACCOUNT argquery ...` works.
- Also confirmed: `--account` and `--profile` are *both* re-declared at the subcommand level on every subcommand, so `iam-recon argquery --account $ACCOUNT --preset privesc` also works. No change needed.

### Cross-cutting issue 4 — variable name

- Bullets mix `$ACCOUNT` and `$ACCOUNT_ID`. Standardize on **`$ACCOUNT_ID`** (already used in every shell example block; `$ACCOUNT` appears only in cheatsheet/recon bullets). Will sweep on the next pass.

### Cross-cutting issue 5 — warmup profile name

- `warmup/instructions.md` references `--profile workshop`. That profile does not exist; the workshop's per-user profiles created by `wwhf-setup.sh` are named `iamws-*-user`.
- Recommendation: warmup should use **a per-participant read-only profile** or fall back to whichever exercise profile the participant gets first (e.g. `iamws-policy-developer-user`, which only has the lab-1 dangerous permissions plus `Get*/List*` on IAM via `iamws-developer-tools-policy`).
- For *validation* of the bullets I'm using `taractf` (admin) as the scan profile. The polished lab will need its own decision.

### Cross-cutting issue 6 — `argquery --preset privesc` is INCOMPLETE for half the scenarios

This is the big content-level finding. iam-recon's `--preset privesc` only catches edges that are emitted by the 9 edge checkers in `src/edges/`. Several scenarios' attack paths are **not** emitted as edges:

| Scenario | Attack vector | In `argquery --preset privesc`? | In `pathfinding`? |
|---|---|---|---|
| 1 — `iamws-policy-developer-user` | `iam:CreatePolicyVersion` self-escalation | ❌ no edge checker for this | ✅ `[iam-001]` |
| 2 — `iamws-role-assumer-user` | `sts:AssumeRole` to `:root`-trust role | ✅ `STS` edge | ✅ `[sts-001]` |
| 3 — `iamws-ci-runner-user` | EC2 PassRole | ✅ `EC2` edge | ✅ `[ec2-001]` |
| 4 — `iamws-lambda-developer-user` | Lambda UpdateFunctionCode | ❌ blocked by `iam:PassRole` gate in `edges/lambda.rs:79` | ✅ `[lambda-003]`/`[lambda-004]` |
| 5 — `iamws-secrets-reader-user` | Lambda env-var disclosure (credential access, not IAM escalation) | n/a (correctly not flagged) | n/a |
| Opt — `iamws-group-admin-user` | `iam:PutGroupPolicy` self-escalation | ❌ no edge checker for this | ✅ `[iam-011]` |

Root cause for Scenario 4: `src/edges/lambda.rs:64-81` short-circuits on `iam:PassRole`. If the source principal cannot pass *some* role to Lambda, the checker `continue`s before evaluating the existing-function UpdateFunctionCode path. `iamws-lambda-developer-user`'s policy only grants `lambda:*`, not `iam:PassRole`, so the entire edge family is skipped. This is upstream behavior, not infra drift.

Root cause for Scenarios 1 and Optional: there is no IAM self-escalation edge checker in `src/edges/iam.rs` (which only handles PassRole-style edges). Pathfinding catches them because pathfinding maps single dangerous permissions to known paths regardless of whether the iam-recon edge graph has the corresponding edge.

**Recommendation:**
- Replace `argquery privesc` with `pathfinding` as the *primary* recon command in every scenario's attack.md. Pathfinding is the universal predictor that actually matches what the bullets describe.
- Keep `argquery --preset privesc` as a secondary command **only in scenarios 2 and 3** where it actually fires, and explicitly call out in scenarios 1, 4, and optional that "the iam-recon privesc preset doesn't catch this — use `pathfinding` instead." That gap is itself a teaching opportunity (edges vs path mapping).
- Defense-side verification: the predicted disappearance of an "edge from argquery privesc" only holds for scenarios 2 and 3. For 1, 4, and optional, switch to "the `[iam-001]` / `[iam-011]` / `[lambda-003]` pathfinding finding disappears."

### Cross-cutting issue 7 — interactive viz validation needs Playwright + a running iam-recon server

The interactive viz is launched by `iam-recon --account $ACCOUNT visualize --interactive-viz` and serves at `http://localhost:8080`. I'll spawn that as a background server, drive it with Playwright MCP, and document — per scenario — what node the participant should click and which edge/path they should see. Not yet done; blocked on your decisions above before continuing.

---

## Per-scenario sections (to be appended after decisions land)

- Warmup — 🔧 Validated with corrections
  - `iam-recon graph create --profile taractf` → OK; 36 nodes / 20 edges / 7 admins.
  - `iam-recon --account $ACCOUNT_ID visualize --interactive-viz` works, but **does not bind to :8080** — it binds to `127.0.0.1:0` (random port). iam-recon prints `Interactive visualization available at: http://127.0.0.1:<port>` and auto-opens the browser. No `--port` flag exists (verified in `iam-recon/src/visualization/interactive/server.rs:29`).
  - Fix applied to `warmup/instructions.md`: removed ":8080" claim, replaced with the dynamic-port behavior. **TODO Tara:** if you want a stable URL for slides, you'd need to upstream a `--port` flag to iam-recon.
  - Browser viz drove cleanly under Playwright MCP. Stats panel showed correct counts; Privesc filter correctly highlighted the same 8 principals that `argquery --preset privesc` returns from the CLI. Screenshot saved to `.playwright-mcp/warmup-viz.png`.
  - Open profile question (warmup TODO) is unchanged — `taractf` works for the validator; the polished lab still needs a per-participant decision.
- Scenario 1 — 🔧 Validated with corrections
  - **Pre-attack recon:** `pathfinding` correctly flags `[iam-001] user/iamws-policy-developer-user (self-escalation)`. `argquery --principal user/iamws-policy-developer-user --action iam:CreatePolicyVersion` returns `ALLOW`. Both match the bullet predictions.
  - **Attack works end-to-end** (`iamws-developer-tools-policy` v1 → v2 admin → crown jewels read), but **only after a ~15s wait** between `create-policy-version --set-as-default` and the S3 read. First S3 attempt got 403 due to IAM eventual consistency. Added a `sleep 15` to the attack bullet (`attack.md` Step 5).
  - **Defense's permissions boundary works at AWS** (verified by `iam create-policy-version` returning `AccessDenied with an explicit deny in a permissions boundary` and AWS `simulate-principal-policy` returning `explicitDeny`).
  - **Defense bullet had a residue bug:** running defense back-to-back after the attack does NOT re-deny crown jewels reads, because the attack's v2 admin policy is still default and the boundary's `AllowDeveloperActions` Sid allows `s3:*`. Added Step 0 to `defense.md` to reset v2 → v1 before applying the boundary. Also created `scenario-1-create-policy-version/cleanup.md` for the inter-scenario revert.
  - ⚠️ **MAJOR: iam-recon does not respect permissions boundaries in `argquery` / `pathfinding`** despite the README claiming it does and despite the boundary being correctly stored in `cache/nodes.json`. `argquery --principal ... --action iam:CreatePolicyVersion` still returns `ALLOW` post-boundary; `pathfinding [iam-001]` row is unchanged. Tested across multiple actions (iam:DeleteUser → DENY as expected, s3:GetObject → DENY because identity policy doesn't grant it, iam:CreatePolicyVersion → ALLOW even with explicit-deny in boundary). This contradicts the bullet's verification predictions for the defense. Updated `defense.md` to recommend AWS `simulate-principal-policy` as the verification surface and document the iam-recon limitation. **TODO upstream:** file an issue against iam-recon (`src/policy_eval/authorization.rs:25-35` calls `policy_has_matching_statement` on boundary, but the boundary policy attached during cache load may not be plumbed into that function via the right code path; needs deeper investigation than this validation pass).
  - **Interactive viz:** the user node was already blue before the defense (no CreatePolicyVersion edge checker, so it was never Privesc-orange). The bullet's "node returns from orange to blue" prediction is wrong. Updated. Screenshot: `.playwright-mcp/scenario-1-postdefense-viz.png`.
  - **Browser-explorer "expected path" for this scenario:** there is **no path/edge** for the participant to see — iam-recon's edge-based graph does not catch CreatePolicyVersion self-escalation. The teaching point in the viz becomes: search the user node, observe it's *blue* (not orange/privesc), highlight that the CLI `pathfinding [iam-001]` is the only iam-recon surface that catches this attack family.
  - **Revert:** boundary detached from user + role, DeveloperBoundary policy deleted, v2 policy version deleted, default restored to v1. Verified clean state.
- Scenario 2 — ✅ Validated (with minor recon-bullet clarifications)
  - **Pre-attack recon all confirmed:** `argquery --preset privesc` lists `user/iamws-role-assumer-user -> STS role/iamws-privileged-admin-role`; `argquery --principal --action --resource` returns ALLOW; `pathfinding` flags `[sts-001] user/iamws-role-assumer-user (principal-access)`.
  - **Attack works end-to-end:** denied → assume-role → admin → crown jewels. No timing issues.
  - **Defense works at AWS:** `aws sts assume-role` after defense returns `AccessDenied`. Crown jewels also forbidden. ✓
  - **Defense's `$(aws sts get-caller-identity --query Arn)` resolved correctly** under `taractf` to `arn:aws:iam::767397689800:user/tmp-wrangling-iam` — a long-lived IAM user ARN, valid as a trust-policy principal. Tara's open question is answered: this works as written.
  - **Verification surface caveat** — recorded as a content fix in `defense.md`:
    - ✅ `argquery --preset privesc` correctly removes the STS edge (its STS edge checker evaluates trust policies). Edges 20 → 18.
    - ❌ `argquery --principal --action --resource` and `query "who can do sts:AssumeRole..."` BOTH still return ALLOW post-defense because they only evaluate the principal's identity policy, ignoring the role's trust policy.
    - ❌ AWS `simulate-principal-policy` also says "allowed" — `simulate-principal-policy` ignores trust policies by design.
    - The only correct standalone verification commands are `aws sts assume-role` (live) and `argquery --preset privesc` (offline).
  - **Browser-explorer expected path:** Pre-defense: search `role-assumer-user` or `privileged-admin-role` — STS edge between user node and red admin role is visible. Post-defense: edge gone. Click the `iamws-privileged-admin-role` node → inspect panel shows the role's `AdministratorAccess` (IDENTITY) and `iamws-privileged-admin-role-trust` (TRUST) policies as clickable items. iam-recon still shows "1 RISK" on the trust policy even after hardening (apparent cosmetic — the authoritative signal is the absent STS edge, not the persistent badge). Screenshot: `.playwright-mcp/scenario-2-postdefense-trust-panel.png`.
  - **Revert:** trust policy restored to `:root` from saved baseline at `/tmp/validation/scenario2-original-trust.json`. Cleanup steps in `scenario-2-trust-policy-root/cleanup.md`.
- Scenario 3 — 🔧 Validated with corrections
  - **Pre-attack recon all confirmed:** `argquery --preset privesc` flags the EC2 PassRole edge; `argquery --principal user/iamws-ci-runner-user --action iam:PassRole` returns ALLOW; `pathfinding` flags `[ec2-001]` and `[ssm-001]`.
  - **Attack works end-to-end:** Launched `i-0c4688b436c592276` with `iamws-prod-deploy-profile`, waited ~30s for SSM agent, used `aws ssm send-command` via `taractf` to run `aws s3 cp` from inside — successfully read crown jewels. The instance assumed-role identity in the output: `arn:aws:sts::767397689800:assumed-role/iamws-prod-deploy-role/i-0c4688b436c592276`. ✓
  - **Two attack-bullet errors caught:**
    1. **Step 2** (`aws iam get-policy-version` as `iamws-ci-runner-user`) fails with `AccessDeniedException` — the user lacks `iam:GetPolicyVersion`. Updated the bullet to call it under `taractf` (or skip; the policy is on the slide).
    2. **Step 5** (`aws ssm describe-instance-information` as `iamws-ci-runner-user`) fails with `AccessDeniedException` — the user has `ssm:StartSession/TerminateSession/DescribeSessions` but **not** `ssm:DescribeInstanceInformation`. Updated to `sleep 90` + poll under `taractf`.
    3. **Step 6** (`aws ssm start-session`) is interactive — works for participants with a real terminal; for non-interactive validation, used `aws ssm send-command` via `taractf` instead. Documented this choice as a comment in the bullet (the participant-facing flow is unchanged).
  - **Defense works at AWS:** New attempt to run-instances with `iamws-prod-deploy-profile` returns `UnauthorizedOperation ... iam:PassRole on resource: arn:aws:iam::*:role/iamws-prod-deploy-role`. AWS `simulate-principal-policy` returns `"allowed"` for legitimate Lambda PassRole, `"implicitDeny"` for EC2 PassRole on prod-deploy-role. Crown jewels still Forbidden. ✓
  - **iam-recon verification works correctly here:**
    - `argquery --preset privesc` no longer flags the *user* (edges: 20 → 18).
    - `argquery --principal --action --resource` returns `DENY` for the attack vector (iam-recon's policy simulator correctly applies the `iam:PassedToService` condition).
    - `pathfinding` `[ec2-001]` row for the user disappears.
  - **One residual gap** — the defense only modifies the *user*'s policy. The same-named *role* (`iamws-ci-runner-role`) still has the original `iamws-ci-runner-policy` attached, so iam-recon's `argquery --preset privesc` still shows `role/iamws-ci-runner-role -> EC2 role/iamws-prod-deploy-role`. Added a note to the defense bullets recommending the symmetric fix.
  - **Browser-explorer expected path:** Pre-defense: search `ci-runner-user` — node is orange (Privesc); EC2 edge to red `iamws-prod-deploy-role` is visible. Post-defense: user node is blue (User), only `SecurePassRole` listed under IDENTITY; EC2 edge to prod-deploy-role gone. The `role/iamws-ci-runner-role` node is still orange (per the residual-gap note above). Screenshot: `.playwright-mcp/scenario-3-postdefense-viz.png`.
  - **Revert:** EC2 instance terminated, `SecurePassRole` inline policy deleted, `iamws-ci-runner-policy` re-attached. Cleanup in `scenario-3-passrole-ec2/cleanup.md`.
- Scenario 4 — 🔧 Validated with corrections
  - **Pre-attack recon all confirmed:** `pathfinding` flags `[lambda-003]` and `[lambda-004]` for `user/iamws-lambda-developer-user`; `argquery --principal --action` returns ALLOW. (As predicted in the bullet, `argquery --preset privesc` does NOT flag this user — iam-recon's lambda edge checker short-circuits on `iam:PassRole`.)
  - **Attack works end-to-end:** Updated `iamws-privileged-lambda` code to the exploit handler, invoked it, response payload showed `Arn: arn:aws:sts::767397689800:assumed-role/iamws-privileged-lambda-role/...` and the crown jewels content.
  - **Defense works at AWS** — but only after a meaningful wait. **MAJOR FINDING: AWS Lambda's IAM permission cache lasts ~3–5 minutes**. Immediately after `put-user-policy SecureLambdaDeveloper` + `detach-user-policy iamws-lambda-developer-policy`, the attacker user could STILL successfully call `lambda:UpdateFunctionCode` on `iamws-privileged-lambda` for several minutes. Verified by detaching ALL policies (zero policies attached) and confirming the call still succeeded — yet AWS `simulate-principal-policy` returned `implicitDeny` immediately. After 5 minutes the live call started correctly returning `AccessDeniedException`. Without this wait, the bullet's "Verify with the attack" step looks like the defense failed.
  - **Defense bullet fixed:** added an explicit `sleep 60` after the detach step (plus a comment explaining the IAM cache). For workshop participants this is naturally hidden by 1–2 minutes of explaining the policy.
  - **iam-recon verification works correctly** (and immediately — it's offline):
    - `pathfinding`: `[lambda-003]/[lambda-004]` rows for `user/iamws-lambda-developer-user` disappear.
    - `argquery --principal user/... --action lambda:UpdateFunctionCode --resource <privileged-fn>`: returns `DENY`.
    - `argquery --principal user/... --action lambda:UpdateFunctionCode --resource <dev-*>`: returns `ALLOW` (legitimate path preserved). Note: the resource ARN needs an explicit account ID (`arn:aws:lambda:*:767397689800:function:dev-foo`); with `*` for account, iam-recon's wildcard matcher returns DENY.
  - **Browser-explorer expected path:** Pre-defense: search `lambda-developer-user` — the node is blue (User) because no edge checker flagged it (per the bullet's teaching note). The `iamws-privileged-lambda-role` is red (Admin). There's no edge between them — iam-recon's edge graph misses this attack family. Post-defense: the user's `POLICIES > IDENTITY` panel now shows `SecureLambdaDeveloper`. Screenshot: `.playwright-mcp/scenario-4-postdefense-viz.png`.
  - **Revert:** Lambda code restored from saved `/tmp/validation/scenario4-original-code.zip` (original `CodeSha256 = UICXkyne1cumrq6E1GRqIafrb4NjgQ4Z7fULur/ZRPM=` confirmed). SecureLambdaDeveloper inline policy deleted, `iamws-lambda-developer-policy` re-attached. Cleanup in `scenario-4-lambda-updatefunctioncode/cleanup.md`.
- Scenario 5 — 🔧 Validated with corrections
  - **Pre-attack recon partial:** `argquery --principal user/iamws-secrets-reader-user --action lambda:GetFunctionConfiguration` returns ALLOW ✓. But the bullet's `analysis` and `pathfinding` predictions are wrong — iam-recon has **no env-var/sensitive-secret detector** and **no Credential Access pathfinding category**. Verified: `analysis` only reports privesc-path findings (lambda-003, ssm-001, etc.); `pathfinding` similarly only enumerates privesc paths. Updated both attack.md and defense.md to remove the wrong predictions and add the gap as a teaching moment.
  - **Attack works end-to-end:** `aws lambda get-function-configuration --function-name iamws-app-with-secrets` as `iamws-secrets-reader-user` dumped all 5 plaintext env vars (DB_HOST, DB_USERNAME, DB_PASSWORD, API_KEY, ADMIN_CREDENTIALS) verbatim from the bullet. ✓
  - **Defense works at AWS:**
    - `aws lambda get-function-configuration` after the env-var swap now returns `{"SECRET_NAME":"iamws-app-secrets"}` only ✓.
    - `aws secretsmanager get-secret-value --secret-id iamws-app-secrets` as the attacker user returns `AccessDeniedException ... secretsmanager:GetSecretValue` ✓.
  - **iam-recon verification works** for the policy-side change (immediately, no IAM cache delay since these are *grants* not *revokes*):
    - `argquery --principal role/iamws-app-lambda-role --action secretsmanager:GetSecretValue --resource <full-secret-arn>` → ALLOW ✓.
    - `argquery --principal user/iamws-secrets-reader-user --action secretsmanager:GetSecretValue` → DENY ✓.
    - Note: with `--resource *` or without a `--resource`, argquery on the Lambda role returns DENY (the scoped policy correctly doesn't match `*`). Need to use the actual secret ARN.
  - **No browser-explorer expected path:** this scenario isn't an IAM-graph attack and the iam-recon graph viz adds nothing here. Skipping viz screenshot.
  - **Revert:** original env vars restored from `/tmp/validation/scenario5-original-env.json`, `SecretsManagerAccess` inline policy deleted from `iamws-app-lambda-role`, secret deleted (`--force-delete-without-recovery`). Cleanup in `scenario-5-lambda-secrets/cleanup.md`.
- Scenario optional — 🔧 Validated with corrections
  - **Pre-attack recon all confirmed:** `pathfinding [iam-011]` flags `user/iamws-group-admin-user`; `argquery --principal --action` returns ALLOW. (As predicted, `argquery --preset privesc` does NOT catch this — no `PutGroupPolicy` edge checker.)
  - **Attack works end-to-end:** wrote admin inline policy on `iamws-dev-team` group; after a 15s IAM consistency wait, crown jewels read succeeded.
  - **Defense works at AWS** (after the 60s IAM cache wait — same gotcha as Scenario 4):
    - `aws iam put-group-policy` on own group (`iamws-dev-team`) → `AccessDenied`.
    - `aws iam put-group-policy` on the not-a-member group (`iamws-platform-team`) → success (legitimate path preserved).
    - Crown jewels still Forbidden after defense.
  - **Two bullet corrections caught and fixed:**
    1. The defense was missing a **reset of the attack's escalated group policy** (`iamws-dev-team-escalated`). Without resetting, the user is still effectively admin via the group's lingering inline policy even after the user-side defense is applied. Added Step 3 to `defense.md` to `delete-group-policy iamws-dev-team-escalated`.
    2. The bullet's "clean up the test" step calls `delete-group-policy --profile iamws-group-admin-user` — that fails (`AccessDenied — iam:DeleteGroupPolicy not allowed`) because `SecureGroupAdmin` only grants `iam:PutGroupPolicy`, not Delete. Updated the cleanup line to run as `taractf`, and added a note that you could expand `SecureGroupAdmin` to include `iam:DeleteGroupPolicy` if the bullet means the attacker user should be able to fully manage the other group.
    3. Added a `sleep 60` after the defense (same IAM-cache reason as Scenario 4).
  - **iam-recon verification works:**
    - `pathfinding [iam-011]` row for the *user* disappears. (The *role* row remains — same residual gap as Scenario 3.)
    - `argquery` on `iamws-dev-team`: DENY ✓.
    - `argquery` on `iamws-platform-team`: ALLOW ✓.
  - **Browser-explorer expected path:** same as Scenario 1/4 — user node is blue (no edge checker for this attack family), inspect panel shows `SecureGroupAdmin` under IDENTITY post-defense. No edge between user and group/admin. Skipping dedicated screenshot.
  - **Revert:** test policies deleted, `iamws-dev-team-escalated` deleted, `SecureGroupAdmin` removed, `iamws-group-admin-policy` re-attached. Cleanup in `scenario-optional-putgrouppolicy/cleanup.md`.

---

## Update — 2026-05-12 (Tara's session): cross-cutting fixes applied

All seven cross-cutting issues from above have been applied to the bullet files. Specifically:

1. **`argquery privesc` → `argquery --preset privesc`** — swept across every `.md` file via `sed`. Remaining occurrences are either in valid contexts (scenarios 2 + 3 where it actually fires, README cheatsheet, slide updates explaining the tool) or in explicit "won't catch this — use pathfinding" callouts in scenarios 1 / 4 / optional. Confirmed via `grep`.
2. **NL `query "can user/X do Y with Z"`** — replaced with `argquery --principal user/X --action Y [--resource Z]` across every attack and defense file. The Scenario 2 defense `"who can assume..."` query was rewritten as `who can do sts:AssumeRole with arn:aws:iam::*:role/iamws-privileged-admin-role` (canonical NL form).
3. **Flag positioning** — no change needed (confirmed `--account` global per your finding).
4. **`$ACCOUNT` → `$ACCOUNT_ID`** — swept; zero bare `$ACCOUNT` instances remain.
5. **`--profile workshop` → `--profile taractf`** — swept across all files. Warmup file got an additional "Profile decision" TODO block listing three options (new readonly-scanner user / sandbox admin / per-exercise user) for the polished pass.
6. **`pathfinding` promoted to primary recon** — Scenarios 1, 4, and Optional now lead recon with `pathfinding` and explicitly flag the `argquery --preset privesc` gap as a teaching moment. Defense-side verification swapped to `[iam-001]` / `[iam-011]` / `[lambda-003/004]` pathfinding findings. Scenarios 2 + 3 keep `argquery --preset privesc` as primary (it works there). README and Slide 1 of Lecture 1 updated with a recon-coverage table showing which scenarios each surface catches.
7. **Interactive viz validation** — not addressed yet; please proceed with Playwright once you confirm the cross-cutting fixes look right.

**Ready for the per-scenario validation pass.** Pick up where you left off — start with the warmup or jump to Scenario 1 (which was previously blocked).

**One remaining open question for you (validator):** the Scenario 2 defense's hardened trust policy uses `$(aws sts get-caller-identity --query Arn)` as the trusted principal. Under `taractf`, does that resolve to a usable ARN (a long-lived IAM user/role) or to a temporary STS session ARN that can't go in a trust policy? Flag if so; we'll either substitute a fixed role ARN or document the limitation.

---

## Final summary — 2026-05-12 (validation pass complete)

All 7 files validated end-to-end against the live AWS account. Per-scenario status:

| Scenario | Status | Key bullet changes |
|---|---|---|
| Warmup | 🔧 Validated with corrections | Removed `:8080` claim; documented dynamic port; profile decision deferred. |
| Scenario 1 (CreatePolicyVersion) | 🔧 Validated with corrections | Added `sleep 15` for IAM eventual consistency; added Step 0 to reset v2→v1 before applying boundary; rewrote verification to use AWS `simulate-principal-policy` since iam-recon doesn't apply boundaries in `argquery`/`pathfinding`. |
| Scenario 2 (trust-policy `:root`) | ✅ Validated (minor) | Clarified that only `argquery --preset privesc` reflects the trust-policy change; `argquery --principal --action --resource` and AWS `simulate-principal-policy` ignore trust policies and still say ALLOW. |
| Scenario 3 (PassRole+EC2) | 🔧 Validated with corrections | Step 2 (`get-policy-version`) and Step 5 (`describe-instance-information`) needed `taractf` (ci-runner-user lacks both perms); Step 6 (`start-session`) called out as interactive; added note that the role version of the user still appears in privesc until same fix is applied to the role. |
| Scenario 4 (Lambda UpdateFunctionCode) | 🔧 Validated with corrections | Added explicit `sleep 60` after defense to wait out AWS IAM permission cache (~3–5 min empirically); documented that pathfinding correctly catches this and `argquery --preset privesc` doesn't (per the existing bullet). |
| Scenario 5 (Lambda secrets) | 🔧 Validated with corrections | Removed wrong predictions about `analysis`/`pathfinding` flagging env-var secrets (iam-recon has neither); replaced with `argquery --action lambda:GetFunctionConfiguration` as the only recon surface. Defense correctly verified via AWS get-function-configuration + argquery. |
| Scenario optional (PutGroupPolicy) | 🔧 Validated with corrections | Added attack-residue reset (`delete-group-policy iamws-dev-team-escalated`); added `sleep 60` for IAM cache; cleanup line switched to `taractf` because `SecureGroupAdmin` lacks `iam:DeleteGroupPolicy`. |

### Cross-cutting findings (above and beyond the 7 from the first pass)

1. **AWS IAM permission cache (~3–5 min)** affects every revoke-style defense (Scenarios 4 and optional are the worst cases). `simulate-principal-policy` correctly returns `implicitDeny` immediately, but live calls keep succeeding briefly. Added `sleep 60` to those defenses; the workshop walkthrough naturally hides this by talking through the policy.
2. **iam-recon does NOT evaluate permissions boundaries in `argquery`/`pathfinding`** (Scenario 1) despite collecting them into the graph correctly. README claims it does. AWS `simulate-principal-policy` is the right verification surface for boundary-based defenses. ⚠️ Worth filing an upstream issue.
3. **iam-recon's NL `query` parser has a cosmetic output bug**: even valid queries like `who can do sts:AssumeRole with <resource>` render the entire query string as the action name in the output (`...can call who can do sts:AssumeRole with arn:... with *`). Underlying authorization is correct, just the formatter. Bullet-side mitigation: prefer `argquery --principal --action --resource` over NL `query` when participants will read the output line-by-line.
4. **Edge-checker gaps in iam-recon** (already documented above) mean `argquery --preset privesc` is *not* the universal verification surface — only Scenarios 2, 3 use it correctly; Scenarios 1, 4, optional rely on `pathfinding`; Scenario 5 has no iam-recon recon surface beyond a per-action argquery.
5. **Attack→defense ordering for "user modifies a policy attached to themselves" scenarios (1 and optional)** requires explicit reset of the attack's policy artifact before the defense will look effective. Added to both defenses.
6. **Defenses that scope a user's permissions don't symmetrically fix the role**: Scenarios 3 and optional both create a same-named role (e.g. `iamws-ci-runner-role`, `iamws-group-admin-role`) that retains the original overly-permissive managed policy. iam-recon still flags those role nodes. Documented as a "if you want the role's edge to also disappear..." note in each defense.

### Interactive viz screenshots saved (Playwright MCP)

- `.playwright-mcp/warmup-viz.png` — full graph with admins/privesc nodes highlighted.
- `.playwright-mcp/scenario-1-postdefense-viz.png` — `iamws-policy-developer-user` blue (no edge family for this attack).
- `.playwright-mcp/scenario-2-postdefense-search.png` — `iamws-privileged-admin-role` isolated after defense (graph went from 20 → 18 edges).
- `.playwright-mcp/scenario-2-postdefense-trust-panel.png` — role inspect panel showing trust policy (still flagged "1 RISK" — cosmetic; the STS edge is gone, which is the authoritative signal).
- `.playwright-mcp/scenario-3-postdefense-viz.png` — `iamws-ci-runner-user` blue, `SecurePassRole` under IDENTITY.
- `.playwright-mcp/scenario-4-postdefense-viz.png` — `iamws-lambda-developer-user` blue, `SecureLambdaDeveloper` under IDENTITY.

### Per-scenario `cleanup.md` files created

- `scenario-1-create-policy-version/cleanup.md`
- `scenario-2-trust-policy-root/cleanup.md`
- `scenario-3-passrole-ec2/cleanup.md`
- `scenario-4-lambda-updatefunctioncode/cleanup.md`
- `scenario-5-lambda-secrets/cleanup.md`
- `scenario-optional-putgrouppolicy/cleanup.md`

Each includes both attack-side artifact reverts (e.g. terminate the launched EC2, restore Lambda code, restore env vars, delete escalated group policy) and defense-side reverts (re-attach managed policies, delete inline policies, delete boundaries / secrets). All polished labs should incorporate these.
