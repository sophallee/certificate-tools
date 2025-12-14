# Certificate Renewal and Management System

This project provides a complete automation solution for managing Let's Encrypt SSL certificates on AlmaLinux systems using Cloudflare DNS validation. The system includes installation, certificate generation, and automated deployment to Webmin servers via Ansible.

📋 Project Structure

```text
.
├── certbot-installer.sh          # Certbot and dependency installer
├── certbot-generator.sh          # Certificate generation and batch processing
├── setup.properties.template     # Configuration template for domain zones
├── check-and-renew-certs.sh      # Automated renewal and deployment script
├── README.md                     # This documentation
└── examples/
    ├── example-com.properties    # Sample config for example.com zone
    ├── example-com.list.template # Sample domain list for batch processing
```


## 🚀 Quick Start

1. Install Dependencies
```bash
chmod +x certbot-installer.sh
./certbot-installer.sh
```

2. Create Configuration
```bash
# Copy template for each domain zone
cp examples/example-com.properties.template example-com.properties
cp examples/example-com.list.template  example-com.list
vim example-com.properties  # Edit with your settings
```

Configuration format (example-com.properties):
```bash
username='youruser'
dns_zone='example.com'
email='admin@example.com'
cloudflare_api_token='YOUR_TOKEN_HERE'
```

3. Create Domain List (Optional)
```bash
# example-list.txt
sub1.example.com
sub2.example.com
api.example.com
```

4. Generate Certificates
Single domain:
```bash
./certbot-generator.sh -c example-com.properties -d sub1.example.com
```

Batch domains:
```bash
./certbot-generator.sh -c example-com.properties -l example-list.txt
```

Non-interactive (for automation):
```bash
./certbot-generator.sh -c example-com.properties -l example-list.txt -n -f
```


## ⚙️ Options

Option	Description
-c FILE	Configuration file (required)
-d DOMAIN	Single domain
-l FILE	Domain list file
-n	Non-interactive mode
-f	Force renewal

## 📁 Files

- certbot-installer.sh - Installs Certbot and dependencies
- certbot-generator.sh - Generates SSL certificates
- *.properties - Domain zone configurations
- *.list - Domain lists

## 🔄 Set Up Automated Renewal and Deployment

```bash
chmod +x check-and-renew-certs.sh
crontab -e
# Add: 0 3 * * * /path/to/check-and-renew-certs.sh >> /home/user/cert-renewal.log 2>&1
```

## 🔒 Script Details

### certbot-installer.sh

Installs and configures Certbot via Snap on AlmaLinux systems with Cloudflare DNS support.

Features:
- Removes old Certbot (RPM/DNF versions)
- Installs and configures Snapd
- Installs Certbot and Cloudflare DNS plugin via Snap
- Configures system paths and permissions

### certbot-generator.sh

Generates SSL certificates using Cloudflare DNS validation with support for multiple domains and batch processing.

Usage:

```bash
# Single domain
./certbot-generator.sh -c example-com.properties -d sub1.example.com

# Batch processing (non-interactive)
./certbot-generator.sh -c example-com.properties -l domains.txt -n

# Force renewal of existing certificates
./certbot-generator.sh -c example-com.properties -l domains.txt -n -f
```

Command Line Options:
- -c, --config FILE - Configuration properties file (required)
- -d, --domain DOMAIN - Generate certificate for single domain
- -l, --list FILE - File containing list of domains
- -n, --non-interactive - Run without prompts (for automation)
- -f, --force - Force renewal if certificate exists

### check-and-renew-certs.sh

Automated certificate renewal and deployment script that:
1. Checks certificate expiration dates
2. Renews certificates expiring within 14 days
3. Deploys renewed certificates to Webmin via Ansible
4. Disables Snap's auto-renewal timer to prevent conflicts

Key Features:
- Runs as non-root user (uses sudo only where needed)
- Automatic conflict prevention with Snap's timer
- Integrates with Ansible for certificate deployment
- Comprehensive logging and error handling

## 🔧 Configuration Management

### Domain Zone Configuration

Each DNS zone requires its own properties file:

example-com.properties:
```bash
username='username'
dns_zone='example.com'
email='admin@example.com'
cloudflare_api_token='YOUR_TOKEN_HERE'
```

### Domain List Files

Create text files with one domain per line for batch processing:

domains.list:
```text
sub1.example.com
sub2.example.com
api.example.com
app.example.com
www.example.com
```

## 🔒 Security Best Practices

File Permissions:
```bash
chmod 600 *.properties
chmod 700 ~/.secrets
chmod 600 ~/.secrets/certbot/*.ini
```

Git Safety (add to .gitignore):
```
gitignore
# Configuration files
*.properties
!setup.properties.template

# Domain lists
*.txt
!*.txt.example

# Secrets
.secrets/
```

API Token Security:
- Use least privilege principle (Zone.DNS Edit permissions only)
- Use separate tokens for different security zones
- Rotate tokens periodically
- Never commit tokens to version control

## 🐛 Troubleshooting

### Common Issues

"certbot command not found"

```bash
# Add Snap to PATH
export PATH=$PATH:/snap/bin
echo 'export PATH=$PATH:/snap/bin' >> ~/.bash_profile
```
"Permission denied" when accessing certificates
```bash
# The script runs as non-root. Certificates may need different permissions
# or the script uses sudo for specific operations
```

Certbot renewal fails

``` bash
# Check logs
sudo journalctl -u snap.certbot.renew
sudo tail -f /var/log/letsencrypt/letsencrypt.log

# Test renewal manually
sudo certbot renew --dry-run
```


### Debug Mode

```bash
# Run generator in debug mode
bash -x certbot-generator.sh -c example-com.properties -d test.example.com

# Run renewal check with maximum verbosity
./check-and-renew-certs.sh 2>&1 | tee debug.log
```

### 📝 Log Files

- Certificate generation: /var/log/letsencrypt/letsencrypt.log
- Auto-renewal script: ~/cert-renewal.log (configurable in crontab)
- Ansible deployments: Check ansible playbook output
- System logs: journalctl -u snap.certbot.renew

## 🔗 Dependencies
- AlmaLinux 8/9 (or other RHEL-based distributions)
- Sudo privileges for the user running scripts
- Cloudflare account with domains configured
- Cloudflare API Token with DNS edit permissions
- Ansible for certificate deployment (optional, for Webmin deployment)

## 🤝 Contributing

- Report issues with detailed error messages and logs
- Test changes in a staging environment first
- Follow the established script structure and variable naming conventions
- Update documentation for any new features

## 📄 License

This project is provided as-is for educational and operational purposes. Use at your own risk in production environments.

## 🙏 Acknowledgments

- Let's Encrypt for free SSL certificates
- Certbot for ACME client
- Cloudflare for DNS services
- AlmaLinux for the enterprise-grade Linux distribution

Note: Always test in a staging environment before production use. Keep backups of important configuration files and certificates.