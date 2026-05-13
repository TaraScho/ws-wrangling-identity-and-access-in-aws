# Warmup — Confirm Your Tools Before the First Scenario

~20 minutes. Goal: verify your AWS credentials and iam-recon are working before any attacks.

## Step 1: Configure your AWS CLI profile

Follow the setup instructions in [`lab-0-prerequisites.md`](../../labs-two-hour-workshop/lab-0-prerequisites/lab-0-prerequisites.md) to configure the AWS CLI profile for your assigned identity.

## Step 2: Build the iam-recon graph

Set your account ID, then run an initial scan:

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text --profile taractf)

iam-recon graph create --profile taractf
```

Expected output includes a node count, edge count, and admin count. You should see roughly 36 nodes, 20 edges, and 7 admins.

## Step 3: Open the interactive visualization

```bash
iam-recon --account $ACCOUNT_ID visualize --interactive-viz
```

iam-recon will print something like:
```
Interactive visualization available at: http://127.0.0.1:54321
```

The port is dynamic — watch the terminal output and open the URL it prints. The browser should open automatically; if not, copy the URL manually.

Once open:
- **Red nodes** = admin-tier principals (`AdministratorAccess` or equivalent)
- **Orange nodes** = principals with a privilege escalation path
- **Blue nodes** = regular users and roles

Use the **Privesc** filter to highlight only the escalation paths. You should see roughly 8 principals highlighted. Your instructor will walk through which nodes correspond to each upcoming scenario.

## Step 4: Optional — terminal dashboard

If you prefer a CLI view:

```bash
iam-recon --tui --account $ACCOUNT_ID
```

## Profile decision (TODO)

The scan above uses `--profile taractf` (the admin profile used for initial graph creation). For participant workshops, the warmup profile needs a decision:

1. **New read-only scanner user** — create a dedicated `iamws-scanner` IAM user with `SecurityAudit` or similar. Cleanest option; requires adding a principal to the Terraform.
1. **Sandbox admin** — have participants use an admin profile for the initial scan only, then switch to attacker profiles for each scenario. Simplest operationally.
1. **Per-exercise user** — start with the first scenario's attacker profile (e.g., `iamws-policy-developer-user`), which only sees what that user can see. Teaching moment about visibility, but noisier for a first scan.

Don't pick an option here — flag for Tara before finalizing participant-facing materials.
