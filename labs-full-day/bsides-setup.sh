#!/bin/bash
# bsides-setup.sh — Full-day workshop setup script
#
# Runs on:
#   - The pre-built workshop image (Linux, every dependency pre-installed)
#   - A learner's own Mac or Linux laptop (script installs missing dependencies)
#
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
# OS / architecture detection
# ============================================================================
# Sets:
#   OS_NAME          linux|darwin           (used by Terraform/SSM downloads)
#   OS_ARCH          amd64|arm64            (used by Terraform/SSM/.deb)
#   IAM_RECON_OS     linux|macos            (iam-recon release asset naming)
#   IAM_RECON_ARCH   x86_64|aarch64         (iam-recon release asset naming)
#
# Bails on Windows / unsupported OSes — iam-recon does not ship Windows
# binaries today, so those learners need to use the provided lab VM.

case "$(uname -s)" in
  Linux*)
    OS_NAME="linux"
    IAM_RECON_OS="linux"
    ;;
  Darwin*)
    OS_NAME="darwin"
    IAM_RECON_OS="macos"
    ;;
  *)
    fail "Unsupported OS: $(uname -s). iam-recon only ships Linux and macOS binaries — use the pre-built workshop image for this workshop."
    ;;
esac

case "$(uname -m)" in
  x86_64|amd64)
    OS_ARCH="amd64"
    IAM_RECON_ARCH="x86_64"
    ;;
  arm64|aarch64)
    OS_ARCH="arm64"
    IAM_RECON_ARCH="aarch64"
    ;;
  *)
    fail "Unsupported CPU architecture: $(uname -m). iam-recon ships x86_64 and aarch64 binaries only."
    ;;
esac

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

echo "  OS              : $OS_NAME/$OS_ARCH"
echo "  Repo directory  : $REPO_DIR"
echo "  Tools directory : $TOOLS_DIR"
echo "  Terraform dir   : $TERRAFORM_DIR"
echo ""

# Required base commands. Available out-of-the-box inside the workshop image; learners on
# their own machines may need to install missing entries via their package
# manager (brew on macOS, apt/yum on Linux).
for cmd in git python3 unzip curl jq zip; do
  if ! command -v "$cmd" &>/dev/null; then
    fail "$cmd is not installed. Please install it via your package manager and re-run this script."
  fi
  echo "  ✓ $cmd found"
done

# AWS credentials
if ! aws sts get-caller-identity &>/dev/null; then
  fail "AWS credentials not configured or invalid. Export AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, and (if using temporary credentials) AWS_SESSION_TOKEN, then re-run."
fi
AWS_ARN=$(aws sts get-caller-identity --query Arn --output text)
echo "  ✓ Authenticated as: $AWS_ARN"

# ============================================================================
# Step 1 — Directory structure
# ============================================================================
step_banner "Step 1: Setting up directory structure"

mkdir -p "$TOOLS_DIR/bin"
export PATH="$TOOLS_DIR/bin:$PATH"
echo "  ✓ $TOOLS_DIR/bin ready"

# OpenTofu compatibility: workshop VMs may ship `tofu` instead of `terraform`.
# tofu is a drop-in fork — same CLI, compatible state — so if tofu is the only
# IaC binary present, alias the `terraform` command to it for the rest of this
# script. When real terraform is on PATH, leave it alone.
if command -v tofu &>/dev/null && ! command -v terraform &>/dev/null; then
  echo "  ✓ Detected OpenTofu — using tofu in place of terraform"
  terraform() { command tofu "$@"; }
fi

# ============================================================================
# Step 2 — Install iam-recon
# ============================================================================
# Upstream: https://github.com/andrewkrug/iam-recon
# Release assets (current as of v0.1.0):
#   iam-recon-linux-x86_64        raw binary
#   iam-recon-linux-aarch64       raw binary
#   iam-recon-macos-x86_64        raw binary
#   iam-recon-macos-aarch64       raw binary
#   iam-recon_amd64.deb           Debian/Ubuntu package
#   iam-recon_arm64.deb           Debian/Ubuntu package
# The repo also acts as a Homebrew tap (andrewkrug/iam-recon).
#
# Install strategy (try the cleanest path first, fall back as needed):
#   1. Homebrew tap     — if `brew` is on PATH (macOS and most Linux laptops).
#   2. .deb package     — Linux + dpkg + sudo (workshop VM is Debian/Ubuntu).
#   3. Raw release bin  — everyone else; drop into $TOOLS_DIR/bin.

step_banner "Step 2: Installing iam-recon"

IAM_RECON_REPO="andrewkrug/iam-recon"
IAM_RECON_RELEASE_BASE="https://github.com/${IAM_RECON_REPO}/releases/latest/download"

install_iam_recon_brew() {
  echo "  Homebrew detected — installing from the upstream tap..."
  if brew list iam-recon &>/dev/null; then
    echo "  ✓ iam-recon already installed via Homebrew"
    return 0
  fi
  if ! brew tap 2>/dev/null | grep -qx "andrewkrug/iam-recon"; then
    brew tap andrewkrug/iam-recon "https://github.com/${IAM_RECON_REPO}" \
      || return 1
  fi
  brew install andrewkrug/iam-recon/iam-recon || return 1
}

