# Lab 2 - Fencin' the Frontier: Remediating IAM Misconfigurations

**Duration:** 45 minutes

## Overview

In Lab 1, you exploited six privilege escalation vulnerabilities—each with a different root cause. Now you'll learn how to prevent them using AWS IAM guardrails. Each exercise follows the pattern: **Recap → Remediate → Verify**.

**What You'll Learn:**
- How **permissions boundaries** cap effective permissions (even for users who can modify their own policies)
- How **trust policies** (resource policies) control who can assume roles
- How **condition keys** (`iam:PassedToService`) restrict PassRole to specific services
- How **resource constraints** limit which resources can be modified (Lambda ARNs and group ARNs)
- Why **Secrets Manager** is essential for credential management

**Why This Matters:**
Finding vulnerabilities is only half the battle. Knowing how to fix them—and understanding which guardrail applies to which attack—is essential for building secure cloud infrastructure.

---

## Prerequisites

- Completed Lab 1 (you understand the six vulnerabilities)
- AWS CLI configured with admin credentials for applying remediations
- Terraform infrastructure still deployed

---

## The Six Guardrails

Before diving into the exercises, here's a preview of the guardrails we'll apply:

| Vulnerability | Category | Root Cause | Guardrail | Defense Type |
|---------------|----------|------------|-----------|--------------|
| CreatePolicyVersion | Self-Escalation | Can modify own attached policy | **Permissions Boundary** | Permissions Boundary |
| AssumeRole | Principal Access | Trust policy trusts :root | **Harden Trust Policy** | Resource Policy |
| PassRole + EC2 | New PassRole | Missing condition key | **iam:PassedToService** | Condition Key |
| UpdateFunctionCode | Existing PassRole | Can modify any Lambda | **Resource Constraint** | Identity Policy |
| GetFunctionConfiguration | Credential Access | Secrets in plaintext | **Secrets Manager** | Best Practice |
| PutGroupPolicy | Self-Escalation | PutGroupPolicy on own group | **Resource Constraint** | Identity Policy |

---

## Exercise 1: Permissions Boundary for CreatePolicyVersion

### Recap

In Lab 1 Exercise 3, you exploited `iamws-policy-developer-user` to create an admin policy version attached to themselves (Self-Escalation via `iam:CreatePolicyVersion`). The root cause: can modify a policy that grants your own permissions.

### Understanding Permissions Boundaries

**Why resource constraints don't fully fix this:** Even if you restrict which policies can be modified, if the user can modify ANY policy attached to themselves, they can escalate. That's why this vulnerability needs a permissions boundary — a fundamentally different kind of control.

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
# Try the attack as the vulnerable user
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
An error occurred (AccessDenied) when calling the CreatePolicyVersion operation:
User: arn:aws:iam::ACCOUNT_ID:user/iamws-policy-developer-user
is not authorized to perform: iam:CreatePolicyVersion on resource:
policy arn:aws:iam::ACCOUNT_ID:policy/iamws-developer-tools-policy
with an explicit deny in a permissions boundary
```

**The attack is blocked!** The boundary explicitly denies `iam:CreatePolicyVersion`.

### What You Learned

- Permissions boundaries cap effective permissions regardless of identity policies
- The `Deny` in a boundary overrides any `Allow` in identity policies
- Boundaries are essential for self-escalation attacks—they're the **only** control that works when users can modify their own attached policies
- Always deny `DeleteUserPermissionsBoundary` and `DeleteRolePermissionsBoundary` in the boundary itself

---

## Exercise 2: Harden Trust Policy for AssumeRole

### Recap

In Lab 1 Exercise 4, you exploited `iamws-privileged-admin-role` because its trust policy trusted `:root` — letting any principal assume it (Principal Access). The root cause: trust policy uses `:root` instead of specific principals.

### Understanding Trust Policies

Trust policies ARE resource policies—they're attached to the role itself (not to the caller). They control WHO can assume the role:

```
┌─────────────────────────────────────────┐
│  Caller's Identity Policy               │
│  "sts:AssumeRole" with Resource: "*"    │
├─────────────────────────────────────────┤
│  Role's Trust Policy (Resource Policy)  │
│  Who is allowed to assume this role?    │
├─────────────────────────────────────────┤
│  RESULT                                 │
│  Both must allow for assume to succeed  │
└─────────────────────────────────────────┘
```

The trust policy is the **defense**—by restricting who it trusts, you control who can become that role.

### Part A: Examine the Current Trust Policy

```bash
aws iam get-role --role-name iamws-privileged-admin-role \
  --query 'Role.AssumeRolePolicyDocument' --output json
