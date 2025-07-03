#!/bin/bash

# Configuration
ROOT_DIR="/etc/coredns"
SCRIPT_DIR="$ROOT_DIR/Scripts"

GENERATOR_SCRIPT="$SCRIPT_DIR/generate_all_zones.sh"
WATCHER_SCRIPT="$SCRIPT_DIR/zone_watcher.sh"

SERVICE_NAME="coredns-zone-watcher"
SERVICE_FILE="/etc/systemd/system/$SERVICE_NAME.service"

ZONES_DIR="/etc/coredns/Zones"
CACHE_DIR="/etc/coredns/Cache"
LOG_DIR="/var/log/coredns"

LOCKFILE="/var/run/zone_watcher.lock"
LOGFILE="$LOG_DIR/zone_watcher.log"

COREDNS_USER="coredns"
COREDNS_GROUP="coredns"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    local color=$1
    local message=$2
    echo -e "${color}[$(date '+%H:%M:%S')] ${message}${NC}"
}

# Function to check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_status $RED "This script must be run as root"
        exit 1
    fi
}

# Function to check if user exists
check_user() {
    if ! id "$COREDNS_USER" &>/dev/null; then
        print_status $YELLOW "User $COREDNS_USER does not exist. Creating..."
        useradd -r -s /bin/false -d /etc/coredns "$COREDNS_USER"
        print_status $GREEN "User $COREDNS_USER created"
    fi
}

# Function to install dependencies
install_dependencies() {
    print_status $BLUE "Checking dependencies..."
    
    if ! command -v inotifywait &> /dev/null; then
        print_status $YELLOW "Installing inotify-tools..."
        apt update && apt install -y inotify-tools
        print_status $GREEN "inotify-tools installed"
    else
        print_status $GREEN "inotify-tools already installed"
    fi
}

# Function to create directories
create_directories() {
    print_status $BLUE "Creating necessary directories..."
    
    local dirs=("$LOG_DIR" "$CACHE_DIR" "$ZONES_DIR" "$ROOT_DIR/Content")
    
    for dir in "${dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            mkdir -p "$dir"
            print_status $GREEN "Created directory: $dir"
        fi
        chown "$COREDNS_USER:$COREDNS_GROUP" "$dir"
        chmod 755 "$dir"
    done
}

# Function to create the zone watcher script
create_watcher_script() {
    print_status $BLUE "Creating zone watcher script..."
    
    # Ensure the Content directory exists
    mkdir -p "$(dirname "$WATCHER_SCRIPT")"
    
    cat > "$WATCHER_SCRIPT" << 'EOF'
#!/bin/bash

# Configuration
ZONES_DIR="/etc/coredns/Zones"
SCRIPT_DIR="/etc/coredns/Scripts"
GENERATOR_SCRIPT="$SCRIPT_DIR/generate_all_zones.sh"

LOCKFILE="/var/run/zone_watcher.lock"
LOGFILE="/var/log/coredns/zone_watcher.log"
DEBOUNCE_TIME=2  # seconds to wait after last change before triggering

# Function to log messages
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOGFILE"
}

# Function to cleanup on exit
cleanup() {
    log_message "Zone watcher shutting down..."
    rm -f "$LOCKFILE"
    # Kill any background jobs
    jobs -p | xargs -r kill
    exit 0
}

# Set up signal handlers
trap cleanup SIGTERM SIGINT EXIT

# Check if already running
if [[ -f "$LOCKFILE" ]]; then
    PID=$(cat "$LOCKFILE")
    if kill -0 "$PID" 2>/dev/null; then
        log_message "Zone watcher already running with PID $PID"
        exit 1
    else
        log_message "Removing stale lockfile"
        rm -f "$LOCKFILE"
    fi
fi

# Create lockfile
echo $$ > "$LOCKFILE"

log_message "Starting zone watcher for $ZONES_DIR"

