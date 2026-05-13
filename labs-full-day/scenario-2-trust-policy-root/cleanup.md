# Scenario 2 — Cleanup

Run as `taractf` (admin) after the defense demo, before the next scenario.

## Revert the defense

Restore the vulnerable `:root` trust policy so the next cohort starts from the intended state:

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text --profile taractf)

aws iam update-assume-role-policy \
  --role-name iamws-privileged-admin-role \
  --policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Principal": {"AWS": "arn:aws:iam::'${ACCOUNT_ID}':root"},
      "Action": "sts:AssumeRole"
    }]
  }' \
  --profile taractf
```

## Attack-side cleanup

Nothing to revert on the attack side — `aws sts assume-role` creates ephemeral session credentials only. They expire automatically and leave no persistent artifact. The attacker's local shell unset the `AWS_*` env vars at the end of the exploit.

## Confirm clean state

Verify the trust policy is back to `:root`:

```bash
aws iam get-role --role-name iamws-privileged-admin-role \
  --query 'Role.AssumeRolePolicyDocument' --output json \
  --profile taractf
```

Expected output:
```json
{
    "Version": "2012-10-17",
    "Statement": [{
        "Effect": "Allow",
        "Principal": { "AWS": "arn:aws:iam::767397689800:root" },
        "Action": "sts:AssumeRole"
    }]
}
```
