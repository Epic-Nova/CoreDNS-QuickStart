#!/bin/bash
set -e

CMD="coredns"
INSTALL_DIR="/usr/local/bin"
INSTALL_PATH="$INSTALL_DIR/$CMD" # Path where the CoreDNS binary will be installed
SERVICE_NAME="coredns.service"
BUILD_DIR="/home/coredns/coredns_build" # Directory for CoreDNS source code and build
CRON_MARKER="# CoreDNS update cron job"
PLUGIN_CFG_PATH="$BUILD_DIR/plugin.cfg" # Path to plugin.cfg within the build directory
TEMP_PLUGIN_CFG="/tmp/coredns_plugin_cfg_backup" # Temporary backup location for plugin.cfg
CUSTOM_PLUGINS=() # Array to store custom plugins to be added

# --- Function to display usage information ---
usage() {
    echo "Usage: $0 [--rebuild] [--set-caps] [--add-plugin=PLUGIN]"
    echo ""
    echo "  --rebuild            Force a full rebuild and reinstallation of CoreDNS from source."
    echo "                       This will skip version checks and always compile the latest release."
    echo "  --set-caps           Only set the CAP_NET_BIND_SERVICE capability on the CoreDNS binary."
    echo "                       This is used to allow CoreDNS to bind to privileged ports (e.g., 53)."
    echo "  --add-plugin=PLUGIN  Add a custom plugin to CoreDNS. Format: name:import_path"
    echo "                       Example: --add-plugin=\"example:github.com/example/plugin\""
    echo "                       Can be specified multiple times for multiple plugins."
    echo "  (no arguments)       Check for the latest CoreDNS release and update if a newer version"
    echo "                       is available. Also ensures service and cron are set up."
    echo ""
    echo "Note: This script requires 'sudo' for certain operations (e.g., installing binary, setting capabilities, managing systemd service)."
    exit 1
}

# --- Parse command-line arguments ---
FORCE_REBUILD=false
SET_CAPS_ONLY=false

while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --rebuild)
            FORCE_REBUILD=true
            ;;
        --set-caps)
            SET_CAPS_ONLY=true
            ;;
        --add-plugin=*)
            CUSTOM_PLUGINS+=("${1#*=}")
            ;;
        --add-plugin)
            if [ -n "$2" ] && [ "${2:0:1}" != "-" ]; then
                CUSTOM_PLUGINS+=("$2")
                shift
            else
                echo "Error: --add-plugin requires a value in format 'name:import_path'"
                usage
            fi
            ;;
        *)
            usage
            ;;
    esac
    shift
done

# --- Fetch latest release information from GitHub API ---
GITHUB_API_URL="https://api.github.com/repos/coredns/coredns/releases/latest"
API_JSON=$(curl -s "$GITHUB_API_URL")

# Extract the latest tag name (e.g., v1.12.2 will become 1.12.2)
LATEST_TAG=$(echo "$API_JSON" | grep '"tag_name":' | head -1 | sed -E 's/.*"v([^"]+)".*/\1/')

if [ -z "$LATEST_TAG" ]; then
    echo "Error: Failed to get latest CoreDNS tag from GitHub API. Exiting."
    exit 1
fi

echo "Latest CoreDNS release tag found: $LATEST_TAG"

