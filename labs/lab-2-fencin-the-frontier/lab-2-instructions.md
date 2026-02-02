# Lab 2 - Fencin' the Frontier: Remediating IAM Misconfigurations

**Duration:** 45 minutes

## Overview

In Lab 1, you exploited four privilege escalation vulnerabilities. Now you'll learn how to prevent them using AWS IAM guardrails. Each exercise follows the pattern: **Recap → Remediate → Verify**.

**What You'll Learn:**
- How **permissions boundaries** cap effective permissions (even for administrators)
- How **trust policies** control who can assume roles
- How **condition keys** restrict PassRole to specific services
- How **resource constraints** enable self-service while blocking access to others

**Why This Matters:**
Finding vulnerabilities is only half the battle. Knowing how to fix them—and understanding which guardrail applies to which attack—is essential for building secure cloud infrastructure.

---

## Prerequisites

- Completed Lab 1 (you understand the four vulnerabilities)
- AWS CLI configured with admin credentials for applying remediations
- Terraform infrastructure still deployed

---

## The Four Guardrails

Before diving into the exercises, here's a preview of the guardrails we'll apply:

| Vulnerability | Category | Guardrail | How It Works |
|---------------|----------|-----------|--------------|
| AttachUserPolicy | Self-Escalation | **Permissions Boundary** | Caps maximum possible permissions |
| CreateAccessKey | Principal Access | **Resource Constraint** | `${aws:username}` limits to self |
| UpdateAssumeRolePolicy | Principal Access | **Trust Policy** | Explicit principal restrictions |
| PassRole + EC2 | New PassRole | **Condition Key** | `iam:PassedToService` limits target services |

---

## Exercise 1: Permissions Boundary for AttachUserPolicy

### Recap: The Vulnerability

In Lab 1, you exploited `iamws-dev-self-service-user` to attach `AdministratorAccess` to themselves. The problem was that `iam:AttachUserPolicy` had no resource constraint—the user could attach ANY policy to ANY user.

