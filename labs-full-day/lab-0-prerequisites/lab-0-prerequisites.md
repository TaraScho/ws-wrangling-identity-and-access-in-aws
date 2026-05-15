# Lab 0 - Prerequisites: Self-Service Setup

This guide walks you through setting up the full-day workshop environment on your own Mac or Linux machine. After completing these steps, you'll pick up at the **Privilege Escalation Categories** section of Lab 1.

> [!IMPORTANT]
> **Never deploy lab resources in a production AWS account.** This workshop intentionally deploys vulnerable IAM resources that create serious privilege escalation paths. Use a dedicated sandbox or test account.

> [!NOTE]
> **Facilitated workshop participants:** Skip this guide entirely. Follow [Lab 1 — Lab Setup](../lab-1-setup/README.md), which uses `bsides-setup.sh` to install everything for you. A pre-built workshop VM image is also available — see the Lab 1 README for details.

> [!NOTE]
> **Windows is not supported on the own-laptop path** — `iam-recon` does not ship a Windows binary. Use the pre-built workshop VM image (VirtualBox variant runs on Windows) referenced in Lab 1.

---

## Prerequisites Checklist

Before you begin, make sure you have the following:

1. **AWS account** that is strictly a sandbox (never production, never an account you care about), with an IAM identity that has `ReadOnlyAccess` plus permissions to create: IAM users, roles, policies, and access keys; Lambda functions; EC2 instances and security groups; S3 buckets; CloudFormation stacks; and Secrets Manager secrets. `AdministratorAccess` in a sandbox account also works.
1. **Git** installed.
1. **Python 3** installed (used by the lab Lambda functions during packaging).
1. **Base Unix tools:** `curl`, `jq`, `unzip`, `zip`. Install any missing ones via your package manager (`brew` on macOS, `apt`/`yum` on Linux).

---

## Tool Installation

### 1. AWS CLI v2

The AWS CLI v2 is required for every lab — `terraform apply`, profile management, exploitation steps, and the Lab 5 Policy Simulator calls all use it.

Install it for your platform using the [official AWS install guide](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html).

**Verify:**

```bash
aws --version
```

You should see `aws-cli/2.x` in the output (v1 will not work for some workshop steps).

**Configure credentials** for your sandbox account. The [AWS CLI authentication docs](https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-authentication.html) cover every supported method (IAM Identity Center, long-lived access keys, AssumeRole). The simplest path is exporting credentials in your terminal:

```bash
export AWS_ACCESS_KEY_ID=AKIA...
export AWS_SECRET_ACCESS_KEY=...
export AWS_SESSION_TOKEN=...   # only if you're using temporary credentials
export AWS_DEFAULT_REGION=us-east-1
```

**Verify:**

```bash
aws sts get-caller-identity
```

The returned `Arn` should match the IAM identity in your sandbox account.

---

### 2. Terraform

Terraform provisions the vulnerable lab infrastructure.