# Function to trigger zone regeneration
trigger_regeneration() {
    local changed_file="$1"
    log_message "Zone file changed: $changed_file"
    log_message "Triggering zone regeneration..."
    
    # Check if generator script exists
    if [[ ! -f "$GENERATOR_SCRIPT" ]]; then
        log_message "ERROR: Generator script not found: $GENERATOR_SCRIPT"
        return 1
    fi
    
    # Check if generator script is executable
    if [[ ! -x "$GENERATOR_SCRIPT" ]]; then
        log_message "ERROR: Generator script is not executable: $GENERATOR_SCRIPT"
        log_message "Current permissions: $(ls -la "$GENERATOR_SCRIPT" 2>/dev/null || echo 'file not accessible')"
        return 1
    fi
    
    # Check if we can read the script directory
    if [[ ! -r "$SCRIPT_DIR" ]]; then
        log_message "ERROR: Cannot read script directory: $SCRIPT_DIR"
        log_message "Current user: $(whoami), Current permissions: $(ls -ld "$SCRIPT_DIR" 2>/dev/null || echo 'directory not accessible')"
        return 1
    fi
    
    # Create a temporary file for error output
    local error_file="/tmp/zone_gen_error_$$"
    
    log_message "Executing: sudo $GENERATOR_SCRIPT"
    log_message "Working directory: $(pwd)"
    log_message "Running as user: $(whoami)"
    
    # Run the generator script with sudo and capture both stdout and stderr
    if sudo "$GENERATOR_SCRIPT" >> "$LOGFILE" 2> "$error_file"; then
        log_message "Zone regeneration completed successfully"
        
        # Clean up temporary error file
        rm -f "$error_file"
        
        # Reload CoreDNS if it's running
        if systemctl is-active --quiet coredns; then
            log_message "Reloading CoreDNS configuration..."
            sudo systemctl reload coredns 2>> "$LOGFILE"
            log_message "CoreDNS reloaded successfully"
        else
            log_message "INFO: CoreDNS is not running, skipping reload"
        fi
        
        return 0
    else
        local exit_code=$?
        log_message "ERROR: Zone regeneration failed with exit code: $exit_code"
        
        # Log the error output if any
        if [[ -f "$error_file" && -s "$error_file" ]]; then
            log_message "Error output:"
            while IFS= read -r line; do
                log_message "  $line"
            done < "$error_file"
        fi
        
        # Clean up temporary error file
        rm -f "$error_file"
        
        # Additional diagnostics
        log_message "Diagnostics:"
        log_message "  Script path: $GENERATOR_SCRIPT"
        log_message "  Script exists: $(test -f "$GENERATOR_SCRIPT" && echo 'yes' || echo 'no')"
        log_message "  Script executable: $(test -x "$GENERATOR_SCRIPT" && echo 'yes' || echo 'no')"
        log_message "  Script size: $(stat -c%s "$GENERATOR_SCRIPT" 2>/dev/null || echo 'unknown') bytes"
        log_message "  Current working directory: $(pwd)"
        log_message "  Available disk space in /tmp: $(df -h /tmp | tail -1 | awk '{print $4}' 2>/dev/null || echo 'unknown')"
        
        return 1
    fi
}

# Debounce mechanism
last_change_time=0
pending_files=()
debounce_pid=""

