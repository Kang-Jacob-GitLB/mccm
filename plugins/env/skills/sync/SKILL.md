---
name: sync
description: env.json 기반으로 마켓플레이스/플러그인/MCP/hooks/settings를 동기화한다. "/sync", "환경 동기화", "플러그인 동기화", "sync env" 등의 요청에 사용한다.
allowed-tools: Bash, Read, Edit
---

## 현재 상태

- env.json (gist): !`gh gist view 7360c28bfd37c47cd7d19d4106224e45 --filename env.json 2>/dev/null || echo "not found"`
- settings.json: !`cat "$HOME/.claude/settings.json" 2>/dev/null || echo "not found"`

## 변수 치환 규칙

env.json의 문자열 값에서 아래 변수를 치환한다:
- `${HOME}` → 현재 OS의 홈 디렉토리 (`$HOME` 또는 `$USERPROFILE`)
- `${USER}` → 현재 사용자명

## 작업 지침

위 두 파일을 비교하여 아래 순서대로 동기화한다.

### 1. 마켓플레이스

env.json의 `marketplaces`를 settings.json의 `extraKnownMarketplaces`와 비교한다.
- 미등록 마켓플레이스: `claude plugin marketplace add` 실행
- 등록 완료: `claude plugin marketplace update` 실행

### 2. 플러그인

env.json의 `plugins`를 settings.json의 `enabledPlugins`와 비교한다.
- 미설치: `claude plugin install` 실행
- 기설치: `claude plugin update` 실행

### 3. CLI 도구

env.json의 `clis`를 확인한다. 각 항목의 `check` 명령으로 설치 여부를 판단한다.

- 미설치: `install` 명령 실행
- 기설치: 스킵

### 4. settings

env.json의 `settings`를 settings.json과 비교한다. 변수 치환 적용 후 비교.

**충돌이 없는 경우** (env.json에만 있는 키): 바로 추가.

**충돌이 있는 경우** (같은 키에 다른 값): 사용자에게 물어본다:
- 각 충돌 항목을 표시: `키: env.json 값 vs settings.json 값`
- 선택지 제시: **(1) 취소** (기존 유지) / **(2) 대치** (env.json 값으로 교체) / **(3) 추가** (둘 다 유지, 객체인 경우 병합)
- 사용자 선택에 따라 적용

### 5. mcpServers

env.json의 `mcpServers`를 settings.json의 `mcpServers`와 비교한다. 변수 치환 적용.

- 새 서버: 바로 추가
- 기존 서버와 충돌: 4단계와 동일하게 사용자에게 물어본다

### 6. hooks

env.json의 `hooks`를 settings.json의 `hooks`와 비교한다. 변수 치환 적용.

- 새 hook: 바로 추가
- 기존 hook과 충돌 (동일 event + matcher에 다른 command): 사용자에게 물어본다

### 7. settings.json 저장

모든 변경을 적용하여 `$HOME/.claude/settings.json`에 저장한다.

Read 도구로 파일을 읽고, 변경 사항을 Edit 도구로 적용한다.

### 8. 완료 보고

- 등록/업데이트된 마켓플레이스
- 설치/업데이트된 플러그인
- 병합된 settings 항목
- 추가된 mcpServers
- 추가된 hooks
- 설치된 CLI 도구
- 충돌 해결 결과
