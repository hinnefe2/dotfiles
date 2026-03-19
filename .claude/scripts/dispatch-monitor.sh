#!/usr/bin/env bash
# dispatch-monitor.sh — Worker state detection + auto-transitions + mode cycling
#
# Called by the manager every ~10 seconds. Checks signal files and tmux state
# for each dispatch-managed worker. Handles the impl→peer_review auto-transition.
#
# Output: JSON array of state changes (or empty array if none)

set -euo pipefail

DISPATCH_DIR="$HOME/.claude/dispatch"

# Exit early if no dispatch state
if [[ ! -f "$DISPATCH_DIR/state.json" ]]; then
  echo "[]"
  exit 0
fi

# Read global state
TICKETS=$(jq -r '.tickets[]' "$DISPATCH_DIR/state.json" 2>/dev/null)
REVIEWERS=$(jq -r '.reviewers // [] | join(" ")' "$DISPATCH_DIR/state.json" 2>/dev/null)

changes=()

for TICKET in $TICKETS; do
  WORKER_STATE="$DISPATCH_DIR/$TICKET/state.json"
  [[ ! -f "$WORKER_STATE" ]] && continue

  PHASE=$(jq -r '.phase' "$WORKER_STATE")
  STATUS=$(jq -r '.status' "$WORKER_STATE")
  WORKTREE=$(jq -r '.worktree' "$WORKER_STATE")
  TMUX_WIN=$(jq -r '.tmux_window' "$WORKER_STATE")

  # Skip completed or errored workers
  [[ "$STATUS" == "done" || "$STATUS" == "error" ]] && continue

  # Check if tmux window still exists
  if ! tmux list-windows -t "dev" -F '#{window_name}' 2>/dev/null | grep -qx "$TMUX_WIN"; then
    # Window gone — mark as error
    jq '.status = "error"' "$WORKER_STATE" > "$WORKER_STATE.tmp" && mv "$WORKER_STATE.tmp" "$WORKER_STATE"
    changes+=("{\"ticket\":\"$TICKET\",\"change\":\"error\",\"reason\":\"tmux window gone\"}")
    continue
  fi

  # Check if Claude is still running in the window
  PANE_CMD=$(tmux display-message -t "dev:$TMUX_WIN" -p '#{pane_current_command}' 2>/dev/null || echo "")
  if [[ "$STATUS" == "running" && "$PANE_CMD" != "claude" && "$PANE_CMD" != "node" ]]; then
    # Claude may have exited — check if it's a bash prompt (Claude crashed)
    # Give it a grace period: only mark error if no signal file exists for current phase
    if [[ ! -f "$DISPATCH_DIR/$TICKET/${PHASE}.done" ]]; then
      jq '.status = "error"' "$WORKER_STATE" > "$WORKER_STATE.tmp" && mv "$WORKER_STATE.tmp" "$WORKER_STATE"
      changes+=("{\"ticket\":\"$TICKET\",\"change\":\"error\",\"reason\":\"claude exited during $PHASE\"}")
      continue
    fi
  fi

  # Check for signal files based on current phase
  case "$PHASE" in
    planning)
      if [[ -f "$DISPATCH_DIR/$TICKET/planning.done" ]]; then
        jq '.phase = "plan_review" | .status = "needs_attention"' "$WORKER_STATE" > "$WORKER_STATE.tmp" && mv "$WORKER_STATE.tmp" "$WORKER_STATE"
        changes+=("{\"ticket\":\"$TICKET\",\"change\":\"plan_review\",\"reason\":\"planning complete\"}")
      fi
      ;;

    implementing)
      if [[ -f "$DISPATCH_DIR/$TICKET/implementing.done" ]]; then
        # Auto-transition: implementing → peer_reviewing
        # Switch from acceptEdits → plan mode (1x BTab)
        jq '.phase = "peer_reviewing" | .status = "running"' "$WORKER_STATE" > "$WORKER_STATE.tmp" && mv "$WORKER_STATE.tmp" "$WORKER_STATE"

        tmux send-keys -t "dev:$TMUX_WIN" BTab
        sleep 1

        # Write peer review instructions to temp file for clean delivery
        REVIEW_INSTRUCTIONS="Run /peer-review $REVIEWERS on the current branch changes. Save the full review output to ~/.claude/dispatch/$TICKET/review-output.md. When done: touch ~/.claude/dispatch/$TICKET/peer_reviewing.done and WAIT for further instructions."
        TMPFILE=$(mktemp)
        echo "$REVIEW_INSTRUCTIONS" > "$TMPFILE"
        tmux send-keys -t "dev:$TMUX_WIN" "$(cat "$TMPFILE")" Enter
        rm -f "$TMPFILE"

        changes+=("{\"ticket\":\"$TICKET\",\"change\":\"peer_reviewing\",\"reason\":\"auto-transition to peer review\"}")
      fi
      ;;

    peer_reviewing)
      if [[ -f "$DISPATCH_DIR/$TICKET/peer_reviewing.done" ]]; then
        jq '.phase = "pr_review" | .status = "needs_attention"' "$WORKER_STATE" > "$WORKER_STATE.tmp" && mv "$WORKER_STATE.tmp" "$WORKER_STATE"
        changes+=("{\"ticket\":\"$TICKET\",\"change\":\"pr_review\",\"reason\":\"peer review complete\"}")
      fi
      ;;

    creating_pr)
      # Check if PR was created by looking for branch
      if [[ -n "$WORKTREE" ]]; then
        PR_URL=$(gh pr list --head "$WORKTREE" --json url --jq '.[0].url' 2>/dev/null || echo "")
        if [[ -n "$PR_URL" ]]; then
          jq --arg url "$PR_URL" '.phase = "done" | .status = "done" | .pr_url = $url' "$WORKER_STATE" > "$WORKER_STATE.tmp" && mv "$WORKER_STATE.tmp" "$WORKER_STATE"
          changes+=("{\"ticket\":\"$TICKET\",\"change\":\"done\",\"reason\":\"PR created\",\"pr_url\":\"$PR_URL\"}")
        fi
      fi
      ;;
  esac
done

# Update global state attention_queue and completed
if [[ ${#changes[@]} -gt 0 ]]; then
  # Rebuild attention queue from worker states
  ATTENTION_QUEUE="[]"
  COMPLETED="[]"
  for TICKET in $TICKETS; do
    WORKER_STATE="$DISPATCH_DIR/$TICKET/state.json"
    [[ ! -f "$WORKER_STATE" ]] && continue
    WS=$(jq -r '.status' "$WORKER_STATE")
    WP=$(jq -r '.phase' "$WORKER_STATE")
    if [[ "$WS" == "needs_attention" ]]; then
      ATTENTION_QUEUE=$(echo "$ATTENTION_QUEUE" | jq --arg t "$TICKET" '. + [$t]')
    fi
    if [[ "$WP" == "done" ]]; then
      COMPLETED=$(echo "$COMPLETED" | jq --arg t "$TICKET" '. + [$t]')
    fi
  done

  # Update global state
  jq --argjson aq "$ATTENTION_QUEUE" --argjson comp "$COMPLETED" \
    '.attention_queue = $aq | .completed = $comp' \
    "$DISPATCH_DIR/state.json" > "$DISPATCH_DIR/state.json.tmp" && mv "$DISPATCH_DIR/state.json.tmp" "$DISPATCH_DIR/state.json"
fi

# Output changes as JSON array
if [[ ${#changes[@]} -eq 0 ]]; then
  echo "[]"
else
  printf '[%s]\n' "$(IFS=,; echo "${changes[*]}")"
fi
