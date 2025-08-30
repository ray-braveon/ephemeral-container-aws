#!/bin/bash
# mock-aws-cli.sh - Mock AWS CLI for testing
# Issue #23: Test Infrastructure

# Mock AWS CLI wrapper
aws() {
    # Capture the AWS command for testing
    local service="$1"
    local operation="$2"
    shift 2
    
    case "$service" in
        "sts")
            case "$operation" in
                "get-caller-identity")
                    echo '{"UserId":"AIDAMOCK123456789","Account":"123456789012","Arn":"arn:aws:iam::123456789012:user/test-user"}'
                    return 0
                    ;;
                *)
                    echo "Mock: Unknown STS operation: $operation" >&2
                    return 1
                    ;;
            esac
            ;;
            
        "ec2")
            case "$operation" in
                "describe-instances")
                    echo '{"Reservations":[]}'
                    return 0
                    ;;
                "describe-security-groups")
                    echo '{"SecurityGroups":[{"GroupId":"sg-mock123","GroupName":"ephemeral-admin-sg"}]}'
                    return 0
                    ;;
                "describe-key-pairs")
                    echo '{"KeyPairs":[{"KeyName":"ephemeral-admin-key","KeyFingerprint":"aa:bb:cc:dd:ee:ff"}]}'
                    return 0
                    ;;
                "describe-spot-price-history")
                    echo '{"SpotPriceHistory":[{"SpotPrice":"0.0104","InstanceType":"t3.small"}]}'
                    return 0
                    ;;
                "request-spot-instances")
                    echo '{"SpotInstanceRequests":[{"SpotInstanceRequestId":"sir-mock123"}]}'
                    return 0
                    ;;
                "describe-spot-instance-requests")
                    echo '{"SpotInstanceRequests":[{"State":"active","InstanceId":"i-mock123456"}]}'
                    return 0
                    ;;
                "describe-images")
                    echo 'ami-mock123456'
                    return 0
                    ;;
                "authorize-security-group-ingress")
                    return 0
                    ;;
                "revoke-security-group-ingress")
                    return 0
                    ;;
                "import-key-pair")
                    return 0
                    ;;
                "create-security-group")
                    echo 'sg-newmock456'
                    return 0
                    ;;
                "terminate-instances")
                    return 0
                    ;;
                *)
                    echo "Mock: Unknown EC2 operation: $operation" >&2
                    return 1
                    ;;
            esac
            ;;
            
        "iam")
            case "$operation" in
                "get-role")
                    echo '{"Role":{"RoleName":"SystemAdminTestingRole","Arn":"arn:aws:iam::123456789012:role/SystemAdminTestingRole"}}'
                    return 0
                    ;;
                "create-role")
                    echo '{"Role":{"RoleName":"SystemAdminTestingRole","Arn":"arn:aws:iam::123456789012:role/SystemAdminTestingRole"}}'
                    return 0
                    ;;
                "attach-role-policy")
                    return 0
                    ;;
                "create-instance-profile")
                    echo '{"InstanceProfile":{"InstanceProfileName":"SystemAdminTestingRole"}}'
                    return 0
                    ;;
                "add-role-to-instance-profile")
                    return 0
                    ;;
                *)
                    echo "Mock: Unknown IAM operation: $operation" >&2
                    return 1
                    ;;
            esac
            ;;
            
        *)
            echo "Mock: Unknown AWS service: $service" >&2
            return 1
            ;;
    esac
}

# Mock SSH commands
ssh() {
    # Mock SSH connectivity tests
    if [[ "$*" == *"echo 'SSH ready'"* ]]; then
        return 0
    fi
    echo "Mock SSH connection"
    return 0
}

ssh-keygen() {
    local key_file=""
    local key_type="rsa"
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -f)
                key_file="$2"
                shift 2
                ;;
            -t)
                key_type="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done
    
    # Create mock keys if file specified
    if [[ -n "$key_file" ]]; then
        echo "MOCK_PRIVATE_KEY_$key_type" > "$key_file"
        echo "ssh-$key_type MOCK_PUBLIC_KEY_DATA user@host" > "${key_file}.pub"
        chmod 600 "$key_file"
        chmod 644 "${key_file}.pub"
    fi
    
    return 0
}

# Mock curl for IP detection
curl() {
    if [[ "$*" == *"checkip"* ]] || [[ "$*" == *"ipify"* ]] || [[ "$*" == *"icanhazip"* ]]; then
        echo "203.0.113.42"  # Test IP from TEST-NET-3
        return 0
    fi
    /usr/bin/curl "$@"
}

# Export mock functions
export -f aws
export -f ssh
export -f ssh-keygen
export -f curl