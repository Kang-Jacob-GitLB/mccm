---
name: cleanup
description: After PR merge, switch to main, pull, prune, and delete stale local branches. Triggered by "/cleanup", "clean up branches", "머지 후 정리", etc.
disable-model-invocation: true
allowed-tools: Bash, Read
---

## Current State

- Current branch: !`git branch --show-current`
- Working tree: !`git status --short`
- Local branches: !`git branch`
- Remote-deleted branches: !`git fetch --prune --dry-run 2>&1`

## Instructions

> **Convention override**: If the project's CLAUDE.md defines a `## Git Conventions` section, follow those conventions instead of the defaults below. Specifically look for overrides on: default branch name, merge strategy (squash vs merge commit), and branch deletion behavior.

Follow these steps in order.

### 1. Pre-check

If `git status --short` is not empty (uncommitted changes or untracked files), **stop** and ask the user to choose:

- **Commit**: commit the changes first, then re-run
- **Stash**: `git stash` to save temporarily, then re-run
- **Cancel**: abort cleanup and keep the current state

### 2. Switch to main

```bash
git checkout main
```

### 3. Sync

```bash
git pull
git fetch --prune
```

### 4. Delete merged local branches

Delete local branches whose remote tracking branch is gone, excluding `main` and `master`.

**Default behavior** (merge-commit strategy — use `-d` safe delete):
```bash
GONE=$(git branch -vv | grep ': gone]' | awk '{print $1}' | grep -v '^main$\|^master$')
[ -n "$GONE" ] && echo "$GONE" | xargs git branch -d
```

> If the project uses **squash merge** strategy (specified in CLAUDE.md Git Conventions), use `git branch -D` (force delete) instead, since squash-merged branches won't be recognized as merged by git.

### 5. Completion Report

- Current branch (main)
- Deleted local branches
- Branches not deleted (if any, with reason)
