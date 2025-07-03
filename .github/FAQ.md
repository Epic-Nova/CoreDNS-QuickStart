<a id="faq-top"></a>

# 🔍 Frequently Asked Questions

Welcome to the CoreDNS-QuickStart FAQ! This document answers common questions about installation, configuration, and troubleshooting.

<details>
  <summary>Table of Contents</summary>
  <ol>
    <li><a href="#-system-requirements">System Requirements</a></li>
    <li><a href="#-common-issues-and-solutions">Common Issues and Solutions</a></li>
    <li><a href="#-service-management">Service Management</a></li>
    <li><a href="#-configuration-questions">Configuration Questions</a></li>
    <li><a href="#-advanced-questions">Advanced Questions</a></li>
  </ol>
</details>

---

## 💻 System Requirements

### What are the minimum system requirements?

- **OS**: Ubuntu 18.04+ / Debian 10+ / CentOS 7+ / RHEL 7+
- **Architecture**: x86_64 / amd64
- **RAM**: 512MB minimum (1GB recommended)
- **Disk**: 1GB free space
- **Network**: Internet access for downloads and updates

### What software dependencies are needed?

**Automatically installed by setup scripts**:
- Docker (latest stable)
- CoreDNS (latest release)
- Go (for CoreDNS compilation)

**Required for DNS zone management**:
- `ldns-utils` (for DNSSEC key generation)
- `bind9-utils` (for DNS utilities)
- `inotify-tools` (for file monitoring)

To install these dependencies manually:
```bash
# For Debian/Ubuntu
sudo apt update
sudo apt install ldns-utils bind9-utils inotify-tools

# For CentOS/RHEL
sudo yum install ldns-utils bind-utils epel-release
sudo yum install inotify-tools
```

### What permissions are required?

Root/sudo access is required for:
- Docker installation
- CoreDNS binary installation
- Service management
- Port binding capabilities (port 53)

<p align="right">(<a href="#faq-top">back to top</a>)</p>

---

## 🛠️ Common Issues and Solutions

### Docker: "Permission denied" errors

**Issue**: You get "permission denied" when trying to use Docker commands.

**Solution**:
```bash
# Add your user to the docker group
sudo usermod -aG docker $USER

# Log out and log back in for changes to take effect
# Or temporarily apply the new group membership:
newgrp docker
```

### CoreDNS: Cannot bind to port 53

**Issue**: CoreDNS fails to start with "listen udp 0.0.0.0:53: bind: permission denied".

**Solution**:
```bash
# Set the CAP_NET_BIND_SERVICE capability on the CoreDNS binary
sudo ./Setup/update_coredns.sh --set-caps
```

### Zone Generation: Files not updating

**Issue**: Changes to zone files are not being picked up automatically.

**Solution**:
```bash
# Check if the zone watcher service is running
sudo ./SanitizedDNS/Scripts/install-watcher-service.sh status

# Restart the service if needed
sudo ./SanitizedDNS/Scripts/install-watcher-service.sh restart

# Manually regenerate all zones
cd SanitizedDNS && ./Scripts/generate_all_zones.sh
```

### Services: CoreDNS or Zone Watcher not starting

**Issue**: One or both services fail to start after installation.

**Solution**:
```bash
# Check CoreDNS service logs
sudo journalctl -u coredns -n 50

# Check zone watcher service logs
sudo journalctl -u coredns-zone-watcher -n 50

# Check the Corefile for syntax errors
sudo coredns -conf /etc/coredns/Corefile -check
```

### DNSSEC: Key generation failures

**Issue**: DNSSEC key generation fails with errors.

**Solution**:
```bash
# Check if ldns-keygen is installed
which ldns-keygen

# Manually install if missing
sudo apt install ldns-utils

# Check permissions on the key directory
sudo chmod 755 SanitizedDNS/Zones/keys
```

### Docker: Container networking issues

**Issue**: Docker containers can't resolve DNS using the CoreDNS server.

**Solution**:
```bash
# Ensure Docker is configured to use the CoreDNS server
# Edit /etc/docker/daemon.json:
{
  "dns": ["your.coredns.ip.address"]
}

# Restart Docker daemon
sudo systemctl restart docker
```

<p align="right">(<a href="#faq-top">back to top</a>)</p>

---

## ⚙️ Service Management

### Where are log files located?