process_pending_changes() {
    if [[ ${#pending_files[@]} -gt 0 ]]; then
        log_message "Processing ${#pending_files[@]} pending changes after debounce period"
        trigger_regeneration "${pending_files[0]}"
        pending_files=()
    fi
    debounce_pid=""
}

# Function to handle file changes with debouncing
handle_change() {
    local file_path="$1"
    local event="$2"
    
    current_time=$(date +%s)
    
    # Add to pending files if not already there
    if [[ ! " ${pending_files[*]} " =~ " ${file_path} " ]]; then
        pending_files+=("$file_path")
        log_message "Queued change: $file_path ($event)"
    fi
    
    last_change_time=$current_time
    
    # Kill existing debounce timer
    if [[ -n "$debounce_pid" ]]; then
        kill "$debounce_pid" 2>/dev/null
    fi
    
    # Start new debounce timer
    (
        sleep $DEBOUNCE_TIME
        if [[ $(($(date +%s) - last_change_time)) -ge $DEBOUNCE_TIME ]]; then
            process_pending_changes
        fi
    ) &
    debounce_pid=$!
}

# Check if zones directory exists
if [[ ! -d "$ZONES_DIR" ]]; then
    log_message "ERROR: Zones directory does not exist: $ZONES_DIR"
    exit 1
fi

# Monitor the Zones directory
log_message "Monitoring $ZONES_DIR for changes..."

inotifywait -m -r -e modify,create,delete,move,moved_to,moved_from --format '%w%f %e' "$ZONES_DIR" 2>/dev/null | while read file_path event; do
    # Only process .zone files
    if [[ "$file_path" == *.zone ]]; then
        handle_change "$file_path" "$event"
    fi
done
EOF

    chmod +x "$WATCHER_SCRIPT"
    chown "$COREDNS_USER:$COREDNS_GROUP" "$WATCHER_SCRIPT"
    print_status $GREEN "Zone watcher script created at $WATCHER_SCRIPT"
}

# Function to create systemd service
create_systemd_service() {
    print_status $BLUE "Creating systemd service..."
    
    cat > "$SERVICE_FILE" << EOF
[Unit]
Description=CoreDNS Zone File Watcher
Documentation=https://github.com/Epic-Nova/CoreDNS-QuickStart/
After=network.target
Wants=network.target

[Service]
Type=simple
ExecStart=$WATCHER_SCRIPT
Restart=always
RestartSec=5
User=$COREDNS_USER
Group=$COREDNS_GROUP
StandardOutput=journal
StandardError=journal

# Security settings (NoNewPrivileges removed to allow sudo)
PrivateTmp=true
ProtectSystem=strict
ReadWritePaths=/etc/coredns /var/log/coredns /var/run /tmp
ProtectHome=true
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true

# Resource limits
LimitNOFILE=1024
MemoryMax=100M

[Install]
WantedBy=multi-user.target
EOF

    print_status $GREEN "Systemd service created at $SERVICE_FILE"
}

# Function to setup sudo privileges
setup_sudo_privileges() {
    print_status $BLUE "Setting up sudo privileges for $COREDNS_USER..."
    
    local sudoers_file="/etc/sudoers.d/coredns-zone-watcher"
    
    cat > "$sudoers_file" << EOF
# Allow coredns user to run zone generation script and systemctl reload as root
$COREDNS_USER ALL=(root) NOPASSWD: $GENERATOR_SCRIPT
$COREDNS_USER ALL=(root) NOPASSWD: /bin/systemctl reload coredns
$COREDNS_USER ALL=(root) NOPASSWD: /usr/bin/systemctl reload coredns
EOF

    chmod 440 "$sudoers_file"
    
    # Validate the sudoers file
    if visudo -c -f "$sudoers_file"; then
        print_status $GREEN "Sudo privileges configured for zone watcher"
    else
        print_status $RED "ERROR: Invalid sudoers configuration"
        rm -f "$sudoers_file"
        return 1
    fi
}

# Function to manage systemd service
manage_service() {
    local action="$1"
    
    case "$action" in
        "install")
            systemctl daemon-reload
            systemctl enable "$SERVICE_NAME"
            print_status $GREEN "Service $SERVICE_NAME enabled"
            ;;
        "start")
            systemctl start "$SERVICE_NAME"
            if systemctl is-active --quiet "$SERVICE_NAME"; then
                print_status $GREEN "Service $SERVICE_NAME started successfully"
            else
                print_status $RED "Failed to start service $SERVICE_NAME"
                return 1
            fi
            ;;
        "stop")
            systemctl stop "$SERVICE_NAME"
            print_status $YELLOW "Service $SERVICE_NAME stopped"
            ;;
        "restart")
            systemctl restart "$SERVICE_NAME"
            if systemctl is-active --quiet "$SERVICE_NAME"; then
                print_status $GREEN "Service $SERVICE_NAME restarted successfully"
            else
                print_status $RED "Failed to restart service $SERVICE_NAME"
                return 1
            fi
            ;;
        "status")
            systemctl status "$SERVICE_NAME" --no-pager
            ;;
        "uninstall")
            systemctl stop "$SERVICE_NAME" 2>/dev/null
            systemctl disable "$SERVICE_NAME" 2>/dev/null
            rm -f "$SERVICE_FILE"
            systemctl daemon-reload
            print_status $YELLOW "Service $SERVICE_NAME uninstalled"
            ;;
    esac
}

