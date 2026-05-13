#!/bin/bash
# wwhf-setup.sh — Full-day workshop setup script
# Forked from labs-two-hour-workshop/wwhf-setup.sh. Diverges from the 2-hour
# version: iam-recon is the only recon tool (no pmapper, no awspx Docker),
# and an extra iamws-scanner-user profile is configured for read-only graph
# scans.

# Bash guard: re-exec with bash if running under sh
if [ -z "$BASH_VERSION" ]; then exec bash "$0" "$@"; fi
set -euo pipefail

# ============================================================================
# AWS CLI defaults
# ============================================================================
export AWS_DEFAULT_REGION="us-east-1"
export AWS_PAGER=""

# ============================================================================
# Helpers
# ============================================================================

fail() {
  echo ""
  echo "✗ ERROR: $1" >&2
  exit 1
}

step_banner() {
  echo ""
  echo "================================================================"
  echo "  $1"
  echo "================================================================"
  echo ""
}

# ============================================================================
# Step 0 — Prerequisites check
# ============================================================================
step_banner "Step 0: Checking prerequisites"

# Locate the repo from the script's own path
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TOOLS_DIR="$REPO_DIR/tools"
# Terraform is shared with the 2-hour workshop.
TERRAFORM_DIR="$REPO_DIR/labs-two-hour-workshop/terraform"

echo "  Repo directory  : $REPO_DIR"
echo "  Tools directory : $TOOLS_DIR"
echo "  Terraform dir   : $TERRAFORM_DIR"
echo ""

# Required system commands
for cmd in git python3 unzip wget; do
  if ! command -v "$cmd" &>/dev/null; then
    fail "$cmd is not installed. Please install it and re-run this script."
  fi
  echo "  ✓ $cmd found"
done

# Passwordless sudo (needed for tool installation steps below)
if ! sudo -n true 2>/dev/null; then
  fail "Passwordless sudo is required. This script is designed for the workshop EC2 instance."
fi
echo "  ✓ sudo access"

# AWS credentials
if ! aws sts get-caller-identity &>/dev/null; then
  fail "AWS credentials not configured or invalid. Export AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, and AWS_SESSION_TOKEN, then re-run."
fi
AWS_ARN=$(aws sts get-caller-identity --query Arn --output text)
echo "  ✓ Authenticated as: $AWS_ARN"

# iam-recon must be on PATH (AMI-baked on the workshop VM)
if ! command -v iam-recon &>/dev/null; then
  fail "iam-recon not found on PATH. Is this the full-day workshop EC2 instance?"
fi
echo "  ✓ iam-recon found at $(command -v iam-recon)"

# ============================================================================
# Step 1 — Directory structure
# ============================================================================
step_banner "Step 1: Setting up directory structure"

mkdir -p "$TOOLS_DIR/bin"
export PATH="$TOOLS_DIR/bin:$PATH"
echo "  ✓ $TOOLS_DIR/bin ready"

# ============================================================================
# Step 2 — Install Terraform
# ============================================================================
step_banner "Step 2: Installing Terraform"

if terraform version &>/dev/null; then
  echo "  ✓ Terraform already installed: $(terraform version -json 2>/dev/null | python3 -c 'import sys,json; print(json.load(sys.stdin)["terraform_version"])' 2>/dev/null || terraform version 2>&1 | head -1)"
else
  TERRAFORM_VERSION="1.14.4"
  echo "  Downloading Terraform ${TERRAFORM_VERSION}..."
  wget -q -P /tmp "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip" \
    || fail "Failed to download Terraform. Check your internet connection."
  unzip -qo "/tmp/terraform_${TERRAFORM_VERSION}_linux_amd64.zip" -d "$TOOLS_DIR/bin/" \
    || fail "Failed to unzip Terraform."
  chmod +x "$TOOLS_DIR/bin/terraform"
  rm -f "/tmp/terraform_${TERRAFORM_VERSION}_linux_amd64.zip"

  terraform version &>/dev/null \
    || fail "Terraform installed but 'terraform version' failed."
  echo "  ✓ Terraform ${TERRAFORM_VERSION} installed"
fi

# ============================================================================
# Step 3 — Install SSM Session Manager plugin
# ============================================================================
step_banner "Step 3: Installing SSM Session Manager plugin"

if command -v session-manager-plugin &>/dev/null; then
  echo "  ✓ SSM Session Manager plugin already installed"
