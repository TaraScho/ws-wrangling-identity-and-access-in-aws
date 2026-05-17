# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This repo hosts a hands-on AWS IAM security workshop teaching identity and access management through attack and defense exercises. Both variants use intentionally vulnerable infrastructure for participants to practice exploitation and remediation techniques.

Two workshop variants live side-by-side, each with its own labs and Terraform tree:
- **Full-day** (`labs-full-day/`) — 9 labs covering setup, CreatePolicyVersion, trust policy abuse, permissions boundaries + condition keys, Kiro + MCP policy hardening, PassRole (EC2), Lambda UpdateFunctionCode, Lambda secret extraction, and cleanup.
- **Two-hour** (`labs-two-hour-workshop/`) — condensed version with two labs:
  1. Layin' Down the Law (Lecture 1): IAM fundamentals (PARC model, policy evaluation, 5 privilege escalation categories)
  1. Layin' Down the Law (Lab 1): Identify and exploit misconfigurations using awspx, pmapper, and pathfinding.cloud
  1. Fencin' the Frontier (Lecture 2): Security guardrails (permissions boundaries, trust policies, condition keys, SCPs)
  1. Fencin' the Frontier (Lab 2): Remediate and verify using guardrails (permissions boundaries, resource constraints, trust policies, condition keys)

The top-level `README.md` is a landing page that routes visitors to one of the two workshop READMEs.

## Architecture

### Workshop Content

- `labs-full-day/` - Full-day workshop (9 labs)
  - `lab-0-prerequisites/`, `lab-1-setup/`, `lab-2-create-policy-version/`, `lab-3-trust-policy-abuse/`, `lab-4-permissions-boundaries-and-condition-keys/`, `lab-5-kiro-iam-hardening/`, `lab-6-passrole-ec2/`, `lab-7-lambda-updatefunctioncode/`, `lab-8-lambda-secrets/`, `lab-9-cleanup/`
  - `bsides-setup.sh` - Workshop setup script
  - `terraform/` - Learner-facing Terraform to deploy vulnerable IAM infrastructure
    - Modules: `cloudformation`, `ec2`, `iam-principals`, `lambda`, `s3`
- `labs-two-hour-workshop/` - Condensed 2-hour workshop
  - `lab-0-prerequisites/` - Prerequisites and setup instructions (tool validation, Terraform deployment)
  - `lab-1-layin-down-the-law/` - Lab 1: Identifying and exploiting IAM misconfigurations
    - `exercises/` - Individual exercise files (exercises 2–7), linked from `lab-1-instructions.md`
  - `lab-2-fencin-the-frontier/` - Lab 2: Remediating IAM misconfigurations with guardrails
    - `exercises/` - Individual exercise files (exercises 1–6), linked from `lab-2-instructions.md`
  - `wwhf-setup.sh` - Workshop setup script
  - `terraform/` - Learner-facing Terraform to deploy vulnerable IAM infrastructure
    - Modules: `cloudformation`, `ec2`, `iam-principals`, `lambda`, `s3`

### Reference Repositories (gitignored, local only)
- `~/repos/iam-recon` - Source code for `iam-recon` tool
- `reference-repos/pathfinding.cloud/` - Fork of pathfinding.cloud AWS IAM privilege escalation path database. This fork is for Claude reference only; learners use the actual pathfinding.cloud website.

## Key Requirements

After each update, ensure all markdown files in the project are updated to reflect the changes and provide accurate information.

## Markdown Style Guide

- **Ordered lists must use `1.` for every item.** Do not manually number list items (e.g., `1.`, `2.`, `3.`). Instead, use `1.` for all items and let the Markdown renderer auto-number them. This makes it easier to reorder, insert, or remove items without renumbering.