# Lecture 1 slide-update bullets — `iam-recon` intro

Drop these bullets into `Lecture-1-Layin-Down-the-Law.pptx` wherever the old tooling demo (awspx / pmapper / pathfinding.cloud) currently lives. **5 slides.** This deck *prefaces* the hands-on lab — no live demo runs during the talk, so each slide must give the audience enough context to know *why* they're about to run these commands.

> **Audience assumption:** IAM novices. They know what users, roles, and policies are after the earlier lecture sections (PARC model, 5 privilege-escalation categories), but they have not seen graph-based IAM tooling before. Define every new term inline the first time it appears.

> **Designer notes** appear in italics throughout. Screenshots referenced by path live in the `iam-recon` source repo at `~/repos/iam-recon/docs/screenshots/`.

---

## Slide A — Meet `iam-recon`

**One-sentence framing (use as slide subtitle):**
*`iam-recon` reads every IAM policy in an AWS account, draws a map showing which principals can become which other principals, and flags the dangerous shortcuts.*

- A **principal** is anything with an AWS identity — an IAM user, an IAM role, or a federated identity. `iam-recon` plots every principal as a node on a map.
- A **directed graph** is that map. Nodes are principals; an arrow from A to B means "A can turn itself into B" — for example, A can assume B's role, or A can edit B's policy to grant itself B's permissions.
- Single Rust binary. Runs on macOS and Linux. No Python, no Docker, no graph database to set up.
- Released by Datadog. Source + pre-built binaries at `github.com/yourorg/iam-recon` *(TODO: confirm final public URL)*.

*Designer note: this slide needs a hero image. Use `~/repos/iam-recon/docs/screenshots/01-graph-overview.png` — the force-directed graph from the README is the iconic "what does this tool look like" shot.*

---

## Slide B — Lineage shoutout

You'll see references to older tools in blog posts and write-ups. They shaped this field. `iam-recon` rolls what each of them did well into one binary.

- **PMapper** (NCC Group) — the original Python privilege-escalation mapper. Abandoned upstream. `iam-recon` is a ground-up Rust rewrite with full feature parity.
- **awspx** (F-Secure) — the first widely-used interactive graph viz for AWS IAM. Inspired `iam-recon`'s browser-based graph explorer.
- **pathfinding.cloud** (Datadog) — an open catalog of 66+ known AWS privilege-escalation attack paths. `iam-recon` bundles the catalog into the binary at build time and links every finding directly to the pathfinding.cloud write-up.

*We're using `iam-recon` today because it consolidates all three into one tool — but the old tools shaped the field and are worth knowing.*

---

## Slide C — The 4 commands you'll run all day

*Designer layout: render as a 2-column table. Monospace command on the left, plain-English gloss on the right.*

| Command | What it does |
|---|---|
| `iam-recon graph create --profile <user>` | **Run this once.** Scans the account via the AWS API, then caches everything locally to `~/.local/share/iam-recon/<account-id>/`. |
| `iam-recon --account $ACCOUNT_ID pathfinding` | Compares every principal's permissions against the 66+ pathfinding.cloud attack patterns. Lists matches and prints a link to each write-up. |
| `iam-recon --account $ACCOUNT_ID argquery --preset privesc` | Lists every privilege-escalation *chain* — every arrow in the graph from a non-admin principal to admin. |
| `iam-recon --account $ACCOUNT_ID visualize --interactive-viz` | Renders the graph in your browser. `iam-recon` prints the URL — **the port is dynamic**, so copy the line that appears in the terminal. |

- After `graph create`, every other command runs **offline** against the cache. No further AWS calls. You can rerun queries on a plane.
- `argquery` is short for "argument-based query." A **preset** (`--preset privesc`) is a pre-built question you don't have to assemble flag-by-flag.
- There's also a TUI (`iam-recon --tui --account $ACCOUNT_ID`) if you prefer keyboard navigation. A few lab scenarios suggest it.

**Color legend for the browser graph** — *designer: render as a small swatch beside the command table.*

- 🔴 **Red** — admin (full account access)
- 🟠 **Orange** — can privilege-escalate *to* admin
- 🔵 **Blue** — IAM user with limited permissions
- 🩵 **Light cyan** — IAM role with limited permissions

---

## Slide D — How `iam-recon` decides a principal is dangerous

This is the technical heart of the tool. `iam-recon` uses **two complementary detection surfaces.** Neither is a superset of the other; you'll run both.

### 1. Edge-checkers — *"Who can become whom?"*

An **edge-checker** is a per-service rule that draws an arrow from principal A to principal B when A has permissions to take over B. For example:

- The **IAM** edge-checker draws an arrow A → B if A can edit B's trust policy.
- The **EC2** edge-checker draws an arrow A → B if A can launch an EC2 instance and attach B as the instance role.
- The **Lambda** edge-checker draws an arrow A → B if A can update a Lambda function that uses B as its execution role.

`iam-recon` ships **9 edge-checkers**, one per AWS service that has a known abuse pattern:

`IAM` · `STS` · `Lambda` · `EC2` · `CodeBuild` · `CloudFormation` · `AutoScaling` · `SSM` · `SageMaker`

You see these edges as rows in `argquery --preset privesc` output and as arrows in the browser graph.

### 2. Pathfinding — *"Does any single principal match a known attack pattern?"*

A separate scan that matches each principal's permissions against the 66+ patterns in the pathfinding.cloud catalog. This catches **self-escalations** — a principal that can elevate *itself* with a single permission, no second principal involved.

Classic example: a principal with `iam:CreatePolicyVersion` on its own policy can give itself admin in one API call. There's no "A → B" arrow to draw — there is no B. Edge-checkers will miss it. Pathfinding catches it.

The catalog's five categories line up with the **5 privilege-escalation categories from earlier in this lecture**:

`SelfEscalation` · `PrincipalAccess` · `NewPassRole` · `ExistingPassRole` · `CredentialAccess`

> **Bottom line:** run `pathfinding` *and* `argquery --preset privesc`. They overlap, but each catches things the other misses.

### Why the answers are trustworthy

`iam-recon`'s policy evaluator is a local re-implementation of AWS's IAM evaluation logic — explicit deny → SCP → resource policy → permissions boundary → session policy → identity policy — including condition keys. Offline queries return the same yes/no AWS itself would.

---

## Slide E — Pathfinding.cloud integration

- Every pathfinding finding includes a link to `pathfinding.cloud/paths/<id>` — the canonical write-up for that attack pattern.
- The `<id>` (e.g., `iam-001`) is the same identifier in the bundled catalog and on the public site. What you see in the terminal, you can read about on the web.
- **Take-home after the workshop:** point `iam-recon` at your own org's accounts and see how many catalog entries you light up.

*Designer note: render a "before/after" pair —*
- *Left: terminal screenshot of one `iam-recon --account $ACCOUNT_ID pathfinding` finding (use `iam-001` — it's the running example in `scenario-1a-create-policy-version.md` and so will recur throughout the lab).*
- *Right: the matching pathfinding.cloud page at `pathfinding.cloud/paths/iam-001`. Arrow from the finding's `Path: iam-001` line to the page header to make the link obvious.*