else
  echo "  Downloading SSM Session Manager plugin..."
  if command -v yum &>/dev/null; then
    wget -q -O /tmp/session-manager-plugin.rpm \
      "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/linux_64bit/session-manager-plugin.rpm" \
      || fail "Failed to download SSM Session Manager plugin."
    sudo yum install -y /tmp/session-manager-plugin.rpm &>/dev/null \
      || fail "Failed to install SSM Session Manager plugin."
    rm -f /tmp/session-manager-plugin.rpm
  elif command -v dpkg &>/dev/null; then
    wget -q -O /tmp/session-manager-plugin.deb \
      "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/ubuntu_64bit/session-manager-plugin.deb" \
      || fail "Failed to download SSM Session Manager plugin."
    sudo dpkg -i /tmp/session-manager-plugin.deb &>/dev/null \
      || fail "Failed to install SSM Session Manager plugin."
    rm -f /tmp/session-manager-plugin.deb
  else
    fail "Could not detect package manager (yum or dpkg) to install SSM Session Manager plugin."
  fi

  command -v session-manager-plugin &>/dev/null \
    || fail "SSM Session Manager plugin installed but not found on PATH."
  echo "  ✓ SSM Session Manager plugin installed"
fi

# ============================================================================
# Step 4 — Persist PATH and AWS defaults
# ============================================================================
step_banner "Step 4: Persisting PATH and AWS defaults"

PATH_LINE="export PATH=\"$TOOLS_DIR/bin:\$PATH\""
REGION_LINE='export AWS_DEFAULT_REGION="us-east-1"'
PAGER_LINE='export AWS_PAGER=""'

for rcfile in "$HOME/.bashrc" "$HOME/.profile"; do
  if ! grep -qF "$TOOLS_DIR/bin" "$rcfile" 2>/dev/null; then
    echo "" >> "$rcfile"
    echo "# Workshop tools" >> "$rcfile"
    echo "$PATH_LINE" >> "$rcfile"
    echo "$REGION_LINE" >> "$rcfile"
    echo "$PAGER_LINE" >> "$rcfile"
    echo "  ✓ Added to $rcfile"
  else
    echo "  ✓ Already in $rcfile"
  fi
done

# ============================================================================
# Step 5 — Deploy lab infrastructure (terraform)
# ============================================================================
step_banner "Step 5: Deploying lab infrastructure with Terraform"

echo "  Running terraform init..."
terraform -chdir="$TERRAFORM_DIR" init -input=false \
  || fail "terraform init failed."

echo "  Running terraform apply (this may take a few minutes)..."
terraform -chdir="$TERRAFORM_DIR" apply -auto-approve -input=false \
  || fail "terraform apply failed."

echo "  ✓ Lab infrastructure deployed"

# ============================================================================
# Step 6 — Set up exercise AWS CLI profiles
# ============================================================================
step_banner "Step 6: Configuring exercise AWS CLI profiles"

REGION="us-east-1"

# Format: "<profile-name>:<terraform-output-prefix>"
# iamws-scanner-user is the read-only recon profile used by iam-recon.
PROFILES=(
  "iamws-scanner-user:scanner"
  "iamws-group-admin-user:group_admin"
  "iamws-policy-developer-user:policy_developer"
  "iamws-role-assumer-user:role_assumer"
  "iamws-ci-runner-user:ci_runner"
  "iamws-lambda-developer-user:lambda_developer"
  "iamws-secrets-reader-user:secrets_reader"
)

PROFILE_COUNT=0
for entry in "${PROFILES[@]}"; do
  profile_name="${entry%%:*}"
  tf_prefix="${entry##*:}"

  access_key_id=$(terraform -chdir="$TERRAFORM_DIR" output -raw "${tf_prefix}_access_key_id" 2>/dev/null) \
    || fail "Could not read terraform output ${tf_prefix}_access_key_id. Did terraform apply succeed?"
  secret_access_key=$(terraform -chdir="$TERRAFORM_DIR" output -raw "${tf_prefix}_secret_access_key" 2>/dev/null) \
    || fail "Could not read terraform output ${tf_prefix}_secret_access_key. Did terraform apply succeed?"

  if [ -z "$access_key_id" ] || [ -z "$secret_access_key" ]; then
    fail "Empty credentials for $profile_name. Check terraform outputs."
  fi

  aws configure set aws_access_key_id "$access_key_id" --profile "$profile_name"
  aws configure set aws_secret_access_key "$secret_access_key" --profile "$profile_name"
  aws configure set region "$REGION" --profile "$profile_name"
  echo "  ✓ Profile: $profile_name"
  PROFILE_COUNT=$((PROFILE_COUNT + 1))
