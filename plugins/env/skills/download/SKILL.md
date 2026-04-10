---
name: download
description: Gist의 mccm.json을 로컬 settings.json에 적용한다. "/download", "환경 다운로드", "download env" 등의 요청에 사용한다.
allowed-tools: Bash, Read, Edit
---

## 현재 상태

- mccm.json (gist): !`GIST_ID=$(gh api gists --jq '.[] | select(.files["mccm.json"] != null) | .id' 2>/dev/null | head -1); [ -n "$GIST_ID" ] && gh gist view "$GIST_ID" --filename mccm.json 2>/dev/null || echo "not found — gist에 mccm.json 파일이 없습니다"`
- settings.json: !`cat "$HOME/.claude/settings.json" 2>/dev/null || echo "not found"`

## 변수 치환 규칙

mccm.json의 문자열 값에서 아래 변수를 치환한다:
- `${HOME}` → 현재 OS의 홈 디렉토리 (`$HOME` 또는 `$USERPROFILE`)
- `${USER}` → 현재 사용자명

## 작업 지침

Gist의 mccm.json을 기준으로 로컬 환경을 구성한다.

### 0. gist 확인

gist를 찾을 수 없으면 사용자에게 안내한다: `gh gist create --desc "mccm env" --public` 으로 mccm.json gist를 먼저 생성하라고.

### 1. 마켓플레이스

mccm.json의 `marketplaces`를 settings.json의 `extraKnownMarketplaces`와 비교한다.
- 미등록 마켓플레이스: `claude plugin marketplace add` 실행
- 등록 완료: `claude plugin marketplace update` 실행

### 2. 플러그인

mccm.json의 `plugins`를 settings.json의 `enabledPlugins`와 비교한다.
- 미설치: `claude plugin install` 실행
- 기설치: `claude plugin update` 실행

### 3. CLI 도구

mccm.json의 `clis`를 확인한다. 각 항목의 `check` 명령으로 설치 여부를 판단한다.

- 미설치: `install` 명령 실행
- 기설치: 스킵

### 4. settings

mccm.json의 `settings`를 settings.json과 비교한다. 변수 치환 적용 후 비교.

**충돌이 없는 경우** (mccm.json에만 있는 키): 바로 추가.

**충돌이 있는 경우** (같은 키에 다른 값): 사용자에게 물어본다:
- 각 충돌 항목을 표시: `키: mccm.json 값 vs settings.json 값`
- 선택지 제시: **(1) 취소** (기존 유지) / **(2) 대치** (mccm.json 값으로 교체)
- 사용자 선택에 따라 적용

### 5. mcpServers

mccm.json의 `mcpServers`를 settings.json의 `mcpServers`와 비교한다. 변수 치환 적용.

- 새 서버: 바로 추가
- 기존 서버와 충돌: 4단계와 동일하게 사용자에게 물어본다

### 6. hooks

mccm.json의 `hooks`를 settings.json의 `hooks`와 비교한다. 변수 치환 적용.

- 새 hook: 바로 추가
- 기존 hook과 충돌 (동일 event + matcher에 다른 command): 사용자에게 물어본다

### 7. 로컬 전용 항목 감지 (완전 동기화)

settings.json에는 있지만 mccm.json에는 없는 항목을 감지한다:

- `enabledPlugins`에 있지만 mccm.json `plugins`에 없는 플러그인
- `mcpServers`에 있지만 mccm.json `mcpServers`에 없는 서버
- `hooks`에 있지만 mccm.json `hooks`에 없는 hook

감지된 항목이 있으면 사용자에게 목록을 보여주고 물어본다:
> 아래 항목은 로컬에만 존재하고 Gist에는 없습니다:
> - (항목 목록)
>
> **(1) 유지** (로컬에만 남김) / **(2) 삭제** (Gist 기준으로 완전 동기화)

사용자가 **(2) 삭제**를 선택하면:
- 플러그인: `claude plugin uninstall` 실행
- mcpServers, hooks: settings.json에서 제거

### 8. settings.json 저장

모든 변경을 적용하여 `$HOME/.claude/settings.json`에 저장한다.

Read 도구로 파일을 읽고, 변경 사항을 Edit 도구로 적용한다.

### 9. 완료 보고

- 등록/업데이트된 마켓플레이스
- 설치/업데이트된 플러그인
- 병합된 settings 항목
- 추가된 mcpServers
- 추가된 hooks
- 설치된 CLI 도구
- 충돌 해결 결과
- 삭제된 로컬 전용 항목 (있는 경우)
