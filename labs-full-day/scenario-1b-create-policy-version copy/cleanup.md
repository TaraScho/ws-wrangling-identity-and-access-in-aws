# Scenario 1 — Cleanup

Run as `iamws-lab-default` (admin) after the defense demo, before the next scenario.

## Revert the attack artifact

Restore the original policy version and remove the escalated v2:

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text --profile iamws-lab-default)
POLICY_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/iamws-developer-tools-policy"

aws iam set-default-policy-version --policy-arn $POLICY_ARN --version-id v1 --profile iamws-lab-default
aws iam delete-policy-version --policy-arn $POLICY_ARN --version-id v2 --profile iamws-lab-default
```

## Revert the defense

Remove the permissions boundary from the user and role, then delete the boundary policy:

```bash
aws iam delete-user-permissions-boundary \
  --user-name iamws-policy-developer-user --profile iamws-lab-default

aws iam delete-role-permissions-boundary \
  --role-name iamws-policy-developer-role --profile iamws-lab-default

aws iam delete-policy \
  --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/DeveloperBoundary --profile iamws-lab-default
```

## Confirm clean state

Verify the policy is back to v1 and no boundary is attached:

```bash
aws iam get-policy \
  --policy-arn $POLICY_ARN \
  --query 'Policy.DefaultVersionId' --output text --profile iamws-lab-default
# expect: v1

aws iam get-user --user-name iamws-policy-developer-user \
  --query 'User.PermissionsBoundary' --output text --profile iamws-lab-default
# expect: None
```
