#!/bin/bash

# Certificate Renewal and Deployment Script
# Checks Let's Encrypt certificates and renews if expiring soon
# Then deploys renewed certificates via Ansible

set -e  # Exit on error

# Color codes for output
red='\033[0;31m'
green='\033[0;32m'
yellow='\033[1;33m'
blue='\033[0;34m'
nc='\033[0m' # No Color

# Configuration
letsencrypt_live_dir="/etc/letsencrypt/live"
renewal_threshold_days=14
ansible_home='~/ansible_home'
ansible_playbook_dir="$ansible_home/playbooks"
ansible_playbook="deploy_webmin_cert.yml"
inventory_file="$ansible_home/inventory/default_inventory"

# Function to print colored output
print_info() {
    echo -e "${blue}[INFO]${nc} $1"
}

print_success() {
    echo -e "${green}[SUCCESS]${nc} $1"
}

print_warning() {
    echo -e "${yellow}[WARNING]${nc} $1"
}

print_error() {
    echo -e "${red}[ERROR]${nc} $1"
}

# Function to disable Snap's auto-renewal timer
disable_snap_auto_renew() {
    local timer_name="snap.certbot.renew.timer"
    local service_name="snap.certbot.renew.service"
    
    print_info "Checking for Snap auto-renewal timer..."
    
    # Check if the timer exists
    if sudo systemctl list-unit-files | grep -q "$timer_name"; then
        print_info "Found Snap timer: $timer_name"
        
        # Check if timer is active
        timer_status=$(sudo systemctl is-active "$timer_name" 2>/dev/null || echo "inactive")
        if [[ "$timer_status" == "active" ]]; then
            print_warning "Snap auto-renewal timer is active. Disabling to prevent conflicts..."
            
            # Stop and disable the timer
            if sudo systemctl stop "$timer_name" && sudo systemctl disable "$timer_name"; then
                print_success "Successfully stopped and disabled $timer_name"
            else
                print_error "Failed to disable $timer_name"
                return 1
            fi
            
            # Optionally stop the service too
            if sudo systemctl stop "$service_name" && sudo systemctl disable "$service_name"; then
                print_info "Also disabled associated service: $service_name"
            fi
        else
            print_success "Snap timer is already inactive"
        fi
    else
        print_info "No Snap auto-renewal timer found"
    fi
    
    # Double-check by listing timers
    print_info "Current Certbot-related timers:"
    sudo systemctl list-timers | grep -i certbot || print_info "No active Certbot timers found"
    
    return 0
}

# Function to check if NOT running as root
check_not_root() {
    if [[ $EUID -eq 0 ]]; then
        print_error "This script should NOT be run as root"
        echo "Please run as a regular user with sudo privileges"
        exit 1
    fi
}

# Function to check certificate expiration (no sudo needed for read)
check_cert_expiration() {
    local cert_file="$1"
    local domain="$2"
    
    if [[ ! -f "$cert_file" ]]; then
        print_warning "Certificate file not found: $cert_file"
        return 2
    fi
    
    # Get expiration date in seconds since epoch
    local expiry_date
    expiry_date=$(openssl x509 -enddate -noout -in "$cert_file" 2>/dev/null | cut -d= -f2)
    
    if [[ -z "$expiry_date" ]]; then
        print_warning "Could not read expiration date for: $domain"
        return 2
    fi
    
    # Convert to epoch seconds
    local expiry_epoch
    if command -v date &> /dev/null; then
        # Try GNU date first
        expiry_epoch=$(date -d "$expiry_date" +%s 2>/dev/null || 
                      date -j -f "%b %d %T %Y %Z" "$expiry_date" +%s 2>/dev/null)
    else
        print_warning "Date command not available"
        return 2
    fi
    
    if [[ -z "$expiry_epoch" ]]; then
        print_warning "Could not parse expiration date for: $domain"
        return 2
    fi
    
    local current_epoch
    current_epoch=$(date +%s)
    local days_until_expiry
    days_until_expiry=$(( (expiry_epoch - current_epoch) / 86400 ))
    
    echo "$days_until_expiry"
    return 0
}

# Function to renew certificate (requires sudo)
renew_certificate() {
    local domain="$1"
    
    print_info "Renewing certificate for: $domain"
    
    # Run certbot renew for specific domain with sudo
    if sudo certbot renew --cert-name "$domain" --quiet; then
        print_success "Certificate renewed for: $domain"
        return 0
    else
        print_error "Failed to renew certificate for: $domain"
        return 1
    fi
}

# Function to deploy certificate via Ansible (no sudo needed, ansible uses become)
deploy_certificate() {
    local domain="$1"
    
    print_info "Deploying certificate to: $domain via Ansible"
    
    # Change to ansible directory if needed
    local original_dir
    original_dir=$(pwd)
    
    if [[ -d "$ansible_playbook_dir" ]]; then
        cd "$ansible_playbook_dir" || {
            print_error "Cannot cd to $ansible_playbook_dir"
            return 1
        }
    fi
    
    # Run ansible playbook for this specific host (no sudo needed)
    if ansible-playbook -i "$inventory_file" -l "$domain" "$ansible_playbook" -v; then
        print_success "Certificate deployed to: $domain"
        cd "$original_dir" || return 0
        return 0
    else
        print_error "Failed to deploy certificate to: $domain"
        cd "$original_dir" || return 1
        return 1
    fi
}

