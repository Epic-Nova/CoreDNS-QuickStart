# CoreDNS Setup Tools (Beta v0.1.0)

This directory contains scripts for automating CoreDNS installation, Docker setup, and system configuration.

## Overview

The Setup tools are designed to streamline CoreDNS deployment by providing:

1. **Docker Installation** - Complete Docker setup with proper user permissions
2. **CoreDNS Installation** - Automated CoreDNS binary installation from GitHub releases
3. **Service Configuration** - Systemd service setup with proper capabilities
4. **Update Automation** - Automatic update checking and cron job configuration

## Scripts

### `install_docker.sh`

Installs Docker and Docker Compose with all dependencies.

**Features**:
- Complete Docker CE installation
- Repository configuration
- User group setup for non-root Docker usage
- Verification of installed components

**Usage**:
```bash
# Install Docker and Docker Compose
sudo ./install_docker.sh
```

**Post-Installation**:
- Log out and log back in for group changes to take effect
- Run `docker run hello-world` to verify installation

### `update_coredns.sh`

Comprehensive CoreDNS installation, update, and management script.

**Features**:
- GitHub API integration for version checking
- Automatic source compilation for the latest release
- Binary installation to system paths
- Systemd service creation and configuration
- Port binding capability management
- Cron job setup for automatic updates

**Usage**:
```bash
# Basic usage - install or update CoreDNS
sudo ./update_coredns.sh

# Force a full rebuild regardless of version
sudo ./update_coredns.sh --rebuild

# Only set port binding capabilities
sudo ./update_coredns.sh --set-caps
```

**Options**:
- `--rebuild` - Force a full rebuild and reinstallation
- `--set-caps` - Only set CAP_NET_BIND_SERVICE capability

## Installation Process

### Method 1: Quick Full Installation

```bash
# Install Docker and CoreDNS with a single command
sudo ./install_docker.sh && sudo ./update_coredns.sh
```

### Method 2: Step-by-Step Installation

```bash
# Step 1: Install Docker
sudo ./install_docker.sh

# Step 2: Install CoreDNS
sudo ./update_coredns.sh

# Step 3: Check installations
docker --version
coredns --version
systemctl status coredns
```

## Configuration Details

### Docker Configuration

- **Repository**: Official Docker CE repository
- **Packages**: docker-ce, docker-ce-cli, containerd.io, docker-buildx-plugin, docker-compose-plugin
- **User Configuration**: Adds current user to docker group for non-root usage

### CoreDNS Configuration

- **Installation Path**: `/usr/local/bin/coredns`
- **Build Directory**: `/home/coredns/coredns_build`
- **Service File**: `/etc/systemd/system/coredns.service`
- **Capabilities**: CAP_NET_BIND_SERVICE for port 53 binding
- **Update Schedule**: Weekly cron job (Sunday 3:00 AM)

### Service Configuration

The CoreDNS systemd service is configured with:

- **User**: `coredns`
- **Group**: `coredns`
- **Working Directory**: `/etc/coredns`
- **Restart Policy**: Always with 10-second delay
- **Capabilities**: NET_BIND_SERVICE
- **Security Restrictions**: Various systemd hardening options

## Advanced Usage

### Customizing the CoreDNS Build

To customize the CoreDNS build with specific plugins:

1. Run the update script with rebuild option:
   ```bash
   sudo ./update_coredns.sh --rebuild
   ```

2. Before the build completes, you can modify the plugin.cfg:
   ```bash
   sudo vim /home/coredns/coredns_build/plugin.cfg
   ```

3. Add or remove plugins as needed, then let the build continue

### Uninstalling

```bash
# Stop and disable CoreDNS service
sudo systemctl stop coredns
sudo systemctl disable coredns
sudo rm /etc/systemd/system/coredns.service

# Remove the binary
sudo rm /usr/local/bin/coredns

# Remove the build directory
sudo rm -rf /home/coredns/coredns_build

# Remove cron job
sudo crontab -l | grep -v "CoreDNS update cron job" | sudo crontab -
```

## Troubleshooting

### Common Issues

**Docker Permission Denied**:
- Make sure you've logged out and back in after `install_docker.sh`
- Check group membership with `groups` command

**CoreDNS Build Failures**:
- Ensure Go is installed: `go version` (1.18+ recommended)
- Check internet connectivity to GitHub
- Verify disk space: `df -h` (need at least 500MB free)

**Port Binding Issues**:
- Check if port 53 is in use: `sudo netstat -tulpn | grep :53`
- Ensure capabilities are set: `getcap /usr/local/bin/coredns`
- Try setting capabilities again: `sudo ./update_coredns.sh --set-caps`

**Service Not Starting**:
- Check logs: `sudo journalctl -u coredns -n 50`
- Verify Corefile location: `/etc/coredns/Corefile`
- Check permission on files: `ls -la /etc/coredns/`

## Integration with Zone Management

After installing CoreDNS with these tools, you can integrate with the zone management system:

1. Set up the SanitizedDNS system:
   ```bash
   cd ../SanitizedDNS
   sudo ./setup_watcher.sh
   ```

2. Ensure the CoreDNS Corefile includes:
   ```
   import AutoZoneGen/*.conf
   ```

3. Verify integration:
   ```bash
   systemctl status coredns
   systemctl status coredns-zone-watcher
   ```

## Upcoming Features

### Web Management Interface

We are actively developing a comprehensive web-based management interface that will allow:

- Visual zone file creation and editing
- Record management through an intuitive UI
- Real-time DNS record changes without manual zone file editing
- User management with role-based access control
- Activity logging and change tracking

### Database Connectivity

CoreDNS QuickStart is being expanded to support multiple database backends:

- **MySQL/MariaDB**: Store zone data in SQL databases
- **Redis**: High-performance caching and record storage
- **PostgreSQL**: Enterprise-grade DNS data management
- **etcd**: Distributed configuration storage

### Advanced CoreDNS Features

This setup tool is being enhanced to easily configure:

- **Geographic DNS**: Route users to the nearest server
- **Advanced caching**: Optimize response times
- **Load balancing**: Distribute traffic across multiple endpoints
- **Metrics and monitoring**: Prometheus integration
- **Custom plugins**: Simplified installation of community plugins

## Requirements

- **OS**: Ubuntu 18.04+ / Debian 10+ / CentOS 7+ / RHEL 7+
- **RAM**: 512MB minimum
- **Disk**: 1GB free space
- **Permissions**: Root/sudo access
- **Internet**: Access to GitHub and Docker repositories
- **Optional**: Go (will be auto-installed if needed)

## Security Notes

- The script sets minimum required permissions for CoreDNS
- Dedicated `coredns` user created for service isolation
- Port binding capability instead of running as root
- Service hardening with systemd security options
- Regular updates via cron job to patch security issues

## Development Status

This is the first beta release (v0.1.0) of CoreDNS QuickStart. While the core functionality is stable and tested, some advanced features are still under development. We appreciate your feedback and contributions to help improve this toolset.
