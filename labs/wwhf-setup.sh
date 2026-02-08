#!/bin/bash
# wwhf-setup.sh
# Makes awspx, pmapper, and terraform available to ssm-user

set -e  # Exit on error

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

# Copy credentials to ubuntu user's home so pmapper can use them
echo "  Copying credentials to ubuntu user..."
sudo mkdir -p /home/ubuntu/.aws
sudo chmod 755 /home/ubuntu/.aws

# Copy credentials if they exist in a file
if [ -f ~/.aws/credentials ]; then
    sudo cp ~/.aws/credentials /home/ubuntu/.aws/credentials
    sudo chown ubuntu:ubuntu /home/ubuntu/.aws/credentials
    sudo chmod 600 /home/ubuntu/.aws/credentials
    echo "    ✓ Copied ~/.aws/credentials"
fi

# Copy config if it exists
if [ -f ~/.aws/config ]; then
    sudo cp ~/.aws/config /home/ubuntu/.aws/config
    sudo chown ubuntu:ubuntu /home/ubuntu/.aws/config
    sudo chmod 600 /home/ubuntu/.aws/config
    echo "    ✓ Copied ~/.aws/config"
fi

# If using environment variables, create credentials file from them
if [ -n "$AWS_ACCESS_KEY_ID" ] && [ -z "$(sudo ls -A /home/ubuntu/.aws/credentials 2>/dev/null)" ]; then
    echo "    Creating credentials file from environment variables..."
    sudo tee /home/ubuntu/.aws/credentials > /dev/null << EOF
[default]
aws_access_key_id = $AWS_ACCESS_KEY_ID
aws_secret_access_key = $AWS_SECRET_ACCESS_KEY
${AWS_SESSION_TOKEN:+aws_session_token = $AWS_SESSION_TOKEN}
EOF
    sudo chown ubuntu:ubuntu /home/ubuntu/.aws/credentials
    sudo chmod 600 /home/ubuntu/.aws/credentials
    echo "    ✓ Created credentials file from environment"
fi

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

echo ""

echo "=== Security Tools Setup Script ==="
echo "Setting up awspx, pmapper, and terraform for ssm-user..."

# 1. Fix pmapper venv (FULL reinstall to ensure all dependencies)
echo ""
echo "[1/4] Fixing pmapper virtual environment..."
if sudo -u ubuntu test -d "/home/ubuntu/workspace/PMapper/venv"; then
    echo "  Reinstalling pmapper with all dependencies..."
    sudo -u ubuntu bash -c "cd /home/ubuntu/workspace/PMapper && source venv/bin/activate && pip install -q --upgrade pip && pip install -q -e ."
    echo "✓ pmapper fully installed"
else
    echo "✗ pmapper venv not found at expected location"
    exit 1
fi

# 2. Install terraform if not present
echo ""
echo "[2/4] Installing terraform..."
if ! command -v terraform &> /dev/null; then
    cd /tmp
    TERRAFORM_VERSION="1.7.4"
    wget -q "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip"
    unzip -q terraform_${TERRAFORM_VERSION}_linux_amd64.zip
    sudo mv terraform /usr/local/bin/
    sudo chmod +x /usr/local/bin/terraform
    rm -f terraform_${TERRAFORM_VERSION}_linux_amd64.zip
    echo "✓ terraform ${TERRAFORM_VERSION} installed"
else
    echo "✓ terraform already installed"
fi

# 3. Create pmapper wrapper script
echo ""
echo "[3/4] Creating pmapper wrapper..."
sudo tee /usr/local/bin/pmapper > /dev/null << 'EOF'
#!/bin/bash
# Wrapper to run pmapper from ubuntu's venv
sudo -u ubuntu /home/ubuntu/workspace/PMapper/venv/bin/pmapper "$@"
EOF
sudo chmod +x /usr/local/bin/pmapper
echo "✓ pmapper wrapper created"

# 4. Create awspx wrapper script (no alias needed!)
echo ""
echo "[4/4] Creating awspx wrapper..."
sudo tee /usr/local/bin/awspx-cli > /dev/null << 'EOF'
#!/bin/bash
# Wrapper to run awspx with sudo automatically
sudo /usr/local/bin/awspx "$@"
EOF
sudo chmod +x /usr/local/bin/awspx-cli

# Create a symlink so 'awspx' command works without sudo prompt
sudo ln -sf /usr/local/bin/awspx-cli /usr/local/bin/awspx-user
echo "✓ awspx wrapper created"

# Add to PATH for current session (works in both sh and bash)
export PATH="/usr/local/bin:$PATH"

echo ""
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
    echo "  ✓ pmapper is working"
else
    echo "  ✗ pmapper failed"
fi

echo ""

# Validate awspx
echo "▸ Testing awspx..."
if sudo /usr/local/bin/awspx --help 2>&1 | head -2; then
    echo "  ✓ awspx is working"
else
    echo "  ✗ awspx failed"
fi

echo ""
echo "=== Setup Complete! ==="
echo ""
echo "✓ All tools are ready to use:"
echo "  • terraform"
echo "  • pmapper"
echo "  • awspx  (requires sudo)"
echo ""

# 5. apply lab terraform modules
# cd /home/ssm-user/ws-wrangling-identity-and-access-in-aws/labs/terraform
# echo "[5/5] Applying lab terraform modules..."
# terraform init
# terraform apply --auto-approve
# echo "✓ lab terraform modules applied"