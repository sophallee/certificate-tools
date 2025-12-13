#!/bin/bash

# Debug version - minimal script to process all domains

config_file=""
domain_list_file=""
domains=()

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -c|--config) config_file="$2"; shift 2 ;;
        -l|--list) domain_list_file="$2"; shift 2 ;;
        -n) non_interactive=true; shift ;;
        -f) force_renew=true; shift ;;
        *) shift ;;
    esac
done

# Load config
source "$config_file" 2>/dev/null || {
    echo "ERROR: Cannot load config file: $config_file"
    exit 1
}

# Load domains
if [[ -f "$domain_list_file" ]]; then
    while read -r line; do
        [[ -z "$line" ]] && continue
        [[ "$line" == \#* ]] && continue
        domains+=("$line")
    done < "$domain_list_file"
fi

echo "Processing ${#domains[@]} domains..."

# Setup once
mkdir -p "/home/$username/.secrets/certbot"
echo "dns_cloudflare_api_token = $cloudflare_api_token" > "/home/$username/.secrets/certbot/$dns_zone.ini"
chmod 600 "/home/$username/.secrets/certbot/$dns_zone.ini"

# Process each domain
for domain in "${domains[@]}"; do
    echo ""
    echo "=== Processing: $domain ==="
    
    # Build command
    cmd="sudo certbot certonly \
        --dns-cloudflare \
        --dns-cloudflare-credentials /home/$username/.secrets/certbot/$dns_zone.ini \
        --preferred-challenges dns \
        --agree-tos \
        --email $email \
        -d $domain"
    
    [[ "$non_interactive" = true ]] && cmd="$cmd --non-interactive"
    [[ "$force_renew" = true ]] && cmd="$cmd --force-renewal"
    
    # Run command
    echo "Running: $cmd"
    eval "$cmd"
    
    # Check result
    if [[ -d "/etc/letsencrypt/live/$domain" ]]; then
        echo "✅ SUCCESS: Certificate created for $domain"
    else
        echo "⚠️  WARNING: Certificate may not have been created for $domain"
    fi
done

echo ""
echo "=== DONE ==="
echo "Processed ${#domains[@]} domains."