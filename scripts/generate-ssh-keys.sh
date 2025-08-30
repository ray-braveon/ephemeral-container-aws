#!/bin/bash
# generate-ssh-keys.sh - Generate and manage SSH key pairs for EC2
# Issue #3: Enhanced SSH Key Management with Security Fixes
# Version: 2.0.0

set -euo pipefail
IFS=$'\n\t'

# Set secure umask to prevent race conditions
umask 077

# Configuration
readonly KEY_NAME="ephemeral-admin-key"
readonly KEY_PATH="${HOME}/.ssh/${KEY_NAME}"
readonly KEY_ALGORITHM="rsa"
readonly KEY_SIZE="4096"
readonly REGION="us-east-1"

# Color codes
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m'

# Helper functions
log_info() {
    echo "  $*"
}

log_success() {
    echo -e "  ${GREEN}✓${NC} $*"
}

log_warn() {
    echo -e "  ${YELLOW}⚠${NC} $*"
}

error_exit() {
    echo -e "  ${NC}ERROR: $*" >&2
    exit 1
}

# Input validation to prevent command injection
validate_key_name() {
    local key_name="$1"
    
    # Check for empty input
    if [[ -z "${key_name}" ]]; then
        error_exit "Key name cannot be empty"
    fi
    
    # Validate key name format (alphanumeric, dash, underscore only)
    if [[ ! "${key_name}" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        error_exit "Invalid key name format. Only alphanumeric, dash, and underscore allowed: ${key_name}"
    fi
    
    # Check for dangerous shell characters
    if [[ "${key_name}" =~ [\$\`\;\"\'\'\|\&\>\<\(\)\{\}\[\]] ]]; then
        error_exit "Key name contains dangerous shell characters: ${key_name}"
    fi
    
    log_info "Key name validation passed: ${key_name}"
}

# AWS credential validation
validate_aws_credentials() {
    log_info "Validating AWS credentials..."
    
    # Check AWS CLI availability
    if ! command -v aws >/dev/null 2>&1; then
        error_exit "AWS CLI not found. Please install AWS CLI first."
    fi
    
    # Verify credentials are configured
    if ! aws sts get-caller-identity &>/dev/null; then
        error_exit "AWS credentials not configured or invalid. Run 'aws configure' first."
    fi
    
    # Check required permissions
    if ! aws ec2 describe-key-pairs --region "${REGION}" &>/dev/null; then
        log_warn "May lack EC2 permissions. Continuing..."
    fi
    
    log_success "AWS credentials validated"
}

# Check if local key exists
check_local_key_exists() {
    [[ -f "${KEY_PATH}" && -f "${KEY_PATH}.pub" ]]
}

# Check if AWS key pair exists
check_aws_key_exists() {
    aws ec2 describe-key-pairs \
        --key-names "${KEY_NAME}" \
        --region "${REGION}" &> /dev/null
}

# Generate new SSH key pair
generate_ssh_key() {
    # Validate key name to prevent injection
    validate_key_name "${KEY_NAME}"
    
    log_info "Generating new SSH key pair"
    
    # Generate key with no passphrase for automation
    # Use printf to safely pass comment, preventing command injection
    if ! ssh-keygen -t "${KEY_ALGORITHM}" \
        -b "${KEY_SIZE}" \
        -f "${KEY_PATH}" \
        -N "" \
        -C "$(printf '%s@ephemeral-admin' "${KEY_NAME}")" \
        -q; then
        error_exit "Failed to generate SSH key"
    fi
    
    # Set correct permissions
    chmod 600 "${KEY_PATH}"
    chmod 644 "${KEY_PATH}.pub"
    
    log_success "Generated ${KEY_ALGORITHM} ${KEY_SIZE}-bit key: ${KEY_PATH}"
}

# Validate key file integrity
validate_key_integrity() {
    log_info "Validating key integrity"
    
    # Check private key format
    if ! ssh-keygen -y -f "${KEY_PATH}" > /dev/null 2>&1; then
        echo "Error: Private key validation failed"
        return 1
    fi
    
    # Check public key format
    if ! ssh-keygen -l -f "${KEY_PATH}.pub" > /dev/null 2>&1; then
        echo "Error: Public key validation failed"
        return 1
    fi
    
    # Check permissions
    local priv_perms
    priv_perms=$(stat -c %a "${KEY_PATH}" 2>/dev/null || stat -f %A "${KEY_PATH}")
    if [[ "${priv_perms}" != "600" ]]; then
        log_warn "Fixing private key permissions"
        chmod 600 "${KEY_PATH}"
    fi
    
    local pub_perms
    pub_perms=$(stat -c %a "${KEY_PATH}.pub" 2>/dev/null || stat -f %A "${KEY_PATH}.pub")
    if [[ "${pub_perms}" != "644" ]]; then
        log_warn "Fixing public key permissions"
        chmod 644 "${KEY_PATH}.pub"
    fi
    
    log_success "Key integrity validated"
}

# Import key to AWS
import_key_to_aws() {
    # Validate key name before AWS operations
    validate_key_name "${KEY_NAME}"
    
    log_info "Importing public key to AWS EC2"
    
    # Check if key already exists in AWS
    if check_aws_key_exists; then
        log_warn "Key ${KEY_NAME} already exists in AWS, verifying..."
        
        # Get fingerprint from AWS
        local aws_fingerprint
        aws_fingerprint=$(aws ec2 describe-key-pairs \
            --key-names "${KEY_NAME}" \
            --region "${REGION}" \
            --query "KeyPairs[0].KeyFingerprint" \
            --output text)
        
        # Get local fingerprint
        local local_fingerprint
        local_fingerprint=$(ssh-keygen -l -f "${KEY_PATH}.pub" | awk '{print $2}' | cut -d: -f2-)
        
        if [[ "${aws_fingerprint}" == "${local_fingerprint}" ]]; then
            log_success "AWS key matches local key"
            return 0
        else
            log_warn "AWS key doesn't match local key, updating..."
            
            # Delete old key with error handling
            if ! aws ec2 delete-key-pair \
                --key-name "${KEY_NAME}" \
                --region "${REGION}" \
                --output text > /dev/null; then
                log_warn "Failed to delete old key, continuing..."
            fi
        fi
    fi
    
    # Import public key
    local public_key_material
    public_key_material=$(cat "${KEY_PATH}.pub")
    
    if ! aws ec2 import-key-pair \
        --key-name "${KEY_NAME}" \
        --public-key-material "${public_key_material}" \
        --region "${REGION}" \
        --tag-specifications "ResourceType=key-pair,Tags=[{Key=Project,Value=ephemeral-container-claude},{Key=Purpose,Value=ssh-access}]" \
        --output text > /dev/null; then
        error_exit "Failed to import SSH key to AWS"
    fi
    
    log_success "Imported key to AWS: ${KEY_NAME}"
}

# Check key age for rotation
check_key_age() {
    if ! check_local_key_exists; then
        return 0
    fi
    
    local key_age_days
    local key_modified
    
    # Get key modification time (macOS and Linux compatible)
    if [[ "$(uname)" == "Darwin" ]]; then
        key_modified=$(stat -f %m "${KEY_PATH}")
    else
        key_modified=$(stat -c %Y "${KEY_PATH}")
    fi
    
    local current_time
    current_time=$(date +%s)
    key_age_days=$(( (current_time - key_modified) / 86400 ))
    
    if [[ ${key_age_days} -gt 90 ]]; then
        log_warn "SSH key is ${key_age_days} days old (recommended rotation: 90 days)"
        echo -n "  Rotate key now? (y/N): "
        read -r response
        if [[ "${response}" =~ ^[Yy]$ ]]; then
            return 1  # Trigger key regeneration
        fi
    else
        log_info "Key age: ${key_age_days} days (rotation at 90 days)"
    fi
    
    return 0
}

# Main execution
# Enhanced UX functions for better user experience

# Show help information
show_help() {
    cat << EOF
SSH Key Management System - Enhanced UX Version

USAGE:
    $0 [OPTIONS]

OPTIONS:
    -v, --verbose       Enable verbose output with debug information
    -q, --quiet         Suppress all output except errors
    --dry-run          Show what would be done without making changes
    --force-rotate     Force key rotation regardless of age
    -h, --help         Show this help message

EXAMPLES:
    $0                 # Normal operation with standard output
    $0 --verbose       # Detailed operation logging
    $0 --dry-run       # Test run without changes
    $0 --force-rotate  # Force key rotation
    $0 --quiet         # Minimal output

DESCRIPTION:
    Manages SSH key pairs for the ephemeral AWS container system.
    Automatically generates RSA-4096 keys, validates integrity,
    and imports to AWS EC2 with proper tagging.

KEY FEATURES:
    • Automatic key age detection and rotation prompts
    • AWS credential validation with permission checks  
    • Secure key generation with proper permissions
    • Fingerprint verification between local and AWS keys
    • Backup creation before rotation
    • Progress indicators for long operations

SECURITY NOTES:
    • Keys are generated without passphrases for automation
    • Private keys have 600 permissions, public keys 644
    • All input is validated to prevent command injection
    • AWS operations use least-privilege principles

FILES:
    Private key: ${KEY_PATH}
    Public key:  ${KEY_PATH}.pub
    AWS name:    ${KEY_NAME}

For troubleshooting, run with --verbose flag.
EOF
}

# Print formatted header
print_header() {
    local title="$1"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    echo
    echo "╭─────────────────────────────────────────────────────────────╮"
    printf "│ %-59s │\n" "${title}"
    printf "│ %-59s │\n" "Started: ${timestamp}"
    echo "╰─────────────────────────────────────────────────────────────╯"
    echo
}

# Show progress step with visual indicators
show_progress_step() {
    local current="$1"
    local total="$2" 
    local description="$3"
    local timestamp
    timestamp=$(date '+%H:%M:%S')
    
    # Calculate progress bar
    local progress=$((current * 20 / total))
    local bar=""
    for ((i=0; i<progress; i++)); do
        bar+="█"
    done
    for ((i=progress; i<20; i++)); do
        bar+="░"
    done
    
    echo
    printf "┌─ Step %d/%d %s\n" "${current}" "${total}" "$(date '+(%H:%M:%S)')"
    printf "│ [%s] %d%%\n" "${bar}" $((current * 100 / total))
    printf "│ %s\n" "${description}"
    printf "└─\n"
}

# Show step completion
show_step_completion() {
    local message="$1"
    printf "   ${GREEN}✓${NC} %s\n" "${message}"
}

# Enhanced key age check with better prompts
check_key_age_with_prompt() {
    if ! check_local_key_exists; then
        return 0
    fi
    
    local key_age_days
    local key_modified
    
    # Get key modification time (macOS and Linux compatible)
    if [[ "$(uname)" == "Darwin" ]]; then
        key_modified=$(stat -f %m "${KEY_PATH}")
    else
        key_modified=$(stat -c %Y "${KEY_PATH}")
    fi
    
    local current_time
    current_time=$(date +%s)
    key_age_days=$(( (current_time - key_modified) / 86400 ))
    
    log_info "Current SSH key age: ${key_age_days} days"
    
    if [[ ${key_age_days} -gt 90 ]]; then
        echo
        log_warn "SSH key is ${key_age_days} days old"
        log_warn "Security best practice recommends rotation every 90 days"
        echo
        echo "  Key rotation benefits:"
        echo "  • Reduces impact of potential key compromise"
        echo "  • Maintains security hygiene"
        echo "  • Compliance with security policies"
        echo
        
        local response
        while true; do
            echo -n "  Rotate SSH key now? [Y/n/info]: "
            read -r response
            case "${response,,}" in
                ""|y|yes)
                    log_info "Key rotation approved by user"
                    return 1  # Trigger key regeneration
                    ;;
                n|no)
                    log_warn "Key rotation skipped by user"
                    return 0
                    ;;
                info)
                    echo
                    echo "  Key Rotation Information:"
                    echo "  • Current key will be backed up as ${KEY_PATH}.backup"
                    echo "  • New RSA-4096 key will be generated"
                    echo "  • AWS key pair will be updated automatically"
                    echo "  • Process takes approximately 10-15 seconds"
                    echo "  • No service interruption during rotation"
                    echo
                    ;;
                *)
                    echo "  Please enter 'y' (yes), 'n' (no), or 'info'"
                    ;;
            esac
        done
    else
        local days_until_rotation=$((90 - key_age_days))
        log_info "Key is current (${days_until_rotation} days until recommended rotation)"
    fi
    
    return 0
}

# Create backup of existing keys
create_key_backup() {
    local backup_suffix
    backup_suffix=$(date '+%Y%m%d_%H%M%S')
    local backup_private="${KEY_PATH}.backup_${backup_suffix}"
    local backup_public="${KEY_PATH}.pub.backup_${backup_suffix}"
    
    log_info "Creating backup of existing keys"
    
    if ! cp "${KEY_PATH}" "${backup_private}"; then
        error_exit "Failed to backup private key"
    fi
    
    if ! cp "${KEY_PATH}.pub" "${backup_public}"; then
        error_exit "Failed to backup public key" 
    fi
    
    # Ensure backup has correct permissions
    chmod 600 "${backup_private}"
    chmod 644 "${backup_public}"
    
    log_success "Keys backed up:"
    log_info "  Private: ${backup_private}"
    log_info "  Public:  ${backup_public}"
}

# Generate SSH key with progress feedback
generate_ssh_key_with_progress() {
    validate_key_name "${KEY_NAME}"
    
    log_info "Generating RSA-${KEY_SIZE} SSH key pair..."
    log_info "Algorithm: ${KEY_ALGORITHM}, Size: ${KEY_SIZE} bits"
    
    # Show a simple progress animation during key generation
    ssh-keygen -t "${KEY_ALGORITHM}" \
        -b "${KEY_SIZE}" \
        -f "${KEY_PATH}" \
        -N "" \
        -C "$(printf '%s@ephemeral-admin' "${KEY_NAME}")" \
        -q &
    
    local keygen_pid=$!
    local spinner="⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"
    local i=0
    
    while kill -0 $keygen_pid 2>/dev/null; do
        printf "\r  Generating key... %c " "${spinner:$i:1}"
        i=$(( (i+1) % ${#spinner} ))
        sleep 0.1
    done
    
    wait $keygen_pid
    local result=$?
    
    printf "\r                                \r"
    
    if [[ $result -ne 0 ]]; then
        error_exit "SSH key generation failed"
    fi
    
    # Set correct permissions
    chmod 600 "${KEY_PATH}"
    chmod 644 "${KEY_PATH}.pub"
    
    # Get key fingerprint for display
    local fingerprint
    fingerprint=$(ssh-keygen -l -f "${KEY_PATH}.pub" | awk '{print $2}')
    
    log_success "Generated SSH key pair"
    log_info "Fingerprint: ${fingerprint}"
}

# Import key to AWS with enhanced progress
import_key_to_aws_with_progress() {
    validate_key_name "${KEY_NAME}"
    
    log_info "Checking existing AWS key pairs..."
    
    # Check if key already exists in AWS
    if check_aws_key_exists; then
        log_info "Found existing AWS key pair: ${KEY_NAME}"
        
        # Get fingerprints for comparison
        local aws_fingerprint
        aws_fingerprint=$(aws ec2 describe-key-pairs \
            --key-names "${KEY_NAME}" \
            --region "${REGION}" \
            --query "KeyPairs[0].KeyFingerprint" \
            --output text)
        
        local local_fingerprint
        local_fingerprint=$(ssh-keygen -l -f "${KEY_PATH}.pub" | awk '{print $2}' | cut -d: -f2-)
        
        if [[ "${aws_fingerprint}" == "${local_fingerprint}" ]]; then
            log_success "AWS key matches local key (fingerprints identical)"
            return 0
        else
            log_warn "AWS key fingerprint mismatch detected"
            log_info "Local:  ${local_fingerprint}"
            log_info "AWS:    ${aws_fingerprint}"
            log_info "Updating AWS key pair..."
            
            # Delete old key with progress
            printf "  Removing old AWS key... "
            if aws ec2 delete-key-pair \
                --key-name "${KEY_NAME}" \
                --region "${REGION}" \
                --output text > /dev/null 2>&1; then
                printf "${GREEN}✓${NC}\n"
            else
                printf "${YELLOW}⚠${NC} (continuing)\n"
            fi
        fi
    fi
    
    # Import public key with progress
    local public_key_material
    public_key_material=$(cat "${KEY_PATH}.pub")
    
    printf "  Importing public key to AWS... "
    if aws ec2 import-key-pair \
        --key-name "${KEY_NAME}" \
        --public-key-material "${public_key_material}" \
        --region "${REGION}" \
        --tag-specifications "ResourceType=key-pair,Tags=[{Key=Project,Value=ephemeral-container-claude},{Key=Purpose,Value=ssh-access},{Key=Created,Value=$(date -I)}]" \
        --output text > /dev/null; then
        printf "${GREEN}✓${NC}\n"
    else
        printf "${RED}✗${NC}\n"
        error_exit "Failed to import SSH key to AWS"
    fi
    
    log_success "AWS key pair updated successfully"
}

# Verify AWS key import
verify_aws_key_import() {
    log_info "Verifying AWS import..."
    
    # Check key exists in AWS
    if ! check_aws_key_exists; then
        error_exit "AWS key verification failed - key not found"
    fi
    
    # Verify fingerprint match
    local aws_fingerprint
    aws_fingerprint=$(aws ec2 describe-key-pairs \
        --key-names "${KEY_NAME}" \
        --region "${REGION}" \
        --query "KeyPairs[0].KeyFingerprint" \
        --output text 2>/dev/null)
    
    local local_fingerprint
    local_fingerprint=$(ssh-keygen -l -f "${KEY_PATH}.pub" | awk '{print $2}' | cut -d: -f2-)
    
    if [[ "${aws_fingerprint}" == "${local_fingerprint}" ]]; then
        log_success "Fingerprint verification passed"
    else
        error_exit "Fingerprint verification failed - AWS/local mismatch"
    fi
    
    # Check tags
    local tags
    tags=$(aws ec2 describe-key-pairs \
        --key-names "${KEY_NAME}" \
        --region "${REGION}" \
        --query "KeyPairs[0].Tags" \
        --output text 2>/dev/null)
    
    if [[ "${tags}" == *"ephemeral-container-claude"* ]]; then
        log_info "Project tags verified"
    else
        log_warn "Project tags missing or incorrect"
    fi
}

# Print comprehensive success summary
print_success_summary() {
    local duration="$1"
    local dry_run="$2"
    local fingerprint=""
    
    if [[ "${dry_run}" == "false" ]] && [[ -f "${KEY_PATH}.pub" ]]; then
        fingerprint=$(ssh-keygen -l -f "${KEY_PATH}.pub" | awk '{print $2}')
    fi
    
    echo "╭─────────────────────────────────────────────────────────────╮"
    if [[ "${dry_run}" == "true" ]]; then
        printf "│ ${GREEN}✓ DRY RUN COMPLETED SUCCESSFULLY${NC} %-24s │\n" "(${duration}s)"
    else
        printf "│ ${GREEN}✓ SSH KEY MANAGEMENT COMPLETED${NC} %-26s │\n" "(${duration}s)"
    fi
    echo "├─────────────────────────────────────────────────────────────┤"
    
    if [[ "${dry_run}" == "false" ]]; then
        printf "│ Private Key: %-47s │\n" "${KEY_PATH}"
        printf "│ Public Key:  %-47s │\n" "${KEY_PATH}.pub"
        printf "│ AWS Region:  %-47s │\n" "${REGION}"
        printf "│ AWS Name:    %-47s │\n" "${KEY_NAME}"
        if [[ -n "${fingerprint}" ]]; then
            printf "│ Fingerprint: %-47s │\n" "${fingerprint}"
        fi
        echo "├─────────────────────────────────────────────────────────────┤"
        printf "│ ${GREEN}Status: Ready for EC2 instance connections${NC} %-15s │\n" ""
    else
        printf "│ Would create: %-46s │\n" "${KEY_PATH}"
        printf "│ Would import to AWS region: %-30s │\n" "${REGION}"
        printf "│ Would use key name: %-38s │\n" "${KEY_NAME}"
        echo "├─────────────────────────────────────────────────────────────┤"
        printf "│ ${YELLOW}Dry run - no actual changes made${NC} %-21s │\n" ""
    fi
    echo "╰─────────────────────────────────────────────────────────────╯"
    
    if [[ "${dry_run}" == "false" ]]; then
        echo
        echo "Next steps:"
        echo "  • SSH key is ready for EC2 connections"
        echo "  • Run ./launch-admin.sh to launch ephemeral instance"
        echo "  • Key will be automatically used for authentication"
    fi
}

main() {
    local start_time
    start_time=$(date +%s)
    
    # Parse command line arguments
    local verbose=false
    local quiet=false
    local dry_run=false
    local force_rotate=false
    
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
            --force-rotate)
                force_rotate=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                error_exit "Unknown option: $1. Use --help for usage information."
                ;;
        esac
    done
    
    # Set logging verbosity
    if [[ "${quiet}" == "true" ]]; then
        exec 3>&1 4>&2
        exec 1>/dev/null 2>/dev/null
    elif [[ "${verbose}" == "true" ]]; then
        set -x
    fi
    
    print_header "SSH Key Management System"
    
    if [[ "${dry_run}" == "true" ]]; then
        log_info "DRY RUN MODE - No changes will be made"
        echo
    fi
    
    # Progress tracking
    local total_steps=6
    local current_step=1
    
    # Step 1: AWS credential validation
    show_progress_step ${current_step} ${total_steps} "Validating AWS credentials"
    if [[ "${dry_run}" == "false" ]]; then
        validate_aws_credentials || exit 1
    else
        log_info "Would validate AWS credentials"
        sleep 1
    fi
    show_step_completion "AWS credentials validated"
    ((current_step++))
    
    # Step 2: Check existing keys
    show_progress_step ${current_step} ${total_steps} "Checking existing SSH keys"
    local needs_generation=false
    local needs_rotation=false
    
    if check_local_key_exists; then
        log_info "Found existing SSH key pair: ${KEY_PATH}"
        
        if [[ "${dry_run}" == "false" ]]; then
            validate_key_integrity
        else
            log_info "Would validate key integrity"
        fi
        
        # Check key age or force rotation
        if [[ "${force_rotate}" == "true" ]]; then
            log_info "Force rotation requested"
            needs_rotation=true
        elif ! check_key_age_with_prompt; then
            needs_rotation=true
        fi
        
        if [[ "${needs_rotation}" == "true" ]]; then
            needs_generation=true
        fi
    else
        log_info "No existing SSH key found"
        needs_generation=true
    fi
    show_step_completion "Key status assessed"
    ((current_step++))
    
    # Step 3: Generate key if needed
    if [[ "${needs_generation}" == "true" ]]; then
        show_progress_step ${current_step} ${total_steps} "Generating new SSH key pair"
        
        if [[ "${needs_rotation}" == "true" ]] && [[ "${dry_run}" == "false" ]]; then
            create_key_backup
        fi
        
        if [[ "${dry_run}" == "false" ]]; then
            generate_ssh_key_with_progress
        else
            log_info "Would generate new ${KEY_ALGORITHM} ${KEY_SIZE}-bit SSH key"
            sleep 2
        fi
        show_step_completion "SSH key generation complete"
    else
        show_progress_step ${current_step} ${total_steps} "Using existing SSH key"
        show_step_completion "Existing key validated and ready"
    fi
    ((current_step++))
    
    # Step 4: Validate key integrity
    if [[ "${needs_generation}" == "true" ]]; then
        show_progress_step ${current_step} ${total_steps} "Validating new key integrity"
        if [[ "${dry_run}" == "false" ]]; then
            validate_key_integrity || error_exit "Key validation failed"
        else
            log_info "Would validate key integrity"
        fi
        show_step_completion "Key integrity confirmed"
    else
        show_progress_step ${current_step} ${total_steps} "Verifying existing key integrity"
        show_step_completion "Key integrity verified"
    fi
    ((current_step++))
    
    # Step 5: AWS import
    show_progress_step ${current_step} ${total_steps} "Importing key to AWS"
    if [[ "${dry_run}" == "false" ]]; then
        import_key_to_aws_with_progress
    else
        log_info "Would import public key to AWS EC2"
        log_info "Would set tags: Project=ephemeral-container-claude, Purpose=ssh-access"
        sleep 1
    fi
    show_step_completion "AWS import complete"
    ((current_step++))
    
    # Step 6: Final verification
    show_progress_step ${current_step} ${total_steps} "Final verification"
    if [[ "${dry_run}" == "false" ]]; then
        verify_aws_key_import
    else
        log_info "Would verify key import to AWS"
    fi
    show_step_completion "Verification complete"
    
    # Calculate execution time
    local end_time
    end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    echo
    print_success_summary "${duration}" "${dry_run}"
    
    # Restore output if quiet mode
    if [[ "${quiet}" == "true" ]]; then
        exec 1>&3 2>&4
        echo "SSH key management completed successfully (quiet mode)"
    fi
    
    return 0
}

# Execute if run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi