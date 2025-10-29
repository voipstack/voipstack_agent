#!/bin/bash

# Test script for VoIPStack Agent Installation Scripts
# This script tests both Debian and CentOS 7 installations using Docker

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
DEBIAN_CONTAINER_NAME="voipstack_agent_debian_test"
CENTOS_CONTAINER_NAME="voipstack_agent_centos_test"
DEBIAN_IMAGE_NAME="voipstack_agent_debian_test"
CENTOS_IMAGE_NAME="voipstack_agent_centos_test"

# Function to cleanup
cleanup() {
    print_message $YELLOW "Cleaning up test environments..."

    # Stop and remove containers
    docker stop $DEBIAN_CONTAINER_NAME >/dev/null 2>&1 || true
    docker rm $DEBIAN_CONTAINER_NAME >/dev/null 2>&1 || true
    docker stop $CENTOS_CONTAINER_NAME >/dev/null 2>&1 || true
    docker rm $CENTOS_CONTAINER_NAME >/dev/null 2>&1 || true

    # Remove images
    docker rmi $DEBIAN_IMAGE_NAME >/dev/null 2>&1 || true
    docker rmi $CENTOS_IMAGE_NAME >/dev/null 2>&1 || true
}

# Function to build test images
build_test_images() {
    print_message $BLUE "Building test Docker images..."

    # Build Debian image
    print_message $BLUE "Building Debian test image..."
    docker build -f Dockerfile.test -t $DEBIAN_IMAGE_NAME .

    # Build CentOS image
    print_message $BLUE "Building CentOS 7 test image..."
    docker build -f Dockerfile.centos7.test -t $CENTOS_IMAGE_NAME .
}

# Function to run Debian installation test
run_debian_test() {
    print_message $BLUE "=== TESTING DEBIAN INSTALLATION ==="
    echo ""

    # Run container
    docker run -d --name $DEBIAN_CONTAINER_NAME $DEBIAN_IMAGE_NAME tail -f /dev/null
    sleep 2

    # Execute the installation script
    print_message $BLUE "Running Debian installation script..."
    docker exec $DEBIAN_CONTAINER_NAME /test/install.debian.sh $TEST_TOKEN

    # Verify installation
    verify_installation $DEBIAN_CONTAINER_NAME "Debian"
}

# Function to run CentOS installation test
run_centos_test() {
    print_message $BLUE "=== TESTING CENTOS 7 INSTALLATION ==="
    echo ""

    # Run container
    docker run -d --name $CENTOS_CONTAINER_NAME $CENTOS_IMAGE_NAME tail -f /dev/null
    sleep 2

    # Execute the installation script
    print_message $BLUE "Running CentOS 7 installation script..."
    docker exec $CENTOS_CONTAINER_NAME /test/install.centos7.sh $TEST_TOKEN

    # Verify installation
    verify_installation $CENTOS_CONTAINER_NAME "CentOS 7"
}

# Function to verify installation
verify_installation() {
    local container_name=$1
    local distro_name=$2

    print_message $BLUE "Verifying $distro_name installation..."

    local failed_tests=0

    # Check if binary is installed
    print_message $YELLOW "Checking if binary is installed..."
    if docker exec $container_name ls -la /usr/local/bin/voipstack_agent >/dev/null 2>&1; then
        print_message $GREEN "  ✓ Binary installed correctly"
        docker exec $container_name ls -la /usr/local/bin/voipstack_agent
    else
        print_message $RED "  ✗ Binary not found"
        ((failed_tests++))
    fi

    # Check if user is created
    print_message $YELLOW "Checking if user is created..."
    if docker exec $container_name id voipstack_agent >/dev/null 2>&1; then
        print_message $GREEN "  ✓ User created correctly"
        docker exec $container_name id voipstack_agent
    else
        print_message $RED "  ✗ User not found"
        ((failed_tests++))
    fi

    # Check if config directory exists
    print_message $YELLOW "Checking if config directory exists..."
    if docker exec $container_name ls -la /etc/voipstack/ >/dev/null 2>&1; then
        print_message $GREEN "  ✓ Config directory created correctly"
        docker exec $container_name ls -la /etc/voipstack/
    else
        print_message $RED "  ✗ Config directory not found"
        ((failed_tests++))
    fi

    # Check if private key is generated
    print_message $YELLOW "Checking if private key is generated..."
    if docker exec $container_name ls -la /etc/voipstack/private_key.pem >/dev/null 2>&1; then
        print_message $GREEN "  ✓ Private key generated correctly"
        docker exec $container_name ls -la /etc/voipstack/private_key.pem
    else
        print_message $RED "  ✗ Private key not found"
        ((failed_tests++))
    fi

    # Check if systemd service is created
    print_message $YELLOW "Checking if systemd service is created..."
    if docker exec $container_name ls -la /etc/systemd/system/voipstack_agent.service >/dev/null 2>&1; then
        print_message $GREEN "  ✓ Systemd service created correctly"
        docker exec $container_name ls -la /etc/systemd/system/voipstack_agent.service
    else
        print_message $RED "  ✗ Systemd service not found"
        ((failed_tests++))
    fi

    # Check service file content
    print_message $YELLOW "Checking service file content..."
    if docker exec $container_name grep -q "$TEST_TOKEN" /etc/systemd/system/voipstack_agent.service >/dev/null 2>&1; then
        print_message $GREEN "  ✓ Agent token correctly embedded in service file"
    else
        print_message $RED "  ✗ Agent token not found in service file"
        ((failed_tests++))
    fi

    # Test binary help
    print_message $YELLOW "Testing binary execution..."
    if docker exec $container_name /usr/local/bin/voipstack_agent --help >/dev/null 2>&1; then
        print_message $GREEN "  ✓ Binary executes correctly"
    else
        print_message $YELLOW "  ⚠ Binary help command returned non-zero exit code (may be expected)"
    fi

    # Summary for this distribution
    echo ""
    if [[ $failed_tests -eq 0 ]]; then
        print_message $GREEN "✅ $distro_name installation test PASSED (0 failures)"
    else
        print_message $RED "❌ $distro_name installation test FAILED ($failed_tests failures)"
    fi

    return $failed_tests
}

