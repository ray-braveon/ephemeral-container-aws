# Ephemeral AWS Container System - Project Overview

## Purpose
Auto-scaling ephemeral container system for AWS with local shell access designed for system administration tasks. The system launches temporary EC2 spot instances on-demand and automatically terminates them when SSH sessions end.

## Tech Stack
- **Language**: Bash scripting
- **Platform**: AWS EC2 (spot instances)
- **Instance Types**: t3.small (primary), t3.micro (fallback)
- **Region**: us-east-1
- **Operating System**: Ubuntu (on launched instances)

## Key Requirements
- Single command launch: `./launch-admin.sh`
- Cost target: Under $2/month
- Connection time: < 60 seconds
- Auto-termination on SSH disconnect
- Primary use case: 1-2 times per week for system administration testing

## Architecture Components
1. **launch-admin.sh** - Main orchestrator script
2. **scripts/check-prerequisites.sh** - AWS CLI and credentials validation
3. **scripts/generate-ssh-keys.sh** - SSH key pair management
4. **scripts/setup-iam.sh** - IAM roles and policies
5. **scripts/manage-security-group.sh** - Dynamic IP whitelisting

## Current Phase
- **Workflow Phase**: POLISH (UI/UX enhancement)
- **Focus**: SSH key management user experience
- **Issue Reference**: GitHub Issue #3