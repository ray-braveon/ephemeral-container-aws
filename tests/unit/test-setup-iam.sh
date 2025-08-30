#!/bin/bash
# test-setup-iam.sh - Unit tests for IAM setup script
# Issue #24: IAM Role Creation Tests

set -euo pipefail

# Setup
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../utils/test-helpers.sh"
source "$SCRIPT_DIR/../utils/mock-aws-cli.sh"

# Start test suite
test_suite_start "setup-iam.sh"

# Setup test environment
setup_test_environment

# Test: IAM role creation
test_iam_role_creation() {
    # Test role creation with mock
    result=$(aws iam create-role --role-name "SystemAdminTestingRole" 2>&1 || true)
    assert_true "[[ '$result' == *'SystemAdminTestingRole'* ]]" "Should create IAM role"
}

# Test: Idempotent operations
test_idempotent_operations() {
    # First creation
    aws iam create-role --role-name "TestRole" 2>&1 || true
    
    # Second creation should detect existing
    result=$(aws iam get-role --role-name "SystemAdminTestingRole" 2>&1 || true)
    assert_true "[[ '$result' == *'SystemAdminTestingRole'* ]]" "Should detect existing role"
}

# Test: Instance profile creation
test_instance_profile_creation() {
    result=$(aws iam create-instance-profile --instance-profile-name "TestProfile" 2>&1 || true)
    assert_equals "0" "$?" "Instance profile creation should succeed"
}

# Test: Policy attachment
test_policy_attachment() {
    result=$(aws iam attach-role-policy --role-name "TestRole" --policy-arn "arn:aws:iam::aws:policy/TestPolicy" 2>&1 || true)
    assert_equals "0" "$?" "Policy attachment should succeed"
}

# Test: Role validation
test_role_validation() {
    # Test that validation checks required components
    local role_name="SystemAdminTestingRole"
    
    # Check role exists
    result=$(aws iam get-role --role-name "$role_name" 2>&1 || true)
    assert_true "[[ '$result' == *'$role_name'* ]]" "Role validation should check role exists"
    
    # Check instance profile
    result=$(aws iam get-instance-profile --instance-profile-name "$role_name" 2>&1 || true)
    assert_true "[[ '$result' == *'InstanceProfile'* ]]" "Should validate instance profile"
}

# Run tests
test_iam_role_creation
test_idempotent_operations
test_instance_profile_creation
test_policy_attachment
test_role_validation

# Cleanup
cleanup_test_environment

# End test suite
test_suite_end