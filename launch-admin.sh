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
readonly RED='[0;31m'
readonly GREEN='[0;32m'
readonly YELLOW='[1;33m'
readonly BLUE='[0;34m'
readonly CYAN='[0;36m'
readonly NC='[0m' # No Color
readonly BOLD='[1m'

# Progress indicators
readonly SPINNER="⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"
readonly CHECKMARK="✓"
readonly WARNING="⚠"
readonly ERROR="✗"

# Ensure logs directory exists
mkdir -p "${LOGS_DIR}"

# Enhanced logging functions with better formatting
log_info() {
    local timestamp=$(date '+%H:%M:%S')
    echo -e "${BLUE}[${timestamp}]${NC} $*" | tee -a "${LOG_FILE}"
}

log_success() {
    local timestamp=$(date '+%H:%M:%S')
    echo -e "${GREEN}[${timestamp}] ${CHECKMARK}${NC} $*" | tee -a "${LOG_FILE}"
}

log_warn() {
    local timestamp=$(date '+%H:%M:%S')
    echo -e "${YELLOW}[${timestamp}] ${WARNING}${NC} $*" | tee -a "${LOG_FILE}"
}

log_error() {
    local timestamp=$(date '+%H:%M:%S')
    echo -e "${RED}[${timestamp}] ${ERROR}${NC} $*" | tee -a "${LOG_FILE}"
}

log_step() {
    local phase="$1"
    local step="$2"
    local timestamp=$(date '+%H:%M:%S')
    echo -e "
${CYAN}[${timestamp}] ═══ ${BOLD}${phase}${NC} ${CYAN}═══${NC}" | tee -a "${LOG_FILE}"
    echo -e "${CYAN}${step}${NC}
" | tee -a "${LOG_FILE}"
}

