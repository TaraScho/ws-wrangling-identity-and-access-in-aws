#!/bin/bash
# wwhf-setup.sh — Workshop setup script
# Installs tools, deploys infrastructure, and configures exercise profiles.
# Designed for the SSM Session Manager environment on the workshop EC2 instance.

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

# Passwordless sudo (needed for Docker and awspx)
if ! sudo -n true 2>/dev/null; then
  fail "Passwordless sudo is required. This script is designed for the workshop EC2 instance."
fi
echo "  ✓ sudo access"

# Docker — installed?
if ! command -v docker &>/dev/null; then
  fail "Docker is not installed."
fi
# Docker — daemon running? Start if needed.
if ! sudo docker info &>/dev/null; then
  echo "  Docker daemon not running — starting it..."
  sudo systemctl start docker 2>/dev/null || sudo service docker start 2>/dev/null \
    || fail "Could not start Docker daemon."
  sleep 2
  sudo docker info &>/dev/null \
    || fail "Docker daemon failed to start. Check 'sudo systemctl status docker' for details."
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
  "$TOOLS_DIR/venvs/pmapper/bin/pip" install -q principalmapper rich \
    || fail "Failed to install principalmapper via pip."

  # Patch Python 3.10+ compatibility (upstream fix PR #139 never merged)
  # collections.Mapping/MutableMapping moved to collections.abc in Python 3.10
  CASE_DICT=$("$TOOLS_DIR/venvs/pmapper/bin/python" -c \
    "import principalmapper.util.case_insensitive_dict as m; print(m.__file__)" 2>/dev/null) \
    || CASE_DICT="$TOOLS_DIR/venvs/pmapper/lib/python*/site-packages/principalmapper/util/case_insensitive_dict.py"
  sed -i 's/from collections import Mapping, MutableMapping, OrderedDict/from collections.abc import Mapping, MutableMapping\nfrom collections import OrderedDict/' $CASE_DICT
  echo "  ✓ Patched collections.abc compatibility"

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
# Step 4 — Install SSM Session Manager plugin
# ============================================================================
step_banner "Step 4: Installing SSM Session Manager plugin"

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
# Step 5 — Recreate awspx container (clean slate every time)
# ============================================================================
step_banner "Step 5: Recreating awspx Docker container"

# Always nuke and recreate. The AMI-baked container was created in a different
# VPC and has a stale Docker network namespace that can't resolve DNS.

sudo docker stop awspx &>/dev/null
sudo docker rm awspx &>/dev/null
sudo docker rmi beatro0t/awspx:latest &>/dev/null

echo "  Pulling awspx image..."
sudo docker pull beatro0t/awspx:latest \
  || fail "Failed to pull awspx image. Check your internet connection."

echo "  Creating awspx container..."
sudo docker run -itd \
  --name awspx \
  --hostname=awspx \
  --env NEO4J_AUTH=neo4j/password \
  -p 127.0.0.1:10000:80 \
  -p 127.0.0.1:7687:7687 \
  -p 127.0.0.1:7373:7373 \
  -p 127.0.0.1:7474:7474 \
  -v /opt/awspx/data:/opt/awspx/data:z \
  -e NEO4J_dbms_security_procedures_unrestricted=apoc.jar \
  --restart=always beatro0t/awspx:latest >/dev/null \
  || fail "Failed to create awspx container."

echo "  ✓ awspx container created"

# ============================================================================
# Step 6 — Set up awspx wrapper
# ============================================================================
step_banner "Step 6: Setting up awspx wrapper"

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
# Step 7 — Persist PATH and AWS defaults
# ============================================================================
step_banner "Step 7: Persisting PATH and AWS defaults"

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
# Step 8 — Deploy lab infrastructure (terraform)
# ============================================================================
step_banner "Step 8: Deploying lab infrastructure with Terraform"

echo "  Running terraform init..."
terraform -chdir="$TERRAFORM_DIR" init -input=false \
  || fail "terraform init failed."

echo "  Running terraform apply (this may take a few minutes)..."
terraform -chdir="$TERRAFORM_DIR" apply -auto-approve -input=false \
  || fail "terraform apply failed."

echo "  ✓ Lab infrastructure deployed"

# ============================================================================
# Step 9 — Set up exercise AWS CLI profiles
# ============================================================================
step_banner "Step 9: Configuring exercise AWS CLI profiles"

REGION="us-east-1"

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
# Step 10 — Persistent default profile (survives session disconnect)
# ============================================================================
step_banner "Step 10: Setting up persistent default profile"

# The facilitator's temporary credentials (env vars) are lost on disconnect.
# This step creates a long-lived IAM user whose access key is stored in
# ~/.aws/credentials [default], so the CLI keeps working after reconnect.

DEFAULT_USER="iamws-lab-default"

if aws sts get-caller-identity --profile default 2>/dev/null | grep -q "$DEFAULT_USER"; then
  echo "  ✓ Persistent default profile already configured"
else
  # Create user if it doesn't exist
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

check "terraform"    "terraform version"
check "pmapper"      "pmapper --help"
check "awspx"        "awspx --help"
check "ssm plugin"   "command -v session-manager-plugin"
check "default profile" "aws sts get-caller-identity --profile default"

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
