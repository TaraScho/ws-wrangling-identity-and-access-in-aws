# Implementation Plan: IAM Workshop

## Status Summary

| Phase | Status |
|-------|--------|
| Phase 1: Terraform Infrastructure | ✅ Complete |
| Phase 2: Lab 1 Instructions | ✅ Complete |
| Phase 3: Lab 2 Instructions | ✅ Complete |
| Phase 4: Validation Testing | ✅ Complete (All exploits & remediations validated) |
| Phase 5: Slides | 🔄 In Progress |

### Trust Policy Note

Trust policies were temporarily updated via AWS CLI to allow both the SSO role and `cloud-foxable` user:
```
arn:aws:sts::115753408004:assumed-role/AWSReservedSSO_AdministratorAccess_676d470c0737bb58/taradschofield@gmail.com
arn:aws:iam::115753408004:user/cloud-foxable
```
This will revert on next `terraform apply`. For permanent fix, deploy Terraform with the desired identity.

---

## Workshop Architecture

### The Five Scenarios

Each scenario covers one of the five pathfinding.cloud privilege escalation categories, with a distinct root cause and defense:

| # | Category | Attack | Root Cause | Defense |
|---|----------|--------|------------|---------|
| 1 | **Self-Escalation** | CreatePolicyVersion | Can modify policy attached to self | Permissions Boundary |
| 2 | **Principal Access** | AssumeRole (permissive trust) | Trust policy trusts `:root` | Harden Trust Policy |
| 3 | **New PassRole** | PassRole + EC2 | Missing `iam:PassedToService` | Condition Key |
| 4 | **Existing PassRole** | UpdateFunctionCode | Can modify any Lambda | Resource Constraint |
| 5 | **Credential Access** | GetFunctionConfiguration | Secrets in env vars | Secrets Manager |

### Lab Structure

- **Lab 0**: Prerequisites and environment setup
- **Lab 1**: Identify + Exploit (6 exercises: setup + 5 attacks)
- **Lab 2**: Remediate + Verify (5 exercises: one per scenario)

---

## Phase 4: Validation Testing

Validate each scenario works with the deployed infrastructure.

### Prerequisites
- Terraform deployed: `cd labs/terraform && terraform apply`
- AWS profile: `AWS_PROFILE=tarademo1`

### Exercise 1: Setup (pmapper + awspx)

| Test | Command | Expected Result | Status |
|------|---------|-----------------|--------|
| pmapper graph create | `cd ~/tools/pmapper && python3 -m principalmapper graph create` | Graph: 42 nodes, 9 admins | ✅ |
| pmapper analysis | `python3 -m principalmapper analysis --output-type text` | Shows `iamws-*` escalation paths | ✅ |
| awspx ingest | `docker exec -e AWS_ACCESS_KEY_ID=... awspx python3 /opt/awspx/cli.py ingest --env --services IAM --region us-east-1` | 18 attack paths found | ✅ |
| awspx UI | Browse http://localhost:8080, search `iamws` | Workshop users visible | ✅ |

### Exercise 2: CreatePolicyVersion (Self-Escalation)

| Test | Command | Expected Result | Status |
|------|---------|-----------------|--------|
| pmapper query | `pmapper query "can user/iamws-policy-developer-user do iam:CreatePolicyVersion with *"` | "IS authorized" | ✅ |
| Exploit | Assume role → access policy versions | Can access policy versions | ✅ |
| Remediation | Apply permissions boundary | Boundary attached | ✅ |
| Verify block | Retry exploit | AccessDenied with "explicit deny in permissions boundary" | ✅ |

### Exercise 3: AssumeRole (Principal Access)

| Test | Command | Expected Result | Status |
|------|---------|-----------------|--------|
| pmapper query | `pmapper query "can user/iamws-role-assumer-user do sts:AssumeRole with arn:aws:iam::*:role/iamws-privileged-admin-role"` | "IS authorized" | ✅ |
| Trust policy | `aws iam get-role --role-name iamws-privileged-admin-role --query 'Role.AssumeRolePolicyDocument'` | Shows `:root` principal | ✅ |
| Exploit | Assume low-priv → assume admin role | Escalated to admin role | ✅ |
| Remediation | Harden trust policy | Trust policy updated | ✅ |
| Verify block | Retry exploit | AccessDenied | ✅ |

### Exercise 4: PassRole + EC2 (New PassRole)

| Test | Command | Expected Result | Status |
|------|---------|-----------------|--------|
| pmapper query | `pmapper query "can user/iamws-ci-runner-user do iam:PassRole with *"` | "IS authorized" | ✅ |
| pmapper query (specific) | `pmapper query "can role/iamws-ci-runner-role do iam:PassRole with arn:aws:iam::*:role/iamws-prod-deploy-role"` | "IS authorized" | ✅ |
| Instance profile exists | `aws iam list-instance-profiles` | Shows `iamws-prod-deploy-profile` | ✅ |
| Remediation | Add condition key + resource constraint | Policy updated | ✅ |
| Verify block | Simulate PassRole to prod role | implicitDeny | ✅ |

### Exercise 5: UpdateFunctionCode (Existing PassRole)

