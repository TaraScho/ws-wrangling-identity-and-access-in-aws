# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is a 2-hour hands-on AWS IAM security workshop teaching identity and access management through attack and defense exercises. The workshop uses intentionally vulnerable infrastructure for participants to practice exploitation and remediation techniques.

**Workshop Structure:**
1. Layin' Down the Law (Lecture 1): IAM fundamentals (PARC model, policy evaluation, 5 privilege escalation categories)
2. Layin' Down the Law (Lab 1): Identify misconfigurations using pmapper and pathfinding.cloud
3. Fencin' the Frontier (Lecture 2): Security guardrails (permissions boundaries, trust policies, condition keys, SCPs)
4. Fencin' the Frontier (Lab 2): Exploit and remediate using attack→defense pairs

## Architecture

### Workshop Content
- `slides/` - Slide presentations in Markdown format - in development and will most likely be Google Slides in the final version
- `labs/` - Hands-on exercise instructions and Terraform infrastructure
  - `labs/terraform/` - Learner-facing Terraform modules to deploy vulnerable IAM infrastructure
  - `labs/lab-1-layin-down-the-law/` - Layin' Down the Law lab instructions (identify misconfigurations)
  - `labs/lab-2-fencin-the-frontier/` - Fencin' the Frontier lab instructions (exploit and remediate)

### Reference Repositories
- `reference-repos/iam-vulnerable/` - Full fork of Bishop Fox's iam-vulnerable repo for reference (learners deploy from `labs/terraform/` instead)
- `reference-repos/pathfinding.cloud/` - Fork of pathfinding.cloud AWS IAM privilege escalation path database with interactive visualizations. This fork is for Claude reference only and learners in the workshop will use the actual pathfinding.cloud website. We are not making changes to the pathfinding.cloud code base.

## Key Requirements

After each update, ensure all markdown files in the project are updated to reflect the changes and provide accurate information. This workshop is currently in development and all collaborators need to understand the purpose of each file and whether it is intended as a final learner facing document, a reference for instructions, or resources for agentic assisted development.