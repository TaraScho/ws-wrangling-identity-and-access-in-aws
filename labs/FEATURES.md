# Lab Features Roadmap

This document tracks the features for the IAM workshop lab reorganization. Each feature will become a GitHub issue for implementation.

---

## Style Guidelines

### What to Include

1. **pathfinding.cloud link** - Link to actual website (e.g., `https://pathfinding.cloud/paths/iam-007`), NOT local fork
2. **Clear step-by-step instructions** - Simple, concise, not verbose
3. **Screenshots for awspx** - Show what learners should see in the graph
4. **Command output samples** - Abbreviated/selected output showing expected results
5. **One-liner scenario description** - Reference actual resource names (e.g., "The `iamws-dev-self-service-user` can attach policies to any user, including themselves")
6. Clear digestible headings.

### What to Avoid

- Reflection questions
- Overly verbose explanations
- Vague instructions

### Available Resources

For understanding tools and troubleshooting:
- `~/repos/pathfinding.cloud` - Local fork of pathfinding.cloud (reference for path details)
- `~/tools/pmapper` - Local pmapper installation
- `~/repos/awspx` - Local awspx installation

---

## Overview

**Goal**: Restructure labs to align with lecture content:
- Lab 1 (after Lecture 1 - PARC): Setup + Identify + Exploit
- Lab 2 (after Lecture 2 - Guardrails): Remediate + Verify

**Scenarios** (ordered by complexity):
1. AttachUserPolicy (Self-Escalation) → Permissions Boundary
2. CreateAccessKey (Principal Access) → Resource Constraint
3. UpdateAssumeRolePolicy (Principal Access) → Trust Policy
4. PassRole + EC2 (New PassRole) → Condition Key

---

## Feature 1: awspx and pmapper Setup Instructions

**File**: `labs/lab-1-layin-down-the-law/lab-1-instructions.md`

**Description**:
Write Exercise 1 with instructions for setting up awspx ingest and pmapper graph. This is the foundation that all subsequent scenarios depend on.

**Tasks**:
- [ ] Research awspx commands for AWS account ingest
- [ ] Write Part A: awspx ingest instructions
- [ ] Write Part B: pmapper graph create instructions
- [ ] Write Part C: pmapper analysis (initial scan)
- [ ] Test awspx ingest with Playwright (verify graph renders)
- [ ] Test pmapper commands with Bash

**Acceptance Criteria**:
- awspx successfully ingests AWS account data
- awspx graph is viewable/queryable
- pmapper graph creates without errors
- pmapper analysis shows privilege escalation paths

**Dependencies**: None

---

## Feature 2: Lab 1 Scenario 1 - AttachUserPolicy (Identify + Exploit)

**File**: `labs/lab-1-layin-down-the-law/lab-1-instructions.md`

**Description**:
Write Exercise 2 covering the AttachUserPolicy self-escalation path. Learners will graph it in awspx, query with pmapper, understand via pathfinding.cloud, and exploit it.

**Tasks**:
- [ ] Write Part A: Graph in awspx (visualize self-escalation path)
- [ ] Write Part B: pmapper query - `can user/iamws-dev-self-service-user do iam:AttachUserPolicy with *`
- [ ] Write Part C: pathfinding.cloud - browse IAM-007
- [ ] Write Part D: Exploit - attach AdministratorAccess to self (move from Lab 2 lines 31-60)
- [ ] Fix user name: `iamws-dev-permissions-user` → `iamws-dev-self-service-user`
- [ ] Test awspx graph query with Playwright
- [ ] Test pmapper query with Bash
- [ ] Test exploit commands with Bash

**Acceptance Criteria**:
- awspx shows the AttachUserPolicy escalation path
- pmapper confirms user can do iam:AttachUserPolicy
- Exploit succeeds: user gains AdministratorAccess

**Dependencies**: Feature 1

---

## Feature 3: Lab 1 Scenario 2 - CreateAccessKey (Identify + Exploit)

**File**: `labs/lab-1-layin-down-the-law/lab-1-instructions.md`

**Description**:
Write Exercise 3 covering the CreateAccessKey principal access path. Learners will graph, query, understand, and exploit.

**Tasks**:
- [ ] Write Part A: Graph in awspx (visualize credential theft path)
- [ ] Write Part B: pmapper query - `who can do iam:CreateAccessKey with *`
- [ ] Write Part C: pathfinding.cloud - browse IAM-002
- [ ] Write Part D: Exploit - create access key for admin user (move from Lab 2 lines 405-429)
- [ ] Test awspx graph query with Playwright
- [ ] Test pmapper query with Bash
- [ ] Test exploit commands with Bash

