#!/bin/bash
# wwhf-setup.sh — Workshop setup script
# Installs tools, deploys infrastructure, and configures exercise profiles.
# Designed for the SSM Session Manager environment on the workshop EC2 instance.

# Bash guard: re-exec with bash if running under sh
if [ -z "$BASH_VERSION" ]; then exec bash "$0" "$@"; fi
set -euo pipefail

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
TERRAFORM_DIR="$REPO_DIR/labs/terraform"

echo "  Repo directory : $REPO_DIR"
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

# Docker
if ! docker info &>/dev/null; then
  fail "Docker is not running. Start Docker and re-run this script."
fi
echo "  ✓ Docker is running"

# AWS credentials
if ! aws sts get-caller-identity &>/dev/null; then
  fail "AWS credentials not configured or invalid. Export AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, and AWS_SESSION_TOKEN, then re-run."
fi
AWS_ARN=$(aws sts get-caller-identity --query Arn --output text)
echo "  ✓ Authenticated as: $AWS_ARN"

# awspx system binary
if [ ! -x /usr/local/bin/awspx ]; then
  fail "awspx not found at /usr/local/bin/awspx. Is this the workshop EC2 instance?"
fi
echo "  ✓ awspx binary found at /usr/local/bin/awspx"

# ============================================================================
# Step 1 — Directory structure
# ============================================================================
step_banner "Step 1: Setting up directory structure"

mkdir -p "$TOOLS_DIR"/{bin,venvs}
export PATH="$TOOLS_DIR/bin:$PATH"
echo "  ✓ $TOOLS_DIR/bin and $TOOLS_DIR/venvs ready"

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
# Step 3 — Install pmapper
# ============================================================================
step_banner "Step 3: Installing pmapper"

if "$TOOLS_DIR/bin/pmapper" --help &>/dev/null; then
  echo "  ✓ pmapper already installed"
else
  echo "  Creating Python virtual environment..."
  python3 -m venv "$TOOLS_DIR/venvs/pmapper" \
    || fail "Failed to create pmapper venv. Is python3-venv installed?"

  echo "  Installing pmapper into venv..."
  "$TOOLS_DIR/venvs/pmapper/bin/pip" install -q --upgrade pip
  "$TOOLS_DIR/venvs/pmapper/bin/pip" install -q principalmapper \
    || fail "Failed to install principalmapper via pip."

  # Create wrapper — calls venv binary directly, no source/activate needed
  cat > "$TOOLS_DIR/bin/pmapper" << WRAPPER
#!/bin/bash
exec "$TOOLS_DIR/venvs/pmapper/bin/pmapper" "\$@"
WRAPPER
  chmod +x "$TOOLS_DIR/bin/pmapper"

  "$TOOLS_DIR/bin/pmapper" --help &>/dev/null \
    || fail "pmapper installed but 'pmapper --help' failed."
  echo "  ✓ pmapper installed"
fi

# ============================================================================
# Step 4 — Set up awspx wrapper
# ============================================================================
step_banner "Step 4: Setting up awspx wrapper"

cat > "$TOOLS_DIR/bin/awspx" << 'WRAPPER'
#!/bin/bash
# Wrapper for awspx: passes AWS credentials through sudo -E

# Prefer env vars if already set; fall back to ~/.aws/credentials [default]
if [ -z "${AWS_ACCESS_KEY_ID:-}" ] && [ -f ~/.aws/credentials ]; then
  export AWS_ACCESS_KEY_ID=$(grep -A2 "\[default\]" ~/.aws/credentials 2>/dev/null | grep aws_access_key_id | cut -d'=' -f2 | tr -d ' ')
  export AWS_SECRET_ACCESS_KEY=$(grep -A2 "\[default\]" ~/.aws/credentials 2>/dev/null | grep aws_secret_access_key | cut -d'=' -f2 | tr -d ' ')
  SESSION_TOKEN=$(grep -A3 "\[default\]" ~/.aws/credentials 2>/dev/null | grep aws_session_token | cut -d'=' -f2 | tr -d ' ')
  if [ -n "$SESSION_TOKEN" ]; then
    export AWS_SESSION_TOKEN="$SESSION_TOKEN"
    export AWS_SECURITY_TOKEN="$SESSION_TOKEN"
  fi
fi

sudo -E /usr/local/bin/awspx "$@"
WRAPPER
chmod +x "$TOOLS_DIR/bin/awspx"

awspx --help &>/dev/null \
  || fail "awspx wrapper created but 'awspx --help' failed. Is Docker running?"
echo "  ✓ awspx wrapper created and validated"

# ============================================================================
# Step 5 — Persist PATH
# ============================================================================
step_banner "Step 5: Persisting PATH"

PATH_LINE="export PATH=\"$TOOLS_DIR/bin:\$PATH\""

for rcfile in "$HOME/.bashrc" "$HOME/.profile"; do
  if ! grep -qF "$TOOLS_DIR/bin" "$rcfile" 2>/dev/null; then
    echo "" >> "$rcfile"
    echo "# Workshop tools" >> "$rcfile"
    echo "$PATH_LINE" >> "$rcfile"
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

REGION=$(aws configure get region 2>/dev/null || echo "us-east-1")

PROFILES=(
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

check "terraform"    "terraform version"
check "pmapper"      "pmapper --help"
check "awspx"        "awspx --help"

IAMWS_COUNT=$(aws configure list-profiles 2>/dev/null | grep -c iamws || true)
TOTAL=$((TOTAL + 1))
if [ "$IAMWS_COUNT" -eq 6 ]; then
  echo "  ✓ exercise profiles ($IAMWS_COUNT/6)"
  PASS=$((PASS + 1))
else
  echo "  ✗ exercise profiles ($IAMWS_COUNT/6)"
fi

echo ""
if [ "$PASS" -eq "$TOTAL" ]; then
  echo "=== Setup Complete! ($PASS/$TOTAL checks passed) ==="
  echo ""
  echo "You're ready to start Lab 1. Happy hacking!"
else
  echo "=== Setup finished with issues ($PASS/$TOTAL checks passed) ==="
  echo ""
  echo "Review the failures above and re-run the script if needed."
  exit 1
fi
