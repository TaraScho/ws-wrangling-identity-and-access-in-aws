# Scenario 3 — Cleanup

Run as `taractf` (admin) after the defense demo, before the next scenario.

## Terminate the EC2 instance launched during the attack

```bash
INSTANCE_ID=$(aws ec2 describe-instances \
  --filters \
    "Name=iam-instance-profile.arn,Values=arn:aws:iam::*:instance-profile/iamws-prod-deploy-profile" \
    "Name=instance-state-name,Values=running,pending,stopping,stopped" \
  --query 'Reservations[].Instances[].InstanceId' --output text --profile taractf)

aws ec2 terminate-instances --instance-ids $INSTANCE_ID --profile taractf
```

## Revert the defense

Remove the scoped inline policy and re-attach the original managed policy:

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text --profile taractf)

aws iam delete-user-policy \
  --user-name iamws-ci-runner-user --policy-name SecurePassRole --profile taractf

aws iam attach-user-policy \
  --user-name iamws-ci-runner-user \
  --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/iamws-ci-runner-policy \
  --profile taractf
```

## Confirm clean state

Verify the original managed policy is attached and no inline policy remains:

```bash
aws iam list-attached-user-policies \
  --user-name iamws-ci-runner-user \
  --query 'AttachedPolicies[].PolicyName' --output table --profile taractf
# expect: iamws-ci-runner-policy

aws iam list-user-policies \
  --user-name iamws-ci-runner-user \
  --query 'PolicyNames' --output text --profile taractf
# expect: (empty)
```
