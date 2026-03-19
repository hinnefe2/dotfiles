---
name: do-ticket
description: Kick off work on a Linear ticket by creating a tmux window, git worktree, and launching Claude Code in plan mode. Use when the user says "do ticket", "start ticket", "kick off ticket", "work on ticket", or provides a Linear ticket identifier/URL and wants to spin up an isolated workspace for it.
argument-hint: "<ticket-identifier-or-url> [short-description]"
user-invocable: true
---

# Do Ticket

Spins up an isolated workspace for a Linear ticket: tmux window, git worktree, and Claude Code in plan mode.

## Arguments

- `<ticket-identifier-or-url>` (required) — A Linear ticket identifier (e.g. `ENGAGE-3185`) or full URL (e.g. `https://linear.app/picnichealth/issue/ENGAGE-3185/...`)
- `[short-description]` (optional) — 2-3 word slug to append to the worktree name for human readability (e.g. `fix-mobile`). If omitted, the skill fetches the ticket title from Linear and generates one.

## Workflow

### 1. Resolve the ticket identifier

Extract the ticket identifier from the argument:
- If a full URL, parse out the identifier (e.g. `ENGAGE-3185` from `https://linear.app/picnichealth/issue/ENGAGE-3185/some-title`)
- If already an identifier like `ENGAGE-3185`, use it directly
- Normalize to uppercase (e.g. `engage-3185` → `ENGAGE-3185`)

### 2. Fetch ticket details from Linear

Use the `get_issue` Linear MCP tool with the ticket identifier to get the ticket title and URL.

If a short description was NOT provided by the user, generate a 2-3 word kebab-case slug from the ticket title. Examples:
- "Fix mobile navigation crash" → `fix-mobile-nav`
- "Add retry logic to webhook" → `add-webhook-retry`
- "Update user message styling" → `update-msg-styling`

### 3. Build the worktree name

Construct the worktree/branch name as: `<ticket-id-lowercase>-<short-description>`

Examples:
- `engage-3185-fix-mobile`
- `cap-4428-crf-ui-changes`
- `ai-123-add-retry`

### 4. Create a tmux window and set up the worktree

Run the following commands via Bash. These must be sequential since each depends on the previous:

```bash
# Create a new tmux window named after the ticket identifier
tmux new-window -n "<TICKET-ID>"

# In that window, create the worktree using the wcreate alias
# wcreate creates ~/picnic-<name> and checks out a new branch
tmux send-keys -t "<TICKET-ID>" "wcreate <worktree-name>" Enter
```

Wait a moment for the worktree to be created (sleep 3), then verify it exists:

```bash
ls -d ~/picnic-<worktree-name>
```

### 5. Launch Claude Code in plan mode

In the same tmux window, start Claude Code in plan mode with a prompt that instructs it to plan the ticket:

```bash
tmux send-keys -t "<TICKET-ID>" "claude --permission-mode plan -p 'You are working on Linear ticket <TICKET-ID>. The ticket URL is <ticket-url>. Fetch the ticket details from Linear, understand what needs to be done, and create a detailed implementation plan. Save the plan to .plans/<worktree-name>.md. If you need human input to proceed, clearly state what you need.'" Enter
```

### 6. Report back

Tell the user:
- The tmux window name (ticket ID)
- The worktree location (`~/picnic-<worktree-name>`)
- The branch name (`<worktree-name>`)
- That Claude Code is running in plan mode in that window

Example output:
```
Started work on ENGAGE-3185:
- tmux window: ENGAGE-3185
- Worktree: ~/picnic-engage-3185-fix-mobile (branch: engage-3185-fix-mobile)
- Claude Code is running in plan mode — check the tmux window for progress
```
