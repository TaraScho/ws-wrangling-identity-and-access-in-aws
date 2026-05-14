# Kiro IAM Hardening Lab

In this lab you'll use **Kiro**, the spec-driven agentic IDE from AWS, to harden an overly permissive IAM role. You'll generate least-privilege policies using Kiro Specs, validate them with AWS MCP servers, deploy the hardened policies, and then **test them** with the IAM Policy Simulator and real AWS API calls to prove they work as intended.

## What you'll learn

- **Kiro Specs:** Writing formal requirements for IAM least-privilege before any policy JSON is generated.
- **AWS IaC MCP Server:** Validating CloudFormation templates containing IAM roles and policies.
- **AWS Documentation MCP Server:** Looking up exact IAM actions, conditions, and resource ARN formats on the fly.
- **IAM policy hardening:** Replacing wildcard (`*`) permissions with scoped actions, resources, and conditions.
- **IAM Policy Simulator:** Testing policies before and after hardening to verify they permit required access and deny everything else.
- **Condition keys:** Using `aws:SourceAccount`, `aws:PrincipalOrgID`, `aws:SecureTransport`, `aws:RequestedRegion`, and `s3:prefix` to tighten access.

## Prerequisites

| Requirement | Details |
| :---- | :---- |
| **AWS account** | A dedicated training account with AdministratorAccess (or IAM, CloudFormation, S3, and EC2 permissions) |
| **Kiro IDE** | Installed from [kiro.dev](https://kiro.dev) — free tier is sufficient |
| **AWS CLI v2** | Configured with credentials for your training account |
| **MCP servers** | AWS IaC MCP Server and AWS Documentation MCP Server enabled in Kiro |
| **Workshop repo** | Cloned at `~/workshop` (from the lab setup) so you can reference `labs-full-day/kiro-iam-hardening/assets/` |

## Lab scenario

Your team inherited an EC2-based analytics application. The instance role has the following overly permissive policy attached:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "*",
      "Resource": "*"
    }
  ]
}
```

This is the classic "Stack Overflow copy-paste" policy. Your job is to replace it with hardened, least-privilege policies that only allow what the application actually needs: reading from a specific S3 bucket, writing CloudWatch logs, and describing EC2 instances for health checks.

## Part A — Setting up Kiro and MCP servers

### Step A.1: Install and configure Kiro

1. Download and install Kiro from [kiro.dev](https://kiro.dev). Sign in with an AWS Builder ID.
1. Create a new project folder called **`iam-hardening-lab`** somewhere outside the workshop repo and open it in Kiro.
1. Open the command palette (**Ctrl+Shift+P** / **Cmd+Shift+P**) and select **MCP: Configure Servers**.
1. Add the following to `.kiro/settings/mcp.json`:

   ```json
   {
     "mcpServers": {
       "aws-iac": {
         "command": "npx",
         "args": ["-y", "@aws/aws-iac-mcp-server"]
       },
       "aws-docs": {
         "command": "npx",
         "args": ["-y", "@aws/aws-documentation-mcp-server"]
       }
     }
   }
   ```

1. Reload the Kiro window. Both servers should appear as active in the status bar.

### Step A.2: Verify connectivity

1. In the Kiro chat panel, type: `@aws-docs What IAM condition keys can I use to restrict S3 access?`
1. Confirm you receive a response listing condition keys like `s3:prefix`, `aws:SourceVpc`, etc.

> [!NOTE]
> If the MCP servers fail to connect, check the Output panel (select **MCP** from the dropdown). Common issues: missing Node.js 18+, expired AWS credentials, or a corporate proxy blocking `npx`.

## Part B — Deploying the overly permissive role

First, deploy the "bad" IAM role and the analytics S3 bucket so you can see the risk and have something real to harden against. Both templates are pre-staged in the workshop repo.

### Step B.1: Set the account variable

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "Account: $ACCOUNT_ID"
```

### Step B.2: Deploy the insecure role

```bash
aws cloudformation deploy \
  --template-file ~/workshop/labs-full-day/kiro-iam-hardening/assets/insecure-role.yaml \
  --stack-name IAM-Hardening-Lab-Insecure \
  --capabilities CAPABILITY_NAMED_IAM \
  --tags Environment=Training Lab=KiroIAMHardening
```

### Step B.3: Deploy the analytics bucket

