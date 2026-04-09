---
name: cleanup
description: PR이 리모트에서 머지된 후 로컬을 리모트와 동기화하고 불필요한 로컬 브랜치를 정리한다. "/cleanup", "머지 후 정리", "브랜치 정리해줘" 등의 요청에 사용한다.
disable-model-invocation: true
allowed-tools: Bash, Read
---

## 현재 상태

- 현재 브랜치: !`git branch --show-current`
- 워킹 트리 상태: !`git status --short`
- 로컬 브랜치 목록: !`git branch`
- Remote에서 삭제된 브랜치: !`git fetch --prune --dry-run 2>&1`

## 오버라이드 슬롯

프로젝트의 CLAUDE.md에 `## jacob-plugin:Cleanup Conventions` 섹션이 있으면, 아래 슬롯 중 명시된 항목만 대체한다. 명시되지 않은 슬롯은 기본값을 사용한다.

| 슬롯 | 키 | 기본값 |
|------|-----|--------|
| 기본 브랜치 | `default-branch` | main |
| 삭제 제외 브랜치 | `protected-branches` | main, master |

**CLAUDE.md 작성 예시:**
```markdown
## jacob-plugin:Cleanup Conventions
- default-branch: main
- protected-branches: main, master, develop
```

## 작업 지침

PR이 리모트에서 머지 완료된 상태에서, 로컬을 리모트와 동기화하고 남아 있는 작업 브랜치를 정리한다. 아래 절차를 순서대로 수행한다.

### 1. 사전 확인

`git status --short` 결과가 비어 있지 않으면 (미커밋 변경 또는 untracked 파일 존재) **중단**하고 사용자에게 아래 중 하나를 선택하도록 안내한다:

- **커밋**: 변경 사항을 커밋한 뒤 다시 실행
- **스태시**: `git stash`로 임시 저장한 뒤 다시 실행
- **취소**: cleanup을 중단하고 현재 작업 유지

### 2. 기본 브랜치로 이동

`default-branch` 슬롯의 브랜치로 이동한다.

```bash
git checkout {default-branch}
```

### 3. 리모트 동기화

리모트의 최신 상태를 로컬에 반영하고, 리모트에서 삭제된 트래킹 브랜치를 정리한다.

```bash
git pull
git fetch --prune
```

### 4. 불필요한 로컬 브랜치 삭제

리모트에서 이미 삭제된(gone) 브랜치 중 아래 브랜치를 **제외**하고 삭제한다:
- `default-branch` 슬롯의 브랜치 (자동 보호)
- `protected-branches` 슬롯에 지정된 브랜치
- 리모트에 push된 적 없는 로컬 전용 브랜치

`protected-branches` 슬롯의 값으로 grep 제외 패턴을 동적으로 구성한다:

```bash
# protected-branches 슬롯 값 + default-branch를 grep 패턴으로 변환
# 예: main, master → '^main$\|^master$'
GONE=$(git branch -vv | grep ': gone]' | awk '{print $1}' | grep -v '{protected-branches 패턴}')
[ -n "$GONE" ] && echo "$GONE" | xargs git branch -D
```

### 5. 완료 보고

- 현재 브랜치
- 삭제된 로컬 브랜치 목록
- 삭제되지 않은 브랜치 (있는 경우)