**Attack path:** [pathfinding.cloud IAM-007](https://pathfinding.cloud/paths/iam-007)

### Understanding Permissions Boundaries

A permissions boundary is a **ceiling** on what permissions an IAM principal can have. Even if a user has `AdministratorAccess` attached, they cannot perform actions that the boundary doesn't allow.

```
┌─────────────────────────────────────────┐
│  Identity Policy                        │  ← "What I want to allow"
│  (AdministratorAccess)                  │
├─────────────────────────────────────────┤
│  Permissions Boundary                   │  ← "Maximum I can have"
│  (DeveloperBoundary)                    │
├─────────────────────────────────────────┤
│  EFFECTIVE PERMISSIONS                  │  ← Intersection of both
│  (Only actions in BOTH)                 │
└─────────────────────────────────────────┘
```

The boundary doesn't grant permissions—it only restricts them.

### Part A: Create the Permissions Boundary Policy

1. **Create a boundary policy file** (`boundary-policy.json`):
   ```json
   {
     "Version": "2012-10-17",
     "Statement": [
       {
         "Sid": "AllowBasicReadAccess",
         "Effect": "Allow",
         "Action": [
           "s3:Get*",
           "s3:List*",
           "ec2:Describe*",
           "iam:Get*",
           "iam:List*"
         ],
         "Resource": "*"
       },
       {
         "Sid": "DenyPrivilegeEscalation",
         "Effect": "Deny",
         "Action": [
           "iam:AttachUserPolicy",
           "iam:AttachRolePolicy",
           "iam:PutUserPolicy",
           "iam:PutRolePolicy",
           "iam:CreateUser",
           "iam:CreateRole",
           "iam:CreateAccessKey",
           "iam:UpdateAssumeRolePolicy",
           "iam:DeleteUserPermissionsBoundary"
         ],
         "Resource": "*"
       }
     ]
   }
   ```

2. **Create the policy in IAM:**
   ```bash
   ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

   aws iam create-policy \
     --policy-name DeveloperBoundary \
     --policy-document file://boundary-policy.json \
     --description "Permissions boundary that prevents privilege escalation"
   ```

### Part B: Apply the Boundary

```bash
aws iam put-user-permissions-boundary \
  --user-name iamws-dev-self-service-user \
  --permissions-boundary arn:aws:iam::${ACCOUNT_ID}:policy/DeveloperBoundary
```

### Part C: Verify the Remediation

Now test that the attack is blocked, even if the user has `AdministratorAccess`:

```bash
# Assume the vulnerable role
CREDS=$(aws sts assume-role \
  --role-arn arn:aws:iam::${ACCOUNT_ID}:role/iamws-dev-self-service-role \
  --role-session-name verify \
  --query "Credentials" \
  --output json)

export AWS_ACCESS_KEY_ID=$(echo $CREDS | jq -r '.AccessKeyId')
export AWS_SECRET_ACCESS_KEY=$(echo $CREDS | jq -r '.SecretAccessKey')
export AWS_SESSION_TOKEN=$(echo $CREDS | jq -r '.SessionToken')

# Try the attack
aws iam attach-user-policy \
  --user-name iamws-dev-self-service-user \
  --policy-arn arn:aws:iam::aws:policy/AdministratorAccess
```

**Expected result:**
```
An error occurred (AccessDenied) when calling the AttachUserPolicy operation:
User: arn:aws:sts::115753408004:assumed-role/iamws-dev-self-service-role/verify
is not authorized to perform: iam:AttachUserPolicy on resource: user iamws-dev-self-service-user
with an explicit deny in a permissions boundary
```

**The attack is blocked!** The boundary explicitly denies `iam:AttachUserPolicy`.

```bash
# Reset credentials
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
```

### What You Learned

- Permissions boundaries cap effective permissions regardless of attached policies
- The `Deny` in a boundary overrides any `Allow` in identity policies
- Boundaries are essential for delegated administration—you can let users manage their own policies while preventing escalation

---

## Exercise 2: Resource Constraint for CreateAccessKey

### Recap: The Vulnerability

In Lab 1, you exploited `iamws-team-onboarding-user` to create access keys for any user, including administrators. The problem was that `iam:CreateAccessKey` had `Resource: "*"`.

**Attack path:** [pathfinding.cloud IAM-002](https://pathfinding.cloud/paths/iam-002)

### Understanding ${aws:username}

The `${aws:username}` policy variable resolves to the name of the IAM user making the request. By using it in the Resource element, you can create "self-service" policies:

```json
"Resource": "arn:aws:iam::*:user/${aws:username}"
```

This allows users to manage their OWN access keys but not anyone else's.

### Part A: Create the Restrictive Policy

```bash
aws iam put-user-policy \
  --user-name iamws-team-onboarding-user \
  --policy-name ManageOwnAccessKeysOnly \
  --policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Sid": "AllowManageOwnAccessKeys",
      "Effect": "Allow",
      "Action": [
        "iam:CreateAccessKey",
        "iam:DeleteAccessKey",
        "iam:ListAccessKeys",
        "iam:UpdateAccessKey"
      ],
      "Resource": "arn:aws:iam::*:user/${aws:username}"
    }]
  }'
```

### Part B: Remove the Overly-Permissive Policy

Check for and remove any policies that grant unrestricted `CreateAccessKey`:

```bash
# List attached policies
aws iam list-attached-user-policies --user-name iamws-team-onboarding-user

# List inline policies
aws iam list-user-policies --user-name iamws-team-onboarding-user

# Detach the overly-permissive managed policy (if present)
aws iam detach-user-policy \
  --user-name iamws-team-onboarding-user \
  --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/iamws-team-onboarding-policy 2>/dev/null || true
```

### Part C: Verify the Remediation

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Assume the vulnerable role
CREDS=$(aws sts assume-role \
  --role-arn arn:aws:iam::${ACCOUNT_ID}:role/iamws-team-onboarding-role \
  --role-session-name verify \
  --query "Credentials" \
  --output json)

export AWS_ACCESS_KEY_ID=$(echo $CREDS | jq -r '.AccessKeyId')
export AWS_SECRET_ACCESS_KEY=$(echo $CREDS | jq -r '.SecretAccessKey')
export AWS_SESSION_TOKEN=$(echo $CREDS | jq -r '.SessionToken')

# Try to create keys for an admin user (should fail)
aws iam create-access-key --user-name cloud-foxable
```

**Expected result:**
```
An error occurred (AccessDenied) when calling the CreateAccessKey operation:
User: arn:aws:sts::115753408004:assumed-role/iamws-team-onboarding-role/verify
is not authorized to perform: iam:CreateAccessKey on resource: user cloud-foxable
```

**The attack is blocked!** The user can only create keys for themselves.

```bash
# Reset credentials
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
```

### What You Learned

- `${aws:username}` enables self-service patterns without granting access to others
- Always use resource constraints when granting IAM credential management permissions
- The combination of `Allow` for self + removal of `*` Resource prevents privilege escalation

---

## Exercise 3: Trust Policy Hardening for UpdateAssumeRolePolicy

### Recap: The Vulnerability

In Lab 1, you exploited `iamws-integration-admin-user` to modify the trust policy of a privileged role, then assume it. The problem was unrestricted `iam:UpdateAssumeRolePolicy` permission.

**Attack path:** [pathfinding.cloud IAM-012](https://pathfinding.cloud/paths/iam-012)

### Understanding Trust Policies

Trust policies ARE resource policies—they control WHO can assume a role. Unlike identity policies (which say what a principal CAN do), trust policies say who can BECOME that principal.

Two defenses:
1. **Explicit deny** in the attacker's identity policy (prevents modification)
2. **Hardened trust policy** on the role (limits who can assume it)

### Part A: Add Explicit Deny to Identity Policy

```bash
aws iam put-user-policy \
  --user-name iamws-integration-admin-user \
  --policy-name DenyTrustPolicyModification \
  --policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Sid": "DenyUpdateAssumeRolePolicy",
      "Effect": "Deny",
      "Action": "iam:UpdateAssumeRolePolicy",
      "Resource": "*"
    }]
  }'
```

### Part B: Harden the Trust Policy

Reset the target role's trust policy to only allow specific principals:

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

aws iam update-assume-role-policy \
  --role-name iamws-prod-deploy-role \
  --policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }]
  }'
```

This trust policy ONLY allows EC2 instances to assume the role—not IAM users or roles.

### Part C: Verify the Remediation

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Assume the vulnerable role
CREDS=$(aws sts assume-role \
  --role-arn arn:aws:iam::${ACCOUNT_ID}:role/iamws-integration-admin-role \
  --role-session-name verify \
  --query "Credentials" \
  --output json)

export AWS_ACCESS_KEY_ID=$(echo $CREDS | jq -r '.AccessKeyId')
export AWS_SECRET_ACCESS_KEY=$(echo $CREDS | jq -r '.SecretAccessKey')
export AWS_SESSION_TOKEN=$(echo $CREDS | jq -r '.SessionToken')

# Try to update the trust policy (should fail due to explicit deny)
aws iam update-assume-role-policy \
  --role-name iamws-prod-deploy-role \
  --policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"AWS":"*"},"Action":"sts:AssumeRole"}]}'
```

**Expected result:**
```
An error occurred (AccessDenied) when calling the UpdateAssumeRolePolicy operation:
User: arn:aws:sts::115753408004:assumed-role/iamws-integration-admin-role/verify
is not authorized to perform: iam:UpdateAssumeRolePolicy on resource: role iamws-prod-deploy-role
with an explicit deny
```

**The attack is blocked!** The explicit deny prevents trust policy modification.

```bash
# Reset credentials
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
```

### What You Learned

- Trust policies are resource policies that control WHO can assume a role
- Explicit denies in identity policies override any allows
- Hardened trust policies with specific principals prevent hijacking even if the deny is bypassed
- Defense in depth: both layers protect the role

---

## Exercise 4: Condition Key for PassRole + EC2

### Recap: The Vulnerability

In Lab 1, you identified that `iamws-ci-runner-user` could pass any role to EC2 instances, allowing them to harvest credentials from the metadata service.

**Attack path:** [pathfinding.cloud EC2-001](https://pathfinding.cloud/paths/ec2-001)

### Understanding iam:PassedToService

The `iam:PassedToService` condition key restricts which AWS service a role can be passed to. Combined with a resource constraint on which roles can be passed, this creates a secure PassRole policy:

```json
{
  "Condition": {
    "StringEquals": {
      "iam:PassedToService": "ec2.amazonaws.com"
    }
  },
  "Resource": "arn:aws:iam::*:role/SpecificRole"
}
```

This ensures:
1. The role can ONLY be passed to EC2 (not Lambda, ECS, etc.)
2. ONLY the specified role can be passed (not admin roles)

### Part A: Create Restricted PassRole Policy

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

aws iam put-user-policy \
  --user-name iamws-ci-runner-user \
  --policy-name RestrictedPassRole \
  --policy-document '{
    "Version": "2012-10-17",
    "Statement": [
      {
        "Sid": "AllowPassRoleToEC2Only",
        "Effect": "Allow",
        "Action": "iam:PassRole",
        "Resource": "arn:aws:iam::'${ACCOUNT_ID}':role/iamws-ci-runner-role",
        "Condition": {
          "StringEquals": {
            "iam:PassedToService": "ec2.amazonaws.com"
          }
        }
      },
      {
        "Sid": "AllowEC2Operations",
        "Effect": "Allow",
        "Action": [
          "ec2:RunInstances",
          "ec2:DescribeInstances",
          "ec2:DescribeImages"
        ],
        "Resource": "*"
      }
    ]
  }'
```

### Part B: Remove Overly-Permissive Policy

```bash
# Detach the original policy that allowed unrestricted PassRole
aws iam detach-user-policy \
  --user-name iamws-ci-runner-user \
  --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/iamws-ci-runner-policy 2>/dev/null || true
```

