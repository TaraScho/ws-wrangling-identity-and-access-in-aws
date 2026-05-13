# Scenario 1 — Defense bullets (afternoon)

Source: Lab 2 Exercise 1. Pairs with `attack.md` (CreatePolicyVersion self-escalation). Control: **permissions boundary** (a ceiling, not a fence).

## Slide intro bullets

- Resource constraints alone don't fix self-escalation — if the user can modify *any* policy attached to themselves, they can remove the constraint.
- A permissions boundary caps **effective** permissions: `effective = identity_policy ∩ boundary`. Explicit `Deny` in the boundary overrides any `Allow` in the identity policy.
- ⚠️ **iam-recon does NOT evaluate permissions boundaries in `argquery`/`pathfinding`** (verified 2026-05-12 — boundary is collected into the graph but not applied during query). Verify this defense with AWS `simulate-principal-policy` (returns `explicitDeny`) or by re-running the attack as the attacker user (AWS returns `AccessDenied with an explicit deny in a permissions boundary`).

## Defense — full command path

```bash
# Step 0: undo the prior attack's escalation — the boundary blocks NEW CreatePolicyVersion calls,
#         but the v2 admin policy created during the attack is still default and still grants the
#         user s3:* (boundary's AllowDeveloperActions also permits s3:*). Reset to v1 first.
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
POLICY_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/iamws-developer-tools-policy"
aws iam set-default-policy-version --policy-arn $POLICY_ARN --version-id v1
aws iam delete-policy-version --policy-arn $POLICY_ARN --version-id v2

# Step 1: write the boundary policy (run as your admin/workshop identity, NOT as the attacker user)
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

# Step 2: create the boundary policy
aws iam create-policy \
  --policy-name DeveloperBoundary \
  --policy-document file:///tmp/boundary-policy.json \
  --description "Permissions boundary that prevents privilege escalation"

# Step 3: apply boundary to the user and role
aws iam put-user-permissions-boundary \
  --user-name iamws-policy-developer-user \
  --permissions-boundary arn:aws:iam::${ACCOUNT_ID}:policy/DeveloperBoundary

aws iam put-role-permissions-boundary \
  --role-name iamws-policy-developer-role \
  --permissions-boundary arn:aws:iam::${ACCOUNT_ID}:policy/DeveloperBoundary
```

## Verify with the attack

```bash
# Re-run the original exploit as the attacker user
POLICY_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/iamws-developer-tools-policy"
aws iam create-policy-version \
  --policy-arn $POLICY_ARN \
  --policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":"*","Resource":"*"}]}' \
  --set-as-default \
  --profile iamws-policy-developer-user
# expect: AccessDenied — explicit deny in permissions boundary

# Crown jewels still safe?
aws s3 cp s3://iamws-crown-jewels-${ACCOUNT_ID}/flag.txt - \
  --profile iamws-policy-developer-user
# expect: AccessDenied
```

## Verify with iam-recon

- `iam-recon graph create --profile taractf` (re-scan with the new boundary).
- ⚠️ **iam-recon does NOT evaluate permissions boundaries in `argquery` or `pathfinding`** despite collecting them correctly into the cached graph. Verified live on 2026-05-12: with the boundary applied and AWS returning `explicitDeny`, iam-recon still reports `ALLOW user/iamws-policy-developer-user can call iam:CreatePolicyVersion with *` and the `[iam-001]` pathfinding row is unchanged. The cached `nodes.json` has the boundary attached; the local policy evaluator just doesn't apply it in the codepath argquery uses.
- **Use AWS `simulate-principal-policy` as the verification surface** for this scenario (it correctly returns `explicitDeny`):
  ```bash
  aws iam simulate-principal-policy \
    --policy-source-arn arn:aws:iam::${ACCOUNT_ID}:user/iamws-policy-developer-user \
    --action-names iam:CreatePolicyVersion \
    --query 'EvaluationResults[0].EvalDecision' \
    --profile taractf
  # expect: "explicitDeny"
  ```
- Re-running the attack as the attacker user (block above) is the other clean verification — `CreatePolicyVersion` returns `AccessDenied with an explicit deny in a permissions boundary`.
- In the interactive viz, the `iamws-policy-developer-user` node was **already blue** before the defense (no CreatePolicyVersion edge checker exists in iam-recon, so the user was never colored Privesc). The bullet's "orange → blue" prediction is wrong; the bullet should be removed or replaced with "the viz coloring is unchanged because iam-recon doesn't catch this attack family on either side."

## Demo bullets

- Side-by-side AWS `simulate-principal-policy` before (`allowed`) and after (`explicitDeny`). Pathfinding row does NOT vanish — iam-recon doesn't apply the boundary during query.
- Highlight: `Deny` in the boundary overrides any `Allow` in the identity policy — even if the user *could* modify their own policy, the boundary blocks the action at evaluation time.
- Watch-out: always deny `iam:DeleteUserPermissionsBoundary` in the boundary itself (otherwise the boundary is removable, defeating the whole control).
