---
name: upload
description: 현재 PC의 settings.json과 전역 CLAUDE.md를 Gist의 mccm.json에 업로드한다. "/upload", "환경 업로드", "upload env" 등의 요청에 사용한다.
allowed-tools: Bash, Read, Edit
---

## 현재 상태

- settings.json: !`cat "$HOME/.claude/settings.json" 2>/dev/null || echo "not found"`
- ccstatusline: !`cat "$HOME/.config/ccstatusline/settings.json" 2>/dev/null || echo "not found"`
- CLAUDE.md: !`f="$HOME/.claude/CLAUDE.md"; [ -f "$f" ] && echo "존재 ($(wc -l < "$f") 줄, $(wc -c < "$f") 바이트) — 내용은 전사하지 말고 8단계에서 jq 로 주입" || echo "not found"`
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

> **⚠️ 글리프 주의 (필독):** `ccstatusline.config`의 `powerline.separators / startCaps / endCaps` 에는 화면상 **빈 칸으로 보이는 Nerd Font PUA 글리프**(U+E0B0~U+E0BF 등)가 들어 있다. 모델이 이 내용을 Read로 읽어 mccm.json 텍스트에 **옮겨 적으면 글리프가 빈 문자열로 소실**되고, 그대로 업로드하면 **gist(단일 진실원)가 오염**되어 이후 모든 PC의 `/download`에 빈 값이 퍼진다.
> - `ccstatusline.config`는 **절대 전사하지 않는다.** 8단계에서 파일 바이트를 `jq`로 그대로 주입한다.
> - 업로드 후 gist의 글리프가 로컬과 일치하는지 **반드시 검증**한다(8단계).

### 3. CLAUDE.md 분석

`~/.claude/CLAUDE.md`(전역 사용자 지침)가 존재하면 파일 내용 전체를 mccm.json의 `claudeMd`에 **문자열로** 저장한다.

파일이 없으면 `claudeMd` 필드를 추가하지 않는다(기존 값이 있으면 보존).

> **⚠️ 전사 금지:** `ccstatusline.config`와 같은 이유다. CLAUDE.md는 길고, 모델이 Read로 읽어 옮겨 적으면 줄바꿈·들여쓰기·유니코드가 어긋나거나 내용이 잘린다. **8단계에서 파일 바이트를 `jq --rawfile`로 그대로 주입**한다.

### 4. 변수 치환 (역방향)

모든 문자열 값에서 머신 의존 경로를 `${HOME}`, `${USER}` 변수로 교체한다. `ccstatusline.config`는 보통 경로를 포함하지 않으나, 포함된 경우 동일 규칙을 적용한다.

> **`claudeMd`는 치환 대상이 아니다.** CLAUDE.md 본문에는 셸 스니펫 예시처럼 **리터럴 `${HOME}`이 문서로서** 들어 있을 수 있고, 치환하면 사용자 지침이 변조된다. 원문 그대로 올린다 — CLAUDE.md에 머신 절대경로를 넣지 않는 것은 사용자 책임이다.

### 5. Gist 전용 항목 감지 (완전 동기화)

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

### 6. mccm.json 생성

위에서 추출한 데이터를 mccm.json 형식으로 구성한다:

```json
{
  "marketplaces": [...],
  "plugins": { "name@marketplace": "latest", ... },
  "clis": [ ... { "name": "ccstatusline", "check": "command -v ccstatusline", "install": "npm install -g ccstatusline" } ],
  "mcpServers": { ... },
  "hooks": { ... },
  "settings": { ..., "statusLine": { ... } },
  "ccstatusline": { "config": { ...위젯 표시 항목·색상·테마 본체... } },
  "claudeMd": "...CLAUDE.md 파일 내용 전체(문자열)..."
}
```

> `ccstatusline.config`와 `claudeMd`를 제외한 본문(marketplaces/plugins/clis/mcpServers/hooks/settings)은 settings.json에서 추출한 일반 JSON이라 모델이 조립해도 된다. 단 **`ccstatusline.config`와 `claudeMd`는 여기서 값을 채워 넣지 말고 생략**하고, 8단계에서 로컬 파일을 `jq`로 주입한다(글리프·원문 보존).

### 7. 사용자 확인

생성된 mccm.json 내용을 사용자에게 보여주고 확인을 받는다.

`mcpServers`에 `env` 키(API 토큰 등)가 포함된 서버가 있으면 **해당 서버의 `env` 값을 제거한 상태**로 mccm.json을 구성한다.

> ⚠️ 아래 MCP 서버에 환경변수(API 토큰 등)가 포함되어 있어 제외했습니다:
> - (서버명 목록)
>
> **(1) 제외 유지** (기본) / **(2) 포함** 중 선택하세요.
> ⚠️ (2)를 선택하면 Gist에 토큰이 그대로 저장됩니다. secret Gist인지 반드시 확인하세요.

사용자가 명시적으로 **(2) 포함**을 선택한 경우에만 env를 포함한다.

### 8. gist 업데이트

`gh api gists`로 `mccm.json`을 포함하는 gist를 검색한다.

- **0개**: 새 gist를 생성한다 (`gh gist create --desc "mccm env"`).
- **1개**: 해당 gist를 업데이트한다.
- **2개 이상**: ID와 description을 목록으로 보여주고 사용자에게 선택을 받는다. `head -1`으로 자동 선택하지 않는다.

> **⚠️ `ccstatusline.config`는 heredoc에 직접 적지 않는다.** PUA 글리프가 전사 과정에서 소실되기 때문이다. 본문은 heredoc으로 쓰되 `ccstatusline.config`는 로컬 파일에서 `jq`로 주입한다.

```bash
GIST_ID=<위 검색·선택 과정에서 결정된 gist id — 신규 생성이면 빈 값>
CCSL="$HOME/.config/ccstatusline/settings.json"
CMD_FILE="$HOME/.claude/CLAUDE.md"

# 1) ccstatusline.config / claudeMd 를 제외한 본문을 heredoc으로 작성 (모델이 조립해도 되는 부분만)
cat > /tmp/mccm-base.json <<'EOF'
{생성된 mccm.json 내용 — "ccstatusline" 과 "claudeMd" 필드는 생략}
EOF

# 2) ccstatusline.config는 로컬 파일 바이트를 jq로 주입 (전사 금지 → 글리프 보존)
if [ -f "$CCSL" ]; then
  jq --slurpfile ccsl "$CCSL" '.ccstatusline = {config: $ccsl[0]}' /tmp/mccm-base.json > /tmp/mccm.json
else
  cp /tmp/mccm-base.json /tmp/mccm.json
fi

# 2-1) CLAUDE.md 를 jq --rawfile 로 주입 (전사 금지 → 원문 보존)
#      줄바꿈은 LF 로 정규화한다. Windows 의 jq 는 raw 출력에서 CRLF 를 내보내므로,
#      정규화하지 않으면 upload/download 왕복마다 줄바꿈이 바뀌어 gist 가 계속 흔들린다.
if [ -f "$CMD_FILE" ]; then
  sed 's/\r$//' "$CMD_FILE" > /tmp/cmd.lf
  jq --rawfile cmd /tmp/cmd.lf '.claudeMd = $cmd' /tmp/mccm.json > /tmp/mccm2.json \
    && mv /tmp/mccm2.json /tmp/mccm.json
fi

# 3) gist 반영 (GIST_ID는 위 선택 과정에서 결정된 값)
if [ -n "$GIST_ID" ]; then
  gh gist edit "$GIST_ID" --filename mccm.json --add /tmp/mccm.json
else
  GIST_ID=$(gh gist create /tmp/mccm.json --desc "mccm env" 2>&1 | grep -oE '[0-9a-f]{20,}' | head -1)
fi

# 4) 업로드 후 검증: gist의 ccstatusline.config가 로컬 파일과 바이트 동일한지 (글리프 포함)
if [ -f "$CCSL" ]; then
  diff <(gh gist view "$GIST_ID" --filename mccm.json | jq -S '.ccstatusline.config') \
       <(jq -S . "$CCSL") >/dev/null \
    && echo "업로드 검증 OK (글리프 포함 일치)" \
    || echo "⚠️ 글리프 소실/불일치 — 본문에 config를 적지 말고 jq 주입으로 재시도"
fi

# 5) CLAUDE.md 검증 — 원시 바이트가 아니라 JSON 값끼리 비교한다.
#    jq 의 raw 출력은 플랫폼에 따라 줄바꿈이 달라져 바이트 비교가 상시 실패한다.
if [ -f "$CMD_FILE" ]; then
  diff <(gh gist view "$GIST_ID" --filename mccm.json | jq '.claudeMd') \
       <(jq -Rs . /tmp/cmd.lf) >/dev/null \
    && echo "CLAUDE.md 검증 OK (원문 일치)" \
    || echo "⚠️ CLAUDE.md 불일치 — 본문에 적지 말고 jq --rawfile 주입으로 재시도"
fi
rm -f /tmp/mccm-base.json /tmp/mccm.json /tmp/mccm2.json /tmp/cmd.lf
```

### 9. 완료 보고

- 추출된 마켓플레이스 수
- 추출된 플러그인 수
- 추출된 MCP 서버 수
- 추출된 hook 수
- 추출된 설정 항목 수
- ccstatusline 설정 포함 여부 (위젯 라인/항목 수)
- CLAUDE.md 포함 여부 (줄 수) 및 검증 결과
- 삭제된 Gist 전용 항목 (있는 경우)
