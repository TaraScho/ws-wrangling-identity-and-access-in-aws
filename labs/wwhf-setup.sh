#!/bin/bash
# fresh-install-security-tools.sh
# Clean installation of security tools for ssm-user (no sudo wrappers needed)

set -e

echo "=== Fresh Security Tools Installation ==="
echo ""

# Setup directory structure
TOOLS_DIR="$HOME/security-tools"
mkdir -p "$TOOLS_DIR"/{bin,venvs}

# Add to PATH for current session
export PATH="$TOOLS_DIR/bin:$PATH"

# ============================================================================
# 0. Validate AWS credentials
# ============================================================================
echo "[0/3] Validating AWS credentials..."
if ! aws sts get-caller-identity &>/dev/null; then
    echo "✗ AWS credentials not configured or invalid"
    echo "  Run: aws configure"
    exit 1
fi
AWS_ARN=$(aws sts get-caller-identity --query Arn --output text)
echo "✓ Authenticated as: $AWS_ARN"
echo ""

# ============================================================================
# 1. Install Terraform
# ============================================================================
echo "[1/3] Installing terraform..."
if [ ! -f "$TOOLS_DIR/bin/terraform" ]; then
    cd /tmp
    TERRAFORM_VERSION="1.14.4"
    wget -q "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip"
    unzip -q terraform_${TERRAFORM_VERSION}_linux_amd64.zip
    mv terraform "$TOOLS_DIR/bin/"
    chmod +x "$TOOLS_DIR/bin/terraform"
    rm -f terraform_${TERRAFORM_VERSION}_linux_amd64.zip
    echo "  ✓ terraform ${TERRAFORM_VERSION} installed"
else
    echo "  ✓ terraform already installed"
fi
echo ""

# ============================================================================
# 2. Install pmapper (fresh venv)
# ============================================================================
echo "[2/3] Installing pmapper..."
if [ ! -d "$TOOLS_DIR/venvs/pmapper" ]; then
    echo "  Creating Python virtual environment..."
    python3 -m venv "$TOOLS_DIR/venvs/pmapper"
    
    echo "  Installing pmapper..."
    source "$TOOLS_DIR/venvs/pmapper/bin/activate"
    pip install -q --upgrade pip
    pip install -q principalmapper
    deactivate
    
    # Create wrapper script
    cat > "$TOOLS_DIR/bin/pmapper" << 'EOF'
#!/bin/bash
source "$HOME/security-tools/venvs/pmapper/bin/activate"
pmapper "$@"
deactivate
EOF
    chmod +x "$TOOLS_DIR/bin/pmapper"
    echo "  ✓ pmapper installed"
else
    echo "  ✓ pmapper already installed"
fi
echo ""

# ============================================================================
# 3. Create awspx wrapper
# ============================================================================
echo "[3/3] Creating awspx wrapper..."

# Create wrapper script that handles sudo and credentials
cat > "$TOOLS_DIR/bin/awspx" << 'EOF'
#!/bin/bash
# Wrapper for awspx that handles sudo and credentials automatically

# Export AWS credentials if they exist in files
if [ -f ~/.aws/credentials ]; then
    export AWS_ACCESS_KEY_ID=$(grep -A2 "\[default\]" ~/.aws/credentials 2>/dev/null | grep aws_access_key_id | cut -d'=' -f2 | tr -d ' ')
    export AWS_SECRET_ACCESS_KEY=$(grep -A2 "\[default\]" ~/.aws/credentials 2>/dev/null | grep aws_secret_access_key | cut -d'=' -f2 | tr -d ' ')
    SESSION_TOKEN=$(grep -A3 "\[default\]" ~/.aws/credentials 2>/dev/null | grep aws_session_token | cut -d'=' -f2 | tr -d ' ')
    if [ -n "$SESSION_TOKEN" ]; then
        export AWS_SESSION_TOKEN="$SESSION_TOKEN"
        export AWS_SECURITY_TOKEN="$SESSION_TOKEN"
    fi
fi

# Call the system awspx with sudo -E (preserve environment)
sudo -E /usr/local/bin/awspx "$@"
EOF
chmod +x "$TOOLS_DIR/bin/awspx"
echo "  ✓ awspx wrapper created"
echo ""

# ============================================================================
# Update shell configuration
# ============================================================================
echo "Adding tools to PATH..."
if ! grep -q "security-tools/bin" ~/.bashrc 2>/dev/null; then
    echo '' >> ~/.bashrc
    echo '# Security tools' >> ~/.bashrc
    echo 'export PATH="$HOME/security-tools/bin:$PATH"' >> ~/.bashrc
    echo "  ✓ Added to ~/.bashrc"
else
    echo "  ✓ Already in ~/.bashrc"
fi

# Also add for current shell session
export PATH="$HOME/security-tools/bin:$PATH"
echo ""

# ============================================================================
# Validation
# ============================================================================
echo "=== Validating Installation ==="
echo ""

echo "▸ terraform:"
terraform version 2>&1 | head -1
echo ""

echo "▸ pmapper:"
pmapper --help 2>&1 | head -2
echo ""

echo "▸ awspx:"
if awspx --help 2>&1 | head -2; then
    echo "  ✓ awspx wrapper is working"
fi
echo ""

echo "=== Installation Complete! ==="
echo ""
echo "✓ All tools ready to use:"
echo "  • terraform"
echo "  • pmapper"
echo "  • awspx  (automatically handles sudo)"
echo ""
echo "For new sessions, run: source ~/.bashrc"
echo "Or just start a new shell session"
echo ""

# 5. apply lab terraform modules
# cd /home/ssm-user/ws-wrangling-identity-and-access-in-aws/labs/terraform
# echo "[5/5] Applying lab terraform modules..."
# terraform init
# terraform apply --auto-approve
# echo "✓ lab terraform modules applied"