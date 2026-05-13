## Exercise 3: Condition Key for PassRole + EC2

### Recap

In Lab 1 Exercise 5, you launched an EC2 instance with a privileged instance profile because `iamws-ci-runner` had unrestricted `iam:PassRole` (New PassRole). The PassRole was intended for Lambda deployments, but without the `iam:PassedToService` condition it worked for any service — including EC2.

### Understanding iam:PassedToService

The `iam:PassedToService` condition key restricts which AWS service a role can be passed to. Since the CI runner's PassRole is intended for Lambda deployments, we scope it to Lambda:

```json
{
  "Condition": {
    "StringEquals": {
      "iam:PassedToService": "lambda.amazonaws.com"
    }
  }
}
```

This ensures:
- The role can ONLY be passed to Lambda (not EC2, ECS, etc.) — completely blocking the EC2 attack path from Lab 1
- Combined with a resource constraint, you can limit WHICH roles can be passed

### Part A: Create the Restrictive PassRole Policy

We'll use `put-user-policy` to attach an inline policy directly to the CI runner user. This replaces their overly-permissive managed policy with one that has proper guardrails:

```bash
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
        "Condition": {
          "StringEquals": {
            "iam:PassedToService": "lambda.amazonaws.com"
          }
        }
      },
      {
        "Sid": "AllowEC2Operations",
        "Effect": "Allow",
        "Action": [
          "ec2:RunInstances",
          "ec2:DescribeInstances",
          "ec2:DescribeImages",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeSubnets",
          "ec2:DescribeKeyPairs"
        ],
        "Resource": "*"
      }
    ]
  }'
```

**What this policy does — two statements working together:**

- **`AllowPassRoleToLambdaOnly`**: Three restrictions lock down PassRole. The **Action** is limited to just `iam:PassRole` (no other IAM actions). The **Resource** is scoped to only the CI runner's own role — not `*`, so they can't pass arbitrary roles. And the **Condition** key `iam:PassedToService` restricts the target to `lambda.amazonaws.com` only. All three must be satisfied for the action to succeed.
- **`AllowEC2Operations`**: The user still has EC2 permissions for legitimate work (launching instances, describing resources). But without PassRole to EC2, they can't attach a privileged instance profile — the attack path from Lab 1 Exercise 5 is completely blocked.

### Part B: Remove the Overly-Permissive Policy

Now we detach the original managed policy. That policy had `Resource: "*"` on PassRole and no `iam:PassedToService` condition key — exactly what made the Lab 1 attack possible. The new inline policy from Part A replaces it with properly scoped permissions.

```bash
# Detach the original vulnerable policy
aws iam detach-user-policy \
  --user-name iamws-ci-runner-user \
  --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/iamws-ci-runner-policy 2>/dev/null || true
```

### Part C: Verify the Remediation

`simulate-principal-policy` is an IAM "what-if" tool — it evaluates whether a given principal would be allowed or denied a specific action, without actually performing it. Think of it as a dry-run for IAM permissions.

**Why we use it here:** We need to confirm the remediation works before moving on. Rather than trying the attack again as the CI runner, we can test specific action + resource + condition combinations from an admin context.

**How to read the parameters:**

1. `--policy-source-arn` — the principal whose policies we're evaluating
1. `--action-names` — the API action to simulate
1. `--resource-arns` — the target resource
1. `--context-entries` — condition key values to include in the simulation (like `iam:PassedToService`)

> **Note:** This command requires `iam:SimulatePrincipalPolicy` permission, so we run it as admin (your default profile) while simulating what the CI runner **user** can do.

First, confirm the legitimate use case still works — the CI runner can pass their own role to Lambda:

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

aws iam simulate-principal-policy \
  --policy-source-arn arn:aws:iam::${ACCOUNT_ID}:user/iamws-ci-runner-user \
  --action-names iam:PassRole \
  --resource-arns arn:aws:iam::${ACCOUNT_ID}:role/iamws-ci-runner-role \
  --context-entries '[{"ContextKeyName":"iam:PassedToService","ContextKeyValues":["lambda.amazonaws.com"],"ContextKeyType":"string"}]' \
  --query 'EvaluationResults[0].EvalDecision'
```

**Expected result:** `"allowed"` — the CI runner can still pass their own role to Lambda, which is the legitimate use case.

Now verify the attack path is blocked — the CI runner cannot pass a privileged role to EC2:

```bash
aws iam simulate-principal-policy \
  --policy-source-arn arn:aws:iam::${ACCOUNT_ID}:user/iamws-ci-runner-user \
  --action-names iam:PassRole \
  --resource-arns arn:aws:iam::${ACCOUNT_ID}:role/iamws-prod-deploy-role \
  --context-entries '[{"ContextKeyName":"iam:PassedToService","ContextKeyValues":["ec2.amazonaws.com"],"ContextKeyType":"string"}]' \
  --query 'EvaluationResults[0].EvalDecision'
```

**Expected result:** `"implicitDeny"` — the CI runner cannot pass any role to EC2, so the attack path from Lab 1 is blocked.

**Verify the crown jewels are still protected:**

```bash
aws s3 cp s3://iamws-crown-jewels-${ACCOUNT_ID}/flag.txt - \
  --profile iamws-ci-runner-user
```

**Expected:** `Forbidden` — the CI runner can no longer pass a privileged role to EC2, so the crown jewels remain safe.

### What You Learned

- `iam:PassedToService` is **essential** for any PassRole permission
- Combine condition keys with **resource constraints** for defense-in-depth
- PassRole should specify WHICH roles can be passed, not `Resource: "*"`
- Always ask: "What's the minimum set of roles this principal needs to pass?"

---

**Next:** [Exercise 4: Resource Constraint for UpdateFunctionCode](exercise-4.md) — Restrict Lambda function access by ARN pattern
