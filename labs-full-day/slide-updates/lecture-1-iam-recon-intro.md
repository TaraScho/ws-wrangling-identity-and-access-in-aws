# Lecture 1 slide-update bullets — replace the awspx / pmapper / pathfinding.cloud demo

Drop these bullets into the existing `Lecture-1-Layin-Down-the-Law.pptx` deck wherever the old tooling demo currently lives. Suggested 4–5 slides.

## Slide A — "Meet iam-recon"

- Single-binary Rust tool that builds a directed graph of every principal in an AWS account.
- Maps dangerous permissions to known privilege-escalation paths automatically.
- Located at https://github.com/<org>/iam-recon (TODO: confirm public URL or note "internal").
- One install, one command surface, zero Python/Docker.

## Slide B — "Lineage shoutout"

- **PMapper** (NCC Group) — original Python privesc mapper. Abandoned upstream. iam-recon is a ground-up Rust rewrite with feature parity.
- **awspx** (F-Secure) — interactive graph viz. iam-recon's interactive viz is inspired by awspx's Cytoscape.js approach.
- **pathfinding.cloud** (Datadog) — comprehensive privesc-path database. iam-recon bundles all 66+ paths at build time and links findings directly to the docs.
- *We're using iam-recon today because it consolidates all three into one tool — but the old tools shaped the field and are worth knowing.*

## Slide C — "The 3 commands you'll run all day"

```bash
iam-recon graph create --profile <user>                  # scan an account
iam-recon --account $ACCOUNT_ID pathfinding                          # find escalation paths (universal)
iam-recon --account $ACCOUNT_ID argquery --preset privesc            # graph-edge view (subset of paths)
iam-recon --account $ACCOUNT_ID visualize --interactive-viz # see them in the browser
```

- Scan once → query offline forever (responses are cached locally).
- Browser opens at :8080, force-directed graph, color-coded by privilege.

## Slide D — "What iam-recon detects"

- Two complementary detection surfaces:
  - **9 edge checkers** (`argquery --preset privesc`) — IAM, STS, Lambda, EC2, CodeBuild, CloudFormation, AutoScaling, SSM, SageMaker. Builds a permissions graph; catches edges where chained perms reach admin.
  - **Pathfinding** (`pathfinding`) — matches dangerous permissions against the 66+ pathfinding.cloud catalog. Catches single-permission self-escalations that don't show up as edges (e.g. `iam:CreatePolicyVersion`, `iam:PutGroupPolicy`).
- Use both. They overlap but neither is a superset.
- Full IAM policy simulation locally — condition keys, permission boundaries, SCPs, resource policies.

## Slide E — "Pathfinding.cloud integration"

- Every iam-recon finding links back to canonical attack-path documentation.
- 66+ known paths bundled at build time; instructor will show clickable links in the demo.
- Useful next step after a workshop: scan your own org's accounts and see where you land on the path catalog.
