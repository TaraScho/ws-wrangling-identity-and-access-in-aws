#!/bin/bash
# wwhf-setup.sh
# Makes awspx, pmapper, and terraform available to ssm-user

set -e  # Exit on error

echo "=== Security Tools Setup Script ==="
echo ""

# ============================================================================
# STEP 0: AWS Credentials Setup & Validation
# ============================================================================
echo "[0/4] Setting up AWS credentials..."
echo ""

# Check if ssm-user has AWS credentials configured
if [ ! -f ~/.aws/credentials ] && [ -z "$AWS_ACCESS_KEY_ID" ]; then
    echo "⚠ No AWS credentials found for ssm-user!"
    echo ""
    echo "Please configure your AWS credentials first:"
    echo "  Option 1: Run 'aws configure' to set up credentials"
    echo "  Option 2: Set environment variables (AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY)"
    echo "  Option 3: Use aws-vault or similar tool"
    echo ""
    exit 1
fi

# Validate credentials work
echo "  Testing AWS credentials..."
if ! aws sts get-caller-identity &>/dev/null; then
    echo "  ✗ AWS credentials are invalid or expired"
    echo ""
    echo "Current AWS identity check failed. Please verify your credentials:"
    echo "  Run: aws sts get-caller-identity"
    echo ""
    exit 1
fi

# Show what identity we're using
AWS_IDENTITY=$(aws sts get-caller-identity --output json 2>/dev/null)
AWS_ARN=$(echo "$AWS_IDENTITY" | grep -o '"Arn": "[^"]*' | cut -d'"' -f4)
AWS_ACCOUNT=$(echo "$AWS_IDENTITY" | grep -o '"Account": "[^"]*' | cut -d'"' -f4)

echo "  ✓ AWS credentials validated"
echo "    Identity: $AWS_ARN"
echo "    Account:  $AWS_ACCOUNT"
echo ""

# Function to copy credentials to a user's home
copy_credentials_to_user() {
    local target_user=$1
    local target_home=$2
    
    echo "  Copying credentials to ${target_user} user (${target_home})..."
    sudo mkdir -p ${target_home}/.aws
    sudo chmod 755 ${target_home}/.aws
    
    # Copy credentials if they exist in a file
    if [ -f ~/.aws/credentials ]; then
        sudo cp ~/.aws/credentials ${target_home}/.aws/credentials
        sudo chown ${target_user}:${target_user} ${target_home}/.aws/credentials 2>/dev/null || sudo chown ${target_user} ${target_home}/.aws/credentials
        sudo chmod 600 ${target_home}/.aws/credentials
        echo "    ✓ Copied ~/.aws/credentials"
    fi
    
    # Copy config if it exists
    if [ -f ~/.aws/config ]; then
        sudo cp ~/.aws/config ${target_home}/.aws/config
        sudo chown ${target_user}:${target_user} ${target_home}/.aws/config 2>/dev/null || sudo chown ${target_user} ${target_home}/.aws/config
        sudo chmod 600 ${target_home}/.aws/config
        echo "    ✓ Copied ~/.aws/config"
    fi
    
    # If using environment variables, create credentials file from them
    if [ -n "$AWS_ACCESS_KEY_ID" ] && [ ! -f ${target_home}/.aws/credentials ]; then
        echo "    Creating credentials file from environment variables..."
        sudo tee ${target_home}/.aws/credentials > /dev/null << EOF
[default]
aws_access_key_id = $AWS_ACCESS_KEY_ID
aws_secret_access_key = $AWS_SECRET_ACCESS_KEY
${AWS_SESSION_TOKEN:+aws_session_token = $AWS_SESSION_TOKEN}
EOF
        sudo chown ${target_user}:${target_user} ${target_home}/.aws/credentials 2>/dev/null || sudo chown ${target_user} ${target_home}/.aws/credentials
        sudo chmod 600 ${target_home}/.aws/credentials
        echo "    ✓ Created credentials file from environment"
    fi
}

# Copy credentials to ubuntu user (for pmapper)
copy_credentials_to_user "ubuntu" "/home/ubuntu"

# Copy credentials to root user (for awspx)
copy_credentials_to_user "root" "/root"

# Validate ubuntu user can authenticate
echo "  Validating ubuntu user can authenticate..."
if sudo -u ubuntu aws sts get-caller-identity &>/dev/null; then
    UBUNTU_ARN=$(sudo -u ubuntu aws sts get-caller-identity --output json 2>/dev/null | grep -o '"Arn": "[^"]*' | cut -d'"' -f4)
    echo "    ✓ ubuntu user authenticated as: $UBUNTU_ARN"
else
    echo "    ✗ ubuntu user cannot authenticate with AWS"
    echo ""
    echo "This might be an issue with credential configuration."
    exit 1
fi

# Validate root user can authenticate
echo "  Validating root user can authenticate..."
if sudo aws sts get-caller-identity &>/dev/null; then
    ROOT_ARN=$(sudo aws sts get-caller-identity --output json 2>/dev/null | grep -o '"Arn": "[^"]*' | cut -d'"' -f4)
    echo "    ✓ root user authenticated as: $ROOT_ARN"
else
    echo "    ✗ root user cannot authenticate with AWS"
    echo ""
    echo "This might be an issue with credential configuration."
    exit 1
fi

echo ""

# ============================================================================
# STEP 1: Fix pmapper venv
# ============================================================================
echo "[1/4] Fixing pmapper virtual environment..."
if sudo -u ubuntu test -d "/home/ubuntu/workspace/PMapper/venv"; then
    echo "  Reinstalling pmapper with all dependencies..."
    sudo -u ubuntu bash -c "cd /home/ubuntu/workspace/PMapper && source venv/bin/activate && pip install -q --upgrade pip && pip install -q -e ."
    echo "  ✓ pmapper fully installed"
else
    echo "  ✗ pmapper venv not found at expected location"
    exit 1
fi

echo ""

# ============================================================================
# STEP 2: Install terraform
# ============================================================================
echo "[2/4] Installing terraform..."
if ! command -v terraform &> /dev/null; then
    cd /tmp
    TERRAFORM_VERSION="1.7.4"
    wget -q "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip"
    unzip -q terraform_${TERRAFORM_VERSION}_linux_amd64.zip
    sudo mv terraform /usr/local/bin/
    sudo chmod +x /usr/local/bin/terraform
    rm -f terraform_${TERRAFORM_VERSION}_linux_amd64.zip
    echo "  ✓ terraform ${TERRAFORM_VERSION} installed"
else
    echo "  ✓ terraform already installed"
fi

echo ""

# ============================================================================
# STEP 3: Create pmapper wrapper
# ============================================================================
echo "[3/4] Creating pmapper wrapper..."
sudo tee /usr/local/bin/pmapper > /dev/null << 'EOF'
#!/bin/bash
# Wrapper to run pmapper from ubuntu's venv (credentials from /home/ubuntu/.aws)
sudo -u ubuntu /home/ubuntu/workspace/PMapper/venv/bin/pmapper "$@"
EOF
sudo chmod +x /usr/local/bin/pmapper
echo "  ✓ pmapper wrapper created"

echo ""

# ============================================================================
# STEP 4: Setup awspx
# ============================================================================
echo "[4/4] Setting up awspx..."
# awspx already exists at /usr/local/bin/awspx and now root has credentials
echo "  ✓ awspx available (credentials configured for root user)"

echo ""

# ============================================================================
# Validation
# ============================================================================
echo "=== Validating Installation ==="
echo ""

# Validate terraform
echo "▸ Testing terraform..."
if terraform --version 2>&1 | head -1; then
    echo "  ✓ terraform is working"
else
    echo "  ✗ terraform failed"
fi

echo ""

# Validate pmapper
echo "▸ Testing pmapper..."
if pmapper --help 2>&1 | head -2; then
    echo "  ✓ pmapper wrapper is working"
else
    echo "  ✗ pmapper failed"
fi

echo ""

# Validate awspx
echo "▸ Testing awspx..."
if sudo /usr/local/bin/awspx --help 2>&1 | head -2; then
    echo "  ✓ awspx is working"
    echo ""
    echo "  Testing awspx AWS access..."
    # Quick AWS auth check for awspx
    if sudo aws sts get-caller-identity &>/dev/null; then
        echo "  ✓ awspx can access AWS (running as root)"
    else
        echo "  ⚠ awspx help works but AWS access needs verification"
    fi
else
    echo "  ✗ awspx failed"
fi

echo ""
echo "=== Setup Complete! ==="
echo ""
echo "✓ All tools are ready to use with AWS credentials:"
echo "  • terraform        - Infrastructure as code"
echo "  • pmapper          - AWS IAM privilege escalation analyzer"
echo "  • sudo awspx       - AWS attack path visualization"
echo ""
echo "AWS Identity: $AWS_ARN"
echo "Account:      $AWS_ACCOUNT"
echo ""

# 5. apply lab terraform modules
# cd /home/ssm-user/ws-wrangling-identity-and-access-in-aws/labs/terraform
# echo "[5/5] Applying lab terraform modules..."
# terraform init
# terraform apply --auto-approve
# echo "✓ lab terraform modules applied"