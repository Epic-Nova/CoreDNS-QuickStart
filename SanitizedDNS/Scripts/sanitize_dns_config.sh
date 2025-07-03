#!/bin/bash
set -euo pipefail

SOURCE_DIR="/etc/coredns"
EXAMPLE_DOMAIN="example.net"
EXAMPLE_ORG="Example Corp"

# Parse command line arguments
DEST_DIR=""
COMPRESS=false
HELP=false

show_usage() {
    echo "Usage: $0 -o OUTPUT_DIR [OPTIONS]"
    echo ""
    echo "Required:"
    echo "  -o, --output DIR     Set output directory (REQUIRED)"
    echo ""
    echo "Options:"
    echo "  -c, --compress       Create compressed archive instead of directory"
    echo "  -h, --help           Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 -o /tmp/sanitized                 # Output to directory"
    echo "  $0 -o /tmp/sanitized -c              # Create compressed archive"
    echo "  $0 --output /home/user/dns-config    # Long form option"
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -o|--output)
            if [[ -z "${2:-}" ]]; then
                echo "Error: -o/--output requires a directory path"
                show_usage
                exit 1
            fi
            DEST_DIR="$2"
            shift 2
            ;;
        -c|--compress)
            COMPRESS=true
            shift
            ;;
        -h|--help)
            HELP=true
            shift
            ;;
        *)
            echo "Unknown argument: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Check if help was requested or if required parameters are missing
if [[ "$HELP" == true ]]; then
    show_usage
    exit 0
fi

if [[ -z "$DEST_DIR" ]]; then
    echo "Error: Output directory is required"
    echo ""
    show_usage
    exit 1
fi

# Create temporary working directory
TEMP_WORK_DIR=$(mktemp -d -t dns-sanitize.XXXXXX)
trap "rm -rf '$TEMP_WORK_DIR'" EXIT

# Set up working paths
WORK_DIR="$TEMP_WORK_DIR/SanitizedDNS"

# Determine final destination based on whether the target directory is empty
if [[ -d "$DEST_DIR" ]]; then
    # Directory exists, check if it's empty
    if [[ -z "$(ls -A "$DEST_DIR" 2>/dev/null)" ]]; then
        # Directory is empty, use it directly
        FINAL_DEST="$DEST_DIR"
        echo "[*] Using empty directory: $DEST_DIR"
    else
        # Directory is not empty, create SanitizedDNS subdirectory
        FINAL_DEST="$DEST_DIR/SanitizedDNS"
        echo "[*] Directory not empty, creating subdirectory: $FINAL_DEST"
    fi
else
    # Directory doesn't exist, check if parent exists
    PARENT_DIR="$(dirname "$DEST_DIR")"
    if [[ -d "$PARENT_DIR" ]]; then
        # Parent exists, use the specified directory name
        FINAL_DEST="$DEST_DIR"
        echo "[*] Creating new directory: $DEST_DIR"
    else
        # Parent doesn't exist, we'll create the full path
        FINAL_DEST="$DEST_DIR"
        echo "[*] Creating directory path: $DEST_DIR"
    fi
fi

echo "[*] Creating sanitized DNS configuration..."
echo "    Source: $SOURCE_DIR"
echo "    Working in: $TEMP_WORK_DIR"
echo "    Final destination: $FINAL_DEST"
if [[ "$COMPRESS" == true ]]; then
    echo "    Compression: Enabled"
fi

# Remove existing sanitized directory if it exists
if [[ -d "$FINAL_DEST" ]]; then
    echo "[*] Removing existing content at destination..."
    rm -rf "$FINAL_DEST"
fi

# Copy entire source directory to temp location
echo "[*] Copying source directory to temporary workspace..."
cp -r "$SOURCE_DIR" "$WORK_DIR"

# Remove auto-generated directories that should not be copied
echo "[*] Removing auto-generated directories..."
rm -rf "$WORK_DIR/AutoZoneGen" "$WORK_DIR/Cache" "$WORK_DIR/Keys"
echo "[✓] Removed AutoZoneGen, Cache, and Keys directories (will be auto-generated)"

echo "[*] Sanitizing configuration files..."

# Function to sanitize a file
sanitize_file() {
    local file="$1"
    
    # Skip binary files and directories
    if [[ -d "$file" ]] || ! file "$file" | grep -q "text"; then
        return
    fi
    
    echo "  Sanitizing: $(basename "$file")"
    
    # Replace Example Corp references
    sed -i 's/example\.net/example.net/g' "$file"
    sed -i 's/Example Corp/Example Corp/g' "$file"
    sed -i 's/example corp/example corp/g' "$file"
    sed -i 's/example/example/g' "$file"
    sed -i 's/EXAMPLE/EXAMPLE/g' "$file"
    
    # Remove  prefix
    sed -i 's/adi\.example\.net/example.net/g' "$file"
    sed -i 's/adi\.//g' "$file"
    
    # Replace email addresses
    sed -i 's/service@example\.net/admin@example.net/g' "$file"
    sed -i 's/postmaster@example\.net/postmaster@example.net/g' "$file"
    sed -i 's/vulnerabilities@example\.net/security@example.net/g' "$file"
    
    # Replace ALL IP addresses with RFC 5737 documentation addresses
    sed -i 's/37\.114\.63\.124/192.0.2.1/g' "$file"
    sed -i 's/37\.114\.63\.238/192.0.2.2/g' "$file"
    sed -i 's/37\.114\.50\.72/192.0.2.3/g' "$file"
    sed -i 's/5\.253\.247\.229/203.0.113.1/g' "$file"
    
    # Replace GitHub Pages IP addresses
    sed -i 's/185\.199\.108\.153/192.0.2.10/g' "$file"
    sed -i 's/185\.199\.109\.153/192.0.2.11/g' "$file"
    sed -i 's/185\.199\.110\.153/192.0.2.12/g' "$file"
    sed -i 's/185\.199\.111\.153/192.0.2.13/g' "$file"
    
    # Replace ALL IPv6 addresses with RFC 3849 documentation addresses
    sed -i 's/2001:db8::1/2001:db8::1/g' "$file"
    sed -i 's/2001:db8::10/2001:db8::10/g' "$file"
    sed -i 's/2001:db8::11/2001:db8::11/g' "$file"
    sed -i 's/2001:db8::12/2001:db8::12/g' "$file"
    sed -i 's/2001:db8::13/2001:db8::13/g' "$file"
    
    # Replace GitHub usernames/organizations
    sed -i 's/epgenix\.github\.io/example-org.github.io/g' "$file"
    sed -i 's/example-org/example-org/g' "$file"
    
    # Replace server hostnames
    sed -i 's/mirai\./ns1./g' "$file"
    sed -i 's/yusuke\./ns2./g' "$file"
    sed -i 's/mlsrv1\./mail1./g' "$file"
    sed -i 's/mlsrv2\./mail2./g' "$file"
    sed -i 's/gtw1\./gw1./g' "$file"
    sed -i 's/gtw2\./gw2./g' "$file"
    
    # Replace Plesk reference
    sed -i 's/vweb01\.netlixor\.de/hosting.example.net/g' "$file"
}

# Function to sanitize private keys and certificates
sanitize_secrets() {
    local file="$1"
    
    if [[ "$file" == *.private ]] || [[ "$file" == *.key.pem ]]; then
        echo "  Replacing private key: $(basename "$file")"
        cat > "$file" <<EOF
-----BEGIN PRIVATE KEY-----
PRIVATE_KEY_PLACEHOLDER_REMOVED_FOR_SECURITY
-----END PRIVATE KEY-----
EOF
    elif [[ "$file" == *.cert.pem ]] || [[ "$file" == *.ca.pem ]]; then
        echo "  Replacing certificate: $(basename "$file")"
        cat > "$file" <<EOF
-----BEGIN CERTIFICATE-----
CERTIFICATE_PLACEHOLDER_REMOVED_FOR_SECURITY
-----END CERTIFICATE-----
EOF
    elif [[ "$file" == *.key ]] && grep -q "DNSKEY" "$file" 2>/dev/null; then
        echo "  Sanitizing DNSSEC key: $(basename "$file")"
        # Replace the actual key data but keep the structure
        sed -i 's/\(DNSKEY.*13 \)[A-Za-z0-9+/=]*\(.*\)/\1DNSSEC_KEY_PLACEHOLDER_REMOVED_FOR_SECURITY\2/' "$file"
    fi
}

echo "[*] Removing all zones except example.zone..."

# Remove all zone files except example.zone
if [[ -d "$WORK_DIR/Zones" ]]; then
    find "$WORK_DIR/Zones" -name "*.zone" ! -name "example.zone" -delete
    echo "[✓] Removed all zones except example.zone"
fi

echo "[*] Restructuring zone files..."

# Create net directory for example.net
mkdir -p "$WORK_DIR/Zones/net"

# Move and rename example.zone to example.zone
if [[ -f "$WORK_DIR/Zones/net/example.zone" ]]; then
    mv "$WORK_DIR/Zones/net/example.zone" "$WORK_DIR/Zones/net/example.zone"
    echo "[✓] Renamed example.zone to example.zone"
else
    echo "[⚠] example.zone not found"
fi

# Remove empty directories
find "$WORK_DIR/Zones" -type d -empty -delete

# Sanitize all remaining files
find "$WORK_DIR" -type f | while read -r file; do
    sanitize_secrets "$file"
    sanitize_file "$file"
done

echo "[*] Creating comprehensive example zone file..."

# Overwrite the example.zone with a comprehensive template based on the original structure
cat > "$WORK_DIR/Zones/net/example.zone" <<'EOF'
;;
;; Domain:     example.net
;;
;; This is an example DNS zone file for demonstration purposes.
;; Replace all placeholder values with your actual configuration.
;;

;; SOA Record
@   3600    IN      SOA     ns1.example.net. admin.example.net. 2025010101 86400 3600 4000000 86400

;; NS Records
@                               86400   IN  NS  ns1.example.net.
@                               86400   IN  NS  ns2.example.net.

;; A Records

;; Primary nameservers
ns1.example.net.                86400   IN  A   192.0.2.1
ns2.example.net.                86400   IN  A   192.0.2.2

;; Web hosting server
@                               86400   IN  A   203.0.113.1

;; GitHub Pages setup (example for static sites)
@                               604800  IN  A   192.0.2.10
@                               604800  IN  A   192.0.2.11
@                               604800  IN  A   192.0.2.12
@                               604800  IN  A   192.0.2.13

;; Documentation subdomain (example for project docs)
docs.project.example.net.       604800  IN  A   192.0.2.10
docs.project.example.net.       604800  IN  A   192.0.2.11
docs.project.example.net.       604800  IN  A   192.0.2.12
docs.project.example.net.       604800  IN  A   192.0.2.13

;; AAAA Records (IPv6)

;; GitHub Pages IPv6 setup
@                               604800  IN  AAAA    2001:db8::10
@                               604800  IN  AAAA    2001:db8::11
@                               604800  IN  AAAA    2001:db8::12
@                               604800  IN  AAAA    2001:db8::13

;; Documentation subdomain IPv6
docs.project.example.net.       604800  IN  AAAA    2001:db8::10
docs.project.example.net.       604800  IN  AAAA    2001:db8::11
docs.project.example.net.       604800  IN  AAAA    2001:db8::12
docs.project.example.net.       604800  IN  AAAA    2001:db8::13

;; CNAME Records

;; Redirect www to the main domain
www.example.net.                86400   IN  CNAME   example.net.
EOF

echo "[*] Cleaning up configuration files..."

# Skip cleaning AutoZoneGen, Cache, and Keys since we removed them
echo "[✓] Skipped cleaning auto-generated directories (already removed)"

echo "[*] Creating watcher service setup script..."

# Create a setup script for watcher service automation
cat > "$WORK_DIR/setup_watcher.sh" <<'EOF'
#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_SCRIPT="$SCRIPT_DIR/Scripts/install-watcher-service.sh"

echo "[*] Setting up CoreDNS Zone Watcher Service..."

# Check if the install script exists
if [[ ! -f "$INSTALL_SCRIPT" ]]; then
    echo "❌ Error: $INSTALL_SCRIPT not found"
    echo "Please ensure all scripts are properly installed in the Scripts directory."
    exit 1
fi

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    echo "❌ Error: This script must be run as root"
    echo "Please run: sudo $0"
    exit 1
fi

# Make the install script executable
chmod +x "$INSTALL_SCRIPT"
echo "[✓] Made install-watcher-service.sh executable"

# Install the watcher service
echo "[*] Installing zone watcher service..."
if "$INSTALL_SCRIPT" install; then
    echo "[✅] Zone watcher service installed and started successfully!"
    
    echo ""
    echo "Service Status:"
    "$INSTALL_SCRIPT" status
    
    echo ""
    echo "[✅] Setup complete!"
    echo "The zone watcher service will:"
    echo "- Monitor zone files for changes automatically"
    echo "- Regenerate DNSSEC keys and configurations as needed"
    echo "- Reload CoreDNS when changes are detected"
    echo "- Run continuously in the background"
    echo ""
    echo "Management commands:"
    echo "  sudo $INSTALL_SCRIPT status     # Check service status"
    echo "  sudo $INSTALL_SCRIPT logs       # View recent logs"
    echo "  sudo $INSTALL_SCRIPT restart    # Restart the service"
    echo "  sudo $INSTALL_SCRIPT stop       # Stop the service"
    echo "  sudo $INSTALL_SCRIPT start      # Start the service"
    echo "  sudo $INSTALL_SCRIPT uninstall  # Remove the service"
    echo ""
    echo "Manual zone generation:"
    echo "  $SCRIPT_DIR/Scripts/generate_all_zones.sh"
else
    echo "❌ Failed to install zone watcher service"
    echo "Check the error messages above and try again."
    exit 1
fi
EOF

chmod +x "$WORK_DIR/setup_watcher.sh"
echo "[✓] Created setup_watcher.sh script"

echo "[*] Updating configuration files to reference new paths..."

# Update any remaining configuration files
find "$WORK_DIR" -name "*.conf" -type f | while read -r conf_file; do
    sed -i 's|/etc/coredns/Zones/net/adi\.example\.zone|/etc/coredns/Zones/net/example.zone|g' "$conf_file"
done

echo "[*] Creating README for open source project..."

cat > "$WORK_DIR/README.md" <<'EOF'
# DNS Zone Management with CoreDNS and DNSSEC

This repository contains a complete DNS zone management system with automated DNSSEC key generation and zone file management for CoreDNS.

## Features

- **Automated DNSSEC key generation** using ECDSA P-256 SHA-256
- **Zone file change detection** with hash-based caching
- **Key archiving system** for security and rollback
- **SOA serial auto-increment** based on date and sequence
- **Multi-domain support** with subdomain delegation
- **Sanitization tools** for sharing configurations safely
- **Real-time zone monitoring** with automatic regeneration
- **Systemd service integration** for reliable operation

## Structure

```
/etc/coredns/
├── Zones/net/example.zone          # Main DNS zone file
├── Keys/                           # DNSSEC keys (auto-generated)
├── AutoZoneGen/                   # Generated CoreDNS configurations (auto-generated)
├── Cache/                         # Zone file hashes for change detection (auto-generated)
├── Scripts/
│   ├── generate_all_zones.sh          # Main zone generation script
│   ├── update_soa_serials.sh          # SOA serial management
│   ├── install-watcher-service.sh     # Zone watcher service installer
│   └── sanitize_dns_config.sh         # Configuration sanitization
└── setup_watcher.sh              # Automated watcher service setup
```

## Quick Start

1. **Setup the system**:
   ```bash
   # Run as root to setup zone monitoring service
   sudo ./setup_watcher.sh
   ```

2. **Customize the zone file**:
   ```bash
   cp Zones/net/example.zone Zones/net/yourdomain.zone
   # Edit the zone file with your domain and IP addresses
   ```

3. **Test manual generation** (optional):
   ```bash
   ./Scripts/generate_all_zones.sh
   ```

4. **Import into CoreDNS**:
   ```bash
   # Add to your CoreDNS Corefile:
   import AutoZoneGen/*.conf
   ```

## Automation

The system includes real-time zone file monitoring:

- **Service**: `coredns-zone-watcher` systemd service
- **Monitoring**: Real-time file change detection using inotify
- **Setup Script**: `setup_watcher.sh` installs and configures the service
- **Automatic**: Runs continuously, no scheduling needed
- **Debouncing**: Prevents excessive regeneration during multiple rapid changes

### Service Management

```bash
# Check service status
sudo ./Scripts/install-watcher-service.sh status

# View recent logs
sudo ./Scripts/install-watcher-service.sh logs

# Restart the service
sudo ./Scripts/install-watcher-service.sh restart

# Stop the service
sudo ./Scripts/install-watcher-service.sh stop

# Start the service
sudo ./Scripts/install-watcher-service.sh start

# Uninstall the service
sudo ./Scripts/install-watcher-service.sh uninstall
```

### Manual Zone Generation

While the watcher service handles automatic updates, you can also run manual generation:

```bash
# Generate all zones
./Scripts/generate_all_zones.sh

# Clear and regenerate everything
./Scripts/generate_all_zones.sh --clear
```

## Configuration

### Zone File Format

The zone files follow standard DNS format with additional features:
- Automatic SOA serial management
- Support for GitHub Pages integration
- Mail server configuration examples
- CAA records for certificate authority authorization

### DNSSEC Keys

- Algorithm: ECDSA P-256 SHA-256 (algorithm 13)
- Automatic key generation per domain
- Archive system for key rotation
- Proper file permissions and ownership

### Scripts

#### `setup_watcher.sh`
Sets up automated zone monitoring service:
- Installs and configures the zone watcher service
- Enables real-time file monitoring
- Configures proper permissions and security
- Idempotent (safe to run multiple times)

