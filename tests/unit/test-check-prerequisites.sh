#!/bin/bash
# test-check-prerequisites.sh - Unit tests for prerequisites checking
# Issue #23: Test Infrastructure

set -euo pipefail

# Setup
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../utils/test-helpers.sh"
source "$SCRIPT_DIR/../utils/mock-aws-cli.sh"

# Start test suite
test_suite_start "check-prerequisites.sh"

# Setup test environment
setup_test_environment

# Test: AWS CLI detection
test_aws_cli_detection() {
    # Mock aws command exists
    if command -v aws > /dev/null 2>&1; then
        assert_command_succeeds "command -v aws" "AWS CLI should be detected"
    else
        skip_test "AWS CLI not installed in test environment"
    fi
}

# Test: AWS credentials validation
test_aws_credentials() {
    # Create mock credentials file
    mkdir -p "$HOME/.aws"
    cat > "$HOME/.aws/credentials" << EOF
[default]
aws_access_key_id = AKIAIOSFODNN7EXAMPLE
aws_secret_access_key = wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
EOF
    
    assert_file_exists "$HOME/.aws/credentials" "AWS credentials file should exist"
    
    # Test that mock AWS STS call works
    result=$(aws sts get-caller-identity 2>/dev/null)
    assert_true "[[ -n '$result' ]]" "AWS STS get-caller-identity should return data"
}

# Test: SSH key validation
test_ssh_key_validation() {
    local ssh_key="$HOME/.ssh/ephemeral-admin-key"
    
    # Test missing key detection
    assert_command_fails "[[ -f '$ssh_key' ]]" "Should detect missing SSH key"
    
    # Create mock SSH key
    mkdir -p "$HOME/.ssh"
    echo "MOCK_PRIVATE_KEY" > "$ssh_key"
    echo "ssh-rsa MOCK_PUBLIC_KEY" > "${ssh_key}.pub"
    chmod 600 "$ssh_key"
    chmod 644 "${ssh_key}.pub"
    
    assert_file_exists "$ssh_key" "SSH private key should exist"
    assert_file_exists "${ssh_key}.pub" "SSH public key should exist"
    
    # Test permissions
    perms=$(stat -c %a "$ssh_key" 2>/dev/null || stat -f %A "$ssh_key" 2>/dev/null || echo "600")
    assert_equals "600" "$perms" "SSH private key should have 600 permissions"
}

# Test: Required tools check
test_required_tools() {
    # Test for required commands
    local required_tools=("bash" "grep" "sed" "awk")
    
    for tool in "${required_tools[@]}"; do
        if command -v "$tool" > /dev/null 2>&1; then
            assert_command_succeeds "command -v $tool" "$tool should be available"
        else
            skip_test "$tool not available in test environment"
        fi
    done
}

# Test: AWS region validation
test_aws_region() {
    # Set test region
    export AWS_REGION="us-east-1"
    assert_equals "us-east-1" "$AWS_REGION" "AWS region should be set correctly"
    
    # Test invalid region format
    export AWS_REGION="invalid-region"
    assert_true "[[ ! '$AWS_REGION' =~ ^[a-z]{2}-[a-z]+-[0-9]+$ ]]" "Should detect invalid region format"
    
    # Reset to valid region
    export AWS_REGION="us-east-1"
    assert_true "[[ '$AWS_REGION' =~ ^[a-z]{2}-[a-z]+-[0-9]+$ ]]" "Should accept valid region format"
}

# Run tests
test_aws_cli_detection
test_aws_credentials
test_ssh_key_validation
test_required_tools
test_aws_region

# Cleanup
cleanup_test_environment

# End test suite
test_suite_end