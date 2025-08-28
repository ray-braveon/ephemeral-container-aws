#!/bin/bash
# manage-security-group.sh - Manage dynamic security groups for SSH access
# Issue #1: AWS Prerequisites and IAM Setup
# Version: 1.0.0

set -euo pipefail

# Configuration
readonly SG_NAME="ephemeral-admin-sg"
readonly SG_DESCRIPTION="Security group for ephemeral admin instances"
readonly REGION="us-east-1"
readonly VPC_ID_CACHE="/tmp/ephemeral-vpc-id"

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

# Detect current public IP
detect_public_ip() {
    log_info "Detecting current public IP address"
    
    local ip=""
    local services=(
        "https://ipv4.icanhazip.com"
        "https://api.ipify.org"
        "https://checkip.amazonaws.com"
    )
    
    for service in "${services[@]}"; do
        ip=$(curl -s --max-time 5 "${service}" 2>/dev/null | tr -d '[:space:]')
        
        # Validate IP format
        if [[ "${ip}" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
            log_success "Detected IP: ${ip}"
            echo "${ip}"
            return 0
        fi
    done
    
    echo "Error: Failed to detect public IP"
    return 1
}

# Get default VPC ID
get_default_vpc_id() {
    # Check cache first
    if [[ -f "${VPC_ID_CACHE}" ]] && [[ $(find "${VPC_ID_CACHE}" -mmin -60 2>/dev/null) ]]; then
        cat "${VPC_ID_CACHE}"
        return 0
    fi
    
    local vpc_id
    vpc_id=$(aws ec2 describe-vpcs \
        --filters "Name=is-default,Values=true" \
        --region "${REGION}" \
        --query "Vpcs[0].VpcId" \
        --output text)
    
    if [[ -z "${vpc_id}" || "${vpc_id}" == "None" ]]; then
        echo "Error: No default VPC found"
        return 1
    fi
    
    # Cache the VPC ID
    echo "${vpc_id}" > "${VPC_ID_CACHE}"
    echo "${vpc_id}"
}

# Check if security group exists
check_sg_exists() {
    local sg_id
    sg_id=$(aws ec2 describe-security-groups \
        --filters "Name=group-name,Values=${SG_NAME}" \
        --region "${REGION}" \
        --query "SecurityGroups[0].GroupId" \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "${sg_id}" && "${sg_id}" != "None" ]]; then
        echo "${sg_id}"
        return 0
    fi
    
    return 1
}

# Create security group
create_security_group() {
    log_info "Creating security group: ${SG_NAME}"
    
    local vpc_id
    vpc_id=$(get_default_vpc_id)
    
    local sg_id
    sg_id=$(aws ec2 create-security-group \
        --group-name "${SG_NAME}" \
        --description "${SG_DESCRIPTION}" \
        --vpc-id "${vpc_id}" \
        --region "${REGION}" \
        --tag-specifications "ResourceType=security-group,Tags=[{Key=Project,Value=ephemeral-container-claude},{Key=Purpose,Value=ssh-access},{Key=Name,Value=${SG_NAME}}]" \
        --query "GroupId" \
        --output text)
    
    log_success "Created security group: ${sg_id}"
    echo "${sg_id}"
}

# Clean up old rules
cleanup_old_rules() {
    local sg_id=$1
    
    log_info "Cleaning up old security group rules"
    
    # Get all ingress rules
    local rules
    rules=$(aws ec2 describe-security-groups \
        --group-ids "${sg_id}" \
        --region "${REGION}" \
        --query "SecurityGroups[0].IpPermissions" \
        --output json)
    
    if [[ "${rules}" == "[]" || "${rules}" == "null" ]]; then
        log_info "No existing rules to clean up"
        return 0
    fi
    
    # Count rules removed
    local count=0
    
    # Parse and remove SSH rules (port 22)
    echo "${rules}" | jq -c '.[] | select(.FromPort == 22 and .ToPort == 22)' | while read -r rule; do
        local cidr
        cidr=$(echo "${rule}" | jq -r '.IpRanges[0].CidrIp // empty')
        
        if [[ -n "${cidr}" ]]; then
            aws ec2 revoke-security-group-ingress \
                --group-id "${sg_id}" \
                --protocol tcp \
                --port 22 \
                --cidr "${cidr}" \
                --region "${REGION}" \
                --output text > /dev/null 2>&1 || true
            ((count++))
        fi
    done
    
    if [[ ${count} -gt 0 ]]; then
        log_success "Removed ${count} old rules"
    fi
}

# Add SSH rule for current IP
add_ssh_rule() {
    local sg_id=$1
    local ip=$2
    
    log_info "Adding SSH rule for IP: ${ip}"
    
    # Check if rule already exists
    local existing_rule
    existing_rule=$(aws ec2 describe-security-groups \
        --group-ids "${sg_id}" \
        --region "${REGION}" \
        --query "SecurityGroups[0].IpPermissions[?FromPort==\`22\` && ToPort==\`22\` && IpRanges[?CidrIp==\`${ip}/32\`]]" \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "${existing_rule}" ]]; then
        log_warn "SSH rule for ${ip} already exists"
        return 0
    fi
    
    # Add the rule
    aws ec2 authorize-security-group-ingress \
        --group-id "${sg_id}" \
        --protocol tcp \
        --port 22 \
        --cidr "${ip}/32" \
        --region "${REGION}" \
        --output text > /dev/null
    
    log_success "Added SSH ingress rule for ${ip}/32"
}

# Ensure outbound rules allow all traffic
ensure_egress_rules() {
    local sg_id=$1
    
    log_info "Ensuring egress rules allow all traffic"
    
    # Check if default egress rule exists
    local egress_rules
    egress_rules=$(aws ec2 describe-security-groups \
        --group-ids "${sg_id}" \
        --region "${REGION}" \
        --query "SecurityGroups[0].IpPermissionsEgress" \
        --output json)
    
    # Security groups have default allow-all egress, just verify
    if [[ "${egress_rules}" != "[]" && "${egress_rules}" != "null" ]]; then
        log_success "Egress rules configured (all traffic allowed)"
    else
        log_warn "No egress rules found, adding allow-all rule"
        
        aws ec2 authorize-security-group-egress \
            --group-id "${sg_id}" \
            --protocol all \
            --cidr "0.0.0.0/0" \
            --region "${REGION}" \
            --output text > /dev/null
    fi
}

# Main execution
main() {
    echo "=== Security Group Management ==="
    echo
    
    # Detect current IP
    local current_ip
    current_ip=$(detect_public_ip)
    
    # Check if security group exists
    local sg_id
    if sg_id=$(check_sg_exists); then
        log_info "Security group exists: ${sg_id}"
    else
        sg_id=$(create_security_group)
    fi
    
    # Clean up old rules
    cleanup_old_rules "${sg_id}"
    
    # Add rule for current IP
    add_ssh_rule "${sg_id}" "${current_ip}"
    
    # Ensure egress rules
    ensure_egress_rules "${sg_id}"
    
    echo
    echo -e "${GREEN}✓ Security group configuration complete${NC}"
    echo "  Security Group ID: ${sg_id}"
    echo "  Security Group Name: ${SG_NAME}"
    echo "  Allowed IP: ${current_ip}/32"
    echo "  Port: 22 (SSH)"
    
    return 0
}

# Execute if run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi