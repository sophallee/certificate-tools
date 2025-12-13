#!/bin/bash

# Certbot Installation Script for AlmaLinux with Cloudflare DNS Support
# Created: $(date)
# Author: slee

set -e  # Exit on error

# Configuration file
config_file="setup.properties"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
config_path="${script_dir}/${config_file}"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values (will be overridden by config file)
username=''
dns_zone=''
domain=''
email=''
cloudflare_api_token=''

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

# Function to load configuration from properties file
load_config() {
    if [[ ! -f "$config_path" ]]; then
        print_error "Configuration file '$config_file' not found in script directory."
        echo "Creating template configuration file..."
        create_config_template
        exit 1
    fi
    
    # Check if config file is readable
    if [[ ! -r "$config_path" ]]; then
        print_error "Cannot read configuration file '$config_file'. Check permissions."
        exit 1
    fi
    
    # Load configuration
    print_header "Loading configuration from ${config_file}"
    
    # Source the config file
    # Using a safer approach to parse the config file
    while IFS='=' read -r key value; do
        # Skip comments and empty lines
        [[ $key =~ ^[[:space:]]*# ]] && continue
        [[ -z $key ]] && continue
        
        # Remove quotes and trim spaces
        key=$(echo "$key" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//;s/"//g;s/'"'"'//g')
        value=$(echo "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//;s/"//g;s/'"'"'//g')
        
        case "$key" in
            username)
                username="$value"
                ;;
            dns_zone)
                dns_zone="$value"
                ;;
            domain)
                domain="$value"
                ;;
            email)
                email="$value"
                ;;
            cloudflare_api_token)
                cloudflare_api_token="$value"
                ;;
            *)
                print_warning "Unknown configuration key: $key"
                ;;
        esac
    done < "$config_path"
    
    # Validate required configuration
    validate_config
}

# Function to create a template configuration file
create_config_template() {
    cat > "${script_dir}/${config_file}.template" << 'EOF'
# Certbot Installation Configuration
# Copy this file to 'setup.properties' and edit the values

# User configuration
username='username'
dns_zone='example.com'
domain='certbot.example.com'
email='admin@example.com'

# IMPORTANT: Replace YOUR_CLOUDFLARE_API_TOKEN_HERE with your actual token
# Get your token from Cloudflare Dashboard: https://dash.cloudflare.com/profile/api-tokens
# Token needs: Zone.DNS Edit permissions
cloudflare_api_token='YOUR_CLOUDFLARE_API_TOKEN_HERE'
EOF
    
    print_success "Template configuration file created: ${config_file}.template"
    echo "Please copy it to '${config_file}' and edit the values before running the script."
}

# Function to validate configuration
validate_config() {
    local missing_configs=()
    
    [[ -z "$username" ]] && missing_configs+=("username")
    [[ -z "$dns_zone" ]] && missing_configs+=("dns_zone")
    [[ -z "$domain" ]] && missing_configs+=("domain")
    [[ -z "$email" ]] && missing_configs+=("email")
    
    if [[ ${#missing_configs[@]} -gt 0 ]]; then
        print_error "Missing required configuration in ${config_file}:"
        printf '  - %s\n' "${missing_configs[@]}"
        exit 1
    fi
    
    # Check for placeholder API token
    if [[ "$cloudflare_api_token" == "YOUR_CLOUDFLARE_API_TOKEN_HERE" ]] || [[ -z "$cloudflare_api_token" ]]; then
        print_error "Please update 'cloudflare_api_token' in ${config_file} with your actual Cloudflare API token"
        echo "Get your token from: https://dash.cloudflare.com/profile/api-tokens"
        echo "Required permissions: Zone.DNS Edit"
        exit 1
    fi
    
    # Show loaded configuration (masking API token)
    masked_token="${cloudflare_api_token:0:8}...${cloudflare_api_token: -4}"
    echo "✓ username: $username"
    echo "✓ dns_zone: $dns_zone"
    echo "✓ domain: $domain"
    echo "✓ email: $email"
    echo "✓ cloudflare_api_token: $masked_token"
    echo ""
}

# Function to save configuration back to file (if needed)
save_config() {
    cat > "$config_path" << EOF
# Certbot Installation Configuration
# Generated on $(date)

# User configuration
username='$username'
dns_zone='$dns_zone'
domain='$domain'
email='$email'

# Cloudflare API Token
cloudflare_api_token='$cloudflare_api_token'
EOF
    
    chmod 600 "$config_path"
    print_success "Configuration saved to ${config_file}"
}

# Load configuration at script start
load_config

# Check if running as root
if [[ $EUID -eq 0 ]]; then
    print_error "This script should not be run as root. Please run as a regular user with sudo privileges."
    exit 1
fi

# Verify user exists
if ! id "$username" &>/dev/null; then
    print_error "User '$username' does not exist. Please update the username in ${config_file}."
    exit 1
fi

print_header "Certbot Installation Script for AlmaLinux with Cloudflare DNS"
echo "Configuration loaded from: $config_path"
echo ""
echo "This script will:"
echo "1. Remove old Certbot (RPM/DNF version)"
echo "2. Install and configure Snapd"
echo "3. Install Certbot and Cloudflare plugin via Snap"
echo "4. Configure sudo secure_path for Snap"
echo "5. Create secrets directory and store Cloudflare API token"
echo "6. Update user PATH for Snap"
echo "7. Issue SSL Certificate via DNS challenge"
echo "8. Set up automatic renewal"
echo ""
read -p "Continue? (y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    print_warning "Installation cancelled."
    exit 0
fi

# Function to handle errors
handle_error() {
    print_error "Command failed at line $1. Check logs for details."
    exit 1
}

trap 'handle_error $LINENO' ERR

print_header "🧹 1. Removing old Certbot (RPM/DNF version)"
if rpm -q certbot &>/dev/null; then
    sudo dnf remove certbot -y
    print_success "Old Certbot removed"
else
    print_success "Certbot not installed via DNF"
fi

print_header "📦 2. Installing and configuring Snapd"
sudo dnf install epel-release -y
print_success "EPEL repository installed"

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

print_header "🔐 5. Creating secrets directory and storing Cloudflare API token"
secrets_dir="/home/${username}/.secrets"
certbot_secrets_dir="${secrets_dir}/certbot"

# Create directories
sudo mkdir -p "$certbot_secrets_dir"
sudo chown -R $username:$username "$secrets_dir"
sudo chmod -R 700 "$secrets_dir"
print_success "Secrets directory created at $secrets_dir"

# Create Cloudflare API token file
certbot_secrets_ini_file="${certbot_secrets_dir}/${dns_zone}.ini"

echo "dns_cloudflare_api_token = $cloudflare_api_token" | sudo tee "$certbot_secrets_ini_file" > /dev/null
sudo chmod 600 "$certbot_secrets_ini_file"
print_success "Cloudflare API token stored at $certbot_secrets_ini_file"

print_header "🔁 6. Ensuring Snap bin is in your user PATH"
# Check if PATH already contains /snap/bin
if grep -q "/snap/bin" ~/.bash_profile; then
    print_success "/snap/bin already in PATH"
else
    echo 'export PATH=$PATH:/snap/bin' >> ~/.bash_profile
    print_success "/snap/bin added to ~/.bash_profile"
fi

# Source bash_profile for current session
source ~/.bash_profile

print_header "📥 7. Issuing SSL Certificate via Certbot with DNS Challenge"
cloud_flare_api="/home/${username}/.secrets/certbot/${dns_zone}.ini"

echo "Domain: $domain"
echo "Email: $email"
echo "Cloudflare API file: $cloud_flare_api"
echo ""

read -p "Proceed with certificate issuance? (y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    print_warning "Certificate issuance skipped. You can run it manually later."
else
    sudo certbot certonly \
        --dns-cloudflare \
        --dns-cloudflare-credentials "$cloud_flare_api" \
        --preferred-challenges dns \
        --agree-tos \
        --email "$email" \
        -d "$domain"
    
    if [ $? -eq 0 ]; then
        print_success "SSL certificate successfully issued for $domain"
        
        # Show certificate info
        echo ""
        print_header "Certificate Information:"
        sudo certbot certificates | grep -A 3 "$domain"
    else
        print_error "Certificate issuance failed. Please check the error messages above."
    fi
fi

print_header "🔄 8. Setting up Automatic Renewal"
echo ""
echo "Select automatic renewal method:"
echo "1) Use Snap's built-in systemd timer (Recommended)"
echo "2) Set up cron job"
echo "3) Skip for now"
read -p "Enter choice (1-3): " renewal_choice

case $renewal_choice in
    1)
        print_header "✅ Option 1: Using Snap's Built-in systemd Timer"
        echo "Checking existing Certbot timers..."
        sudo systemctl list-timers | grep -i certbot || echo "No Certbot timers found"
        
        # Test renewal
        echo ""
        print_warning "Testing certificate renewal (dry-run)..."
        sudo certbot renew --dry-run
        
        if [ $? -eq 0 ]; then
            print_success "Renewal test successful! Snap's timer will handle automatic renewal."
        else
            print_error "Renewal test failed. Please check logs and configure manually."
        fi
        ;;
    2)
        print_header "✅ Option 2: Cron Job Setup"
        cron_job="0 3 * * * sudo certbot renew --quiet --dns-cloudflare --dns-cloudflare-credentials $cloud_flare_api >> /var/log/letsencrypt/renew.log 2>&1"
        
        # Create log directory
        sudo mkdir -p /var/log/letsencrypt
        
        # Add to crontab
        (crontab -l 2>/dev/null | grep -v "certbot renew"; echo "$cron_job") | crontab -
        
        print_success "Cron job added:"
        echo "$cron_job"
        echo ""
        print_warning "Note: You may need to manually restart services (e.g., Nginx) after certificate renewal."
        ;;
    3)
        print_warning "Automatic renewal setup skipped."
        ;;
    *)
        print_error "Invalid choice. Skipping automatic renewal setup."
        ;;
esac

print_header "📋 Installation Summary"
echo ""
echo "✅ Installation completed!"
echo ""
echo "Important information:"
echo "• Configuration file: $config_path"
echo "• Cloudflare API token stored at: $certbot_secrets_ini_file"
echo "• Certificate for domain: $domain"
echo "• Renewal test command: sudo certbot renew --dry-run"
echo ""
echo "Next steps:"
echo "1. Configure your web server (Nginx/Apache) to use the certificate"
echo "2. Test SSL configuration at: https://www.ssllabs.com/ssltest/"
echo "3. Monitor renewal logs: sudo tail -f /var/log/letsencrypt/letsencrypt.log"
echo ""
echo "Certificate locations (typically):"
echo "• Certificate: /etc/letsencrypt/live/$domain/fullchain.pem"
echo "• Private key: /etc/letsencrypt/live/$domain/privkey.pem"
echo ""
print_success "Script execution completed!"