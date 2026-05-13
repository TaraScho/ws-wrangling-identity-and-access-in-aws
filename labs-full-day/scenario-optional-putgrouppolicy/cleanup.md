# Optional Scenario — Cleanup

Run as `taractf` (admin) after the defense demo.

## Revert the attack artifact

Remove the escalated inline policy the attacker wrote to their own group:

```bash
aws iam delete-group-policy \
  --group-name iamws-dev-team \
  --policy-name iamws-dev-team-escalated \
  --profile taractf 2>/dev/null || true
```

## Revert the defense

Drop any test inline policies created during verification, then restore the original managed policy:

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text --profile taractf)

aws iam delete-group-policy \
  --group-name iamws-platform-team --policy-name test-allowed \
  --profile taractf 2>/dev/null || true

aws iam delete-group-policy \
  --group-name iamws-dev-team --policy-name test-escalation \
  --profile taractf 2>/dev/null || true

aws iam delete-user-policy \
  --user-name iamws-group-admin-user --policy-name SecureGroupAdmin \
  --profile taractf

aws iam attach-user-policy \
  --user-name iamws-group-admin-user \
  --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/iamws-group-admin-policy \
  --profile taractf
```

## Confirm clean state

```bash
aws iam list-attached-user-policies \
  --user-name iamws-group-admin-user \
  --query 'AttachedPolicies[].PolicyName' --output table --profile taractf
# expect: iamws-group-admin-policy

aws iam list-user-policies \
  --user-name iamws-group-admin-user \
  --query 'PolicyNames' --output text --profile taractf
# expect: (empty)

aws iam list-group-policies \
  --group-name iamws-dev-team \
  --query 'PolicyNames' --output text --profile taractf
# expect: iamws-dev-team-readonly (the original read-only policy only)
```
