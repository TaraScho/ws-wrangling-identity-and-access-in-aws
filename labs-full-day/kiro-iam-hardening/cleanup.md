# Kiro IAM Hardening Lab — Cleanup

Delete all three CloudFormation stacks created during the lab.

```bash
# Empty the analytics bucket first — the BucketPolicy doesn't allow deletion
# while objects remain, and the seeder lambda only cleans up the easter-egg
# object on stack delete. If you uploaded anything extra, this catches it.
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
aws s3 rm "s3://analytics-data-${ACCOUNT_ID}" --recursive 2>/dev/null || true

# Delete the secure (hardened) stack
aws cloudformation delete-stack --stack-name IAM-Hardening-Lab-Secure

# Delete the insecure stack
aws cloudformation delete-stack --stack-name IAM-Hardening-Lab-Insecure

# Delete the bucket stack
aws cloudformation delete-stack --stack-name IAM-Hardening-Lab-Bucket

# Wait for all three to finish
aws cloudformation wait stack-delete-complete \
  --stack-name IAM-Hardening-Lab-Secure
aws cloudformation wait stack-delete-complete \
  --stack-name IAM-Hardening-Lab-Insecure
aws cloudformation wait stack-delete-complete \
  --stack-name IAM-Hardening-Lab-Bucket
```

> [!WARNING]
> If deletion fails, check for dependencies:
>
> - Instance profiles attached to running EC2 instances will block deletion of either role stack — terminate any instances using the profiles first.
> - If you attached the hardened role's instance profile to an EC2 instance for the easter-egg step, detach or terminate the instance before deleting `IAM-Hardening-Lab-Secure`.
> - The analytics bucket stack will not delete cleanly if the bucket isn't empty. Re-run the `aws s3 rm ... --recursive` above and retry.
