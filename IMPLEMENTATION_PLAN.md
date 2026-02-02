# Implementation Plan: Lab Rearchitecture

## Educational Context

### The Problem We're Solving

The current lab exercises have a significant pedagogical flaw: **three of four vulnerabilities share the same root cause** (`Resource: "*"` in identity policies). This teaches learners a narrow, repetitive lesson rather than building comprehensive understanding of IAM privilege escalation.

Additionally, the current exercises:
- Have **two exercises in the same category** (principal-access appears twice)
- **Miss two of five pathfinding.cloud categories** entirely (existing-passrole, credential-access)
- Don't cover all the **defenses promised in the workshop abstract** (permissions boundaries, resource policies, condition keys)

### What Learners Should Walk Away With

After completing the rearchitected labs, learners should understand:

1. **The five categories of privilege escalation** (from pathfinding.cloud):
   - Self-escalation: Modify your own permissions
   - Principal-access: Gain access to another principal
   - New-passrole: Pass a role to new compute
   - Existing-passrole: Modify existing compute that has a role
   - Credential-access: Access credentials stored insecurely

2. **That different root causes require different defenses:**
   - Policy attached to self is modifiable → Permissions Boundary
   - Trust policy too permissive → Harden Trust Policy (Resource Policy)
   - PassRole missing condition → Condition Key
   - Can modify any resource → Resource Constraint
   - Secrets in plaintext → Use Secrets Manager

3. **The three main guardrail types:**
   - Permissions boundaries (ceiling on permissions)
   - Resource policies (trust policies, bucket policies)
   - Condition keys (iam:PassedToService, aws:SourceIp)

### Why Each Root Cause Must Be Distinct

If learners see `Resource: "*"` as the problem three times, they'll think:
> "Just avoid wildcard resources and I'm safe."

By showing **five distinct root causes**, learners understand that:
- The same permission can be dangerous for different reasons
- Different misconfigurations require different defenses
- IAM security requires understanding the full attack surface

---

## Summary: New Lab Architecture

| # | Category | Attack | Path ID | Root Cause | Defense | Defense Type |
|---|----------|--------|---------|------------|---------|--------------|
| 1 | **self-escalation** | `iam:CreatePolicyVersion` | IAM-001 | Can modify policy *attached to self* | Permissions Boundary | **Permissions Boundary** ✅ |
| 2 | **principal-access** | `sts:AssumeRole` (overly permissive trust) | STS-001 | Trust policy trusts *account root* | Harden trust policy | **Resource Policy** ✅ |
| 3 | **new-passrole** | `iam:PassRole + ec2:RunInstances` | EC2-001 | Missing `iam:PassedToService` condition | Add condition key | **Condition Key** ✅ |
| 4 | **existing-passrole** | `lambda:UpdateFunctionCode` | Lambda-003 | Can modify *any* Lambda with privileged role | Resource constraint (specific ARN) | Identity policy fix |
| 5 | **credential-access** | Secrets in Lambda env vars | *(new)* | Secrets stored in plaintext | Use Secrets Manager | Best practice |

### What's Changing

| Current Exercise | Action | New Exercise |
|-----------------|--------|--------------|
| AttachUserPolicy (self-escalation) | **REPLACE** | CreatePolicyVersion (self-escalation) |
| CreateAccessKey (principal-access) | **REPLACE** | AssumeRole with overly permissive trust (principal-access) |
| UpdateAssumeRolePolicy (principal-access) | **REMOVE** | *(duplicate category)* |
| PassRole + EC2 (new-passrole) | **KEEP** (minor updates) | PassRole + EC2 (new-passrole) |
| *(none)* | **ADD** | UpdateFunctionCode (existing-passrole) |
| *(none)* | **ADD** | Credential access from Lambda env vars |

### All Promised Defenses Covered

| Defense from Workshop Abstract | Exercise |
|-------------------------------|----------|
| Permissions boundaries | Exercise 1 (CreatePolicyVersion) |
| Resource policies (trust policies) | Exercise 2 (AssumeRole) |
| Condition keys | Exercise 3 (PassRole + EC2) |
| SCPs | Lecture only (as currently noted) |

---

## Implementation Phases

### Phase 1: Cleanup

Remove Terraform modules for exercises we're replacing:

1. [ ] Delete `labs/terraform/modules/iam-principals/iamws-dev-self-service.tf`
2. [ ] Delete `labs/terraform/modules/iam-principals/iamws-team-onboarding.tf`
3. [ ] Delete `labs/terraform/modules/iam-principals/iamws-integration-admin.tf`
4. [ ] Run `terraform plan` to verify clean removal
5. [ ] Run `terraform apply` to remove resources from AWS

