---
marp: true
theme: default
paginate: true
header: 'Wrangling Identity and Access in AWS'
footer: 'Module 2: Fencin'' the Frontier'
---

# Fencin' the Frontier

## Permissions Boundaries, Resource Policies, Condition Keys, and SCPs

---

# Recap: What We Learned

From Layin' Down the Law, you now know:
- **PARC Model for Policies** — Principal, Action, Resource, Condition
- **Escalation Categories** — Self-Escalation, Principal Access, New PassRole, Existing PassRole, Credential Access
- **pmapper** — Automates discovery of privilege escalation paths
- **pathfinding.cloud** — Catalog of privilege escalation paths with remediations

**Now: The guardrails that stop these attacks**

---

# Defense Layers

```
┌─────────────────────────────────────────────┐
│  1. Identity Policy                         │  ← What you WANT to allow
├─────────────────────────────────────────────┤
│  2. Condition Keys                          │  ← WHEN and HOW it applies
├─────────────────────────────────────────────┤
│  3. Permissions Boundary                    │  ← Maximum you CAN allow
├─────────────────────────────────────────────┤
│  4. Resource Policy                         │  ← Who can access the resource
├─────────────────────────────────────────────┤
│  5. Service Control Policy (SCP)            │  ← Org-wide guardrails
└─────────────────────────────────────────────┘
```

Each layer provides independent defense. A hole in one is blocked by others.

---

# Permissions Boundaries

## The Maximum Permissions Envelope

---

# What is a Permissions Boundary?

A **permissions boundary** sets the *maximum* permissions an identity can have.

Think of it as a **ceiling** on permissions:
- Identity policy says what you *want* to allow
- Boundary says what you *can* allow
- Effective permissions = **intersection** (overlap)

---

# Visual: Intersection, Not Union

```
┌─────────────────────────────────┐
│   Permissions Boundary          │
│   ┌───────────────────────┐     │
│   │                       │     │
│   │    ┌───────────┐      │     │
│   │    │ EFFECTIVE │      │     │
│   │    │     ✓     │      │     │
│   │    └───────────┘      │     │
│   │  Identity Policy      │     │
│   └───────────────────────┘     │
│                                 │
└─────────────────────────────────┘
```

Only actions allowed by **BOTH** are effective.

---

# Fencin' the Frontier Preview: Permissions Boundary Defense

**Attack:** Attacker attaches `AdministratorAccess` to themselves
**Boundary:** Caps permissions to S3 read-only + EC2 describe

**Result:**
```
Identity Policy: AdministratorAccess (all actions)
Boundary: S3 read + EC2 describe
─────────────────────────────────────────────────
Effective: S3 read + EC2 describe
```

**"The boundary is a ceiling—it doesn't matter what policies say, you can't exceed it."**

---

# When to Use Permissions Boundaries

**Delegated administration:**
- Allow team leads to create users
- But limit what permissions they can grant

**Developer sandboxes:**
- Let developers experiment
- Prevent accidental (or intentional) privilege escalation

**Service accounts:**
- Cap what automation can do
- Even if the policy is misconfigured

---

# Permissions Boundary Example

Boundary (maximum allowed):
```json
{
  "Effect": "Allow",
  "Action": ["s3:*", "ec2:Describe*"],
  "Resource": "*"
}
```

Identity policy:
```json
{
  "Effect": "Allow",
  "Action": ["s3:*", "iam:*"],
  "Resource": "*"
}
```

**Effective permissions:** Only `s3:*` (IAM blocked by boundary)

---

# Resource Policies

## Including Trust Policies

---

# What is a Resource Policy?

A **resource policy** is attached to a resource, not an identity.

It controls **WHO** can access the resource, independent of the caller's identity policy.

**Examples:**
- S3 bucket policies
- KMS key policies
- SQS queue policies
- **IAM role trust policies** ← Key insight!

---

# Trust Policies ARE Resource Policies

When you create an IAM role, the **trust policy** is the resource policy.