install_iam_recon_deb() {
  local deb_url="${IAM_RECON_RELEASE_BASE}/iam-recon_${OS_ARCH}.deb"
  echo "  Downloading iam-recon_${OS_ARCH}.deb from ${deb_url} ..."
  curl -fsSL -o /tmp/iam-recon.deb "$deb_url" || return 1
  sudo dpkg -i /tmp/iam-recon.deb >/dev/null || { rm -f /tmp/iam-recon.deb; return 1; }
  rm -f /tmp/iam-recon.deb
}

install_iam_recon_binary() {
  local bin_url="${IAM_RECON_RELEASE_BASE}/iam-recon-${IAM_RECON_OS}-${IAM_RECON_ARCH}"
  echo "  Downloading iam-recon binary (${IAM_RECON_OS}/${IAM_RECON_ARCH}) from ${bin_url} ..."
  curl -fsSL "$bin_url" -o "$TOOLS_DIR/bin/iam-recon" || return 1
  chmod +x "$TOOLS_DIR/bin/iam-recon"
}

if command -v iam-recon &>/dev/null; then
  echo "  ✓ iam-recon already installed: $(command -v iam-recon)"
else
  installed=0
  if command -v brew &>/dev/null; then
    install_iam_recon_brew && installed=1
  fi
  if [ "$installed" -eq 0 ] && [ "$OS_NAME" = "linux" ] \
      && command -v dpkg &>/dev/null && command -v sudo &>/dev/null; then
    install_iam_recon_deb && installed=1
  fi
  if [ "$installed" -eq 0 ]; then
    install_iam_recon_binary && installed=1
  fi
  [ "$installed" -eq 1 ] \
    || fail "All iam-recon install methods failed. See https://github.com/${IAM_RECON_REPO}/releases for manual install."

  hash -r 2>/dev/null || true
  command -v iam-recon &>/dev/null \
    || fail "iam-recon installed but not found on PATH. Check $TOOLS_DIR/bin or your Homebrew prefix."
  iam-recon --help &>/dev/null \
    || fail "iam-recon installed but 'iam-recon --help' failed."
  echo "  ✓ iam-recon installed: $(command -v iam-recon)"
fi

# ============================================================================
# Step 3 — Install Terraform
# ============================================================================
step_banner "Step 3: Installing Terraform"

if terraform version &>/dev/null; then
  echo "  ✓ Terraform already installed: $(terraform version -json 2>/dev/null | python3 -c 'import sys,json; print(json.load(sys.stdin)["terraform_version"])' 2>/dev/null || terraform version 2>&1 | head -1)"
else
  TERRAFORM_VERSION="1.14.4"
  TF_ZIP="terraform_${TERRAFORM_VERSION}_${OS_NAME}_${OS_ARCH}.zip"
  echo "  Downloading Terraform ${TERRAFORM_VERSION} (${OS_NAME}/${OS_ARCH})..."
  curl -fsSL -o "/tmp/${TF_ZIP}" \
    "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/${TF_ZIP}" \
    || fail "Failed to download Terraform. Check your internet connection."
  unzip -qo "/tmp/${TF_ZIP}" -d "$TOOLS_DIR/bin/" \
    || fail "Failed to unzip Terraform."
  chmod +x "$TOOLS_DIR/bin/terraform"
  rm -f "/tmp/${TF_ZIP}"

  terraform version &>/dev/null \
    || fail "Terraform installed but 'terraform version' failed."
  echo "  ✓ Terraform ${TERRAFORM_VERSION} installed"
fi

# ============================================================================
# Step 4 — Install SSM Session Manager plugin
# ============================================================================
step_banner "Step 4: Installing SSM Session Manager plugin"

if command -v session-manager-plugin &>/dev/null; then
  echo "  ✓ SSM Session Manager plugin already installed"