# Progress animation function
show_spinner() {
    local pid=$1
    local message="$2"
    local delay=0.1
    local i=0
    
    while kill -0 "$pid" 2>/dev/null; do
        printf "
  %s %c " "$message" "${SPINNER:$i:1}"
        sleep $delay
        i=$(( (i+1) % ${#SPINNER} ))
    done
    printf "
  %s %s
" "$message" "${GREEN}${CHECKMARK}${NC}"
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
# Help function
show_help() {
    cat << EOF
${BOLD}Ephemeral AWS Container System - Launch Orchestrator${NC}

USAGE:
    $0 [OPTIONS]

OPTIONS:
    -v, --verbose       Enable verbose output with detailed logging
    -q, --quiet         Suppress non-essential output  
    --dry-run          Show what would be done without making changes
    --skip-prerequisites Skip prerequisites validation (use with caution)
    --ssh-only         Only run SSH key management phase
    -h, --help         Show this help message

EXAMPLES:
    $0                 # Normal operation
    $0 --verbose       # Detailed logging
    $0 --dry-run       # Test run without changes
    $0 --ssh-only      # Only manage SSH keys

DESCRIPTION:
    Orchestrates the complete setup of AWS prerequisites for ephemeral
    container system including IAM roles, SSH keys, and security groups.

PHASES:
    1. Prerequisites validation (AWS CLI, credentials)
    2. IAM setup (roles, policies, instance profiles)
    3. SSH key management (generation, AWS import)  
    4. Security group configuration (dynamic IP rules)

OUTPUTS:
    Session logs: ${LOGS_DIR}/
    Current log:  ${LOG_FILE}

For troubleshooting, run with --verbose flag and check log files.
EOF
}

# Print formatted header with system info
print_launch_header() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S %Z')
    local user=$(whoami)
    local aws_profile="${AWS_PROFILE:-default}"
    
    echo
    echo "╭─────────────────────────────────────────────────────────────╮"
    printf "│ ${BOLD}%-59s${NC} │\n" "Ephemeral AWS Container System"
    echo "├─────────────────────────────────────────────────────────────┤"
    printf "│ Session ID: %-47s │\n" "${SESSION_ID}"
    printf "│ Started:    %-47s │\n" "${timestamp}"
    printf "│ User:       %-47s │\n" "${user}"
    printf "│ AWS Profile:%-47s │\n" "${aws_profile}"
    printf "│ Log File:   %-47s │\n" "${LOG_FILE}"
    echo "╰─────────────────────────────────────────────────────────────╯"
    echo
}

# Phase progress tracking
show_phase_progress() {
    local current="$1"
    local total="$2"
    local phase_name="$3"
    local description="$4"
    
    # Calculate progress bar (40 characters wide)
    local progress=$((current * 40 / total))
    local bar=""
    for ((i=0; i<progress; i++)); do bar+="█"; done
    for ((i=progress; i<40; i++)); do bar+="░"; done
    
    echo
    printf "┌─ Phase %d/%d: %s\n" "${current}" "${total}" "${phase_name}"
    printf "│ [%s] %d%%\n" "${bar}" $((current * 100 / total))
    printf "│ %s\n" "${description}"
    printf "└─\n"
}

# Enhanced cleanup with better messaging
enhanced_cleanup() {
    local exit_code=$?
    local timestamp=$(date '+%H:%M:%S')
    
    if [[ ${exit_code} -ne 0 ]]; then
        echo
        echo "╭─────────────────────────────────────────────────────────────╮"
        printf "│ ${RED}${ERROR} LAUNCH FAILED${NC} %-44s │\n" "(${timestamp})"
        echo "├─────────────────────────────────────────────────────────────┤"
        printf "│ Exit Code:   %-47s │\n" "${exit_code}"
        printf "│ Session ID:  %-47s │\n" "${SESSION_ID}"
        printf "│ Log File:    %-47s │\n" "${LOG_FILE}"
        echo "├─────────────────────────────────────────────────────────────┤"
        printf "│ ${YELLOW}Troubleshooting:${NC} %-42s │\n" ""
        printf "│ • Check log file for detailed error information %-12s │\n" ""
        printf "│ • Run with --verbose for additional debugging   %-12s │\n" ""
        printf "│ • Verify AWS credentials and permissions       %-13s │\n" ""
        echo "╰─────────────────────────────────────────────────────────────╯"
        
        # Execute rollback if needed
        if [[ ${#ROLLBACK_STACK[@]} -gt 0 ]]; then
            log_warn "Executing rollback operations..."
            for ((i=${#ROLLBACK_STACK[@]}-1; i>=0; i--)); do
                log_info "Rollback: ${ROLLBACK_STACK[i]}"
                eval "${ROLLBACK_STACK[i]}" || log_warn "Rollback operation failed: ${ROLLBACK_STACK[i]}"
            done
        fi
    fi
}

main() {
    local start_time=$(date +%s)
    
    # Parse command line arguments
    local verbose=false
    local quiet=false
    local dry_run=false
    local skip_prerequisites=false
    local ssh_only=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -v|--verbose)
                verbose=true
                shift
                ;;
            -q|--quiet)
                quiet=true
                shift
                ;;
            --dry-run)
                dry_run=true
                shift
                ;;
            --skip-prerequisites)
                skip_prerequisites=true
                shift
                ;;
            --ssh-only)
                ssh_only=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                echo -e "${RED}Error: Unknown option '$1'${NC}"
                echo "Use --help for usage information."
                exit 1
                ;;
        esac
    done
    
    # Override cleanup function
    trap enhanced_cleanup EXIT ERR INT TERM
    
    # Configure logging based on flags
    if [[ "${quiet}" == "true" ]]; then
        exec 3>&1 4>&2
        exec 1>/dev/null 2>/dev/null
    elif [[ "${verbose}" == "true" ]]; then
        set -x
    fi
    
    # Print header
    if [[ "${quiet}" == "false" ]]; then
        print_launch_header
        
        if [[ "${dry_run}" == "true" ]]; then
            log_warn "DRY RUN MODE - No actual changes will be made"
            echo
        fi
    fi
    
    # Determine phases to run
    local total_phases=4
    if [[ "${ssh_only}" == "true" ]]; then
        total_phases=1
    elif [[ "${skip_prerequisites}" == "true" ]]; then
        total_phases=3
    fi
    
    local current_phase=1
    
    # Phase 1: Prerequisites validation
    if [[ "${ssh_only}" == "false" ]]; then
        show_phase_progress ${current_phase} ${total_phases} "Prerequisites" "Validating AWS CLI, credentials, and environment"
        
        if [[ "${skip_prerequisites}" == "false" ]]; then
            if [[ "${dry_run}" == "false" ]]; then
                if ! "${SCRIPTS_DIR}/check-prerequisites.sh" 2>&1 | tee -a "${LOG_FILE}"; then
                    log_error "Prerequisites validation failed"
                    exit 1
                fi
            else
                log_info "Would validate prerequisites"
                sleep 2
            fi
            log_success "Prerequisites validation complete"
        else
            log_warn "Prerequisites validation skipped by user"
        fi
        ((current_phase++))
    fi
    
    # Phase 2: IAM setup
    if [[ "${ssh_only}" == "false" ]]; then
        show_phase_progress ${current_phase} ${total_phases} "IAM Setup" "Creating roles, policies, and instance profiles"
        
        if [[ "${dry_run}" == "false" ]]; then
            if ! "${SCRIPTS_DIR}/setup-iam.sh" 2>&1 | tee -a "${LOG_FILE}"; then
                log_error "IAM setup failed"
                exit 1
            fi
        else
            log_info "Would setup IAM roles and policies"
            sleep 2
        fi
        log_success "IAM setup complete"
        ((current_phase++))
    fi
    
    # Phase 3: SSH key management (enhanced with new UX features)
    if [[ "${ssh_only}" == "true" ]]; then
        show_phase_progress 1 1 "SSH Keys" "Managing SSH key pairs for secure access"
    else
        show_phase_progress ${current_phase} ${total_phases} "SSH Keys" "Managing SSH key pairs for secure access"
    fi
    
    local ssh_args=()
    if [[ "${verbose}" == "true" ]]; then
        ssh_args+=("--verbose")
    elif [[ "${quiet}" == "true" ]]; then
        ssh_args+=("--quiet")
    fi
    if [[ "${dry_run}" == "true" ]]; then
        ssh_args+=("--dry-run")
    fi
    
    if [[ "${dry_run}" == "false" ]]; then
        if ! "${SCRIPTS_DIR}/generate-ssh-keys.sh" "${ssh_args[@]}" 2>&1 | tee -a "${LOG_FILE}"; then
            log_error "SSH key generation failed"
            exit 1
        fi
    else
        log_info "Would manage SSH keys with enhanced UX"
        sleep 2
    fi
    log_success "SSH keys ready"
    
    if [[ "${ssh_only}" == "true" ]]; then
        # Calculate execution time
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        
        echo
        echo "╭─────────────────────────────────────────────────────────────╮"
        printf "│ ${GREEN}${CHECKMARK} SSH KEY MANAGEMENT COMPLETED${NC} %-25s │\n" "(${duration}s)"
        echo "├─────────────────────────────────────────────────────────────┤"
        printf "│ Session: %-51s │\n" "${SESSION_ID}"
        printf "│ Log:     %-51s │\n" "${LOG_FILE}"
        echo "╰─────────────────────────────────────────────────────────────╯"
        
        # Restore output if quiet mode
        if [[ "${quiet}" == "true" ]]; then
            exec 1>&3 2>&4
            echo "SSH key management completed successfully (quiet mode)"
        fi
        
        return 0
    fi
    
    ((current_phase++))
    
    # Phase 4: Security group configuration
    show_phase_progress ${current_phase} ${total_phases} "Security Groups" "Configuring dynamic IP access rules"
    
    if [[ "${dry_run}" == "false" ]]; then
        if ! "${SCRIPTS_DIR}/manage-security-group.sh" 2>&1 | tee -a "${LOG_FILE}"; then
            log_error "Security group management failed"
            exit 1
        fi
    else
        log_info "Would configure security groups"
        sleep 2
    fi
    log_success "Security groups configured"
    
    # Calculate execution time
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    # Final success message with enhanced formatting
    echo
    echo "╭─────────────────────────────────────────────────────────────╮"
    if [[ "${dry_run}" == "true" ]]; then
        printf "│ ${GREEN}${CHECKMARK} DRY RUN COMPLETED SUCCESSFULLY${NC} %-24s │\n" "(${duration}s)"
        echo "├─────────────────────────────────────────────────────────────┤"
        printf "│ All prerequisites would be configured correctly  %-10s │\n" ""
        printf "│ No actual changes were made to AWS resources   %-11s │\n" ""
    else
        printf "│ ${GREEN}${CHECKMARK} AWS PREREQUISITES SETUP COMPLETE${NC} %-21s │\n" "(${duration}s)"
        echo "├─────────────────────────────────────────────────────────────┤"
        printf "│ System is ready for ephemeral instance launch  %-11s │\n" ""
        printf "│ All AWS resources configured successfully      %-13s │\n" ""
    fi
    echo "├─────────────────────────────────────────────────────────────┤"
    printf "│ Session ID: %-47s │\n" "${SESSION_ID}"
    printf "│ Log File:   %-47s │\n" "${LOG_FILE}"
    printf "│ Duration:   %-47s │\n" "${duration} seconds"
    echo "╰─────────────────────────────────────────────────────────────╯"
    
    if [[ "${dry_run}" == "false" ]]; then
        echo
        echo "Next steps:"
        echo "  ${GREEN}${CHECKMARK}${NC} AWS prerequisites complete"
        echo "  ${CYAN}→${NC} Ready for Phase 2: Spot instance launch script implementation"
        echo "  ${CYAN}→${NC} Use configured SSH key for secure connections"
        echo "  ${CYAN}→${NC} Security groups will auto-update with your current IP"
    fi
    
    # Restore output if quiet mode
    if [[ "${quiet}" == "true" ]]; then
        exec 1>&3 2>&4
        echo "AWS prerequisites setup completed successfully (quiet mode)"
    fi
    
    return 0
}

# Execute main function
main "$@"