It answers: **"Who can assume this role?"**

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {"Service": "ec2.amazonaws.com"},
    "Action": "sts:AssumeRole"
  }]
}
```

This trust policy says: "Only the EC2 service can assume this role."

---

# Fencin' the Frontier Preview: Trust Policy Defense

**Attack:** Attacker modifies trust policy to allow themselves to assume a privileged role

**Defense:** Harden the trust policy:
- Explicit principals (no wildcards)
- Require MFA for human access
- Restrict to specific services

```json
{
  "Principal": {"AWS": "arn:aws:iam::ACCOUNT:role/TrustedAdmin"},
  "Condition": {"Bool": {"aws:MultiFactorAuthPresent": "true"}}
}
```

---

# Resource Policy vs Identity Policy

| Aspect | Identity Policy | Resource Policy |
|--------|-----------------|-----------------|
| Attached to | User, role, group | The resource itself |
| Controls | What the identity can do | Who can access the resource |
| Scope | Follows the identity | Protects the resource |
| Cross-account | Requires both policies | Can grant access alone |

**Defense in depth:** Use BOTH for sensitive resources.

---

# Condition Keys

## Context-Based Restrictions

---

# What are Condition Keys?

Condition keys add **context-based restrictions** to policies.

They go beyond Action and Resource to ask questions like:
- What service is receiving this role?
- What IP address is the request from?
- Is MFA present?
- What tags does the resource have?

---

# The Key Condition: `iam:PassedToService`

When granting `iam:PassRole`, always ask: **"Passed to WHAT service?"**

```json
{
  "Effect": "Allow",
  "Action": "iam:PassRole",
  "Resource": "arn:aws:iam::*:role/EC2AppRole",
  "Condition": {
    "StringEquals": {
      "iam:PassedToService": "ec2.amazonaws.com"
    }
  }
}
```

Without this condition, the role could be passed to Lambda, SageMaker, or any service.

---

# Fencin' the Frontier Preview: Condition Key Defense

**Attack:** PassRole + RunInstances to launch EC2 with admin role

**Defense:** Add `iam:PassedToService` condition

**Result:**
```
Action: iam:PassRole
Resource: arn:aws:iam::*:role/EC2AppRole
Condition: iam:PassedToService = ec2.amazonaws.com
─────────────────────────────────────────────────
Role can ONLY be passed to EC2, not Lambda, etc.
```

---

# Common Condition Keys

| Condition Key | Use Case |
|---------------|----------|
| `iam:PassedToService` | Restrict which services can receive roles |
| `aws:MultiFactorAuthPresent` | Require MFA for sensitive actions |
| `aws:SourceIp` | Restrict to specific IP ranges |
| `aws:PrincipalOrgID` | Limit to your organization |
| `aws:RequestTag/*` | Control tagging operations |

---

# Service Control Policies (SCPs)

## Organization-Wide Guardrails

---

# What is an SCP?

A **Service Control Policy** sets permission guardrails across an entire AWS organization.

- Applies to all accounts in an OU (organizational unit)
- Cannot be overridden by account admins
- Does NOT grant permissions—only restricts them

**Analogy:** Permissions boundary for your whole organization

---

# SCP in the Defense Stack

```
┌─────────────────────────────────────────────┐
│  Identity Policy + Boundary                 │
│  ┌───────────────────────────────────────┐  │
│  │  Resource Policy                      │  │
│  │  ┌─────────────────────────────────┐  │  │
│  │  │  SCP (Org-wide)                 │  │  │
│  │  │  ┌───────────────────────────┐  │  │  │
│  │  │  │ EFFECTIVE PERMISSIONS    │  │  │  │
│  │  │  └───────────────────────────┘  │  │  │
│  │  └─────────────────────────────────┘  │  │
│  └───────────────────────────────────────┘  │
└─────────────────────────────────────────────┘
```

SCPs are the outermost layer—they affect EVERYONE in the org.

---

# SCP Example: Deny Region Access

Prevent all users in an OU from using non-approved regions:

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Sid": "DenyNonApprovedRegions",
    "Effect": "Deny",
    "Action": "*",
    "Resource": "*",
    "Condition": {
      "StringNotEquals": {
        "aws:RequestedRegion": ["us-east-1", "us-west-2"]
      }
    }
  }]
}
```

Even account admins cannot use other regions.

---

# SCP Example: Prevent Privilege Escalation

Block dangerous IAM operations across all accounts:

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Sid": "DenyPrivilegeEscalation",
    "Effect": "Deny",
    "Action": [
      "iam:CreateUser",
      "iam:CreateAccessKey",
      "iam:AttachUserPolicy",
      "iam:UpdateAssumeRolePolicy"
    ],
    "Resource": "*",
    "Condition": {
      "StringNotEquals": {
        "aws:PrincipalArn": "arn:aws:iam::*:role/SecurityTeamRole"
      }
    }
  }]
}
```

---

# SCPs: Key Points

- **Not in Fencin' the Frontier lab** — learners use sandbox accounts without Organizations
- **Lecture coverage only** — understand the concept for real-world use
- **Complement other layers** — don't replace identity policies or boundaries
- **Test carefully** — overly restrictive SCPs can break workloads

---

# Common IAM Misconfigurations

## Where Things Go Wrong

---

# Misconfiguration #1: Overly Permissive Wildcards

**The problem:**
```json
{
  "Effect": "Allow",
  "Action": "*",
  "Resource": "*"
}
```

**Why it's dangerous:**
- Full admin access to everything
- One compromised credential = game over
- Often called "God mode"

**The fix:** Be explicit about actions and resources

---

# Misconfiguration #2: Missing Resource Constraints

**The problem:**
```json
{
  "Effect": "Allow",
  "Action": "iam:AttachUserPolicy",
  "Resource": "*"
}
```

**Why it's dangerous:**
- Can attach any policy to any user
- Self-escalation to admin is trivial

**The fix:** Constrain to specific user ARNs or use `${aws:username}`

---

# Misconfiguration #3: Dangerous Action Combinations

**The problem:**
```json
{
  "Action": ["iam:PassRole", "ec2:RunInstances"],
  "Resource": "*"
}
```

**Why it's dangerous:**
- Pass admin role to EC2
- Launch instance with that role
- Get admin credentials from IMDS

**The fix:** Add `iam:PassedToService` condition + restrict role ARNs

---

# Other Dangerous Combinations

| Actions | Escalation Path |
|---------|-----------------|
| `iam:CreatePolicyVersion` | Modify existing policies to grant more access |
| `iam:AttachUserPolicy` | Attach AdministratorAccess to yourself |
| `iam:CreateAccessKey` | Create keys for other users |
| `iam:UpdateAssumeRolePolicy` | Let yourself assume privileged roles |
| `sts:AssumeRole` (unrestricted) | Assume any role in the account |

---

# Privilege Escalation Primer

## How Attackers Think

---

# What is Privilege Escalation?

**Starting point:** Low-privilege access (e.g., read-only user)

**Goal:** Gain higher privileges (e.g., admin access)

**Method:** Exploit misconfigurations, not vulnerabilities

> "The best privilege escalation doesn't exploit bugs —
> it uses exactly what you gave them permission to do."

---

# Escalation as Pathfinding

Think of IAM as a **graph**:
- **Nodes:** Users, roles, groups
- **Edges:** Permissions that connect them

Attackers look for **paths** from low privilege to high privilege.

```
Low-priv User → PassRole → EC2 → Admin Role
                    ↓
              Execute Code with Admin Permissions
```

---

# Tools for Finding Escalation Paths

**PMapper** (Principal Mapper)
- Open source from NCC Group
- Maps IAM relationships as a graph
- Identifies escalation paths automatically

**pathfinding.cloud**
- Web-based visualization
- Catalog of known privilege escalation paths
- Remediation recommendations

We'll use pathfinding.cloud in Fencin' the Frontier!

---

# Defense Strategy

## Reduce Paths, Not Just Permissions

1. **Apply least privilege** — fewer permissions = fewer paths
2. **Use permissions boundaries** — cap what users can grant
3. **Harden trust policies** — explicit principals, require MFA
4. **Add condition keys** — `iam:PassedToService` on all PassRole
5. **Use SCPs** — org-wide guardrails for sensitive actions
6. **Regular review** — permissions drift over time

---

# The "Swiss Cheese" Model

Multiple layers of defense:

```
┌─────────────────────────────────┐
│     Identity Policy             │  ← Hole: iam:PassRole
├─────────────────────────────────┤
│   Permissions Boundary          │  ← Blocks iam:*
├─────────────────────────────────┤
│   Resource Policy (Trust)       │  ← Explicit principals
├─────────────────────────────────┤
│   Service Control Policy        │  ← Org-wide deny
└─────────────────────────────────┘
```

Holes in one layer are blocked by others.

---

# Mapping Attacks to Guardrails

| Attack | Primary Guardrail | Why |
|--------|-------------------|-----|
| AttachUserPolicy | **Permissions Boundary** | Caps effective permissions even with admin policy |
| UpdateAssumeRolePolicy | **Resource Policy** | Trust policy controls who can assume |
| PassRole + EC2 | **Condition Key** | `iam:PassedToService` restricts target service |
| All of the above | **SCP** | Org-wide deny as backstop |

---

# Key Takeaways

1. **Permissions boundaries** set maximum permissions (intersection, not union)
2. **Trust policies ARE resource policies** — they control who can assume roles
3. **Condition keys** add context-based restrictions (`iam:PassedToService`)
4. **SCPs** provide org-wide guardrails (covered here, not in lab)
5. **Action combinations matter** — `PassRole` + service creation = escalation
6. **Defense in depth** — multiple layers catch what one layer misses

---

# Fencin' the Frontier Pattern: Attack → Defense → Verify

Each exercise follows the same three-part structure:

```
┌─────────────────────────────────────────────────────┐
│  Part A: EXPLOIT                                     │
│  Execute the attack to understand how it works       │
├─────────────────────────────────────────────────────┤
│  Part B: REMEDIATE                                   │
│  Apply the guardrail to block the attack             │
├─────────────────────────────────────────────────────┤
│  Part C: VERIFY                                      │
│  Confirm the guardrail actually stops the attack     │
└─────────────────────────────────────────────────────┘
```

**Why this pattern?** You can't defend what you don't understand.

| Exercise | Attack | Guardrail |
|----------|--------|-----------|
| 1 | AttachUserPolicy | **Permissions Boundary** |
| 2 | UpdateAssumeRolePolicy | **Trust Policy** (Resource Policy) |
| 3 | PassRole + EC2 | **Condition Key** (`iam:PassedToService`) |
| 4 | CreateAccessKey | **Resource Constraint** (`${aws:username}`) |

**Time:** 45 minutes

---

# Wrap-up/Questions?

---
