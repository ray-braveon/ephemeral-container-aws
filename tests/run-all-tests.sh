#!/bin/bash
# run-all-tests.sh - Main test runner for all test suites
# Issue #23: Test Infrastructure

set -euo pipefail

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Test result tracking
TOTAL_SUITES=0
PASSED_SUITES=0
FAILED_SUITES=0
SKIPPED_SUITES=0

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Print header
echo "=============================================="
echo " Ephemeral Container AWS - Test Suite"
echo " Running all tests..."
echo "=============================================="
echo

# Source test helpers
source "$SCRIPT_DIR/utils/test-helpers.sh"

# Function to run a test suite
run_test_suite() {
    local suite_type="$1"
    local suite_name="$2"
    local suite_file="$SCRIPT_DIR/$suite_type/$suite_name"
    
    TOTAL_SUITES=$((TOTAL_SUITES + 1))
    
    if [[ ! -f "$suite_file" ]]; then
        echo -e "${YELLOW}⊘ SKIPPED:${NC} $suite_type/$suite_name (file not found)"
        SKIPPED_SUITES=$((SKIPPED_SUITES + 1))
        return
    fi
    
    echo -e "${BLUE}Running:${NC} $suite_type/$suite_name"
    
    if bash "$suite_file"; then
        PASSED_SUITES=$((PASSED_SUITES + 1))
        echo -e "${GREEN}✓ PASSED:${NC} $suite_type/$suite_name"
    else
        FAILED_SUITES=$((FAILED_SUITES + 1))
        echo -e "${RED}✗ FAILED:${NC} $suite_type/$suite_name"
    fi
    echo
}

# Run unit tests
echo "=== UNIT TESTS ==="
run_test_suite "unit" "test-check-prerequisites.sh"
run_test_suite "unit" "test-update-security-group.sh"
run_test_suite "unit" "test-generate-ssh-keys.sh"
run_test_suite "unit" "test-launch-spot.sh"

# Run integration tests
echo
echo "=== INTEGRATION TESTS ==="
run_test_suite "integration" "test-full-workflow.sh"
run_test_suite "integration" "test-error-scenarios.sh"
run_test_suite "integration" "test-cleanup-rollback.sh"

# Run security tests
echo
echo "=== SECURITY TESTS ==="
run_test_suite "security" "test-vulnerability-fixes.sh"
run_test_suite "security" "test-permission-validation.sh"
run_test_suite "security" "test-credential-handling.sh"

# Run performance tests
echo
echo "=== PERFORMANCE TESTS ==="
run_test_suite "performance" "test-launch-time.sh"
run_test_suite "performance" "test-resource-usage.sh"

# Print summary
echo
echo "=============================================="
echo " TEST SUMMARY"
echo "=============================================="
echo -e " Total Suites:   $TOTAL_SUITES"
echo -e " Passed:         ${GREEN}$PASSED_SUITES${NC}"
echo -e " Failed:         ${RED}$FAILED_SUITES${NC}"
echo -e " Skipped:        ${YELLOW}$SKIPPED_SUITES${NC}"

# Calculate pass rate
if [[ $TOTAL_SUITES -gt 0 ]]; then
    PASS_RATE=$(( (PASSED_SUITES * 100) / TOTAL_SUITES ))
    echo -e " Pass Rate:      ${PASS_RATE}%"
fi

echo "=============================================="

# Exit with appropriate code
if [[ $FAILED_SUITES -gt 0 ]]; then
    echo -e "${RED}TEST SUITE FAILED${NC}"
    exit 1
else
    echo -e "${GREEN}ALL TESTS PASSED${NC}"
    exit 0
fi