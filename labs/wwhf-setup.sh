#!/bin/bash
# setup-security-tools.sh
# Makes awspx, pmapper, and terraform available to ssm-user

set -e  # Exit on error

echo "=== Security Tools Setup Script ==="
echo "Setting up awspx, pmapper, and terraform for ssm-user..."

# 1. Fix pmapper venv (install missing dependencies)
echo ""
echo "[1/4] Fixing pmapper virtual environment..."
if [ -d "/home/ubuntu/workspace/PMapper/venv" ]; then
    sudo -u ubuntu bash -c "cd /home/ubuntu/workspace/PMapper && source venv/bin/activate && pip install -q -r requirements.txt"
    echo "✓ pmapper dependencies installed"
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
    echo "✓ terraform already installed ($(terraform version -json | grep -o '"version":"[^"]*' | cut -d'"' -f4))"
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

# 4. Create awspx wrapper (handles sudo automatically)
echo ""
echo "[4/4] Creating awspx wrapper..."
sudo tee /usr/local/bin/awspx-wrapper > /dev/null << 'EOF'
#!/bin/bash
# Wrapper to run awspx with sudo automatically
sudo /usr/local/bin/awspx "$@"
EOF
sudo chmod +x /usr/local/bin/awspx-wrapper
echo "✓ awspx wrapper created"

# 5. Add alias for awspx if user wants to use 'awspx' instead of 'awspx-wrapper'
# (Optional - uncomment if you want 'awspx' to work directly)
if ! grep -q "alias awspx=" ~/.bashrc 2>/dev/null; then
    echo "" >> ~/.bashrc
    echo "# Security tools aliases" >> ~/.bashrc
    echo "alias awspx='sudo /usr/local/bin/awspx'" >> ~/.bashrc
    echo "✓ awspx alias added to ~/.bashrc"
fi

echo ""
echo "=== Setup Complete! ==="
echo ""
echo "Available commands:"
echo "  • terraform --version"
echo "  • pmapper --help"
echo "  • awspx --help  (use 'awspx' if you sourced .bashrc, otherwise 'awspx-wrapper')"
echo ""
echo "To activate the awspx alias in current session, run: source ~/.bashrc"
echo ""