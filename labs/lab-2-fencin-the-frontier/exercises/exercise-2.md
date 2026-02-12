## Exercise 2: Harden Trust Policy for AssumeRole

### Recap

In Lab 1 Exercise 4, you exploited `iamws-privileged-admin-role` because its trust policy trusted `:root` — letting any principal assume it (Principal Access). The root cause: trust policy uses `:root` instead of specific principals.

### Understanding Trust Policies

Trust policies ARE resource policies—they're attached to the role itself (not to the caller). They control WHO can assume the role:

```
┌─────────────────────────────────────────┐
│  Caller's Identity Policy               │
│  "sts:AssumeRole" with Resource: "*"    │
├─────────────────────────────────────────┤
│  Role's Trust Policy (Resource Policy)  │
│  Who is allowed to assume this role?    │
├─────────────────────────────────────────┤
│  RESULT                                 │
│  Both must allow for assume to succeed  │
└─────────────────────────────────────────┘
```

The trust policy is the **defense**—by restricting who it trusts, you control who can become that role.

### Part A: Examine the Current Trust Policy 

```bash
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

**The problem:** As you know, `:root` means "any principal in this account can assume this role if their identity policy allows `sts:AssumeRole`."

### Part B: Harden the Trust Policy

Update the trust policy to only allow specific, authorized principals:

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Get the ARN of the principal that SHOULD be allowed (e.g., your admin role)
ADMIN_ROLE_ARN=$(aws sts get-caller-identity --query Arn --output text)

aws iam update-assume-role-policy \
  --role-name iamws-privileged-admin-role \
  --policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Principal": {
        "AWS": "'$ADMIN_ROLE_ARN'"
      },
      "Action": "sts:AssumeRole",
      "Condition": {
        "Bool": {
          "aws:MultiFactorAuthPresent": "true"
        }
      }
    }]
  }'
```

**What we changed:**
1. **Specific principal:** Only your admin role can assume it (not anyone in the account) - eliminates the `:root` vuln
1. **MFA condition:** Requires MFA for additional security - good application of condition keys for extra hardening

### Part C: Verify the Remediation

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text \
  --profile iamws-role-assumer-user)

# Try to assume the privileged role
aws sts assume-role \
  --role-arn arn:aws:iam::${ACCOUNT_ID}:role/iamws-privileged-admin-role \
  --role-session-name escalated \
  --profile iamws-role-assumer-user
```

**Expected result:**
```
An error occurred (AccessDenied) when calling the AssumeRole operation:
User: arn:aws:iam::ACCOUNT_ID:user/iamws-role-assumer-user
is not authorized to perform: sts:AssumeRole on resource:
arn:aws:iam::ACCOUNT_ID:role/iamws-privileged-admin-role
```

**The attack is blocked!** The hardened trust policy doesn't trust the attacker.

**Verify the crown jewels are still protected:**

```bash
aws s3 cp s3://iamws-crown-jewels-${ACCOUNT_ID}/flag.txt - \
  --profile iamws-role-assumer-user
```

**Expected:** `Forbidden` — the role assumer can't assume the admin role anymore, so the crown jewels remain safe.

### What You Learned

- Trust policies using `:root` are dangerously permissive—they trust EVERYONE in the account
- Always use **specific principal ARNs** in trust policies
- Add **conditions** (like MFA) for additional security on sensitive roles
- Trust policies are the first line of defense for role assumption

---

**Next:** [Exercise 3: Condition Key for PassRole + EC2](exercise-3.md) — Use iam:PassedToService to limit PassRole targets
