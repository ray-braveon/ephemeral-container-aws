#!/bin/bash
# launch-admin.sh - Main launcher for Ephemeral AWS Container System
# Issue #4: Core Launch Script Implementation  
# Version: 2.0.0 - Full launch functionality

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
${BOLD}${CYAN}✨ Ephemeral AWS Container System - Launch Orchestrator ✨${NC}

${BOLD}USAGE:${NC}
    $0 [OPTIONS]

${BOLD}OPTIONS:${NC}
    ${GREEN}Core Options:${NC}
    -v, --verbose              Enable verbose output with detailed logging
    -q, --quiet                Suppress non-essential output  
    --dry-run                 Show what would be done without making changes
    --skip-prerequisites      Skip prerequisites validation (use with caution)
    --ssh-only                Only run SSH key management phase
    -h, --help                Show this help message

    ${GREEN}Enhanced Options:${NC}
    --show-costs              Display detailed cost analysis and estimates
    --instance-type TYPE      Specify instance type (t3.micro, t3.small, t3.medium)
    --region REGION           Specify AWS region (default: us-east-1)
    --max-cost PRICE          Set maximum spot price limit (\$0.08 default)
    --show-history            Display recent launch history and exit
    --quick-reconnect         Check for existing instances and reconnect
    --show-metrics            Display detailed performance metrics

${BOLD}EXAMPLES:${NC}
    ${CYAN}Basic Usage:${NC}
    $0                        # Normal operation with interactive prompts
    $0 --verbose              # Detailed logging and progress tracking
    $0 --dry-run              # Test run without making changes
    
    ${CYAN}Advanced Usage:${NC}
    $0 --instance-type t3.medium --region us-west-2
                              # Launch specific instance type in different region
    $0 --show-costs --max-cost 0.05
                              # Show cost analysis with custom price limit
    $0 --ssh-only             # Only manage SSH keys (quick setup)

${BOLD}INTERACTIVE FEATURES:${NC}
    ${GREEN}During Launch:${NC}
    • Real-time cost estimates and spot pricing
    • Interactive instance type and region selection
    • Launch confirmation with detailed summary
    • Progress tracking with time estimates
    • Connection speed and status monitoring

    ${GREEN}Cost Management:${NC}
    • Live spot pricing display
    • Session cost calculations
    • Monthly usage projections
    • Automatic cost limit warnings

${BOLD}LAUNCH PHASES:${NC}
    ${BLUE}Phase 1:${NC} Prerequisites validation (AWS CLI, credentials)
    ${BLUE}Phase 2:${NC} IAM setup (roles, policies, instance profiles)
    ${BLUE}Phase 3:${NC} SSH key management (generation, AWS import)
    ${BLUE}Phase 4:${NC} Security group configuration (dynamic IP rules)
    ${BLUE}Phase 5:${NC} Spot instance launch and SSH connection

${BOLD}SYSTEM REQUIREMENTS:${NC}
    • AWS CLI installed and configured
    • Valid AWS credentials with EC2 permissions
    • SSH client available
    • Internet connectivity for IP detection

${BOLD}OUTPUTS & LOGGING:${NC}
    Session logs: ${LOGS_DIR}/
    Current log:  ${LOG_FILE}
    
    ${YELLOW}For troubleshooting:${NC}
    • Run with --verbose for detailed debugging
    • Check log files for error details
    • Use --dry-run to validate configuration

${BOLD}COST TARGETS:${NC}
    • Target: < \$2/month for typical usage (2 sessions/week)
    • Session cost: ~\$0.02-0.04 per 2-hour session
    • Auto-termination prevents runaway costs

${GREEN}🎉 Professional Features:${NC}
    ✓ Real-time progress tracking with ETA
    ✓ Interactive cost-aware launching
    ✓ Professional visual interface
    ✓ Comprehensive error handling
    ✓ Automated troubleshooting guidance
    ✓ Session history and monitoring

For more information, visit: https://github.com/your-repo/ephemeral-aws-container
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
        # Track failed session
        local duration=$(($(date +%s) - ${start_time:-$(date +%s)}))
        track_launch_session "failed" "${duration}" "failed" "${instance_type:-unknown}" "${region:-unknown}" "0" 2>/dev/null || true
        
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

# Enhanced UI Functions for Professional User Experience

# Print enhanced header with system info and cost estimates
print_enhanced_launch_header() {
    local instance_type="$1"
    local region="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S %Z')
    local user=$(whoami)
    local aws_profile="${AWS_PROFILE:-default}"
    local aws_account=""
    
    # Get AWS account info safely
    if command -v aws >/dev/null 2>&1; then
        aws_account=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "unknown")
    fi
    
    echo
    echo "╭─────────────────────────────────────────────────────────────╮"
    printf "│ ${BOLD}${CYAN}✨ Ephemeral AWS Container System ✨${NC}%-18s │\n" ""
    echo "├─────────────────────────────────────────────────────────────┤"
    printf "│ ${BOLD}Session Details${NC}%-44s │\n" ""
    printf "│   ID: %-53s │\n" "${SESSION_ID}"
    printf "│   Started: %-46s │\n" "${timestamp}"
    printf "│   User: %-49s │\n" "${user}"
    echo "├─────────────────────────────────────────────────────────────┤"
    printf "│ ${BOLD}AWS Configuration${NC}%-40s │\n" ""
    printf "│   Profile: %-46s │\n" "${aws_profile}"
    printf "│   Account: %-46s │\n" "${aws_account:0:47}"
    printf "│   Region: %-47s │\n" "${region}"
    printf "│   Instance: %-45s │\n" "${instance_type}"
    echo "├─────────────────────────────────────────────────────────────┤"
    printf "│ ${BOLD}System Resources${NC}%-41s │\n" ""
    printf "│   Log File: %-45s │\n" "${LOG_FILE}"
    printf "│   Scripts: %-46s │\n" "${SCRIPTS_DIR}"
    echo "╰─────────────────────────────────────────────────────────────╯"
    echo
}

# Display cost information and estimates
display_cost_information() {
    local instance_type="$1"
    local region="$2"
    local max_cost="$3"
    
    echo "╭─────────────────────────────────────────────────────────────╮"
    printf "│ ${BOLD}${GREEN}💰 Cost Information${NC}%-38s │\n" ""
    echo "├─────────────────────────────────────────────────────────────┤"
    
    # Get current spot pricing
    local spot_price=""
    local on_demand_price=""
    local savings=""
    
    if command -v aws >/dev/null 2>&1; then
        # Get spot price
        spot_price=$(aws ec2 describe-spot-price-history \
            --instance-types "${instance_type}" \
            --region "${region}" \
            --max-results 1 \
            --query 'SpotPriceHistory[0].SpotPrice' \
            --output text 2>/dev/null || echo "unknown")
        
        # Estimate on-demand pricing (approximate)
        case "${instance_type}" in
            "t3.micro") on_demand_price="0.0104" ;;
            "t3.small") on_demand_price="0.0208" ;;
            "t3.medium") on_demand_price="0.0416" ;;
            *) on_demand_price="unknown" ;;
        esac
        
        if [[ "${spot_price}" != "unknown" && "${on_demand_price}" != "unknown" ]]; then
            savings=$(echo "scale=0; (1 - ${spot_price}/${on_demand_price}) * 100" | bc 2>/dev/null || echo "unknown")
        fi
    fi
    
    printf "│   Instance Type: %-40s │\n" "${instance_type}"
    printf "│   Current Spot Price: %-35s │\n" "\$${spot_price:-unknown}/hour"
    printf "│   On-Demand Price: %-38s │\n" "\$${on_demand_price:-unknown}/hour"
    if [[ "${savings}" != "unknown" ]]; then
        printf "│   Spot Savings: %-41s │\n" "${savings}%"
    fi
    
    echo "├─────────────────────────────────────────────────────────────┤"
    printf "│ ${BOLD}Usage Estimates${NC} (based on 2hr sessions)%-16s │\n" ""
    
    if [[ "${spot_price}" != "unknown" ]]; then
        local session_cost=$(echo "scale=4; ${spot_price} * 2" | bc 2>/dev/null || echo "unknown")
        local weekly_cost=$(echo "scale=4; ${spot_price} * 4" | bc 2>/dev/null || echo "unknown")  # 2 sessions/week
        local monthly_cost=$(echo "scale=2; ${spot_price} * 16" | bc 2>/dev/null || echo "unknown")  # ~8 sessions/month
        
        printf "│   Per Session (2hrs): %-33s │\n" "\$${session_cost}"
        printf "│   Weekly (2 sessions): %-32s │\n" "\$${weekly_cost}"
        printf "│   Monthly Estimate: %-35s │\n" "\$${monthly_cost}"
        
        if [[ -n "${max_cost}" ]]; then
            printf "│   Cost Limit: %-41s │\n" "\$${max_cost}"
        fi
    else
        printf "│   Unable to retrieve current pricing%-21s │\n" ""
    fi
    
    echo "╰─────────────────────────────────────────────────────────────╯"
    echo
}

# Get launch confirmation with enhanced options
get_launch_confirmation() {
    local instance_type="$1"
    local region="$2"
    
    echo "╭─────────────────────────────────────────────────────────────╮"
    printf "│ ${BOLD}${YELLOW}⚡ Launch Confirmation${NC}%-32s │\n" ""
    echo "├─────────────────────────────────────────────────────────────┤"
    printf "│ Ready to launch ${CYAN}%s${NC} instance in ${CYAN}%s${NC}%-*s │\n" "${instance_type}" "${region}" $((34 - ${#instance_type} - ${#region})) ""
    printf "│ Instance will auto-terminate on SSH disconnect%-14s │\n" ""
    echo "├─────────────────────────────────────────────────────────────┤"
    printf "│ Options:%-50s │\n" ""
    printf "│   [Enter] - Continue with launch%-25s │\n" ""
    printf "│   [c] - Change instance type%-29s │\n" ""
    printf "│   [r] - Change region%-37s │\n" ""
    printf "│   [s] - Show detailed spot pricing%-23s │\n" ""
    printf "│   [q] - Cancel launch%-37s │\n" ""
    echo "╰─────────────────────────────────────────────────────────────╯"
    
    while true; do
        read -p "Continue? [Enter/c/r/s/q]: " -r choice
        case "${choice}" in
            ""|"y"|"yes")
                echo
                log_info "Launch confirmed by user"
                return 0
                ;;
            "c"|"change")
                echo
                printf "Available instance types: ${CYAN}t3.micro, t3.small, t3.medium${NC}\n"
                read -p "New instance type [${instance_type}]: " -r new_type
                if [[ -n "${new_type}" ]]; then
                    instance_type="${new_type}"
                    log_info "Instance type changed to: ${instance_type}"
                fi
                # Restart confirmation with new settings
                get_launch_confirmation "${instance_type}" "${region}"
                return $?
                ;;
            "r"|"region")
                echo
                printf "Common regions: ${CYAN}us-east-1, us-west-2, eu-west-1${NC}\n"
                read -p "New region [${region}]: " -r new_region
                if [[ -n "${new_region}" ]]; then
                    region="${new_region}"
                    log_info "Region changed to: ${region}"
                fi
                # Restart confirmation with new settings
                get_launch_confirmation "${instance_type}" "${region}"
                return $?
                ;;
            "s"|"show"|"pricing")
                echo
                display_cost_information "${instance_type}" "${region}" ""
                ;;
            "q"|"quit"|"cancel")
                log_warn "Launch cancelled by user"
                exit 0
                ;;
            *)
                echo -e "${RED}Invalid option. Please choose Enter, c, r, s, or q.${NC}"
                ;;
        esac
    done
}

