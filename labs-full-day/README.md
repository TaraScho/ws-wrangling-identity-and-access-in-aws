# Wrangling Identity and Access in AWS

A full-day, hands-on workshop on AWS IAM privilege escalation and remediation.

Use this README as your playbook for the day. Each row links to the instructions you'll work from during that block. Slide links will be added closer to the event.

## Agenda

| Time | Block | Materials |
| :--- | :--- | :--- |
| 9:00 – 9:40 | Welcome and Introduction to IAM | [Slides](https://docs.google.com/presentation/d/1z6z0WDAdlMDVyiDvu2jmfG_a9le--AM1/edit?usp=drive_link&rtpof=true&sd=true) |
| 9:40 – 10:00 | **Lab 1: Lab Setup** | [Instructions](./lab-1-setup/README.md)<br>[Slides](https://docs.google.com/presentation/d/1QSUtnibKrYtv2-eEfJ6SlNwzUcLFZsH_/edit?usp=drive_link&rtpof=true&sd=true) |
| 10:00 – 10:15 | **Lab 2: Self Privilege Escalation via CreatePolicyVersion** | [Instructions](./lab-2-create-policy-version/README.md)<br>[Slides](https://docs.google.com/presentation/d/1ylN5bXFtflkiJqCH5vUmW65AMs7BiF38/edit?usp=drive_link&rtpof=true&sd=true) |
| 10:15 – 10:30 | **Lab 3: Trust Policy Abuse** | [Instructions](./lab-3-trust-policy-abuse/README.md)<br>[Slides](https://docs.google.com/presentation/d/1AKED2urhbXi8-3XEkMBafXSWQh8xd-jI/edit?usp=drive_link&ouid=109780715844951499863&rtpof=true&sd=true) |
| 10:30 – 10:45 | Morning Break | — |
| 10:45 – 11:15 | Lesson: Guardrails and Validation | [Slides](https://docs.google.com/presentation/d/1cj7xJw6OB84WSbeuTEKOsdmcVRb_T8Ea/edit?usp=drive_link&ouid=109780715844951499863&rtpof=true&sd=true) |
| 11:15 – 11:30 | **Lab 4: Permissions Boundaries & Condition Keys** | [Instructions](./lab-4-permissions-boundaries-and-condition-keys/README.md) [Slides](https://docs.google.com/presentation/d/1gW3cBqOJ_WVPKgZbLy8EnklvhHJ5LBaU/edit?usp=drive_link&ouid=109780715844951499863&rtpof=true&sd=true)|
| 11:30 – 12:00 | Lesson: Kiro for Cloud Security | [Slides](https://docs.google.com/presentation/d/1edug67aDepcrbPXwHDflaaVrhGOW1JXO/edit?usp=drive_link&ouid=109780715844951499863&rtpof=true&sd=true) |
| 12:00 – 1:00 | Lunch | — |
| 1:00 – 1:30 | Knowledge Refresh Game | N/A |
| 1:30 – 2:00 | **Lab 5: Hardening IAM Policies with Kiro + MCP** | [Instructions](./lab-5-kiro-iam-hardening/README.md) |
| 2:00 – 2:30 | **Lab 6: Privilege Escalation via iam:PassRole (EC2)** | [Instructions](./lab-6-passrole-ec2/README.md)<br>[Slides](https://docs.google.com/presentation/d/1Ooka3AlRLppVj8w9ca1XsPK_pUjnicFs/edit?usp=drive_link&ouid=109780715844951499863&rtpof=true&sd=true) |
| 2:30 – 2:45 | Afternoon Break | — |
| 2:45 – 3:15 | **Lab 7: Privilege Escalation via Lambda UpdateFunctionCode** | [Instructions](./lab-7-lambda-updatefunctioncode/README.md)<br>[Slides](https://docs.google.com/presentation/d/1BeZ_opM_Vfi3_4FLvwP1wbrllA55d4sc/edit?usp=drive_link&rtpof=true&sd=true) |
| 2:45 – 3:15 | **Lab 8: Lambda Secret Extraction** | [Instructions](./lab-8-lambda-secrets/README.md)<br>[Slides](https://docs.google.com/presentation/d/1JegcTECdlsICUz6EngVbF5HSdzz5aB-W/edit?usp=drive_link&ouid=109780715844951499863&rtpof=true&sd=true) |
| 3:15 – 3:30 | Lesson: IAM Spy and Provers | [Slides](https://docs.google.com/presentation/d/1tnTvKrRj0TfFRdA_I7mn8OMqKx0s8ll-/edit?usp=drive_link&ouid=109780715844951499863&rtpof=true&sd=true) |
| 3:30 – 4:30 | Flex / Knowledge Game 2 | N/A |
| 4:30 – 5:00 | **Lab 9: Environment Cleanup and Wrap-up** | [Instructions](./lab-9-cleanup/README.md) |

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