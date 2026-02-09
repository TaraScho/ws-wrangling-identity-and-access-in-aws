# Lab 0 - Prerequisites: Setup and Validation

**Duration:** 10 minutes

## Overview

Validate your workstation tools and deploy the vulnerable IAM infrastructure for this workshop.

---

## Requirements

This workshop requires the following tools. If needed, follow the instructions at the links below to install the tools. Then, you will run the commands below to validate the tools are available and ready to use.

* [AWS Command Line Interface (CLI)](https://aws.amazon.com/cli/)
* [Terraform](https://developer.hashicorp.com/terraform/tutorials/aws-get-started/install-cli)
* [Docker](https://docs.docker.com/engine/install/)
* [pmapper (Principal Mapper)](https://github.com/nccgroup/PMapper)
* [awspx](https://github.com/ReversecLabs/awspx)
* A sandbox AWS account to deploy lab resources

> **🚨 IMPORTANT**
> Never deploy lab resources in a production AWS account. This lab intentionally deploys vulnerable resources that create serious privilege escalation paths in your AWS account.

## Step 1: Validate Tool Installation

Run the following commands to confirm your tools are installed:

### AWS CLI

```bash
aws --version
```

### Terraform

```bash
terraform --version
```

### pmapper (Principal Mapper)

```bash
pmapper -h
```

### awspx (requires Docker to be running)

```bash
awspx
```

---

## Step 2: Configure AWS Authentication

The workshop requires a sandbox AWS account. If you are already comfortable with the AWS CLI you can use your preferred method of [configuring your terminal environment with authentication and access credentials](https://docs.aws.amazon.com/cli/v1/userguide/cli-chap-authentication.html).

> **NOTE**
> We do not recommend logging in with the `aws login` command as this can cause downstream issues with Pmapper.

> **NOTE**
> You must be authenticated with an IAM role or user that has the following permissions:
>
> TODO

Ensure your AWS CLI is configured with credentials for your sandbox account:

```bash
aws sts get-caller-identity
```

Expected output looks similar to the following:

```
{
    "UserId": "<Your user id>",
    "Account": "<your account id>",
    "Arn": "<your identity arn>"
}
```

When you have successfully authenticated with AWS, you are ready to move on!

---

## Step 3: Deploy Vulnerable Infrastructure

> **🚨Extra serious final warning🚨:** This lab deploys intentionally vulnerable IAM infrastructure to your sandbox account. Do not run this in a production account. Seriously. It deploys bad things.

1. Navigate to the terraform directory:
   ```bash
   cd labs/terraform
   ```

2. Initialize and apply Terraform:
   ```bash
   terraform init
   terraform apply
   ```

3. When prompted, type `yes` to confirm the resources to be created in AWS.

Sample output (partial):

```
time_sleep.iam_propagation: Creation complete after 15s [id=2026-02-07T03:21:38Z]
module.cloudformation.aws_cloudformation_stack.iamws-demo-stack: Creating...
module.cloudformation.aws_cloudformation_stack.iamws-demo-stack: Still creating... [00m10s elapsed]
module.cloudformation.aws_cloudformation_stack.iamws-demo-stack: Creation complete after 10s [id=arn:aws:cloudformation:us-east-1:115753408004:stack/iamws-demo-stack/1d834bd0-03d4-11f1-b327-0affcddb0efb]

Apply complete! Resources: 87 added, 0 changed, 0 destroyed.
```

---

## Validation and lab deployment complete

When you have successfully installed the tools and deployed the lab infrastructure you are ready to proceed to **Lab 1 - Layin' Down the Law**.

cd ~
git clone https://github.com/TaraScho/ws-wrangling-identity-and-access-in-aws.git
cd ws-wrangling-identity-and-access-in-aws/labs
chmod +x wwhf-setup.sh
./wwhf-setup.sh