```bash
aws cloudformation deploy \
  --template-file ~/workshop/labs-full-day/kiro-iam-hardening/assets/analytics-bucket.yaml \
  --stack-name IAM-Hardening-Lab-Bucket \
  --capabilities CAPABILITY_IAM \
  --tags Environment=Training Lab=KiroIAMHardening
```

The bucket stack creates `analytics-data-${ACCOUNT_ID}` with TLS-only access, and seeds `reports/quarterly.txt` with content you'll only be able to read if you do the hardening right. We won't open it in the main lab path — it's an end-of-day easter egg.

### Step B.4: See just how dangerous the role is

```bash
INSECURE_ROLE_ARN=$(aws cloudformation describe-stacks \
  --stack-name IAM-Hardening-Lab-Insecure \
  --query 'Stacks[0].Outputs[?OutputKey==`RoleArn`].OutputValue' \
  --output text)

aws iam simulate-principal-policy \
  --policy-source-arn "$INSECURE_ROLE_ARN" \
  --action-names \
    s3:DeleteBucket \
    ec2:TerminateInstances \
    iam:CreateUser \
    iam:DeleteRole \
  --output table
```

Every action should show **`allowed`**. This role can delete buckets, terminate instances, create IAM users, and delete roles — far beyond what an analytics app needs.

> [!WARNING]
> This is exactly the kind of role that gets exploited in cloud breaches. An attacker who compromises the EC2 instance gets unrestricted access to every AWS service in the account. SSRF attacks against the metadata service (IMDSv1) make this trivial.

## Part C — Writing the Kiro Spec for least privilege

Now use Kiro's spec-driven workflow to define what the role actually needs and generate hardened policies.

### Step C.1: Create a new spec

1. In the Kiro sidebar, click **Specs > New Spec**.
1. Title: **Least-Privilege IAM Role for Analytics EC2 Application**.
1. Enter the following prompt (substitute your account ID in the bucket name):

   ```text
   Create a hardened, least-privilege IAM role for an EC2-based analytics application.
   The application requires ONLY the following access:

   1. S3 read-only:
      - GetObject and ListBucket on a specific bucket: analytics-data-<ACCOUNT_ID>
      - ListBucket should be restricted to the prefix "reports/"
      - All S3 access must require TLS (aws:SecureTransport)

   2. CloudWatch Logs:
      - CreateLogGroup, CreateLogStream, PutLogEvents
      - Scoped to log groups starting with /app/analytics/

   3. EC2 Describe (health checks):
      - DescribeInstances, DescribeInstanceStatus
      - Restricted to the current region only using aws:RequestedRegion

   4. SSM Agent (for Session Manager, no SSH keys):
      - ssm:UpdateInstanceInformation, ssmmessages:*, ec2messages:*

   Security requirements:
   - NO wildcard (*) actions or resources anywhere
   - Use separate policy statements for each service
   - Include condition keys wherever possible
   - AssumeRole trust must be restricted to ec2.amazonaws.com only
   - Add a permissions boundary that denies IAM and Organizations actions
   - Tag all resources with Environment=Training and Lab=KiroIAMHardening
   - Output as CloudFormation YAML
   ```

1. Click **Generate Spec** and wait for Kiro to process the three phases.

### Step C.2: Review the requirements phase

Kiro should produce requirements like these. Verify each one:

| ID | Requirement |
| :---- | :---- |
| **REQ-001** | S3 GetObject scoped to `analytics-data-<ACCOUNT_ID>` bucket ARN with objects key |
| **REQ-002** | S3 ListBucket scoped to the same bucket with `s3:prefix` condition for `reports/` |
| **REQ-003** | All S3 actions require `aws:SecureTransport = true` |
| **REQ-004** | CloudWatch Logs actions scoped to log groups matching `/app/analytics/*` |
| **REQ-005** | EC2 Describe actions restricted by `aws:RequestedRegion` condition |
| **REQ-006** | SSM Agent permissions for Session Manager connectivity |
| **REQ-007** | Permissions boundary denying `iam:*` and `organizations:*` actions |
| **REQ-008** | No wildcard actions or resources in any statement |
| **REQ-009** | All resources tagged with `Environment` and `Lab` keys |

> [!NOTE]
> If Kiro missed the permissions boundary or the `s3:prefix` condition, add them manually. The spec is your contract — anything not in the spec may not end up in the generated code.

### Step C.3: Review design and tasks, then generate