- **CoreDNS**: `/var/log/coredns/` or via `journalctl -u coredns`
- **Zone Watcher**: View via `journalctl -u coredns-zone-watcher`
- **Setup Scripts**: Console output during execution

### How do I manually start/stop services?

**CoreDNS Service**:
```bash
sudo systemctl start coredns
sudo systemctl stop coredns
sudo systemctl restart coredns
sudo systemctl status coredns
```

**Zone Watcher Service**:
```bash
sudo ./SanitizedDNS/Scripts/install-watcher-service.sh start
sudo ./SanitizedDNS/Scripts/install-watcher-service.sh stop
sudo ./SanitizedDNS/Scripts/install-watcher-service.sh restart
sudo ./SanitizedDNS/Scripts/install-watcher-service.sh status
```

### How do I update CoreDNS to the latest version?

```bash
# Update CoreDNS to latest version
sudo ./Setup/update_coredns.sh

# Force rebuild if needed
sudo ./Setup/update_coredns.sh --rebuild
```

<p align="right">(<a href="#faq-top">back to top</a>)</p>

---

## 🔧 Configuration Questions

### How do I add custom plugins to CoreDNS?

```bash
# Add a custom plugin and rebuild CoreDNS
sudo ./Setup/update_coredns.sh --add-plugin="example:github.com/example/plugin" --rebuild

# Multiple plugins can be added at once
sudo ./Setup/update_coredns.sh --add-plugin="redis:github.com/miekg/redis" --add-plugin="etcd:github.com/coredns/etcd" --rebuild
```

### How do I enable DNSSEC for my zones?

DNSSEC is automatically enabled for zones in the SanitizedDNS setup. To verify:

1. Check for key files in `SanitizedDNS/Zones/keys/`
2. Ensure the Corefile has the dnssec plugin enabled:
   ```
   example.com {
     dnssec
     file /path/to/zone/file
   }
   ```
3. Test DNSSEC validation:
   ```bash
   dig +dnssec @localhost example.com
   ```

### How do I set up DNS-over-TLS (DoT)?

1. Generate or obtain TLS certificates for your server
2. Place cert and key files in `SanitizedDNS/Certs/`
3. Configure the tls plugin in your Corefile:
   ```
   .:853 {
     tls SanitizedDNS/Certs/cert.pem SanitizedDNS/Certs/key.pem
     forward . 8.8.8.8 8.8.4.4
   }
   ```

### How do I back up my configuration?

```bash
# Create a sanitized backup (removes sensitive data)
cd SanitizedDNS && ./Scripts/sanitize_dns_config.sh backup

# For a complete backup including keys
tar -czf coredns-backup.tar.gz SanitizedDNS/
```

<p align="right">(<a href="#faq-top">back to top</a>)</p>

---

## 🚀 Advanced Questions

### Can I run CoreDNS in Docker instead of as a service?

Yes. After installing Docker:

```bash
# Pull the CoreDNS image
docker pull coredns/coredns

# Run CoreDNS with your configuration
docker run -d --name coredns \
  -v /path/to/Corefile:/Corefile \
  -v /path/to/zones:/zones \
  -p 53:53/udp -p 53:53/tcp \
  coredns/coredns -conf /Corefile
```

### How do I monitor CoreDNS performance?

CoreDNS exposes metrics via its metrics endpoint:

1. Make sure the Corefile has the metrics plugin enabled:
   ```
   .:53 {
     metrics localhost:9153
     ...
   }
   ```

2. Access metrics:
   ```bash
   curl http://localhost:9153/metrics
   ```

3. For visualization, configure Prometheus and Grafana to scrape and display these metrics.

### How can I integrate with Kubernetes?

CoreDNS is the default DNS provider for Kubernetes. To use your custom CoreDNS build:

1. Build a custom CoreDNS image with your plugins
2. Update the CoreDNS deployment in Kubernetes:
   ```bash
   kubectl -n kube-system set image deployment/coredns coredns=your-custom-coredns-image:tag
   ```

For detailed Kubernetes integration, refer to the [CoreDNS Kubernetes plugin documentation](https://coredns.io/plugins/kubernetes/).

<p align="right">(<a href="#faq-top">back to top</a>)</p>

---

<div align="center">
  <p>Still have questions? <a href="https://github.com/Epic-Nova/CoreDNS-QuickStart/issues/new?template=question.md">Open an issue</a> and we'll help you out!</p>
</div>
