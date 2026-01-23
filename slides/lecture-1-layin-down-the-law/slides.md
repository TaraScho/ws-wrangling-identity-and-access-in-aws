---
marp: true
theme: default
paginate: true
header: 'Wrangling Identity and Access in AWS'
footer: 'Module 1: Layin'' Down the Law'
---

# Layin' Down the Law

## Understanding IAM and the PARC Model

---

# Learning Objectives

By the end of this lecture, you will be able to:

1. Explain what IAM is and why it's foundational to AWS security
2. Identify the four components of the PARC model
3. Read and interpret a basic IAM policy document

---

# Why This Matters

> "Capital One data breach exposes 100 million customers' data"
> — *2019*

**Root cause:** Misconfigured IAM role with overly permissive policies

A single misconfigured policy can expose:
- Customer data
- Financial records
- Your organization's reputation

---

# What is IAM?

**Identity and Access Management** is AWS's service for controlling *who* can do *what* to *which resources*.

Think of it as **the law in a frontier town**:
- Knows who you are (authentication)
- Knows what you're allowed to do (authorization)
- Enforces different rules for different places (fine-grained access)

---

# Authentication vs Authorization

| Authentication | Authorization |
|----------------|---------------|
| "Who are you?" | "What can you do?" |
| Proves identity | Grants permissions |
| Username/password, MFA | IAM policies |
| Happens first | Happens second |

**IAM handles both**, but today we focus on **authorization** through policies.

---

# The PARC Model

Four questions every access decision answers:

| Letter | Question | IAM Element |
|--------|----------|-------------|
| **P** | Who is making the request? | Principal |
| **A** | What are they trying to do? | Action |
| **R** | What are they trying to access? | Resource |
| **C** | Under what circumstances? | Condition |

---

# P is for Principal

**Who is making the request?**

Principals can be:
- IAM Users (humans or service accounts)
- IAM Roles (temporary credentials)
- AWS Services (like Lambda or EC2)
- Federated identities (SSO users)
- Anonymous (public access - usually bad!)

```
"Principal": {
  "AWS": "arn:aws:iam::123456789012:user/alice"
}
```

---

# A is for Action

**What are they trying to do?**

Actions follow the pattern: `service:operation`

Examples:
- `s3:GetObject` — Download a file from S3
- `ec2:StartInstances` — Start an EC2 instance
- `iam:CreateUser` — Create a new IAM user

**The wildcard `*` matches all actions — dangerous!**

```
"Action": ["s3:GetObject", "s3:ListBucket"]
```

---

# R is for Resource

**What are they trying to access?**

Resources are identified by ARN (Amazon Resource Name):

```
arn:aws:s3:::my-bucket/documents/*
│   │   │    │         │
│   │   │    │         └── Object key pattern
│   │   │    └── Bucket name
│   │   └── Service (S3)
│   └── Partition (aws)
└── ARN prefix
```

**Specify exact resources — avoid `*` when possible!**

---

# C is for Condition

**Under what circumstances?**

Add extra guardrails beyond action + resource:

- `aws:SourceIp` — Only from specific IP addresses
- `aws:MultiFactorAuthPresent` — Require MFA
- `s3:prefix` — Only certain S3 prefixes
- `aws:RequestedRegion` — Only in certain regions

```json
"Condition": {
  "IpAddress": {
    "aws:SourceIp": "203.0.113.0/24"
  }
}
```

---

