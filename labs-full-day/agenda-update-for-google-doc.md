# Updated "Formalized Outline w/ Links to Materials" — paste-ready

This file rebuilds the **Formalized Outline w/ Links to Materials** table in the [Bsides Tampa WS Outline Google Doc](https://docs.google.com/document/d/1ZltldmyaMyJqWtMDZHGWwFZEj1xMn225hdA0YKvJYVU/edit) so that the block names and instruction/slide links match the canonical full-day [README](https://github.com/TaraScho/ws-wrangling-identity-and-access-in-aws/blob/main/labs-full-day/README.md).

Block names use the README verbatim. GitHub instruction links are absolute URLs prefixed with `https://github.com/TaraScho/ws-wrangling-identity-and-access-in-aws/blob/main/`. The Speaker column is preserved from the existing Doc — only renamed where the corresponding block was renamed.

## Updated agenda table

| Time | Topic | Assets | Speaker |
| :---- | :---- | :---- | :---- |
| 9:00 – 9:40 | Welcome and Lesson 1: Introduction to IAM | [Slides](https://docs.google.com/presentation/d/1z6z0WDAdlMDVyiDvu2jmfG_a9le--AM1/edit?usp=drive_link&rtpof=true&sd=true) | Tara |
| 9:40 – 10:00 | Lab 1: Lab Setup | [Instructions](https://github.com/TaraScho/ws-wrangling-identity-and-access-in-aws/blob/main/labs-full-day/lab-setup-instructions.md) · [Slides](https://docs.google.com/presentation/d/1QSUtnibKrYtv2-eEfJ6SlNwzUcLFZsH_/edit?usp=drive_link&rtpof=true&sd=true) | Andrew |
| 10:00 – 10:15 | Lab 2: Self Privilege Escalation via CreatePolicyVersion | [Instructions](https://github.com/TaraScho/ws-wrangling-identity-and-access-in-aws/blob/main/labs-full-day/scenario-1a-create-policy-version.md) · [Slides](https://docs.google.com/presentation/d/1ylN5bXFtflkiJqCH5vUmW65AMs7BiF38/edit?usp=drive_link&rtpof=true&sd=true) | Tara |
| 10:15 – 10:30 | Lab 3: Trust Policy Abuse | [Instructions](https://github.com/TaraScho/ws-wrangling-identity-and-access-in-aws/blob/main/labs-full-day/scenario-2-trust-policy-root.md) · [Slides](https://docs.google.com/presentation/d/1AKED2urhbXi8-3XEkMBafXSWQh8xd-jI/edit?usp=drive_link&ouid=109780715844951499863&rtpof=true&sd=true) | Tara |
| 10:30 – 10:45 | Morning Break | — | N/A |
| 10:45 – 11:15 | Lesson 2: Guardrails and Validation | [Slides](https://docs.google.com/presentation/d/1cj7xJw6OB84WSbeuTEKOsdmcVRb_T8Ea/edit?usp=drive_link&ouid=109780715844951499863&rtpof=true&sd=true) | Andrew |
| 11:15 – 11:30 | Lab 4: Permissions Boundaries & Condition Keys | [Instructions](https://github.com/TaraScho/ws-wrangling-identity-and-access-in-aws/blob/main/labs-full-day/apply-permissions-boundaries-and-condition-keys.md) | Tara |
| 11:30 – 12:00 | Lesson 3: Kiro for Cloud Security | [Slides](https://docs.google.com/presentation/d/1edug67aDepcrbPXwHDflaaVrhGOW1JXO/edit?usp=drive_link&ouid=109780715844951499863&rtpof=true&sd=true) | Andrew |
| 12:00 – 1:00 | Lunch | — | N/A |
| 1:00 – 1:30 | Knowledge Refresh Game | Join link _(tbd)_ | Andrew |
| 1:30 – 2:00 | Lab 5: Hardening IAM Policies with Kiro + MCP | [Instructions](https://github.com/TaraScho/ws-wrangling-identity-and-access-in-aws/blob/main/labs-full-day/kiro-iam-hardening/instructions.md) | Andrew |
| 2:00 – 2:30 | Lab 6: Privilege Escalation via iam:PassRole (EC2) | [Instructions](https://github.com/TaraScho/ws-wrangling-identity-and-access-in-aws/blob/main/labs-full-day/scenario-3-passrole-ec2/attack.md) · [Slides](https://docs.google.com/presentation/d/1Ooka3AlRLppVj8w9ca1XsPK_pUjnicFs/edit?usp=drive_link&ouid=109780715844951499863&rtpof=true&sd=true) | Tara |
| 2:30 – 2:45 | Afternoon Break | — | N/A |
| 2:45 – 3:15 | Lab 7: Privilege Escalation via Lambda UpdateFunctionCode | [Instructions](https://github.com/TaraScho/ws-wrangling-identity-and-access-in-aws/blob/main/labs-full-day/scenario-4-lambda-updatefunctioncode/lambda-updatefunctioncode.md) · [Slides](https://docs.google.com/presentation/d/1BeZ_opM_Vfi3_4FLvwP1wbrllA55d4sc/edit?usp=drive_link&rtpof=true&sd=true) | Tara |
| 2:45 – 3:15 | Lab 8: Lambda Secret Extraction | [Instructions](https://github.com/TaraScho/ws-wrangling-identity-and-access-in-aws/blob/main/labs-full-day/scenario-5-lambda-secrets/instructions.md) · [Slides](https://docs.google.com/presentation/d/1JegcTECdlsICUz6EngVbF5HSdzz5aB-W/edit?usp=drive_link&ouid=109780715844951499863&rtpof=true&sd=true) | Tara |
| 3:15 – 3:30 | Lecture: IAM Spy and Provers | Slides _(tbd)_ | Andrew |
| 3:30 – 4:30 | Flex / Knowledge Game 2 | Join link _(tbd)_ | Andrew |
| 4:30 – 5:00 | Environment Clean up and Wrap-up | [Cleanup Instructions](https://github.com/TaraScho/ws-wrangling-identity-and-access-in-aws/blob/main/labs-full-day/lab-cleanup-instructions.md) | Both |

## Notes on the changes vs. the current Google Doc

1. The current Doc combines "Scenarios 4 and 5 – Privilege Escalation with Lambda" into one row at 2:45–3:15. The README splits these into **Lab 7** and **Lab 8** (both at 2:45–3:15, intended to run in parallel or as choices). Both are kept assigned to **Tara**, matching the existing Doc assignment.
1. Block titles changed to match README verbatim — e.g., "Lab Setup" → **Lab 1: Lab Setup**; "Lab: Privesc Scenario 1 - Self privilege escalation" → **Lab 2: Self Privilege Escalation via CreatePolicyVersion**; "Lecture - Guardrails and Validation" → **Lesson 2: Guardrails and Validation**.
1. GitHub URLs that previously pointed at the old `labs-full-day/scenario-1a-create-policy-version/instructions.md` (and similar) are now corrected to the README's actual paths (e.g., `labs-full-day/scenario-1a-create-policy-version.md`).
1. New URLs added for Lab 5 (Kiro hardening), Lab 7 (Lambda UpdateFunctionCode), Lab 8 (Lambda Secrets), and the wrap-up cleanup instructions, which were placeholders in the Doc.
1. Slide links from the README are reused as-is. Where the README has "Slides _(tbd)_" (IAM Spy, Game 1, Game 2), the Doc keeps the same placeholder.
1. Speakers preserved: Tara (welcome, Labs 2/3/4/6/7/8), Andrew (Lab 1 setup, Lessons 2/3, Knowledge games, Lab 5, IAM Spy lecture), N/A (breaks/lunch), Both (wrap-up).

## How to apply this in the Google Doc

1. Open the [Bsides Tampa WS Outline](https://docs.google.com/document/d/1ZltldmyaMyJqWtMDZHGWwFZEj1xMn225hdA0YKvJYVU/edit).
1. Scroll to the **Formalized Outline w/ Links to Materials** section.
1. Easiest path: delete the existing table, place your cursor in the empty spot, and use **Insert → Table from Sheets** (or just create a new 4-column table and paste rows). Then copy the rows above one-by-one. Hyperlinks paste through as live links if you copy from a rendered markdown preview or from the Slack/Notion preview of this file.
1. Faster manual path: keep the existing table and update each row in place — change the **Topic** text to match the README block name, replace the **Assets** links with the URLs above, and leave the **Speaker** column alone (it's already correct).
