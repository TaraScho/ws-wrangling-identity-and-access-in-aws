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
> Never deploy the lab into a production AWS account. The Terraform that runs in Step 4 creates IAM users with deliberately exploitable permissions. Use a dedicated sandbox.

> [!NOTE]
> Need a sandbox? Setting one up is out of scope for this workshop — allow ~30 minutes before the session if you're starting from scratch. AWS's [free-tier sign-up](https://aws.amazon.com/free) is one way to get a dedicated account.

---

## Step 1: Check your system requirements

You'll run the labs from a terminal on your own machine. The setup script in Step 4 installs every workshop tool for you, so all you need to bring is a supported operating system.

- **macOS or Linux** — you're already good to go. Both the Intel/AMD (`x86_64`) and Apple Silicon / ARM (`aarch64`) architectures are supported.
- **Windows** — our tooling doesn't ship a Windows build (`iam-recon` has no native Windows binary), so we suggest running the labs inside **WSL2 with Ubuntu**, which gives you a real Linux environment on your Windows machine. See Microsoft's [WSL2 install guide](https://learn.microsoft.com/en-us/windows/wsl/install) to set it up, then run every command in this workshop from your Ubuntu shell.

It's your choice whether to work from your main OS directly or from a dedicated VM — the setup script runs the same either way. If you'd rather keep the workshop's intentionally-vulnerable tooling and credentials isolated from your day-to-day machine, a throwaway Linux VM (or WSL2 on Windows) is a reasonable way to do that.

---

## Step 2: Authenticate to your sandbox account in the terminal

You need an authenticated terminal session against **your own sandbox account** before running the setup script.

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

The setup script added the workshop tools directory to your `PATH`. Reload your current shell so the new entries take effect:

```bash
source ~/.bashrc
```

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

## Step 7: Meet `iam-recon`

`iam-recon` is a single-binary Rust tool that builds a directed graph of every IAM user, role, group, and policy in an AWS account, then maps the resulting privileges to the 66+ known attack paths catalogued by pathfinding.cloud. It is the only recon tool used in this workshop — it consolidates the capabilities of the older Python tools you may have seen (PMapper, awspx) into one binary, plus first-class pathfinding.cloud integration.

What you can do with it:

- Build an offline graph of an AWS account in one command, then query it forever without re-hitting the AWS API
- Identify principals that have known privilege escalation paths (`pathfinding`, `argquery --preset privesc`)
- Confirm individual permissions against simulated policy evaluation (`argquery --principal <name> --action <action>`)
- Explore the graph visually in a browser (`visualize --interactive-viz`) or in a terminal dashboard (`--tui`)

Confirm it's on your `PATH`:

```bash
iam-recon --help | head -5
```

---

## Step 8: Build the IAM graph

Set the account ID once so you can reuse it for every iam-recon query in this and later steps:

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text --profile iamws-scanner-user)
```

Build the graph:

```bash
iam-recon graph create --profile iamws-scanner-user
```

This takes about 30 seconds. Under the hood, iam-recon:

1. Calls `sts:GetCallerIdentity` and `iam:GetAccountAuthorizationDetails` (a single paginated API call that returns every user, role, group, and policy in the account)
1. Runs nine privilege escalation **edge checkers** — IAM, STS, Lambda, EC2, CodeBuild, CloudFormation, AutoScaling, SSM, SageMaker — and adds a graph edge whenever it finds a chain like "user X can launch an EC2 instance with role Y attached"
1. Caches every API response to `~/.local/share/iam-recon/<account-id>/`, so every subsequent iam-recon command can run fully offline by passing `--account $ACCOUNT_ID`

When it finishes you'll see something like:

```
Graph Data for Account:  <account ID>
# of Nodes:              ~36
# of Edges:              ~20  (privilege escalation edges)
# of Groups:             2
# of (tracked) Policies: ~50
# of Admins:             ~7
```

> [!NOTE]
> **Why a dedicated scanner profile?** `iamws-scanner-user` is attached to the AWS-managed `SecurityAudit` policy — read-only access to IAM and every service iam-recon enumerates. Recon is a read-only activity; doing it with a least-privilege identity (instead of an admin profile) is the same principle you'll defend against attackers in Lab 2. Every other workshop scenario uses a scenario-specific exercise profile (e.g., `iamws-policy-developer-user`) for exploitation — never the scanner.

You can re-display this summary at any time without rescanning:

```bash
iam-recon --account $ACCOUNT_ID graph display
```

---

## Step 9: Tour the data

The three commands below are the iam-recon surfaces you'll use across the rest of the workshop. Run them now so you know what each one looks like — and so you finish setup oriented in the graph that every scenario will reference.

### 9a. Map permissions to known attack paths (`pathfinding`)

```bash
iam-recon --account $ACCOUNT_ID pathfinding
```

This is the primary recon command — it walks every principal against the bundled pathfinding.cloud database and prints one entry per match. Each entry looks like:

```
[iam-001] user/iamws-policy-developer-user (self-escalation)
    Path: iam:CreatePolicyVersion
    Perms: iam:CreatePolicyVersion
    https://www.pathfinding.cloud/paths/iam-001
```

The bracketed ID (`iam-001`) is the pathfinding.cloud path identifier — every scenario in this workshop will point you at one or more of these IDs and ask you to find them in this output.

### 9b. Visualize the graph (`visualize --interactive-viz`)

```bash
iam-recon --account $ACCOUNT_ID visualize --interactive-viz
```

iam-recon prints a line like `Interactive visualization available at: http://127.0.0.1:54321` — **the port is dynamic**, so copy the URL it prints (the browser should also open automatically). The page renders a force-directed graph of every principal:

- **Red nodes** — admin-tier principals (full `*:*` access)
- **Orange nodes** — principals with at least one known privilege escalation path
- **Blue nodes** — regular users
- **Light cyan nodes** — regular roles

Click a node to inspect its policies and trust relationships. Click an edge to see the policy document that created it (e.g., the inline policy granting `iam:PassRole`).

Now enable the **Privesc** filter in the viz toolbar. The graph should collapse to roughly 8 highlighted principals — **these are the starting points for the scenarios you're about to run.** Your instructor will walk through which highlighted node corresponds to which scenario. Click a few of them to get a feel for the inspector panel — node properties, attached policies, group membership, and the pathfinding.cloud paths each principal is implicated in.

Press `Ctrl+C` in the terminal when you're done — the visualization keeps running until you stop it.

### 9c. Check a specific permission (`argquery`)

```bash
iam-recon --account $ACCOUNT_ID argquery \
  --principal user/iamws-policy-developer-user \
  --action iam:CreatePolicyVersion
```

This evaluates a single principal against a single IAM action and prints `ALLOW` or `DENY` with the policy chain that produced the decision. You'll use this in every scenario to confirm a specific permission before exploiting it.

Expected output for the example above:

```
ALLOW user/iamws-policy-developer-user can call iam:CreatePolicyVersion with *
```

---

## Step 10: Optional — Terminal dashboard

If you prefer a CLI-first view, iam-recon ships a TUI that wraps everything in Step 9:

```bash
iam-recon --tui --account $ACCOUNT_ID
```

Navigate with the arrow keys. Press `q` to quit. The TUI is purely a viewing tool — every action it surfaces is available as a regular CLI command, so feel free to skip it.

