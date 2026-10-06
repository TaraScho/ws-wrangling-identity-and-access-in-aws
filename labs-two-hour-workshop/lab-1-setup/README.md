# Two-Hour Workshop — Lab Setup

## Overview

Before the first attack scenario you'll set up your workstation, deploy the vulnerable lab infrastructure into your own AWS sandbox, and build the IAM recon graph that every scenario in the workshop will query. By the end of this setup you will have:

- A workstation with every workshop dependency installed by the setup script
- Six intentionally-vulnerable IAM users, plus a least-privilege `iamws-scanner-user` for read-only recon and an `iamws-lab-default` admin user for setup/debugging/cleanup, all deployed into your AWS sandbox
- An [`iam-recon`](https://github.com/andrewkrug/iam-recon) graph of the account, ready to query offline
- A working mental model of the five privilege escalation categories used by [pathfinding.cloud](https://pathfinding.cloud)
- A short tour of the graph so you know where every scenario starts before we begin Scenario 1a

---

## Before you begin — bring your own AWS sandbox

This workshop intentionally deploys vulnerable IAM resources. You need an AWS account that is **strictly a sandbox** — never use a production account, never use an account that hosts anything you care about.

In that sandbox account you'll need an IAM identity (user or role) with permission to create:

- IAM users, roles, policies, and access keys
- Lambda functions
- EC2 instances and security groups
- S3 buckets
- CloudFormation stacks
- Secrets Manager secrets

`ReadOnlyAccess` plus the create permissions above is sufficient. An admin identity in a sandbox account also works.

> [!IMPORTANT]
> Never deploy the lab into a production AWS account. The Terraform that runs in Step 4 creates IAM users with deliberately exploitable permissions. Use a dedicated sandbox. We will provide instructions at the end to clean up the account. 

> [!NOTE]
> Don't have an AWS sandbox account? AWS provides [free-tier account sign-up](https://aws.amazon.com/free) instructions.

---

## Step 1: Check your system requirements

You'll run the labs from a terminal on your own machine or workstation. The setup script in Step 4 installs every workshop tool for you, so all you need to bring is a supported operating system.

- **macOS or Linux users** — you're already good to go. Both the Intel/AMD (`x86_64`) and Apple Silicon / ARM (`aarch64`) architectures are supported.
- **Windows users** — some workshop tools don't ship a Windows build (`iam-recon` has no native Windows binary), so we suggest running the labs inside a VM or setting up **WSL2 with Ubuntu**, which gives you a real Linux environment on your Windows machine. See Microsoft's [WSL2 install guide](https://learn.microsoft.com/en-us/windows/wsl/install) to set it up, then run every command in this workshop from your Ubuntu shell.

It's your choice whether to work from your main OS directly or from a dedicated VM. If you'd rather keep the workshop's tooling and AWS credentials isolated from your day-to-day machine, you can use your virtualization tool of choice such as VirtualBox or Tart. More information about virtualization tools workshop attendees have used in the past is available [in this document](https://docs.google.com/document/d/1bLbSTfht3QR-hxu03v33n1x-NdZ5XBlaXHqSjfx8-gY/edit?usp=sharing). 

**If you are not already familiar with virtualization and virtual machines, we do not recommend trying to set up a VM. We will provide clean up instructions for your local machine at the end of the workshop.**

---

## Step 2: Authenticate to your AWS sandbox account in the terminal

You need an authenticated terminal session for your **sandbox AWS account** before running the setup script.

1. Generate or retrieve credentials for the IAM identity you described in [Before you begin](#before-you-begin--bring-your-own-aws-sandbox). The [AWS CLI authentication docs](https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-authentication.html) walk through every supported method (IAM Identity Center, long-lived access keys, AssumeRole, etc.) — pick whichever your sandbox uses.

1. Export the credentials in your terminal:

   ```bash
   export AWS_ACCESS_KEY_ID=AKIA...
   export AWS_SECRET_ACCESS_KEY=...
   export AWS_SESSION_TOKEN=...   # only if you're using temporary credentials
   ```

1. Verify:

   ```bash
   aws sts get-caller-identity
   ```

   The returned `Arn` should match the IAM identity in your sandbox account.

---

## Step 3: Clone the workshop repository

```bash
git clone https://github.com/TaraScho/ws-wrangling-identity-and-access-in-aws.git ~/workshop
cd ~/workshop
```

---

## Step 4: Run the setup script

### What the script installs

The script only installs a tool if it isn't already on your `PATH`, so if you pre-installed any of these it'll simply skip them. Expect any of the following to be installed if missing:

| Tool                        | Source                                                                                  | Why                                                                       |
|-----------------------------|-----------------------------------------------------------------------------------------|---------------------------------------------------------------------------|
| AWS CLI v2                  | [AWS CLI install guide](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) | Used by every lab — Terraform calls it, profile config, and all exploit/defense steps |
| Terraform (v1.14.x)         | [HashiCorp install guide](https://developer.hashicorp.com/terraform/install) ([OpenTofu](https://opentofu.org/) works too) | Deploys the vulnerable lab infrastructure                                 |
| `iam-recon`                 | [iam-recon releases](https://github.com/andrewkrug/iam-recon/releases)                     | Builds the IAM graph used by every scenario                               |
| SSM Session Manager plugin  | [AWS install guide](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html) | Lets `aws ssm start-session` connect to the lab EC2 instance in Scenario 3 |

Beyond installing those tools, the script also deploys the lab and wires up your credentials. Run it now:

```bash
bash labs-two-hour-workshop/setup.sh
```

The script:

1. Verifies prerequisites (AWS credentials, base Unix tools)
1. Installs any missing workshop dependencies (the four tools above)
1. Runs `terraform apply` to deploy the vulnerable lab infrastructure into your sandbox account
1. Configures AWS CLI profiles for **eight** users — the six intentionally-vulnerable scenario users, `iamws-scanner-user` (a least-privilege read-only identity used for IAM reconnaissance), and `iamws-lab-default` (an admin identity used outside the attack scenarios for setup, debugging, and cleanup). It also mirrors `iamws-lab-default`'s credentials into the unnamed `default` profile so the CLI keeps working if you lose your shell session.

When every check passes you'll see a banner like:

```
=== Setup Complete! (7/7 checks passed) ===

You're ready to start the workshop. Happy hacking!
```

You can re-run the script safely — every install step is idempotent.

---

## Step 5: Reload your shell

The setup script added the workshop tools directory to your `PATH` in `~/.bashrc`, `~/.profile`, and `~/.zshrc`. Reload your current shell so the new entries take effect. On macOS the default shell is zsh:

```bash
source ~/.zshrc
```

On Linux or WSL2 (bash):

```bash
source ~/.bashrc
```

Not sure which shell you're in? Run `echo $SHELL`.

---

## Step 6: Privilege escalation categories

Before you start identifying vulnerabilities, get familiar with how the security community organizes privilege escalation attacks. Throughout this workshop we'll reference [pathfinding.cloud](https://pathfinding.cloud), an open source knowledge base for understanding, detecting, and demonstrating AWS IAM privilege escalation.

1. Navigate to [pathfinding.cloud](https://pathfinding.cloud) in your browser.

1. Open the **Privilege Escalation Library**.

1. Note the **CATEGORY** drop-down filter. As of writing, pathfinding.cloud organizes paths into five categories:

   | Category              | Description                                                                                |
   |-----------------------|--------------------------------------------------------------------------------------------|
   | **Self-Escalation**   | Modify your own permissions directly to escalate privileges                                |
   | **Principal Access**  | Gain access to a different principal to escalate privileges                                |
   | **New PassRole**      | Create a new resource (EC2, Lambda, etc.) and pass a privileged role to it                 |
   | **Existing PassRole** | Modify an existing resource with an attached role and gain access to that role             |
   | **Credential Access** | Access hardcoded credentials stored insecurely                                             |

   You'll exploit vulnerabilities from each of these categories during the workshop. Click into a few paths now to see how each one is described — every iam-recon finding you'll see in Step 8 links back to one of these paths.

---

## Step 7: Familiarize yourself with `iam-recon`

`iam-recon` is a single-binary Rust tool that graphs every IAM user, role, group, and policy in an AWS account, then maps the resulting privileges to the 66+ known attack paths catalogued by pathfinding.cloud. It consolidates the capabilities of the older Python tools you may have seen (PMapper, awspx) into one binary, plus first-class pathfinding.cloud integration.

What you can do with it:

- Build an offline graph of an AWS account in one command, then query it forever without re-hitting the AWS API
- Identify principals that have known privilege escalation paths (`pathfinding`, `argquery --preset privesc`)
- Confirm individual permissions against simulated policy evaluation (`argquery --principal <name> --action <action>`)
- Explore the graph visually in a browser (`visualize --interactive-viz`) or in a terminal dashboard (`--tui`)

To start, confirm it's on your `PATH`:

```bash
iam-recon --help | head -5
```

Expected output

```bash
AWS IAM privilege escalation and attack path mapper

Usage: iam-recon [OPTIONS] [COMMAND]

Commands:
```

---

## Step 8: Build the IAM graph

Build the graph:

```bash
iam-recon graph create --profile iamws-scanner-user
```

> [!NOTE]
> **Why a dedicated scanner profile?** `iamws-scanner-user` is attached to the AWS-managed `SecurityAudit` policy — read-only access to IAM and every service iam-recon enumerates. Recon is a read-only activity; doing it with a least-privilege identity (instead of an admin profile) is the same principle you'll defend against attackers in Lab 2. Every other workshop scenario uses a scenario-specific exercise profile (e.g., `iamws-policy-developer-user`) for exploitation — never the scanner.

This takes about 30 seconds. Under the hood, iam-recon:

1. Calls `sts:GetCallerIdentity` and `iam:GetAccountAuthorizationDetails` (a single paginated API call that returns every user, role, group, and policy in the account)
1. Runs nine privilege escalation **edge checkers** — IAM, STS, Lambda, EC2, CodeBuild, CloudFormation, AutoScaling, SSM, SageMaker — and adds a graph edge whenever it finds a chain like "user X can launch an EC2 instance with role Y attached"
1. Caches every API response to `~/.local/share/iam-recon/<account-id>/`

When it finishes you'll see something like:

```
Graph Data for Account:  <account ID>
  OK Graph stored at /Users/tara.schofield/Library/Application Support/iam-recon/<account id>
      159 nodes, 503 edges
       API responses cached for offline queries
```

> [!NOTE]
> Your sandbox account will likely have less nodes and edges, this is just example output.

Set the AWS account ID in your environment so that `iam-recon`.

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text --profile iamws-scanner-user)
```

Now, every subsequent iam-recon command can run fully offline by passing `--account $ACCOUNT_ID`. If you had data for multiple AWS accounts stored in `~/.local/share/iam-recon/<account-id>/`, you would use the `--account` argument to specify which AWS account you want `iam-recon` to query.

You can re-display the initial scan summary at any time without rescanning:

```bash
iam-recon --account $ACCOUNT_ID graph display
```

---

## Step 9: Tour the data

Try the following three commands. These are examples of the types of `iam-recon` commands you will use throughout the rest of the workshop in different scenarios.

### 9a. Map permissions to known attack paths (`pathfinding`)

```bash
iam-recon --account $ACCOUNT_ID pathfinding
```

This is the primary recon command — it checks every principal against the bundled pathfinding.cloud database and prints one entry per whenever an IAM principal in the account matches a known attack path. Each entry looks like:

```
[iam-001] user/iamws-policy-developer-user (self-escalation)
    Path: iam:CreatePolicyVersion
    Perms: iam:CreatePolicyVersion
    https://www.pathfinding.cloud/paths/iam-001
```

The bracketed ID (`iam-001`) is the pathfinding.cloud path identifier — every scenario in this workshop will point you at one or more of these IDs.

### 9b. Visualize the graph (`visualize --interactive-viz`)

```bash
iam-recon --account $ACCOUNT_ID visualize --interactive-viz
```

iam-recon prints a line like `Interactive visualization available at: http://127.0.0.1:54321` — **the port is dynamic**, so copy the URL it prints.

The page renders a visual graph of every principal `iam-recon` found. The graph is color coded:

- **Red nodes** — admin-tier principals (full `*:*` access)
- **Orange nodes** — principals with at least one known privilege escalation path
- **Blue nodes** — regular users with no found priv esc paths
- **Light cyan nodes** — regular roles with no found priv esc paths

Click a node to inspect its policies and trust relationships. Click an edge to see the policy document that creates a relationship between two linked IAM principals (e.g., the inline policy granting `iam:PassRole` might link a user node and a role node).

Click a few user and role nodes to get a feel for the inspector panel — node properties, attached policies, group membership, and the pathfinding.cloud paths each principal is part of.

Press `Ctrl+C` in the terminal when you're done — the visualization keeps running until you stop it.

### 9c. Check a specific permission (`argquery`)

```bash
iam-recon --account $ACCOUNT_ID argquery \
  --principal user/iamws-policy-developer-user \
  --action iam:CreatePolicyVersion
```

This command evaluates a single principal against a single IAM action and prints `ALLOW` or `DENY`. You'll use this in every scenario to confirm a specific permission before exploiting it.

Expected output for the example above:

```
ALLOW user/iamws-policy-developer-user can call iam:CreatePolicyVersion with *
```

---

## Step 10: Optional — Terminal dashboard

If you prefer a CLI-first view (rather than the graph in browser), iam-recon ships a TUI. Try it out with the following command:

```bash
iam-recon --tui --account $ACCOUNT_ID
```

Navigate with the arrow keys. Press `q` to quit. The TUI is purely a viewing tool — every action it surfaces is available as a regular CLI command, so feel free to skip it.

## Lab summary

When you have successfully created the lab resources in your AWS account, and ran the example `iam-recon` commands above, you have successfully completed your lab set up! You are ready to move on to lab 2 and the **Self Privilege Escalation via CreatePolicyVersion** scenario. You are welcome to start working on lab 2 now using the instructions in GitHub. Or you can sit tight and wait for the instructors to introduce lab 2 before you get started.