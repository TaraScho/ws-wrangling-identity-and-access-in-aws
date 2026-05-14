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

In Scenario 2's defense (Part D), you eliminated the `:root` trust by naming the admin principal directly. That alone blocks `iamws-role-assumer-user` from assuming the role, but it leaves one weakness: an attacker who compromises the admin's long-term access keys can assume the role with no additional challenge.

Layer an MFA condition on top of the principal restriction. Now an attacker needs the right identity *and* an active MFA-authenticated session — a defense-in-depth pattern that defeats stolen-key replay.

### Part A: Add the MFA condition to the trust policy

Run all defense steps as your admin identity.

**Step 1: Confirm the starting state of the trust policy**

```bash
aws iam get-role --role-name iamws-privileged-admin-role \
  --query 'Role.AssumeRolePolicyDocument' --output json
```

Expected output (the Scenario 2 defense already restricted the principal — there is no `Condition` block yet):
```json
{
    "Version": "2012-10-17",
    "Statement": [{
        "Effect": "Allow",
        "Principal": { "AWS": "arn:aws:iam::767397689800:user/<your-admin-identity>" },
        "Action": "sts:AssumeRole"
    }]
}
```

**Step 2: Update the trust policy to require MFA**

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ADMIN_ROLE_ARN=$(aws sts get-caller-identity --query Arn --output text)

aws iam update-assume-role-policy \
  --role-name iamws-privileged-admin-role \
  --policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Principal": {"AWS": "'$ADMIN_ROLE_ARN'"},
      "Action": "sts:AssumeRole",
      "Condition": {
        "Bool": { "aws:MultiFactorAuthPresent": "true" }
      }
    }]
  }'
```

What this adds:
1. **Condition keys evaluate per-request context:** `aws:MultiFactorAuthPresent` is a global condition key AWS sets to `true` only when the caller authenticated with MFA in this session.
1. **`Bool` operator matches the key's type:** Using the wrong operator (for example `StringEquals`) silently fails to match — the statement won't apply, and the request falls through to an implicit deny.
1. **Defense in depth:** Layered with the Scenario 2 principal restriction — an attacker would need both the right identity *and* an active MFA session.

### Part B: Verify the Remediation

**Step 1: Attempt to assume the role without MFA — confirm it's blocked**

Run as the admin identity itself (default profile). Long-term access keys carry no MFA context in the session, so the condition fails even though the admin *is* the trusted principal:

```bash
aws sts assume-role \
  --role-arn arn:aws:iam::${ACCOUNT_ID}:role/iamws-privileged-admin-role \
  --role-session-name no-mfa-test
```

Expected output:
```
An error occurred (AccessDenied) when calling the AssumeRole operation:
User: arn:aws:iam::767397689800:user/<your-admin-identity>
is not authorized to perform: sts:AssumeRole on resource:
arn:aws:iam::767397689800:role/iamws-privileged-admin-role
```

> [!NOTE]
> The admin identity *is* the trusted principal in this trust policy — the principal restriction from Scenario 2 is *not* what blocked this request. The denial comes from the new `aws:MultiFactorAuthPresent` condition: the calling session has no MFA context, so the condition evaluates `false` and the statement doesn't apply.

**Step 2: Verify with `simulate-principal-policy`**

Pass `aws:MultiFactorAuthPresent` as a context entry and observe how the decision flips:

```bash
aws iam simulate-principal-policy \
  --policy-source-arn $ADMIN_ROLE_ARN \
  --action-names sts:AssumeRole \
  --resource-arns arn:aws:iam::${ACCOUNT_ID}:role/iamws-privileged-admin-role \
  --context-entries ContextKeyName=aws:MultiFactorAuthPresent,ContextKeyValues=false,ContextKeyType=boolean \
  --query 'EvaluationResults[0].EvalDecision'
```

Expected output:
```
"implicitDeny"
```

Now re-run with the MFA context set to `true`:

```bash
aws iam simulate-principal-policy \
  --policy-source-arn $ADMIN_ROLE_ARN \
  --action-names sts:AssumeRole \
  --resource-arns arn:aws:iam::${ACCOUNT_ID}:role/iamws-privileged-admin-role \
  --context-entries ContextKeyName=aws:MultiFactorAuthPresent,ContextKeyValues=true,ContextKeyType=boolean \
  --query 'EvaluationResults[0].EvalDecision'
```

Expected output:
```
"allowed"
```

> [!NOTE]
> Because we passed `--resource-arns`, the simulator evaluates the role's trust policy (a resource-based policy) against the action — that's how the trust policy condition gets exercised here. `--context-entries` lets you test condition behavior without provisioning a real MFA device.

### What You Learned

- **Condition keys** add per-request context to authorization — `Principal` says *who*, `Action`/`Resource` say *what*, `Condition` says *under what circumstances*.
- `aws:MultiFactorAuthPresent` is a **global condition key**: it's available in every request's context regardless of which service is being called.
- Conditions enable **defense in depth**: layered with principal scoping and resource scoping, a single compromise (such as leaked long-term keys) is no longer sufficient to escalate.
- The companion key `aws:MultiFactorAuthAge` (used with `NumericLessThan`) further bounds *how recently* MFA was performed — useful when long-lived sessions are a risk.
- `simulate-principal-policy` with `--context-entries` lets you validate condition behavior end-to-end without setting up MFA hardware.
