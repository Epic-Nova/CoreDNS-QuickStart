# 👨‍💻 DEVELOPMENT.md

Welcome to the **CoreDNS-QuickStart Development Guide!** This document will walk you through setting up your development environment to work with CoreDNS-QuickStart.

> 🧠 **Before You Begin:**  
> Make sure to read the [README.md](../README.md) for an overview of the project and contribution guidelines.

--- 
## 🚀 Getting Started with CoreDNS

### 📦 Install Required Software

CoreDNS-QuickStart is developed and tested with **Docker** and **CoreDNS**.

To install Docker:
- Follow the instructions in the `Setup/install_docker.sh` script or
- Visit [Docker's official installation guides](https://docs.docker.com/get-docker/)

To install CoreDNS:
- Use our provided setup script: `Setup/update_coredns.sh`, which builds CoreDNS from source and allows you to integrate external plugins into the plugin config file
- This approach gives you more flexibility than using pre-built binaries

> [!NOTE]
> 💡 **We recommend using the latest stable releases of Docker and CoreDNS.** CoreDNS-QuickStart aims to stay up-to-date with the newest versions.

---

## 🛠️ Basic Setup

If you're just getting started with CoreDNS-QuickStart, follow these steps:

### ✅ Step 1: Clone the Repository

Clone the latest version of CoreDNS-QuickStart from the repository.

```bash
git clone https://github.com/Epic-Nova/CoreDNS-QuickStart.git
cd CoreDNS-QuickStart
```

### ✅ Step 2: Install Docker and Dependencies

Run the setup script to install Docker and other dependencies:

```bash
chmod +x Setup/install_docker.sh
./Setup/install_docker.sh
```

### ✅ Step 3: Configure CoreDNS

1. Navigate to the SanitizedDNS folder.
2. Edit the `Corefile` to configure your DNS settings.
3. Run the setup watcher script.

```bash
cd SanitizedDNS
./setup_watcher.sh
```

### ✅ Step 4: Verify Installation

You're all set! You can now start using the features of CoreDNS-QuickStart.  
Verify your setup is working with a simple DNS lookup test.

---

## 💻 Advanced Setup for Development

If you're planning to contribute to CoreDNS-QuickStart or need to customize it further, follow these additional steps:

### 🔧 Prerequisites for Development

1. Install Go 1.18+ (required for CoreDNS development)
   ```bash
   # Example for Ubuntu/Debian
   sudo apt-get update
   sudo apt-get install golang-go
   
   # Example for macOS with Homebrew
   brew install go
   ```

2. Verify your Go installation
   ```bash
   go version
   ```

### 📚 Setting Up Your Development Environment

1. Set up your GOPATH environment variable
   ```bash
   # Add this to your .bashrc or .zshrc
   export GOPATH=$HOME/go
   export PATH=$PATH:$GOPATH/bin
   ```

2. Understanding CoreDNS Compilation with update_coredns.sh
   
   Our `Setup/update_coredns.sh` script handles:
   - Cloning the CoreDNS repository
   - Adding any custom or external plugins to the plugin.cfg file
   - Building the CoreDNS binary with the Go compiler
   - Installing it to the appropriate location
   
   ```bash
   # To rebuild CoreDNS with custom plugins
   sudo ./Setup/update_coredns.sh --rebuild
   
   # To add a custom plugin (can be used multiple times)
   sudo ./Setup/update_coredns.sh --add-plugin="example:github.com/example/plugin"
   sudo ./Setup/update_coredns.sh --add-plugin="redis:github.com/miekg/redis" --add-plugin="etcd:github.com/coredns/etcd"
   
   # Combine options to add a plugin and force rebuild
   sudo ./Setup/update_coredns.sh --add-plugin="example:github.com/example/plugin" --rebuild
   ```
   
   The `--add-plugin` option requires a value in the format `name:import_path` where:
   - `name` is the plugin name used in Corefile configurations
   - `import_path` is the Go import path for the plugin package

   When adding a custom plugin, make sure:
   1. The plugin is compatible with your CoreDNS version
   2. The Go module is accessible (public repository or in your GOPATH)
   3. Any dependencies required by the plugin are also available
   
3. Building CoreDNS manually (alternative approach)
   ```bash
   mkdir -p $GOPATH/src/github.com/coredns
   cd $GOPATH/src/github.com/coredns
   git clone https://github.com/coredns/coredns.git
   cd coredns
   # Edit plugin.cfg manually to add your plugins
   make
   ```

### 📋 Project Structure and Organization

The project is organized in the following directories:

```
CoreDNS-QuickStart/
├── Setup/                          # Installation scripts
│   ├── install_docker.sh           # Docker installer
│   └── update_coredns.sh           # CoreDNS installer/updater
├── SanitizedDNS/                   # Main DNS configuration
│   ├── Corefile                    # CoreDNS main config
│   ├── setup_watcher.sh            # Zone file monitor setup
│   ├── Zones/                      # DNS zone files
│   │   ├── com/                    # .com domains
│   │   ├── net/                    # .net domains
│   │   └── org/                    # .org domains
│   ├── Certs/                      # TLS certificates
│   └── Scripts/                    # Utility scripts
│       ├── generate_all_zones.sh       # Zone generator
│       ├── install-watcher-service.sh  # Service manager
│       ├── sanitize_dns_config.sh      # Configuration sanitizer for quick sharing
│       ├── update_soa_serials_sh       # SOA Serial updater (for manual execution)
│       └── zone_watcher.sh             # Configuration sanitizer for quick sharing
│
```

---

### 🔒 DNS Security Configuration

CoreDNS-QuickStart comes with pre-configured security settings:

1. **DNSSEC** - Digital signing of DNS records
   ```
   # In your Corefile:
   dnssec {
     key file /path/to/Kexample.org.+013+12345
   }
   ```

2. **DNS-over-TLS** - Encrypted DNS queries
   ```
   # In your Corefile:
   tls {
     cert /path/to/cert.pem
     key /path/to/key.pem
   }
   ```

3. **Access Control** - Limit who can query your DNS
   ```
   # In your Corefile:
   acl {
     allow net 192.168.0.0/16
     block net 10.0.0.0/8
   }
   ```

---

### 🛠️ Step 5: Update CoreDNS Configuration

If you need to update your CoreDNS configuration:

- Edit zone files in the `SanitizedDNS/Zones` directory
- Update the `Corefile` to adjust DNS server settings
- Run the update scripts to apply changes

After the changes, restart CoreDNS to apply them.

---

### ✅ Step 6: Service Management

Learn to manage the various services that make up CoreDNS-QuickStart:

#### CoreDNS Service

CoreDNS runs as a systemd service for reliable operation:

```bash
# Service control commands
sudo systemctl start coredns
sudo systemctl stop coredns
sudo systemctl restart coredns
sudo systemctl status coredns

# View CoreDNS logs
sudo journalctl -u coredns -f
```

#### Zone Watcher Service

The zone watcher service automatically monitors and updates DNS zones when changes are detected:

```bash
# Service control commands
sudo ./SanitizedDNS/Scripts/install-watcher-service.sh start
sudo ./SanitizedDNS/Scripts/install-watcher-service.sh stop
sudo ./SanitizedDNS/Scripts/install-watcher-service.sh restart
sudo ./SanitizedDNS/Scripts/install-watcher-service.sh status

# View Zone Watcher logs
sudo ./SanitizedDNS/Scripts/install-watcher-service.sh logs
```

#### Health Monitoring

You can verify the health of your CoreDNS installation with:

```bash
# Check CoreDNS health endpoint
curl http://localhost:8080/health

# Check metrics endpoint
curl http://localhost:9153/metrics

# Test DNS resolution
dig @localhost yourdomain.zone
```

---

### ✅ Step 7: Monitor and Maintain

For ongoing management:

1. Check the Docker container status with `docker ps`.
2. Monitor DNS queries with the provided logging tools.
3. Update zone files as needed and let the watcher scripts handle the updates.

---

### 🧪 Need Help?

Check the Issues page, ask questions, or reach out to the dev team. We're happy to help you get started and contribute!

### 🙌 You're Ready!

Whether you're just using the project or helping us build it — welcome aboard.
Thanks for being part of the **CoreDNS-QuickStart** journey! 🌌
