# Scenario 2 — Defense bullets (afternoon, first slot after Lecture 2, ~30 min)

Source: Lab 2 Exercise 2. Pairs with `attack.md` (AssumeRole trust `:root`). Control: **hardened trust policy** (specific principal + MFA condition). **Includes Andrew's Kiro lab.**

## Slide intro bullets

- Trust policies are **resource policies** on the role itself — they answer "who can assume me?"
- Fix the trust policy, not the caller. `:root` means "anyone in this account"; replace with a specific principal ARN.
- Add `aws:MultiFactorAuthPresent: true` for defense in depth — sensitive roles should require MFA.
- iam-recon evaluates trust policies with condition keys → STS edge disappears unless simulating with MFA context.

## Defense — full command path

```bash
# Step 1: inspect the current vulnerable trust policy (admin/workshop identity)
aws iam get-role --role-name iamws-privileged-admin-role \
  --query 'Role.AssumeRolePolicyDocument' --output json
# note: Principal.AWS = arn:aws:iam::ACCOUNT:root

# Step 2: harden — replace :root with specific principal + add MFA condition
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ADMIN_ROLE_ARN=$(aws sts get-caller-identity --query Arn --output text)

aws iam update-assume-role-policy \
  --role-name iamws-privileged-admin-role \
  --policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Principal": {"AWS": "'$ADMIN_ROLE_ARN'"},
      "Action": "sts:AssumeRole",
      "Condition": {"Bool": {"aws:MultiFactorAuthPresent": "true"}}
    }]
  }'
```

## Andrew's Kiro lab (placeholder)

- **TODO Andrew:** drop bullet outline + commands here.
- Best guess at integration point: after the hardened trust policy lands, Kiro walks participants through authoring/refactoring the trust policy in Kiro (IDE? agent?) to demonstrate a defender workflow.

## Verify with the attack

```bash
# Re-run the original exploit as the attacker user
aws sts assume-role \
  --role-arn arn:aws:iam::${ACCOUNT_ID}:role/iamws-privileged-admin-role \
  --role-session-name escalated \
  --profile iamws-role-assumer-user
# expect: AccessDenied — principal not trusted (and no MFA)

# Crown jewels still safe?
aws s3 cp s3://iamws-crown-jewels-${ACCOUNT_ID}/flag.txt - \
  --profile iamws-role-assumer-user
# expect: Forbidden
```

## Verify with iam-recon

- `iam-recon graph create --profile taractf`.
- `iam-recon --account $ACCOUNT_ID argquery --preset privesc` → STS edge from `iamws-role-assumer-user` → `iamws-privileged-admin-role` is gone (verified: graph edges drop from 20 → 18 after the defense). **This is the only iam-recon command that correctly reflects the trust-policy change** — its STS edge checker (`src/edges/sts.rs`) does evaluate trust policies.
- ⚠️ `argquery --principal user/iamws-role-assumer-user --action sts:AssumeRole --resource <role-arn>` will still say `ALLOW` — iam-recon's per-action query only checks the principal's identity policy, not the role's trust policy. Same caveat applies to AWS `simulate-principal-policy` (it ignores trust policies by design). The live `aws sts assume-role` + the privesc edge disappearance are the two correct verifications.
- In the interactive viz, click the role node — the inspect panel lists `role/iamws-privileged-admin-role-trust` under `TRUST` (clickable). Note: iam-recon's viz flags the trust policy as "1 RISK" even post-hardening (it appears to flag any trust policy on an admin-tier role regardless of scoping); the authoritative signal is the absent STS edge in the graph, not the persistent risk badge.

## Demo bullets

- Pull up the role in iam-recon's viz both before and after; click the trust edge to show condition keys inline.
- Discuss: trust policies travel with the role across account boundaries; this is how you safely share a role cross-account.
- Watch-out: `aws:MultiFactorAuthPresent` only works for long-term IAM users; federated SSO sessions need different condition keys (`aws:PrincipalTag/...`).
