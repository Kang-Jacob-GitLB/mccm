---
name: pr
description: 현재 브랜치를 push하고 PR을 생성한다. "/pr", "PR 만들어줘", "풀리퀘스트 생성", "create PR" 등의 요청에 사용한다.
disable-model-invocation: true
allowed-tools: Bash, Read
---

## 사전 요구사항

- [GitHub CLI (`gh`)](https://cli.github.com/) 설치 및 인증 필요 (`gh auth login`)

## 현재 상태

- 현재 브랜치: !`git branch --show-current`
- 베이스 브랜치와의 커밋 목록: !`git log main..HEAD --oneline`
- 베이스 브랜치와의 변경 diff: !`git diff main..HEAD`

> 위 명령의 `main`은 `base-branch` 슬롯 값으로 대체한다.
- 이미 PR 존재 여부: !`gh pr view 2>&1 || echo "PR 없음"`

## 오버라이드 슬롯

프로젝트의 CLAUDE.md에 `## mccm:PR Conventions` 섹션이 있으면, 아래 슬롯 중 명시된 항목만 대체한다. 명시되지 않은 슬롯은 기본값을 사용한다.

| 슬롯 | 키 | 기본값 |
|------|-----|--------|
| 베이스 브랜치 | `base-branch` | main |
| 언어 | `language` | 영문 |
| PR 제목 형식 | `title-format` | `{타입}: {제목}` |
| 타입 목록 | `types` | feat, fix, refactor, test, docs, chore, ci |
| 제목 최대 길이 | `title-max-length` | 70자 |
| 본문 형식 | `body-format` | `## Changes\n- ...\n\n## Test Plan\n...` |
| 라벨 매핑 | `label-map` | feat→feature, fix→bugfix, refactor→refactoring, test→test, docs→documentation, chore→chore, ci→ci/cd |
| 자동 assignee | `auto-assignee` | true (현재 GitHub 사용자) |
| 체크 타임아웃 | `checks-timeout` | 600000 (ms, 10분) |

**CLAUDE.md 작성 예시:**
```markdown
## mccm:PR Conventions
- language: 한글
- title-format: [{타입}] {제목}
- title-max-length: 60
- body-format: ## 변경 내용\n- ...\n\n## 테스트 계획\n...
- label-map: feat→enhancement, fix→bug
- auto-assignee: false
- checks-timeout: 300000
```

## 작업 지침

### 1. 사전 확인

- 현재 브랜치가 `base-branch` 슬롯의 브랜치이면 중단하고 사용자에게 알린다.
- 베이스 브랜치와의 커밋이 없으면 중단하고 사용자에게 알린다.
- 이미 PR이 열려 있으면 **업데이트 모드**로 전환한다 (6단계 참고).

### 2. Push

```bash
git push -u origin HEAD
```

### 3. PR 제목 작성

브랜치 이름과 커밋 목록을 바탕으로 PR 제목을 작성한다.

- 형식: `title-format` 슬롯 사용
- 타입: `types` 슬롯 사용
- 언어: `language` 슬롯 사용
- 제목 길이: `title-max-length` 슬롯 사용

### 4. PR 본문 작성

커밋 목록과 diff를 분석해 본문을 작성한다.

- 형식: `body-format` 슬롯 사용
- 언어: `language` 슬롯 사용
- 간결하게 작성
- 변경이 단순하면 본문 전체 생략 가능

### 5. PR 생성

- 라벨: `label-map` 슬롯 사용. 매핑된 라벨이 저장소에 존재하지 않으면 `--label` 옵션을 생략한다.
- assignee: `auto-assignee` 슬롯이 true이면 현재 GitHub 사용자를 할당

```bash
gh api user --jq '.login'
```

```bash
gh pr create --title "{제목}" --assignee "$(gh api user --jq '.login')" --label "{라벨}" --body "$(cat <<'EOF'
{본문}
EOF
)"
```

### 6. PR 업데이트 (이미 PR이 열려 있는 경우)

push 후 전체 커밋 목록과 diff를 재분석하여 제목과 본문을 업데이트한다.

```bash
gh pr edit --title "{제목}" --body "$(cat <<'EOF'
{본문}
EOF
)"
```

### 7. Actions 체크 추적

PR 생성(또는 업데이트) 후 GitHub Actions 체크가 완료될 때까지 대기한다.

```bash
gh pr checks --watch --fail-fast
```

> 이 명령은 `run_in_background`로 실행하고, 완료되면 결과를 확인한다. 타임아웃은 `checks-timeout` 슬롯 값을 사용한다.

- **전체 통과**: 체크 이름과 통과 상태를 요약 보고한다.
- **실패 발생**: 아래 절차를 수행한다.
  1. 실패한 체크 이름과 로그 URL을 알린다.
  2. `gh run view {run-id} --log-failed` 로 실패 로그를 가져와 원인을 분석한다.
  3. 수정 방안을 제시하고, 사용자 확인 후 코드를 수정한다.
  4. 수정 커밋 → push 후 7단계를 다시 수행한다.
- **체크 없음**: Actions가 설정되지 않은 저장소이면 이 단계를 건너뛴다.

### 8. 완료 보고

- PR URL
- Actions 체크 결과 (통과/실패/없음)
- 실패 수정 이력 (수정한 경우)
