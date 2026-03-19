---
name: where-was-i
description: Re-orient to in-progress work on a branch. Use when the user says "where was I", "what was I doing", "catch me up", "what's the status", "re-orient", or returns to a branch after time away and needs a quick summary of what they're working on and where things stand.
allowed-tools: Bash(git *), Bash(gh *), Grep, Glob, Read
---

# Where Was I?

Quickly re-orient the user to in-progress work on their current branch. Output should be **brief** — enough to jog memory, not a wall of text.

## Workflow

### Step 1: Gather context (run these in parallel)

```bash
# Current branch name
git branch --show-current

# Commits on this branch not on master (the work done so far)
git log master..HEAD --oneline --reverse

# Uncommitted changes
git status --short

# Unstaged + staged diff stat (what's in progress right now)
git diff --stat HEAD

# Branch description from the first commit message (often has ticket context)
git log master..HEAD --format="%B" --reverse | head -20
```

```bash
# Try to extract a ticket ID from the branch name (e.g., engage-1234, pla-567, run-890)
# and fetch the ticket title/description from Linear if possible
BRANCH=$(git branch --show-current)
TICKET_ID=$(echo "$BRANCH" | grep -oiE '(engage|pla|run|eng|data|infra|ml|ops|growth|rev)-[0-9]+' | head -1 | tr '[:lower:]' '[:upper:]')
if [ -n "$TICKET_ID" ]; then
  echo "TICKET_ID=$TICKET_ID"
fi
```

```bash
# Check if there's a PR already open for this branch
gh pr view --json title,body,state,url 2>/dev/null || echo "NO_PR"
```

### Step 2: If a ticket ID was found, fetch from Linear

Use the Linear MCP tool `get_issue` to fetch the ticket title, description, and status. This gives the "why" behind the work.

### Step 3: Check conversation history

Look at the current conversation context. If this is a resumed session, there may be earlier messages explaining the goal. Note any plan or task list that was established.

### Step 4: Synthesize a brief summary

Write a short summary with these sections. Use 1-3 sentences each — be terse:

```
## Branch: <branch-name>

**Goal:** <What you're trying to accomplish, from ticket/PR/conversation context>

**Done so far:**
- <bullet per commit or logical chunk of work>

**Current state:**
- <What's uncommitted/in-progress, or "Clean — all changes committed">
- <PR status if one exists, or "No PR yet">

**Next steps:**
- <What remains based on ticket scope vs. completed work, or "Looks complete — ready for PR" if done>
```

### Important

- **Be brief.** This is a memory jogger, not a status report.
- Prefer concrete details (file names, function names) over abstract descriptions.
- If you can't determine the goal (no ticket, no PR, no conversation context), say so and summarize purely from the diff.
- Do NOT read the full contents of changed files — the diff stat and commit messages are sufficient.
