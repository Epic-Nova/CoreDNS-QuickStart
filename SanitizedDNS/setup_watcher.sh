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
