## Exercise 1: Permissions Boundary for CreatePolicyVersion

### Recap

In Lab 1 Exercise 3, you exploited `iamws-policy-developer-user` to create an admin policy version attached to themselves (Self-Escalation via `iam:CreatePolicyVersion`). The root cause: can modify a policy that grants your own permissions.

### Understanding Permissions Boundaries

**Why resource constraints don't fully fix this:** Even if you restrict which policies can be modified, if the user can modify ANY policy attached to themselves, they can remove those restrictions and escalate. That's why this vulnerability needs a permissions boundary — a fundamentally different kind of control.

A permissions boundary is a **ceiling** on what permissions an IAM principal can have. Even if a user modifies their own policy to grant `*:*`, the boundary limits what they can actually do.

```
┌─────────────────────────────────────────┐
│  Identity Policy                        │  ← "What I want to allow"
│  (Modified to *:*)                      │
├─────────────────────────────────────────┤
│  Permissions Boundary                   │  ← "Maximum I can have"
│  (DeveloperBoundary)                    │
├─────────────────────────────────────────┤
│  EFFECTIVE PERMISSIONS                  │  ← Intersection of both
│  (Only actions in BOTH)                 │
└─────────────────────────────────────────┘
```

**Key insight:** The boundary doesn't grant permissions—it only restricts them. If the boundary doesn't allow `iam:*`, the user can't use IAM admin permissions even if their identity policy allows it.

### Part A: Create the Permissions Boundary Policy

1. **Create a boundary policy file** (`boundary-policy.json`):
   ```json
   {
     "Version": "2012-10-17",
     "Statement": [
       {
         "Sid": "AllowDeveloperActions",
         "Effect": "Allow",
         "Action": [
           "s3:*",
           "ec2:Describe*",
           "lambda:List*",
           "lambda:Get*",
           "logs:*",
           "cloudwatch:*"
         ],
         "Resource": "*"
       },
       {
         "Sid": "AllowLimitedIAMRead",
         "Effect": "Allow",
         "Action": [
           "iam:Get*",
           "iam:List*"
         ],
         "Resource": "*"
       },
       {
         "Sid": "DenyPrivilegeEscalation",
         "Effect": "Deny",
         "Action": [
           "iam:CreatePolicyVersion",
           "iam:SetDefaultPolicyVersion",
           "iam:AttachUserPolicy",
           "iam:AttachRolePolicy",
           "iam:PutUserPolicy",
           "iam:PutRolePolicy",
           "iam:CreateUser",
           "iam:CreateRole",
           "iam:CreateAccessKey",
           "iam:UpdateAssumeRolePolicy",
           "iam:DeleteUserPermissionsBoundary",
           "iam:DeleteRolePermissionsBoundary"
         ],
         "Resource": "*"
       }
     ]
   }
   ```

   **Note the explicit denies:** These block privilege escalation actions regardless of identity policy permissions.

1. **Create the policy in IAM:**
   ```bash
   ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

   aws iam create-policy \
     --policy-name DeveloperBoundary \
     --policy-document file://boundary-policy.json \
     --description "Permissions boundary that prevents privilege escalation"
   ```

### Part B: Apply the Boundary

Apply the boundary to both the user and the role:

```bash
# Apply to the user
aws iam put-user-permissions-boundary \
  --user-name iamws-policy-developer-user \
  --permissions-boundary arn:aws:iam::${ACCOUNT_ID}:policy/DeveloperBoundary

# Apply to the role
aws iam put-role-permissions-boundary \
  --role-name iamws-policy-developer-role \
  --permissions-boundary arn:aws:iam::${ACCOUNT_ID}:policy/DeveloperBoundary
```

### Part C: Verify the Remediation

Now test that the attack is blocked:

```bash
# Try the same attack as lab 01
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text \
  --profile iamws-policy-developer-user)
POLICY_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/iamws-developer-tools-policy"

aws iam create-policy-version \
  --policy-arn $POLICY_ARN \
  --policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":"*","Resource":"*"}]}' \
  --set-as-default \
  --profile iamws-policy-developer-user
```

**Expected result:**
```
An error occurred (AccessDenied) when calling the CreatePolicyVersion operation: User: arn:aws:iam::072054739058:user/iamws-policy-developer-user is not authorized to perform: iam:CreatePolicyVersion on resource: policy arn:aws:iam::072054739058:policy/iamws-developer-tools-policy with an explicit deny in a permissions boundary: arn:aws:iam::072054739058:policy/DeveloperBoundary
```

**The attack is blocked!** The boundary explicitly denies `iam:CreatePolicyVersion`.

### What You Learned

- Permissions boundaries cap effective permissions regardless of identity policies
- The `Deny` in a boundary overrides any `Allow` in identity policies
- Boundaries are a great control for self-escalation attacks
- Always deny `DeleteUserPermissionsBoundary` and `DeleteRolePermissionsBoundary` in the boundary itself

---

**Next:** [Exercise 2: Harden Trust Policy for AssumeRole](exercise-2.md) — Restrict trust policy to specific principals with MFA
