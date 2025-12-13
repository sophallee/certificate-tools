#!/bin/bash

# Certbot Installer Script for AlmaLinux with Cloudflare DNS Support
# This script installs and configures Certbot and its dependencies
# Created: $(date)
# Author: slee

set -e  # Exit on error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_header() {
    echo -e "\n${BLUE}## $1${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

# Function to handle errors
handle_error() {
    print_error "Command failed at line $1. Check logs for details."
    exit 1
}

trap 'handle_error $LINENO' ERR

# Check if running as root
if [[ $EUID -eq 0 ]]; then
    print_error "This script should not be run as root. Please run as a regular user with sudo privileges."
    exit 1
fi

print_header "Certbot Installer for AlmaLinux with Cloudflare DNS"
echo "This script will install and configure:"
echo "1. Snapd package manager"
echo "2. Certbot via Snap"
echo "3. Cloudflare DNS plugin"
echo "4. Required system configurations"
echo ""
read -p "Continue? (y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    print_warning "Installation cancelled."
    exit 0
fi

print_header "🧹 1. Checking for old Certbot (RPM/DNF version)"
if rpm -q certbot &>/dev/null; then
    sudo dnf remove certbot -y
    print_success "Old Certbot removed"
else
    print_success "Certbot not installed via DNF"
fi

print_header "📦 2. Installing and configuring Snapd"
if ! rpm -q epel-release &>/dev/null; then
    sudo dnf install epel-release -y
    print_success "EPEL repository installed"
else
    print_success "EPEL repository already installed"
fi

sudo dnf install snapd -y
print_success "Snapd installed"

sudo systemctl enable --now snapd.socket
print_success "Snapd socket enabled and started"

# Create symbolic links
sudo ln -sf /var/lib/snapd/snap /snap
sudo ln -sf /snap/bin /usr/local/bin/snap
print_success "Symbolic links created"

print_header "🔒 3. Installing Certbot and Cloudflare plugin via Snap"
# Wait a moment for snap to initialize
sleep 2

sudo snap install --classic certbot
print_success "Certbot installed via Snap"

sudo snap set certbot trust-plugin-with-root=ok
print_success "Root trust for plugins enabled"

sudo snap install certbot-dns-cloudflare
print_success "Cloudflare DNS plugin installed"

print_header "🛠️ 4. Updating sudo secure_path for Snap"
# Backup original sudoers file
sudo cp /etc/sudoers /etc/sudoers.backup.$(date +%Y%m%d%H%M%S)

# Create temporary sudoers file
sudo cp /etc/sudoers /tmp/sudoers.edit

# Check if secure_path already contains /snap/bin
if sudo grep -q "secure_path.*/snap/bin" /tmp/sudoers.edit; then
    print_success "secure_path already contains /snap/bin"
else
    sudo sed -i 's|^Defaults\s\+secure_path\s*=\s*\(.*\)|Defaults    secure_path = \1:/snap/bin|' /tmp/sudoers.edit
    # Validate syntax before applying
    if sudo visudo -c -f /tmp/sudoers.edit; then
        sudo cp /tmp/sudoers.edit /etc/sudoers
        print_success "sudo secure_path updated"
    else
        print_error "Failed to update sudoers file. Please check manually."
        exit 1
    fi
fi

print_header "🔁 5. Ensuring Snap bin is in your user PATH"
# Check if PATH already contains /snap/bin
if grep -q "/snap/bin" ~/.bash_profile; then
    print_success "/snap/bin already in PATH"
else
    echo 'export PATH=$PATH:/snap/bin' >> ~/.bash_profile
    print_success "/snap/bin added to ~/.bash_profile"
fi

# Source bash_profile for current session
source ~/.bash_profile

print_header "📋 Installation Summary"
echo ""
echo "✅ Certbot installation completed successfully!"
echo ""
echo "What's installed:"
echo "• Snapd package manager"
echo "• Certbot (via Snap)"
echo "• Cloudflare DNS plugin"
echo "• System configurations"
echo ""
echo "Next steps:"
echo "1. Create a configuration file using the template:"
echo "   cp setup.properties.template setup.properties"
echo "2. Edit setup.properties with your domains and API tokens"
echo "3. Run the certificate generator:"
echo "   ./certbot-generator.sh setup.properties"
echo ""
print_success "Certbot installer completed!"