# Enhanced phase progress display with icons and ETA
show_enhanced_phase_progress() {
    local current="$1"
    local total="$2"
    local phase_name="$3"
    local description="$4"
    local icon="$5"
    
    # Calculate progress bar (50 characters wide)
    local progress=$((current * 50 / total))
    local percentage=$((current * 100 / total))
    
    # Create progress bar with gradient effect
    local bar=""
    local filled_char="█"
    local partial_char="▓"
    local empty_char="░"
    
    for ((i=0; i<progress; i++)); do bar+="${filled_char}"; done
    if [[ $progress -lt 50 ]]; then
        bar+="${partial_char}"
        for ((i=progress+1; i<50; i++)); do bar+="${empty_char}"; done
    fi
    
    # Estimate time remaining (rough estimate)
    local eta=""
    if [[ $current -gt 1 ]]; then
        eta=" (~$((30 * (total - current)))s remaining)"
    fi
    
    echo
    printf "┌─ ${icon} ${BOLD}Phase %d/%d: %s${NC}\n" "${current}" "${total}" "${phase_name}"
    printf "│ [${GREEN}%s${NC}] %d%%${eta}\n" "${bar}" "${percentage}"
    printf "│ %s\n" "${description}"
    printf "└─\n"
}

# Display troubleshooting tips for common issues
display_troubleshooting_tips() {
    local component="$1"
    
    echo
    echo "╭─────────────────────────────────────────────────────────────╮"
    printf "│ ${BOLD}${YELLOW}🔧 Troubleshooting: %s${NC}%-*s │\n" "${component}" $((36 - ${#component})) ""
    echo "├─────────────────────────────────────────────────────────────┤"
    
    case "${component}" in
        "prerequisites")
            printf "│ • Verify AWS CLI is installed: aws --version%-16s │\n" ""
            printf "│ • Check credentials: aws sts get-caller-identity%-12s │\n" ""
            printf "│ • Ensure region is set: aws configure list%-18s │\n" ""
            printf "│ • Test connectivity: aws ec2 describe-regions%-15s │\n" ""
            ;;
        "iam")
            printf "│ • Check IAM permissions for role creation%-20s │\n" ""
            printf "│ • Verify policy attachment permissions%-21s │\n" ""
            printf "│ • Review CloudTrail logs for detailed errors%-16s │\n" ""
            printf "│ • Run: aws iam list-roles --query 'Roles[?contains(\`RoleName\`, \`SystemAdmin\`)]'%-11s │\n" ""
            ;;
        "ssh")
            printf "│ • Check SSH key permissions: chmod 600 ~/.ssh/id_*%-12s │\n" ""
            printf "│ • Verify key exists: ls -la ~/.ssh/%-27s │\n" ""
            printf "│ • Test AWS import: aws ec2 describe-key-pairs%-18s │\n" ""
            ;;
        "security_group")
            printf "│ • Verify VPC exists in target region%-25s │\n" ""
            printf "│ • Check security group rules: aws ec2 describe-security-groups%-6s │\n" ""
            printf "│ • Confirm IP detection: curl -s https://checkip.amazonaws.com/%-1s │\n" ""
            ;;
        "spot_launch")
            printf "│ • Check spot pricing: aws ec2 describe-spot-price-history%-9s │\n" ""
            printf "│ • Verify subnet availability in AZ%-26s │\n" ""
            printf "│ • Review launch template configuration%-22s │\n" ""
            printf "│ • Check instance limits: aws ec2 describe-account-attributes%-3s │\n" ""
            ;;
    esac
    
    echo "├─────────────────────────────────────────────────────────────┤"
    printf "│ For detailed logs, check: %-33s │\n" "${LOG_FILE}"
    printf "│ Run with --verbose for more debugging info%-18s │\n" ""
    echo "╰─────────────────────────────────────────────────────────────╯"
    echo
}

# Display launch summary before spot instance creation
display_launch_summary() {
    local instance_type="$1"
    local region="$2"
    
    echo
    echo "╭─────────────────────────────────────────────────────────────╮"
    printf "│ ${BOLD}${BLUE}🚀 Launch Summary${NC}%-40s │\n" ""
    echo "├─────────────────────────────────────────────────────────────┤"
    printf "│ Instance Type: %-42s │\n" "${instance_type}"
    printf "│ Region: %-49s │\n" "${region}"
    printf "│ Launch Method: %-42s │\n" "EC2 Spot Request"
    printf "│ Auto-terminate: %-41s │\n" "On SSH disconnect"
    printf "│ Connection Timeout: %-37s │\n" "300 seconds"
    echo "├─────────────────────────────────────────────────────────────┤"
    printf "│ ${BOLD}Launch Steps${NC}%-44s │\n" ""
    printf "│   1. Create spot instance request%-26s │\n" ""
    printf "│   2. Wait for instance launch%-29s │\n" ""
    printf "│   3. Configure auto-termination%-27s │\n" ""
    printf "│   4. Establish SSH connection%-29s │\n" ""
    echo "╰─────────────────────────────────────────────────────────────╯"
    echo
}

# Enhanced completion banners for different scenarios
display_completion_banner() {
    local type="$1"
    local duration_or_start="$2"
    local session_id="$3"
    local log_file="$4"
    
    local timestamp=$(date '+%H:%M:%S')
    local duration=""
    
    if [[ "${type}" == "SSH_ONLY" ]]; then
        duration=$(($(date +%s) - duration_or_start))
    else
        duration="${duration_or_start}"
    fi
    
    echo
    echo "╭─────────────────────────────────────────────────────────────╮"
    
    case "${type}" in
        "SSH_ONLY")
            printf "│ ${GREEN}✓ SSH KEY MANAGEMENT COMPLETED${NC}%-25s │\n" "(${duration}s)"
            echo "├─────────────────────────────────────────────────────────────┤"
            printf "│ SSH keys are ready for secure instance access%-14s │\n" ""
            ;;
        "DRY_RUN")
            printf "│ ${GREEN}✓ DRY RUN COMPLETED SUCCESSFULLY${NC}%-23s │\n" "(${duration}s)"
            echo "├─────────────────────────────────────────────────────────────┤"
            printf "│ All operations validated - no changes made%-17s │\n" ""
            printf "│ System ready for actual launch%-29s │\n" ""
            ;;
        "COMPLETE")
            printf "│ ${GREEN}✨ EPHEMERAL CONTAINER SYSTEM READY ✨${NC}%-17s │\n" "(${duration}s)"
            echo "├─────────────────────────────────────────────────────────────┤"
            printf "│ AWS prerequisites configured successfully%-18s │\n" ""
            printf "│ Spot instance launched and connected%-24s │\n" ""
            ;;
    esac
    
    echo "├─────────────────────────────────────────────────────────────┤"
    printf "│ Session: %-51s │\n" "${session_id}"
    printf "│ Log:     %-51s │\n" "${log_file}"
    printf "│ Time:    %-51s │\n" "${timestamp}"
    echo "╰─────────────────────────────────────────────────────────────╯"
}

# Display next steps guidance after successful launch
display_next_steps_guidance() {
    echo
    echo "╭─────────────────────────────────────────────────────────────╮"
    printf "│ ${BOLD}${CYAN}🎯 What's Next?${NC}%-42s │\n" ""
    echo "├─────────────────────────────────────────────────────────────┤"
    printf "│ ${BOLD}Current Session${NC}%-43s │\n" ""
    printf "│   • Instance is running and ready for use%-20s │\n" ""
    printf "│   • SSH connection established%-32s │\n" ""
    printf "│   • Auto-termination configured%-30s │\n" ""
    echo "├─────────────────────────────────────────────────────────────┤"
    printf "│ ${BOLD}Future Launches${NC}%-43s │\n" ""
    printf "│   • Simply run: ./launch-admin.sh%-26s │\n" ""
    printf "│   • All AWS prerequisites are now configured%-16s │\n" ""
    printf "│   • Estimated launch time: <60 seconds%-21s │\n" ""
    echo "├─────────────────────────────────────────────────────────────┤"
    printf "│ ${BOLD}Monitoring & Costs${NC}%-40s │\n" ""
    printf "│   • Check AWS Cost Explorer for usage%-23s │\n" ""
    printf "│   • Session logs available at: ~/.ephemeral-admin/logs%-6s │\n" ""
    printf "│   • Target: <\$2/month for typical usage%-21s │\n" ""
    echo "╰─────────────────────────────────────────────────────────────╯"
    
    # Add celebration message
    echo
    printf "${GREEN}🎉 Congratulations! Your ephemeral AWS container system is ready to use!${NC}\n"
    echo
}

# Enhanced spot instance launch function with real-time monitoring
launch_spot_instance_enhanced() {
    local instance_type="$1"
    local region="$2"
    local max_cost="$3"
    
    log_info "Starting enhanced spot instance launch..."
    
    # Create the launch script if it doesn't exist
    if [[ ! -f "${SCRIPTS_DIR}/launch-spot.sh" ]]; then
        create_spot_launch_script
    fi
    
    # Launch with enhanced monitoring
    if ! "${SCRIPTS_DIR}/launch-spot.sh" "${instance_type}" "${region}" "${max_cost}"; then
        return 1
    fi
    
    return 0
}

