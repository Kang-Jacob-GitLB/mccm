---
name: upload
description: 현재 PC의 settings.json을 Gist의 mccm.json에 업로드한다. "/upload", "환경 업로드", "upload env" 등의 요청에 사용한다.
allowed-tools: Bash, Read, Edit
---

## 현재 상태

- settings.json: !`cat "$HOME/.claude/settings.json" 2>/dev/null || echo "not found"`
- 현재 mccm.json (gist): !`GIST_ID=$(gh api gists --jq '.[] | select(.files["mccm.json"] != null) | .id' 2>/dev/null | head -1); [ -n "$GIST_ID" ] && gh gist view "$GIST_ID" --filename mccm.json 2>/dev/null || echo "not found — gist에 mccm.json 파일이 없습니다"`

## 변수 치환 규칙 (역방향)

settings.json의 값을 mccm.json에 저장할 때, 머신 의존 경로를 변수로 치환한다:
- 홈 디렉토리 경로 (`$HOME` 또는 `$USERPROFILE` 값) → `${HOME}`
- 사용자명 (`$USER` 또는 `$USERNAME` 값) → `${USER}`

## 작업 지침

현재 PC의 settings.json을 기준으로 Gist의 mccm.json을 업데이트한다.

### 1. settings.json 분석

settings.json에서 아래 섹션을 추출한다:

| settings.json 키 | mccm.json 매핑 |
|---|---|
| `extraKnownMarketplaces` | `marketplaces` 배열 |
| `enabledPlugins` (값이 `true`인 것만) | `plugins` 객체 (`"latest"`) |
| `mcpServers` | `mcpServers` 객체 |
| `hooks` | `hooks` 객체 |
| 나머지 포터블 설정 | `settings` 객체 |

**제외 항목** (머신별 상태이므로):
- `feedbackSurveyState`
- `permissions` (비어있으면)
- `enabledPlugins` (plugins 섹션으로 이동)
- `extraKnownMarketplaces` (marketplaces 섹션으로 이동)

### 2. 변수 치환 (역방향)

모든 문자열 값에서 머신 의존 경로를 `${HOME}`, `${USER}` 변수로 교체한다.

### 3. Gist 전용 항목 감지 (완전 동기화)

기존 mccm.json과 비교하여, Gist에는 있지만 로컬 settings.json에는 없는 항목을 감지한다:

- mccm.json `plugins`에 있지만 로컬 `enabledPlugins`에 없는 플러그인
- mccm.json `mcpServers`에 있지만 로컬 `mcpServers`에 없는 서버
- mccm.json `hooks`에 있지만 로컬 `hooks`에 없는 hook
- mccm.json `clis`에 있지만 로컬에 설치되지 않은 CLI 도구

감지된 항목이 있으면 사용자에게 목록을 보여주고 물어본다:
> 아래 항목은 Gist에만 존재하고 현재 PC에는 없습니다:
> - (항목 목록)
>
> **(1) 유지** (Gist에 남김) / **(2) 삭제** (로컬 기준으로 완전 동기화)

사용자가 **(2) 삭제**를 선택하면 생성할 mccm.json에서 해당 항목을 제외한다.

### 4. mccm.json 생성

위에서 추출한 데이터를 mccm.json 형식으로 구성한다:

```json
{
  "marketplaces": [...],
  "plugins": { "name@marketplace": "latest", ... },
  "mcpServers": { ... },
  "hooks": { ... },
  "settings": { ... }
}
```

### 5. 사용자 확인

생성된 mccm.json 내용을 사용자에게 보여주고 확인을 받는다.

### 6. gist 업데이트

```bash
GIST_ID=$(gh api gists --jq '.[] | select(.files["mccm.json"] != null) | .id' | head -1)

cat > /tmp/mccm.json <<'EOF'
{생성된 mccm.json 내용}
EOF

if [ -n "$GIST_ID" ]; then
  gh gist edit "$GIST_ID" --filename mccm.json --add /tmp/mccm.json
else
  gh gist create /tmp/mccm.json --desc "mccm env" --public
fi
rm -f /tmp/mccm.json
```

### 7. 완료 보고

- 추출된 마켓플레이스 수
- 추출된 플러그인 수
- 추출된 MCP 서버 수
- 추출된 hook 수
- 추출된 설정 항목 수
- 삭제된 Gist 전용 항목 (있는 경우)