1. Review the **Design phase** — confirm Kiro plans to create separate policy statements per service, a permissions boundary as a managed policy, and an instance profile.
1. Review the **Tasks phase** — confirm the implementation order makes sense (permissions boundary first, then the role, then the instance profile).
1. Click **Approve & Generate**.

## Part D — Validating the generated policies

Kiro has generated a CloudFormation template (likely named `iam-hardened-role.yaml` or similar). Before deploying, validate it thoroughly.

### Step D.1: Manual review checklist

Open the generated template and check every `Statement` block against this checklist:

| Check | Expected | Red flag |
| :---- | :---- | :---- |
| **No wildcard actions** | Each `Action` lists specific API calls | `Action: '*'` or `Action: 's3:*'` |
| **No wildcard resources** | `Resource` uses full ARN with account ID | `Resource: '*'` |
| **S3 prefix condition** | `s3:prefix` condition on `ListBucket` | `ListBucket` without condition |
| **TLS enforcement** | `aws:SecureTransport: 'true'` on S3 | S3 access without transport check |
| **Region restriction** | `aws:RequestedRegion` on EC2 calls | EC2 describe without region lock |
| **Permissions boundary** | Separate managed policy with `Deny` on `iam:*` | No boundary attached |
| **Tags on all resources** | `Environment` + `Lab` on role, boundary, and profile | Untagged resources |

### Step D.2: Validate with the IaC MCP server

1. In the Kiro chat, run:

   ```text
   @aws-iac Validate this CloudFormation template for IAM security.
   Check for: wildcard permissions, missing conditions, overly broad
   resource ARNs, missing permissions boundaries, and missing tags.
   ```

1. Review each finding. Common issues the MCP server may flag:

   - S3 `GetObject` Resource should include `/*` after the bucket ARN for object-level access.
   - CloudWatch Logs resource ARN should use `:log-group:/app/analytics/*:*` format.
   - Permissions boundary should also deny `sts:AssumeRole` to external accounts.

1. Ask Kiro to fix any issues:

   ```text
   Fix the issues identified by validation. For each fix, explain which
   requirement (REQ-001 through REQ-009) it addresses.
   ```

1. Re-validate until no findings remain.

> [!WARNING]
> A clean validation does not mean the policy is perfect — it means it passes automated checks. The Policy Simulator in Part E is your real test. Always test with actual API simulations.

> [!NOTE]
> If after several iterations Kiro's output still won't deploy or won't pass the checklist, ask your instructor for the out-of-band reference template. Don't go hunting for it in the repo — keeping it out of Kiro's project context is the point.

## Part E — Deploying and testing the hardened role

### Step E.1: Deploy the hardened stack

1. Deploy the validated template:

   ```bash
   aws cloudformation deploy \
     --template-file iam-hardened-role.yaml \
     --stack-name IAM-Hardening-Lab-Secure \
     --capabilities CAPABILITY_NAMED_IAM \
     --tags Environment=Training Lab=KiroIAMHardening
   ```

1. Wait for **`CREATE_COMPLETE`** and capture the role ARN:

   ```bash
   SECURE_ROLE_ARN=$(aws cloudformation describe-stacks \
     --stack-name IAM-Hardening-Lab-Secure \
     --query 'Stacks[0].Outputs[?OutputKey==`RoleArn`].OutputValue' \
     --output text)
   echo "Hardened Role ARN: $SECURE_ROLE_ARN"
   ```

### Step E.2: Test allowed actions

Use the IAM Policy Simulator to confirm the role **can** do what the application needs:

```bash
aws iam simulate-principal-policy \
  --policy-source-arn "$SECURE_ROLE_ARN" \
  --action-names \
    s3:GetObject \
    s3:ListBucket \
    logs:CreateLogGroup \
    logs:CreateLogStream \
    logs:PutLogEvents \
    ec2:DescribeInstances \
    ec2:DescribeInstanceStatus \
    ssm:UpdateInstanceInformation \
  --output table
```

Verify every action returns **`allowed`**. If any return `implicitDeny`, your policy is too restrictive — go back to the template and check the `Resource` ARN and conditions.

### Step E.3: Test denied actions

Now confirm the role **cannot** do things outside its scope:

```bash
aws iam simulate-principal-policy \
  --policy-source-arn "$SECURE_ROLE_ARN" \
  --action-names \
    s3:DeleteBucket \
    s3:PutObject \
    ec2:TerminateInstances \
    ec2:RunInstances \
    iam:CreateUser \
    iam:CreateRole \
    iam:DeleteRole \
    lambda:InvokeFunction \
    organizations:ListAccounts \
  --output table
```