| Test | Command | Expected Result | Status |
|------|---------|-----------------|--------|
| pmapper query | `pmapper query "can user/iamws-lambda-developer-user do lambda:UpdateFunctionCode with *"` | "IS authorized" | ✅ |
| Lambda exists | `aws lambda get-function --function-name iamws-privileged-lambda` | Shows privileged Lambda with admin role | ✅ |
| Remediation | Add resource constraint (dev-* only) | Policy updated | ✅ |
| Verify block | Simulate update privileged Lambda | implicitDeny | ✅ |

### Exercise 6: GetFunctionConfiguration (Credential Access)

| Test | Command | Expected Result | Status |
|------|---------|-----------------|--------|
| pmapper query | `pmapper query "can user/iamws-secrets-reader-user do lambda:GetFunctionConfiguration with *"` | "IS authorized" | ✅ |
| Exploit | `aws lambda get-function-configuration --function-name iamws-app-with-secrets --query 'Environment.Variables'` | Shows `SuperSecretPassword123!` | ✅ |
| Remediation | Clear env vars (Secrets Manager in production) | Lambda env empty | ✅ |
| Verify block | Retry get-function-configuration | Shows `null` | ✅ |

---

## Phase 5: Slides

Update slides to align with new scenarios.

### Lecture 1: Layin' Down the Law

| Task | Status |
|------|--------|
| Review PARC model content | ⬜ |
| Update privilege escalation category examples | ⬜ |
| Ensure policy examples match Terraform | ⬜ |
| Remove/resolve any TODO markers | ⬜ |

### Lecture 2: Fencin' the Frontier

| Task | Status |
|------|--------|
| Review guardrails content | ⬜ |
| Update defense examples to match Lab 2 | ⬜ |
| Add permissions boundary example | ⬜ |
| Add trust policy hardening example | ⬜ |
| Add condition key example | ⬜ |
| Remove/resolve any TODO markers | ⬜ |

---

## Completed Work

### Phase 1: Terraform Infrastructure ✅

All vulnerable IAM principals deployed:

**Users:**
- `iamws-policy-developer-user` (Self-Escalation)
- `iamws-role-assumer-user` (Principal Access)
- `iamws-ci-runner-user` (New PassRole)
- `iamws-lambda-developer-user` (Existing PassRole)
- `iamws-secrets-reader-user` (Credential Access)

**Roles:**
- `iamws-policy-developer-role`
- `iamws-privileged-admin-role` (target - permissive trust)
- `iamws-ci-runner-role`
- `iamws-prod-deploy-role` (target - instance profile)
- `iamws-lambda-developer-role`
- `iamws-privileged-lambda-role` (target - Lambda exec role)
- `iamws-secrets-reader-role`
- `iamws-app-lambda-role`

**Lambda Functions:**
- `iamws-privileged-lambda` (admin exec role)
- `iamws-app-with-secrets` (plaintext secrets in env vars)

### Phase 2: Lab 1 Instructions ✅

File: `labs/lab-1-layin-down-the-law/lab-1-instructions.md` (767 lines)

- Exercise 1: pmapper + awspx setup
- Exercise 2: CreatePolicyVersion exploit
- Exercise 3: AssumeRole exploit
- Exercise 4: PassRole + EC2 exploit
- Exercise 5: UpdateFunctionCode exploit
- Exercise 6: GetFunctionConfiguration exploit
- Wrap-up with category mapping

### Phase 3: Lab 2 Instructions ✅

File: `labs/lab-2-fencin-the-frontier/lab-2-instructions.md` (919 lines)

- Exercise 1: Permissions Boundary defense
- Exercise 2: Trust Policy hardening
- Exercise 3: Condition Key defense
- Exercise 4: Resource Constraint defense
- Exercise 5: Secrets Manager defense
- Defense in Depth diagram
- Cleanup instructions

---

## Quick Reference

### Test Commands

```bash
# Set profile
export AWS_PROFILE=tarademo1

# Verify identity
aws sts get-caller-identity

# List workshop users
aws iam list-users --query 'Users[?starts_with(UserName, `iamws`)].UserName'

# List workshop roles
aws iam list-roles --query 'Roles[?starts_with(RoleName, `iamws`)].RoleName'

# List workshop Lambdas
aws lambda list-functions --query 'Functions[?starts_with(FunctionName, `iamws`)].FunctionName'

# pmapper graph
pmapper graph create
pmapper analysis --output-type text

# awspx ingest
docker exec awspx python3 /opt/awspx/cli.py ingest --env --services IAM --region us-east-1
```

### Assume Role Pattern

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

CREDS=$(aws sts assume-role \
  --role-arn arn:aws:iam::${ACCOUNT_ID}:role/ROLE_NAME \
  --role-session-name test \
  --query "Credentials" \
  --output json)

export AWS_ACCESS_KEY_ID=$(echo $CREDS | jq -r '.AccessKeyId')
export AWS_SECRET_ACCESS_KEY=$(echo $CREDS | jq -r '.SecretAccessKey')
export AWS_SESSION_TOKEN=$(echo $CREDS | jq -r '.SessionToken')

# Reset
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
```