### Phase 2: Create/Update All Terraform Modules

Create all new modules so infrastructure can be deployed for testing:

1. [ ] Create `iamws-policy-developer.tf` (Exercise 1: CreatePolicyVersion)
2. [ ] Create `iamws-privileged-role.tf` (Exercise 2: AssumeRole with permissive trust)
3. [ ] Update `iamws-ci-runner.tf` (Exercise 3: emphasize missing condition key)
4. [ ] Create `iamws-lambda-developer.tf` (Exercise 4: UpdateFunctionCode)
5. [ ] Create `iamws-secrets-reader.tf` (Exercise 5: credential-access)
6. [ ] Run `terraform plan` to verify all modules
7. [ ] Run `terraform apply` to deploy infrastructure

### Phase 3: Implement and Test Each Scenario

For each scenario, implement the lab instructions and thoroughly test:

#### Exercise 1: CreatePolicyVersion (self-escalation)
1. [ ] Write Lab 1 instructions (exploit)
2. [ ] Write Lab 2 instructions (remediate with permissions boundary)
3. [ ] Test with pmapper: verify vulnerability detection
4. [ ] Test with awspx (Playwright): verify graph shows relationships
5. [ ] Test with AWS CLI: verify exploit works, then remediation blocks it

#### Exercise 2: AssumeRole with Permissive Trust (principal-access)
1. [ ] Write Lab 1 instructions (exploit)
2. [ ] Write Lab 2 instructions (remediate with hardened trust policy)
3. [ ] Test with pmapper: verify vulnerability detection
4. [ ] Test with awspx (Playwright): verify graph shows trust relationship
5. [ ] Test with AWS CLI: verify exploit works, then remediation blocks it

#### Exercise 3: PassRole + EC2 (new-passrole)
1. [ ] Update Lab 1 instructions (emphasize missing condition key)
2. [ ] Update Lab 2 instructions (add iam:PassedToService condition)
3. [ ] Test with pmapper: verify vulnerability detection
4. [ ] Test with awspx (Playwright): verify graph shows PassRole edge
5. [ ] Test with AWS CLI: verify exploit scenario, then remediation blocks it

#### Exercise 4: UpdateFunctionCode (existing-passrole)
1. [ ] Write Lab 1 instructions (exploit)
2. [ ] Write Lab 2 instructions (remediate with resource constraint)
3. [ ] Test with pmapper: verify vulnerability detection
4. [ ] Test with awspx (Playwright): verify graph shows Lambda permissions
5. [ ] Test with AWS CLI: verify exploit works, then remediation blocks it

#### Exercise 5: Credential Access (credential-access)
1. [ ] Write Lab 1 instructions (exploit)
2. [ ] Write Lab 2 instructions (remediate with Secrets Manager)
3. [ ] Test with pmapper: verify GetFunctionConfiguration permission visible
4. [ ] Test with awspx (Playwright): verify graph shows Lambda access
5. [ ] Test with AWS CLI: verify secrets exposed, then hidden after remediation

### Phase 4: Update Lab Documents

1. [ ] Rewrite `labs/lab-1-layin-down-the-law/lab-1-instructions.md` with new exercises
2. [ ] Rewrite `labs/lab-2-fencin-the-frontier/lab-2-instructions.md` with new defenses
3. [ ] Update wrap-up sections with correct category mapping
4. [ ] Update defense-in-depth diagram

### Phase 5: Update Slides

1. [ ] Update `slides/lecture-1-layin-down-the-law/slides.md` with new examples
2. [ ] Update `slides/lecture-2-fencin-the-frontier/slides.md` with new defenses
3. [ ] Ensure all policy examples match lab scenarios exactly
4. [ ] Remove/address all TODO markers

---

## Terraform Module Specifications

### Exercise 1: CreatePolicyVersion (self-escalation)

**File:** `labs/terraform/modules/iam-principals/iamws-policy-developer.tf`

