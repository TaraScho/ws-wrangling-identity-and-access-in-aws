# Scenario 4 — Cleanup

Run as `iamws-lab-default` (admin) after the defense demo, before the next scenario.

## Restore the Lambda's original code

The attack overwrote `iamws-privileged-lambda`'s code. Restore it via Terraform (the source of truth):

```bash
cd <repo-root>/labs-two-hour-workshop/terraform
terraform apply -target=module.lambda --profile iamws-lab-default
```

If Terraform isn't available locally, restore from a saved pre-attack zip:

```bash
aws lambda update-function-code \
  --function-name iamws-privileged-lambda \
  --zip-file fileb:///tmp/validation/scenario4-original-code.zip \
  --profile iamws-lab-default
```

## Revert the defense

Remove the scoped inline policy and re-attach the original managed policy:

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text --profile iamws-lab-default)

aws iam delete-user-policy \
  --user-name iamws-lambda-developer-user --policy-name SecureLambdaDeveloper --profile iamws-lab-default

aws iam attach-user-policy \
  --user-name iamws-lambda-developer-user \
  --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/iamws-lambda-developer-policy \
  --profile iamws-lab-default
```

## Confirm clean state

```bash
aws iam list-attached-user-policies \
  --user-name iamws-lambda-developer-user \
  --query 'AttachedPolicies[].PolicyName' --output table --profile iamws-lab-default
# expect: iamws-lambda-developer-policy

aws iam list-user-policies \
  --user-name iamws-lambda-developer-user \
  --query 'PolicyNames' --output text --profile iamws-lab-default
# expect: (empty)
```

> [!NOTE]
> After reverting the defense, wait ~60 seconds before the next run — AWS keeps a short-lived permission cache (~3–5 minutes) for Lambda. Without the wait, the original attack still succeeds even with the managed policy back in place.
