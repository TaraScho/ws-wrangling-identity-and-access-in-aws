# Scenario 5 — Defense bullets (afternoon)

Source: Lab 2 Exercise 5. Pairs with `attack.md` (Lambda env-var secret disclosure). Control: **architectural — Secrets Manager**, not a policy edit.

## Slide intro bullets

- Lambda env vars are visible to anyone with `GetFunctionConfiguration` — they're not secure storage.
- Three-part fix:
  1. Move the secret to AWS Secrets Manager.
  2. Grant the Lambda's *execution role* `secretsmanager:GetSecretValue` on that secret ARN.
  3. Replace the env vars with a single `SECRET_NAME` pointer; the function fetches the value at runtime.
- iam-recon's `analysis` preset flags Lambdas with sensitive env-var names; after the fix, the finding disappears.

## Defense — full command path

```bash
# Step 1: create the secret in Secrets Manager (admin/workshop identity)
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

aws secretsmanager create-secret \
  --name iamws-app-secrets \
  --description "Secrets for the app Lambda function" \
  --secret-string '{
    "DB_HOST": "prod-db.example.internal",
    "DB_USERNAME": "app_service_account",
    "DB_PASSWORD": "SuperSecretPassword123!",
    "API_KEY": "sk-prod-api-key-do-not-expose"
  }'

# Step 2: grant the Lambda's execution role access to ONLY this secret
aws iam put-role-policy \
  --role-name iamws-app-lambda-role \
  --policy-name SecretsManagerAccess \
  --policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Action": ["secretsmanager:GetSecretValue"],
      "Resource": "arn:aws:secretsmanager:us-east-1:'${ACCOUNT_ID}':secret:iamws-app-secrets*"
    }]
  }'

# Step 3: replace plaintext env vars with a secret-name reference
aws lambda update-function-configuration \
  --function-name iamws-app-with-secrets \
  --environment '{"Variables":{"SECRET_NAME":"iamws-app-secrets"}}'
```

**Conceptual** (don't run today): Lambda handler code that fetches at runtime:

```python
import boto3, json, os
def get_secret():
    return json.loads(boto3.client('secretsmanager')
        .get_secret_value(SecretId=os.environ['SECRET_NAME'])['SecretString'])

def handler(event, context):
    secrets = get_secret()
    db_password = secrets['DB_PASSWORD']
    return {'statusCode': 200, 'body': 'Connected'}
```

## Verify with the attack

```bash
# Re-run the original disclosure as the attacker user
aws lambda get-function-configuration \
  --function-name iamws-app-with-secrets \
  --query 'Environment.Variables' --output json \
  --profile iamws-secrets-reader-user
# expect: { "SECRET_NAME": "iamws-app-secrets" } — no plaintext secrets anymore

# Can the attacker fetch the secret directly?
aws secretsmanager get-secret-value \
  --secret-id iamws-app-secrets \
  --profile iamws-secrets-reader-user
# expect: AccessDenied — the attacker user has no Secrets Manager perms
```

## Verify with iam-recon

- `iam-recon graph create --profile iamws-lab-default`.
- ⚠️ `iam-recon --account $ACCOUNT_ID analysis` never flagged the env-var disclosure in the first place (no detector — see attack.md note), so there's nothing to disappear here. Use the AWS CLI step (`get-function-configuration` returns a pointer instead of plaintext secrets) as the canonical "before/after" demo.
- `iam-recon --account $ACCOUNT_ID argquery --principal role/iamws-app-lambda-role --action secretsmanager:GetSecretValue --resource 'arn:aws:secretsmanager:us-east-1:'${ACCOUNT_ID}':secret:iamws-app-secrets-<suffix>'` → ALLOW for the Lambda execution role only (use the actual secret ARN — Secrets Manager appends a random suffix). Without `--resource`, argquery against `*` returns DENY because the policy is scoped.
- `iam-recon --account $ACCOUNT_ID argquery --principal user/iamws-secrets-reader-user --action secretsmanager:GetSecretValue` → DENY for the attacker (no Secrets Manager permission was ever granted).

## Demo bullets

- This is the *one* defense that requires application changes — emphasize that IAM policy alone can't fix this class of vuln.
- Side-by-side: pre-fix `get-function-configuration` dumped 5 secrets; post-fix returns a pointer.
- Discuss benefits unlocked by the move: rotation, encryption at rest, audit logging via CloudTrail's `GetSecretValue` events, fine-grained per-secret IAM.
- Watch-out: `Resource: "arn:...:iamws-app-secrets*"` ends in a wildcard because Secrets Manager appends a random suffix to the ARN — without it, post-rotation the policy may stop matching.