```hcl
# Policy Developer - Can manage policy versions for development policies
# Attack: iam:CreatePolicyVersion allows modifying a policy attached to self
# Path: Developer → CreatePolicyVersion → Add admin permissions to attached policy → Full admin
# Root Cause: User can create new versions of a policy that's attached to them

# Create a customer-managed policy that will be attached to the user
resource "aws_iam_policy" "iamws-developer-tools-policy" {
  name        = "iamws-developer-tools-policy"
  path        = "/"
  description = "Developer tools policy - intentionally allows policy version management"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowDeveloperTools"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket",
          "ec2:DescribeInstances"
        ]
        Resource = "*"
      }
    ]
  })
}

# The vulnerable policy - allows CreatePolicyVersion on any policy
resource "aws_iam_policy" "iamws-policy-developer-policy" {
  name        = "iamws-policy-developer-policy"
  path        = "/"
  description = "Allows managing policy versions - vulnerable to privesc via iam:CreatePolicyVersion"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowPolicyVersionManagement"
        Effect = "Allow"
        Action = [
          "iam:CreatePolicyVersion",
          "iam:ListPolicyVersions",
          "iam:GetPolicy",
          "iam:GetPolicyVersion"
        ]
        # ROOT CAUSE: Can modify ANY policy, including ones attached to self
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role" "iamws-policy-developer-role" {
  name = "iamws-policy-developer-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action    = "sts:AssumeRole"
        Effect    = "Allow"
        Principal = { AWS = var.aws_assume_role_arn }
      }
    ]
  })
}

resource "aws_iam_user" "iamws-policy-developer-user" {
  name = "iamws-policy-developer-user"
  path = "/"
}

resource "aws_iam_access_key" "iamws-policy-developer-user" {
  user = aws_iam_user.iamws-policy-developer-user.name
}

# Attach both policies to user - the developer tools AND the policy management
resource "aws_iam_user_policy_attachment" "iamws-policy-developer-user-tools" {
  user       = aws_iam_user.iamws-policy-developer-user.name
  policy_arn = aws_iam_policy.iamws-developer-tools-policy.arn
}

resource "aws_iam_user_policy_attachment" "iamws-policy-developer-user-mgmt" {
  user       = aws_iam_user.iamws-policy-developer-user.name
  policy_arn = aws_iam_policy.iamws-policy-developer-policy.arn
}

resource "aws_iam_role_policy_attachment" "iamws-policy-developer-role-tools" {
  role       = aws_iam_role.iamws-policy-developer-role.name
  policy_arn = aws_iam_policy.iamws-developer-tools-policy.arn
}

resource "aws_iam_role_policy_attachment" "iamws-policy-developer-role-mgmt" {
  role       = aws_iam_role.iamws-policy-developer-role.name
  policy_arn = aws_iam_policy.iamws-policy-developer-policy.arn
}
```

### Exercise 2: AssumeRole with Overly Permissive Trust (principal-access)

**File:** `labs/terraform/modules/iam-principals/iamws-privileged-role.tf`

```hcl
# Privileged Admin Role - Has overly permissive trust policy
# Attack: Trust policy trusts account root, allowing any principal to assume
# Path: Any user with sts:AssumeRole → Assume privileged role → Full admin
# Root Cause: Trust policy uses account root notation instead of explicit principals

data "aws_caller_identity" "current" {}

resource "aws_iam_role" "iamws-privileged-admin-role" {
  name = "iamws-privileged-admin-role"

  # ROOT CAUSE: Trusts account root - any principal with sts:AssumeRole can assume this
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
        Action    = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "iamws-privileged-admin-role-admin" {
  role       = aws_iam_role.iamws-privileged-admin-role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# Low-privilege user that has sts:AssumeRole permission
resource "aws_iam_policy" "iamws-role-assumer-policy" {
  name        = "iamws-role-assumer-policy"
  path        = "/"
  description = "Allows assuming roles - combined with permissive trust policy enables privesc"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowAssumeRole"
        Effect = "Allow"
        Action = "sts:AssumeRole"
        # NOTE: This is NOT the root cause - it's the trust policy that's too permissive
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role" "iamws-role-assumer-role" {
  name = "iamws-role-assumer-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action    = "sts:AssumeRole"
        Effect    = "Allow"
        Principal = { AWS = var.aws_assume_role_arn }
      }
    ]
  })
}

resource "aws_iam_user" "iamws-role-assumer-user" {
  name = "iamws-role-assumer-user"
  path = "/"
}

resource "aws_iam_access_key" "iamws-role-assumer-user" {
  user = aws_iam_user.iamws-role-assumer-user.name
}

resource "aws_iam_user_policy_attachment" "iamws-role-assumer-user-attach" {
  user       = aws_iam_user.iamws-role-assumer-user.name
  policy_arn = aws_iam_policy.iamws-role-assumer-policy.arn
}

resource "aws_iam_role_policy_attachment" "iamws-role-assumer-role-attach" {
  role       = aws_iam_role.iamws-role-assumer-role.name
  policy_arn = aws_iam_policy.iamws-role-assumer-policy.arn
}
```

### Exercise 3: PassRole + EC2 (new-passrole)