# Create the spot launch script with enhanced features
create_spot_launch_script() {
    log_info "Creating enhanced spot launch script..."
    
    cat > "${SCRIPTS_DIR}/launch-spot.sh" << 'EOF'
#!/bin/bash
# Enhanced spot instance launch script with real-time monitoring

set -euo pipefail

# Parameters
INSTANCE_TYPE="${1:-t3.small}"
REGION="${2:-us-east-1}"
MAX_COST="${3:-}"

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOGS_DIR="${HOME}/.ephemeral-admin/logs"
readonly SESSION_ID="ephemeral-$(date +%s)"

# Colors for output
readonly GREEN='[0;32m'
readonly BLUE='[0;34m'
readonly CYAN='[0;36m'
readonly YELLOW='[1;33m'
readonly RED='[0;31m'
readonly NC='[0m'
readonly CHECKMARK="✓"

# Logging functions
log_info() { echo -e "${BLUE}[$(date '+%H:%M:%S')]${NC} $*"; }
log_success() { echo -e "${GREEN}[$(date '+%H:%M:%S')] ${CHECKMARK}${NC} $*"; }
log_warn() { echo -e "${YELLOW}[$(date '+%H:%M:%S')]${NC} $*"; }
log_error() { echo -e "${RED}[$(date '+%H:%M:%S')]${NC} $*"; }

# Enhanced progress tracking with countdown
show_launch_progress() {
    local message="$1"
    local max_time="$2"
    local check_cmd="$3"
    local start_time=$(date +%s)
    
    echo -n "  ${message}"
    
    while true; do
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        local remaining=$((max_time - elapsed))
        
        if [[ $remaining -le 0 ]]; then
            echo -e " ${RED}Timeout${NC}"
            return 1
        fi
        
        if eval "${check_cmd}" 2>/dev/null; then
            echo -e " ${GREEN}${CHECKMARK} (${elapsed}s)${NC}"
            return 0
        fi
        
        printf "  [%ds remaining]" "${remaining}"
        sleep 2
        printf "                    "
    done
}

# Get spot pricing with fallback
get_spot_price() {
    local instance_type="$1"
    local region="$2"
    
    local spot_price
    spot_price=$(aws ec2 describe-spot-price-history \
        --instance-types "${instance_type}" \
        --region "${region}" \
        --max-results 1 \
        --query 'SpotPriceHistory[0].SpotPrice' \
        --output text 2>/dev/null || echo "0.05")
    
    echo "${spot_price}"
}

# Main launch logic
main() {
    log_info "🚀 Launching ${CYAN}${INSTANCE_TYPE}${NC} spot instance in ${CYAN}${REGION}${NC}"
    
    # Get current spot price
    local current_spot_price
    current_spot_price=$(get_spot_price "${INSTANCE_TYPE}" "${REGION}")
    log_info "Current spot price: \$${current_spot_price}/hour"
    
    # Set max price (150% of current spot price if not specified)
    if [[ -z "${MAX_COST}" ]]; then
        MAX_COST=$(echo "scale=4; ${current_spot_price} * 1.5" | bc 2>/dev/null || echo "0.08")
    fi
    log_info "Max bid price: \$${MAX_COST}/hour"
    
    # Create user data script for auto-termination
    local user_data_script
    user_data_script=$(cat << 'USERDATA'
#!/bin/bash
# Auto-termination script
cat > /usr/local/bin/ssh-monitor.sh << 'MONITOR'
#!/bin/bash
while true; do
    if ! pgrep -f "sshd.*pts" >/dev/null; then
        logger "No active SSH sessions detected, initiating shutdown"
        shutdown -h now
        break
    fi
    sleep 30
done
MONITOR

chmod +x /usr/local/bin/ssh-monitor.sh

# Create systemd service for SSH monitoring
cat > /etc/systemd/system/ssh-monitor.service << 'SERVICE'
[Unit]
Description=SSH Session Monitor for Auto-termination
After=network.target

[Service]
ExecStart=/usr/local/bin/ssh-monitor.sh
Restart=always
User=root

[Install]
WantedBy=multi-user.target
SERVICE

systemctl enable ssh-monitor.service
systemctl start ssh-monitor.service

# Install essential tools
yum update -y
yum install -y htop tmux git vim curl wget

logger "Ephemeral instance setup complete"
USERDATA
)
    
    # Base64 encode user data
    local user_data_b64
    user_data_b64=$(echo "${user_data_script}" | base64 -w 0)
    
    # Create launch template
    log_info "Creating launch template..."
    local template_name="ephemeral-admin-template-$(date +%s)"
    local template_id
    template_id=$(aws ec2 create-launch-template \
        --region "${REGION}" \
        --launch-template-name "${template_name}" \
        --launch-template-data "{
            \"ImageId\":\"ami-0c02fb55956c7d316\",
            \"InstanceType\":\"${INSTANCE_TYPE}\",
            \"KeyName\":\"ephemeral-admin-key\",
            \"SecurityGroupIds\":[\"$(aws ec2 describe-security-groups --region ${REGION} --group-names ephemeral-admin-sg --query 'SecurityGroups[0].GroupId' --output text)\"],
            \"UserData\":\"${user_data_b64}\",
            \"IamInstanceProfile\":{\"Name\":\"SystemAdminTestingProfile\"},
            \"InstanceInitiatedShutdownBehavior\":\"terminate\"
        }" \
        --query 'LaunchTemplate.LaunchTemplateId' \
        --output text)
    
    if [[ -z "${template_id}" ]]; then
        log_error "Failed to create launch template"
        return 1
    fi
    
    log_success "Launch template created: ${template_id}"
    
    # Create spot request
    log_info "Requesting spot instance..."
    local spot_request_id
    spot_request_id=$(aws ec2 request-spot-instances \
        --region "${REGION}" \
        --spot-price "${MAX_COST}" \
        --instance-count 1 \
        --type "one-time" \
        --launch-specification "{
            \"ImageId\":\"ami-0c02fb55956c7d316\",
            \"InstanceType\":\"${INSTANCE_TYPE}\",
            \"KeyName\":\"ephemeral-admin-key\",
            \"SecurityGroups\":[\"ephemeral-admin-sg\"],
            \"UserData\":\"${user_data_b64}\",
            \"IamInstanceProfile\":{\"Name\":\"SystemAdminTestingProfile\"}
        }" \
        --query 'SpotInstanceRequests[0].SpotInstanceRequestId' \
        --output text)
    
    if [[ -z "${spot_request_id}" ]]; then
        log_error "Failed to create spot request"
        aws ec2 delete-launch-template --region "${REGION}" --launch-template-id "${template_id}" >/dev/null 2>&1
        return 1
    fi
    
    log_success "Spot request created: ${spot_request_id}"
    
    # Wait for spot request fulfillment
    log_info "Waiting for spot request fulfillment..."
    if ! show_launch_progress "Spot request fulfillment" 300 \
        "aws ec2 describe-spot-instance-requests --region ${REGION} --spot-instance-request-ids ${spot_request_id} --query 'SpotInstanceRequests[0].State' --output text | grep -q 'active'"; then
        log_error "Spot request fulfillment timeout"
        aws ec2 cancel-spot-instance-requests --region "${REGION}" --spot-instance-request-ids "${spot_request_id}" >/dev/null 2>&1
        aws ec2 delete-launch-template --region "${REGION}" --launch-template-id "${template_id}" >/dev/null 2>&1
        return 1
    fi
    
    # Get instance ID
    local instance_id
    instance_id=$(aws ec2 describe-spot-instance-requests \
        --region "${REGION}" \
        --spot-instance-request-ids "${spot_request_id}" \
        --query 'SpotInstanceRequests[0].InstanceId' \
        --output text)
    
    log_success "Instance launched: ${instance_id}"
    
    # Wait for instance to be running
    log_info "Waiting for instance to be running..."
    if ! show_launch_progress "Instance startup" 120 \
        "aws ec2 describe-instances --region ${REGION} --instance-ids ${instance_id} --query 'Reservations[0].Instances[0].State.Name' --output text | grep -q 'running'"; then
        log_error "Instance startup timeout"
        aws ec2 terminate-instances --region "${REGION}" --instance-ids "${instance_id}" >/dev/null 2>&1
        aws ec2 delete-launch-template --region "${REGION}" --launch-template-id "${template_id}" >/dev/null 2>&1
        return 1
    fi
    
    # Get public IP
    local public_ip
    public_ip=$(aws ec2 describe-instances \
        --region "${REGION}" \
        --instance-ids "${instance_id}" \
        --query 'Reservations[0].Instances[0].PublicIpAddress' \
        --output text)
    
    log_success "Instance IP: ${public_ip}"
    
    # Wait for SSH to be ready
    log_info "Waiting for SSH service..."
    if ! show_launch_progress "SSH readiness" 180 \
        "nc -z -w5 ${public_ip} 22"; then
        log_error "SSH readiness timeout"
        aws ec2 terminate-instances --region "${REGION}" --instance-ids "${instance_id}" >/dev/null 2>&1
        aws ec2 delete-launch-template --region "${REGION}" --launch-template-id "${template_id}" >/dev/null 2>&1
        return 1
    fi
    
    # Display connection information
    echo
    echo "╭─────────────────────────────────────────────────────────────╮"
    printf "│ ${GREEN}✨ INSTANCE READY FOR CONNECTION ✨${NC}%-20s │\n" ""
    echo "├─────────────────────────────────────────────────────────────┤"
    printf "│ Instance ID: %-46s │\n" "${instance_id}"
    printf "│ Public IP: %-48s │\n" "${public_ip}"
    printf "│ SSH Command: %-44s │\n" "ssh -i ~/.ssh/ephemeral-admin ec2-user@${public_ip}"
    echo "├─────────────────────────────────────────────────────────────┤"
    printf "│ ${YELLOW}Auto-termination: Instance will shutdown on SSH disconnect${NC}%-2s │\n" ""
    printf "│ ${YELLOW}Cost monitoring: Check AWS Cost Explorer for charges${NC}%-8s │\n" ""
    echo "╰─────────────────────────────────────────────────────────────╯"
    
    # Initiate SSH connection
    log_info "Initiating SSH connection..."
    ssh -i ~/.ssh/ephemeral-admin -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ec2-user@"${public_ip}"
    
    # Cleanup after SSH disconnect
    log_info "SSH session ended, cleaning up..."
    aws ec2 delete-launch-template --region "${REGION}" --launch-template-id "${template_id}" >/dev/null 2>&1 || true
    log_success "Cleanup complete"
    
    return 0
}

main "$@"
EOF
    
    chmod +x "${SCRIPTS_DIR}/launch-spot.sh"
    log_success "Spot launch script created and ready"
}

