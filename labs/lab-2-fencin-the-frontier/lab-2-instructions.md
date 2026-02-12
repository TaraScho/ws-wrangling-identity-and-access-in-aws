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

## Exercises

1. [Exercise 1: Permissions Boundary for CreatePolicyVersion](exercises/exercise-1.md) — Apply a permissions boundary to cap effective permissions
1. [Exercise 2: Harden Trust Policy for AssumeRole](exercises/exercise-2.md) — Restrict trust policy to specific principals with MFA
1. [Exercise 3: Condition Key for PassRole + EC2](exercises/exercise-3.md) — Use iam:PassedToService to limit PassRole targets
1. [Exercise 4: Resource Constraint for UpdateFunctionCode](exercises/exercise-4.md) — Restrict Lambda function access by ARN pattern
1. [Exercise 5: Secrets Manager for Credential Access](exercises/exercise-5.md) — Move secrets from env vars to Secrets Manager
1. [Exercise 6: Resource Constraint for PutGroupPolicy](exercises/exercise-6.md) — Restrict PutGroupPolicy to authorized group ARNs

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
