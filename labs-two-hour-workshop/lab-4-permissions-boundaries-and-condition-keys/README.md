# Lab 4: Permissions Boundaries & Condition Keys

## Remediate Scenario 1: CreatePolicyVersion — Self-Escalation via Policy Version Manipulation

**Category:** Self-Escalation
**Starting Identity:** `iamws-policy-developer-user`
**Target:** Crown jewels in `s3://iamws-crown-jewels-${ACCOUNT_ID}/flag.txt`

**The Vulnerability:**
- As you saw in the first scenario, `iamws-policy-developer-user` can create new versions of IAM policies — including `iamws-developer-tools-policy`, which is attached to their own user.
- By creating a new version of the `iamws-developer-tools-policy` with administrator permissions and setting it as the default version of the policy, the `iamws-policy-developer-user` can grant themselves full admin access.

In this lab, you will apply defenses to prevent this type of privilege escalation.

### A note on the identities you'll switch between

This is a defense lab, so you spend most of it as your admin identity. Keep this straight as you go (see Lab 1 for the full roster):

| Identity | What it is | When you use it |
| --- | --- | --- |
| `iamws-lab-default` (the **default** profile) | Your admin identity, acting as the defender. It's configured as the default AWS CLI profile, so most commands here carry no `--profile` flag. | Everywhere except the re-tests |
| `iamws-policy-developer-user` | The attacker from Lab 2. | Part B: re-running the Lab 2 exploit to prove the boundary now blocks it |

> [!NOTE]
> The "Additional Controls" section at the end hardens the Scenario 2 role (`iamws-privileged-admin-role`) from Lab 3. You run those steps as the same admin identity — you never switch to `iamws-role-assumer-user` there; you only reference the role by name.

### Part A: Remediate the `CreatePolicyVersion` privesc path by applying a permissions boundary

Run an `iam-recon argquery` command to refresh yourself on the vulnerable permission policy:

```bash
iam-recon --account $ACCOUNT_ID argquery \
  --principal user/iamws-policy-developer-user \
  --action iam:CreatePolicyVersion
```

Expected output:
```
ALLOW user/iamws-policy-developer-user can call iam:CreatePolicyVersion with *
```

> [!NOTE]
> You will not use a `profile` argument for the following commands because you are running all defense steps as your `iamws-lab-default` admin identity which is configured as the default AWS CLI profile.

**Step 0: Reset the attack artifact — restore the original policy version**

In scenario 1, you changed the `iamws-developer-tools-policy` from v1 to v2. For learning purposes, reset the policy to v1 before proceeding, this ensures you are at the same starting point you started from in the first attack.

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
POLICY_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/iamws-developer-tools-policy"

aws iam set-default-policy-version --policy-arn $POLICY_ARN --version-id v1
aws iam delete-policy-version --policy-arn $POLICY_ARN --version-id v2
```

**Step 1: Write a permissions boundary policy**

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
1. **Provides a ceiling for allowed actions for the `iamws-policy-developer-user`.** Even if the user has a `*:*` policy version attached, the boundary caps what they can actually do.
1. **Explicit Deny on escalation actions:** `DenyPrivilegeEscalation` blocks the specific IAM mutations that enabled the self-escalation.
1. **Self-protection:** `iam:DeleteUserPermissionsBoundary` is in the deny list — the user can't remove the permissions boundary itself.

### Part B: Verify the Remediation

**Step 1: Re-run the scenario 1 exploit and confirm the priv esc path is blocked**

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
User: arn:aws:iam::<aws account id>:user/iamws-policy-developer-user
is not authorized to perform: iam:CreatePolicyVersion on resource:
policy arn:aws:iam::<aws account id>:policy/iamws-developer-tools-policy
with an explicit deny in a permissions boundary: arn:aws:iam::<aws account id>:policy/DeveloperBoundary
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
  --query 'EvaluationResults[0].EvalDecision'
```

Expected output:
```
"explicitDeny"
```

The boundary is correctly denying the escalation action.

### What You Learned

- Without additional scoping, `iam:CreatePolicyVersion` allows modifying any policy — including ones attached to your own user. This was the root cause of self-escalation in the first scenario.
- A **permissions boundary** caps effective permissions at the intersection of the identity policy and the boundary, regardless of what a policy attached to the identity grants.
- `Deny` in a boundary overrides any `Allow` in the identity policy — even a `*:*` identity policy is constrained by the boundary.
- Always deny `iam:DeleteUserPermissionsBoundary` (and the role variant) in the boundary itself, so that the user cannot escalate privileges by removing the permissions boundary.
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
        "Principal": { "AWS": "arn:aws:iam::<aws account id>:user/iamws-lab-default" },
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
User: arn:aws:iam::<aws account id>:user/<your-admin-identity>
is not authorized to perform: sts:AssumeRole on resource:
arn:aws:iam::<aws account id>:role/iamws-privileged-admin-role
```

> [!NOTE]
> The admin identity *is* the trusted principal in this trust policy — the principal restriction from Scenario 2 is *not* what blocked this request. The denial comes from the new `aws:MultiFactorAuthPresent` condition: the calling session has no MFA context, so the condition evaluates `false` and the statement doesn't apply.

### What You Learned

- **Condition keys** add per-request context to authorization — `Principal` says *who*, `Action`/`Resource` say *what*, `Condition` says *under what circumstances*.
- `aws:MultiFactorAuthPresent` is a **global condition key**: it's available in every request's context regardless of which service is being called.
- Conditions enable **defense in depth**: layered with principal scoping and resource scoping, a single compromise (such as leaked long-term keys) is no longer sufficient to escalate.

---

**Next:** [Lab 5: Privilege Escalation via iam:PassRole (EC2)](../lab-5-passrole-ec2/README.md)
