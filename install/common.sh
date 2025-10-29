#!/bin/bash

# VoIPStack Agent - Common Installation Functions
# Shared functions for different Linux distributions

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
GITHUB_REPO="voipstack/voipstack_agent"
INSTALL_DIR="/usr/local/bin"
SERVICE_FILE="/etc/systemd/system/voipstack_agent.service"
CONFIG_DIR="/etc/voipstack"
USER="voipstack_agent"
BINARY_NAME="voipstack_agent"

# Global variables
LATEST_VERSION=""
DOWNLOAD_URL=""

# Function to print colored output
print_message() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# Function to check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_message $RED "This script must be run as root (use sudo)"
        exit 1
    fi
}

# Function to show usage
show_usage() {
    local script_name=$1
    echo "Usage: $script_name <AGENT_TOKEN>"
    echo ""
    echo "Arguments:"
    echo "  AGENT_TOKEN    Your VoIPStack agent token (required)"
    echo ""
    echo "Example:"
    echo "  sudo $script_name your_agent_token_here"
    exit 1
}

# Function to validate arguments
validate_arguments() {
    if [[ $# -ne 1 ]]; then
        show_usage "$0"
    fi

    local agent_token=$1

    # Validate token (basic check)
    if [[ -z "$agent_token" ]]; then
        print_message $RED "Agent token cannot be empty"
        show_usage "$0"
    fi
}

# Function to get latest release info from GitHub
get_latest_release() {
    print_message $BLUE "Fetching latest release information..."

    # Get latest release info
    local api_url="https://api.github.com/repos/${GITHUB_REPO}/releases/latest"
    local release_info

    if command -v curl &> /dev/null; then
        release_info=$(curl -s "$api_url")
    elif command -v wget &> /dev/null; then
        release_info=$(wget -qO- "$api_url")
    else
        print_message $RED "Neither curl nor wget is available. Please install one of them."
        exit 1
    fi

    # Extract tag name and download URL
    LATEST_VERSION=$(echo "$release_info" | grep '"tag_name"' | sed -E 's/.*"tag_name": "([^"]+)".*/\1/')

    # Look for Linux x86_64 binary
    DOWNLOAD_URL=$(echo "$release_info" | grep '"browser_download_url"' | grep -i linux | grep -i x86_64 | head -1 | sed -E 's/.*"browser_download_url": "([^"]+)".*/\1/')

    if [[ -z "$LATEST_VERSION" || -z "$DOWNLOAD_URL" ]]; then
        print_message $RED "Failed to fetch release information. Please check your internet connection."
        exit 1
    fi

    print_message $GREEN "Latest version: $LATEST_VERSION"
}

# Function to create user
create_user() {
    if ! id "$USER" &>/dev/null; then
        print_message $BLUE "Creating user: $USER"
        useradd --system --no-create-home --shell /bin/false "$USER"
    else
        print_message $YELLOW "User $USER already exists"
    fi
}

# Function to download and install binary
download_and_install() {
    print_message $BLUE "Downloading VoIPStack Agent..."

    local temp_dir=$(mktemp -d)
    local archive_file="$temp_dir/voipstack_agent.tar.gz"

    # Download the archive
    if command -v curl &> /dev/null; then
        curl -L -o "$archive_file" "$DOWNLOAD_URL"
    else
        wget -O "$archive_file" "$DOWNLOAD_URL"
    fi

    print_message $BLUE "Extracting and installing binary..."

    # Extract and install
    cd "$temp_dir"
    tar -xzf "$archive_file"

    # Find the binary (it might be in a subdirectory)
    local binary_path=$(find . -name "$BINARY_NAME" -type f | head -1)

    if [[ -z "$binary_path" ]]; then
        print_message $RED "Could not find $BINARY_NAME in the downloaded archive"
        rm -rf "$temp_dir"
        exit 1
    fi

    # Install binary
    cp "$binary_path" "$INSTALL_DIR/$BINARY_NAME"
    chmod +x "$INSTALL_DIR/$BINARY_NAME"

    # Cleanup
    rm -rf "$temp_dir"

    print_message $GREEN "Binary installed to $INSTALL_DIR/$BINARY_NAME"
}

# Function to create configuration directory
create_config_dir() {
    print_message $BLUE "Creating configuration directory..."
    mkdir -p "$CONFIG_DIR"
    chown -R "$USER:$USER" "$CONFIG_DIR"
    chmod 750 "$CONFIG_DIR"
}

# Function to generate private key
generate_private_key() {
    local key_path="$CONFIG_DIR/private_key.pem"

    if [[ ! -f "$key_path" ]]; then
        print_message $BLUE "Generating private key..."
        echo ""
        print_message $YELLOW "═══════════════════════════════════════════════════════════════════════"
        print_message $GREEN "                     IMPORTANT - SAVE THIS PUBLIC KEY"
        print_message $YELLOW "═══════════════════════════════════════════════════════════════════════"
        "$INSTALL_DIR/$BINARY_NAME" --generate-private-key "$key_path"
        print_message $YELLOW "═══════════════════════════════════════════════════════════════════════"
        print_message $GREEN "You MUST register the above public key in the VoIPStack admin interface!"
        print_message $YELLOW "═══════════════════════════════════════════════════════════════════════"
        echo ""
        chown "$USER:$USER" "$key_path"
        chmod 600 "$key_path"
        print_message $GREEN "Private key generated at $key_path"
    else
        print_message $YELLOW "Private key already exists at $key_path"
    fi
}

# Function to create systemd service
create_systemd_service() {
    local agent_token=$1

    print_message $BLUE "Creating systemd service..."

    cat > "$SERVICE_FILE" << EOF
[Unit]
Description=VoIPStack Agent Service
After=network.target

[Service]
Type=simple
ExecStart=$INSTALL_DIR/$BINARY_NAME -i $agent_token
Environment=LOG_LEVEL=info
# See examples/
# Environment=VOIPSTACK_AGENT_SOFTSWITCH_CONFIG_PATH=/etc/voipstack/voipstack.yml
# chown voipstack_agent:voipstack_agent /etc/voipstack/private_key.pem
Environment=VOIPSTACK_AGENT_PRIVATE_KEY_PEM_PATH=$CONFIG_DIR/private_key.pem
# example asterisk: asterisk://amiuser:amipass@localhost:5038
# example freeswitch fusion pbx: fsfusionpbx://none:ClueCon@localhost:8021
# example HEPv3 any SIP Platform: generic+udp+hepv3://localhost:9060
Environment=VOIPSTACK_AGENT_SOFTSWITCH_URL=fs://none:ClueCon@localhost:8021
# When there is not state consumption, the process will exit.
# This avoid unnecessary billing.
Environment=VOIPSTACK_AGENT_EXIT_ON_MINIMAL_MODE=true
Restart=always
RestartSec=15
User=$USER
Environment=PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

[Install]
WantedBy=multi-user.target
EOF

    print_message $GREEN "Systemd service created at $SERVICE_FILE"
}

# Function to setup and start service
setup_service() {
    print_message $BLUE "Setting up systemd service..."

    # Try to reload daemon and enable service, but don't fail if systemd is not available
    if systemctl daemon-reload 2>/dev/null; then
        if systemctl enable voipstack_agent 2>/dev/null; then
            print_message $GREEN "Service enabled. You can now start it with:"
            print_message $YELLOW "  systemctl start voipstack_agent"
            print_message $YELLOW "  systemctl status voipstack_agent"
        else
            print_message $YELLOW "Could not enable service (this is normal in containers)"
        fi
    else
        print_message $YELLOW "Could not reload systemd daemon (this is normal in containers)"
        print_message $YELLOW "On a real system, the service will be enabled automatically"
    fi
}

# Function to show post-installation instructions
show_post_install() {
    print_message $GREEN "Installation completed successfully!"
    echo ""
    print_message $BLUE "IMPORTANT - Next steps:"
    print_message $YELLOW "1. Register the agent's public key in the VoIPStack admin interface:"
    print_message $YELLOW "   - Log in to https://admin.voipstack.io"
    print_message $YELLOW "   - Navigate to your agents section"
    print_message $YELLOW "   - Add this agent using the public key that was displayed above"
    print_message $YELLOW "   - The public key is also available in the installation output"
    echo ""
    echo "2. Configure your softswitch URL in the service file if needed:"
    echo "   $SERVICE_FILE"
    echo ""
    echo "3. Start the service:"
    echo "   systemctl start voipstack_agent"
    echo ""
    echo "4. Check service status:"
    echo "   systemctl status voipstack_agent"
    echo ""
    echo "5. View logs:"
    echo "   journalctl -u voipstack_agent -f"
    echo ""
    print_message $YELLOW "Configuration files are located in: $CONFIG_DIR"
    print_message $YELLOW "Binary is installed at: $INSTALL_DIR/$BINARY_NAME"
    echo ""
    print_message $BLUE "Note: You may need to update the systemd service to point to the correct FreeSWITCH URL."
    print_message $BLUE "Edit $SERVICE_FILE and modify the VOIPSTACK_AGENT_SOFTSWITCH_URL environment variable."
}

# Function to run common installation steps
run_common_installation() {
    local agent_token=$1

    print_message $GREEN "Starting VoIPStack Agent installation..."
    echo ""

    # Run common installation steps
    check_root
    get_latest_release
    create_user
    download_and_install
    create_config_dir
    generate_private_key
    create_systemd_service "$agent_token"
    setup_service

    echo ""
    show_post_install
}
