---
name: dispatch-tickets
description: Dispatch multiple Linear tickets to parallel Claude Code workers with manager-worker orchestration. Workers run autonomously; the manager monitors, queues reviews, and presents them one at a time.
argument-hint: "[--reviewers user1,user2] [--resume] TICKET-1 TICKET-2 [TICKET-3 ...]"
user-invocable: true
---

# Dispatch Tickets — Manager-Worker Orchestration

Dispatches multiple Linear tickets to parallel Claude Code worker sessions. Each worker runs in its own tmux window and git worktree. The manager monitors all workers and presents review points one at a time.

## Arguments

- `--reviewers user1,user2` (optional) — GitHub usernames for `/peer-review` (comma-separated)
- `--resume` — Pick up a previous dispatch from `~/.claude/dispatch/state.json`
- `TICKET-1 TICKET-2 ...` (required unless `--resume`) — Linear ticket identifiers

## Architecture

```
Manager (this session)          Workers (tmux windows)
┌────────────────────┐          ┌──────────────────────┐
│ Monitor loop       │──tmux──► │ TICKET-1: planning   │
│ Dashboard          │──tmux──► │ TICKET-2: impl       │
│ Review queue       │──tmux──► │ TICKET-3: peer review│
│ User commands      │──tmux──► │ TICKET-4: done       │
└────────────────────┘          └──────────────────────┘
```

Workers are long-lived interactive Claude sessions. Instructions are sent via `tmux send-keys`. Permission modes are cycled via `tmux send-keys BTab` (Shift+Tab).

## Permission Mode Cycling (BTab = Shift+Tab)

```
Normal ──BTab──► Auto-Accept (acceptEdits) ──BTab──► Plan ──BTab──► Normal
```

- **Normal to plan**: 2x BTab
- **Plan to acceptEdits**: 2x BTab (plan → normal → acceptEdits)
- **AcceptEdits to plan**: 1x BTab

## Worker Lifecycle

```
planning [plan mode] → plan_review (PAUSE) → implementing [acceptEdits]
→ peer_reviewing [plan mode] → pr_review (PAUSE) → creating_pr [acceptEdits] → done
```

Workers write signal files when phases complete:
- `~/.claude/dispatch/<TICKET>/planning.done`
- `~/.claude/dispatch/<TICKET>/implementing.done`
- `~/.claude/dispatch/<TICKET>/peer_reviewing.done`

## Workflow

### Step 1: Parse Arguments

Parse the arguments string to extract:
1. `--reviewers` flag value (split on commas)
2. `--resume` flag (boolean)
3. Remaining args are ticket IDs (normalize to uppercase)

### Step 2: Initialization

Rename the current tmux window to `DISPATCH`:
```bash
tmux rename-window "DISPATCH"
```

#### If `--resume`:
1. Read existing `~/.claude/dispatch/state.json`
2. For each ticket, check:
   - Does the tmux window still exist? (`tmux list-windows -t dev -F '#{window_name}'`)
   - Is Claude still running? (`tmux display-message -t "dev:<TICKET>" -p '#{pane_current_command}'`)
   - What phase/status is it in?
3. For windows where Claude exited:
   - Re-create tmux window if needed
   - Re-launch Claude in the worktree with context-appropriate instructions
   - Set appropriate permission mode based on phase
4. Skip to Step 3 (Monitor Loop)

#### If new dispatch:
1. Create `~/.claude/dispatch/` directory and per-ticket subdirectories
2. Write global `state.json`:
   ```json
   {
     "tickets": ["TICKET-1", "TICKET-2"],
     "reviewers": ["user1", "user2"],
     "attention_queue": [],
     "active_review": null,
     "completed": []
   }
   ```
3. For each ticket:
   a. Fetch ticket details from Linear using `get_issue` MCP tool
   b. Generate worktree name: `<ticket-id-lowercase>-<short-slug>` (2-3 word kebab-case from title)
   c. Create tmux window:
      ```bash
      tmux new-window -n "<TICKET-ID>"
      ```
   d. Create worktree:
      ```bash
      tmux send-keys -t "dev:<TICKET-ID>" "wcreate <worktree-name>" Enter
      ```
   e. Wait for worktree creation (sleep 5, verify `~/picnic-<worktree-name>` exists)
   f. Write worker `state.json`:
      ```json
      {
        "ticket_id": "<TICKET-ID>",
        "ticket_title": "<title>",
        "ticket_url": "<url>",
        "worktree": "<worktree-name>",
        "tmux_window": "<TICKET-ID>",
        "phase": "planning",
        "status": "running",
        "started_at": "<ISO-8601>",
        "pr_url": null
      }
      ```
   g. Launch Claude in interactive mode (no permission flag):
      ```bash
      tmux send-keys -t "dev:<TICKET-ID>" "cd ~/picnic-<worktree-name> && claude" Enter
      ```
   h. Wait for Claude to start (sleep 8), then switch to plan mode and send planning instructions:
      ```bash
      # Normal → acceptEdits → plan (2x BTab)
      tmux send-keys -t "dev:<TICKET-ID>" BTab
      sleep 1
      tmux send-keys -t "dev:<TICKET-ID>" BTab
      sleep 1
      # Send planning instructions
      tmux send-keys -t "dev:<TICKET-ID>" "You are working on Linear ticket <TICKET-ID>. URL: <ticket-url>. Fetch the ticket details from Linear, understand what needs to be done, and create a detailed implementation plan. Save the plan to .plans/<worktree-name>.md. When done: touch ~/.claude/dispatch/<TICKET-ID>/planning.done and WAIT for further instructions. Do NOT proceed to implementation." Enter
      ```