**Acceptance Criteria**:
- awspx shows the CreateAccessKey escalation path
- pmapper identifies users who can create access keys for others
- Exploit succeeds: new access key created for target user

**Dependencies**: Feature 1

---

## Feature 4: Lab 1 Scenario 3 - UpdateAssumeRolePolicy (Identify + Exploit)

**File**: `labs/lab-1-layin-down-the-law/lab-1-instructions.md`

**Description**:
Write Exercise 4 covering the UpdateAssumeRolePolicy principal access path. This is more complex as it involves modifying trust policies.

**Tasks**:
- [ ] Write Part A: Graph in awspx (visualize trust policy manipulation)
- [ ] Write Part B: pmapper query - `can user/iamws-integration-admin-user do iam:UpdateAssumeRolePolicy with *`
- [ ] Write Part C: pathfinding.cloud - browse IAM-012
- [ ] Write Part D: Exploit - update trust policy + assume role (move from Lab 2 lines 159-203)
- [ ] Test awspx graph query with Playwright
- [ ] Test pmapper query with Bash
- [ ] Test exploit commands with Bash

**Acceptance Criteria**:
- awspx shows the UpdateAssumeRolePolicy escalation path
- pmapper confirms user can modify trust policies
- Exploit succeeds: user can assume the privileged role

**Dependencies**: Feature 1

---

## Feature 5: Lab 1 Scenario 4 - PassRole + EC2 (Identify + Exploit)

**File**: `labs/lab-1-layin-down-the-law/lab-1-instructions.md`

**Description**:
Write Exercise 5 covering the PassRole + EC2 new-passrole path. This is the most complex scenario involving EC2 instance creation.

**Tasks**:
- [ ] Write Part A: Graph in awspx (visualize PassRole attack chain)
- [ ] Write Part B: pmapper query - `can user/iamws-ci-runner-user do iam:PassRole with *`
- [ ] Write Part C: pathfinding.cloud - browse EC2-001
- [ ] Write Part D: Exploit - launch EC2 with privileged role (move from Lab 2 lines 281-319)
- [ ] Test awspx graph query with Playwright
- [ ] Test pmapper query with Bash
- [ ] Test exploit commands with Bash (note: EC2 launch has cost implications)

**Acceptance Criteria**:
- awspx shows the PassRole + EC2 escalation path
- pmapper confirms user can pass roles
- Exploit documented (may not fully test due to EC2 costs)

**Dependencies**: Feature 1

---

## Feature 6: Lab 1 Wrap-up Section

**File**: `labs/lab-1-layin-down-the-law/lab-1-instructions.md`

**Description**:
Update the wrap-up section to summarize what was learned and transition to Lab 2.

**Tasks**:
- [ ] Update summary table (remove Lab 2 exercise references)
- [ ] Add transition text pointing to Lab 2 for remediation
- [ ] Update learning objectives in overview to include exploitation
- [ ] Update title to "Identifying and Exploiting IAM Misconfigurations"

**Acceptance Criteria**:
- Lab 1 reads as complete narrative: setup → identify → exploit
- Clear handoff to Lab 2 for remediation

**Dependencies**: Features 2-5

---

## Feature 7: Lab 2 Scenario 1 - AttachUserPolicy (Remediate + Verify)

**File**: `labs/lab-2-fencin-the-frontier/lab-2-instructions.md`

**Description**:
Update Exercise 1 to be remediation-focused. Remove exploit section (now in Lab 1), add vulnerability recap.

**Tasks**:
- [ ] Remove Part A: Exploit (moved to Lab 1)
- [ ] Add Part A: Review the Vulnerability (2-3 sentence recap)
- [ ] Keep Part B: Apply Permissions Boundary (existing content)
- [ ] Keep Part C: Verify boundary blocks escalation (existing content)
- [ ] Fix user name: `iamws-dev-permissions-user` → `iamws-dev-self-service-user`
- [ ] Test remediation commands with Bash
- [ ] Test verification commands with Bash

**Acceptance Criteria**:
- No exploit content in Lab 2 for this scenario
- Permissions boundary successfully applied
- Verification confirms boundary blocks escalation

