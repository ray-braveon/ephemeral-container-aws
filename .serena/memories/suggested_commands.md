# Suggested Commands for Ephemeral AWS Container System

## Development Commands

### Main Project Commands
```bash
# Main launcher (orchestrates all phases)
./launch-admin.sh

# Make scripts executable
chmod +x launch-admin.sh
find scripts/ -name "*.sh" -exec chmod +x {} \;
```

### Individual Script Testing
```bash
# Test prerequisites validation
./scripts/check-prerequisites.sh

# Test SSH key generation
./scripts/generate-ssh-keys.sh

# Test IAM setup
./scripts/setup-iam.sh

# Test security group management
./scripts/manage-security-group.sh
```

### AWS Verification Commands
```bash
# Verify AWS CLI configuration
aws sts get-caller-identity

# Check EC2 instances
aws ec2 describe-instances --region us-east-1

# Check security groups
aws ec2 describe-security-groups --region us-east-1

# Check spot pricing
aws ec2 describe-spot-price-history --instance-types t3.small --region us-east-1 --max-results 1

# Check SSH key pairs
aws ec2 describe-key-pairs --region us-east-1
```

### Debugging & Logs
```bash
# View recent logs
ls -la ~/.ephemeral-admin/logs/
tail -f ~/.ephemeral-admin/logs/ephemeral-*.log

# Check script syntax
bash -n script_name.sh

# Run with debugging
bash -x ./launch-admin.sh
```

### Git Operations
```bash
# View project status
git status

# Check current branch
git branch

# View commit history
git log --oneline -10
```

### System Utilities (Linux)
```bash
# List files
ls -la

# Change directory
cd /path/to/directory

# Search files
find . -name "*.sh"

# Search content
grep -r "pattern" .

# File permissions
chmod +x script.sh

# View file contents
cat filename
head -20 filename
tail -20 filename
```