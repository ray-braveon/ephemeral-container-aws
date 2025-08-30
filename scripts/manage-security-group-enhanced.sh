#!/bin/bash

# Enhanced Security Group Management for Issue #2
# Provides comprehensive security group management with dynamic IP detection

set -euo pipefail

# Configuration
REGION="${AWS_REGION:-us-east-1}"
SECURITY_GROUP_NAME="ephemeral-admin-sg"
SSH_PORT=22

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1" >&2
}

# Enhanced IP detection with multiple fallback services
detect_current_ip() {
    local ip=""
    local services=(
        "https://checkip.amazonaws.com"
        "https://ipinfo.io/ip"
        "https://api.ipify.org"
        "https://icanhazip.com"
        "https://ifconfig.me/ip"
    )
    
    log "Detecting current public IP address..."
    
    for service in "${services[@]}"; do
        if ip=$(curl -s --connect-timeout 10 --max-time 15 "$service" 2>/dev/null); then
            # Validate IP format
            if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
                # Additional validation for valid IP ranges
                IFS='.' read -ra OCTETS <<< "$ip"
                local valid=true
                for octet in "${OCTETS[@]}"; do
                    if ((octet < 0 || octet > 255)); then
                        valid=false
                        break
                    fi
                done
                
                if [[ "$valid" == "true" ]]; then
                    log "Current IP detected: $ip (via $service)"
                    echo "$ip"
                    return 0
                fi
            fi
        fi
    done
    
    error "Failed to detect current IP from all services"
    return 1
}

# Get or create security group
ensure_security_group() {
    local vpc_id
    vpc_id=$(aws ec2 describe-vpcs \
        --region "$REGION" \
        --filters "Name=is-default,Values=true" \
        --query 'Vpcs[0].VpcId' \
        --output text)
    
    if [[ "$vpc_id" == "None" || -z "$vpc_id" ]]; then
        error "No default VPC found in region $REGION"
        return 1
    fi
    
    # Check if security group already exists
    local sg_id
    sg_id=$(aws ec2 describe-security-groups \
        --region "$REGION" \
        --filters "Name=group-name,Values=$SECURITY_GROUP_NAME" "Name=vpc-id,Values=$vpc_id" \
        --query 'SecurityGroups[0].GroupId' \
        --output text 2>/dev/null || echo "None")
    
    if [[ "$sg_id" != "None" && -n "$sg_id" ]]; then
        log "Security group already exists: $sg_id"
        echo "$sg_id"
        return 0
    fi
    
    # Create security group
    sg_id=$(aws ec2 create-security-group \
        --region "$REGION" \
        --group-name "$SECURITY_GROUP_NAME" \
        --description "Ephemeral AWS Container - Dynamic SSH Access" \
        --vpc-id "$vpc_id" \
        --query 'GroupId' \
        --output text)
    
    if [[ -z "$sg_id" ]]; then
        error "Failed to create security group"
        return 1
    fi
    
    log "Security group created: $sg_id"
    
    # Add tags
    aws ec2 create-tags \
        --region "$REGION" \
        --resources "$sg_id" \
        --tags Key=Name,Value="$SECURITY_GROUP_NAME" Key=Purpose,Value="EphemeralContainer"
    
    echo "$sg_id"
}

# Clean up old SSH rules
cleanup_old_rules() {
    local sg_id="$1"
    local current_ip="$2"
    
    log "Cleaning up old SSH rules..."
    
    # Get existing SSH rules
    local existing_rules
    existing_rules=$(aws ec2 describe-security-groups \
        --region "$REGION" \
        --group-ids "$sg_id" \
        --query "SecurityGroups[0].IpPermissions[?FromPort==\`$SSH_PORT\`].IpRanges[].CidrIp" \
        --output text)
    
    if [[ -n "$existing_rules" ]]; then
        for rule in $existing_rules; do
            local rule_ip="${rule%/32}"
            if [[ "$rule_ip" != "$current_ip" ]]; then
                log "Removing old SSH rule: $rule"
                aws ec2 revoke-security-group-ingress \
                    --region "$REGION" \
                    --group-id "$sg_id" \
                    --protocol tcp \
                    --port "$SSH_PORT" \
                    --cidr "$rule" || warn "Failed to remove rule: $rule"
            fi
        done
    fi
}

# Add SSH rule for current IP
add_ssh_rule() {
    local sg_id="$1"
    local ip="$2"
    local cidr="${ip}/32"
    
    log "Adding SSH access for IP: $ip"
    
    # Check if rule already exists
    local existing_rule
    existing_rule=$(aws ec2 describe-security-groups \
        --region "$REGION" \
        --group-ids "$sg_id" \
        --query "SecurityGroups[0].IpPermissions[?FromPort==\`$SSH_PORT\`].IpRanges[?CidrIp==\`$cidr\`].CidrIp" \
        --output text)
    
    if [[ "$existing_rule" == "$cidr" ]]; then
        log "SSH rule already exists for IP: $ip"
        return 0
    fi
    
    # Add the new rule
    if aws ec2 authorize-security-group-ingress \
        --region "$REGION" \
        --group-id "$sg_id" \
        --protocol tcp \
        --port "$SSH_PORT" \
        --cidr "$cidr"; then
        log "SSH access granted for IP: $ip"
    else
        error "Failed to add SSH rule"
        return 1
    fi
}

# Main function
main() {
    log "Starting enhanced security group management"
    
    # Validate AWS CLI
    if ! command -v aws >/dev/null 2>&1; then
        error "AWS CLI not found"
        exit 1
    fi
    
    # Validate credentials
    if ! aws sts get-caller-identity --region "$REGION" >/dev/null 2>&1; then
        error "AWS credentials not configured or invalid"
        exit 1
    fi
    
    # Detect current IP
    local current_ip
    if ! current_ip=$(detect_current_ip); then
        exit 1
    fi
    
    # Ensure security group exists
    local sg_id
    if ! sg_id=$(ensure_security_group); then
        exit 1
    fi
    
    # Clean up old rules
    cleanup_old_rules "$sg_id" "$current_ip"
    
    # Add SSH rule for current IP
    if ! add_ssh_rule "$sg_id" "$current_ip"; then
        exit 1
    fi
    
    log "Security group management completed successfully"
    echo "$sg_id"
}

# Execute if called directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi