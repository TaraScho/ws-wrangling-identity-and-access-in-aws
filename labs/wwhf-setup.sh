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

# 4. Add awspx alias to bashrc if not present
echo ""
echo "[4/4] Setting up awspx alias..."
if ! grep -q "alias awspx=" ~/.bashrc 2>/dev/null; then
    echo "" >> ~/.bashrc
    echo "# Security tools aliases" >> ~/.bashrc
    echo "alias awspx='sudo /usr/local/bin/awspx'" >> ~/.bashrc
    echo "✓ awspx alias added to ~/.bashrc"
else
    echo "✓ awspx alias already exists"
fi

# Reload bashrc in current shell
alias awspx='sudo /usr/local/bin/awspx'

echo ""
echo "=== Setup Complete! ==="
echo ""
echo "Available commands:"
echo "  • terraform --version"
echo "  • pmapper --help"
echo "  • awspx --help"
echo ""
echo "Note: If 'awspx' alias doesn't work, run: . ~/.bashrc"
echo "      (or just use 'sudo /usr/local/bin/awspx' directly)"
echo ""