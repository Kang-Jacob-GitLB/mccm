---
name: pr
description: Push the current branch and create a pull request. Triggered by "/pr", "create PR", "PR 만들어줘", etc.
disable-model-invocation: true
allowed-tools: Bash, Read
---

## Prerequisites

- [GitHub CLI (`gh`)](https://cli.github.com/) installed and authenticated (`gh auth login`)

## Current State

- Current branch: !`git branch --show-current`
- Commits ahead of main: !`git log main..HEAD --oneline`
- Diff from main: !`git diff main..HEAD`
- Existing PR: !`gh pr view 2>&1 || echo "No PR found"`

## Instructions

> **Convention override**: If the project's CLAUDE.md defines a `## Git Conventions` section, follow those conventions instead of the defaults below. Specifically look for overrides on: language, PR title format, PR body template, label mapping, and any other PR-related rules.

### 1. Pre-checks

- If the current branch is `main` or `master`, stop and notify the user.
- If there are no commits ahead of main, stop and notify the user.
- If a PR is already open, switch to **update mode** (see step 6).

### 2. Push

```bash
git push -u origin HEAD
```

### 3. PR Title

Derive the PR title from the branch name and commit list.

**Default format:** `{type}: {concise description}`

**Type selection:**
- `feat` — new feature
- `fix` — bug fix
- `refactor` — refactoring (no behavior change)
- `test` — test additions/modifications
- `docs` — documentation changes
- `chore` — build config, dependencies, misc
- `ci` — CI/CD related

**Title rules (defaults):**
- Written in English
- 70 characters or less
- Imperative mood (Add, Fix, Remove, Update)
- No trailing period

### 4. PR Body

Analyze the commit list and diff to compose the body.

**Default format:**
```markdown
## Changes
- {change item 1}
- {change item 2}

## Test Plan
{How to test, or omit if not applicable}
```

- Keep it concise
- Omit body entirely for trivial changes

### 5. Create PR

**Default label mapping:**
- `feat` → `feature`
- `fix` → `bugfix`
- `refactor` → `refactoring`
- `test` → `test`
- `docs` → `documentation`
- `chore` → `chore`
- `ci` → `ci/cd`

First, get the current GitHub username:
```bash
gh api user --jq '.login'
```

Then create the PR:
```bash
gh pr create --title "{type}: {title}" --assignee "$(gh api user --jq '.login')" --label "{label}" --body "$(cat <<'EOF'
{body}
EOF
)"
```

### 6. Update Existing PR

If a PR is already open, push the new commits and update the title and body based on the full commit list and diff.

```bash
gh pr edit --title "{type}: {title}" --body "$(cat <<'EOF'
{body}
EOF
)"
```

### 7. Completion Report

Output the PR URL.
