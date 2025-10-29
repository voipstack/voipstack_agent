#!/bin/bash

# VoIPStack Agent - CentOS 7 Installation Script
# This script installs the latest version of VoIPStack Agent from GitHub
# and sets up a systemd service on CentOS 7 systems.

set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source common functions
source "$SCRIPT_DIR/common.sh"

# Function to check if this is a CentOS 7 system
check_centos7() {
    if [[ ! -f /etc/centos-release ]]; then
        print_message $RED "This script is designed for CentOS systems only"
        exit 1
    fi

    local version=$(cat /etc/centos-release | grep -oE '[0-9]+' | head -1)
    if [[ "$version" != "7" ]]; then
        print_message $RED "This script is designed for CentOS 7 only (detected version: $version)"
        exit 1
    fi
}

# Function to install required dependencies
install_dependencies() {
    print_message $BLUE "Installing required dependencies..."

    # Update package cache
    yum makecache fast

    # Install EPEL repository for additional packages
    yum install -y epel-release

    # Install required packages
    yum install -y wget curl tar systemd ca-certificates

    # Check systemd availability (don't fail if not available in containers)
    if ! systemctl is-active systemd >/dev/null 2>&1; then
        print_message $YELLOW "Note: systemd is not active (this is normal in containers)"
    fi
}

# Function to configure firewall (optional)
configure_firewall() {
    print_message $BLUE "Checking firewall configuration..."

    if systemctl is-active firewalld >/dev/null 2>&1; then
        print_message $YELLOW "FirewallD is active. You may need to configure it for your VoIP traffic."
        print_message $YELLOW "Common ports that might need to be opened:"
        print_message $YELLOW "  - SIP: 5060/tcp, 5060/udp"
        print_message $YELLOW "  - RTP: 10000-20000/udp (range varies by configuration)"
        print_message $YELLOW "  - AMI: 5038/tcp (for Asterisk)"
        print_message $YELLOW "  - ESL: 8021/tcp (for FreeSWITCH)"
    else
        print_message $YELLOW "FirewallD is not active."
    fi
}

# Function to configure SELinux
configure_selinux() {
    print_message $BLUE "Checking SELinux configuration..."

    if command -v getenforce >/dev/null 2>&1; then
        local selinux_status=$(getenforce)
        if [[ "$selinux_status" == "Enforcing" ]]; then
            print_message $YELLOW "SELinux is in Enforcing mode."
            print_message $YELLOW "You may need to configure SELinux policies for the VoIPStack Agent."
            print_message $YELLOW "If you encounter permission issues, consider:"
            print_message $YELLOW "  - Creating custom SELinux policies"
            print_message $YELLOW "  - Or temporarily setting SELinux to Permissive mode: setenforce 0"
        else
            print_message $YELLOW "SELinux is in $selinux_status mode."
        fi
    fi
}

# Main installation function
main() {
    # Validate arguments
    validate_arguments "$@"

    local agent_token=$1

    # CentOS 7 specific checks and setup
    check_centos7
    install_dependencies
    configure_firewall
    configure_selinux

    # Run common installation steps
    run_common_installation "$agent_token"

    echo ""
    print_message $BLUE "CentOS 7 specific notes:"
    print_message $YELLOW "- Check firewall rules if you have connectivity issues"
    print_message $YELLOW "- SELinux policies may need adjustment if the service fails to start"
    print_message $YELLOW "- Ensure your FreeSWITCH/Asterisk system is properly configured"
}

# Run main function with all arguments
main "$@"
