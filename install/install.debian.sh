#!/bin/bash

# VoIPStack Agent - Debian Installation Script
# This script installs the latest version of VoIPStack Agent from GitHub
# and sets up a systemd service on Debian systems.

set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source common functions
source "$SCRIPT_DIR/common.sh"

# Function to check if this is a Debian-based system
check_debian() {
    if ! command -v apt-get &> /dev/null && ! [ -f /etc/debian_version ]; then
        print_message $RED "This script is designed for Debian-based systems only"
        exit 1
    fi
}

# Function to install required dependencies
install_dependencies() {
    print_message $BLUE "Installing required dependencies..."
    apt-get update
    apt-get install -y wget curl tar systemd ca-certificates
}

# Main installation function
main() {
    # Validate arguments
    validate_arguments "$@"

    local agent_token=$1

    # Debian-specific checks
    check_debian
    install_dependencies

    # Run common installation steps
    run_common_installation "$agent_token"
}

# Run main function with all arguments
main "$@"