# Anatomy of a Policy

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowS3ReadAccess",
      "Effect": "Allow",
      "Action": ["s3:GetObject"],
      "Resource": "arn:aws:s3:::my-bucket/*",
      "Condition": {
        "IpAddress": {
          "aws:SourceIp": "10.0.0.0/8"
        }
      }
    }
  ]
}
```

---

# Policy Components Explained

| Field | Purpose |
|-------|---------|
| `Version` | Always `"2012-10-17"` (current policy language) |
| `Statement` | Array of permission rules |
| `Sid` | Optional statement identifier |
| `Effect` | `"Allow"` or `"Deny"` |
| `Action` | What operations are permitted |
| `Resource` | What AWS resources this applies to |
| `Condition` | Optional additional constraints |

---

# Allow vs Deny

TODO: replace with policy evaluation diagram

**Default behavior:** Everything is denied unless explicitly allowed

**Evaluation order:**
1. Explicit Deny always wins
2. Explicit Allow grants access
3. Implicit Deny (default) if no match

```
Explicit Deny > Explicit Allow > Implicit Deny
```

---

# Reading a Policy: Practice

TODO: replace these slides with better examples

What does this policy allow?

```json
{
  "Effect": "Allow",
  "Action": "s3:*",
  "Resource": "*"
}
```

**Answer:** Full S3 access to ALL buckets in ALL accounts
**Risk:** Extremely dangerous — never use in production!

---

# Reading a Policy: Better Version

```json
{
  "Effect": "Allow",
  "Action": ["s3:GetObject", "s3:ListBucket"],
  "Resource": [
    "arn:aws:s3:::company-public-assets",
    "arn:aws:s3:::company-public-assets/*"
  ]
}
```

**Better because:**
- Specific actions (read-only)
- Specific resource (one bucket)
- No dangerous wildcards

---

# The Principle of Least Privilege

TODO: replace this slide with more nuanced example

> Grant only the minimum permissions required to perform a task.

**Ask yourself:**
- Does this user need `s3:*` or just `s3:GetObject`?
- Does this apply to all buckets or just one?
- Should this work from anywhere or just the office?

**When in doubt, deny. You can always add permissions later.**

---

# Privilege Escalation Categories

How do attackers abuse IAM misconfigurations?

| Category | Description |
|----------|-------------|
| **Self-Escalation** | Modify your own permissions directly |
| **Principal Access** | Gain access to other users/roles |
| **New PassRole** | Create new resources with privileged roles |
| **Existing PassRole** | Modify existing resources to leverage their roles |
| **Credential Access** | Access hardcoded or stored credentials |

---

# Category 1: Self-Escalation

TODO: replace/enhance each of these category slides with images from pathfinding.cloud

**Definition:** Modify your own permissions directly

**Example Attack:**
```
iam:CreatePolicyVersion
```
Create a new version of a policy you control with admin permissions.

**PARC Flaw:** `Resource: "*"` allows modifying any policy

**Why it works:** Policy versions are separate from policy attachment—create a privileged version, then it's automatically in effect.

---

# Category 2: Principal Access

**Definition:** Gain access to other principals (users/roles)

**Example Attack:**
```
iam:CreateAccessKey with Resource: "*"
```
Create access keys for ANY user, including admins.

**PARC Flaw:** Missing resource constraint

**Why it works:** You don't need a user's password to become them—just create new credentials.

---

# Category 3: New PassRole

**Definition:** Create new resources and pass privileged roles to them

**Example Attack:**
```
iam:PassRole + ec2:RunInstances
```
Launch EC2 with an admin role, then curl the metadata service for credentials.

**PARC Flaw:** No `iam:PassedToService` condition

**Why it works:** PassRole + resource creation = code execution as that role.

---

# Category 4: Existing PassRole

**Definition:** Modify existing resources to leverage their attached roles

**Example Attack:**
```
lambda:UpdateFunctionCode
```
Modify a Lambda function that has a privileged execution role.

**PARC Flaw:** Resource access without role restriction

**Why it works:** You don't pass the role—you hijack a resource that already has one.

---

# Category 5: Credential Access

**Definition:** Access hardcoded or stored credentials (not through IAM)

**Example Attack:**
```
lambda:GetFunction  # Extract env vars with secrets
ssm:GetParameter    # Read secrets from Parameter Store
```

**PARC Flaw:** Overly broad read access to secrets

**Why it works:** Credentials stored outside IAM bypass IAM privilege escalation controls entirely.

---

# Up Next: Layin' Down the Law Lab

TODO - add images from pmapper and pathfinding.cloud - we will introduce pmapper on this slide

## Identifying IAM Misconfigurations

You will:
1. Deploy iam-vulnerable infrastructure
2. Run pmapper to scan for privilege escalation paths
3. Use pathfinding.cloud to understand the findings
4. Categorize misconfigurations into the 5 categories

**Time:** 40 minutes