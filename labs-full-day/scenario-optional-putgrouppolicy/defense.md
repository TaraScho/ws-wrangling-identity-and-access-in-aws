# Optional Scenario — Defense bullets

Source: Lab 2 Exercise 6. Pairs with `attack.md` (PutGroupPolicy self-escalation). Control: **resource constraint on group ARN** — the user can only manage groups they're NOT a member of.

## Slide intro bullets

- Same pattern as Scenario 4 (resource constraint), applied to group ARNs.
- Key trick: scope `PutGroupPolicy` to a group the attacker is **not** a member of (`iamws-platform-team`) so self-escalation via own membership is broken, but the user can still legitimately manage another team's group.
- iam-recon resolves the resource pattern + group membership → PutGroupPolicy edge to admin disappears.

## Defense — full command path

```bash
# Step 1: scoped inline policy (admin/workshop identity)
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

aws iam put-user-policy \
  --user-name iamws-group-admin-user \
  --policy-name SecureGroupAdmin \
  --policy-document '{
    "Version": "2012-10-17",
    "Statement": [
      {
        "Sid": "AllowPutGroupPolicyOnPlatformTeamOnly",
        "Effect": "Allow",
        "Action": "iam:PutGroupPolicy",
        "Resource": "arn:aws:iam::'${ACCOUNT_ID}':group/iamws-platform-team"
      },
      {
        "Sid": "AllowGroupEnumeration",
        "Effect": "Allow",
        "Action": ["iam:ListGroups","iam:ListGroupPolicies","iam:GetGroupPolicy",
                   "iam:ListGroupsForUser","iam:GetGroup"],
        "Resource": "*"
      }
    ]
  }'

# Step 2: detach the overly-permissive managed policy
aws iam detach-user-policy \
  --user-name iamws-group-admin-user \
  --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/iamws-group-admin-policy

# Step 3: remove the attack residue (the admin inline policy the attacker wrote to their own group).
# Like Scenario 1, scoping doesn't undo the existing escalation — only new attempts. Without this,
# the user is still effectively admin via the group's lingering inline policy.
aws iam delete-group-policy \
  --group-name iamws-dev-team \
  --policy-name iamws-dev-team-escalated 2>/dev/null || true

# Step 4: WAIT for AWS IAM permission cache to expire (~60s) before verifying.
# Without the wait, the attacker user can still PutGroupPolicy on iamws-dev-team for ~3–5 min.
sleep 60
```

## Verify with the attack

```bash
# Original attack: write admin policy on own group → DENIED
aws iam put-group-policy \
  --group-name iamws-dev-team \
  --policy-name test-escalation \
  --policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":"*","Resource":"*"}]}' \
  --profile iamws-group-admin-user
# expect: AccessDenied

# Legitimate path: write a benign policy on a group the user is NOT in → ALLOWED
aws iam put-group-policy \
  --group-name iamws-platform-team \
  --policy-name test-allowed \
  --policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":"s3:GetObject","Resource":"*"}]}' \
  --profile iamws-group-admin-user
# expect: success

# Clean up the test — needs taractf because SecureGroupAdmin grants iam:PutGroupPolicy
# (matching the bullet's intent) but NOT iam:DeleteGroupPolicy. If you want the attacker user
# to be able to fully manage the platform-team group, add iam:DeleteGroupPolicy to
# SecureGroupAdmin's Sid AllowPutGroupPolicyOnPlatformTeamOnly.
aws iam delete-group-policy \
  --group-name iamws-platform-team \
  --policy-name test-allowed \
  --profile taractf

# Crown jewels still safe?
aws s3 cp s3://iamws-crown-jewels-${ACCOUNT_ID}/flag.txt - \
  --profile iamws-group-admin-user
# expect: AccessDenied
```

## Verify with iam-recon

- `iam-recon graph create --profile taractf`.
- `iam-recon --account $ACCOUNT_ID pathfinding` → `[iam-011]` finding for `iamws-group-admin-user` against `iamws-dev-team` should disappear.
- `iam-recon --account $ACCOUNT_ID argquery --principal user/iamws-group-admin-user --action iam:PutGroupPolicy --resource 'arn:aws:iam::*:group/iamws-dev-team'` → should now show DENY.

## Demo bullets

- Reinforce the pairing with Scenario 1 (CreatePolicyVersion) and Scenario 4 (Lambda code) — same family, three variations: write to a policy attached to self, write to a group containing self, write to a Lambda runnable as a privileged role.
- Watch-out: this defense relies on the attacker not being a member of the allowed group. In a real environment, periodically audit group membership against any "manage group X" permissions — group membership drift is a quiet way this control becomes a self-escalation again.
