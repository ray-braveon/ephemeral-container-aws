#!/bin/bash
# check-prerequisites.sh - Validate AWS CLI and system prerequisites
# Issue #1: AWS Prerequisites and IAM Setup
# Version: 1.0.0

set -euo pipefail

# Color codes
readonly GREEN='\033[0;32m'
readonly RED='\033[0;31m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m'

# Configuration
readonly MIN_AWS_CLI_VERSION="2.0.0"
readonly REQUIRED_REGION="us-east-1"

# Results tracking
VALIDATION_FAILED=0

# Helper functions
print_check() {
    echo -n "  Checking $1... "
}

print_pass() {
    echo -e "${GREEN}✓${NC} $1"
}

print_fail() {
    echo -e "${RED}✗${NC} $1"
    VALIDATION_FAILED=1
}

print_warn() {
    echo -e "${YELLOW}⚠${NC} $1"
}

# Validation functions
check_aws_cli() {
    print_check "AWS CLI installation"
    
    if ! command -v aws &> /dev/null; then
        print_fail "AWS CLI not found"
        echo "    Please install AWS CLI v2: https://aws.amazon.com/cli/"
        return 1
    fi
    
    local aws_version
    aws_version=$(aws --version 2>&1 | cut -d' ' -f1 | cut -d'/' -f2)
    
    if [[ "${aws_version}" < "${MIN_AWS_CLI_VERSION}" ]]; then
        print_fail "AWS CLI version ${aws_version} is too old (minimum: ${MIN_AWS_CLI_VERSION})"
        return 1
    fi
    
    print_pass "AWS CLI v${aws_version} installed"
    return 0
}

check_aws_credentials() {
    print_check "AWS credentials"
    
    if ! aws sts get-caller-identity &> /dev/null; then
        print_fail "AWS credentials not configured or invalid"
        echo "    Run: aws configure"
        return 1
    fi
    
    local account_id
    account_id=$(aws sts get-caller-identity --query Account --output text)
    print_pass "Credentials valid (Account: ${account_id})"
    return 0
}

check_aws_region() {
    print_check "AWS region configuration"
    
    local current_region
    current_region=$(aws configure get region || echo "")
    
    if [[ -z "${current_region}" ]]; then
        print_fail "No default region configured"
        echo "    Run: aws configure set region ${REQUIRED_REGION}"
        return 1
    fi
    
    if [[ "${current_region}" != "${REQUIRED_REGION}" ]]; then
        print_warn "Region is ${current_region} (recommended: ${REQUIRED_REGION})"
        echo "    Note: Using ${REQUIRED_REGION} provides lowest costs"
    else
        print_pass "Region configured: ${current_region}"
    fi
    
    return 0
}

check_aws_permissions() {
    print_check "Required AWS permissions"
    
    # Test EC2 permissions
    if ! aws ec2 describe-instances --max-results 1 &> /dev/null; then
        print_fail "Missing EC2 permissions"
        echo "    Required: ec2:DescribeInstances"
        return 1
    fi
    
    # Test IAM permissions
    if ! aws iam list-roles --max-items 1 &> /dev/null; then
        print_warn "Missing IAM list permissions (may affect role creation)"
    fi
    
    print_pass "Basic permissions verified"
    return 0
}

check_network_connectivity() {
    print_check "Network connectivity"
    
    if ! curl -s --max-time 5 https://aws.amazon.com > /dev/null; then
        print_fail "Cannot reach AWS services"
        echo "    Check your internet connection"
        return 1
    fi
    
    print_pass "Network connectivity confirmed"
    return 0
}

check_ssh_directory() {
    print_check "SSH directory"
    
    if [[ ! -d "${HOME}/.ssh" ]]; then
        mkdir -p "${HOME}/.ssh"
        chmod 700 "${HOME}/.ssh"
        print_pass "Created ~/.ssh directory"
    else
        print_pass "SSH directory exists"
    fi
    
    return 0
}

check_dependencies() {
    print_check "Required dependencies"
    
    local missing_deps=()
    
    for cmd in jq curl sed awk; do
        if ! command -v "${cmd}" &> /dev/null; then
            missing_deps+=("${cmd}")
        fi
    done
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        print_fail "Missing dependencies: ${missing_deps[*]}"
        echo "    Please install: ${missing_deps[*]}"
        return 1
    fi
    
    print_pass "All dependencies installed"
    return 0
}

# Main execution
main() {
    echo "=== AWS Prerequisites Validation ==="
    echo
    
    # Run all checks
    check_aws_cli
    check_aws_credentials
    check_aws_region
    check_aws_permissions
    check_network_connectivity
    check_ssh_directory
    check_dependencies
    
    echo
    
    # Summary
    if [[ ${VALIDATION_FAILED} -eq 0 ]]; then
        echo -e "${GREEN}✓ All prerequisites validated successfully${NC}"
        return 0
    else
        echo -e "${RED}✗ Prerequisites validation failed${NC}"
        echo "  Please resolve the issues above and try again"
        return 1
    fi
}

# Execute if run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi