#!/bin/bash
# test-helpers.sh - Common test utilities and assertions
# Issue #23: Test Infrastructure

set -euo pipefail

# Colors for test output
readonly TEST_RED='\033[0;31m'
readonly TEST_GREEN='\033[0;32m'
readonly TEST_YELLOW='\033[1;33m'
readonly TEST_NC='\033[0m'

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

# Test functions
assert_equals() {
    local expected="$1"
    local actual="$2"
    local message="${3:-Assertion failed}"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    
    if [[ "$expected" == "$actual" ]]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${TEST_GREEN}✓${TEST_NC} $message"
        return 0
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${TEST_RED}✗${TEST_NC} $message"
        echo "  Expected: $expected"
        echo "  Actual:   $actual"
        return 1
    fi
}

assert_true() {
    local condition="$1"
    local message="${2:-Assertion failed}"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    
    if eval "$condition"; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${TEST_GREEN}✓${TEST_NC} $message"
        return 0
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${TEST_RED}✗${TEST_NC} $message"
        echo "  Condition failed: $condition"
        return 1
    fi
}

assert_file_exists() {
    local file="$1"
    local message="${2:-File should exist}"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    
    if [[ -f "$file" ]]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${TEST_GREEN}✓${TEST_NC} $message: $file"
        return 0
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${TEST_RED}✗${TEST_NC} $message: $file"
        return 1
    fi
}

assert_command_succeeds() {
    local command="$1"
    local message="${2:-Command should succeed}"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    
    if eval "$command" > /dev/null 2>&1; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${TEST_GREEN}✓${TEST_NC} $message"
        return 0
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${TEST_RED}✗${TEST_NC} $message"
        echo "  Command failed: $command"
        return 1
    fi
}

assert_command_fails() {
    local command="$1"
    local message="${2:-Command should fail}"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    
    if ! eval "$command" > /dev/null 2>&1; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${TEST_GREEN}✓${TEST_NC} $message"
        return 0
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${TEST_RED}✗${TEST_NC} $message"
        echo "  Command succeeded unexpectedly: $command"
        return 1
    fi
}

test_suite_start() {
    local suite_name="$1"
    echo
    echo "==================================="
    echo " Test Suite: $suite_name"
    echo "==================================="
    TESTS_RUN=0
    TESTS_PASSED=0
    TESTS_FAILED=0
    TESTS_SKIPPED=0
}

test_suite_end() {
    echo
    echo "-----------------------------------"
    echo " Test Results:"
    echo "-----------------------------------"
    echo -e " Total:   $TESTS_RUN"
    echo -e " Passed:  ${TEST_GREEN}$TESTS_PASSED${TEST_NC}"
    echo -e " Failed:  ${TEST_RED}$TESTS_FAILED${TEST_NC}"
    echo -e " Skipped: ${TEST_YELLOW}$TESTS_SKIPPED${TEST_NC}"
    
    if [[ $TESTS_FAILED -gt 0 ]]; then
        echo
        echo -e "${TEST_RED}SUITE FAILED${TEST_NC}"
        return 1
    else
        echo
        echo -e "${TEST_GREEN}SUITE PASSED${TEST_NC}"
        return 0
    fi
}

skip_test() {
    local message="$1"
    TESTS_SKIPPED=$((TESTS_SKIPPED + 1))
    echo -e "${TEST_YELLOW}⊘${TEST_NC} SKIPPED: $message"
}

# Mock functions
setup_test_environment() {
    export TEST_MODE=true
    export AWS_MOCK_ENABLED=true
    export TEST_TEMP_DIR=$(mktemp -d)
    export HOME="$TEST_TEMP_DIR"
    mkdir -p "$HOME/.ssh"
    mkdir -p "$HOME/.aws"
}

cleanup_test_environment() {
    if [[ -n "${TEST_TEMP_DIR:-}" ]] && [[ -d "$TEST_TEMP_DIR" ]]; then
        rm -rf "$TEST_TEMP_DIR"
    fi
}

# Export functions
export -f assert_equals
export -f assert_true
export -f assert_file_exists
export -f assert_command_succeeds
export -f assert_command_fails
export -f test_suite_start
export -f test_suite_end
export -f skip_test
export -f setup_test_environment
export -f cleanup_test_environment