```

You'll see:
```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "AWS": "arn:aws:iam::ACCOUNT_ID:root" },
    "Action": "sts:AssumeRole"
  }]
}
```

**The problem:** `:root` means "any principal in this account can assume this role if their identity policy allows `sts:AssumeRole`."

### Part B: Harden the Trust Policy

Update the trust policy to only allow specific, authorized principals:

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Get the ARN of the principal that SHOULD be allowed (e.g., your admin role)
ADMIN_ROLE_ARN=$(aws sts get-caller-identity --query Arn --output text)

aws iam update-assume-role-policy \
  --role-name iamws-privileged-admin-role \
  --policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Principal": {
        "AWS": "'$ADMIN_ROLE_ARN'"
      },
      "Action": "sts:AssumeRole",
      "Condition": {
        "Bool": {
          "aws:MultiFactorAuthPresent": "true"
        }
      }
    }]
  }'
```

**What we changed:**
1. **Specific principal:** Only your admin role can assume it (not anyone in the account)
1. **MFA condition:** Requires MFA for additional security

### Part C: Verify the Remediation

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text \
  --profile iamws-role-assumer-user)

# Try to assume the privileged role
aws sts assume-role \
  --role-arn arn:aws:iam::${ACCOUNT_ID}:role/iamws-privileged-admin-role \
  --role-session-name escalated \
  --profile iamws-role-assumer-user
```

**Expected result:**
```
An error occurred (AccessDenied) when calling the AssumeRole operation:
User: arn:aws:iam::ACCOUNT_ID:user/iamws-role-assumer-user
is not authorized to perform: sts:AssumeRole on resource:
arn:aws:iam::ACCOUNT_ID:role/iamws-privileged-admin-role
```

**The attack is blocked!** The hardened trust policy doesn't trust the attacker.

### What You Learned

- Trust policies using `:root` are dangerously permissive—they trust EVERYONE in the account
- Always use **specific principal ARNs** in trust policies
- Add **conditions** (like MFA) for additional security on sensitive roles
- Trust policies are the first line of defense for role assumption

---

## Exercise 3: Condition Key for PassRole + EC2

### Recap

In Lab 1 Exercise 5, you launched an EC2 instance with a privileged instance profile because `iamws-ci-runner` had unrestricted `iam:PassRole` (New PassRole). The PassRole was intended for Lambda deployments, but without the `iam:PassedToService` condition it worked for any service — including EC2.

### Understanding iam:PassedToService

The `iam:PassedToService` condition key restricts which AWS service a role can be passed to. Since the CI runner's PassRole is intended for Lambda deployments, we scope it to Lambda:

```json
{
  "Condition": {
    "StringEquals": {
      "iam:PassedToService": "lambda.amazonaws.com"
    }
  }
}
```

This ensures:
- The role can ONLY be passed to Lambda (not EC2, ECS, etc.) — completely blocking the EC2 attack path from Lab 1
- Combined with a resource constraint, you can limit WHICH roles can be passed

### Part A: Create the Restrictive PassRole Policy

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

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
        "Condition": {
          "StringEquals": {
            "iam:PassedToService": "lambda.amazonaws.com"
          }
        }
      },
      {
        "Sid": "AllowEC2Operations",
        "Effect": "Allow",
        "Action": [
          "ec2:RunInstances",
          "ec2:DescribeInstances",
          "ec2:DescribeImages",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeSubnets",
          "ec2:DescribeKeyPairs"
        ],
        "Resource": "*"
      }
    ]
  }'

# Also apply to the role
aws iam put-role-policy \
  --role-name iamws-ci-runner-role \
  --policy-name SecurePassRole \
  --policy-document '{
    "Version": "2012-10-17",
    "Statement": [
      {
        "Sid": "AllowPassRoleToLambdaOnly",
        "Effect": "Allow",
        "Action": "iam:PassRole",
        "Resource": "arn:aws:iam::'${ACCOUNT_ID}':role/iamws-ci-runner-role",
        "Condition": {
          "StringEquals": {
            "iam:PassedToService": "lambda.amazonaws.com"
          }
        }
      },
      {
        "Sid": "AllowEC2Operations",
        "Effect": "Allow",
        "Action": [
          "ec2:RunInstances",
          "ec2:DescribeInstances",
          "ec2:DescribeImages",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeSubnets",
          "ec2:DescribeKeyPairs"
        ],
        "Resource": "*"
      }
    ]
  }'
```

