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

Workers are long-lived interactive Claude sessions launched with `--dangerously-skip-permissions` so they run autonomously without blocking on permission prompts. Instructions are sent via `tmux send-keys`.

## CRITICAL: Permission Handling

**Workers MUST be launched with `--dangerously-skip-permissions`**. Without this flag, Claude Code shows TUI permission prompts (numbered arrow-key menus) that block the worker indefinitely. The manager cannot reliably approve these remotely because:

1. Permission prompts are **arrow-key selection menus** (not text input) — you must use `Down`/`Up` keys + `Enter`, NOT type numbers
2. Workers hit **multiple different permission types** (MCP tools, Bash commands, file reads) — approving one doesn't prevent the next
3. The monitor script checks process liveness but **cannot detect** a permission prompt vs active work
4. BTab mode cycling (Shift+Tab) **does not work** when a permission prompt is active

**Do NOT use BTab mode cycling**. It was unreliable in practice — plan mode blocks tool execution (including MCP calls to Linear), and mode switches sent via tmux are fragile.

## Worker Lifecycle

```
planning [skip-permissions] → plan_review (PAUSE) → implementing [skip-permissions]
→ peer_reviewing [skip-permissions] → pr_review (PAUSE) → creating_pr [skip-permissions] → done
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
3. Mark all tickets as **In Progress** in Linear using `save_issue` with `state: "In Progress"`.
4. For each ticket:
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
        "pr_url": null,
        "conversation_id": null
      }
      ```
   g. Launch Claude with `--dangerously-skip-permissions` so it runs autonomously:
      ```bash
      tmux send-keys -t "dev:<TICKET-ID>" "cd ~/picnic-<worktree-name> && claude --dangerously-skip-permissions" Enter
      ```
   h. Wait for Claude to start (sleep 8), then send planning instructions directly (no mode switching needed):
      ```bash
      tmux send-keys -t "dev:<TICKET-ID>" "You are working on Linear ticket <TICKET-ID>. URL: <ticket-url>. Fetch the ticket details from Linear, understand what needs to be done, and create a detailed implementation plan. Save the plan to .plans/<worktree-name>.md. When done: touch ~/.claude/dispatch/<TICKET-ID>/planning.done and WAIT for further instructions. Do NOT proceed to implementation." Enter
      ```
   i. After Claude starts working, capture the conversation ID and save it to the worker state:
      ```bash
      CONV_ID=$(ls -t ~/.claude/projects/-home-coder-picnic-<worktree-name>/*.jsonl | head -1 | xargs basename | sed 's/.jsonl//')
      jq --arg c "$CONV_ID" '.conversation_id = $c' ~/.claude/dispatch/<TICKET-ID>/state.json > tmp && mv tmp ~/.claude/dispatch/<TICKET-ID>/state.json
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
2. Send implementation instructions (no mode switching needed — workers run with `--dangerously-skip-permissions`):
   ```bash
   tmux send-keys -t "dev:<TICKET-ID>" "Now implement the plan at .plans/<worktree-name>.md for ticket <TICKET-ID>. Follow every step. Run tests. Fix lint errors. When done: touch ~/.claude/dispatch/<TICKET-ID>/implementing.done and WAIT for further instructions." Enter
   ```
3. Remove from attention queue

#### `done <TICKET-ID>`
Used after reviewing peer review results and user has directed any fixes:
1. Update worker state: `phase=creating_pr`, `status=running`
2. Send PR creation instructions (no mode switching needed):
   ```bash
   tmux send-keys -t "dev:<TICKET-ID>" "Create a PR for ticket <TICKET-ID> using /create-pr. The branch is <worktree-name>. When the PR is created, you're done." Enter
   ```
3. Remove from attention queue

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

### Resuming conversations

Claude Code stores conversation history per-project in `~/.claude/projects/-home-coder-picnic-<worktree>/`. Each conversation is a `<uuid>.jsonl` file. To find the conversation ID for a worktree:

```bash
ls -t ~/.claude/projects/-home-coder-picnic-<worktree>/*.jsonl | head -1 | xargs basename | sed 's/.jsonl//'
```

To resume a conversation inside a running Claude session, use `/resume <session-id>`. This restores full context from the previous session — no need to re-send instructions or explain what happened.

### Resume scenarios

**For ALL scenarios**: every ticket needs a tmux window with Claude running and the previous conversation resumed. This includes `needs_attention` (plan_review, pr_review) tickets — the user switches to the worker window to review, and after approval the worker receives implementation instructions there.

**Scenario A: Worker Claude is still running** (window exists, `pane_current_command` is `claude` or `node`)
- Just reconnect to monitor loop. Worker continues where it left off.

**Scenario B: Worker Claude exited** (window exists but Claude not running)
- Re-launch Claude in the worktree:
  ```bash
  tmux send-keys -t "dev:<TICKET-ID>" "cd ~/picnic-<worktree> && claude --dangerously-skip-permissions" Enter
  ```
- Wait for Claude to start (sleep 8), then resume the previous conversation:
  ```bash
  tmux send-keys -t "dev:<TICKET-ID>" "/resume <session-id>" Enter
  ```
- **IMPORTANT**: `/resume` only loads conversation history — Claude does NOT automatically continue working. After resuming (sleep 5), send a nudge message with phase-appropriate instructions:
  ```bash
  tmux send-keys -t "dev:<TICKET-ID>" "Continue where you left off. <phase-specific instructions>" Enter
  ```

**Scenario C: tmux window gone**
- Re-create window: `tmux new-window -n "<TICKET-ID>"`
- Then same as Scenario B

## Implementation Notes

- **tmux send-keys quoting**: For long instructions, send directly as a single string. Avoid heredocs in tmux send-keys.
- **Worker idle detection**: Workers write `.done` signal files. The monitor checks these every 10 seconds.
- **Manager window**: Named `DISPATCH` for easy identification in `Ctrl-B w` window list.
- **Permission handling**: Workers MUST be launched with `--dangerously-skip-permissions`. Do NOT rely on BTab mode cycling or auto-approve hooks — they are unreliable for autonomous workers.
- **TUI permission prompts**: If a worker does get stuck on a permission prompt (e.g., launched without `--dangerously-skip-permissions`), the prompt is an **arrow-key selection menu** — use `tmux send-keys Down Enter` to select option 2 ("don't ask again"), NOT `"2" Enter` (which types the character "2" into a non-text-input widget). Plain `Enter` selects the currently highlighted option.
- **Pane capture quirks**: Claude Code's TUI uses alternate screen buffers. `tmux capture-pane -p` may return empty content. Use `tmux capture-pane -p -S 0 -E 50 | cat -v` to capture with raw escape sequences, or grep for known strings like "proceed", "plan mode", "Searching".
- **Slash commands vs Skill tool**: Some skills (like `/peer-review`) have `disable-model-invocation` set, meaning Claude cannot call them via the `Skill()` tool — they MUST be typed as direct user input. When triggering slash commands on workers, send them as raw tmux input (`tmux send-keys -t "dev:<WIN>" "/peer-review args" Enter`), NOT as instructions telling Claude to "Run /peer-review" (which would try the Skill tool and fail).
