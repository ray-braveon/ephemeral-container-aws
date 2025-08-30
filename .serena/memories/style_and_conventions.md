# Code Style and Conventions

## Bash Scripting Standards

### Script Headers
All scripts include:
- Shebang: `#!/bin/bash`
- Description comment with issue reference
- Version number
- Strict error handling: `set -euo pipefail`
- IFS setting: `IFS=$'\n\t'`

### Security Practices
- Set secure umask: `umask 077`
- Input validation to prevent command injection
- Proper quoting of variables
- Use readonly for constants
- Validate user input with regex patterns

### Code Organization
- Configuration variables at top (readonly)
- Color codes defined as constants
- Helper functions before main logic
- Main execution at bottom with `main "$@"`

### Naming Conventions
- Functions: snake_case (e.g., `log_info`, `validate_key_name`)
- Variables: lowercase with underscores (e.g., `key_name`, `aws_fingerprint`)
- Constants: UPPERCASE (e.g., `KEY_NAME`, `REGION`)
- Files: kebab-case (e.g., `generate-ssh-keys.sh`)

### Error Handling
- Use `error_exit()` function for fatal errors
- Implement rollback mechanisms where needed
- Log all operations to files
- Provide clear, actionable error messages

### Output Standards
- Consistent color coding:
  - Green (✓) for success
  - Yellow (⚠) for warnings  
  - Red for errors
  - Blue for info
- Structured logging with timestamps
- Progress indicators for long operations

### Documentation
- Inline comments for complex operations
- Function descriptions
- Usage examples in headers
- Clear variable explanations