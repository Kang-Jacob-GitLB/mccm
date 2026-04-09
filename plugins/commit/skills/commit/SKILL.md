---
name: commit
description: 변경 사항을 staging하고 커밋한다. "/commit", "커밋해줘", "변경사항 커밋", "commit the changes" 등의 요청에 사용한다.
disable-model-invocation: true
allowed-tools: Bash, Read
---

## 현재 상태

- 현재 브랜치: !`git branch --show-current`
- Git 상태: !`git status`
- 변경 사항 diff: !`git diff HEAD`
- 최근 커밋: !`git log --oneline -5`

## 오버라이드 슬롯

프로젝트의 CLAUDE.md에 `## jacob-plugin:Commit Conventions` 섹션이 있으면, 아래 슬롯 중 명시된 항목만 대체한다. 명시되지 않은 슬롯은 기본값을 사용한다.

| 슬롯 | 키 | 기본값 |
|------|-----|--------|
| 언어 | `language` | 영문 |
| 커밋 제목 형식 | `title-format` | `{타입}: {제목}` |
| 타입 목록 | `types` | feat, fix, refactor, test, docs, chore, ci |
| 제목 최대 길이 | `title-max-length` | 50자 |
| 본문 포함 | `body` | 선택 |
| 브랜치 접두사 | `branch-prefixes` | feat/, fix/, refactor/, test/, docs/, chore/, ci/ |
| 브랜치 이름 형식 | `branch-format` | `{prefix}/{english-slug}` |

**CLAUDE.md 작성 예시:**
```markdown
## jacob-plugin:Commit Conventions
- language: 한글
- title-format: {제목}
- types: add, fix, update, remove
- title-max-length: 40
- body: 필수
- branch-prefixes: feature/, bugfix/, hotfix/
```

## 작업 지침

위의 변경 사항을 분석하여 아래 절차를 순서대로 수행한다.

### 1. 보안 검토

커밋하기 전에 아래 패턴이 포함된 파일이 스테이징 대상에 포함되는지 확인한다:
- `.env`, `.env.*` (`.env.example` 제외)
- API 키, 비밀 키, 토큰, 패스워드가 하드코딩된 코드
- 인증 관련 파일 (`*.jks`, `*.keystore`, `*.pem`, `*.p12`, `credentials.json`, `google-services.json`)
- `local.properties` (SDK 경로 외 민감 정보 포함 시)

보안상 위험한 파일이 있으면 **해당 파일을 제외하고** 사용자에게 반드시 알린다.

### 2. 브랜치 처리

현재 브랜치가 `main` 또는 `master`이면, 변경 사항의 성격에 맞는 새 브랜치를 생성한다.

- 접두사: `branch-prefixes` 슬롯 사용
- 이름 형식: `branch-format` 슬롯 사용

명령: `git checkout -b {브랜치명}`

### 3. 파일 스테이징

아래 파일 유형을 **제외**하고 모든 변경 파일을 스테이징한다:
- 보안 검토에서 식별된 민감 파일
- 빌드 산출물 (`*.class`, `*.apk`, `*.aab`, `*.ipa`, `*.o`, `*.so`, `*.dylib`)

변경 파일 각각을 `git add {파일경로}`로 명시적으로 스테이징한다. `git add -A`나 `git add .`는 사용하지 않는다.

### 4. 커밋 메시지 작성

- 형식: `title-format` 슬롯 사용
- 타입: `types` 슬롯 사용
- 언어: `language` 슬롯 사용
- 제목 길이: `title-max-length` 슬롯 사용
- 본문: `body` 슬롯 사용 (선택 = 단순 변경 시 생략, 필수 = 항상 포함)

**커밋 명령:**
```bash
git commit -m "$(cat <<'EOF'
{제목}

{본문 (있는 경우만)}
EOF
)"
```

### 5. 완료 보고

커밋 완료 후 다음을 간략히 알린다:
- 생성된 브랜치 (main에서 분기한 경우)
- 커밋 메시지 요약
- 스테이징에서 제외된 파일 (있는 경우)
