# Wrangling Identity and Access in AWS

In this 2-hour hands-on workshop, learners navigate the world of identity and access management in AWS. Participants work through policy grammar and the PARC model (principal, action, resource, and condition), resource policies, permissions boundaries, and guardrails like condition keys. Using open source tools and intentionally vulnerable infrastructure, learners simulate and remediate real-world identity misconfigurations.

> [!IMPORTANT]
> This workshop deploys intentionally vulnerable IAM infrastructure to your AWS account. Do not deploy workshop resources to an account with any production data or workloads. Use a dedicated sandbox account.

## Prerequisites

1. A sandbox AWS account (NOT production!) with permissions to create and manage:
   - IAM users, roles, groups, policies, and permissions boundaries
   - Lambda functions
   - EC2 instances and security groups
   - CloudFormation stacks
   - S3 buckets
   - Secrets Manager secrets
1. AWS CLI configured with credentials
1. Terraform
1. Docker
1. Python 3 with venv
1. Git
1. Basic familiarity with JSON and the AWS Console

For detailed setup and validation steps, see the [Prerequisites Lab](labs/lab-0-prerequisites/lab-0-prerequisites.md).

## Workshop Structure

### Module 1: Layin' Down the Law (60 minutes)

**Lecture 1 -- The Sheriff's Handbook (20 minutes)**
- [Slides](https://docs.google.com/presentation/d/15IF92MF-tpn5OzeFu3IypIMvFDcgvSF2/edit?usp=sharing&ouid=109780715844951499863&rtpof=true&sd=true)
- IAM fundamentals and the PARC model
- Policy evaluation logic
- 5 privilege escalation categories

**Lab 1 -- Identifying IAM Misconfigurations (40 minutes)**
- [Instructions](labs/lab-1-layin-down-the-law/lab-1-instructions.md)
- Deploy vulnerable IAM infrastructure with Terraform
- Scan with pmapper and awspx to find privilege escalation paths
- Use pathfinding.cloud to understand findings
- Exploit 6 misconfigurations across different escalation categories

### Module 2: Fencin' the Frontier (60 minutes)

**Lecture 2 -- Guardrails and What Goes Wrong (15 minutes)**
- [Slides](https://docs.google.com/presentation/d/1r08sa_l1YvCGMGzZG_ptN2Za6kc8aWnn/edit?usp=sharing&ouid=109780715844951499863&rtpof=true&sd=true)
- Permissions boundaries, trust policies, condition keys, SCPs

**Lab 2 -- Remediate and Verify (45 minutes)**
- [Instructions](labs/lab-2-fencin-the-frontier/lab-2-instructions.md)
- Remediate each privilege escalation path from Lab 1
- Apply guardrails: permissions boundaries, resource constraints, trust policies, condition keys
- Verify remediations block the original exploits

## Open Source Tools and References

Tools used in this workshop:

- [pmapper](https://github.com/nccgroup/pmapper) -- Principal Mapper for identifying privilege escalation paths in IAM configurations
- [awspx](https://github.com/WithSecureLabs/awspx) -- Graph-based AWS visualization backed by Neo4j
- [pathfinding.cloud](https://pathfinding.cloud) -- AWS IAM privilege escalation path database with interactive visualizations
- [iam-vulnerable](https://github.com/BishopFox/iam-vulnerable) -- Intentionally vulnerable IAM configurations (lab Terraform modules are based on this project)

## Other Great Tools and Resources

- [IAM Tutor](https://www.sharmaprateek.com/guides/iam-tutor/)
- [Cloud Splaining](https://github.com/salesforce/cloudsplaining)

## Cleanup

After completing the workshop, destroy all deployed resources:

```bash
cd labs/terraform
terraform destroy
```

See the [Prerequisites Lab](labs/lab-0-prerequisites/lab-0-prerequisites.md) for full cleanup instructions including stopping Docker containers.