**File:** `labs/terraform/modules/iam-principals/iamws-ci-runner.tf` (UPDATE EXISTING)

Update the existing file to emphasize the missing condition key as the root cause:

```hcl
# CI Runner - CI/CD service account
# Attack: iam:PassRole + ec2:RunInstances allows launching EC2 with any role
# Path: CI Runner → PassRole → Launch EC2 with admin role → Harvest credentials
# Root Cause: PassRole has no iam:PassedToService condition (not just Resource: "*")

resource "aws_iam_policy" "iamws-ci-runner-policy" {
  name        = "iamws-ci-runner-policy"
  path        = "/"
  description = "CI runner permissions - vulnerable due to missing iam:PassedToService condition"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowPassRole"
        Effect = "Allow"
        Action = "iam:PassRole"
        Resource = "*"
        # ROOT CAUSE: Missing this condition block:
        # "Condition": {
        #   "StringEquals": {
        #     "iam:PassedToService": "ec2.amazonaws.com"
        #   }
        # }
      },
      {
        Sid    = "AllowEC2Operations"
        Effect = "Allow"
        Action = [
          "ec2:RunInstances",
          "ec2:DescribeInstances",
          "ec2:CreateKeyPair"
        ]
        Resource = "*"
      }
    ]
  })
}

# ... rest of existing resources (role, user, access key, attachments) ...
```

### Exercise 4: UpdateFunctionCode (existing-passrole)

**File:** `labs/terraform/modules/iam-principals/iamws-lambda-developer.tf`

```hcl
# Lambda Developer - Can update Lambda function code
# Attack: lambda:UpdateFunctionCode allows modifying a Lambda with a privileged role
# Path: Developer → UpdateFunctionCode → Replace with malicious code → Invoke → Admin
# Root Cause: Can modify ANY Lambda function, including those with admin roles

# A Lambda function with a privileged execution role (the target)
resource "aws_iam_role" "iamws-privileged-lambda-role" {
  name = "iamws-privileged-lambda-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "iamws-privileged-lambda-role-admin" {
  role       = aws_iam_role.iamws-privileged-lambda-role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# Create a simple Lambda function with the privileged role
data "archive_file" "privileged_lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/privileged_lambda.zip"
  source {
    content  = "def handler(event, context): return {'statusCode': 200, 'body': 'Hello'}"
    filename = "lambda_function.py"
  }
}

resource "aws_lambda_function" "iamws-privileged-lambda" {
  filename         = data.archive_file.privileged_lambda_zip.output_path
  function_name    = "iamws-privileged-lambda"
  role             = aws_iam_role.iamws-privileged-lambda-role.arn
  handler          = "lambda_function.handler"
  runtime          = "python3.9"
  source_code_hash = data.archive_file.privileged_lambda_zip.output_base64sha256
}

# The vulnerable policy - allows updating ANY Lambda function code
resource "aws_iam_policy" "iamws-lambda-developer-policy" {
  name        = "iamws-lambda-developer-policy"
  path        = "/"
  description = "Lambda developer permissions - vulnerable to privesc via UpdateFunctionCode"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowLambdaCodeUpdate"
        Effect = "Allow"
        Action = [
          "lambda:UpdateFunctionCode",
          "lambda:GetFunction",
          "lambda:InvokeFunction",
          "lambda:ListFunctions"
        ]
        # ROOT CAUSE: Can modify ANY Lambda, including privileged ones
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role" "iamws-lambda-developer-role" {
  name = "iamws-lambda-developer-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { AWS = var.aws_assume_role_arn }
    }]
  })
}

resource "aws_iam_user" "iamws-lambda-developer-user" {
  name = "iamws-lambda-developer-user"
  path = "/"
}

resource "aws_iam_access_key" "iamws-lambda-developer-user" {
  user = aws_iam_user.iamws-lambda-developer-user.name
}

resource "aws_iam_user_policy_attachment" "iamws-lambda-developer-user-attach" {
  user       = aws_iam_user.iamws-lambda-developer-user.name
  policy_arn = aws_iam_policy.iamws-lambda-developer-policy.arn
}

resource "aws_iam_role_policy_attachment" "iamws-lambda-developer-role-attach" {
  role       = aws_iam_role.iamws-lambda-developer-role.name
  policy_arn = aws_iam_policy.iamws-lambda-developer-policy.arn
}
```

### Exercise 5: Credential Access from Lambda Environment Variables

**File:** `labs/terraform/modules/iam-principals/iamws-secrets-reader.tf`

