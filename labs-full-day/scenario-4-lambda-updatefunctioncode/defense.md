# Scenario 4 — Defense bullets (afternoon)

Source: Lab 2 Exercise 4. Pairs with `attack.md` (Lambda UpdateFunctionCode hijack). Control: **resource constraint** on Lambda ARN pattern.

## Slide intro bullets

- The fix is one line: `Resource: "*"` → `Resource: "arn:aws:lambda:*:*:function:dev-*"`.
- Developer can still update dev functions; privileged functions like `iamws-privileged-lambda` are out of scope.
- Naming convention (`dev-*` vs `iamws-privileged-*`) becomes the security boundary — combine with tagging in production for richer scoping.
- iam-recon resolves the ARN pattern → the Existing PassRole edge to the privileged Lambda disappears.

## Defense — full command path

```bash
# Step 1: write the scoped policy (admin/workshop identity)
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

# Step 2: detach the overly-permissive policy
aws iam detach-user-policy \
  --user-name iamws-lambda-developer-user \
  --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/iamws-lambda-developer-policy 2>/dev/null || true

# Step 3: WAIT for AWS IAM permission cache to expire (~60s minimum).
#         Without the wait, lambda:UpdateFunctionCode against the privileged function still
#         succeeds for the attacker user even with zero policies — AWS keeps a short-lived
#         permission cache (verified empirically: full deny lands at ~3–5 min, but 60s is
#         usually enough). simulate-principal-policy correctly returns implicitDeny
#         immediately, so use AWS simulate to demo the change while waiting for the live deny.
sleep 60
```

## Verify with the attack

```bash
# Make a dummy zip
echo "def handler(e,c): pass" > /tmp/dummy_lambda.py
cd /tmp && zip -j /tmp/dummy_lambda.zip dummy_lambda.py && cd -

# Re-run the original attack against the privileged Lambda
aws lambda update-function-code \
  --function-name iamws-privileged-lambda \
  --zip-file fileb:///tmp/dummy_lambda.zip \
  --profile iamws-lambda-developer-user 2>&1 | head -3
# expect: AccessDeniedException on UpdateFunctionCode

# Crown jewels still safe?
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text \
  --profile iamws-lambda-developer-user)
aws s3 cp s3://iamws-crown-jewels-${ACCOUNT_ID}/flag.txt - \
  --profile iamws-lambda-developer-user
# expect: AccessDenied
```

## Verify with iam-recon

- `iam-recon graph create --profile taractf`.
- `iam-recon --account $ACCOUNT_ID pathfinding` → `[lambda-003]` / `[lambda-004]` finding for `iamws-lambda-developer-user` against `iamws-privileged-lambda` should disappear.
- `iam-recon --account $ACCOUNT_ID argquery --principal user/iamws-lambda-developer-user --action lambda:UpdateFunctionCode --resource 'arn:aws:lambda:*:*:function:iamws-privileged-lambda'` → should now show DENY.
- ⚠️ `argquery --preset privesc` will not show a difference here — same lambda-edge-checker short-circuit as in `attack.md`. Pathfinding is the verification surface for this scenario.
- If `dev-*` functions exist in the account, confirm pathfinding/argquery still allow updates against those (proves the policy isn't over-restrictive).

## Demo bullets

- Show before/after edge count in the iam-recon viz — concrete reduction in attack surface.
- Discuss tagging-based access control (`aws:ResourceTag/Environment`) as the next-level pattern when naming conventions aren't enough.
- Watch-out: this control only works if there's a meaningful name/tag boundary between dev and privileged resources. Mixed naming = no security.