### Step 3: Monitor Loop

Run the monitor script every 10 seconds using a Bash loop. **IMPORTANT**: The manager must stay responsive to user input between polls. Use a polling pattern where the manager:

1. Calls the monitor script:
   ```bash
   bash ~/.claude/scripts/dispatch-monitor.sh
   ```

2. Parses the JSON output for state changes

3. For each change:
   - `plan_review`: Add ticket to attention queue, notify user
   - `peer_reviewing`: Log auto-transition (no user action needed)
   - `pr_review`: Add ticket to attention queue, notify user
   - `done`: Log completion with PR URL
   - `error`: Log error, suggest `--resume` to recover

4. Show dashboard when queue changes or on `status` command

#### Dashboard Format

```
=== Dispatch Dashboard ===
 [1] ENGAGE-1234  plan_review     ⚡ NEEDS REVIEW
 [2] ENGAGE-5678  implementing    🔄 running (12m)
 [3] ENGAGE-9012  planning        🔄 running (5m)
 [4] ENGAGE-3456  done            ✅ PR #7855

Attention queue: ENGAGE-1234
Say 'review next' to review ENGAGE-1234.
```

### Step 4: Handle User Commands

The manager responds to these user commands (spoken in the chat):

#### `status`
Show the dashboard.

#### `review next` or `review <TICKET-ID>`
1. Identify the ticket (next in attention queue, or specific ID)
2. Read the relevant file:
   - For `plan_review`: Read `~/picnic-<worktree>/.plans/<worktree-name>.md`
   - For `pr_review`: Read `~/.claude/dispatch/<TICKET>/review-output.md`
3. Print a brief summary in the manager window
4. Switch to worker window:
   ```bash
   tmux select-window -t "dev:<TICKET-ID>"
   ```
5. Tell user: "Switched to <TICKET-ID>. The worker is waiting for input. When done, switch back to DISPATCH (Ctrl-B w) and say 'approve <TICKET-ID>' or 'done <TICKET-ID>'."

#### `approve <TICKET-ID>`
Used after reviewing a plan. Transitions worker to implementation:
1. Update worker state: `phase=implementing`, `status=running`
2. Switch permission mode from plan → acceptEdits:
   ```bash
   # plan → normal → acceptEdits (2x BTab)
   tmux send-keys -t "dev:<TICKET-ID>" BTab
   sleep 1
   tmux send-keys -t "dev:<TICKET-ID>" BTab
   sleep 1
   ```
3. Send implementation instructions:
   ```bash
   tmux send-keys -t "dev:<TICKET-ID>" "Now implement the plan at .plans/<worktree-name>.md for ticket <TICKET-ID>. Follow every step. Run tests. Fix lint errors. When done: touch ~/.claude/dispatch/<TICKET-ID>/implementing.done and WAIT for further instructions." Enter
   ```
4. Remove from attention queue

#### `done <TICKET-ID>`
Used after reviewing peer review results and user has directed any fixes:
1. Update worker state: `phase=creating_pr`, `status=running`
2. Ensure worker is in acceptEdits mode (if not already):
   ```bash
   # From plan mode: plan → normal → acceptEdits (2x BTab)
   tmux send-keys -t "dev:<TICKET-ID>" BTab
   sleep 1
   tmux send-keys -t "dev:<TICKET-ID>" BTab
   sleep 1
   ```
3. Send PR creation instructions:
   ```bash
   tmux send-keys -t "dev:<TICKET-ID>" "Create a PR for ticket <TICKET-ID> using /create-pr. The branch is <worktree-name>. When the PR is created, you're done." Enter
   ```
4. Remove from attention queue

#### `skip <TICKET-ID>`
Skip a ticket (remove from attention queue, mark as done):
1. Update worker state: `phase=done`, `status=done`
2. Remove from attention queue

### Step 5: Completion

When all tickets are `done` or `error`, print final summary:
```
=== Dispatch Complete ===
 ✅ ENGAGE-1234  PR: https://github.com/...
 ✅ ENGAGE-5678  PR: https://github.com/...
 ❌ ENGAGE-9012  Error: claude exited during planning
```

## Resume Capability

State files persist in `~/.claude/dispatch/`. On `--resume`:

**Scenario A: Worker Claude is still running** (window exists, `pane_current_command` is `claude` or `node`)
- Just reconnect to monitor loop. Worker continues where it left off.

**Scenario B: Worker Claude exited** (window exists but Claude not running)
- Check signal files to determine last completed phase
- Re-launch Claude in the worktree:
  ```bash
  tmux send-keys -t "dev:<TICKET-ID>" "cd ~/picnic-<worktree> && claude" Enter
  ```
- Set appropriate permission mode and send phase-appropriate instructions
- Include context: "You were previously working on <TICKET-ID>. Check .plans/<worktree>.md for the plan. Check git status/log for implementation progress."

**Scenario C: tmux window gone**
- Re-create window: `tmux new-window -n "<TICKET-ID>"`
- Then same as Scenario B

## Implementation Notes

- **tmux send-keys quoting**: For long instructions, send directly as a single string. Avoid heredocs in tmux send-keys.
- **BTab timing**: Always sleep 1 second between BTab presses to let Claude Code process the mode switch.
- **Worker idle detection**: Workers write `.done` signal files. The monitor checks these every 10 seconds.
- **Manager window**: Named `DISPATCH` for easy identification in `Ctrl-B w` window list.
- **Auto-approve hook**: Workers have a PermissionRequest hook (`dispatch-auto-approve.sh`) that auto-approves most operations. Only production-critical operations fall through to user prompt.
