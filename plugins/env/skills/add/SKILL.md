---
name: add
description: 환경에 플러그인/마켓플레이스/MCP/hook/setting을 추가한다. "/add", "플러그인 추가해줘", "환경에 추가", "MCP 추가", "add to env" 등의 요청에 사용한다.
allowed-tools: Bash, Read, Edit
---

## 현재 상태

- env.json (gist): !`gh gist view 7360c28bfd37c47cd7d19d4106224e45 --filename env.json 2>/dev/null || echo "not found"`

## 작업 지침

사용자의 요청을 분석하여 아래 절차를 수행한다.

### 1. 요청 파싱

추가 대상을 파악한다:

- **플러그인**: `플러그인명@마켓플레이스` 형식 → `plugins` 에 추가
- **마켓플레이스**: 이름 + repo 또는 git URL → `marketplaces` 에 추가
- **MCP 서버**: 이름 + 설정 → `mcpServers` 에 추가
- **hook**: 이벤트 + matcher + command → `hooks` 에 추가
- **CLI 도구**: 이름 + check 명령 + install 명령 → `clis` 에 추가
- **setting**: 키 + 값 → `settings` 에 추가
- 모호한 경우 사용자에게 확인한다
- 경로에 머신 의존값이 있으면 `${HOME}`, `${USER}` 변수로 치환하여 저장

### 2. gist에서 env.json 가져오기

```bash
gh gist view 7360c28bfd37c47cd7d19d4106224e45 --filename env.json > /tmp/mccm-env.json
```

### 3. env.json 수정

`/tmp/mccm-env.json`을 수정한다.

- 이미 존재하는 항목이면 추가하지 않고 사용자에게 알린다
- 플러그인 추가 시, 해당 마켓플레이스가 `marketplaces`에 없으면 함께 추가한다

### 4. gist 업데이트

```bash
gh gist edit 7360c28bfd37c47cd7d19d4106224e45 --filename env.json --add /tmp/mccm-env.json
```

### 5. 즉시 적용

추가한 항목을 현재 PC에도 바로 적용한다:

- 마켓플레이스: `claude plugin marketplace add` + `update`
- 플러그인: `claude plugin install`
- MCP/hook/setting: `$HOME/.claude/settings.json`에 직접 병합 (변수 치환 적용)

### 6. 정리

```bash
rm -f /tmp/mccm-env.json
```

### 7. 완료 보고

- 추가된 항목
- 즉시 적용 결과
- 다른 PC 반영 시점 (`/sync` 실행 시)
