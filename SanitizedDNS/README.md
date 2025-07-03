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
1. Replace [example.net](./Zones/net/example.zone) with your domain
2. Update IP addresses to your servers
3. Modify DNS records as required
4. Generate new DNSSEC keys
5. Review security settings
6. Setup zone monitoring with setup_watcher.sh
