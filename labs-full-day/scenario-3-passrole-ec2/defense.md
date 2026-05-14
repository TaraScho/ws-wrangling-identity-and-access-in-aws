# Scenario 3 — Defense bullets (afternoon)

Source: Lab 2 Exercise 3. Pairs with `attack.md` (PassRole + EC2). Control: **`iam:PassedToService` condition** + resource constraint on PassRole.

## Slide intro bullets

- `iam:PassedToService` scopes PassRole to a specific AWS service — the CI runner's PassRole is meant for Lambda, so we condition it on `lambda.amazonaws.com`.
- Also tighten Resource: only the CI runner's own role can be passed, not `*`.
- Three locks now: action limited to `iam:PassRole`, resource limited to the runner's role, condition limited to Lambda — all three must be satisfied.
- iam-recon evaluates `iam:PassedToService` → the EC2 PassRole edge disappears; any legitimate Lambda PassRole edge stays.

## Defense — full command path

```bash
# Step 1: write the new scoped policy (admin/workshop identity)
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

aws iam put-user-policy \
  --user-name iamws-ci-runner-user \
  --policy-name SecurePassRole \
  --policy-document '{
    "Version": "2012-10-17",
    "Statement": [
      {
        "Sid": "AllowPassRoleToLambdaOnly",
        "Effect": "Allow",
        "Action": "iam:PassRole",
        "Resource": "arn:aws:iam::'${ACCOUNT_ID}':role/iamws-ci-runner-role",
        "Condition": {"StringEquals": {"iam:PassedToService": "lambda.amazonaws.com"}}
      },
      {
        "Sid": "AllowEC2Operations",
        "Effect": "Allow",
        "Action": ["ec2:RunInstances","ec2:DescribeInstances","ec2:DescribeImages",
                   "ec2:DescribeSecurityGroups","ec2:DescribeSubnets","ec2:DescribeKeyPairs"],
        "Resource": "*"
      }
    ]
  }'

# Step 2: detach the overly-permissive managed policy
aws iam detach-user-policy \
  --user-name iamws-ci-runner-user \
  --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/iamws-ci-runner-policy 2>/dev/null || true
```

## Verify with simulate-principal-policy (AWS native — kept from original)

```bash
# Legitimate path: pass own role to Lambda → allowed
aws iam simulate-principal-policy \
  --policy-source-arn arn:aws:iam::${ACCOUNT_ID}:user/iamws-ci-runner-user \
  --action-names iam:PassRole \
  --resource-arns arn:aws:iam::${ACCOUNT_ID}:role/iamws-ci-runner-role \
  --context-entries '[{"ContextKeyName":"iam:PassedToService","ContextKeyValues":["lambda.amazonaws.com"],"ContextKeyType":"string"}]' \
  --query 'EvaluationResults[0].EvalDecision'
# expect: "allowed"

# Attack path: pass prod-deploy-role to EC2 → implicit deny
aws iam simulate-principal-policy \
  --policy-source-arn arn:aws:iam::${ACCOUNT_ID}:user/iamws-ci-runner-user \
  --action-names iam:PassRole \
  --resource-arns arn:aws:iam::${ACCOUNT_ID}:role/iamws-prod-deploy-role \
  --context-entries '[{"ContextKeyName":"iam:PassedToService","ContextKeyValues":["ec2.amazonaws.com"],"ContextKeyType":"string"}]' \
  --query 'EvaluationResults[0].EvalDecision'
# expect: "implicitDeny"
```

## Verify with the attack

```bash
# Crown jewels still safe?
aws s3 cp s3://iamws-crown-jewels-${ACCOUNT_ID}/flag.txt - \
  --profile iamws-ci-runner-user
# expect: Forbidden — can't pass a privileged role to EC2 anymore
```

## Verify with iam-recon

- `iam-recon graph create --profile iamws-lab-default`.
- `iam-recon --account $ACCOUNT_ID argquery --preset privesc --principal user/iamws-ci-runner-user` → reports `cannot escalate to admin`; the EC2 PassRole edge to `iamws-prod-deploy-role` is gone. ⚠️ Note: `role/iamws-ci-runner-role` (the role version of the same principal, used for IAM role chaining) still escalates — re-run with `--principal role/iamws-ci-runner-role` to confirm. The defense only put a scoped inline policy on the *user*; the *role* still has the original `iamws-ci-runner-policy` attached. If you want the role's edge to also disappear, apply the same `SecurePassRole` policy to the role and detach the managed policy from the role too.
- `iam-recon --account $ACCOUNT_ID argquery --principal user/iamws-ci-runner-user --action iam:PassRole --resource 'arn:aws:iam::*:role/iamws-prod-deploy-role'` → should now show DENY.
- `iam-recon --account $ACCOUNT_ID pathfinding --principal user/iamws-ci-runner-user` → `[ec2-001]` finding for this user disappears.

## Demo bullets

- Side-by-side `simulate-principal-policy` and `iam-recon query` — two ways to prove the same thing, one online via AWS, one offline via iam-recon's local simulator.
- Highlight: the legitimate Lambda PassRole still works. This is the cleanest example of "scope, don't deny."
- Watch-out: forgetting `iam:PassedToService` on PassRole is one of the top three IAM misconfigs in the wild.
