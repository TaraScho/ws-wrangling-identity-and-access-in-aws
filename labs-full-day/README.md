# Wrangling Identity and Access in AWS

A full-day, hands-on workshop on AWS IAM privilege escalation and remediation.

Use this README as your playbook for the day. Each row links to the instructions you'll work from during that block. Slide links will be added closer to the event.

## Agenda

| Time | Block | Materials |
| :--- | :--- | :--- |
| 9:00 – 9:40 | Welcome and Lesson 1: Introduction to IAM | [Slides](https://docs.google.com/presentation/d/1z6z0WDAdlMDVyiDvu2jmfG_a9le--AM1/edit?usp=drive_link&rtpof=true&sd=true) |
| 9:40 – 10:00 | **Lab 1: Lab Setup** | [Instructions](./lab-setup-instructions.md)<br>[Slides](https://docs.google.com/presentation/d/1QSUtnibKrYtv2-eEfJ6SlNwzUcLFZsH_/edit?usp=drive_link&rtpof=true&sd=true) |
| 10:00 – 10:15 | **Lab 2: Self Privilege Escalation via CreatePolicyVersion** | [Instructions](./scenario-1a-create-policy-version.md)<br>[Slides](https://docs.google.com/presentation/d/1ylN5bXFtflkiJqCH5vUmW65AMs7BiF38/edit?usp=drive_link&rtpof=true&sd=true) |
| 10:15 – 10:30 | **Lab 3: Trust Policy Abuse** | [Instructions](./scenario-2-trust-policy-root.md)<br>[Slides](https://docs.google.com/presentation/d/1AKED2urhbXi8-3XEkMBafXSWQh8xd-jI/edit?usp=drive_link&ouid=109780715844951499863&rtpof=true&sd=true) |
| 10:30 – 10:45 | Morning Break | — |
| 10:45 – 11:15 | Lesson 2: Guardrails and Validation | [Slides](https://docs.google.com/presentation/d/1cj7xJw6OB84WSbeuTEKOsdmcVRb_T8Ea/edit?usp=drive_link&ouid=109780715844951499863&rtpof=true&sd=true) |
| 11:15 – 11:30 | **Lab 4: Permissions Boundaries & Condition Keys** | [Instructions](./apply-permissions-boundaries-and-condition-keys.md) |
| 11:30 – 12:00 | Lesson 3: Kiro for Cloud Security | [Slides](https://docs.google.com/presentation/d/1edug67aDepcrbPXwHDflaaVrhGOW1JXO/edit?usp=drive_link&ouid=109780715844951499863&rtpof=true&sd=true) |
| 12:00 – 1:00 | Lunch | — |
| 1:00 – 1:30 | Knowledge Refresh Game | Join link _(tbd)_ |
| 1:30 – 2:00 | **Lab 5: Hardening IAM Policies with Kiro + MCP** | [Instructions](./kiro-iam-hardening/instructions.md) |
| 2:00 – 2:30 | **Lab 6: Privilege Escalation via iam:PassRole (EC2)** | [Instructions](./scenario-3-passrole-ec2/attack.md)<br>[Slides](https://docs.google.com/presentation/d/1Ooka3AlRLppVj8w9ca1XsPK_pUjnicFs/edit?usp=drive_link&ouid=109780715844951499863&rtpof=true&sd=true) |
| 2:30 – 2:45 | Afternoon Break | — |
| 2:45 – 3:15 | **Lab 7: Privilege Escalation via Lambda UpdateFunctionCode** | [Instructions](./scenario-4-lambda-updatefunctioncode/lambda-updatefunctioncode.md)<br>[Slides](https://docs.google.com/presentation/d/1BeZ_opM_Vfi3_4FLvwP1wbrllA55d4sc/edit?usp=drive_link&rtpof=true&sd=true) |
| 2:45 – 3:15 | **Lab 8: Lambda Secret Extraction** | [Instructions](./scenario-5-lambda-secrets/instructions.md)<br>[Slides](https://docs.google.com/presentation/d/1JegcTECdlsICUz6EngVbF5HSdzz5aB-W/edit?usp=drive_link&ouid=109780715844951499863&rtpof=true&sd=true) |
| 3:15 – 3:30 | Lecture: IAM Spy and Provers | Slides _(tbd)_ |
| 3:30 – 4:30 | Flex / Knowledge Game 2 | Join link _(tbd)_ |
| 4:30 – 5:00 | Environment Clean up and Wrap-up | [Cleanup Instructions](./lab-cleanup-instructions.md) |

## Resources

### Tools Used in This Workshop

- [iam-recon](https://github.com/yourorg/iam-recon) — Single-binary Rust tool that builds an offline graph of IAM users, roles, groups, and policies and maps them to the attack paths catalogued by pathfinding.cloud. Used in every recon-and-verify step of the workshop.
- [pathfinding.cloud](https://pathfinding.cloud) — AWS IAM privilege escalation path database with interactive visualizations. Every iam-recon finding links back to a path here.
- [Kiro](https://kiro.dev) — AI-native IDE used in Lab 5 to harden IAM policies.
- [AWS Labs MCP servers](https://github.com/awslabs/mcp) — Model Context Protocol servers from AWS Labs, including the [AWS IaC MCP server](https://awslabs.github.io/mcp/servers/aws-iac-mcp-server) used with Kiro in Lab 5.
- [iam-vulnerable](https://github.com/BishopFox/iam-vulnerable) — Intentionally vulnerable IAM configurations. The workshop's Terraform modules are based on this project.

### AWS Documentation

- [IAM Access Analyzer](https://docs.aws.amazon.com/IAM/latest/UserGuide/what-is-access-analyzer.html) — Validate policies and find unintended external access.
- [Testing IAM policies](https://docs.aws.amazon.com/IAM/latest/UserGuide/access_policies_testing-policies.html) — IAM policy simulator and other validation approaches.
- [IAM security best practices](https://docs.aws.amazon.com/IAM/latest/UserGuide/best-practices.html)

### Further Learning

- [IAM Tutor](https://www.sharmaprateek.com/guides/iam-tutor/) — Interactive IAM policy walkthroughs.
- [Cloudsplaining](https://github.com/salesforce/cloudsplaining) — Identifies violations of least privilege in IAM policies.
- [Kiro: Enterprise governance with MCP and models](https://kiro.dev/blog/enterprise-governance-mcp-and-models/) — Background reading for the Kiro + MCP lab.