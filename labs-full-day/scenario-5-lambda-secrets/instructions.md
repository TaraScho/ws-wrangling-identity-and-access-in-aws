## Scenario 5: Lambda Environment Variables — Credential Access via GetFunctionConfiguration

**Category:** Credential Access
**Starting Identity:** `iamws-secrets-reader-user`
**Target:** Plaintext secrets in `iamws-app-with-secrets` Lambda environment variables

**The Vulnerability:** `iamws-secrets-reader-user` can read Lambda function configurations, which include environment variables. The Lambda function `iamws-app-with-secrets` stores database credentials, API keys, and admin passwords in plaintext environment variables — visible to anyone with `lambda:GetFunctionConfiguration`.

**Real-world scenario:** A monitoring or debugging tool needs read access to Lambda configurations to check runtime settings. Environment variables are a common but insecure place to store secrets. Anyone with this read permission can see all of them — no escalation required.

### Part A: Identify with iam-recon

Build or refresh your iam-recon graph:

```bash
iam-recon graph create --profile taractf
```

Confirm the attacker user has permission to read Lambda function configurations:

```bash
iam-recon --account $ACCOUNT_ID argquery \
  --principal user/iamws-secrets-reader-user \
  --action lambda:GetFunctionConfiguration
```

Expected output:
```
ALLOW user/iamws-secrets-reader-user can call lambda:GetFunctionConfiguration with *
```

This is the only iam-recon surface that catches this scenario — there is no pathfinding or privesc edge for credential access via Lambda env vars.

> [!NOTE]
> `iam-recon analysis` does **not** flag Lambda functions with sensitive environment variable names — iam-recon has no env-var or secrets detector (verified 2026-05-12). `pathfinding` similarly has no Credential Access category. This scenario illustrates a real coverage gap in IAM graph tools: they model permission escalation, not data exposure. The right move is to check for dangerous permissions with `argquery`, then enumerate functions with env vars via the AWS CLI.

### Part B: Understand the Attack

- **Category:** Credential Access
- **Required permission:** `lambda:GetFunctionConfiguration`
- **Root cause:** Secrets stored in plaintext Lambda environment variables
- **Impact:** Access to credentials for external systems — databases, APIs, admin consoles

> [!NOTE]
> This is different from the previous scenarios — you're not escalating IAM permissions. The attacker's AWS permissions never change, and there are no crown jewels in S3 to claim. But don't underestimate it: in production, exposed database passwords, API keys, and admin credentials often grant access to data just as sensitive as anything in S3 — customer PII, SaaS admin consoles, or credentials for external systems that AWS IAM can't gate at all.

### Part C: Exploit the Vulnerability

**Step 1: Confirm your identity**

```bash
aws sts get-caller-identity --profile iamws-secrets-reader-user
```

Expected output:
```json
{
    "UserId": "AIDAXXXXXXXXXXXXXXXXX",
    "Account": "767397689800",
    "Arn": "arn:aws:iam::767397689800:user/iamws-secrets-reader-user"
}
```

**Step 2: Find Lambdas with environment variables**

```bash
aws lambda list-functions \
  --query 'Functions[?Environment.Variables].FunctionName' \
  --output table --profile iamws-secrets-reader-user
```

Expected output: `iamws-app-with-secrets` — this function has env vars.

**Step 3: Dump the environment variables**

```bash
aws lambda get-function-configuration \
  --function-name iamws-app-with-secrets \
  --query 'Environment.Variables' --output json \
  --profile iamws-secrets-reader-user
```

Expected output:
```json
{
    "DB_HOST": "prod-db.example.internal",
    "DB_USERNAME": "app_service_account",
    "DB_PASSWORD": "SuperSecretPassword123!",
    "API_KEY": "sk-prod-api-key-do-not-expose",
    "ADMIN_CREDENTIALS": "admin:P@ssw0rd!"
}
```

Five plaintext secrets — production DB credentials, an API key, and admin credentials — exposed with a single API call.

### Part D: Apply the Defense