# --- Version comparison function ---
# Compares two version strings (e.g., 1.12.2 vs 1.12.3)
vercomp() {
    # usage: vercomp ver1 ver2
    if [[ "$1" == "$2" ]]; then
        return 0 # Versions are equal
    fi
    local IFS=.
    local i ver1=($1) ver2=($2)
    # Fill empty fields in ver1 with zeros for proper comparison
    for ((i=${#ver1[@]}; i<${#ver2[@]}; i++)); do
        ver1[i]=0
    done
    for ((i=0; i<${#ver1[@]}; i++)); do
        if [[ -z ${ver2[i]} ]]; then
            # Fill empty fields in ver2 with zeros
            ver2[i]=0
        fi
        if ((10#${ver1[i]} > 10#${ver2[i]})); then
            return 1 # ver1 is newer
        fi
        if ((10#${ver1[i]} < 10#${ver2[i]})); then
            return 2 # ver2 is newer
        fi
    done
    return 0 # Versions are equal
}

# --- Function to set CAP_NET_BIND_SERVICE capability ---
set_port_capabilities() {
    echo "Checking and setting CAP_NET_BIND_SERVICE capability on $INSTALL_PATH..."

    if [ ! -f "$INSTALL_PATH" ]; then
        echo "Error: CoreDNS binary not found at $INSTALL_PATH. Cannot set capabilities."
        exit 1
    fi

    # Check current capabilities
    CURRENT_CAPS=$(getcap "$INSTALL_PATH" 2>/dev/null || true)
    if echo "$CURRENT_CAPS" | grep -q "cap_net_bind_service+ep"; then
        echo "CAP_NET_BIND_SERVICE is already set for $INSTALL_PATH."
        return 0
    fi

    echo "Attempting to set CAP_NET_BIND_SERVICE on $INSTALL_PATH..."
    if ! sudo setcap 'cap_net_bind_service=+ep' "$INSTALL_PATH"; then
        echo "Error: Failed to set CAP_NET_BIND_SERVICE effective capability."
        echo "This command requires sudo privileges. Please ensure you have sudo access."
        exit 1
    fi
    echo "CAP_NET_BIND_SERVICE set successfully for $INSTALL_PATH."
}

# --- Function to add custom plugins to plugin.cfg ---
add_custom_plugins() {
    if [ ${#CUSTOM_PLUGINS[@]} -eq 0 ]; then
        # No custom plugins to add
        return 0
    fi

    echo "Adding custom plugins to $PLUGIN_CFG_PATH..."
    
    if [ ! -f "$PLUGIN_CFG_PATH" ]; then
        echo "Error: plugin.cfg not found at $PLUGIN_CFG_PATH. Exiting."
        return 1
    fi
    
    # Create a backup of the original plugin.cfg
    cp "$PLUGIN_CFG_PATH" "${PLUGIN_CFG_PATH}.orig"
    
    for plugin in "${CUSTOM_PLUGINS[@]}"; do
        # Validate plugin format (name:import_path)
        if [[ ! "$plugin" =~ ^[a-zA-Z0-9_]+:[a-zA-Z0-9_/.@-]+$ ]]; then
            echo "Warning: Invalid plugin format: '$plugin'. Expected 'name:import_path'. Skipping."
            continue
        fi
        
        # Extract name and import path
        name="${plugin%%:*}"
        import_path="${plugin#*:}"
        
        # Check if the plugin is already in the configuration
        if grep -q "^${name}:" "$PLUGIN_CFG_PATH"; then
            echo "Plugin '$name' is already in plugin.cfg. Skipping."
            continue
        fi
        
        echo "Adding plugin: $name ($import_path)"
        
        # Append the plugin just before the last line (usually "health")
        sed -i '$i'"${name}:${import_path}" "$PLUGIN_CFG_PATH"
        
        if [ $? -ne 0 ]; then
            echo "Error: Failed to add plugin '$name' to plugin.cfg."
            # Restore original plugin.cfg on error
            cp "${PLUGIN_CFG_PATH}.orig" "$PLUGIN_CFG_PATH"
            return 1
        fi
    done
    
    echo "Successfully added custom plugins to plugin.cfg:"
    for plugin in "${CUSTOM_PLUGINS[@]}"; do
        echo " - $plugin"
    done
    
    # Clean up the backup if everything succeeded
    rm "${PLUGIN_CFG_PATH}.orig"
    return 0
}

# --- Function to build and install CoreDNS from source ---
install_coredns() {
    echo "Attempting to build and install CoreDNS version $LATEST_TAG from source..."

    # Ensure the build directory exists
    mkdir -p "$BUILD_DIR"

    # Check if the build directory is a Git repository; if not, clone CoreDNS
    if [ ! -d "$BUILD_DIR/.git" ]; then
        echo "CoreDNS repository not found in $BUILD_DIR. Cloning now..."
        if ! git clone https://github.com/coredns/coredns.git "$BUILD_DIR"; then
            echo "Error: Failed to clone CoreDNS repository into $BUILD_DIR. Exiting."
            exit 1
        fi
    fi

    # Navigate into the build directory
    pushd "$BUILD_DIR" > /dev/null

    # --- Backup plugin.cfg if it exists ---
    if [ -f "$PLUGIN_CFG_PATH" ]; then
        echo "Backing up existing $PLUGIN_CFG_PATH to $TEMP_PLUGIN_CFG..."
        cp "$PLUGIN_CFG_PATH" "$TEMP_PLUGIN_CFG"
    fi

    echo "Fetching latest tags from origin..."
    if ! git fetch --tags origin; then
        echo "Error: Failed to fetch Git tags from origin. Exiting."
        popd > /dev/null
        exit 1
    fi

    echo "Resetting to CoreDNS version v$LATEST_TAG..."
    # 'git reset --hard' ensures a clean state matching the tag
    if ! git reset --hard "v$LATEST_TAG"; then
        echo "Error: Failed to checkout tag v$LATEST_TAG. Exiting."
        popd > /dev/null
        exit 1
    fi

    # --- Restore plugin.cfg if a backup exists ---
    if [ -f "$TEMP_PLUGIN_CFG" ]; then
        echo "Restoring $TEMP_PLUGIN_CFG to $PLUGIN_CFG_PATH..."
        cp "$TEMP_PLUGIN_CFG" "$PLUGIN_CFG_PATH"
        rm "$TEMP_PLUGIN_CFG" # Clean up temporary backup
    fi
    
    # --- Add any custom plugins to plugin.cfg ---
    if [ ${#CUSTOM_PLUGINS[@]} -gt 0 ]; then
        if ! add_custom_plugins; then
            echo "Error: Failed to add custom plugins. Exiting."
            popd > /dev/null
            exit 1
        fi
    fi

    echo "Building CoreDNS binary using 'make'..."
    # The 'make' command compiles CoreDNS. Requires Go to be installed and in PATH.
    if ! make; then
        echo "Error: Failed to build CoreDNS. Please ensure Go (golang) and make are installed and accessible in your PATH. Exiting."
        popd > /dev/null
        exit 1
    fi

    # Check if the built binary exists
    if [ ! -f "$BUILD_DIR/$CMD" ]; then
        echo "Error: Built coredns binary not found at $BUILD_DIR/$CMD after 'make'. Exiting."
        popd > /dev/null
        exit 1
    fi

    # Stop the CoreDNS service before replacing the binary to avoid conflicts
    SERVICE_WAS_ACTIVE=false
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        SERVICE_WAS_ACTIVE=true
        echo "Stopping $SERVICE_NAME before replacing the binary..."
        sudo systemctl stop "$SERVICE_NAME"
    fi

    # Ensure the installation directory exists
    sudo mkdir -p "$INSTALL_DIR"

    # Move the newly built binary to the installation path
    sudo mv "$BUILD_DIR/$CMD" "$INSTALL_PATH"
    sudo chmod +x "$INSTALL_PATH"
    echo "CoreDNS built and installed successfully at $INSTALL_PATH"

    # Set port binding capabilities after installation
    set_port_capabilities

    # Restart the service if it was active before the update
    if [ "$SERVICE_WAS_ACTIVE" = true ]; then
        echo "Starting $SERVICE_NAME after binary replacement..."
        sudo systemctl start "$SERVICE_NAME" || echo "Warning: Could not restart $SERVICE_NAME. Please check logs."
    fi

    popd > /dev/null # Return to the original directory
}

# --- Function to create/update the systemd service file ---
create_service() {
    echo "Setting up CoreDNS systemd service..."

    # Create a dedicated system user for CoreDNS if it doesn't exist
    if ! id -u coredns >/dev/null 2>&1; then
        echo "Creating 'coredns' system user and group..."
        sudo useradd --system --no-create-home --shell /usr/sbin/nologin coredns
    fi

    # Ensure the directory for Corefile exists and is owned by coredns user
    sudo mkdir -p /etc/coredns
    sudo chown coredns:coredns /etc/coredns # Ensure CoreDNS can read/write its config

    # Create the systemd service unit file
    # Note: No 'setcap' or 'sudo' in ExecStart, as capabilities are set directly on the binary
    sudo cat << EOF > "/etc/systemd/system/$SERVICE_NAME"
[Unit]
Description=CoreDNS DNS Server
After=network.target

[Service]
ExecStart=$INSTALL_PATH -conf /etc/coredns/Corefile
Restart=on-failure
User=coredns
Group=coredns
LimitNOFILE=65536 # Recommended for DNS servers handling many connections
Environment="GOMAXPROCS=4"

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload # Reload systemd manager configuration
    sudo systemctl enable "$SERVICE_NAME" # Enable service to start on boot
    sudo systemctl start "$SERVICE_NAME" # Start the service immediately

    echo "Systemd service $SERVICE_NAME created, enabled, and started."

    # Ensure port capabilities are set after service setup
    set_port_capabilities
}

# --- Function to set up a cron job for automatic updates ---
setup_cronjob() {
    CRON_CMD="/usr/bin/env bash $(realpath "$0")" # Get absolute path of the current script
    # Check if the cron job already exists to avoid duplicates
    if ! sudo crontab -l 2>/dev/null | grep -F "$CRON_MARKER" >/dev/null 2>&1; then
        # Add a weekly cron job (Sunday at 3:00 AM)
        # Use a temporary file for crontab to avoid issues with pipes and sudo
        (sudo crontab -l 2>/dev/null || true; echo "0 3 * * 0 $CRON_CMD $CRON_MARKER") | sudo crontab -
        echo "Cron job added to run this script every Sunday at 3:00 AM for updates."
    else
        echo "CoreDNS update cron job already exists."
    fi
}

# --- Main Logic ---

if [ "$SET_CAPS_ONLY" = true ]; then
    echo "Running in --set-caps mode."
    set_port_capabilities
    echo "Port capability registration completed."
    exit 0
fi

INSTALL_OR_UPDATE_REQUIRED=false

# Check if the CoreDNS binary exists at the installation path
if [ ! -f "$INSTALL_PATH" ] || [ "$FORCE_REBUILD" = true ]; then
    if [ "$FORCE_REBUILD" = true ]; then
        echo "Force rebuild requested. Performing full source build and install..."
    else
        echo "CoreDNS binary not found at $INSTALL_PATH. Performing initial source build and install..."
    fi
    INSTALL_OR_UPDATE_REQUIRED=true
else
    # Extract the local CoreDNS version from the installed binary
    LOCAL_VERSION=$("$INSTALL_PATH" --version 2>/dev/null | head -1 | sed -E 's/CoreDNS-([0-9.]+)/\1/')

    if [ -z "$LOCAL_VERSION" ]; then
        echo "Warning: Could not determine local CoreDNS version from $INSTALL_PATH. Assuming an update is needed."
        INSTALL_OR_UPDATE_REQUIRED=true
    else
        echo "Local CoreDNS version: $LOCAL_VERSION"

        # Compare local version with the latest available tag
        vercomp "$LATEST_TAG" "$LOCAL_VERSION"
        cmp_result=$?

        if [ $cmp_result -eq 2 ]; then
            echo "Local CoreDNS version ($LOCAL_VERSION) is newer than or equal to the latest release ($LATEST_TAG). No update needed."
            INSTALL_OR_UPDATE_REQUIRED=false
        elif [ $cmp_result -eq 1 ]; then
            echo "Latest CoreDNS release ($LATEST_TAG) is newer than local ($LOCAL_VERSION). Update required."
            INSTALL_OR_UPDATE_REQUIRED=true
        else # cmp_result is 0 (versions are equal)
            echo "CoreDNS is up to date ($LATEST_TAG == $LOCAL_VERSION)."
            INSTALL_OR_UPDATE_REQUIRED=false
        fi
    fi
fi

# Execute installation or update if required
if [ "$INSTALL_OR_UPDATE_REQUIRED" = true ]; then
    install_coredns
fi

# Ensure the systemd service exists and is properly configured, regardless of update status
if [ ! -f "/etc/systemd/system/$SERVICE_NAME" ]; then
    create_service
else
    # If service file exists and an update just occurred, ensure it's running
    if [ "$INSTALL_OR_UPDATE_REQUIRED" = true ] && ! sudo systemctl is-active --quiet "$SERVICE_NAME"; then
        echo "Service $SERVICE_NAME was not running after update, starting it now..."
        sudo systemctl start "$SERVICE_NAME" || echo "Warning: Could not start $SERVICE_NAME. Please check logs."
    fi
    # Always ensure the service is enabled to start on boot
    sudo systemctl enable "$SERVICE_NAME"
fi

# Set up or confirm the cron job for future automatic updates
setup_cronjob

echo "CoreDNS update script finished."