```hcl
# Secrets Reader - Can read Lambda configuration including env vars
# Attack: lambda:GetFunctionConfiguration exposes secrets stored in env vars
# Path: Reader → GetFunctionConfiguration → Read plaintext secrets → Access external systems
# Root Cause: Secrets stored in Lambda env vars instead of Secrets Manager

# A Lambda function with secrets in environment variables (bad practice)
data "archive_file" "app_lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/app_lambda.zip"
  source {
    content  = "def handler(event, context): return {'statusCode': 200, 'body': 'App running'}"
    filename = "lambda_function.py"
  }
}

resource "aws_iam_role" "iamws-app-lambda-role" {
  name = "iamws-app-lambda-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_lambda_function" "iamws-app-with-secrets" {
  filename         = data.archive_file.app_lambda_zip.output_path
  function_name    = "iamws-app-with-secrets"
  role             = aws_iam_role.iamws-app-lambda-role.arn
  handler          = "lambda_function.handler"
  runtime          = "python3.9"
  source_code_hash = data.archive_file.app_lambda_zip.output_base64sha256

  # ROOT CAUSE: Secrets stored in plaintext environment variables
  environment {
    variables = {
      DB_PASSWORD       = "SuperSecretPassword123!"
      API_KEY           = "sk-fake-api-key-do-not-use"
      ADMIN_CREDENTIALS = "admin:P@ssw0rd!"
    }
  }
}

# User who can read Lambda configurations
resource "aws_iam_policy" "iamws-secrets-reader-policy" {
  name        = "iamws-secrets-reader-policy"
  description = "Can read Lambda configurations - exposes env var secrets"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "lambda:GetFunction",
        "lambda:GetFunctionConfiguration",
        "lambda:ListFunctions"
      ]
      Resource = "*"
    }]
  })
}

resource "aws_iam_role" "iamws-secrets-reader-role" {
  name = "iamws-secrets-reader-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { AWS = var.aws_assume_role_arn }
    }]
  })
}

resource "aws_iam_user" "iamws-secrets-reader-user" {
  name = "iamws-secrets-reader-user"
}

resource "aws_iam_access_key" "iamws-secrets-reader-user" {
  user = aws_iam_user.iamws-secrets-reader-user.name
}

resource "aws_iam_user_policy_attachment" "iamws-secrets-reader-user-attach" {
  user       = aws_iam_user.iamws-secrets-reader-user.name
  policy_arn = aws_iam_policy.iamws-secrets-reader-policy.arn
}

resource "aws_iam_role_policy_attachment" "iamws-secrets-reader-role-attach" {
  role       = aws_iam_role.iamws-secrets-reader-role.name
  policy_arn = aws_iam_policy.iamws-secrets-reader-policy.arn
}
```

---

## Testing Approach

For each scenario, testing happens as part of implementing the lab instructions (not as separate test scripts). The testing validates:

### 1. pmapper Detection
```bash
# Verify pmapper can identify the vulnerability
pmapper graph create
pmapper query "can user/iamws-XXX-user do ACTION with *"
# Expected: "IS authorized"
```

### 2. awspx Visualization (using Playwright)
```bash
# Refresh awspx data
docker exec awspx python3 /opt/awspx/cli.py ingest --env --services IAM --region us-east-1

# Use Playwright to:
# - Navigate to http://localhost
# - Search for the user/role
# - Verify the expected permissions/relationships appear
# - Take screenshots for documentation
```

### 3. AWS CLI Exploit Verification
```bash
# Before remediation: Exploit should succeed
# After remediation: Exploit should fail with AccessDenied
```

---

## Files Summary

### Files to Delete (Phase 1)
- `labs/terraform/modules/iam-principals/iamws-dev-self-service.tf`
- `labs/terraform/modules/iam-principals/iamws-team-onboarding.tf`
- `labs/terraform/modules/iam-principals/iamws-integration-admin.tf`

### Files to Create (Phase 2)
- `labs/terraform/modules/iam-principals/iamws-policy-developer.tf`
- `labs/terraform/modules/iam-principals/iamws-privileged-role.tf`
- `labs/terraform/modules/iam-principals/iamws-lambda-developer.tf`
- `labs/terraform/modules/iam-principals/iamws-secrets-reader.tf`

### Files to Modify (Phase 2-5)
- `labs/terraform/modules/iam-principals/iamws-ci-runner.tf` (update comments/emphasis)
- `labs/lab-1-layin-down-the-law/lab-1-instructions.md` (rewrite)
- `labs/lab-2-fencin-the-frontier/lab-2-instructions.md` (rewrite)
- `slides/lecture-1-layin-down-the-law/slides.md` (update)
- `slides/lecture-2-fencin-the-frontier/slides.md` (update)
