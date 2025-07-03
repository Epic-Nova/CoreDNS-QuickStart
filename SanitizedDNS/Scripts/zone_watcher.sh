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