Every action above should return **`implicitDeny`** or **`explicitDeny`**. If any return `allowed`, you have a gap in your policy.

> [!NOTE]
> The `iam:*` and `organizations:*` actions should be explicitly denied by the permissions boundary, not just implicitly denied. The simulator will show `explicitDeny` for these — that's even better.

### Step E.4: Compare insecure vs. secure side-by-side

Run the dangerous actions against the **insecure** role to see the contrast:

```bash
echo "=== INSECURE ROLE ==="
aws iam simulate-principal-policy \
  --policy-source-arn "$INSECURE_ROLE_ARN" \
  --action-names s3:DeleteBucket iam:CreateUser ec2:TerminateInstances \
  --output table

echo "=== SECURE ROLE ==="
aws iam simulate-principal-policy \
  --policy-source-arn "$SECURE_ROLE_ARN" \
  --action-names s3:DeleteBucket iam:CreateUser ec2:TerminateInstances \
  --output table
```

The insecure role allows all three actions. The secure role denies them. This is the tangible result of the hardening work.

> [!NOTE]
> **Easter egg — afternoon flex time only.** The `analytics-data-${ACCOUNT_ID}` bucket has a `reports/quarterly.txt` object seeded with something fun. If your hardened role really does what the spec asked, you should be able to attach the instance profile to a quick EC2 instance (or use `sts:AssumeRole` after granting yourself trust permission) and `aws s3 cp s3://analytics-data-${ACCOUNT_ID}/reports/quarterly.txt -`. We're not walking you through it; figure out the path yourself.

## Part F — Discussion & review

Reflect on the lab and discuss the following with your group or instructor.

### Discussion questions

- **Wildcard vs. least privilege:** How often do you encounter `Action: *` or `Resource: *` in your organization's IAM policies? What are the barriers to fixing them?
- **Spec rigor:** Did the Kiro Spec catch requirements you would have missed with a free-form prompt? Did it miss any? How does formalizing requirements change the quality of generated IAM policies?
- **MCP validation vs. manual review:** What did the IaC MCP Server flag that you didn't catch in your manual review? Would you trust it as a gate in CI/CD?
- **Policy Simulator:** How does `simulate-principal-policy` compare to actually testing with real API calls? What are its limitations?
- **Permissions boundaries:** How would you use permissions boundaries across an organization? Could you enforce them via SCPs or CloudFormation StackSets?
- **Continuous compliance:** How would you detect if someone re-attaches a wildcard policy after you've hardened the role? Think about AWS Config rules, IAM Access Analyzer, and Kiro automation hooks.

### What you learned

- An `Action: *` / `Resource: *` policy is the most dangerous configuration in AWS IAM. Treat it as a critical finding.
- Kiro's spec-driven workflow forces you to enumerate exactly what access is needed before writing policy JSON — this is the discipline that prevents over-permissioning.
- The IAM Policy Simulator is your best friend for testing policies without deploying infrastructure. Use it to test both allowed and denied actions.
- Permissions boundaries provide a safety net: even if someone attaches a broad policy, the boundary limits what the role can actually do.
- AWS MCP servers catch common IAM mistakes automatically, but human review and simulation testing remain essential.

## Cleanup

See [`cleanup.md`](cleanup.md) — three CloudFormation stacks to delete.

## Resources

- [Kiro IDE](https://kiro.dev/) — download and documentation
- [AWS MCP servers (GitHub)](https://github.com/awslabs/mcp) — official AWS MCP server repository
- [AWS IaC MCP Server](https://awslabs.github.io/mcp/servers/aws-iac-mcp-server) — CloudFormation and CDK validation
- [IAM Policy Simulator](https://docs.aws.amazon.com/IAM/latest/UserGuide/access_policies_testing-policies.html) — AWS documentation
- [IAM best practices](https://docs.aws.amazon.com/IAM/latest/UserGuide/best-practices.html) — AWS official IAM security guide
- [Kiro enterprise governance](https://kiro.dev/blog/enterprise-governance-mcp-and-models/) — admin controls for MCP and model governance
- [IAM Access Analyzer](https://docs.aws.amazon.com/IAM/latest/UserGuide/what-is-access-analyzer.html) — automated policy analysis
