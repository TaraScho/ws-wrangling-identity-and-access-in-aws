## Remediate Scenario 1: CreatePolicyVersion — Self-Escalation via Policy Version Manipulation

**Category:** Self-Escalation
**Starting Identity:** `iamws-policy-developer-user`
**Target:** Crown jewels in `s3://iamws-crown-jewels-${ACCOUNT_ID}/flag.txt`

**The Vulnerability:** `iamws-policy-developer-user` can create new versions of IAM policies — including `iamws-developer-tools-policy`, which is attached to their own user. By creating a new version with administrator permissions and setting it as default, they grant themselves full access without touching any other principal or resource. In lab scenario 1, you exploited this privesc path.

### Part A: Remediate the `CreatePolicyVersion` privesc path by applying a permissions boundary

Run an `iam-recon` pathfinding scan to refresh yourself on the self-escalation privilege escalation path available:

```bash
iam-recon --account $ACCOUNT_ID pathfinding --principal user/iamws-policy-developer-user
```

Look for the `[iam-001] user/iamws-policy-developer-user` entry:
```
[iam-001] user/iamws-policy-developer-user (self-escalation)
    Path: iam:CreatePolicyVersion
    Perms: iam:CreatePolicyVersion
    https://www.pathfinding.cloud/paths/iam-001
```

You can also re-run the `iam-recon argquery` command to confirm the specific permission directly:

```bash
iam-recon --account $ACCOUNT_ID argquery \
  --principal user/iamws-policy-developer-user \
  --action iam:CreatePolicyVersion
```

Expected output:
```
ALLOW user/iamws-policy-developer-user can call iam:CreatePolicyVersion with *
```

Run all defense steps as your admin identity.

**Step 0: Reset the attack artifact — restore the original policy version**

In scenario 1, you changed the `iamws-developer-tools-policy` from v1 to v2. For learning purposes, reset the policy to v1 before proceeding, this ensures you are at the same starting point you started from in the first attack.

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
```

What this boundary does:
1. **Ceiling, not fence:** effective permissions = identity policy boundary. Even if the user creates a `*:*` policy version, the boundary caps what they can actually do.
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
```

Expected output:
```
"explicitDeny"
```

The boundary is correctly denying the escalation action.

### What You Learned

- Without additional scoping, `iam:CreatePolicyVersion` allows modifying any policy — including ones attached to your own user. This was the root cause of self-escalation in the first scenario.
- A **permissions boundary** caps effective permissions at the intersection of the identity policy and the boundary, regardless of what the identity policy grants.
- `Deny` in a boundary overrides any `Allow` in the identity policy — even a `*:*` identity policy is constrained by the boundary.
- Always deny `iam:DeleteUserPermissionsBoundary` (and the role variant) in the boundary itself, or the control is self-removing.
- AWS `simulate-principal-policy` is a great tool to verify boundary-based defenses.

## Additional Controls for Scenario 2: Add Condition Key requiring MFA