done

echo ""
echo "  ✓ $PROFILE_COUNT exercise profiles configured"

# ============================================================================
# Step 7 — Persistent default profile (survives session disconnect)
# ============================================================================
step_banner "Step 7: Setting up persistent default profile"

# The facilitator's temporary credentials (env vars) are lost on disconnect.
# This step creates a long-lived IAM user whose access key is stored in
# ~/.aws/credentials [default], so the CLI keeps working after reconnect.

DEFAULT_USER="iamws-lab-default"

if aws sts get-caller-identity --profile default 2>/dev/null | grep -q "$DEFAULT_USER"; then
  echo "  ✓ Persistent default profile already configured"
else
  if aws iam get-user --user-name "$DEFAULT_USER" &>/dev/null; then
    echo "  IAM user $DEFAULT_USER already exists"
  else
    echo "  Creating IAM user $DEFAULT_USER..."
    aws iam create-user --user-name "$DEFAULT_USER" --output text &>/dev/null \
      || fail "Failed to create IAM user $DEFAULT_USER."
    aws iam attach-user-policy --user-name "$DEFAULT_USER" \
      --policy-arn arn:aws:iam::aws:policy/AdministratorAccess \
      || fail "Failed to attach AdministratorAccess to $DEFAULT_USER."
  fi

  echo "  Creating access key..."
  KEY_JSON=$(aws iam create-access-key --user-name "$DEFAULT_USER" --output json) \
    || fail "Failed to create access key for $DEFAULT_USER. (Max 2 keys per user — delete old keys if needed.)"

  AK=$(echo "$KEY_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['AccessKey']['AccessKeyId'])")
  SK=$(echo "$KEY_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['AccessKey']['SecretAccessKey'])")

  aws configure set aws_access_key_id "$AK" --profile default
  aws configure set aws_secret_access_key "$SK" --profile default
  aws configure set region "$REGION" --profile default

  # New IAM access keys can take a few seconds to propagate (eventual consistency)
  echo "  Waiting for access key to become active..."
  for i in 1 2 3 4 5; do
    if aws sts get-caller-identity --profile default &>/dev/null; then
      break
    fi
    if [ "$i" -eq 5 ]; then
      fail "Default profile created but authentication failed after 25s. The access key may need more time to propagate — try: aws sts get-caller-identity --profile default"
    fi
    sleep 5
  done
  echo "  ✓ Persistent default profile configured ($DEFAULT_USER)"
  echo "    If you lose your session, your CLI will automatically use this profile."
fi

# ============================================================================
# Final — Validation summary
# ============================================================================
step_banner "Validation Summary"

PASS=0
TOTAL=0

check() {
  TOTAL=$((TOTAL + 1))
  if eval "$2" &>/dev/null; then
    echo "  ✓ $1"
    PASS=$((PASS + 1))
  else
    echo "  ✗ $1"
  fi
}

check "terraform"       "terraform version"
check "iam-recon"       "iam-recon --help"
check "ssm plugin"      "command -v session-manager-plugin"
check "default profile" "aws sts get-caller-identity --profile default"
check "scanner profile" "aws sts get-caller-identity --profile iamws-scanner-user"

IAMWS_COUNT=$(aws configure list-profiles 2>/dev/null | grep -c iamws || true)
TOTAL=$((TOTAL + 1))
if [ "$IAMWS_COUNT" -eq 7 ]; then
  echo "  ✓ exercise profiles ($IAMWS_COUNT/7)"
  PASS=$((PASS + 1))
else
  echo "  ✗ exercise profiles ($IAMWS_COUNT/7)"
fi

echo ""
if [ "$PASS" -eq "$TOTAL" ]; then
  echo "=== Setup Complete! ($PASS/$TOTAL checks passed) ==="
  echo ""
  echo "You're ready to start the workshop. Happy hacking!"
  echo ""
  echo "  Run this command to activate the tools in your current session:"
  echo ""
  echo "    source ~/.bashrc"
  echo ""
else
  echo "=== Setup finished with issues ($PASS/$TOTAL checks passed) ==="
  echo ""
  echo "Review the failures above and re-run the script if needed."
  exit 1
fi
