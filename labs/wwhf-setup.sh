#!/bin/bash
# wwhf-setup.sh
# Makes awspx, pmapper, and terraform available to ssm-user

set -e  # Exit on error

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
echo "  • sudo awspx  (requires sudo)"
echo ""