## Exercise 5: Secrets Manager for Credential Access

### Recap

In Lab 1 Exercise 7, you read plaintext secrets from Lambda environment variables using `lambda:GetFunctionConfiguration` (Credential Access). The root cause: secrets stored in env vars instead of a proper secrets manager.

### Understanding the Problem

Lambda environment variables are NOT secure storage:
- Anyone with `lambda:GetFunctionConfiguration` can read them
- They're visible in the AWS Console
- They may appear in logs

**The fix isn't an IAM policy change—it's architectural:**
1. Store secrets in AWS Secrets Manager
1. Grant the Lambda role permission to read specific secrets
1. Retrieve secrets at runtime in the Lambda code

### Part A: Create a Secret in Secrets Manager

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Create the secret
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

Example output:

```
{
    "ARN": "arn:aws:secretsmanager:us-east-1:072054739058:secret:iamws-app-secrets-Q5nIvd",
    "Name": "iamws-app-secrets",
    "VersionId": "211e0d9e-2f1b-4c95-8c4c-9f8341491fd7"
}
```

### Part B: Grant the Lambda Role Access to the Secret

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Add a policy to the Lambda's execution role
aws iam put-role-policy \
  --role-name iamws-app-lambda-role \
  --policy-name SecretsManagerAccess \
  --policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue"
      ],
      "Resource": "arn:aws:secretsmanager:us-east-1:'${ACCOUNT_ID}':secret:iamws-app-secrets*"
    }]
  }'
```

### Part C: Update the Lambda to Use Secrets Manager (Conceptual — you don't need to run this in today's lab)

In production, you'd update the Lambda code to retrieve secrets at runtime instead of reading them from environment variables. Here's what that looks like:

```python
import boto3
import json
import os

def get_secret():
    secret_name = os.environ['SECRET_NAME']

    client = boto3.client('secretsmanager')

    response = client.get_secret_value(SecretId=secret_name)
    return json.loads(response['SecretString'])

def handler(event, context):
    # Secrets retrieved at runtime, not stored in env vars
    secrets = get_secret()
    db_password = secrets['DB_PASSWORD']

    # Use the secret to connect to the database...
    return {
        'statusCode': 200,
        'body': 'Connected to database successfully'
    }
```

### Part D: Replace Secrets with a Secret Reference

```bash
# Replace plaintext secrets with just a pointer to the secret name
aws lambda update-function-configuration \
  --function-name iamws-app-with-secrets \
  --environment '{"Variables":{"SECRET_NAME":"iamws-app-secrets"}}'
```

This replaces all existing env vars with just the secret reference — the plaintext values are gone.

### Part E: Verify the Remediation

**Step 1: Confirm the environment variables only contain the secret reference**

```bash
aws lambda get-function-configuration \
  --function-name iamws-app-with-secrets \
  --query 'Environment.Variables' \
  --output json
```

Expected output:

```json
{
    "SECRET_NAME": "iamws-app-secrets"
}
```

Lambda can use this secret name to find the secret in Secrets Manager at runtime - no need to store it in plain text.

### What You Learned

- This was an **Lambda configuration fix**, not a permissions fix. The attacker's permissions didn't change — we eliminated the vulnerability at the source.
- Lambda environment variables are **not secure storage** — they're visible to anyone with `GetFunctionConfiguration`.
- Moving secrets to Secrets Manager provides proper access control (scoped to specific secret ARNs), automatic rotation, encryption at rest, and audit logging.

---

**Next:** [Exercise 6: Resource Constraint for PutGroupPolicy](exercise-6.md) — Restrict PutGroupPolicy to authorized group ARNs
