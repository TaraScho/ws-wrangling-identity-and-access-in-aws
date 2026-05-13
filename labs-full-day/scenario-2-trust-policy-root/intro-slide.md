# Scenario 2 — AssumeRole with trust `:root`

## Slide intro bullets

- `iamws-privileged-admin-role` trusts `arn:aws:iam::$ACCOUNT_ID:root` — looks scoped, actually means "anyone in the account with sts:AssumeRole."
- `iamws-role-assumer` user has `sts:AssumeRole *` → assumes the admin role.
- iam-recon shows this as a STS edge from user → role with no MFA condition.
- Pathfinding.cloud category: STS-AssumeRole (trust-policy overpermissive).

## Learning objective

Participants distinguish between principal-style identifiers and account-root principal, and recognize that `:root` in a trust policy is *not* a least-privilege constraint.