# Function to show comparison results
show_comparison() {
    print_message $BLUE "=== INSTALLATION COMPARISON ==="
    echo ""

    print_message $YELLOW "Debian service file:"
    docker exec $DEBIAN_CONTAINER_NAME cat /etc/systemd/system/voipstack_agent.service | head -10
    echo ""

    print_message $YELLOW "CentOS 7 service file:"
    docker exec $CENTOS_CONTAINER_NAME cat /etc/systemd/system/voipstack_agent.service | head -10
    echo ""

    print_message $YELLOW "Binary sizes:"
    docker exec $DEBIAN_CONTAINER_NAME ls -lh /usr/local/bin/voipstack_agent | awk '{print "Debian:   " $5 " " $9}'
    docker exec $CENTOS_CONTAINER_NAME ls -lh /usr/local/bin/voipstack_agent | awk '{print "CentOS 7: " $5 " " $9}'
}

# Function to run interactive comparison
run_interactive() {
    echo ""
    print_message $BLUE "Interactive mode available:"
    print_message $YELLOW "Debian container: docker exec -it $DEBIAN_CONTAINER_NAME /bin/bash"
    print_message $YELLOW "CentOS container: docker exec -it $CENTOS_CONTAINER_NAME /bin/bash"
    echo ""

    read -p "Do you want to open an interactive shell? (d=debian, c=centos, n=no): " -n 1 -r
    echo
    case $REPLY in
        [Dd]* )
            docker exec -it $DEBIAN_CONTAINER_NAME /bin/bash
            ;;
        [Cc]* )
            docker exec -it $CENTOS_CONTAINER_NAME /bin/bash
            ;;
        * )
            print_message $YELLOW "Skipping interactive mode"
            ;;
    esac
}

# Main function
main() {
    print_message $GREEN "Starting VoIPStack Agent installation tests for all distributions..."
    echo ""

    # Check if Docker is available
    if ! command -v docker &> /dev/null; then
        print_message $RED "Docker is required but not installed"
        exit 1
    fi

    # Check if installation scripts exist
    if [[ ! -f "install.debian.sh" ]]; then
        print_message $RED "install.debian.sh not found in current directory"
        exit 1
    fi

    if [[ ! -f "install.centos7.sh" ]]; then
        print_message $RED "install.centos7.sh not found in current directory"
        exit 1
    fi

    if [[ ! -f "common.sh" ]]; then
        print_message $RED "common.sh not found in current directory"
        exit 1
    fi

    # Cleanup any previous test
    cleanup

    local total_failures=0

    # Build and run tests
    build_test_images

    # Test Debian
    if run_debian_test; then
        print_message $GREEN "Debian test completed"
    else
        ((total_failures++))
    fi

    echo ""
    echo "================================================"
    echo ""

    # Test CentOS
    if run_centos_test; then
        print_message $GREEN "CentOS test completed"
    else
        ((total_failures++))
    fi

    echo ""
    echo "================================================"
    echo ""

    # Show comparison
    show_comparison

    # Final summary
    echo ""
    print_message $BLUE "=== FINAL TEST SUMMARY ==="
    if [[ $total_failures -eq 0 ]]; then
        print_message $GREEN "🎉 ALL TESTS PASSED! Both Debian and CentOS 7 installations work correctly."
    else
        print_message $RED "❌ Some tests failed. Check the output above for details."
    fi

    print_message $YELLOW "Containers are still running for inspection:"
    print_message $YELLOW "  Debian:   $DEBIAN_CONTAINER_NAME"
    print_message $YELLOW "  CentOS 7: $CENTOS_CONTAINER_NAME"

    # Interactive mode
    run_interactive

    # Final cleanup
    print_message $YELLOW "Cleaning up test environment..."
    cleanup
    print_message $GREEN "Test completed!"

    exit $total_failures
}

# Handle script arguments
case "${1:-}" in
    "cleanup")
        cleanup
        ;;
    "debian-only")
        cleanup
        build_test_images
        run_debian_test
        cleanup
        ;;
    "centos-only")
        cleanup
        build_test_images
        run_centos_test
        cleanup
        ;;
    "help"|"-h"|"--help")
        echo "Usage: $0 [command]"
        echo ""
        echo "Commands:"
        echo "  (no args)     Run all tests"
        echo "  debian-only   Test Debian installation only"
        echo "  centos-only   Test CentOS 7 installation only"
        echo "  cleanup       Clean up test environments"
        echo "  help          Show this help message"
        echo ""
        echo "Examples:"
        echo "  $0                # Run all tests"
        echo "  $0 debian-only    # Test Debian only"
        echo "  $0 centos-only    # Test CentOS 7 only"
        echo "  $0 cleanup        # Clean up"
        ;;
    *)
        main "$@"
        ;;
esac
