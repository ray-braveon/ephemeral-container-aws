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
main() {
    echo "=== SSH Key Management ==="
    echo
    
    # Validate AWS credentials first
    validate_aws_credentials || exit 1
    
    # Check if keys need generation
    if check_local_key_exists; then
        log_info "SSH key pair found: ${KEY_PATH}"
        
        # Check key age
        if ! check_key_age; then
            log_info "Rotating SSH key..."
            
            # Backup old key
            mv "${KEY_PATH}" "${KEY_PATH}.old"
            mv "${KEY_PATH}.pub" "${KEY_PATH}.pub.old"
            
            generate_ssh_key
        else
            validate_key_integrity
        fi
    else
        log_info "No existing SSH key found"
        generate_ssh_key
    fi
    
    # Import to AWS
    import_key_to_aws
    
    echo
    echo -e "${GREEN}✓ SSH key management complete${NC}"
    echo "  Private key: ${KEY_PATH}"
    echo "  Public key: ${KEY_PATH}.pub"
    echo "  AWS key name: ${KEY_NAME}"
    
    return 0
}

# Execute if run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi