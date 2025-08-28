#!/bin/bash
# setup-iam.sh - Create and configure IAM roles and policies
# Issue #1: AWS Prerequisites and IAM Setup
# Version: 1.0.0

set -euo pipefail

# Configuration
readonly ROLE_NAME="SystemAdminTestingRole"
readonly POLICY_NAME="SystemAdminTestingPolicy"
readonly INSTANCE_PROFILE_NAME="SystemAdminTestingProfile"
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

# Trust policy for EC2 instances
get_trust_policy() {
    cat <<'EOF'
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "ec2.amazonaws.com"
            },
            "Action": "sts:AssumeRole",
            "Condition": {
                "StringEquals": {
                    "aws:RequestedRegion": "us-east-1"
                }
            }
        }
    ]
}
EOF
}

# IAM policy with least privilege permissions
get_iam_policy() {
    cat <<'EOF'
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "SpotInstanceManagement",
            "Effect": "Allow",
            "Action": [
                "ec2:RequestSpotInstances",
                "ec2:DescribeSpotInstanceRequests",
                "ec2:CancelSpotInstanceRequests",
                "ec2:DescribeInstances",
                "ec2:TerminateInstances",
                "ec2:RunInstances"
            ],
            "Resource": "*",
            "Condition": {
                "StringEquals": {
                    "aws:RequestedRegion": "us-east-1"
                },
                "ForAllValues:StringEquals": {
                    "ec2:InstanceType": ["t3.small", "t3.micro"]
                }
            }
        },
        {
            "Sid": "SecurityGroupManagement",
            "Effect": "Allow",
            "Action": [
                "ec2:CreateSecurityGroup",
                "ec2:AuthorizeSecurityGroupIngress",
                "ec2:RevokeSecurityGroupIngress",
                "ec2:DescribeSecurityGroups",
                "ec2:DeleteSecurityGroup"
            ],
            "Resource": "*",
            "Condition": {
                "StringEquals": {
                    "aws:RequestedRegion": "us-east-1"
                }
            }
        },
        {
            "Sid": "KeyPairManagement",
            "Effect": "Allow",
            "Action": [
                "ec2:CreateKeyPair",
                "ec2:DescribeKeyPairs",
                "ec2:ImportKeyPair",
                "ec2:DeleteKeyPair"
            ],
            "Resource": "*",
            "Condition": {
                "StringEquals": {
                    "aws:RequestedRegion": "us-east-1"
                }
            }
        },
        {
            "Sid": "CloudWatchLogging",
            "Effect": "Allow",
            "Action": [
                "logs:CreateLogGroup",
                "logs:CreateLogStream",
                "logs:PutLogEvents",
                "logs:DescribeLogGroups",
                "logs:DescribeLogStreams",
                "cloudwatch:PutMetricData"
            ],
            "Resource": "*"
        },
        {
            "Sid": "TagManagement",
            "Effect": "Allow",
            "Action": [
                "ec2:CreateTags",
                "ec2:DescribeTags"
            ],
            "Resource": "*"
        }
    ]
}
EOF
}

# Check if IAM role exists
check_role_exists() {
    aws iam get-role --role-name "${ROLE_NAME}" &> /dev/null
}

# Check if instance profile exists
check_instance_profile_exists() {
    aws iam get-instance-profile --instance-profile-name "${INSTANCE_PROFILE_NAME}" &> /dev/null
}

# Create IAM role
create_iam_role() {
    log_info "Creating IAM role: ${ROLE_NAME}"
    
    if check_role_exists; then
        log_warn "Role ${ROLE_NAME} already exists, skipping creation"
        return 0
    fi
    
    local trust_policy
    trust_policy=$(get_trust_policy)
    
    aws iam create-role \
        --role-name "${ROLE_NAME}" \
        --assume-role-policy-document "${trust_policy}" \
        --description "Role for ephemeral EC2 spot instances for system administration" \
        --tags "Key=Project,Value=ephemeral-container-claude" "Key=Purpose,Value=system-admin-testing" \
        --output text > /dev/null
    
    log_success "Created IAM role: ${ROLE_NAME}"
}

# Attach inline policy to role
attach_policy() {
    log_info "Attaching inline policy to role"
    
    local policy_document
    policy_document=$(get_iam_policy)
    
    aws iam put-role-policy \
        --role-name "${ROLE_NAME}" \
        --policy-name "${POLICY_NAME}" \
        --policy-document "${policy_document}" \
        --output text > /dev/null
    
    log_success "Attached policy: ${POLICY_NAME}"
}

# Create instance profile
create_instance_profile() {
    log_info "Creating instance profile: ${INSTANCE_PROFILE_NAME}"
    
    if check_instance_profile_exists; then
        log_warn "Instance profile ${INSTANCE_PROFILE_NAME} already exists, skipping creation"
        return 0
    fi
    
    aws iam create-instance-profile \
        --instance-profile-name "${INSTANCE_PROFILE_NAME}" \
        --output text > /dev/null
    
    log_success "Created instance profile: ${INSTANCE_PROFILE_NAME}"
}

# Add role to instance profile
add_role_to_instance_profile() {
    log_info "Adding role to instance profile"
    
    # Check if role is already in instance profile
    local roles_in_profile
    roles_in_profile=$(aws iam get-instance-profile \
        --instance-profile-name "${INSTANCE_PROFILE_NAME}" \
        --query "InstanceProfile.Roles[?RoleName=='${ROLE_NAME}'].RoleName" \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "${roles_in_profile}" ]]; then
        log_warn "Role already attached to instance profile, skipping"
        return 0
    fi
    
    aws iam add-role-to-instance-profile \
        --instance-profile-name "${INSTANCE_PROFILE_NAME}" \
        --role-name "${ROLE_NAME}" \
        --output text > /dev/null
    
    log_success "Added role to instance profile"
}

# Validate the setup
validate_setup() {
    log_info "Validating IAM setup"
    
    # Check role exists
    if ! check_role_exists; then
        echo "Error: Role ${ROLE_NAME} not found"
        return 1
    fi
    
    # Check instance profile exists
    if ! check_instance_profile_exists; then
        echo "Error: Instance profile ${INSTANCE_PROFILE_NAME} not found"
        return 1
    fi
    
    # Check policy is attached
    local attached_policies
    attached_policies=$(aws iam list-role-policies \
        --role-name "${ROLE_NAME}" \
        --query "PolicyNames[?@=='${POLICY_NAME}']" \
        --output text)
    
    if [[ -z "${attached_policies}" ]]; then
        echo "Error: Policy ${POLICY_NAME} not attached to role"
        return 1
    fi
    
    log_success "IAM setup validated successfully"
    return 0
}

# Main execution
main() {
    echo "=== IAM Setup ==="
    echo
    
    # Create resources
    create_iam_role
    attach_policy
    create_instance_profile
    add_role_to_instance_profile
    
    # Wait for eventual consistency
    log_info "Waiting for IAM propagation..."
    sleep 5
    
    # Validate
    validate_setup
    
    echo
    echo -e "${GREEN}✓ IAM setup complete${NC}"
    echo "  Role: ${ROLE_NAME}"
    echo "  Instance Profile: ${INSTANCE_PROFILE_NAME}"
    
    return 0
}

# Execute if run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi