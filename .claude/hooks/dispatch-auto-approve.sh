#!/usr/bin/env bash
# dispatch-auto-approve.sh — Auto-approve tool calls for dispatch-managed workers
#
# PermissionRequest hook that auto-approves ALL tool calls for dispatch-managed
# Claude sessions, with a small deny list for truly dangerous operations.
#
# Safety:
# - Only activates if current tmux window matches a dispatch-managed worker
# - Non-dispatch sessions are completely unaffected (hook exits silently)
# - Dangerous operations (production DB, deploys, secrets, destructive git) fall through
#   to normal user prompt
#
# Exit behavior:
# - Outputs JSON → auto-approve decision
# - Exits with no output → falls through to user prompt (deny list / non-dispatch)

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')

# Check if this is a dispatch-managed window
WIN=$(tmux display-message -p '#{window_name}' 2>/dev/null || true)

# Not in tmux or can't detect window → fall through silently
[[ -z "$WIN" ]] && exit 0

# No dispatch state for this window → fall through (not a dispatch worker)
[[ ! -f "$HOME/.claude/dispatch/$WIN/state.json" ]] && exit 0

# This IS a dispatch worker — auto-approve with deny list check

# For Bash commands, check against deny patterns
if [[ "$TOOL_NAME" == "Bash" ]]; then
  COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

  # Deny list: production operations that must always require human approval
  # Mirrors always_ask_patterns from approved-patterns.json
  DENY_PATTERNS=(
    'pkubectl2.*(apply|delete|scale|rollout|exec.*psql)'
    'goto-db\s+(prod|production)'
    'helm.*(install|upgrade|delete).*prod'
    'terragrunt\s+(apply|destroy).*prod'
    'terraform\s+(apply|destroy).*prod'
    'gcloud\s+secrets.*(create|delete|versions\s+add)'
    'gh\s+pr\s+merge'
    'git\s+push.*--force'
    'git\s+reset\s+--hard'
    'rm\s+-rf\s+[/~]'
  )

  for pattern in "${DENY_PATTERNS[@]}"; do
    if echo "$COMMAND" | grep -qEi "$pattern"; then
      # Fall through to user prompt (exit with no output)
      exit 0
    fi
  done
fi

# Auto-approve everything else
echo '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow","message":"Auto-approved for dispatch worker"}}}'