### Part B: Remove the Overly-Permissive Policy

```bash
# Detach the original vulnerable policy
aws iam detach-user-policy \
  --user-name iamws-ci-runner-user \
  --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/iamws-ci-runner-policy 2>/dev/null || true

aws iam detach-role-policy \
  --role-name iamws-ci-runner-role \
  --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/iamws-ci-runner-policy 2>/dev/null || true
```

### Part C: Verify the Remediation

We use `simulate-principal-policy` to test the user's effective permissions. This command requires `iam:SimulatePrincipalPolicy` permission, so we run it as admin (your default profile) while simulating what the CI runner **user** can do:

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Verify: Can pass their own role to Lambda (should work)
echo "Testing: Can iamws-ci-runner-user pass iamws-ci-runner-role to Lambda?"
aws iam simulate-principal-policy \
  --policy-source-arn arn:aws:iam::${ACCOUNT_ID}:user/iamws-ci-runner-user \
  --action-names iam:PassRole \
  --resource-arns arn:aws:iam::${ACCOUNT_ID}:role/iamws-ci-runner-role \
  --context-entries '[{"ContextKeyName":"iam:PassedToService","ContextKeyValues":["lambda.amazonaws.com"],"ContextKeyType":"string"}]' \
  --query 'EvaluationResults[0].EvalDecision'

# Verify: Cannot pass any role to EC2 (should fail — the attack path is blocked)
echo "Testing: Can iamws-ci-runner-user pass iamws-prod-deploy-role to EC2? (should fail)"
aws iam simulate-principal-policy \
  --policy-source-arn arn:aws:iam::${ACCOUNT_ID}:user/iamws-ci-runner-user \
  --action-names iam:PassRole \
  --resource-arns arn:aws:iam::${ACCOUNT_ID}:role/iamws-prod-deploy-role \
  --context-entries '[{"ContextKeyName":"iam:PassedToService","ContextKeyValues":["ec2.amazonaws.com"],"ContextKeyType":"string"}]' \
  --query 'EvaluationResults[0].EvalDecision'
```

**Expected result:**
- First query: `"allowed"` (can pass their own role to Lambda — the legitimate use case)
- Second query: `"implicitDeny"` (cannot pass any role to EC2 — the attack path is blocked)

### What You Learned

- `iam:PassedToService` is **essential** for any PassRole permission
- Combine condition keys with **resource constraints** for defense-in-depth
- PassRole should specify WHICH roles can be passed, not `Resource: "*"`
- Always ask: "What's the minimum set of roles this principal needs to pass?"

---

## Exercise 4: Resource Constraint for UpdateFunctionCode

### Recap

In Lab 1 Exercise 6, you hijacked `iamws-privileged-lambda` by replacing its code with a credential-exfiltration payload (Existing PassRole via `lambda:UpdateFunctionCode`). The root cause: `Resource: "*"` allowed modifying any Lambda.

### Understanding Resource Constraints

The fix is simple: restrict which Lambda functions the developer can modify:

```json
{
  "Resource": "arn:aws:lambda:*:*:function:dev-*"
}
```

This allows updating only functions whose names start with `dev-`.

### Part A: Create the Restrictive Policy

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

aws iam put-user-policy \
  --user-name iamws-lambda-developer-user \
  --policy-name SecureLambdaDeveloper \
  --policy-document '{
    "Version": "2012-10-17",
    "Statement": [
      {
        "Sid": "AllowLambdaCodeUpdateDevOnly",
        "Effect": "Allow",
        "Action": [
          "lambda:UpdateFunctionCode",
          "lambda:InvokeFunction"
        ],
        "Resource": "arn:aws:lambda:*:'${ACCOUNT_ID}':function:dev-*"
      },
      {
        "Sid": "AllowLambdaReadAll",
        "Effect": "Allow",
        "Action": [
          "lambda:GetFunction",
          "lambda:ListFunctions"
        ],
        "Resource": "*"
      }
    ]
  }'

# Also apply to the role
aws iam put-role-policy \
  --role-name iamws-lambda-developer-role \
  --policy-name SecureLambdaDeveloper \
  --policy-document '{
    "Version": "2012-10-17",
    "Statement": [
      {
        "Sid": "AllowLambdaCodeUpdateDevOnly",
        "Effect": "Allow",
        "Action": [
          "lambda:UpdateFunctionCode",
          "lambda:InvokeFunction"
        ],
        "Resource": "arn:aws:lambda:*:'${ACCOUNT_ID}':function:dev-*"
      },
      {
        "Sid": "AllowLambdaReadAll",
        "Effect": "Allow",
        "Action": [
          "lambda:GetFunction",
          "lambda:ListFunctions"
        ],
        "Resource": "*"
      }
    ]
  }'
```

### Part B: Remove the Overly-Permissive Policy

```bash
aws iam detach-user-policy \
  --user-name iamws-lambda-developer-user \
  --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/iamws-lambda-developer-policy 2>/dev/null || true

aws iam detach-role-policy \
  --role-name iamws-lambda-developer-role \
  --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/iamws-lambda-developer-policy 2>/dev/null || true
```

### Part C: Verify the Remediation

```bash
# Try to update the privileged Lambda (should fail)
echo "Testing: Can update iamws-privileged-lambda? (should fail)"
aws lambda update-function-code \
  --function-name iamws-privileged-lambda \
  --zip-file fileb:///dev/null \
  --profile iamws-lambda-developer-user 2>&1 | head -3
```

**Expected result:**
```
An error occurred (AccessDeniedException) when calling the UpdateFunctionCode operation:
User: arn:aws:iam::ACCOUNT_ID:user/iamws-lambda-developer-user
is not authorized to perform: lambda:UpdateFunctionCode on resource:
arn:aws:lambda:us-east-1:ACCOUNT_ID:function:iamws-privileged-lambda
```

**The attack is blocked!** The developer can only update `dev-*` functions.

### What You Learned

- **Resource constraints** are the primary defense for "Existing PassRole" attacks
- Use naming conventions (like `dev-*`, `prod-*`) to enable resource-based access control
- Read permissions can be broader than write permissions
- Always ask: "What's the minimum set of resources this principal needs to modify?"

---

## Exercise 5: Secrets Manager for Credential Access

### Recap

In Lab 1 Exercise 7, you read plaintext secrets from Lambda environment variables using `lambda:GetFunctionConfiguration` (Credential Access). The root cause: secrets stored in env vars instead of a proper secrets manager.

### Understanding the Problem

Lambda environment variables are NOT secure storage:
- Anyone with `lambda:GetFunctionConfiguration` can read them
- They're visible in the AWS Console
- They may appear in logs

**The fix isn't an IAM policy change—it's architectural:**
1. Store secrets in AWS Secrets Manager
1. Grant the Lambda role permission to read specific secrets
1. Retrieve secrets at runtime in the Lambda code

### Part A: Create a Secret in Secrets Manager

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Create the secret
aws secretsmanager create-secret \
  --name iamws-app-secrets \
  --description "Secrets for the app Lambda function" \
  --secret-string '{
    "DB_HOST": "prod-db.example.internal",
    "DB_USERNAME": "app_service_account",
    "DB_PASSWORD": "SuperSecretPassword123!",
    "API_KEY": "sk-prod-api-key-do-not-expose"
  }'
```

### Part B: Grant the Lambda Role Access to the Secret

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Add a policy to the Lambda's execution role
aws iam put-role-policy \
  --role-name iamws-app-lambda-role \
  --policy-name SecretsManagerAccess \
  --policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue"
      ],
      "Resource": "arn:aws:secretsmanager:us-east-1:'${ACCOUNT_ID}':secret:iamws-app-secrets*"
    }]
  }'
```

### Part C: Update the Lambda to Use Secrets Manager

The Lambda code should look like this:

```python
import boto3
import json
import os

def get_secret():
    secret_name = "iamws-app-secrets"
    region_name = "us-east-1"

    session = boto3.session.Session()
    client = session.client(
        service_name='secretsmanager',
        region_name=region_name
    )

    response = client.get_secret_value(SecretId=secret_name)
    return json.loads(response['SecretString'])

def handler(event, context):
    # Secrets retrieved at runtime, not stored in env vars
    secrets = get_secret()
    db_password = secrets['DB_PASSWORD']

    # Use the secret to connect to the database...
    return {
        'statusCode': 200,
        'body': 'Connected to database successfully'
    }
```

### Part D: Remove Secrets from Environment Variables

```bash
# Update the Lambda to remove env vars
aws lambda update-function-configuration \
  --function-name iamws-app-with-secrets \
  --environment '{"Variables":{}}'
```

### Part E: Verify the Remediation

```bash
# Try to read secrets from the Lambda env vars
echo "Testing: Can read secrets from Lambda env vars?"
aws lambda get-function-configuration \
  --function-name iamws-app-with-secrets \
  --query 'Environment.Variables' \
  --output json \
  --profile iamws-secrets-reader-user

# Try to read the secret from Secrets Manager
echo "Testing: Can read from Secrets Manager directly?"
aws secretsmanager get-secret-value \
  --secret-id iamws-app-secrets \
  --profile iamws-secrets-reader-user 2>&1 | head -3
```

**Expected results:**
1. Lambda env vars: `{}` or `null` (no secrets)
1. Secrets Manager: `AccessDeniedException` (the reader doesn't have `secretsmanager:GetSecretValue`)

**The attack is blocked!** Secrets are now:
- Not visible via `GetFunctionConfiguration`
- Only accessible to the Lambda's execution role
- Not readable by users with Lambda read permissions

### What You Learned

- Lambda environment variables are **not secure**—use Secrets Manager
- Secrets Manager provides:
  - Fine-grained access control (specific secret ARNs)
  - Automatic rotation
  - Encryption at rest
  - Audit logging
- The fix is **architectural**, not just an IAM policy change
- "Credential Access" vulnerabilities require moving secrets to proper storage

---

## Exercise 6: Resource Constraint for PutGroupPolicy

### Recap

In Lab 1 Exercise 2, you exploited `iamws-group-admin-user` to write an admin inline policy on `iamws-dev-team` — a group the attacker belongs to (Self-Escalation via `iam:PutGroupPolicy`). The root cause: `Resource: "*"` allowed writing inline policies on any group, including the attacker's own.

### Understanding the Fix

This is the same principle as Exercise 4's resource constraint, applied to group ARNs instead of Lambda ARNs. By restricting `iam:PutGroupPolicy` to only specific groups that the principal is **not** a member of, you prevent the self-escalation path.

The key insight: `iamws-group-admin-user` is a member of `iamws-dev-team` but **not** a member of `iamws-platform-team`. If we restrict `PutGroupPolicy` to only `iamws-platform-team`, the attacker can still manage group policies for that team — but can't escalate their own permissions.

### Part A: Create the Restrictive Policy

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Apply restrictive inline policy to the user
aws iam put-user-policy \
  --user-name iamws-group-admin-user \
  --policy-name SecureGroupAdmin \
  --policy-document '{
    "Version": "2012-10-17",
    "Statement": [
      {
        "Sid": "AllowPutGroupPolicyOnPlatformTeamOnly",
        "Effect": "Allow",
        "Action": "iam:PutGroupPolicy",
        "Resource": "arn:aws:iam::'${ACCOUNT_ID}':group/iamws-platform-team"
      },
      {
        "Sid": "AllowGroupEnumeration",
        "Effect": "Allow",
        "Action": [
          "iam:ListGroups",
          "iam:ListGroupPolicies",
          "iam:GetGroupPolicy",
          "iam:ListGroupsForUser",
          "iam:GetGroup"
        ],
        "Resource": "*"
      }
    ]
  }'

# Also apply to the role
aws iam put-role-policy \
  --role-name iamws-group-admin-role \
  --policy-name SecureGroupAdmin \
  --policy-document '{
    "Version": "2012-10-17",
    "Statement": [
      {
        "Sid": "AllowPutGroupPolicyOnPlatformTeamOnly",
        "Effect": "Allow",
        "Action": "iam:PutGroupPolicy",
        "Resource": "arn:aws:iam::'${ACCOUNT_ID}':group/iamws-platform-team"
      },
      {
        "Sid": "AllowGroupEnumeration",
        "Effect": "Allow",
        "Action": [
          "iam:ListGroups",
          "iam:ListGroupPolicies",
          "iam:GetGroupPolicy",
          "iam:ListGroupsForUser",
          "iam:GetGroup"
        ],
        "Resource": "*"
      }
    ]
  }'
```

### Part B: Remove the Overly-Permissive Policy

```bash
aws iam detach-user-policy \
  --user-name iamws-group-admin-user \
  --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/iamws-group-admin-policy 2>/dev/null || true

aws iam detach-role-policy \
  --role-name iamws-group-admin-role \
  --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/iamws-group-admin-policy 2>/dev/null || true
```

### Part C: Verify the Remediation

```bash
# Try the original attack: PutGroupPolicy on iamws-dev-team (should fail)
echo "Testing: Can write inline policy on iamws-dev-team? (should fail)"
aws iam put-group-policy \
  --group-name iamws-dev-team \
  --policy-name test-escalation \
  --policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":"*","Resource":"*"}]}' \
  --profile iamws-group-admin-user 2>&1

# Try on iamws-platform-team (should succeed)
echo "Testing: Can write inline policy on iamws-platform-team? (should succeed)"
aws iam put-group-policy \
  --group-name iamws-platform-team \
  --policy-name test-allowed \
  --policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":"s3:GetObject","Resource":"*"}]}' \
  --profile iamws-group-admin-user

# Clean up the test policy
aws iam delete-group-policy \
  --group-name iamws-platform-team \
  --policy-name test-allowed \
  --profile iamws-group-admin-user 2>/dev/null || true
```

**Expected results:**
- `iamws-dev-team`: `AccessDenied` — the user can no longer write policies on their own group
- `iamws-platform-team`: Success — they can still manage the group they're authorized for

**The attack is blocked!** The resource constraint prevents the self-escalation path.

### What You Learned

- **Resource constraints** prevent self-escalation via group policies — same principle as Exercise 4
- Restricting `PutGroupPolicy` to specific group ARNs ensures users can only manage groups they're authorized for
- Combine resource constraints with **naming conventions** (e.g., team-based group prefixes) for scalable access control
- Always ask: "Is this principal a member of any group they can write policies on?"

---

## Wrap-up

### Summary: What You Applied

| Exercise | Vulnerability | Guardrail | Key Technique |
|----------|--------------|-----------|---------------|
| 1 | CreatePolicyVersion | Permissions Boundary | Explicit deny in boundary |
| 2 | AssumeRole | Trust Policy | Specific principals, MFA condition |
| 3 | PassRole + EC2 | Condition Key | `iam:PassedToService` |
| 4 | UpdateFunctionCode | Resource Constraint | `Resource: "arn:...:function:dev-*"` |
| 5 | GetFunctionConfiguration | Secrets Manager | Architectural change |
| 6 | PutGroupPolicy | Resource Constraint | Restrict group ARNs in Resource |

### Defense in Depth Diagram

```
┌──────────────────────────────────────────────────────────────┐
│  Layer 6: Service Control Policy (SCP)                       │
│  └─ Organization-wide guardrails (not in this lab)           │
├──────────────────────────────────────────────────────────────┤
│  Layer 5: Secrets Management                                 │
│  └─ Secrets Manager, Parameter Store (not env vars!)         │
├──────────────────────────────────────────────────────────────┤
│  Layer 4: Condition Keys                                     │
│  └─ iam:PassedToService, aws:SourceIp, aws:MfaPresent        │
├──────────────────────────────────────────────────────────────┤
│  Layer 3: Resource Policies (Trust Policies)                 │
│  └─ Control WHO can assume roles                             │
├──────────────────────────────────────────────────────────────┤
│  Layer 2: Permissions Boundaries                             │
│  └─ Maximum possible permissions (ceiling)                   │
├──────────────────────────────────────────────────────────────┤
│  Layer 1: Identity Policies                                  │
│  └─ What you want to allow (with resource constraints)       │
└──────────────────────────────────────────────────────────────┘
```

Each layer provides independent protection. Even if one layer has a misconfiguration, the others can still block an attack.

### Key Takeaways

1. **Permissions boundaries** are essential for self-escalation attacks—they're the ONLY control that works when users can modify their own policies
1. **Trust policies** using `:root` trust the entire account—always use specific principals
1. **`iam:PassedToService`** is required for ANY policy that grants PassRole
1. **Resource constraints** are the primary defense for "Existing PassRole" attacks and group-based self-escalation
1. **Secrets Manager** is the only acceptable way to store credentials—never use env vars
1. **Resource constraints on groups** prevent self-escalation via `PutGroupPolicy`—always restrict which group ARNs can be modified

### The Six Defenses Summary

| Attack Category | Defense | Why It Works |
|-----------------|---------|--------------|
| Self-Escalation (Policy) | Permissions Boundary | Caps permissions even if user modifies own policy |
| Principal Access | Hardened Trust Policy | Resource policy on target controls who can assume |
| New PassRole | Condition Key | Limits which services can receive the role |
| Existing PassRole | Resource Constraint | Limits which resources can be modified |
| Credential Access | Secrets Manager | Secrets not visible via read permissions |
| Self-Escalation (Group) | Resource Constraint | Limits which groups can have inline policies written |

---

## Cleanup

When you're done with the workshop, clean up the resources:

### Remove Remediation Policies

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Remove permissions boundaries
aws iam delete-user-permissions-boundary \
  --user-name iamws-policy-developer-user 2>/dev/null || true

aws iam delete-role-permissions-boundary \
  --role-name iamws-policy-developer-role 2>/dev/null || true

# Delete inline policies
aws iam delete-user-policy \
  --user-name iamws-ci-runner-user \
  --policy-name SecurePassRole 2>/dev/null || true

aws iam delete-role-policy \
  --role-name iamws-ci-runner-role \
  --policy-name SecurePassRole 2>/dev/null || true

aws iam delete-user-policy \
  --user-name iamws-lambda-developer-user \
  --policy-name SecureLambdaDeveloper 2>/dev/null || true

aws iam delete-role-policy \
  --role-name iamws-lambda-developer-role \
  --policy-name SecureLambdaDeveloper 2>/dev/null || true

aws iam delete-role-policy \
  --role-name iamws-app-lambda-role \
  --policy-name SecretsManagerAccess 2>/dev/null || true

aws iam delete-user-policy \
  --user-name iamws-group-admin-user \
  --policy-name SecureGroupAdmin 2>/dev/null || true

aws iam delete-role-policy \
  --role-name iamws-group-admin-role \
  --policy-name SecureGroupAdmin 2>/dev/null || true

# Delete the boundary policy
aws iam delete-policy \
  --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/DeveloperBoundary 2>/dev/null || true

# Delete the secret
aws secretsmanager delete-secret \
  --secret-id iamws-app-secrets \
  --force-delete-without-recovery 2>/dev/null || true
```

### Destroy Terraform Infrastructure

```bash
cd labs/terraform
terraform destroy
```

When prompted, type `yes` to confirm.

---

## Next Steps

You've completed the IAM Security Workshop! You now understand:
- How attackers find and exploit IAM misconfigurations across all six vulnerability types
- How to apply the right guardrail for each type of vulnerability
- The principle of defense in depth in IAM

**Continue learning:**
- [pathfinding.cloud](https://pathfinding.cloud) - Explore all IAM privilege escalation paths
- [AWS IAM Best Practices](https://docs.aws.amazon.com/IAM/latest/UserGuide/best-practices.html)
- [Principal Mapper (pmapper)](https://github.com/nccgroup/PMapper) - Regular IAM security scanning
- [AWS Secrets Manager](https://docs.aws.amazon.com/secretsmanager/latest/userguide/intro.html) - Secure credential management
