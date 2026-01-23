# Lab 1 - Layin' Down the Law: Identifying IAM Misconfigurations

**Duration:** 40 minutes

## Overview

Use **pmapper** (Principal Mapper) and **pathfinding.cloud** to identify privilege escalation paths in intentionally vulnerable IAM configurations. This lab focuses on **finding and understanding** misconfigurations—Fencin' the Frontier (Lab 2) will cover exploitation and remediation.

**Learning Objectives:**
1. Deploy and scan IAM infrastructure with pmapper
2. Interpret privilege escalation findings
3. Categorize findings into the 5 escalation categories
4. Use pathfinding.cloud to understand attack paths

---

## Setup

### Step 1: Configure AWS Credentials

Ensure your AWS CLI is configured with credentials for your sandbox account:

```bash
aws sts get-caller-identity
```

You should see your account ID and IAM principal. These credentials need permissions to create IAM resources.

### Step 2: Deploy Vulnerable Infrastructure

> **IMPORTANT:** 🚨 This lab deploys intentionally vulnerable IAM infrastructure to your sandbox account. Do not run this in your production account.

1. Navigate to the terraform directory:
   ```bash
   cd labs/terraform
   ```

2. Initialize and apply Terraform:
   ```bash
   terraform init
   terraform apply
   ```

3. When prompted, type `yes` to confirm the resources to be created in AWS.

### Step 3: Install pmapper

Install Principal Mapper (pmapper) from NCC Group:

```bash
pip install principalmapper
```

Verify installation:
```bash
pmapper --version
```

---

## Exercise 1: Scan AWS with pmapper

### Part A: Build the IAM Graph

pmapper analyzes IAM relationships by building a graph of principals and their permissions.

1. Create a graph of your AWS account:
   ```bash
   pmapper graph create
   ```

   This command:
   - Enumerates all IAM users, roles, and groups
   - Maps all policies (managed and inline)
   - Builds a graph of permission relationships

2. View the graph summary:
   ```bash
   pmapper graph display
   ```

### Part B: Find Privilege Escalation Paths

1. Run the privilege escalation analysis:
   ```bash
   pmapper analysis find_privesc
   ```

2. Save the output for reference:
   ```bash
   pmapper analysis find_privesc > pmapper-findings.txt
   ```

3. Review the findings. You should see output like:
   ```
   User privesc7-AttachUserPolicy can escalate privileges by attaching a different policy to themselves
   User privesc14-UpdatingAssumeRolePolicy can escalate privileges by updating the trust policy of role ...
   User privesc3-CreateEC2WithExistingIP can escalate privileges by creating an EC2 instance with role ...
   ```

### Part C: Query Specific Paths

pmapper can query specific permission relationships:

1. Check if a user can reach admin:
   ```bash
   pmapper query "who can do iam:* with *"
   ```

2. Check what a specific user can do:
   ```bash
   pmapper query "can privesc7-AttachUserPolicy do iam:AttachUserPolicy with *"
   ```

3. Continue exploring the pmapper findings. Consider questions like the following:

- How many privilege escalation paths did pmapper find?
- Which users have the most escalation options?
- Which paths are the most dangerous?

---

## Exercise 2: Investigate Privilege Escalation Paths

In this exercise, you'll investigate each privilege escalation path found by pmapper. For each path, you'll:
1. Use pmapper to query the specific finding
2. Navigate to pathfinding.cloud to understand the attack in depth
3. Review the attack details and remediation strategies

---

### Path 1: AttachUserPolicy (Self-Escalation)

**pmapper Investigation:**

Query the specific user to confirm their escalation capability:

```bash
pmapper query "can privesc7-AttachUserPolicy do iam:AttachUserPolicy with *"
```

This confirms the user can attach policies to themselves—a classic self-escalation vulnerability.

**pathfinding.cloud Investigation:**

