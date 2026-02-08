# Wrangling Identity and Access in AWS

> [!NOTE]
> 🚧 Workshop is currently in development - some material (e.g. pathfinding.cloud fork) is only commited to project as reference for agentic assisted development. Final learning facing material will be organized/presented differently.

In this 2-hour hands-on workshop learners will navigate the world of identity and access management in AWS. Students should bring their own sandbox AWS account as we navigate policy grammar and becoming familiar with the PARC model (principal, action, resource, and condition), resource policies, permissions boundaries, and introduce guardrails like condition keys. Learners will be hands-on in AWS and leveraging open source tools to simulate various identity misconfigurations.

## Requirements

1. A sandbox AWS account (NOT production!) with credentials for an IAM role/user with the following permissions:
   - TODO - add permissions
2. AWS CLI configured with credentials
3. Terraform 
4. Python 3.8+ with pip
5. Basic familiarity with JSON

> [!IMPORTANT]
> 🚨 This workshop deploys intentionally vulnerable IAM infrastructure to your sandbox account. Do not deploy workshop resources to an AWS account with any production data or workloads.

## Open source tools and references

We will be using the following open source tools and references:

- [pmapper](https://github.com/nccgroup/pmapper) - Open source tool for identifying privilege escalation paths in IAM configurations
- [pathfinding.cloud](https://pathfinding.cloud) - AWS IAM privilege escalation path database with interactive visualizations
- [iam-vulnerable](https://github.com/BishopFox/iam-vulnerable) - Intentionally vulnerable IAM configurations - lab terraform modules are a fork of this repository with some modules removed to reduce complexity and cost and other small changes.

## Workshop Structure

### Module 1: Layin' Down the Law - 60 minutes

**Lecture 1 - Layin' Down the Law: The Sheriff's Handbook - 20 minutes**
- [Slides](https://docs.google.com/presentation/d/15IF92MF-tpn5OzeFu3IypIMvFDcgvSF2/edit?usp=sharing&ouid=109780715844951499863&rtpof=true&sd=true)
- IAM fundamentals, PARC model, policy evaluation
- 5 privilege escalation categories

**Lab 1 - Layin' Down the Law: Identifying IAM Misconfigurations - 40 minutes**
- [Instructions](labs/lab-1-layin-down-the-law/instructions.md)
- Deploy vulnerable IAM infrastructure from `labs/terraform/`
- Scan with pmapper to find privilege escalation paths
- Use pathfinding.cloud to understand findings

### Module 2: Fencin' the Frontier - 60 minutes

**Lecture 2 - Fencin' the Frontier: Guardrails and What Goes Wrong - 15 minutes**
- [Slides](https://docs.google.com/presentation/d/1r08sa_l1YvCGMGzZG_ptN2Za6kc8aWnn/edit?usp=sharing&ouid=109780715844951499863&rtpof=true&sd=true)
- Permissions boundaries, resource policies, condition keys, SCPs

**Lab 2 - Fencin' the Frontier: Exploit and Remediate - 45 minutes**
- [Instructions](labs/lab-2-fencin-the-frontier/instructions.md)
- Remediate privilege escalation paths from Lab 1 using guardrails (permissions boundaries, resource policies, condition keys)

## Other Great Tools and Resources

- [IAM Tutor](https://www.sharmaprateek.com/guides/iam-tutor/)
- [Cloud Splaining](https://github.com/salesforce/cloudsplaining)