

# **Lab Overview**

In this lab you will use **Kiro**, the spec-driven agentic IDE from AWS, to harden an overly permissive IAM role, generate least-privilege policies using Kiro Specs, validate them with AWS MCP servers, deploy the hardened policies, and then **test them** using the IAM Policy Simulator and real AWS API calls to prove they work as intended.

## **What You Will Learn**

* **Kiro Specs:** Writing formal requirements for IAM least-privilege before any policy JSON is generated

* **AWS IaC MCP Server:** Validating CloudFormation templates containing IAM roles and policies

* **AWS Documentation MCP Server:** Looking up exact IAM actions, conditions, and resource ARN formats on the fly

* **IAM Policy Hardening:** Replacing wildcard (\*) permissions with scoped actions, resources, and conditions

* **IAM Policy Simulator:** Testing policies before and after hardening to verify they permit required access and deny everything else

* **Condition Keys:** Using aws:SourceAccount, aws:PrincipalOrgID, and s3:prefix conditions to tighten access

## **Prerequisites**

| Requirement | Details |
| :---- | :---- |
| **AWS Account** | A dedicated training account with AdministratorAccess (or IAM, CloudFormation, S3, and EC2 permissions) |
| **Kiro IDE** | Installed from kiro.dev — free tier is sufficient |
| **AWS CLI v2** | Configured with credentials for your training account |
| **MCP Servers** | AWS IaC MCP Server and AWS Documentation MCP Server enabled in Kiro |
| **Prior Lab** | Completion of the “Deploying a Service” lesson is recommended but not required |

 

## 

## 

## 

## **Lab Scenario**

Your team inherited an EC2-based analytics application. The instance role has the following overly permissive policy attached:

{  
  "Version": "2012-10-17",  
  "Statement": \[  
    {  
      "Effect": "Allow",  
      "Action": "\*",  
      "Resource": "\*"  
    }  
  \]  
}  
 

This is the classic “Stack Overflow copy-paste” policy. Your job is to replace it with hardened, least-privilege policies that only allow what the application actually needs: reading from a specific S3 bucket, writing CloudWatch logs, and describing EC2 instances for health checks.

# **Part 1 — Setting Up Kiro and MCP Servers**

## **Step 1.1: Install and Configure Kiro**

