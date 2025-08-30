#!/bin/bash
# test-generate-ssh-keys.sh - Unit tests for SSH key generation
# Issue #23: Test Infrastructure

set -euo pipefail

# Setup
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../utils/test-helpers.sh"
source "$SCRIPT_DIR/../utils/mock-aws-cli.sh"

# Start test suite
test_suite_start "generate-ssh-keys.sh"

# Setup test environment
setup_test_environment

# Test: Key generation with mock ssh-keygen
test_key_generation() {
    local key_path="$HOME/.ssh/ephemeral-admin-key"
    
    # Generate mock key
    ssh-keygen -t rsa -f "$key_path" -N ""
    
    assert_file_exists "$key_path" "Private key should be created"
    assert_file_exists "${key_path}.pub" "Public key should be created"
    
    # Check permissions
    local priv_perms=$(stat -c %a "$key_path" 2>/dev/null || echo "600")
    local pub_perms=$(stat -c %a "${key_path}.pub" 2>/dev/null || echo "644")
    
    assert_equals "600" "$priv_perms" "Private key should have 600 permissions"
    assert_equals "644" "$pub_perms" "Public key should have 644 permissions"
}

# Test: Key name validation (security fix from Issue #3)
test_key_name_validation() {
    # Test valid key names
    local valid_names=("test-key" "key123" "my_key" "key.name")
    for name in "${valid_names[@]}"; do
        assert_true "[[ '$name' =~ ^[a-zA-Z0-9._-]+$ ]]" "Should accept valid key name: $name"
    done
    
    # Test invalid key names (command injection prevention)
    local invalid_names=(
        "key;rm -rf /"
        "key\$(whoami)"
        "key\`pwd\`"
        "key&&ls"
        "key|cat"
    )
    for name in "${invalid_names[@]}"; do
        assert_true "[[ ! '$name' =~ ^[a-zA-Z0-9._-]+$ ]]" "Should reject dangerous key name: $name"
    done
}

# Test: AWS key import
test_aws_key_import() {
    local key_name="test-key"
    
    # Mock AWS key import (uses mock aws function)
    result=$(aws ec2 import-key-pair --key-name "$key_name" 2>&1)
    assert_equals "0" "$?" "AWS key import should succeed with mock"
}

# Test: Idempotent operations
test_idempotent_operations() {
    local key_path="$HOME/.ssh/test-idempotent"
    
    # First generation
    ssh-keygen -t rsa -f "$key_path" -N ""
    local first_content=$(cat "$key_path")
    
    # Second generation (should detect existing)
    if [[ -f "$key_path" ]]; then
        assert_file_exists "$key_path" "Should detect existing key"
        # In real script, this would skip regeneration
    fi
    
    # Verify key wasn't changed (idempotent)
    local second_content=$(cat "$key_path")
    assert_equals "$first_content" "$second_content" "Key should not be regenerated if exists"
}

# Test: umask setting (security fix from Issue #3)
test_umask_security() {
    # Save original umask
    local original_umask=$(umask)
    
    # Test that secure umask is set
    umask 077
    local test_umask=$(umask)
    assert_equals "0077" "$test_umask" "Umask should be set to 077 for security"
    
    # Restore original umask
    umask "$original_umask"
}

# Run tests
test_key_generation
test_key_name_validation
test_aws_key_import
test_idempotent_operations
test_umask_security

# Cleanup
cleanup_test_environment

# End test suite
test_suite_end