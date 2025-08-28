# Claude Project Configuration

This directory contains Claude AI workflow state and configuration.

## Quick Commands

Run from project root:
```bash
# Check current state
.claude/workflow check_state

# View last review feedback  
.claude/workflow load_feedback

# Run validation checks
.claude/workflow validate

# Run all tests
.claude/workflow run_tests

# Create regression test
.claude/workflow create_regression

# Log an issue
.claude/workflow log_issue "description" "HIGH"

# Generate handoff package
.claude/workflow handoff

# Advance to next phase (use with caution)
.claude/workflow advance_phase
```

## Directory Structure

- `state/` - Workflow state files
  - `current-phase.json` - Current phase and status
  - `review-history.json` - Review feedback history
  - `issues.jsonl` - Logged issues and blockers
- `agents/` - Agent-specific configurations
- `templates/` - Reusable templates
- `config.json` - Project configuration

## Workflow Phases

1. **DEV** - Development (implementation-specialist)
2. **CR** - Code Review (code-reviewer)
3. **PR** - Product Review (product-reviewer)
4. **QA** - Quality Assurance (project-qa)
5. **DONE** - Ready for merge

**RW** - Rework phase (returns to implementation-specialist)

## State Management

The project master workflow is managed through `state/current-phase.json`. Each agent should:
1. Check state before starting work
2. Validate they're in the correct phase
3. Update state after completing work
4. Generate handoff for next agent

## Issue Management

The the implementation and planning workflow is managed through `state/issues/$issue-number/$issue-number.json`. Coordinator, scrum master and dev agents should:
1. Check state before starting work
2. Validate they're in the correct phase
3. Update state after completing work
4. Generate handoff for next agent

## Iteration Management

The workflow is managed through `state/issues/$issue-number/$iteration-number/$iteration-number.json`. Iteration subagents should:
1. Check state before starting work
2. Validate they're in the correct phase
3. Update state after completing work
4. Generate handoff for next agent

## For Agents

Always start with:
```bash
.claude/workflow check_state
.claude/workflow git_safety
```

Before handoff:
```bash
.claude/workflow validate
.claude/workflow handoff
```
