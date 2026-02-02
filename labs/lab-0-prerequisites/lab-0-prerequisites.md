# Lab 0 - Prerequisites: Setup and Validation

**Duration:** 10 minutes

## Overview

Validate your workstation tools and deploy the vulnerable IAM infrastructure for this workshop.

---

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
pmapper --version
```

### awspx

```bash
awspx --version
```

---

## Step 2: Configure AWS Credentials

Ensure your AWS CLI is configured with credentials for your sandbox account:

```bash
aws sts get-caller-identity
```

You should see your account ID and IAM principal. These credentials need permissions to create IAM resources.

---

## Step 3: Deploy Vulnerable Infrastructure

> **IMPORTANT:** This lab deploys intentionally vulnerable IAM infrastructure to your sandbox account. Do not run this in a production account.

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

---

## Validation Complete

You're ready to proceed to **Lab 1 - Layin' Down the Law**.
