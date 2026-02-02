# Lab 1 - Layin' Down the Law: Identifying and Exploiting IAM Misconfigurations

**Duration:** 40 minutes

## Overview

Use **awspx**, **pmapper** (Principal Mapper), and **pathfinding.cloud** to identify and exploit privilege escalation paths in intentionally vulnerable IAM configurations.

**Learning Objectives:**
1. Visualize IAM relationships with awspx
2. Scan and analyze IAM with pmapper
3. Identify privilege escalation paths
4. Exploit misconfigurations to understand the risk

---

## Prerequisites

Complete [Lab 0 - Prerequisites](../lab-0-prerequisites/lab-0-prerequisites.md) before starting this lab. If you are taking this workshop at Wild West Hackin Fest, your environment is already preconfigured.

---

## Exercise 1: Setup awspx and pmapper

### Part A: Ingest AWS Data with awspx

awspx visualizes IAM relationships as an interactive graph.

1. Run the awspx ingest command to pull IAM data from your AWS account:
   ```bash
   docker exec -it awspx awspx ingest
   ```

   Expected output:
   ```
   [*] Collecting IAM data...
   [*] Processing 90 resources...
   [*] Graph updated successfully
   ```

2. Open awspx in your browser at [http://localhost](http://localhost)

3. Verify the graph loaded by searching for `iamws` in the search box - you should see the workshop IAM users

### Part B: Create pmapper Graph

pmapper analyzes IAM relationships and finds privilege escalation paths.

1. Create a graph of your AWS account:
   ```bash
   pmapper graph create
   ```

2. View the graph summary:
   ```bash
   pmapper graph display
   ```

   Expected output:
   ```
   Graph Data for Account:  <your-account-id>
     # of Nodes:              90 (16 admins)
     # of Edges:              317
     # of Groups:             3
     # of (tracked) Policies: 75
   ```

### Part C: Run pmapper Analysis

1. Run the privilege escalation analysis:
   ```bash
   pmapper analysis --output-type text
   ```

2. Review the findings. Look for users with names starting with `iamws-`:
   ```
   iamws-dev-self-service-user can escalate privileges by attaching a different policy to themselves
   iamws-team-onboarding-user can escalate privileges by creating access keys for another user
   iamws-integration-admin-user can escalate privileges by updating the trust policy of a role
   iamws-ci-runner-user can escalate privileges by passing a role to EC2
   ```

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