1. Download and install Kiro from [kiro.dev](https://kiro.dev/). Sign in with an AWS Builder ID.

2. Create a new project folder called **iam-hardening-lab** and open it in Kiro.

3. Open the command palette (**Ctrl+Shift+P** / **Cmd+Shift+P**) and select **MCP: Configure Servers**.

4. Add the following to **.kiro/settings/mcp.json**:

{  
  "mcpServers": {  
    "aws-iac": {  
      "command": "npx",  
      "args": \["-y", "@aws/aws-iac-mcp-server"\]  
    },  
    "aws-docs": {  
      "command": "npx",  
      "args": \["-y", "@aws/aws-documentation-mcp-server"\]  
    }  
  }  
}  
 

5. Reload the Kiro window. Both servers should appear as active in the status bar.

## **Step 1.2: Verify Connectivity**

1. In the Kiro chat panel, type: **@aws-docs What IAM condition keys can I use to restrict S3 access?**

2. Confirm you receive a response listing condition keys like s3:prefix, aws:SourceVpc, etc.

| Tip If the MCP servers fail to connect, check the Output panel (select "MCP" from the dropdown). Common issues: missing Node.js 18+, expired AWS credentials, or corporate proxy blocking npx. |
| :---- |

 

# **Part 2 — Deploy the Overly Permissive Role**

First, create the “bad” IAM role so you can test it, see the risks, and then harden it.

## **Step 2.1: Create the Insecure CloudFormation Template**

1. In your project, create a file called **insecure-role.yaml** with the following content:

AWSTemplateFormatVersion: '2010-09-09'  
Description: Overly permissive EC2 instance role (DO NOT use in production)  
   
Resources:  
  AnalyticsInstanceRole:  
    Type: AWS::IAM::Role  
    Properties:  
      RoleName: AnalyticsAppRole-Insecure  
      AssumeRolePolicyDocument:  
        Version: '2012-10-17'  
        Statement:  
          \- Effect: Allow  
            Principal:  
              Service: ec2.amazonaws.com  
            Action: sts:AssumeRole  
      Policies:  
        \- PolicyName: OverlyPermissivePolicy  
          PolicyDocument:  
            Version: '2012-10-17'  
            Statement:  
              \- Effect: Allow  
                Action: '\*'  
                Resource: '\*'  
      Tags:  
        \- Key: Environment  
          Value: Training  
        \- Key: Lab  
          Value: IAMHardening  
   
  AnalyticsInstanceProfile:  
    Type: AWS::IAM::InstanceProfile  
    Properties:  
      InstanceProfileName: AnalyticsAppProfile-Insecure  
      Roles:  
        \- \!Ref AnalyticsInstanceRole  
   
Outputs:  
  RoleArn:  
    Value: \!GetAtt AnalyticsInstanceRole.Arn  
  RoleName:  
    Value: \!Ref AnalyticsInstanceRole  
 

## **Step 2.2: Deploy and Observe**

1. Deploy the stack:

aws cloudformation deploy \\  
  \--template-file insecure-role.yaml \\  
  \--stack-name IAM-Hardening-Lab-Insecure \\  
  \--capabilities CAPABILITY\_NAMED\_IAM \\  
  \--tags Environment=Training Lab=IAMHardening  
 

2. Now use the IAM Policy Simulator to see just how dangerous this role is:

\# Simulate: can this role delete an S3 bucket?  
aws iam simulate-principal-policy \\  
  \--policy-source-arn $(aws cloudformation describe-stacks \\  
    \--stack-name IAM-Hardening-Lab-Insecure \\  
    \--query 'Stacks\[0\].Outputs\[?OutputKey==\`RoleArn\`\].OutputValue' \\  
    \--output text) \\  
  \--action-names s3:DeleteBucket ec2:TerminateInstances \\  
    iam:CreateUser iam:DeleteRole \\  
  \--output table  
 

3. Review the output. Every single action should show **allowed**. This role can delete buckets, terminate instances, create IAM users, and delete roles — far beyond what an analytics app needs.

| Warning This is exactly the kind of role that gets exploited in cloud breaches. An attacker who compromises the EC2 instance gets unrestricted access to every AWS service in the account. SSRF attacks against the metadata service (IMDSv1) make this trivial. |
| :---- |

 

# **Part 3 — Writing the Kiro Spec for Least Privilege**

Now use Kiro’s spec-driven workflow to define what the role actually needs and generate hardened policies.

## **Step 3.1: Create a New Spec**

1. In the Kiro sidebar, click **Specs \> New Spec**.

2. Title: **Least-Privilege IAM Role for Analytics EC2 Application**

3. Enter the following prompt:

Create a hardened, least-privilege IAM role for an EC2-based analytics application.  
The application requires ONLY the following access:  
   
1\. S3 Read-Only:  
   \- GetObject and ListBucket on a specific bucket: analytics-data-\<ACCOUNT\_ID\>  
   \- ListBucket should be restricted to the prefix "reports/"  
   \- All S3 access must require TLS (aws:SecureTransport)  
   
2\. CloudWatch Logs:  
   \- CreateLogGroup, CreateLogStream, PutLogEvents  
   \- Scoped to log groups starting with /app/analytics/  
   
3\. EC2 Describe (health checks):  
   \- DescribeInstances, DescribeInstanceStatus  
   \- Restricted to the current region only using aws:RequestedRegion  
   
4\. SSM Agent (for session manager, no SSH keys):  
   \- ssm:UpdateInstanceInformation, ssmmessages:\*, ec2messages:\*  
   
Security requirements:  
\- NO wildcard (\*) actions or resources anywhere  
\- Use separate policy statements for each service  
\- Include condition keys wherever possible  
\- AssumeRole trust must be restricted to ec2.amazonaws.com only  
\- Add a permissions boundary that denies IAM and Organizations actions  
\- Tag all resources with Environment=Training and Lab=IAMHardening  
\- Output as CloudFormation YAML  
 

4. Click **Generate Spec** and wait for Kiro to process the three phases.

## **Step 3.2: Review the Requirements Phase**

Kiro should produce requirements like these. Verify each one:

| ID | Requirement |
| :---- | :---- |
| **REQ-001** | S3 GetObject scoped to analytics-data-\<ACCOUNT\_ID\> bucket ARN with objects key |
| **REQ-002** | S3 ListBucket scoped to the same bucket with s3:prefix condition for reports/ |
| **REQ-003** | All S3 actions require aws:SecureTransport \= true |
| **REQ-004** | CloudWatch Logs actions scoped to log groups matching /app/analytics/\* |
| **REQ-005** | EC2 Describe actions restricted by aws:RequestedRegion condition |
| **REQ-006** | SSM Agent permissions for Session Manager connectivity |
| **REQ-007** | Permissions boundary denying iam:\* and organizations:\* actions |
| **REQ-008** | No wildcard actions or resources in any statement |
| **REQ-009** | All resources tagged with Environment and Lab keys |

 

| Tip If Kiro missed the permissions boundary or the s3:prefix condition, add them manually. The spec is your contract — anything not in the spec may not end up in the generated code. |
| :---- |

 

## **Step 3.3: Review Design and Tasks, then Generate**

1. Review the **Design phase** — confirm Kiro plans to create separate policy statements per service, a permissions boundary as a managed policy, and an instance profile.

2. Review the **Tasks phase** — confirm the implementation order makes sense (permissions boundary first, then the role, then the instance profile).

3. Click **Approve & Generate**.

# **Part 4 — Validating the Generated Policies**

Kiro has generated a CloudFormation template (likely named **iam-hardened-role.yaml** or similar). Before deploying, validate it thoroughly.

## **Step 4.1: Manual Review Checklist**

1. Open the generated template and check every Statement block against this checklist:

| Check | Expected | Red Flag |
| :---- | :---- | :---- |
| **No wildcard actions** | Each Action lists specific API calls | Action: '\*' or Action: 's3:\*' |
| **No wildcard resources** | Resource uses full ARN with account ID | Resource: '\*' |
| **S3 prefix condition** | s3:prefix condition on ListBucket | ListBucket without condition |
| **TLS enforcement** | aws:SecureTransport: 'true' on S3 | S3 access without transport check |
| **Region restriction** | aws:RequestedRegion on EC2 calls | EC2 describe without region lock |
| **Permissions boundary** | Separate managed policy with Deny on iam:\* | No boundary attached |
| **Tags on all resources** | Environment \+ Lab on role, boundary, and profile | Untagged resources |

 

## **Step 4.2: Validate with the IaC MCP Server**

1. In the Kiro chat, run:

@aws-iac Validate this CloudFormation template for IAM security.  
Check for: wildcard permissions, missing conditions, overly broad  
resource ARNs, missing permissions boundaries, and missing tags.  
 

2. Review each finding. Common issues the MCP server may flag:

* S3 GetObject Resource should include /\* after the bucket ARN for object-level access

* CloudWatch Logs resource ARN should use :log-group:/app/analytics/\*:\* format

* Permissions boundary should also deny sts:AssumeRole to external accounts

3. Ask Kiro to fix any issues:

Fix the issues identified by validation. For each fix, explain which  
requirement (REQ-001 through REQ-009) it addresses.  
 

4. Re-validate until no findings remain.

| Warning A clean validation does not mean the policy is perfect — it means it passes automated checks. The Policy Simulator in Part 5 is your real test. Always test with actual API simulations. |
| :---- |

 

# **Part 5 — Deploying and Testing the Hardened Role**

## **Step 5.1: Deploy the Hardened Stack**

1. Deploy the validated template:

aws cloudformation deploy \\  
  \--template-file iam-hardened-role.yaml \\  
  \--stack-name IAM-Hardening-Lab-Secure \\  
  \--capabilities CAPABILITY\_NAMED\_IAM \\  
  \--tags Environment=Training Lab=IAMHardening  
 

2. Wait for **CREATE\_COMPLETE** and capture the role ARN:

SECURE\_ROLE\_ARN=$(aws cloudformation describe-stacks \\  
  \--stack-name IAM-Hardening-Lab-Secure \\  
  \--query 'Stacks\[0\].Outputs\[?OutputKey==\`RoleArn\`\].OutputValue' \\  
  \--output text)  
echo "Hardened Role ARN: $SECURE\_ROLE\_ARN"  
 

## **Step 5.2: Test Allowed Actions**

Use the IAM Policy Simulator to confirm the role **can** do what the application needs:

\# These should all return "allowed"  
aws iam simulate-principal-policy \\  
  \--policy-source-arn $SECURE\_ROLE\_ARN \\  
  \--action-names \\  
    s3:GetObject \\  
    s3:ListBucket \\  
    logs:CreateLogGroup \\  
    logs:CreateLogStream \\  
    logs:PutLogEvents \\  
    ec2:DescribeInstances \\  
    ec2:DescribeInstanceStatus \\  
    ssm:UpdateInstanceInformation \\  
  \--output table  
 

Verify every action returns **allowed**. If any return “implicitDeny”, your policy is too restrictive — go back to the template and check the Resource ARN and conditions.

## **Step 5.3: Test Denied Actions**

Now confirm the role **cannot** do things outside its scope:

\# These should all return "implicitDeny"  
aws iam simulate-principal-policy \\  
  \--policy-source-arn $SECURE\_ROLE\_ARN \\  
  \--action-names \\  
    s3:DeleteBucket \\  
    s3:PutObject \\  
    ec2:TerminateInstances \\  
    ec2:RunInstances \\  
    iam:CreateUser \\  
    iam:CreateRole \\  
    iam:DeleteRole \\  
    lambda:InvokeFunction \\  
    organizations:ListAccounts \\  
  \--output table  
 

Every single action above should return **implicitDeny**. If any return “allowed”, you have a gap in your policy.

| Tip The iam:\* and organizations:\* actions should be explicitly denied by the permissions boundary, not just implicitly denied. The simulator will show "explicitDeny" for these — that’s even better. |
| :---- |

 

## **Step 5.4: Compare Insecure vs. Secure**

Run the dangerous actions against the **insecure** role to see the contrast side-by-side:

INSECURE\_ROLE\_ARN=$(aws cloudformation describe-stacks \\  
  \--stack-name IAM-Hardening-Lab-Insecure \\  
  \--query 'Stacks\[0\].Outputs\[?OutputKey==\`RoleArn\`\].OutputValue' \\  
  \--output text)  
   
echo "=== INSECURE ROLE \==="  
aws iam simulate-principal-policy \\  
  \--policy-source-arn $INSECURE\_ROLE\_ARN \\  
  \--action-names s3:DeleteBucket iam:CreateUser ec2:TerminateInstances \\  
  \--output table  
   
echo "=== SECURE ROLE \==="  
aws iam simulate-principal-policy \\  
  \--policy-source-arn $SECURE\_ROLE\_ARN \\  
  \--action-names s3:DeleteBucket iam:CreateUser ec2:TerminateInstances \\  
  \--output table  
 

The insecure role allows all three actions. The secure role denies them. This is the tangible result of the hardening work.

# **Part 6 — Cleanup**

Delete both stacks to remove all IAM resources from your training account.

\# Delete the secure stack  
aws cloudformation delete-stack \--stack-name IAM-Hardening-Lab-Secure  
   
\# Delete the insecure stack  
aws cloudformation delete-stack \--stack-name IAM-Hardening-Lab-Insecure  
   
\# Wait for both  
aws cloudformation wait stack-delete-complete \\  
  \--stack-name IAM-Hardening-Lab-Secure  
aws cloudformation wait stack-delete-complete \\  
  \--stack-name IAM-Hardening-Lab-Insecure  
 

| Warning If deletion fails, check for dependencies. Instance profiles attached to running EC2 instances will block deletion. Terminate any instances using the profiles first. |
| :---- |

 

# **Part 7 — Discussion & Review**

Reflect on the lab and discuss the following with your group or instructor.

## **Discussion Questions**

* **Wildcard vs. Least Privilege:** How often do you encounter Action: \* or Resource: \* in your organization’s IAM policies? What are the barriers to fixing them?

* **Spec Rigor:** Did the Kiro Spec catch requirements you would have missed with a free-form prompt? Did it miss any? How does formalizing requirements change the quality of generated IAM policies?

* **MCP Validation vs. Manual Review:** What did the IaC MCP Server flag that you didn’t catch in your manual review? Would you trust it as a gate in CI/CD?

* **Policy Simulator:** How does simulate-principal-policy compare to actually testing with real API calls? What are its limitations?

* **Permissions Boundaries:** How would you use permissions boundaries across an organization? Could you enforce them via SCPs or CloudFormation StackSets?

* **Continuous Compliance:** How would you detect if someone re-attaches a wildcard policy after you’ve hardened the role? Think about AWS Config rules, IAM Access Analyzer, and Kiro automation hooks.

## **Key Takeaways**

* An Action: \* / Resource: \* policy is the most dangerous configuration in AWS IAM. It should be treated as a critical finding.

* Kiro’s spec-driven workflow forces you to enumerate exactly what access is needed before writing policy JSON — this is the discipline that prevents over-permissioning.

* The IAM Policy Simulator is your best friend for testing policies without deploying infrastructure. Use it to test both allowed and denied actions.

* Permissions boundaries provide a safety net: even if someone attaches a broad policy, the boundary limits what the role can actually do.

* AWS MCP servers catch common IAM mistakes automatically, but human review and simulation testing remain essential.

## **Resources**

[Kiro IDE](https://kiro.dev/) — Download and documentation

[AWS MCP Servers (GitHub)](https://github.com/awslabs/mcp) — Official AWS MCP server repository

[AWS IaC MCP Server](https://awslabs.github.io/mcp/servers/aws-iac-mcp-server) — CloudFormation and CDK validation

[IAM Policy Simulator](https://docs.aws.amazon.com/IAM/latest/UserGuide/access_policies_testing-policies.html) — AWS documentation

[IAM Best Practices](https://docs.aws.amazon.com/IAM/latest/UserGuide/best-practices.html) — AWS official IAM security guide

[Kiro Enterprise Governance](https://kiro.dev/blog/enterprise-governance-mcp-and-models/) — Admin controls for MCP and model governance

[IAM Access Analyzer](https://docs.aws.amazon.com/IAM/latest/UserGuide/what-is-access-analyzer.html) — Automated policy analysis