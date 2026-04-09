---
name: commit
description: Stage changes and create a git commit. Triggered by "/commit", "commit this", "커밋해줘", etc.
disable-model-invocation: true
allowed-tools: Bash, Read
---

## Current State

- Current branch: !`git branch --show-current`
- Git status: !`git status`
- Diff: !`git diff HEAD`
- Recent commits: !`git log --oneline -5`

## Instructions

Analyze the changes above and follow these steps in order.

> **Convention override**: If the project's CLAUDE.md defines a `## Git Conventions` section, follow those conventions instead of the defaults below. Specifically look for overrides on: language, branch prefixes, commit message format, excluded file patterns, and any other commit-related rules.

### 1. Security Review

Before committing, check whether any staged candidates match these patterns:
- `.env`, `.env.*` (except `.env.example`)
- Hard-coded API keys, secrets, tokens, or passwords
- Credential files (`*.jks`, `*.keystore`, `*.pem`, `*.p12`, `credentials.json`, `google-services.json`)
- `local.properties` containing sensitive info beyond SDK paths

If risky files are found, **exclude them** and notify the user.

### 2. Branch Handling

If the current branch is `main` or `master`, create a new branch based on the nature of the changes.

**Default branch prefix rules:**
- `feat/` — new feature
- `fix/` — bug fix
- `refactor/` — refactoring (no behavior change)
- `test/` — test additions/modifications
- `docs/` — documentation changes
- `chore/` — build config, dependencies, misc
- `ci/` — CI/CD related

**Branch name format:** `{prefix}/{short-english-slug-with-hyphens}`

Command: `git checkout -b {branch-name}`

### 3. File Staging

Stage all changed files **except**:
- Sensitive files identified in the security review
- Build artifacts (`*.class`, `*.apk`, `*.aab`, `*.ipa`, `*.o`, `*.so`, `*.dylib`)

Stage each file explicitly with `git add {filepath}`. Do **not** use `git add -A` or `git add .`.

### 4. Commit Message

**Default format:**
```
{type}: {concise subject}

{body (optional)}
```

**Type:** `feat`, `fix`, `refactor`, `test`, `docs`, `chore`, `ci`

**Subject rules (defaults):**
- Written in English
- 50 characters or less
- Imperative mood (Add, Fix, Remove, Update)
- No trailing period

**Body rules (optional):**
- Skip if the change is trivial
- Explain *why* the change was made, not *what* changed
- Separate from subject with a blank line

**Commit command:**
```bash
git commit -m "$(cat <<'EOF'
{subject}

{body (if any)}
EOF
)"
```

### 5. Completion Report

After committing, briefly report:
- Branch created (if branched from main)
- Commit message summary
- Files excluded from staging (if any)