1. Open [pathfinding.cloud](https://pathfinding.cloud) in your browser

2. Browse the **Categories** section on the left sidebar:
   - Self-Escalation
   - Principal Access
   - New PassRole
   - Existing PassRole
   - Credential Access

3. Navigate to **Self-Escalation** → **[IAM-007: iam:AttachUserPolicy](https://pathfinding.cloud/paths/iam-007)**

4. Review the path details:
   - **Description** — What the attack does
   - **Required Permissions** — What permissions enable it
   - **Attack Steps** — How an attacker would execute it
   - **Remediation** — How to fix it (you'll implement this in Lab 2!)

---

### Path 2: UpdateAssumeRolePolicy (Principal Access)

**pmapper Investigation:**

Query the user's escalation path:

```bash
pmapper query "can privesc14-UpdatingAssumeRolePolicy do iam:UpdateAssumeRolePolicy with *"
```

This user can modify trust policies on roles, allowing them to grant themselves access to assume privileged roles.

**pathfinding.cloud Investigation:**

1. Navigate to **Principal Access** → **[IAM-012: iam:UpdateAssumeRolePolicy](https://pathfinding.cloud/paths/iam-012)**

2. Review the path details:
   - **Description** — How modifying trust policies enables escalation
   - **Required Permissions** — The dangerous combination of permissions
   - **Attack Steps** — The specific API calls an attacker would use
   - **Remediation** — Trust policy hardening strategies

---

### Path 3: PassRole + EC2 (New PassRole)

**pmapper Investigation:**

Query the user's ability to pass roles:

```bash
pmapper query "can privesc3-CreateEC2WithExistingIP do iam:PassRole with *"
```

This user can pass high-privilege roles to EC2 instances they create, then access those credentials.

**pathfinding.cloud Investigation:**

1. Navigate to **New PassRole** → **[EC2-001: iam:PassRole + ec2:RunInstances](https://pathfinding.cloud/paths/ec2-001)**

2. Review the path details:
   - **Description** — How PassRole enables privilege escalation through compute services
   - **Required Permissions** — The PassRole + service combination
   - **Attack Steps** — Creating an instance and harvesting credentials
   - **Remediation** — Condition key restrictions on PassRole

---

### Path 4: CreateAccessKey (Principal Access)

**pmapper Investigation:**

Query for users who can create access keys for other principals:

```bash
pmapper query "who can do iam:CreateAccessKey with *"
```

This identifies users who can create credentials for other IAM users—potentially including admin users.

**pathfinding.cloud Investigation:**

1. Navigate to **Principal Access** → **[IAM-002: iam:CreateAccessKey](https://pathfinding.cloud/paths/iam-002)**

2. Review the path details:
   - **Description** — How creating keys for other users enables escalation
   - **Required Permissions** — The unrestricted CreateAccessKey permission
   - **Attack Steps** — Creating keys for privileged users
   - **Remediation** — Resource constraints limiting key creation to self

---

## Wrap-up

### Summary: Findings to Fencin' the Frontier Remediations

| Finding | Category | Fencin' the Frontier Exercise | Guardrail |
|---------|----------|----------------|-----------|
| AttachUserPolicy | Self-Escalation | Exercise 1 | **Permissions Boundary** |
| UpdateAssumeRolePolicy | Principal Access | Exercise 2 | **Trust Policy (Resource Policy)** |
| PassRole + EC2 | New PassRole | Exercise 3 | **Condition Key** |
| CreateAccessKey | Principal Access | Exercise 4 | **Resource Constraint** |

In the next lab, you will apply guardrails to the vulnerable infrastructure to remediate the privilege escalation paths.

---

## Optional: Additional pmapper Commands

If you finish early, explore these additional pmapper capabilities:

```bash
# Visualize the graph (requires graphviz)
pmapper graph visualize

# Find all paths to a specific role
pmapper query "who can pass role AdminRole to *"

# Check for cross-account access
pmapper analysis cross_account

# Export findings as JSON
pmapper analysis find_privesc --output json > findings.json
```

---