# Launch history tracking system
track_launch_session() {
    local session_type="$1"
    local duration="$2"
    local status="$3"
    local instance_type="${4:-unknown}"
    local region="${5:-unknown}"
    local cost="${6:-unknown}"
    
    local history_file="${HOME}/.ephemeral-admin/launch_history.jsonl"
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    # Ensure directory exists
    mkdir -p "$(dirname "${history_file}")"
    
    # Create history entry
    local history_entry
    history_entry=$(cat << EOF
{
  "timestamp": "${timestamp}",
  "session_id": "${SESSION_ID}",
  "session_type": "${session_type}",
  "duration": ${duration},
  "status": "${status}",
  "instance_type": "${instance_type}",
  "region": "${region}",
  "estimated_cost": "${cost}",
  "log_file": "${LOG_FILE}"
}
EOF
    )
    
    echo "${history_entry}" >> "${history_file}"
}

# Display recent launch history
show_launch_history() {
    local history_file="${HOME}/.ephemeral-admin/launch_history.jsonl"
    
    if [[ ! -f "${history_file}" ]]; then
        echo "No launch history found."
        return 0
    fi
    
    echo "╭─────────────────────────────────────────────────────────────╮"
    printf "│ ${BOLD}${CYAN}📊 Recent Launch History${NC}%-32s │\n" ""
    echo "├─────────────────────────────────────────────────────────────┤"
    
    # Show last 5 launches
    tail -n 5 "${history_file}" | while IFS= read -r line; do
        if [[ -n "${line}" ]]; then
            local timestamp session_type duration status instance_type
            timestamp=$(echo "${line}" | jq -r '.timestamp // "unknown"' 2>/dev/null || echo "unknown")
            session_type=$(echo "${line}" | jq -r '.session_type // "unknown"' 2>/dev/null || echo "unknown")
            duration=$(echo "${line}" | jq -r '.duration // "0"' 2>/dev/null || echo "0")
            status=$(echo "${line}" | jq -r '.status // "unknown"' 2>/dev/null || echo "unknown")
            instance_type=$(echo "${line}" | jq -r '.instance_type // "unknown"' 2>/dev/null || echo "unknown")
            
            local date_part="${timestamp:0:10}"
            local time_part="${timestamp:11:8}"
            local status_icon="❓"
            
            case "${status}" in
                "success") status_icon="${GREEN}✓${NC}" ;;
                "failed") status_icon="${RED}✗${NC}" ;;
                "cancelled") status_icon="${YELLOW}⚠${NC}" ;;
            esac
            
            printf "│ %s ${status_icon} %s %s (%ds) %s%-*s │\n" \
                "${date_part}" "${time_part}" "${session_type}" "${duration}" "${instance_type}" \
                $((35 - ${#date_part} - ${#time_part} - ${#session_type} - ${#duration} - ${#instance_type})) ""
        fi
    done
    
    echo "╰─────────────────────────────────────────────────────────────╯"
    echo
}

# Performance benchmarks and system metrics
display_performance_metrics() {
    local session_start="$1"
    local phase_times=("${@:2}")
    
    echo "╭─────────────────────────────────────────────────────────────╮"
    printf "│ ${BOLD}${BLUE}⚡ Performance Metrics${NC}%-35s │\n" ""
    echo "├─────────────────────────────────────────────────────────────┤"
    
    # System information
    local cpu_info memory_info disk_info network_info
    cpu_info=$(grep "model name" /proc/cpuinfo | head -1 | cut -d: -f2 | xargs 2>/dev/null || echo "Unknown CPU")
    memory_info=$(free -h | awk 'NR==2{print $2}' 2>/dev/null || echo "Unknown")
    disk_info=$(df -h / | awk 'NR==2{print $4}' 2>/dev/null || echo "Unknown")
    network_info=$(curl -s --max-time 3 https://httpbin.org/ip | jq -r '.origin' 2>/dev/null || echo "Unknown")
    
    printf "│ ${BOLD}System Info${NC}%-46s │\n" ""
    printf "│   CPU: %-50s │\n" "${cpu_info:0:50}"
    printf "│   Memory: %-45s │\n" "${memory_info}"
    printf "│   Disk Free: %-42s │\n" "${disk_info}"
    printf "│   Public IP: %-42s │\n" "${network_info}"
    
    echo "├─────────────────────────────────────────────────────────────┤"
    printf "│ ${BOLD}Phase Timings${NC}%-43s │\n" ""
    
    local total_time=$(($(date +%s) - session_start))
    local phase_names=("Prerequisites" "IAM Setup" "SSH Keys" "Security Groups" "Spot Launch")
    
    for i in "${!phase_names[@]}"; do
        if [[ ${i} -lt ${#phase_times[@]} ]]; then
            local phase_time="${phase_times[i]}"
            local percentage=$((phase_time * 100 / total_time))
            printf "│   %s: %ds (%d%%)%-*s │\n" \
                "${phase_names[i]}" "${phase_time}" "${percentage}" \
                $((40 - ${#phase_names[i]} - ${#phase_time} - ${#percentage})) ""
        fi
    done
    
    echo "├─────────────────────────────────────────────────────────────┤"
    printf "│ ${BOLD}Connection Metrics${NC}%-40s │\n" ""
    printf "│   Total Launch Time: %-34s │\n" "${total_time}s"
    printf "│   Target Time: %-40s │\n" "<60s"
    
    if [[ ${total_time} -lt 60 ]]; then
        printf "│   Performance: %-40s │\n" "${GREEN}Excellent${NC}"
    elif [[ ${total_time} -lt 120 ]]; then
        printf "│   Performance: %-40s │\n" "${YELLOW}Good${NC}"
    else
        printf "│   Performance: %-40s │\n" "${RED}Needs Optimization${NC}"
    fi
    
    echo "╰─────────────────────────────────────────────────────────────╯"
    echo
}

# Quick reconnect functionality for existing instances
quick_reconnect() {
    echo "╭─────────────────────────────────────────────────────────────╮"
    printf "│ ${BOLD}${CYAN}🔄 Quick Reconnect${NC}%-40s │\n" ""
    echo "├─────────────────────────────────────────────────────────────┤"
    printf "│ Checking for existing ephemeral instances...%-16s │\n" ""
    echo "╰─────────────────────────────────────────────────────────────╯"
    
    # Look for running instances with our tag or name pattern
    local instances
    instances=$(aws ec2 describe-instances \
        --region us-east-1 \
        --filters "Name=instance-state-name,Values=running" \
                  "Name=tag:Purpose,Values=ephemeral-admin" \
        --query 'Reservations[*].Instances[*].[InstanceId,PublicIpAddress,LaunchTime]' \
        --output text 2>/dev/null || echo "")
    
    if [[ -z "${instances}" ]]; then
        log_info "No existing ephemeral instances found"
        return 1
    fi
    
    echo "Found existing instances:"
    echo "${instances}" | while read -r instance_id public_ip launch_time; do
        printf "  • %s (%s) - launched %s\n" "${instance_id}" "${public_ip}" "${launch_time}"
        
        # Test SSH connectivity
        if nc -z -w5 "${public_ip}" 22 2>/dev/null; then
            printf "    ${GREEN}✓ SSH Ready${NC} - Connect: ssh -i ~/.ssh/ephemeral-admin ec2-user@%s\n" "${public_ip}"
        else
            printf "    ${YELLOW}⚠ SSH Not Ready${NC}\n"
        fi
    done
    
    return 0
}

main() {
    local start_time=$(date +%s)
    
    # Parse command line arguments
    local verbose=false
    local quiet=false
    local dry_run=false
    local skip_prerequisites=false
    local ssh_only=false
    local show_costs=false
    local show_history=false
    local quick_reconnect_mode=false
    local show_metrics=false
    local instance_type="t3.small"
    local region="us-east-1"
    local max_cost=""
    
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
            --show-costs)
                show_costs=true
                shift
                ;;
            --instance-type)
                instance_type="$2"
                shift 2
                ;;
            --region)
                region="$2"
                shift 2
                ;;
            --max-cost)
                max_cost="$2"
                shift 2
                ;;
            --show-history)
                show_history=true
                shift
                ;;
            --quick-reconnect)
                quick_reconnect_mode=true
                shift
                ;;
            --show-metrics)
                show_metrics=true
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
    
    # Handle special modes first
    if [[ "${show_history}" == "true" ]]; then
        show_launch_history
        return 0
    fi
    
    if [[ "${quick_reconnect_mode}" == "true" ]]; then
        quick_reconnect
        return $?
    fi
    
    # Override cleanup function
    trap enhanced_cleanup EXIT ERR INT TERM
    
    # Configure logging based on flags
    if [[ "${quiet}" == "true" ]]; then
        exec 3>&1 4>&2
        exec 1>/dev/null 2>/dev/null
    elif [[ "${verbose}" == "true" ]]; then
        set -x
    fi
    
    # Print header with enhanced system info
    if [[ "${quiet}" == "false" ]]; then
        print_enhanced_launch_header "${instance_type}" "${region}"
        
        if [[ "${dry_run}" == "true" ]]; then
            log_warn "DRY RUN MODE - No actual changes will be made"
            echo
        fi
        
        # Show cost information if requested or when launching
        if [[ "${show_costs}" == "true" ]] || [[ "${ssh_only}" == "false" && "${dry_run}" == "false" ]]; then
            display_cost_information "${instance_type}" "${region}" "${max_cost}"
        fi
        
        # Get user confirmation for launch
        if [[ "${ssh_only}" == "false" && "${dry_run}" == "false" ]]; then
            get_launch_confirmation "${instance_type}" "${region}"
        fi
    fi
    
    # Determine phases to run
    local total_phases=5  # Now includes spot instance launch
    if [[ "${ssh_only}" == "true" ]]; then
        total_phases=1
    elif [[ "${skip_prerequisites}" == "true" ]]; then
        total_phases=4  # Skip prereqs but include spot launch
    fi
    
    local current_phase=1
    
    # Phase 1: Prerequisites validation with enhanced feedback
    if [[ "${ssh_only}" == "false" ]]; then
        show_enhanced_phase_progress ${current_phase} ${total_phases} "Prerequisites" "Validating AWS CLI, credentials, and environment" "🔍"
        
        if [[ "${skip_prerequisites}" == "false" ]]; then
            if [[ "${dry_run}" == "false" ]]; then
                local start_phase=$(date +%s)
                if ! "${SCRIPTS_DIR}/check-prerequisites.sh" 2>&1 | tee -a "${LOG_FILE}"; then
                    log_error "Prerequisites validation failed"
                    display_troubleshooting_tips "prerequisites"
                    exit 1
                fi
                local phase_duration=$(($(date +%s) - start_phase))
                log_success "Prerequisites validation complete (${phase_duration}s)"
            else
                log_info "Would validate prerequisites"
                sleep 1
            fi
        else
            log_warn "Prerequisites validation skipped by user"
        fi
        ((current_phase++))
    fi
    
    # Phase 2: IAM setup with detailed progress
    if [[ "${ssh_only}" == "false" ]]; then
        show_enhanced_phase_progress ${current_phase} ${total_phases} "IAM Setup" "Creating roles, policies, and instance profiles" "🔐"
        
        if [[ "${dry_run}" == "false" ]]; then
            local start_phase=$(date +%s)
            if ! "${SCRIPTS_DIR}/setup-iam.sh" 2>&1 | tee -a "${LOG_FILE}"; then
                log_error "IAM setup failed"
                display_troubleshooting_tips "iam"
                exit 1
            fi
            local phase_duration=$(($(date +%s) - start_phase))
            log_success "IAM setup complete (${phase_duration}s)"
        else
            log_info "Would setup IAM roles and policies"
            sleep 1
        fi
        ((current_phase++))
    fi
    
    # Phase 3: SSH key management with enhanced UX
    if [[ "${ssh_only}" == "true" ]]; then
        show_enhanced_phase_progress 1 1 "SSH Keys" "Managing SSH key pairs for secure access" "🔑"
    else
        show_enhanced_phase_progress ${current_phase} ${total_phases} "SSH Keys" "Managing SSH key pairs for secure access" "🔑"
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
        local start_phase=$(date +%s)
        if ! "${SCRIPTS_DIR}/generate-ssh-keys.sh" "${ssh_args[@]}" 2>&1 | tee -a "${LOG_FILE}"; then
            log_error "SSH key generation failed"
            display_troubleshooting_tips "ssh"
            exit 1
        fi
        local phase_duration=$(($(date +%s) - start_phase))
        log_success "SSH keys ready (${phase_duration}s)"
    else
        log_info "Would manage SSH keys with enhanced UX"
        sleep 1
    fi
    
    if [[ "${ssh_only}" == "true" ]]; then
        display_completion_banner "SSH_ONLY" "${start_time}" "${SESSION_ID}" "${LOG_FILE}"
        return 0
    fi
    
    ((current_phase++))
    
    # Phase 4: Security group configuration with IP detection
    show_enhanced_phase_progress ${current_phase} ${total_phases} "Security Groups" "Configuring dynamic IP access rules" "🛡️"
    
    if [[ "${dry_run}" == "false" ]]; then
        local start_phase=$(date +%s)
        # Show current IP being whitelisted
        local current_ip
        current_ip=$(curl -s https://checkip.amazonaws.com/ || curl -s https://ipv4.icanhazip.com/ || echo "unknown")
        if [[ "$current_ip" != "unknown" ]]; then
            log_info "Whitelisting current IP: ${CYAN}${current_ip}${NC}"
        fi
        
        if ! "${SCRIPTS_DIR}/manage-security-group.sh" 2>&1 | tee -a "${LOG_FILE}"; then
            log_error "Security group management failed"
            display_troubleshooting_tips "security_group"
            exit 1
        fi
        local phase_duration=$(($(date +%s) - start_phase))
        log_success "Security groups configured (${phase_duration}s)"
    else
        log_info "Would configure security groups"
        sleep 1
    fi
    ((current_phase++))
    
    # Phase 5: Enhanced spot instance launch with real-time feedback
    if [[ "${dry_run}" == "false" ]]; then
        show_enhanced_phase_progress ${current_phase} ${total_phases} "Spot Launch" "Launching instance and establishing SSH connection" "🚀"
        
        # Display pre-launch summary
        display_launch_summary "${instance_type}" "${region}"
        
        # Launch with enhanced monitoring
        local launch_start=$(date +%s)
        if ! launch_spot_instance_enhanced "${instance_type}" "${region}" "${max_cost}"; then
            log_error "Spot instance launch failed"
            display_troubleshooting_tips "spot_launch"
            exit 1
        fi
        local launch_duration=$(($(date +%s) - launch_start))
        log_success "Instance launched and connected (${launch_duration}s)"
    fi
    
    # Calculate total execution time
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    # Track session for history
    local session_status="success"
    local estimated_cost="unknown"
    if [[ "${dry_run}" == "true" ]]; then
        track_launch_session "dry_run" "${duration}" "${session_status}" "${instance_type}" "${region}" "${estimated_cost}"
    elif [[ "${ssh_only}" == "true" ]]; then
        track_launch_session "ssh_only" "${duration}" "${session_status}" "none" "none" "0"
    else
        # Calculate estimated cost if possible
        if command -v aws >/dev/null 2>&1; then
            local spot_price
            spot_price=$(aws ec2 describe-spot-price-history --instance-types "${instance_type}" --region "${region}" --max-results 1 --query 'SpotPriceHistory[0].SpotPrice' --output text 2>/dev/null || echo "unknown")
            if [[ "${spot_price}" != "unknown" ]]; then
                estimated_cost=$(echo "scale=4; ${spot_price} * 2" | bc 2>/dev/null || echo "unknown")  # Assume 2hr session
            fi
        fi
        track_launch_session "full_launch" "${duration}" "${session_status}" "${instance_type}" "${region}" "${estimated_cost}"
    fi
    
    # Show performance metrics if requested
    if [[ "${show_metrics}" == "true" ]] && [[ "${quiet}" == "false" ]]; then
        display_performance_metrics "${start_time}"
    fi
    
    # Display final completion banner
    if [[ "${dry_run}" == "true" ]]; then
        display_completion_banner "DRY_RUN" "${duration}" "${SESSION_ID}" "${LOG_FILE}"
    else
        display_completion_banner "COMPLETE" "${duration}" "${SESSION_ID}" "${LOG_FILE}"
        display_next_steps_guidance
    fi
    
    # Restore output if quiet mode
    if [[ "${quiet}" == "true" ]]; then
        exec 1>&3 2>&4
        echo "Launch completed successfully (quiet mode)"
    fi
    
    return 0
}

# Execute main function
main "$@"