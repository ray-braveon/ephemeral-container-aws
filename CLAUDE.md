# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is an **Ephemeral AWS Container System** - an auto-scaling container system for AWS with local shell access designed for system administration tasks. The system launches temporary EC2 spot instances on-demand via a local bash script and automatically terminates them when the SSH session ends.

### Key Requirements
- **Primary Use Case**: System administration testing shell (1-2 times per week)
- **Launch Method**: Single command `./launch-admin.sh`
- **Instance Type**: t3.small spot instances (fallback: t3.micro)
- **Region**: us-east-1
- **Auto-termination**: On SSH disconnect
- **Cost Target**: Under $2/month
- **Connection Time**: < 60 seconds

## Development Commands

### AWS Setup and Testing
```bash
# Verify AWS CLI configuration
aws ec2 describe-instances --region us-east-1

# Test spot instance pricing
aws ec2 describe-spot-price-history --instance-types t3.small --region us-east-1 --max-results 1

# Check security groups
aws ec2 describe-security-groups --region us-east-1
```

### Script Development
```bash
# Make launch script executable
chmod +x launch-admin.sh

# Test script components individually
./scripts/check-prerequisites.sh
./scripts/update-security-group.sh
./scripts/launch-spot.sh
```

## Architecture & Structure

### Core Components
1. **launch-admin.sh** - Main launcher script that orchestrates:
   - Prerequisites validation (AWS CLI, credentials, SSH keys)
   - Dynamic IP detection and security group updates
   - Spot instance request and provisioning
   - SSH connection establishment
   - Auto-termination setup

2. **IAM Configuration**
   - Role: `SystemAdminTestingRole` with EC2 assume role trust
   - Policies: EC2 Spot management, CloudWatch Logs, Security Group management

3. **Security Group Management**
   - Dynamic IP whitelisting for current user
   - Automatic cleanup on termination
   - SSH-only access (port 22)

4. **Instance Lifecycle**
   - Spot request → Instance launch → SSH ready → Active session → Auto-terminate on disconnect

### Implementation Phases
- **Phase 1 (P0)**: AWS prerequisites, IAM, security groups, SSH keys
- **Phase 2 (P1)**: Core launch script, auto-termination mechanism
- **Phase 3 (P2)**: Spot templates, multi-AZ failover
- **Phase 4 (P3)**: Logging, monitoring, cost tracking
- **Phase 5 (P4-P5)**: System tools, documentation, web interface

## Project Management Integration

This repository follows the multi-agent workflow defined in `~/.claude/`. When working on issues:

1. **Issue Tracking**: All work items are tracked in GitHub Issues (#1-#12) with priority levels (P0-P5)
2. **Phase Progression**: Follow REQ → DESIGN → ARCH → DEV → CR → VALIDATE → PR → POLISH → QA workflow
3. **Agent Coordination**: Different specialized agents handle different phases
4. **State Management**: Project state tracked in `~/.claude/state/`

## Critical Implementation Notes

### Spot Instance Configuration
```bash
# Primary instance type
INSTANCE_TYPE="t3.small"  # 2 vCPU, 2 GiB RAM

# Fallback type
FALLBACK_TYPE="t3.micro"  # 2 vCPU, 1 GiB RAM

# Max spot price (50% of on-demand)
MAX_PRICE=$(aws ec2 describe-spot-price-history \
  --instance-types $INSTANCE_TYPE \
  --region us-east-1 \
  --query 'SpotPriceHistory[0].SpotPrice' \
  --output text)
```

### Auto-Termination Mechanism
The instance must self-terminate when SSH disconnects. Implementation approaches:
1. CloudWatch alarm on network metrics
2. Systemd service monitoring SSH sessions
3. User-data script with session detection

### Error Handling Requirements
- Rollback incomplete launches
- Clean up security group rules on failure
- Terminate orphaned instances
- Clear error messages for troubleshooting

## Cost Management
- Target: < $2/month (3-6 hours weekly usage)
- Monitor with AWS Cost Explorer
- Use spot instances exclusively
- Implement aggressive auto-termination

## Security Considerations
- Never commit AWS credentials
- Use IAM roles over access keys when possible
- Implement least-privilege IAM policies
- Rotate SSH keys regularly
- Log all administrative sessions