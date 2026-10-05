# Wrangling Identity and Access in AWS — Two-Hour Workshop

A condensed, hands-on workshop on AWS IAM privilege escalation and remediation. You'll build an offline graph of a vulnerable AWS account with `iam-recon`, exploit real privilege escalation paths from [pathfinding.cloud](https://pathfinding.cloud), and then harden each one with permissions boundaries, trust-policy scoping, and condition keys.

This two-hour workshop runs the same labs as the full-day version, minus the Kiro hardening lab. The attack-and-defense labs (4–7) are worked **as far as the group gets in the time available** — some participants will go faster than others, and that's expected.

> [!IMPORTANT]
> This workshop deploys intentionally vulnerable IAM infrastructure to your AWS account. Do not deploy workshop resources to an account with any production data or workloads. Use a dedicated sandbox account.

## Prerequisites

You need a sandbox AWS account (**never** production) with permissions to create and manage IAM users, roles, groups, policies, and permissions boundaries; Lambda functions; EC2 instances and security groups; S3 buckets; CloudFormation stacks; and Secrets Manager secrets. `AdministratorAccess` in a sandbox account works.

- **Facilitated participants:** Start at [Lab 1 — Lab Setup](./lab-1-setup/README.md). It runs `setup.sh`, which installs every tool (AWS CLI v2, Terraform, `iam-recon`, the SSM Session Manager plugin), deploys the Terraform infrastructure, and configures all AWS CLI profiles for you. A pre-built workshop VM image is also available — see the Lab 1 README.
- **Own-laptop / self-service setup:** Follow [Lab 0 — Prerequisites](./lab-0-prerequisites/lab-0-prerequisites.md) to install the tools and deploy the environment by hand, then pick up at Lab 1's recon steps.

> [!NOTE]
> Windows is not supported on the own-laptop path — `iam-recon` does not ship a Windows binary. Use the pre-built workshop VM image (the VirtualBox variant runs on Windows).

## Agenda

Use this README as your playbook. Each row links to the instructions you'll work from during that block.

| Block | Materials |
| :--- | :--- |
| Welcome and Introduction to IAM | [Slides](https://docs.google.com/presentation/d/1z6z0WDAdlMDVyiDvu2jmfG_a9le--AM1/edit?usp=drive_link&rtpof=true&sd=true) |
| **Lab 1: Lab Setup** | [Instructions](./lab-1-setup/README.md)<br>[Slides](https://docs.google.com/presentation/d/1QSUtnibKrYtv2-eEfJ6SlNwzUcLFZsH_/edit?usp=drive_link&rtpof=true&sd=true) |
| **Lab 2: Self Privilege Escalation via CreatePolicyVersion** | [Instructions](./lab-2-create-policy-version/README.md)<br>[Slides](https://docs.google.com/presentation/d/1ylN5bXFtflkiJqCH5vUmW65AMs7BiF38/edit?usp=drive_link&rtpof=true&sd=true) |
| **Lab 3: Trust Policy Abuse** | [Instructions](./lab-3-trust-policy-abuse/README.md)<br>[Slides](https://docs.google.com/presentation/d/1AKED2urhbXi8-3XEkMBafXSWQh8xd-jI/edit?usp=drive_link&ouid=109780715844951499863&rtpof=true&sd=true) |
| Lesson: Guardrails and Validation | [Slides](https://docs.google.com/presentation/d/1cj7xJw6OB84WSbeuTEKOsdmcVRb_T8Ea/edit?usp=drive_link&ouid=109780715844951499863&rtpof=true&sd=true) |
| **Lab 4: Permissions Boundaries & Condition Keys** | [Instructions](./lab-4-permissions-boundaries-and-condition-keys/README.md)<br>[Slides](https://docs.google.com/presentation/d/1gW3cBqOJ_WVPKgZbLy8EnklvhHJ5LBaU/edit?usp=drive_link&ouid=109780715844951499863&rtpof=true&sd=true) |
| **Lab 5: Privilege Escalation via iam:PassRole (EC2)** | [Instructions](./lab-5-passrole-ec2/README.md)<br>[Slides](https://docs.google.com/presentation/d/1Ooka3AlRLppVj8w9ca1XsPK_pUjnicFs/edit?usp=drive_link&ouid=109780715844951499863&rtpof=true&sd=true) |
| **Lab 6: Privilege Escalation via Lambda UpdateFunctionCode** | [Instructions](./lab-6-lambda-updatefunctioncode/README.md)<br>[Slides](https://docs.google.com/presentation/d/1BeZ_opM_Vfi3_4FLvwP1wbrllA55d4sc/edit?usp=drive_link&rtpof=true&sd=true) |
| **Lab 7: Lambda Secret Extraction** | [Instructions](./lab-7-lambda-secrets/README.md)<br>[Slides](https://docs.google.com/presentation/d/1JegcTECdlsICUz6EngVbF5HSdzz5aB-W/edit?usp=drive_link&ouid=109780715844951499863&rtpof=true&sd=true) |
| **Lab 8: Environment Cleanup and Wrap-up** | [Instructions](./lab-8-cleanup/README.md) |

> [!NOTE]
> Labs 4–7 are the attack-and-defense core. Work through them in order as far as time allows — the facilitator will call time and move the group to cleanup regardless of how far along everyone is.

## Resources

### Tools Used in This Workshop

- [iam-recon](https://github.com/andrewkrug/iam-recon) — Single-binary Rust tool that builds an offline graph of IAM users, roles, groups, and policies and maps them to the attack paths catalogued by pathfinding.cloud. Used in every recon-and-verify step of the workshop.
- [pathfinding.cloud](https://pathfinding.cloud) — AWS IAM privilege escalation path database with interactive visualizations. Every iam-recon finding links back to a path here.
- [iam-vulnerable](https://github.com/BishopFox/iam-vulnerable) — Intentionally vulnerable IAM configurations. The workshop's Terraform modules are based on this project.

### AWS Documentation

- [IAM Access Analyzer](https://docs.aws.amazon.com/IAM/latest/UserGuide/what-is-access-analyzer.html) — Validate policies and find unintended external access.
- [Testing IAM policies](https://docs.aws.amazon.com/IAM/latest/UserGuide/access_policies_testing-policies.html) — IAM policy simulator and other validation approaches.
- [IAM security best practices](https://docs.aws.amazon.com/IAM/latest/UserGuide/best-practices.html)

### Further Learning

- [IAM Tutor](https://www.sharmaprateek.com/guides/iam-tutor/) — Interactive IAM policy walkthroughs.
- [Cloudsplaining](https://github.com/salesforce/cloudsplaining) — Identifies violations of least privilege in IAM policies.

## Cleanup

When you're done, tear down everything the workshop created — scenario artifacts, the Terraform-deployed infrastructure, and the local AWS CLI profiles. Follow [Lab 8 — Environment Cleanup](./lab-8-cleanup/README.md) for the full, correctly-sequenced teardown.