#### `Scripts/install-watcher-service.sh`
Zone watcher service management:
- Installs systemd service for zone monitoring
- Configures inotify-based file watching
- Sets up proper user permissions and sudo access
- Provides service management commands

#### `Scripts/generate_all_zones.sh`
Main script that:
- Scans for zone file changes using MD5 hashes
- Archives old DNSSEC keys before regeneration
- Generates new keys as needed
- Creates CoreDNS configuration blocks
- Updates SOA serials automatically

Options:
- `--clear`: Clean all generated files (preserves archives)

#### `Scripts/update_soa_serials.sh`
Updates SOA serial numbers:
- Format: YYYYMMDDNN (date + sequence)
- Increments sequence for same-day updates
- Resets to 01 for new days

#### `Scripts/sanitize_dns_config.sh`
Removes sensitive information for sharing:
- Replaces real domains with example.net
- Sanitizes IP addresses using RFC documentation ranges
- Removes private keys and certificates
- Safe for public repositories

## Security Considerations

- Private keys are stored with 600 permissions
- Keys are automatically archived before regeneration
- All sensitive data is excluded from version control
- Sanitization script for safe sharing
- Service runs with minimal privileges using dedicated user
- Sudo access limited to specific required commands only

## Requirements

- `ldns-keygen` for DNSSEC key generation
- `bind9-utils` for DNS utilities
- `inotify-tools` for file monitoring
- CoreDNS server
- Bash 4.0+
- Root access for service setup
- systemd for service management

## Installation

1. Clone or extract this configuration to `/etc/coredns/`
2. Run `sudo ./setup_watcher.sh` to install the monitoring service
3. Customize zone files for your domains
4. The service will automatically detect changes and regenerate configurations

## Monitoring and Logs

The zone watcher service provides comprehensive logging:

```bash
# View service status
systemctl status coredns-zone-watcher

# View real-time logs
journalctl -u coredns-zone-watcher -f

# View recent logs
sudo ./Scripts/install-watcher-service.sh logs 100
```

## License

This configuration management system is provided as-is for educational and operational use.
Replace all example values with your actual configuration before production use.

## Support

This is a template configuration. Customize according to your specific needs:
1. Replace example.net with your domain
2. Update IP addresses to your servers
3. Modify DNS records as required
4. Generate new DNSSEC keys
5. Review security settings
6. Setup zone monitoring with setup_watcher.sh
EOF

# Clean up any remaining sensitive files
find "$WORK_DIR" -name "*.hash" -delete
find "$WORK_DIR" -name "*.log" -delete

# Set appropriate permissions
chmod -R 755 "$WORK_DIR"
find "$WORK_DIR" -name "*.private" -exec chmod 600 {} \;
find "$WORK_DIR" -name "*.key" -exec chmod 644 {} \;

# Handle final output
if [[ "$COMPRESS" == true ]]; then
    echo "[*] Creating compressed archive..."
    
    # Create archive name based on destination
    ARCHIVE_PATH="${FINAL_DEST}.tar.gz"
    
    # Create archive from temp directory
    cd "$TEMP_WORK_DIR"
    tar -czf "$ARCHIVE_PATH" "SanitizedDNS"
    
    echo "[✅] Sanitization and compression complete!"
    echo "    Archive created: $ARCHIVE_PATH"
    echo "    Archive size: $(du -h "$ARCHIVE_PATH" | cut -f1)"
else
    echo "[*] Moving sanitized files to final destination..."
    
    # Create destination directory if needed
    mkdir -p "$(dirname "$FINAL_DEST")"
    
    # Move from temp to final destination
    mv "$WORK_DIR" "$FINAL_DEST"
    
    echo "[✅] Sanitization complete!"
    echo "    Destination: $FINAL_DEST"
fi

echo ""
echo "Open source DNS management system ready!"
echo "- Only example.net zone preserved and sanitized"
echo "- All IP addresses replaced with RFC documentation ranges"
echo "- All sensitive information removed"
echo "- Auto-generated directories excluded (Keys, AutoZoneGen, Cache)"
echo "- Includes cron automation setup script"
echo ""
if [[ "$COMPRESS" == false ]]; then
    echo "Next steps:"
    echo "1. cd $FINAL_DEST"
    echo "2. sudo ./setup_watcher.sh  # Setup zone monitoring service"
    echo "3. ./Scripts/generate_all_zones.sh  # Test manual execution (optional)"
else
    echo "Extract the archive and follow the README.md for setup instructions."
fi