# Main function
main() {
    print_info "Starting certificate renewal check"
    
    # Check if NOT running as root
    check_not_root

    # Disable Snap's auto-renewal to prevent conflicts
    disable_snap_auto_renew
    
    # Check if Let's Encrypt directory exists and is readable
    if [[ ! -d "$letsencrypt_live_dir" ]]; then
        print_error "Let's Encrypt live directory not found: $letsencrypt_live_dir"
        exit 1
    fi
    
    if [[ ! -r "$letsencrypt_live_dir" ]]; then
        print_error "Cannot read Let's Encrypt directory: $letsencrypt_live_dir"
        print_info "Trying with sudo for directory listing..."
        
        # Try to list directories with sudo
        local sudo_domains
        sudo_domains=$(sudo ls -d "$letsencrypt_live_dir"/*/ 2>/dev/null | grep -v README | xargs -I {} basename {} || echo "")
        
        if [[ -z "$sudo_domains" ]]; then
            print_error "Cannot access certificate directories even with sudo"
            exit 1
        fi
        
        # Convert to array
        local domains=()
        while IFS= read -r domain; do
            [[ -n "$domain" ]] && domains+=("$domain")
        done <<< "$sudo_domains"
    else
        # Get list of domains (directories in live folder, excluding README)
        local domains=()
        for item in "$letsencrypt_live_dir"/*; do
            if [[ -d "$item" ]] && [[ "$item" != "$letsencrypt_live_dir/README" ]]; then
                local domain_name
                domain_name=$(basename "$item")
                domains+=("$domain_name")
            fi
        done
    fi
    
    if [[ ${#domains[@]} -eq 0 ]]; then
        print_warning "No domains found in $letsencrypt_live_dir"
        exit 0
    fi
    
    print_info "Found ${#domains[@]} domains:"
    printf '  - %s\n' "${domains[@]}"
    echo ""
    
    local renewed_domains=()
    local failed_domains=()
    
    # Check each domain
    for domain in "${domains[@]}"; do
        local cert_file="$letsencrypt_live_dir/$domain/cert.pem"
        
        print_info "Checking certificate for: $domain"
        
        # First check if we can read the cert file without sudo
        local can_read_cert=false
        
        if [[ -r "$cert_file" ]]; then
            can_read_cert=true
        else
            # Try with sudo
            print_info "Certificate file not readable, trying with sudo..."
            if sudo test -f "$cert_file"; then
                can_read_cert=true
                # Use sudo to read the cert
                cert_file="<(sudo cat \"$letsencrypt_live_dir/$domain/cert.pem\")"
            fi
        fi
        
        if [[ "$can_read_cert" = false ]]; then
            print_warning "Cannot read certificate for: $domain"
            failed_domains+=("$domain (cannot read cert)")
            continue
        fi
        
        # Check expiration
        local days_until_expiry
        if [[ "$cert_file" == "<("* ]]; then
            # Using sudo cat via process substitution
            days_until_expiry=$(bash -c "openssl x509 -enddate -noout -in $cert_file 2>/dev/null | cut -d= -f2" | 
                xargs -I {} date -d "{}" +%s 2>/dev/null | 
                awk -v now="$(date +%s)" '{print ($1 - now) / 86400}')
        else
            # Normal file path
            days_until_expiry=$(check_cert_expiration "$cert_file" "$domain")
        fi
        
        if [[ $? -eq 2 ]] || [[ -z "$days_until_expiry" ]]; then
            # Error reading certificate
            print_warning "Error checking expiration for: $domain"
            failed_domains+=("$domain (read error)")
            continue
        fi
        
        # Convert to integer
        days_until_expiry_int=$(printf "%.0f" "$days_until_expiry")
        
        print_info "Certificate expires in $days_until_expiry_int days"
        
        if [[ "$days_until_expiry_int" -le "$renewal_threshold_days" ]]; then
            print_warning "Certificate for $domain expires in $days_until_expiry_int days (threshold: $renewal_threshold_days days)"
            
            # Renew certificate (requires sudo)
            if renew_certificate "$domain"; then
                renewed_domains+=("$domain")
                
                # Deploy renewed certificate (ansible uses become)
                if deploy_certificate "$domain"; then
                    print_success "Successfully renewed and deployed certificate for: $domain"
                else
                    print_error "Renewed but failed to deploy certificate for: $domain"
                    failed_domains+=("$domain (deploy failed)")
                fi
            else
                print_error "Failed to renew certificate for: $domain"
                failed_domains+=("$domain (renew failed)")
            fi
        else
            print_success "Certificate for $domain is valid for $days_until_expiry_int days (no renewal needed)"
        fi
        
        echo ""
    done
    
    # Summary
    print_info "========== RENEWAL SUMMARY =========="
    echo ""
    
    if [[ ${#renewed_domains[@]} -gt 0 ]]; then
        print_success "Successfully renewed ${#renewed_domains[@]} domain(s):"
        printf '  - %s\n' "${renewed_domains[@]}"
        echo ""
    fi
    
    if [[ ${#failed_domains[@]} -gt 0 ]]; then
        print_error "Failed to process ${#failed_domains[@]} domain(s):"
        printf '  - %s\n' "${failed_domains[@]}"
        echo ""
    fi
    
    if [[ ${#renewed_domains[@]} -eq 0 ]] && [[ ${#failed_domains[@]} -eq 0 ]]; then
        print_success "All certificates are valid. No renewals needed."
    fi
    
    print_info "Certificate check completed"
}

# Run main function
main "$@"