else
  echo "  Downloading SSM Session Manager plugin (${OS_NAME}/${OS_ARCH})..."
  if [ "$OS_NAME" = "darwin" ]; then
    # macOS: extract the official bundle and drop the binary into tools/bin
    # (avoids sudo / system-wide install). Bundle paths differ by arch.
    if [ "$OS_ARCH" = "arm64" ]; then
      SSM_URL="https://s3.amazonaws.com/session-manager-downloads/plugin/latest/mac_arm64/sessionmanager-bundle.zip"
    else
      SSM_URL="https://s3.amazonaws.com/session-manager-downloads/plugin/latest/mac/sessionmanager-bundle.zip"
    fi
    curl -fsSL -o /tmp/sessionmanager-bundle.zip "$SSM_URL" \
      || fail "Failed to download SSM Session Manager plugin."
    rm -rf /tmp/sessionmanager-bundle
    unzip -qo /tmp/sessionmanager-bundle.zip -d /tmp/ \
      || fail "Failed to unzip SSM Session Manager plugin bundle."
    cp /tmp/sessionmanager-bundle/bin/session-manager-plugin "$TOOLS_DIR/bin/" \
      || fail "Failed to install SSM Session Manager plugin binary."
    chmod +x "$TOOLS_DIR/bin/session-manager-plugin"
    rm -rf /tmp/sessionmanager-bundle /tmp/sessionmanager-bundle.zip
  elif command -v yum &>/dev/null; then
    curl -fsSL -o /tmp/session-manager-plugin.rpm \
      "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/linux_64bit/session-manager-plugin.rpm" \
      || fail "Failed to download SSM Session Manager plugin."
    sudo yum install -y /tmp/session-manager-plugin.rpm &>/dev/null \
      || fail "Failed to install SSM Session Manager plugin."
    rm -f /tmp/session-manager-plugin.rpm
  elif command -v dpkg &>/dev/null; then
    curl -fsSL -o /tmp/session-manager-plugin.deb \
      "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/ubuntu_64bit/session-manager-plugin.deb" \
      || fail "Failed to download SSM Session Manager plugin."
    sudo dpkg -i /tmp/session-manager-plugin.deb &>/dev/null \
      || fail "Failed to install SSM Session Manager plugin."
    rm -f /tmp/session-manager-plugin.deb
  else
    fail "Could not detect a supported package manager (yum, dpkg, or macOS) to install SSM Session Manager plugin."
  fi

  command -v session-manager-plugin &>/dev/null \
    || fail "SSM Session Manager plugin installed but not found on PATH."
  echo "  ✓ SSM Session Manager plugin installed"
fi

# ============================================================================
# Step 5 — Persist PATH and AWS defaults
# ============================================================================
step_banner "Step 5: Persisting PATH and AWS defaults"

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
# Step 6 — Deploy lab infrastructure (terraform)
# ============================================================================
step_banner "Step 6: Deploying lab infrastructure with Terraform"

echo "  Running terraform init..."
terraform -chdir="$TERRAFORM_DIR" init -input=false \
  || fail "terraform init failed."

echo "  Running terraform apply (this may take a few minutes)..."
terraform -chdir="$TERRAFORM_DIR" apply -auto-approve -input=false \
  || fail "terraform apply failed."

echo "  ✓ Lab infrastructure deployed"

# ============================================================================
# Step 7 — Set up exercise AWS CLI profiles
# ============================================================================
step_banner "Step 7: Configuring exercise AWS CLI profiles"

REGION="us-east-1"

# Format: "<profile-name>:<terraform-output-prefix>"
# iamws-scanner-user is the read-only recon profile used by iam-recon.
# iamws-lab-default is the admin profile referenced throughout the lab docs.
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
# Step 8 — Populate the default profile from iamws-lab-default
# ============================================================================
# iamws-lab-default is created as part of `terraform apply` (managed in the
# iam-principals module). Here we just mirror its credentials into the
# unnamed `default` profile so that:
#   - The AWS CLI keeps working after a Guacamole / SSH session drops the
#     env-var credentials the learner started with.
#   - Any `aws` command without an explicit --profile flag uses the admin user.
# The named `iamws-lab-default` profile is already configured in Step 7.

step_banner "Step 8: Mirroring iamws-lab-default into the default profile"

lab_default_ak=$(terraform -chdir="$TERRAFORM_DIR" output -raw lab_default_access_key_id 2>/dev/null) \
  || fail "Could not read terraform output lab_default_access_key_id. Did terraform apply succeed?"
lab_default_sk=$(terraform -chdir="$TERRAFORM_DIR" output -raw lab_default_secret_access_key 2>/dev/null) \
  || fail "Could not read terraform output lab_default_secret_access_key. Did terraform apply succeed?"

if [ -z "$lab_default_ak" ] || [ -z "$lab_default_sk" ]; then
  fail "Empty credentials for iamws-lab-default. Check terraform outputs."
fi

aws configure set aws_access_key_id "$lab_default_ak" --profile default
aws configure set aws_secret_access_key "$lab_default_sk" --profile default
aws configure set region "$REGION" --profile default
echo "  ✓ Default profile configured (iamws-lab-default)"
echo "    If you lose your session, your CLI will automatically use this profile."

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

check "terraform"          "terraform version"
check "iam-recon"          "iam-recon --help"
check "ssm plugin"         "command -v session-manager-plugin"
check "scanner profile"    "aws sts get-caller-identity --profile iamws-scanner-user"
check "lab-default profile" "aws sts get-caller-identity --profile iamws-lab-default"
check "default profile"    "aws sts get-caller-identity --profile default"

IAMWS_COUNT=$(aws configure list-profiles 2>/dev/null | grep -c iamws || true)
TOTAL=$((TOTAL + 1))
if [ "$IAMWS_COUNT" -eq 8 ]; then
  echo "  ✓ workshop profiles ($IAMWS_COUNT/8)"
  PASS=$((PASS + 1))
else
  echo "  ✗ workshop profiles ($IAMWS_COUNT/8)"
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
