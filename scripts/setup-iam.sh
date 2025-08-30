#!/bin/bash
# setup-iam.sh - IAM role and policy setup for ephemeral container system
# Issue #24: Missing IAM Role Creation Script
# Version: 1.0.0

set -euo pipefail
IFS=$'\n\t'

# Configuration
readonly ROLE_NAME="SystemAdminTestingRole"
readonly INSTANCE_PROFILE_NAME="SystemAdminTestingRole"
readonly REGION="${AWS_REGION:-us-east-1}"

# Color codes
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly RED='\033[0;31m'
readonly NC='\033[0m'

# Helper functions
log_info() {
    echo -e "  $*"
}

log_success() {
    echo -e "  ${GREEN}✓${NC} $*"
}

log_warn() {
    echo -e "  ${YELLOW}⚠${NC} $*"
}

log_error() {
    echo -e "  ${RED}✗${NC} $*" >&2
}

# Check if IAM role exists
check_role_exists() {
    aws iam get-role --role-name "$ROLE_NAME" --region "$REGION" &>/dev/null
}

# Check if instance profile exists
check_instance_profile_exists() {
    aws iam get-instance-profile --instance-profile-name "$INSTANCE_PROFILE_NAME" --region "$REGION" &>/dev/null
}

# Create IAM role with trust policy
create_iam_role() {
    log_info "Creating IAM role: $ROLE_NAME"
    
    # Define trust policy for EC2
    local trust_policy='{
        "Version": "2012-10-17",
        "Statement": [
            {
                "Effect": "Allow",
                "Principal": {
                    "Service": "ec2.amazonaws.com"
                },
                "Action": "sts:AssumeRole"
            }
        ]
    }'
    
    if aws iam create-role \
        --role-name "$ROLE_NAME" \
        --assume-role-policy-document "$trust_policy" \
        --description "Role for ephemeral container system administration" \
        --max-session-duration 3600 \
        --region "$REGION" &>/dev/null; then
        log_success "IAM role created: $ROLE_NAME"
        return 0
    else
        log_error "Failed to create IAM role"
        return 1
    fi
}

# Attach required policies to role
attach_policies() {
    log_info "Attaching policies to role"
    
    # List of AWS managed policies to attach
    local policies=(
        "arn:aws:iam::aws:policy/AmazonEC2SpotFleetTaggingRole"
        "arn:aws:iam::aws:policy/CloudWatchLogsCreateLogGroup"
    )
    
    for policy_arn in "${policies[@]}"; do
        if aws iam attach-role-policy \
            --role-name "$ROLE_NAME" \
            --policy-arn "$policy_arn" \
            --region "$REGION" &>/dev/null; then
            log_success "Attached policy: ${policy_arn##*/}"
        else
            log_warn "Failed to attach policy: ${policy_arn##*/}"
        fi
    done
    
    # Create and attach custom policy for security group management
    create_custom_policy
}

# Create custom policy for security group operations
create_custom_policy() {
    log_info "Creating custom security group policy"
    
    local policy_name="${ROLE_NAME}-SecurityGroupPolicy"
    local policy_document='{
        "Version": "2012-10-17",
        "Statement": [
            {
                "Effect": "Allow",
                "Action": [
                    "ec2:DescribeSecurityGroups",
                    "ec2:AuthorizeSecurityGroupIngress",
                    "ec2:RevokeSecurityGroupIngress",
                    "ec2:CreateSecurityGroup",
                    "ec2:DeleteSecurityGroup",
                    "ec2:DescribeInstances",
                    "ec2:DescribeInstanceStatus",
                    "ec2:TerminateInstances"
                ],
                "Resource": "*",
                "Condition": {
                    "StringEquals": {
                        "ec2:ResourceTag/Project": "ephemeral-container-claude"
                    }
                }
            },
            {
                "Effect": "Allow",
                "Action": [
                    "ec2:DescribeRegions",
                    "ec2:DescribeAvailabilityZones",
                    "ec2:DescribeImages",
                    "ec2:DescribeKeyPairs",
                    "ec2:DescribeSpotPriceHistory",
                    "ec2:RequestSpotInstances",
                    "ec2:CancelSpotInstanceRequests",
                    "ec2:DescribeSpotInstanceRequests"
                ],
                "Resource": "*"
            }
        ]
    }'
    
    # Check if policy already exists
    if aws iam get-policy --policy-arn "arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):policy/$policy_name" &>/dev/null; then
        log_warn "Custom policy already exists: $policy_name"
    else
        # Create the policy
        local policy_arn
        policy_arn=$(aws iam create-policy \
            --policy-name "$policy_name" \
            --policy-document "$policy_document" \
            --description "Security group management for ephemeral containers" \
            --region "$REGION" \
            --query 'Policy.Arn' \
            --output text 2>/dev/null)
        
        if [[ -n "$policy_arn" ]]; then
            log_success "Created custom policy: $policy_name"
            
            # Attach to role
            if aws iam attach-role-policy \
                --role-name "$ROLE_NAME" \
                --policy-arn "$policy_arn" \
                --region "$REGION" &>/dev/null; then
                log_success "Attached custom policy to role"
            fi
        else
            log_warn "Failed to create custom policy"
        fi
    fi
}

