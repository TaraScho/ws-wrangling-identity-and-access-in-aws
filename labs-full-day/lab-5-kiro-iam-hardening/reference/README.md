# Reference materials — instructor / fallback use only

> [!WARNING]
> **Do not open this folder as part of your Kiro project, and do not copy `iam-hardened-role.reference.yaml` into the working directory you point Kiro at.**
>
> The whole point of Part C is to write a Kiro Spec from scratch and let Kiro generate the hardened template. If the reference template is anywhere in Kiro's context (project root, open tab, attached file), Kiro will pattern-match on it and you'll learn nothing about spec-driven generation.

## When to consult this folder

- **You're an instructor** running the lab and want to know what "good" looks like.
- **A learner has been stuck for 10+ minutes** with a Kiro output that won't deploy or won't pass the Part D rubric, and they're missing the time budget for the afternoon block.
- **You want to verify the simulator commands in Part E** are calibrated correctly — deploy the reference template and confirm every allowed action returns `allowed` and every denied action returns `implicitDeny` / `explicitDeny`.

## What's in here

- `iam-hardened-role.reference.yaml` — a known-good hardened CloudFormation template that satisfies REQ-001 through REQ-009 from the spec. Separate policy statements per service, a permissions boundary that denies IAM and Organizations actions, a trust policy locked to `ec2.amazonaws.com`, no wildcards, and full tagging.

Treat this as one valid solution, not *the* solution. Kiro will produce different — and frequently better — structures depending on how it interprets the spec.