The fix is architectural, not a policy edit. Move the secrets to AWS Secrets Manager, grant the Lambda's execution role access to only that secret, and replace the plaintext env vars with a pointer.

Run all defense steps as your admin identity.

**Step 1: Create the secret in Secrets Manager**

```bash
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
```

Note the ARN in the output — you'll need the suffix (random characters after `iamws-app-secrets-`) in Step 3.

Example output:
```json
{
    "ARN": "arn:aws:secretsmanager:us-east-1:767397689800:secret:iamws-app-secrets-Q5nIvd",
    "Name": "iamws-app-secrets"
}
```

**Step 2: Grant the Lambda's execution role access to this secret**

```bash
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
```

The `Resource` ARN ends with `*` because Secrets Manager appends a random suffix to the secret ARN — without the wildcard, the policy may stop matching after rotation.

**Step 3: Replace plaintext env vars with a secret-name reference**

```bash
aws lambda update-function-configuration \
  --function-name iamws-app-with-secrets \
  --environment '{"Variables":{"SECRET_NAME":"iamws-app-secrets"}}'
```

The five plaintext secrets are gone — replaced by a single pointer. The Lambda retrieves the actual values from Secrets Manager at runtime.

**Conceptual (don't run today):** here's what the Lambda handler code looks like with Secrets Manager:

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

### Part E: Verify the Remediation

**Step 1: Re-run the disclosure — confirm only the pointer is visible**

```bash
aws lambda get-function-configuration \
  --function-name iamws-app-with-secrets \
  --query 'Environment.Variables' --output json \
  --profile iamws-secrets-reader-user
```

Expected output:
```json
{
    "SECRET_NAME": "iamws-app-secrets"
}
```

No plaintext secrets. The attacker can see the secret's name but not its value.

**Step 2: Confirm the attacker can't fetch the secret directly**

```bash
aws secretsmanager get-secret-value \
  --secret-id iamws-app-secrets \
  --profile iamws-secrets-reader-user
```

Expected output:
```
An error occurred (AccessDeniedException) when calling the GetSecretValue operation:
User: arn:aws:iam::767397689800:user/iamws-secrets-reader-user
is not authorized to perform: secretsmanager:GetSecretValue on resource: iamws-app-secrets
```

The attacker user has no Secrets Manager permissions.

**Step 3: Verify with iam-recon**

Confirm the Lambda's execution role can access the secret (using the actual ARN from Step 1 of the defense):

```bash
iam-recon --account $ACCOUNT_ID argquery \
  --principal role/iamws-app-lambda-role \
  --action secretsmanager:GetSecretValue \
  --resource 'arn:aws:secretsmanager:us-east-1:767397689800:secret:iamws-app-secrets-<suffix>'
```

Expected output: `ALLOW role/iamws-app-lambda-role can call secretsmanager:GetSecretValue with ...`

Confirm the attacker user is denied:

```bash
iam-recon --account $ACCOUNT_ID argquery \
  --principal user/iamws-secrets-reader-user \
  --action secretsmanager:GetSecretValue
```

Expected output: `DENY user/iamws-secrets-reader-user cannot call secretsmanager:GetSecretValue with *`

### What You Learned

- Lambda environment variables are visible to **anyone** with `lambda:GetFunctionConfiguration` — they are not secure storage.
- This is **credential access**, not IAM privilege escalation. The attacker's permissions never change; the fix is eliminating the exposed data.
- Moving secrets to Secrets Manager provides proper access control (scoped per-secret ARN), automatic rotation, encryption at rest, and audit logging via CloudTrail `GetSecretValue` events.
- iam-recon has no env-var or credential exposure detector — `argquery` on the specific read action is the only iam-recon surface for this scenario.
- The Secrets Manager `Resource` ARN should end with `*` to handle the random suffix Secrets Manager appends.

### Cleanup

See [`cleanup.md`](cleanup.md) for revert steps before moving to the next scenario.

---

**Next:** [Optional Scenario: PutGroupPolicy](../scenario-optional-putgrouppolicy/instructions.md) — Self-escalation via group policy manipulation
