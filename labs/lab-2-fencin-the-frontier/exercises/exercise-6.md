## Exercise 6: Resource Constraint for PutGroupPolicy

### Recap

In Lab 1 Exercise 2, you exploited `iamws-group-admin-user` to write an admin inline policy on `iamws-dev-team` — a group the attacker belongs to (Self-Escalation via `iam:PutGroupPolicy`). The root cause: `Resource: "*"` allowed writing inline policies on any group, including the attacker's own.

### Understanding the Fix

This is the same principle as Exercise 4's resource constraint, applied to group ARNs instead of Lambda ARNs. By restricting `iam:PutGroupPolicy` to only specific groups that the principal is **not** a member of, you prevent the self-escalation path.

The key insight: `iamws-group-admin-user` is a member of `iamws-dev-team` but **not** a member of `iamws-platform-team`. If we restrict `PutGroupPolicy` to only `iamws-platform-team`, the attacker can still manage group policies for that team — but can't escalate their own permissions.

### Part A: Create the Restrictive Policy

**Step 1: Get your account ID**

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
```

**Step 2: Apply a restrictive inline policy to the user**

This replaces the overly-permissive managed policy with an inline policy that only allows `PutGroupPolicy` on `iamws-platform-team` — a group the attacker is **not** a member of:

```bash
aws iam put-user-policy \
  --user-name iamws-group-admin-user \
  --policy-name SecureGroupAdmin \
  --policy-document '{
    "Version": "2012-10-17",
    "Statement": [
      {
        "Sid": "AllowPutGroupPolicyOnPlatformTeamOnly",
        "Effect": "Allow",
        "Action": "iam:PutGroupPolicy",
        "Resource": "arn:aws:iam::'${ACCOUNT_ID}':group/iamws-platform-team"
      },
      {
        "Sid": "AllowGroupEnumeration",
        "Effect": "Allow",
        "Action": [
          "iam:ListGroups",
          "iam:ListGroupPolicies",
          "iam:GetGroupPolicy",
          "iam:ListGroupsForUser",
          "iam:GetGroup"
        ],
        "Resource": "*"
      }
    ]
  }'
```

### Part B: Remove the Overly-Permissive Policy

Detach the original managed policy that allowed `PutGroupPolicy` on any group:

```bash
aws iam detach-user-policy \
  --user-name iamws-group-admin-user \
  --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/iamws-group-admin-policy
```

### Part C: Verify the Remediation

**Step 1: Try the original attack — PutGroupPolicy on iamws-dev-team (should fail)**

```bash
aws iam put-group-policy \
  --group-name iamws-dev-team \
  --policy-name test-escalation \
  --policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":"*","Resource":"*"}]}' \
  --profile iamws-group-admin-user
```

**Expected:** `AccessDenied` — the user can no longer write policies on their own group.

**Step 2: Try PutGroupPolicy on iamws-platform-team (should succeed)**

```bash
aws iam put-group-policy \
  --group-name iamws-platform-team \
  --policy-name test-allowed \
  --policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":"s3:GetObject","Resource":"*"}]}' \
  --profile iamws-group-admin-user
```

**Expected:** Success — they can still manage the group they're authorized for.

**Step 3: Clean up the test policy**

```bash
aws iam delete-group-policy \
  --group-name iamws-platform-team \
  --policy-name test-allowed \
  --profile iamws-group-admin-user
```

**The attack is blocked!** The resource constraint prevents the self-escalation path.

**Step 4: Verify the crown jewels are still protected**

```bash
aws s3 cp s3://iamws-crown-jewels-${ACCOUNT_ID}/flag.txt - \
  --profile iamws-group-admin-user
```

**Expected:** `AccessDenied` — the group admin can no longer escalate via their own group, so the crown jewels remain safe.

### What You Learned

- **Resource constraints** prevent self-escalation via group policies — same principle as Exercise 4
- Restricting `PutGroupPolicy` to specific group ARNs ensures users can only manage groups they're authorized for
- Combine resource constraints with **naming conventions** (e.g., team-based group prefixes) for scalable access control
- Always ask: "Is this principal a member of any group they can write policies on?"

---

**Next:** [Back to Lab 2 — Wrap-up](../lab-2-instructions.md#wrap-up)