# Function to show service logs
show_logs() {
    local lines="${1:-50}"
    print_status $BLUE "Showing last $lines lines of service logs:"
    journalctl -u "$SERVICE_NAME" -n "$lines" --no-pager
}

# Function to check service status
check_service_status() {
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        print_status $GREEN "Service $SERVICE_NAME is running"
        return 0
    elif systemctl is-enabled --quiet "$SERVICE_NAME"; then
        print_status $YELLOW "Service $SERVICE_NAME is installed but not running"
        return 1
    else
        print_status $RED "Service $SERVICE_NAME is not installed"
        return 2
    fi
}

# Function to validate configuration
validate_config() {
    print_status $BLUE "Validating configuration..."
    
    local errors=0
    
    if [[ ! -f "$GENERATOR_SCRIPT" ]]; then
        print_status $RED "Generator script not found: $GENERATOR_SCRIPT"
        ((errors++))
    elif [[ ! -x "$GENERATOR_SCRIPT" ]]; then
        print_status $RED "Generator script is not executable: $GENERATOR_SCRIPT"
        ((errors++))
    fi
    
    if [[ ! -d "$ZONES_DIR" ]]; then
        print_status $RED "Zones directory not found: $ZONES_DIR"
        ((errors++))
    fi
    
    if [[ ! -f "$WATCHER_SCRIPT" ]]; then
        print_status $RED "Watcher script not found: $WATCHER_SCRIPT"
        ((errors++))
    elif [[ ! -x "$WATCHER_SCRIPT" ]]; then
        print_status $RED "Watcher script is not executable: $WATCHER_SCRIPT"
        ((errors++))
    fi
    
    # Test if the watcher script can be executed by the coredns user
    if [[ -f "$WATCHER_SCRIPT" ]]; then
        if ! sudo -u "$COREDNS_USER" test -x "$WATCHER_SCRIPT"; then
            print_status $RED "Watcher script cannot be executed by user $COREDNS_USER"
            ((errors++))
        fi
    fi
    
    if [[ $errors -eq 0 ]]; then
        print_status $GREEN "Configuration validation passed"
        return 0
    else
        print_status $RED "Configuration validation failed with $errors errors"
        return 1
    fi
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [COMMAND]"
    echo ""
    echo "Commands:"
    echo "  install     - Install and setup the zone watcher service"
    echo "  uninstall   - Remove the zone watcher service"
    echo "  start       - Start the service"
    echo "  stop        - Stop the service"
    echo "  restart     - Restart the service"
    echo "  status      - Show service status"
    echo "  logs [N]    - Show last N lines of logs (default: 50)"
    echo "  validate    - Validate configuration"
    echo "  help        - Show this help message"
    echo ""
    echo "If no command is provided, 'install' will be executed."
}

# Main execution
main() {
    local command="${1:-install}"
    
    case "$command" in
        "install")
            check_root
            print_status $BLUE "Setting up CoreDNS Zone Watcher..."
            
            check_user
            install_dependencies
            create_directories
            create_watcher_script
            setup_sudo_privileges
            create_systemd_service
            manage_service "install"
            
            if validate_config; then
                manage_service "start"
                print_status $GREEN "Zone watcher setup completed successfully!"
                print_status $BLUE "You can check the status with: $0 status"
                print_status $BLUE "You can view logs with: $0 logs"
            else
                print_status $RED "Setup completed but configuration validation failed"
                exit 1
            fi
            ;;
        "uninstall")
            check_root
            manage_service "uninstall"
            rm -f "$WATCHER_SCRIPT"
            rm -f "$LOCKFILE"
            rm -f "/etc/sudoers.d/coredns-zone-watcher"
            print_status $GREEN "Zone watcher uninstalled successfully"
            ;;
        "start")
            check_root
            manage_service "start"
            ;;
        "stop")
            check_root
            manage_service "stop"
            ;;
        "restart")
            check_root
            manage_service "restart"
            ;;
        "status")
            check_service_status
            echo ""
            manage_service "status"
            ;;
        "logs")
            show_logs "$2"
            ;;
        "validate")
            validate_config
            ;;
        "help"|"-h"|"--help")
            show_usage
            ;;
        *)
            print_status $RED "Unknown command: $command"
            show_usage
            exit 1
            ;;
    esac
}

# Run main function with all arguments
main "$@"