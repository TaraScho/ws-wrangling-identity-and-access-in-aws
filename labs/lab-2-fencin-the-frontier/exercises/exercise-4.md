## Exercise 4: Resource Constraint for UpdateFunctionCode

### Recap

In Lab 1 Exercise 6, you hijacked `iamws-privileged-lambda` by replacing its code with a credential-exfiltration payload (Existing PassRole via `lambda:UpdateFunctionCode`). The root cause: `Resource: "*"` allowed modifying any Lambda.

### Understanding Resource Constraints

The fix is simple: restrict which Lambda functions the developer can modify:

```json
{
  "Resource": "arn:aws:lambda:*:*:function:dev-*"
}
```

This allows updating only functions whose names start with `dev-`.

### Part A: Create the Restrictive Policy

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

aws iam put-user-policy \
  --user-name iamws-lambda-developer-user \
  --policy-name SecureLambdaDeveloper \
  --policy-document '{
    "Version": "2012-10-17",
    "Statement": [
      {
        "Sid": "AllowLambdaCodeUpdateDevOnly",
        "Effect": "Allow",
        "Action": [
          "lambda:UpdateFunctionCode",
          "lambda:InvokeFunction"
        ],
        "Resource": "arn:aws:lambda:*:'${ACCOUNT_ID}':function:dev-*"
      },
      {
        "Sid": "AllowLambdaReadAll",
        "Effect": "Allow",
        "Action": [
          "lambda:GetFunction",
          "lambda:ListFunctions"
        ],
        "Resource": "*"
      }
    ]
  }'
```

### Part B: Remove the Overly-Permissive Policy

```bash
aws iam detach-user-policy \
  --user-name iamws-lambda-developer-user \
  --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/iamws-lambda-developer-policy 2>/dev/null || true
```

### Part C: Verify the Remediation

```bash
# Create a dummy zip for the test (the CLI validates the zip format locally)
echo "def handler(e,c): pass" > /tmp/dummy_lambda.py
cd /tmp && zip -j /tmp/dummy_lambda.zip dummy_lambda.py

# Try to update the privileged Lambda (should fail)
echo "Testing: Can update iamws-privileged-lambda? (should fail)"
aws lambda update-function-code \
  --function-name iamws-privileged-lambda \
  --zip-file fileb:///tmp/dummy_lambda.zip \
  --profile iamws-lambda-developer-user 2>&1 | head -3
```

**Expected result:**
```
An error occurred (AccessDeniedException) when calling the UpdateFunctionCode operation:
User: arn:aws:iam::ACCOUNT_ID:user/iamws-lambda-developer-user
is not authorized to perform: lambda:UpdateFunctionCode on resource:
arn:aws:lambda:us-east-1:ACCOUNT_ID:function:iamws-privileged-lambda
```

**The attack is blocked!** The developer can only update `dev-*` functions.

**Verify the crown jewels are still protected:**

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text \
  --profile iamws-lambda-developer-user)

aws s3 cp s3://iamws-crown-jewels-${ACCOUNT_ID}/flag.txt - \
  --profile iamws-lambda-developer-user
```

**Expected:** `AccessDenied` — the Lambda developer can no longer hijack privileged functions, so the crown jewels remain safe.

### What You Learned

- **Resource constraints** are a possible guardrail for "Existing PassRole" attacks
- Use naming conventions (like `dev-*`, `prod-*`) to enable resource-based access control - tagging is also a good option for this
- Always ask: "What's the minimum set of resources this principal needs to modify?"

---

**Next:** [Exercise 5: Secrets Manager for Credential Access](exercise-5.md) — Move secrets from env vars to Secrets Manager
