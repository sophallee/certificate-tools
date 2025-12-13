## Certbot Automation for AlmaLinux

Automated Certbot installation and SSL certificate generation using Cloudflare DNS validation.

### 🚀 Quick Start

1. Install Dependencies
```
chmod +x certbot-installer.sh
./certbot-installer.sh
```

2. Create Configuration
```
# Copy template for each domain zone
cp example-com.properties.template example-com.properties
nano example-com.properties  # Edit with your settings
```
Configuration format (example-com.properties):
```
username='youruser'
dns_zone='example.com'
email='admin@example.com'
cloudflare_api_token='YOUR_TOKEN_HERE'
```

3. Create Domain List (Optional)
```
# example-list.txt
sub1.example.com
sub2.example.com
api.example.com
```

4. Generate Certificates
Single domain:
```
./certbot-generator.sh -c example-com.properties -d sub1.example.com
```

Batch domains:
```
./certbot-generator.sh -c example-com.properties -l example-list.txt
```

Non-interactive (for automation):
```
./certbot-generator.sh -c example-com.properties -l example-list.txt -n -f
```


### ⚙️ Options

Option	Description
-c FILE	Configuration file (required)
-d DOMAIN	Single domain
-l FILE	Domain list file
-n	Non-interactive mode
-f	Force renewal

### 📁 Files

- certbot-installer.sh - Installs Certbot and dependencies
- certbot-generator.sh - Generates SSL certificates
- *.properties - Domain zone configurations
- *.txt - Domain lists

### 🔄 Renewal

Certificates auto-renew via Snap's systemd timer. Test with:
```
sudo certbot renew --dry-run
```

### 🔒 Security

- Never commit .properties files to Git
- Set permissions: chmod 600 *.properties
- Use separate API tokens per domain zone

### ❓ Help

```
./certbot-generator.sh -h
```

Certificates stored in: /etc/letsencrypt/live/[domain]/