Install Terraform 1.14.x for your platform using the [official install guide](https://developer.hashicorp.com/terraform/install). The workshop setup script pins 1.14.4 — any 1.14.x release is fine.

**Verify:**

```bash
terraform version
```

> [!TIP]
> [OpenTofu](https://opentofu.org/) (`tofu`) is a drop-in fork of Terraform — same CLI, same state format. The full-day workshop's Terraform works against either. If you already have `tofu` installed, substitute it for `terraform` in every command below.

---

### 3. iam-recon

`iam-recon` is a single-binary Rust tool that builds an offline graph of every IAM user, role, group, and policy in an AWS account, then maps the resulting privileges to the 66+ known attack paths catalogued by [pathfinding.cloud](https://pathfinding.cloud). It is the only recon tool used in the full-day workshop and replaces the older Python tools (pmapper, awspx) used in the 2-hour version.

**Option A — Homebrew (macOS or Linux with Homebrew):**

```bash
brew tap andrewkrug/iam-recon https://github.com/andrewkrug/iam-recon
brew install andrewkrug/iam-recon/iam-recon
```

**Option B — Debian/Ubuntu package:**

```bash
# Replace amd64 with arm64 if you're on an ARM machine
curl -fsSL -o /tmp/iam-recon.deb \
  https://github.com/andrewkrug/iam-recon/releases/latest/download/iam-recon_amd64.deb
sudo dpkg -i /tmp/iam-recon.deb
```

**Option C — Raw release binary (any Mac or Linux):**

```bash
# Pick the asset matching your OS/arch:
#   iam-recon-linux-x86_64    iam-recon-linux-aarch64
#   iam-recon-macos-x86_64    iam-recon-macos-aarch64
mkdir -p ~/.local/bin
curl -fsSL -o ~/.local/bin/iam-recon \
  https://github.com/andrewkrug/iam-recon/releases/latest/download/iam-recon-macos-aarch64
chmod +x ~/.local/bin/iam-recon
export PATH="$HOME/.local/bin:$PATH"   # add to your shell rc to persist
```

**Verify:**

```bash
iam-recon --help
```

---

### 4. SSM Session Manager Plugin

The SSM Session Manager Plugin is required for Lab 6 (PassRole + EC2) — you'll connect to the EC2 instance you launch during the exploit without needing SSH keys.

Install it for your platform using the [official AWS install guide](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html).

**Verify:**

```bash
session-manager-plugin --version
```

---

### 5. Kiro IDE (required for Lab 5)

Lab 5 (Hardening IAM Policies with Kiro + MCP) uses [Kiro](https://kiro.dev), AWS's spec-driven agentic IDE, to generate hardened IAM policies via the AWS IaC MCP Server and AWS Documentation MCP Server.

1. Download and install Kiro from [kiro.dev](https://kiro.dev).
1. Launch Kiro and sign in with an AWS Builder ID. The free tier is sufficient for the workshop.

You'll configure the MCP servers during Lab 5 itself — no further action needed during prerequisites setup.

---

### 6. Node.js 18+ (required for Lab 5)

Kiro's AWS MCP servers (`@aws/aws-iac-mcp-server`, `@aws/aws-documentation-mcp-server`) run via `npx`, which requires Node.js 18 or later.

Install Node.js from [nodejs.org](https://nodejs.org/) or via your package manager (`brew install node`, `apt install nodejs npm`, etc.).

**Verify:**

```bash
node --version
```

You should see `v18.x` or later.

---

## Deploy Lab Infrastructure

Clone the workshop repository and deploy the vulnerable infrastructure with Terraform:

```bash
git clone https://github.com/TaraScho/ws-wrangling-identity-and-access-in-aws.git ~/workshop
cd ~/workshop
```

```bash
terraform -chdir=labs-full-day/terraform init -input=false
terraform -chdir=labs-full-day/terraform apply -auto-approve -input=false
```

This creates eight IAM users (six intentionally-vulnerable scenario users, plus `iamws-scanner-user` for read-only recon and `iamws-lab-default` as an admin used during setup, defense, and cleanup), along with supporting Lambda functions, EC2 security groups, S3 buckets, a CloudFormation stack, and Secrets Manager secrets. The full apply takes a few minutes.

---

## Configure Exercise AWS CLI Profiles

Terraform exposes each user's access keys as outputs. Configure an AWS CLI profile for each one, then mirror the admin credentials into the unnamed `default` profile so the CLI keeps working if your terminal's environment variables drop.

Run the following from the repository root (`~/workshop`):

```bash
PROFILES=(
  "iamws-scanner-user:scanner"
  "iamws-group-admin-user:group_admin"
  "iamws-policy-developer-user:policy_developer"
  "iamws-role-assumer-user:role_assumer"
  "iamws-ci-runner-user:ci_runner"
  "iamws-lambda-developer-user:lambda_developer"
  "iamws-secrets-reader-user:secrets_reader"
  "iamws-lab-default:lab_default"
)

for entry in "${PROFILES[@]}"; do
  profile_name="${entry%%:*}"
  tf_prefix="${entry##*:}"

  aws configure set aws_access_key_id \
    "$(terraform -chdir=labs-full-day/terraform output -raw ${tf_prefix}_access_key_id)" \
    --profile "$profile_name"
  aws configure set aws_secret_access_key \
    "$(terraform -chdir=labs-full-day/terraform output -raw ${tf_prefix}_secret_access_key)" \
    --profile "$profile_name"
  aws configure set region us-east-1 --profile "$profile_name"

  echo "Configured profile: $profile_name"
done

# Mirror iamws-lab-default into the unnamed default profile so the CLI keeps
# working after your shell session drops its env-var credentials.
aws configure set aws_access_key_id \
  "$(terraform -chdir=labs-full-day/terraform output -raw lab_default_access_key_id)" \
  --profile default
aws configure set aws_secret_access_key \
  "$(terraform -chdir=labs-full-day/terraform output -raw lab_default_secret_access_key)" \
  --profile default
aws configure set region us-east-1 --profile default
echo "Configured profile: default (mirrors iamws-lab-default)"
```

**Verify:**

```bash
aws sts get-caller-identity --profile iamws-policy-developer-user
```

You should see output containing `iamws-policy-developer-user` in the ARN.

---

## Validation Checklist

Run through these checks to confirm everything is ready:

```bash
# Tools installed
aws --version
terraform version
iam-recon --help | head -1
session-manager-plugin --version
node --version

# Workshop profiles configured (should return 8: 6 scenario users + scanner + lab-default)
aws configure list-profiles | grep -c iamws

# Test the scanner profile (used to build the iam-recon graph in Lab 1)
aws sts get-caller-identity --profile iamws-scanner-user

# Test the lab-default profile (used for setup, defense, and cleanup)
aws sts get-caller-identity --profile iamws-lab-default

# Test the default profile (mirrors iamws-lab-default)
aws sts get-caller-identity
```

If all checks pass, you're ready to start Lab 1 at the **Privilege Escalation Categories** section.

---

## Cleanup

When you're done with the workshop, tear down everything you created. Run all commands from the repository root.

1. **Delete the Lab 5 CloudFormation stacks** (skip this step if you didn't run Lab 5):

   ```bash
   ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text --profile iamws-lab-default)

   aws s3 rm "s3://analytics-data-${ACCOUNT_ID}" --recursive \
     --profile iamws-lab-default 2>/dev/null || true

   for stack in IAM-Hardening-Lab-Secure IAM-Hardening-Lab-Insecure IAM-Hardening-Lab-Bucket; do
     aws cloudformation delete-stack --stack-name "$stack" --profile iamws-lab-default 2>/dev/null || true
   done

   for stack in IAM-Hardening-Lab-Secure IAM-Hardening-Lab-Insecure IAM-Hardening-Lab-Bucket; do
     aws cloudformation wait stack-delete-complete --stack-name "$stack" --profile iamws-lab-default 2>/dev/null || true
   done
   ```

1. **Destroy the Terraform-deployed infrastructure:**

   ```bash
   terraform -chdir=labs-full-day/terraform destroy -auto-approve
   ```

   > [!IMPORTANT]
   > After `terraform destroy` finishes, `iamws-lab-default` is gone — any further `--profile iamws-lab-default` or `--profile default` calls will fail with `InvalidClientTokenId`. This is expected.

   > [!NOTE]
   > If `terraform destroy` errors out, the most likely cause is a workshop artifact left behind — typically a running EC2 instance from Lab 6, or a non-default IAM policy version from Lab 2. See [Lab 9 — Cleanup](../lab-9-cleanup/README.md) for the full troubleshooting checklist.

1. **Remove the workshop AWS CLI profiles** (optional, edits `~/.aws/credentials` and `~/.aws/config` locally):

   ```bash
   for profile in iamws-scanner-user iamws-group-admin-user iamws-policy-developer-user \
                  iamws-role-assumer-user iamws-ci-runner-user iamws-lambda-developer-user \
                  iamws-secrets-reader-user iamws-lab-default; do
     aws configure set aws_access_key_id "" --profile "$profile"
     aws configure set aws_secret_access_key "" --profile "$profile"
   done
   ```
