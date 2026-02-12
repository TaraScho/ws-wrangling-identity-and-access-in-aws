# Lab 0 - Prerequisites: Setup and Validation

**Duration:** 10 minutes

## Overview

Configure your AWS credentials, clone the workshop repository, and run the setup script. The script handles everything else — tool installation, infrastructure deployment, and exercise profile configuration.

> [!IMPORTANT]
> Never deploy lab resources in a production AWS account. This lab intentionally deploys vulnerable resources that create serious privilege escalation paths in your AWS account.

---

## Step 1: Configure AWS Credentials

Paste the `export` commands provided by the workshop facilitator into your terminal session:

```bash
export AWS_ACCESS_KEY_ID=AKIA...
export AWS_SECRET_ACCESS_KEY=...
export AWS_SESSION_TOKEN=...
```

Verify the credentials are working:

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

---

## Step 2: Clone the Workshop Repository

```bash
git clone https://github.com/TaraScho/ws-wrangling-identity-and-access-in-aws.git ~/workshop
cd ~/workshop
```

---

## Step 3: Run the Setup Script

```bash
bash labs/wwhf-setup.sh
```

The script will:

1. Verify prerequisites (Docker, Python 3, AWS credentials, etc.)
1. Install Terraform and pmapper
1. Create the awspx credential wrapper
1. Add tools to your PATH
1. Deploy the vulnerable lab infrastructure with Terraform
1. Configure AWS CLI profiles for all 6 exercise users

When the script finishes, you should see:

```
=== Setup Complete! (4/4 checks passed) ===

You're ready to start Lab 1. Happy hacking!
```

> [!TIP]
> The script is idempotent — if you get disconnected or hit an error, fix the issue and re-run `bash labs/wwhf-setup.sh`. It will skip steps that are already complete.

---

## Troubleshooting

If the setup script fails, check the following:

1. **AWS credentials not configured** — Re-export your `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, and `AWS_SESSION_TOKEN` environment variables. Credentials are lost when your session disconnects.

1. **Docker is not running** — The awspx tool requires Docker. Verify with `docker info`.

1. **Terraform download failed** — Check your internet connection and re-run the script.

1. **Exercise profiles missing** — This means `terraform apply` may not have completed. Re-run the script.

### Manual Validation

If you need to verify individual tools after setup:

```bash
terraform version
pmapper --help
awspx --help
aws configure list-profiles | grep iamws
```

---

## Setup complete

When the setup script reports all checks passed, you are ready to proceed to **Lab 1 - Layin' Down the Law**.