**Dependencies**: Feature 2 (Lab 1 Scenario 1 must exist)

---

## Feature 8: Lab 2 Scenario 2 - CreateAccessKey (Remediate + Verify)

**File**: `labs/lab-2-fencin-the-frontier/lab-2-instructions.md`

**Description**:
Update Exercise 2 (reordered from current Exercise 4) to be remediation-focused.

**Tasks**:
- [ ] Remove Part A: Exploit (moved to Lab 1)
- [ ] Add Part A: Review the Vulnerability (2-3 sentence recap)
- [ ] Keep Part B: Apply `${aws:username}` resource constraint (existing content)
- [ ] Keep Part C: Verify can manage own keys but not others (existing content)
- [ ] Test remediation commands with Bash
- [ ] Test verification commands with Bash

**Acceptance Criteria**:
- Resource constraint successfully applied
- User can create/delete own access keys
- User cannot create access keys for other users

**Dependencies**: Feature 3 (Lab 1 Scenario 2 must exist)

---

## Feature 9: Lab 2 Scenario 3 - UpdateAssumeRolePolicy (Remediate + Verify)

**File**: `labs/lab-2-fencin-the-frontier/lab-2-instructions.md`

**Description**:
Update Exercise 3 (reordered from current Exercise 2) to be remediation-focused.

**Tasks**:
- [ ] Remove Part A: Exploit (moved to Lab 1)
- [ ] Add Part A: Review the Vulnerability (2-3 sentence recap)
- [ ] Keep Part B: Apply explicit deny + harden trust policy (existing content)
- [ ] Keep Part C: Verify both defenses work (existing content)
- [ ] Test remediation commands with Bash
- [ ] Test verification commands with Bash

**Acceptance Criteria**:
- Explicit deny policy applied to user
- Trust policy hardened (specific principals only)
- User cannot update trust policy or assume the role

**Dependencies**: Feature 4 (Lab 1 Scenario 3 must exist)

---

## Feature 10: Lab 2 Scenario 4 - PassRole + EC2 (Remediate + Verify)

**File**: `labs/lab-2-fencin-the-frontier/lab-2-instructions.md`

**Description**:
Update Exercise 4 (reordered from current Exercise 3) to be remediation-focused.

**Tasks**:
- [ ] Remove Part A: Exploit (moved to Lab 1)
- [ ] Add Part A: Review the Vulnerability (2-3 sentence recap)
- [ ] Keep Part B: Apply `iam:PassedToService` condition key (existing content)
- [ ] Keep Part C: Verify condition blocks attack (existing content)
- [ ] Test remediation commands with Bash
- [ ] Test verification commands with Bash

**Acceptance Criteria**:
- Condition key successfully restricts PassRole
- User cannot launch EC2 with privileged role

**Dependencies**: Feature 5 (Lab 1 Scenario 4 must exist)

---

## Feature 11: Lab 2 Wrap-up and Cleanup

**File**: `labs/lab-2-fencin-the-frontier/lab-2-instructions.md`

**Description**:
Update wrap-up section and ensure cleanup instructions are accurate.

**Tasks**:
- [ ] Update title to "Remediating IAM Misconfigurations with Guardrails"
- [ ] Update overview to focus on remediation
- [ ] Update prerequisites to mention Lab 1 exploitation completed
- [ ] Keep Defense in Depth diagram (existing content)
- [ ] Keep Key Takeaways (existing content)
- [ ] Update cleanup instructions to match scenario order
- [ ] Verify terraform destroy works

**Acceptance Criteria**:
- Lab 2 reads as complete narrative: recap → remediate → verify → cleanup
- Cleanup instructions are accurate and complete

**Dependencies**: Features 7-10

---

## Implementation Order

1. Feature 1 (Setup) - foundation for all Lab 1 scenarios
2. Features 2-5 (Lab 1 Scenarios) - can be done in parallel after Feature 1
3. Feature 6 (Lab 1 Wrap-up) - after Features 2-5
4. Features 7-10 (Lab 2 Scenarios) - after corresponding Lab 1 scenarios
5. Feature 11 (Lab 2 Wrap-up) - after Features 7-10

---

## Notes

- **User name fix**: All occurrences of `iamws-dev-permissions-user` must become `iamws-dev-self-service-user`
- **Testing**: Use Playwright for awspx graph verification, Bash for command verification
- **pathfinding.cloud references**: IAM-007, IAM-002, IAM-012, EC2-001