# Create instance profile
create_instance_profile() {
    log_info "Creating instance profile: $INSTANCE_PROFILE_NAME"
    
    if aws iam create-instance-profile \
        --instance-profile-name "$INSTANCE_PROFILE_NAME" \
        --region "$REGION" &>/dev/null; then
        log_success "Instance profile created"
        
        # Add role to instance profile
        if aws iam add-role-to-instance-profile \
            --instance-profile-name "$INSTANCE_PROFILE_NAME" \
            --role-name "$ROLE_NAME" \
            --region "$REGION" &>/dev/null; then
            log_success "Role added to instance profile"
        else
            log_error "Failed to add role to instance profile"
            return 1
        fi
    else
        log_error "Failed to create instance profile"
        return 1
    fi
}

# Validate IAM setup
validate_iam_setup() {
    log_info "Validating IAM setup"
    
    local validation_passed=true
    
    # Check role exists
    if check_role_exists; then
        log_success "Role exists: $ROLE_NAME"
    else
        log_error "Role not found: $ROLE_NAME"
        validation_passed=false
    fi
    
    # Check instance profile exists
    if check_instance_profile_exists; then
        log_success "Instance profile exists: $INSTANCE_PROFILE_NAME"
    else
        log_error "Instance profile not found: $INSTANCE_PROFILE_NAME"
        validation_passed=false
    fi
    
    # Check role is in instance profile
    if aws iam get-instance-profile \
        --instance-profile-name "$INSTANCE_PROFILE_NAME" \
        --query "InstanceProfile.Roles[?RoleName=='$ROLE_NAME']" \
        --region "$REGION" &>/dev/null; then
        log_success "Role is attached to instance profile"
    else
        log_error "Role not attached to instance profile"
        validation_passed=false
    fi
    
    if [[ "$validation_passed" == "true" ]]; then
        log_success "IAM setup validation passed"
        return 0
    else
        log_error "IAM setup validation failed"
        return 1
    fi
}

# Cleanup on error
cleanup_on_error() {
    log_warn "Cleaning up partial IAM configuration"
    
    # Remove role from instance profile
    aws iam remove-role-from-instance-profile \
        --instance-profile-name "$INSTANCE_PROFILE_NAME" \
        --role-name "$ROLE_NAME" \
        --region "$REGION" &>/dev/null || true
    
    # Delete instance profile
    aws iam delete-instance-profile \
        --instance-profile-name "$INSTANCE_PROFILE_NAME" \
        --region "$REGION" &>/dev/null || true
    
    # Detach policies
    local attached_policies
    attached_policies=$(aws iam list-attached-role-policies \
        --role-name "$ROLE_NAME" \
        --query 'AttachedPolicies[].PolicyArn' \
        --output text 2>/dev/null || true)
    
    for policy_arn in $attached_policies; do
        aws iam detach-role-policy \
            --role-name "$ROLE_NAME" \
            --policy-arn "$policy_arn" \
            --region "$REGION" &>/dev/null || true
    done
    
    # Delete role
    aws iam delete-role \
        --role-name "$ROLE_NAME" \
        --region "$REGION" &>/dev/null || true
    
    log_info "Cleanup completed"
}

# Main execution
main() {
    echo "=== IAM Setup for Ephemeral Container System ==="
    echo
    
    # Check if role already exists (idempotent)
    if check_role_exists; then
        log_warn "IAM role already exists: $ROLE_NAME"
        
        # Validate existing setup
        if validate_iam_setup; then
            echo
            echo -e "${GREEN}✓ IAM setup already configured and valid${NC}"
            return 0
        else
            log_warn "Existing IAM setup is incomplete, reconfiguring..."
        fi
    else
        log_info "IAM role not found, creating new setup"
    fi
    
    # Set trap for cleanup on error
    trap cleanup_on_error ERR
    
    # Create IAM role if needed
    if ! check_role_exists; then
        if ! create_iam_role; then
            log_error "Failed to create IAM role"
            exit 1
        fi
    fi
    
    # Attach policies
    attach_policies
    
    # Create instance profile if needed
    if ! check_instance_profile_exists; then
        if ! create_instance_profile; then
            log_error "Failed to create instance profile"
            exit 1
        fi
    else
        log_warn "Instance profile already exists: $INSTANCE_PROFILE_NAME"
        
        # Ensure role is attached
        if ! aws iam add-role-to-instance-profile \
            --instance-profile-name "$INSTANCE_PROFILE_NAME" \
            --role-name "$ROLE_NAME" \
            --region "$REGION" &>/dev/null; then
            log_info "Role already attached to instance profile"
        fi
    fi
    
    # Remove trap after successful setup
    trap - ERR
    
    # Final validation
    if validate_iam_setup; then
        echo
        echo -e "${GREEN}✓ IAM setup completed successfully${NC}"
        echo "  Role Name: $ROLE_NAME"
        echo "  Instance Profile: $INSTANCE_PROFILE_NAME"
        echo "  Region: $REGION"
        return 0
    else
        echo
        echo -e "${RED}✗ IAM setup failed validation${NC}"
        return 1
    fi
}

# Execute if run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi