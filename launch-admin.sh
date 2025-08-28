#!/bin/bash
# launch-admin.sh - Main orchestrator for ephemeral AWS container system
# Issue #1: AWS Prerequisites and IAM Setup
# Version: 1.0.1

set -euo pipefail
IFS=$'\n\t'

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPTS_DIR="${SCRIPT_DIR}/scripts"
readonly LOGS_DIR="${HOME}/.ephemeral-admin/logs"
readonly SESSION_ID="ephemeral-$(date +%s)"
readonly LOG_FILE="${LOGS_DIR}/${SESSION_ID}.log"

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Ensure logs directory exists
mkdir -p "${LOGS_DIR}"

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $*" | tee -a "${LOG_FILE}"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*" | tee -a "${LOG_FILE}"
}

log_warn() {
    echo -e "${YELLOW}[WARNING]${NC} $*" | tee -a "${LOG_FILE}"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" | tee -a "${LOG_FILE}"
}

# Track created resources for rollback
declare -a ROLLBACK_STACK=()

# Cleanup function with rollback
cleanup() {
    local exit_code=$?
    if [[ ${exit_code} -ne 0 ]]; then
        log_error "Launch failed with exit code ${exit_code}"
        log_info "Check log file for details: ${LOG_FILE}"
        
        # Execute rollback
        if [[ ${#ROLLBACK_STACK[@]} -gt 0 ]]; then
            log_info "Rolling back changes..."
            for ((i=${#ROLLBACK_STACK[@]}-1; i>=0; i--)); do
                log_info "Rollback: ${ROLLBACK_STACK[i]}"
                eval "${ROLLBACK_STACK[i]}" || true
            done
        fi
    fi
}

trap cleanup EXIT ERR INT TERM

# Main execution
main() {
    log_info "Starting ephemeral AWS container launch (Session: ${SESSION_ID})"
    log_info "Log file: ${LOG_FILE}"
    
    # Phase 1: Prerequisites validation
    log_info "Phase 1: Validating prerequisites..."
    if ! "${SCRIPTS_DIR}/check-prerequisites.sh" 2>&1 | tee -a "${LOG_FILE}"; then
        log_error "Prerequisites validation failed"
        exit 1
    fi
    log_success "Prerequisites validation complete"
    
    # Phase 2: IAM setup
    log_info "Phase 2: Setting up IAM roles and policies..."
    if ! "${SCRIPTS_DIR}/setup-iam.sh" 2>&1 | tee -a "${LOG_FILE}"; then
        log_error "IAM setup failed"
        exit 1
    fi
    log_success "IAM setup complete"
    
    # Phase 3: SSH key management
    log_info "Phase 3: Managing SSH keys..."
    if ! "${SCRIPTS_DIR}/generate-ssh-keys.sh" 2>&1 | tee -a "${LOG_FILE}"; then
        log_error "SSH key generation failed"
        exit 1
    fi
    log_success "SSH keys ready"
    
    # Phase 4: Security group configuration
    log_info "Phase 4: Configuring security groups..."
    if ! "${SCRIPTS_DIR}/manage-security-group.sh" 2>&1 | tee -a "${LOG_FILE}"; then
        log_error "Security group management failed"
        exit 1
    fi
    log_success "Security groups configured"
    
    # Success message
    log_success "AWS prerequisites setup complete!"
    log_info "System is ready for spot instance launch"
    log_info "Next step: Run spot instance launch script (Phase 2 implementation)"
    
    return 0
}

# Execute main function
main "$@"