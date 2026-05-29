---
name: upload
description: 현재 PC의 settings.json을 Gist의 mccm.json에 업로드한다. "/upload", "환경 업로드", "upload env" 등의 요청에 사용한다.
allowed-tools: Bash, Read, Edit
---

## 현재 상태

- settings.json: !`cat "$HOME/.claude/settings.json" 2>/dev/null || echo "not found"`
- ccstatusline: !`cat "$HOME/.config/ccstatusline/settings.json" 2>/dev/null || echo "not found"`
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
| 나머지 포터블 설정 (`statusLine` 포함) | `settings` 객체 |

**제외 항목** (머신별 상태이므로):
- `feedbackSurveyState`
- `permissions` (비어있으면)
- `enabledPlugins` (plugins 섹션으로 이동)
- `extraKnownMarketplaces` (marketplaces 섹션으로 이동)

> `statusLine` 블록(예: `{"type":"command","command":"ccstatusline",...}`)은 머신 의존 경로가 없으면 `settings`에 그대로 포함한다. ccstatusline 바이너리는 아래 2단계에서 `clis`로 함께 등록되므로 둘이 항상 짝으로 배포된다.

### 2. ccstatusline 분석

`~/.config/ccstatusline/settings.json`(위젯 표시 항목·색상·테마 등 디자인 본체)이 존재하면:

1. 파일 내용 전체를 mccm.json의 `ccstatusline.config`에 저장한다 (JSON 객체 그대로).
2. mccm.json의 `clis` 배열에 ccstatusline 설치 항목이 없으면 추가한다:
   ```json
   { "name": "ccstatusline", "check": "command -v ccstatusline", "install": "npm install -g ccstatusline" }
   ```

파일이 없으면 `ccstatusline` 필드와 clis 항목을 추가하지 않는다(기존 값이 있으면 보존).

### 3. 변수 치환 (역방향)

모든 문자열 값에서 머신 의존 경로를 `${HOME}`, `${USER}` 변수로 교체한다. `ccstatusline.config`는 보통 경로를 포함하지 않으나, 포함된 경우 동일 규칙을 적용한다.

### 4. Gist 전용 항목 감지 (완전 동기화)

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

### 5. mccm.json 생성

위에서 추출한 데이터를 mccm.json 형식으로 구성한다:

```json
{
  "marketplaces": [...],
  "plugins": { "name@marketplace": "latest", ... },
  "clis": [ ... { "name": "ccstatusline", "check": "command -v ccstatusline", "install": "npm install -g ccstatusline" } ],
  "mcpServers": { ... },
  "hooks": { ... },
  "settings": { ..., "statusLine": { ... } },
  "ccstatusline": { "config": { ...위젯 표시 항목·색상·테마 본체... } }
}
```

### 6. 사용자 확인

생성된 mccm.json 내용을 사용자에게 보여주고 확인을 받는다.

`mcpServers`에 `env` 키(API 토큰 등)가 포함된 서버가 있으면 **해당 서버의 `env` 값을 제거한 상태**로 mccm.json을 구성한다.

> ⚠️ 아래 MCP 서버에 환경변수(API 토큰 등)가 포함되어 있어 제외했습니다:
> - (서버명 목록)
>
> **(1) 제외 유지** (기본) / **(2) 포함** 중 선택하세요.
> ⚠️ (2)를 선택하면 Gist에 토큰이 그대로 저장됩니다. secret Gist인지 반드시 확인하세요.

사용자가 명시적으로 **(2) 포함**을 선택한 경우에만 env를 포함한다.

### 7. gist 업데이트

`gh api gists`로 `mccm.json`을 포함하는 gist를 검색한다.

- **0개**: 새 gist를 생성한다 (`gh gist create --desc "mccm env"`).
- **1개**: 해당 gist를 업데이트한다.
- **2개 이상**: ID와 description을 목록으로 보여주고 사용자에게 선택을 받는다. `head -1`으로 자동 선택하지 않는다.

```bash
cat > /tmp/mccm.json <<'EOF'
{생성된 mccm.json 내용}
EOF

# GIST_ID는 위 선택 과정에서 결정된 값
if [ -n "$GIST_ID" ]; then
  gh gist edit "$GIST_ID" --filename mccm.json --add /tmp/mccm.json
else
  gh gist create /tmp/mccm.json --desc "mccm env"
fi
rm -f /tmp/mccm.json
```

### 8. 완료 보고

- 추출된 마켓플레이스 수
- 추출된 플러그인 수
- 추출된 MCP 서버 수
- 추출된 hook 수
- 추출된 설정 항목 수
- ccstatusline 설정 포함 여부 (위젯 라인/항목 수)
- 삭제된 Gist 전용 항목 (있는 경우)
