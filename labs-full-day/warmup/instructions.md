# Warmup — Get Oriented in the Graph

~5 minutes. Goal: get oriented in the IAM graph you built during setup before the first attack scenario.

## Step 1: Confirm the graph is loaded

If you haven't already, set the account ID so every iam-recon query in this and later scenarios can run offline:

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text --profile iamws-scanner-user)
```

Verify the graph from setup is still cached and readable:

```bash
iam-recon --account $ACCOUNT_ID graph display
```

Expected output: a summary line with the account ID, node count (~36), edge count (~20), admin count (~7). If you see "no graph found", revisit [lab setup](../lab-setup-instructions.md#step-7-build-the-iam-graph) and re-run `iam-recon graph create --profile iamws-scanner-user`.

## Step 2: Open the interactive visualization

```bash
iam-recon --account $ACCOUNT_ID visualize --interactive-viz
```

iam-recon prints something like:

```
Interactive visualization available at: http://127.0.0.1:54321
```

The port is dynamic — open the URL iam-recon prints (the browser should open automatically). Once it loads, you'll see a force-directed graph of every IAM principal in the account.

Node colors:

- **Red** — admin-tier principals (full `*:*` access)
- **Orange** — principals with at least one known privilege escalation path
- **Blue** — regular users
- **Light cyan** — regular roles

## Step 3: Apply the Privesc filter

In the viz toolbar, enable the **Privesc** filter. The graph should collapse to roughly 8 highlighted principals — these are every starting point for the scenarios you're about to run. Your instructor will walk through which highlighted node corresponds to which scenario.

While the filter is on, click a few nodes to get a feel for the inspector panel — node properties, attached policies, group membership, and any pathfinding.cloud paths the principal is implicated in.

## Step 4: Optional — terminal dashboard

If you prefer a terminal-first view of the same data:

```bash
iam-recon --tui --account $ACCOUNT_ID
```

Use the arrow keys to navigate. Press `q` to quit.

---

You're ready for [Scenario 1a — CreatePolicyVersion](../scenario-1a-create-policy-version.md).
