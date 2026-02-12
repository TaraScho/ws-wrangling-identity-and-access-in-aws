# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is a 2-hour hands-on AWS IAM security workshop teaching identity and access management through attack and defense exercises. The workshop uses intentionally vulnerable infrastructure for participants to practice exploitation and remediation techniques.

**Workshop Structure:**
1. Layin' Down the Law (Lecture 1): IAM fundamentals (PARC model, policy evaluation, 5 privilege escalation categories)
1. Layin' Down the Law (Lab 1): Identify and exploit misconfigurations using awspx, pmapper, and pathfinding.cloud
1. Fencin' the Frontier (Lecture 2): Security guardrails (permissions boundaries, trust policies, condition keys, SCPs)
1. Fencin' the Frontier (Lab 2): Remediate and verify using guardrails (permissions boundaries, resource constraints, trust policies, condition keys)

## Architecture

### Workshop Content
- `labs/` - Hands-on exercise instructions and infrastructure
  - `labs/lab-0-prerequisites/` - Prerequisites and setup instructions (tool validation, Terraform deployment)
  - `labs/lab-1-layin-down-the-law/` - Lab 1: Identifying and exploiting IAM misconfigurations
    - `exercises/` - Individual exercise files (exercises 2–7), linked from `lab-1-instructions.md`
  - `labs/lab-2-fencin-the-frontier/` - Lab 2: Remediating IAM misconfigurations with guardrails
    - `exercises/` - Individual exercise files (exercises 1–6), linked from `lab-2-instructions.md`
  - `labs/bonus-scenarios/` - Additional scenarios beyond the core workshop
  - `labs/FEATURES.md` - Feature roadmap tracking lab development tasks
  - `labs/wwhf-setup.sh` - Workshop setup script
  - `labs/terraform/` - Learner-facing Terraform to deploy vulnerable IAM infrastructure
    - Modules: `cloudformation`, `ec2`, `iam-principals`, `lambda`

### Reference Repositories (gitignored, local only)
- `reference-repos/PMapper/` - Fork of NCC Group's PMapper (Principal Mapper) for IAM privilege escalation analysis
- `reference-repos/pathfinding.cloud/` - Fork of pathfinding.cloud AWS IAM privilege escalation path database. This fork is for Claude reference only; learners use the actual pathfinding.cloud website. We are not making changes to the pathfinding.cloud codebase.

## Key Requirements

After each update, ensure all markdown files in the project are updated to reflect the changes and provide accurate information. This workshop is currently in development and all collaborators need to understand the purpose of each file and whether it is intended as a final learner facing document, a reference for instructions, or resources for agentic assisted development.

## Markdown Style Guide

- **Ordered lists must use `1.` for every item.** Do not manually number list items (e.g., `1.`, `2.`, `3.`). Instead, use `1.` for all items and let the Markdown renderer auto-number them. This makes it easier to reorder, insert, or remove items without renumbering.