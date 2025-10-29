#!/bin/bash

# Test script for VoIPStack Agent Debian installation
# This script tests the installation using Docker

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_message() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# Test configuration
TEST_TOKEN="test_agent_token_123456789"
CONTAINER_NAME="voipstack_agent_test"
IMAGE_NAME="voipstack_agent_test"

# Function to cleanup
cleanup() {
    print_message $YELLOW "Cleaning up..."
    docker stop $CONTAINER_NAME >/dev/null 2>&1 || true
    docker rm $CONTAINER_NAME >/dev/null 2>&1 || true
    docker rmi $IMAGE_NAME >/dev/null 2>&1 || true
}

# Function to build test image
build_test_image() {
    print_message $BLUE "Building test Docker image..."
    docker build -f Dockerfile.test -t $IMAGE_NAME .
}

# Function to run installation test
run_installation_test() {
    print_message $BLUE "Starting installation test..."

    # Run container in background
    docker run -d \
        --name $CONTAINER_NAME \
        $IMAGE_NAME \
        tail -f /dev/null

    # Wait for container to be ready
    sleep 2

    print_message $BLUE "Running installation script inside container..."

    # Execute the installation script
    docker exec $CONTAINER_NAME /test/install.debian.sh $TEST_TOKEN

    print_message $GREEN "Installation completed!"
}

# Function to verify installation
verify_installation() {
    print_message $BLUE "Verifying installation..."

    # Check if binary is installed
    print_message $YELLOW "Checking if binary is installed..."
    docker exec $CONTAINER_NAME ls -la /usr/local/bin/voipstack_agent

    # Check if user is created
    print_message $YELLOW "Checking if user is created..."
    docker exec $CONTAINER_NAME id voipstack_agent

    # Check if config directory exists
    print_message $YELLOW "Checking if config directory exists..."
    docker exec $CONTAINER_NAME ls -la /etc/voipstack/

    # Check if private key is generated
    print_message $YELLOW "Checking if private key is generated..."
    docker exec $CONTAINER_NAME ls -la /etc/voipstack/private_key.pem

    # Check if systemd service is created
    print_message $YELLOW "Checking if systemd service is created..."
    docker exec $CONTAINER_NAME ls -la /etc/systemd/system/voipstack_agent.service

    # Check if service is enabled (may not work in Docker without systemd init)
    print_message $YELLOW "Checking if service is enabled..."
    docker exec $CONTAINER_NAME systemctl is-enabled voipstack_agent || print_message $YELLOW "  (Note: systemctl may not work properly in Docker without init system)"

    # Show service status (may not work in Docker without systemd init)
    print_message $YELLOW "Checking service status..."
    docker exec $CONTAINER_NAME systemctl status voipstack_agent --no-pager 2>/dev/null || print_message $YELLOW "  (Note: Service status unavailable - this is expected in Docker without systemd init)"

    # Show service file content
    print_message $YELLOW "Showing service file content..."
    docker exec $CONTAINER_NAME cat /etc/systemd/system/voipstack_agent.service

    print_message $GREEN "Verification completed!"
}

# Function to test service start (will likely fail due to no actual FreeSWITCH, but we can check if it tries to start)
test_service_start() {
    print_message $BLUE "Testing service start (skipping in Docker)..."
    print_message $YELLOW "Note: Service start testing is skipped in Docker environment."
    print_message $YELLOW "In a real system, you would run: systemctl start voipstack_agent"

    # Test the binary directly to see if it works
    print_message $YELLOW "Testing binary execution..."
    docker exec $CONTAINER_NAME /usr/local/bin/voipstack_agent --help || print_message $YELLOW "  (Binary help command may fail - this is expected)"
}

# Function to run interactive shell
run_interactive() {
    print_message $BLUE "Starting interactive shell in container..."
    docker exec -it $CONTAINER_NAME /bin/bash
}

# Main function
main() {
    print_message $GREEN "Starting VoIPStack Agent installation test..."
    echo ""

    # Check if Docker is available
    if ! command -v docker &> /dev/null; then
        print_message $RED "Docker is required but not installed"
        exit 1
    fi

    # Check if installation script exists
    if [[ ! -f "install.debian.sh" ]]; then
        print_message $RED "install.debian.sh not found in current directory"
        exit 1
    fi

    # Cleanup any previous test
    cleanup

    # Build and run test
    build_test_image
    run_installation_test
    verify_installation
    test_service_start

    echo ""
    print_message $GREEN "Test completed successfully!"
    print_message $YELLOW "Container is still running. You can inspect it with:"
    print_message $YELLOW "  docker exec -it $CONTAINER_NAME /bin/bash"
    print_message $YELLOW ""
    print_message $YELLOW "To cleanup when done:"
    print_message $YELLOW "  docker stop $CONTAINER_NAME && docker rm $CONTAINER_NAME"

    # Ask if user wants interactive shell
    echo ""
    read -p "Do you want to open an interactive shell in the container? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        run_interactive
    fi

    # Cleanup
    print_message $YELLOW "Cleaning up test environment..."
    cleanup
    print_message $GREEN "Cleanup completed!"
}

# Handle script arguments
case "${1:-}" in
    "cleanup")
        cleanup
        ;;
    "interactive")
        cleanup
        build_test_image
        docker run -it --rm \
            $IMAGE_NAME /bin/bash
        ;;
    *)
        main "$@"
        ;;
esac
