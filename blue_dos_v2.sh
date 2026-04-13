#!/bin/bash

# Improved version of the blue_dos script with additional features

# Function to handle graceful shutdown
trap "exit" INT TERM

# Function for logging
log_file="blue_dos.log"
log() {
    echo "[32m[$(date +'%Y-%m-%d %H:%M:%S')] - $1[0m" | tee -a "$log_file"
}

# Check for root privileges
if [[ $EUID -ne 0 ]]; then
    log "This script must be run as root."
    exit 1
fi

# Limit concurrent processes
max_processes=5
current_processes=$(pgrep -c blue_dos)
if [ "$current_processes" -ge "$max_processes" ]; then
    log "Maximum concurrent processes reached. Exiting..."
    exit 1
fi

log "Script started."

# (Insert the main functionality of the script here)

log "Script completed successfully."