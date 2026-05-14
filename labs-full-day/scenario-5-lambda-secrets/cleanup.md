# Scenario 5 — Cleanup

Run as `iamws-lab-default` (admin) after the defense demo, before the next scenario.

## Restore the original plaintext environment variables

```bash
aws lambda update-function-configuration \
  --function-name iamws-app-with-secrets \
  --environment '{"Variables":{
    "DB_HOST": "prod-db.example.internal",
    "DB_USERNAME": "app_service_account",
    "DB_PASSWORD": "SuperSecretPassword123!",
    "API_KEY": "sk-prod-api-key-do-not-expose",
    "ADMIN_CREDENTIALS": "admin:P@ssw0rd!"
  }}' \
  --profile iamws-lab-default
```

## Remove the secret and role policy

```bash
aws iam delete-role-policy \
  --role-name iamws-app-lambda-role \
  --policy-name SecretsManagerAccess \
  --profile iamws-lab-default

aws secretsmanager delete-secret \
  --secret-id iamws-app-secrets \
  --force-delete-without-recovery \
  --profile iamws-lab-default
```

## Confirm clean state

Verify the plaintext secrets are back in the env vars:

```bash
aws lambda get-function-configuration \
  --function-name iamws-app-with-secrets \
  --query 'Environment.Variables' --output json --profile iamws-lab-default
# expect: the 5 plaintext key/value pairs

aws iam list-role-policies \
  --role-name iamws-app-lambda-role \
  --query 'PolicyNames' --output text --profile iamws-lab-default
# expect: (empty — SecretsManagerAccess removed)
```