### Part C: Verify the Remediation

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Assume the vulnerable role
CREDS=$(aws sts assume-role \
  --role-arn arn:aws:iam::${ACCOUNT_ID}:role/iamws-ci-runner-role \
  --role-session-name verify \
  --query "Credentials" \
  --output json)

export AWS_ACCESS_KEY_ID=$(echo $CREDS | jq -r '.AccessKeyId')
export AWS_SECRET_ACCESS_KEY=$(echo $CREDS | jq -r '.SecretAccessKey')
export AWS_SESSION_TOKEN=$(echo $CREDS | jq -r '.SessionToken')

# List instance profiles to find the privileged one
aws iam list-instance-profiles --query 'InstanceProfiles[*].InstanceProfileName' --output table

# Try to launch EC2 with the privileged prod-deploy profile (should fail)
# Note: This is conceptual - we're showing the permission check would fail
aws ec2 run-instances \
  --image-id ami-12345678 \
  --instance-type t3.micro \
  --iam-instance-profile Name=iamws-prod-deploy-profile \
  --dry-run 2>&1 | head -5
```

**Expected result:** The `--dry-run` will show an error because the user cannot pass the `iamws-prod-deploy-role` to EC2 (it's not in the allowed Resource list).

```bash
# Reset credentials
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
```

### What You Learned

- `iam:PassedToService` is essential for any PassRole permission
- Resource constraints limit WHICH roles can be passed
- Condition keys limit WHICH services roles can be passed to
- Both constraints together prevent PassRole-based privilege escalation

---

## Wrap-up

### Summary: What You Applied

| Exercise | Vulnerability | Guardrail | Key Technique |
|----------|--------------|-----------|---------------|
| 1 | AttachUserPolicy | Permissions Boundary | Explicit deny in boundary |
| 2 | CreateAccessKey | Resource Constraint | `${aws:username}` variable |
| 3 | UpdateAssumeRolePolicy | Trust Policy + Deny | Explicit deny + hardened trust |
| 4 | PassRole + EC2 | Condition Key | `iam:PassedToService` |

### Defense in Depth Diagram

```
┌──────────────────────────────────────────────────────────┐
│  Layer 5: Service Control Policy (SCP)                   │
│  └─ Organization-wide guardrails (not in this lab)       │
├──────────────────────────────────────────────────────────┤
│  Layer 4: Condition Keys                                 │
│  └─ iam:PassedToService, aws:SourceIp, aws:MfaPresent    │
├──────────────────────────────────────────────────────────┤
│  Layer 3: Resource Policies (Trust Policies)             │
│  └─ Control WHO can assume roles                         │
├──────────────────────────────────────────────────────────┤
│  Layer 2: Permissions Boundaries                         │
│  └─ Maximum possible permissions                         │
├──────────────────────────────────────────────────────────┤
│  Layer 1: Identity Policies                              │
│  └─ What you want to allow (with constraints)            │
└──────────────────────────────────────────────────────────┘
```

Each layer provides independent protection. Even if one layer has a misconfiguration, the others can still block an attack.

### Key Takeaways

1. **Permissions boundaries** are a ceiling, not a floor—they cap what's possible, they don't grant anything
2. **`${aws:username}`** enables self-service patterns without granting access to others
3. **Trust policies ARE resource policies**—they control who can become a principal
4. **`iam:PassedToService`** is essential for ANY policy that grants PassRole
5. **Explicit denies** override all allows—use them for critical protections

---

## Cleanup

When you're done with the workshop, clean up the resources:

### Remove Remediation Policies

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Remove permissions boundary
aws iam delete-user-permissions-boundary \
  --user-name iamws-dev-self-service-user 2>/dev/null || true

# Delete inline policies
aws iam delete-user-policy \
  --user-name iamws-team-onboarding-user \
  --policy-name ManageOwnAccessKeysOnly 2>/dev/null || true

aws iam delete-user-policy \
  --user-name iamws-integration-admin-user \
  --policy-name DenyTrustPolicyModification 2>/dev/null || true

aws iam delete-user-policy \
  --user-name iamws-ci-runner-user \
  --policy-name RestrictedPassRole 2>/dev/null || true

# Delete the boundary policy
aws iam delete-policy \
  --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/DeveloperBoundary 2>/dev/null || true
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
- How attackers find and exploit IAM misconfigurations
- How to apply the right guardrail for each type of vulnerability
- The principle of defense in depth in IAM

**Continue learning:**
- [pathfinding.cloud](https://pathfinding.cloud) - Explore all IAM privilege escalation paths
- [AWS IAM Best Practices](https://docs.aws.amazon.com/IAM/latest/UserGuide/best-practices.html)
- [Principal Mapper (pmapper)](https://github.com/nccgroup/PMapper) - Regular IAM security scanning
