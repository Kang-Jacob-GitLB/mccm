---
name: upload
description: 현재 PC의 settings.json과 전역 CLAUDE.md를 Gist의 mccm.json에 업로드한다. "/upload", "환경 업로드", "upload env" 등의 요청에 사용한다.
allowed-tools: Bash, Read, Edit
---

## 현재 상태

- settings.json: !`cat "$HOME/.claude/settings.json" 2>/dev/null || echo "not found"`
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
| 나머지 포터블 설정 | `settings` 객체 |

**제외 항목** (머신별 상태이므로):
- `feedbackSurveyState`
- `permissions` (비어있으면)
- `enabledPlugins` (plugins 섹션으로 이동)
- `extraKnownMarketplaces` (marketplaces 섹션으로 이동)
- `env`의 인증 정보 키 (토큰·인증 헤더 등 — 판정과 사용자 확인은 7단계)

### 2. worklog 프로필 수집

아래 두 프로필(worklog 플러그인의 개인화 프로필)은 각각 파일이 존재하고 최상위 `.sync`가 `true`이면 업로드 대상에 포함한다. 둘은 서로 독립이다 — 한쪽만 켜도 된다.

| 로컬 파일 | gist 형제 파일 | 쓰는 스킬 |
|---|---|---|
| `$HOME/.config/mccm/worklog.json` | `worklog.json` | `today`·`week` |
| `$HOME/.config/mccm/jira-task.json` | `jira-task.json` | `jira-task-create`·`jira-epic-create` |

**mccm.json에는 넣지 않는다.** 같은 gist의 같은 이름 형제 파일로 8단계에서 별도 업로드한다 — 6단계에서 mccm.json 본문은 매번 heredoc으로 새로 조립되고, 5단계 "gist 전용 항목 감지"는 `plugins`/`mcpServers`/`hooks`/`clis`만 보므로, mccm.json 안에 손으로 넣은 키는 다음 `/upload`에서 조용히 사라질 위험이 있다.

`.sync`가 `false`이거나 파일이 없으면 건너뛴다(정상, 조용히 스킵).

> ⚠️ gist의 "secret"은 비공개가 아니라 **URL을 아는 누구나 접근 가능**하다는 뜻이다. 그래서 프로필에는 토큰·서버 주소·로그인 이메일을 넣지 않는다 — 각각 `JIRA_API_TOKEN` 환경변수와 `~/.config/.jira/.config.yml`이 담당한다.

### 3. CLAUDE.md 분석

`~/.claude/CLAUDE.md`(전역 사용자 지침)가 존재하면 파일 내용 전체를 mccm.json의 `claudeMd`에 **문자열로** 저장한다.

파일이 없으면 `claudeMd` 필드를 추가하지 않는다(기존 값이 있으면 보존).

> **⚠️ 전사 금지:** CLAUDE.md는 길고, 모델이 Read로 읽어 옮겨 적으면 줄바꿈·들여쓰기·유니코드가 어긋나거나 내용이 잘린다. **8단계에서 파일 바이트를 `jq --rawfile`로 그대로 주입**한다.

### 4. 변수 치환 (역방향)

모든 문자열 값에서 머신 의존 경로를 `${HOME}`, `${USER}` 변수로 교체한다.

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
  "clis": [ ... ],
  "mcpServers": { ... },
  "hooks": { ... },
  "settings": { ... },
  "claudeMd": "...CLAUDE.md 파일 내용 전체(문자열)..."
}
```

> `claudeMd`를 제외한 본문(marketplaces/plugins/clis/mcpServers/hooks/settings)은 settings.json에서 추출한 일반 JSON이라 모델이 조립해도 된다. 단 **`claudeMd`는 여기서 값을 채워 넣지 말고 생략**하고, 8단계에서 로컬 파일을 `jq --rawfile`로 주입한다(원문 보존).

### 7. 사용자 확인

생성된 mccm.json 내용을 사용자에게 보여주고 확인을 받는다.

`mcpServers`에 `env` 키(API 토큰 등)가 포함된 서버가 있으면 **해당 서버의 `env` 값을 제거한 상태**로 mccm.json을 구성한다.

> ⚠️ 아래 MCP 서버에 환경변수(API 토큰 등)가 포함되어 있어 제외했습니다:
> - (서버명 목록)
>
> **(1) 제외 유지** (기본) / **(2) 포함** 중 선택하세요.
> ⚠️ (2)를 선택하면 Gist에 토큰이 그대로 저장됩니다. secret Gist인지 반드시 확인하세요.

사용자가 명시적으로 **(2) 포함**을 선택한 경우에만 env를 포함한다.

`settings.env`에도 인증 정보가 들어 있을 수 있다(예: `OTEL_EXPORTER_OTLP_HEADERS`의 Basic 인증). 아래 중 하나에 해당하는 키는 **제거한 상태**로 mccm.json을 구성한다:

- 키 이름에 `TOKEN`·`KEY`·`SECRET`·`AUTH`·`PASS`·`PWD`·`CREDENTIAL`·`HEADER`·`DSN` 포함 (대소문자 무시). `PAT`는 `PATH`·`PATTERN` 오탐이 나므로 쓰지 않는다.
- 값에 `Basic `·`Bearer `가 포함 (대소문자 무시). **값의 시작이 아니라 포함 여부로 판정한다** — 실제 값은 `Authorization=Basic ...` 처럼 앞에 다른 토막이 붙는다. `Basic%20...` 같은 URL 인코딩 변형도 함께 본다.
- 값에 URL 자격증명 `://사용자:비밀번호@호스트` 형태가 포함 (`HTTPS_PROXY`, `SENTRY_DSN` 등)

> ⚠️ 아래 `settings.env` 항목에 인증 정보가 있어 제외했습니다:
> - (키 목록 — **값은 표시하지 않는다**)
>
> **(1) 제외 유지** (기본) / **(2) 포함** 중 선택하세요.
> ⚠️ (2)를 선택하면 Gist에 인증 정보가 그대로 저장됩니다. secret Gist인지 반드시 확인하세요.

사용자가 명시적으로 **(2) 포함**을 선택한 경우에만 포함한다. 제외해도 나머지 `env` 키는 그대로 올라가므로, 다른 PC에서는 인증 값만 직접 채워 넣으면 된다.

프로필(`worklog.json`·`jira-task.json`)을 업로드 대상에 포함한 경우(2단계), 별도로 **값 패턴** 스캔을 한다. 이 스캔은 산문 규칙이 아니라 **8단계 업로드 블록 안에 실행 코드로 내장**되어 있다 — 8단계 블록만 실행해도 스캔이 생략되지 않는다.

- 기존 필터를 그대로 쓸 수 없는 이유: 기존 필터는 키 이름에 `TOKEN`·`KEY` 등이 들어가면 제거하는 방식인데, 프로필 스키마의 `examples.issue_keys`(예: `ABC-123`) 같은 키가 "KEY" 문자열을 포함해 전량 오탐한다. 그래서 여기서는 **키 이름 문자열이 아니라 토큰 형태**를 본다 — 값과 키 경로 양쪽에 같은 규칙을 적용한다(사람이 토큰을 키 이름에 적어 두는 일이 실제로 있다).
- 아래 패턴이 하나라도 걸리면 업로드를 중단한다. 각 규칙은 길이만이 아니라 **토큰다움**을 요구한다 — `"Keep it basic and short."`나 `Weekly_Report_For_Team_Alpha_2026` 같은 정상 값이 걸리면 사용자가 스캔 자체를 끄게 되므로, 정밀도도 안전의 일부다:
  - `Basic`/`Bearer` 뒤에 공백 또는 `%20`이 오고, 이어지는 8자 이상 덩어리에 숫자나 `+/=`가 든 경우 (영어 문장의 "basic ..."은 걸리지 않는다)
  - `ATATT`/`ATCTT` (Atlassian), `ghp_`/`github_pat_`/`gho_`/`ghs_` (GitHub), `xox[baprs]-`/`xapp-` (Slack), `AIza` (Google), `sk-` (OpenAI류), `AKIA` (AWS), `glpat-` (GitLab) — **값의 어느 위치에 있어도** 걸린다. 단 `sk-` 는 `task-create`·`risk-based` 처럼 낱말 안에 흔해, 바로 앞이 영숫자가 아닐 때(값 맨 앞·공백·`=`·`:` 뒤 등)만 본다
  - `://사용자:비밀번호@호스트` 형태
  - 구분자 없이 이어진 24자 이상 영숫자 런에 숫자가 포함된 경우 (경로·URL·CamelCase 식별자는 런이 끊겨 걸리지 않는다)
  - 40자 이상 base64 런에 숫자가 포함된 경우 / 32자 이상 16진 문자열 / UUID 형태
- **유일한 예외 — `jira-task.json` 의 `reference_users[].accountId`.** Jira accountId(`5b10…` 같은 24자리 16진, 또는 `712020:` + UUID)는 자격증명이 아니라 공개 식별자인데, 위 규칙의 "24자 이상 런"·UUID 에 반드시 걸린다. 그래서 **그 경로의 값이 accountId 형식에 정확히 일치할 때만** 스캔에서 뺀다. 형식이 조금이라도 다르면(접두·접미가 붙거나 다른 키에 있으면) 그대로 스캔되어 걸린다 — 예외가 토큰을 숨기는 통로가 되지 않게 하기 위해서다. 다른 경로·다른 파일에는 예외가 없다. 다만 동료의 실명과 accountId 가 "URL 을 아는 누구나" 볼 수 있는 gist 에 올라간다는 점은 `.sync` 를 켜기 전에 사용자에게 알린다. **`.sync` 를 다시 꺼도 회수가 아니다** — 이미 올라간 파일은 gist 에 남고(8단계가 경고만 한다), 지워도 gist 리비전 이력에 남는다.
- 스캔은 원본이 아니라 **`jq -S` 정규화 사본**에 하고, 올리는 것도 그 사본이다. 원본을 올리면 같은 키가 두 번 있을 때 스캔은 마지막 값만 보고 원본에는 앞 값이 그대로 남는다.
- **사내 호스트명·내부 URL**은 위 패턴에 걸리지 않지만 `report_destination` 등에 가장 자연스럽게 들어갈 수 있는 값이다. 값에 사내 위키·인트라넷으로 보이는 호스트명이 보이면 패턴 매치 여부와 무관하게 사용자에게 업로드해도 되는지 확인한다.

> ⚠️ (worklog.json / jira-task.json)에서 아래 경로에 민감해 보이는 값이 발견되어 그 파일의 업로드를 중단했습니다:
> - (JSON 경로만 표시 — **값은 표시하지 않는다**)
>
> 프로필에서 해당 값을 제거한 뒤 다시 시도하세요. (MCP 서버·settings.env와 달리 "포함" 선택지는 제공하지 않는다 — worklog 프로필은 개인 작업 로그이므로 토큰류가 들어갈 이유가 없다.)

### 8. gist 업데이트

`gh api gists`로 `mccm.json`을 포함하는 gist를 검색한다.

- **0개**: 새 gist를 생성한다 (`gh gist create --desc "mccm env"`).
- **1개**: 해당 gist를 업데이트한다.
- **2개 이상**: ID와 description을 목록으로 보여주고 사용자에게 선택을 받는다. `head -1`으로 자동 선택하지 않는다.

> **⚠️ `claudeMd`는 heredoc에 직접 적지 않는다.** 모델이 옮겨 적으면 줄바꿈·유니코드가 어긋나기 때문이다. 본문은 heredoc으로 쓰되 `claudeMd`는 로컬 파일에서 `jq --rawfile`로 주입한다.

```bash
GIST_ID=<위 검색·선택 과정에서 결정된 gist id — 신규 생성이면 빈 값>
CMD_FILE="$HOME/.claude/CLAUDE.md"

# 1) claudeMd 를 제외한 본문을 heredoc으로 작성 (모델이 조립해도 되는 부분만)
cat > /tmp/mccm.json <<'EOF'
{생성된 mccm.json 내용 — "claudeMd" 필드는 생략}
EOF

# 2) CLAUDE.md 를 jq --rawfile 로 주입 (전사 금지 → 원문 보존)
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

# 4) CLAUDE.md 검증 — 원시 바이트가 아니라 JSON 값끼리 비교한다.
#    jq 의 raw 출력은 플랫폼에 따라 줄바꿈이 달라져 바이트 비교가 상시 실패한다.
if [ -f "$CMD_FILE" ]; then
  diff <(gh gist view "$GIST_ID" --filename mccm.json | jq '.claudeMd') \
       <(jq -Rs . /tmp/cmd.lf) >/dev/null \
    && echo "CLAUDE.md 검증 OK (원문 일치)" \
    || echo "⚠️ CLAUDE.md 불일치 — 본문에 적지 말고 jq --rawfile 주입으로 재시도"
fi
# 5) 프로필(worklog.json·jira-task.json)은 mccm.json과 별개의 형제 파일로 업로드한다 (2단계 참고, mccm.json에는 넣지 않는다)
#    이 블록만 실행해도 7단계 스캔이 생략되지 않도록, 게이트를 블록 안에 그대로 넣는다.
#    gist 형제 파일 이름 = 로컬 파일 이름. 목록을 늘릴 때는 download 4단계의 목록도 함께 고친다.
PROFILE_DIR="$HOME/.config/mccm"
SYNC_PROFILES="worklog.json jira-task.json"

wl_scan() {   # $1=파일 $2=gist 파일 이름. 민감 의심 값·키 이름이 있는 JSON 경로만 출력한다. 출력이 비면 깨끗한 것이다. 값 자체는 절대 출력하지 않는다.
  # 길이만으로는 자격증명과 평범한 식별자를 못 가른다. 그래서 각 규칙이 "토큰다움"을
  # 요구한다 — 인증 스킴 뒤에 숫자/기호가 든 덩어리, 구분자 없는 긴 런 + 숫자, 16진/UUID.
  # 오탐이 잦으면 사용자가 스캔을 끄게 되므로, 정밀도도 안전의 일부다.
  # 예외는 jira-task.json 의 reference_users[].accountId 하나뿐이고, 값이 accountId 형식에
  # "정확히" 맞을 때만 뺀다 — 형식이 어긋나면 그대로 스캔돼 걸린다(예외가 토큰 은닉 통로가 되지 않게).
  jq -r --arg name "$2" '
    def accountid: type == "string"
        and test("^([0-9a-f]{24}|[0-9]{1,10}:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})$");
    def exempt:
        if $name == "jira-task.json" and (.reference_users | type) == "array"
        then .reference_users |= map(if type == "object" and (.accountId | accountid) then del(.accountId) else . end)
        else . end;
    def suspicious:
        test("(basic|bearer)([ ]|%20)(?=[A-Za-z0-9+/=_.\\-]{8,})[A-Za-z0-9+/=_.\\-]*[0-9+/=]";"i")
        or test("(ATATT|ATCTT|ghp_|github_pat_|gho_|ghs_|xox[baprs]-|xapp-|AIza|AKIA|glpat-)")
        # sk- 는 낱말 안(ta"sk-"create, ri"sk-"based)에 흔해 앞이 영숫자가 아닐 때만 본다.
        or test("(^|[^A-Za-z0-9])sk-")
        or test("://[^/@[:space:]]+:[^/@[:space:]]+@")
        or test("(?=[A-Za-z0-9]{24,})[A-Za-z]*[0-9][A-Za-z0-9]*")
        or test("(?=[A-Za-z0-9+/=]{40,})[A-Za-z+/=]*[0-9]")
        or test("[0-9a-f]{32,}";"i")
        or test("[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}";"i");
    exempt
    | [paths(scalars) as $p
       | {p:($p|join(".")), v:(getpath($p)|tostring), k:($p|map(tostring)|join(" "))}]
    | map(select((.v | suspicious) or (.k | suspicious)))
    | .[].p' "$1" 2>/dev/null
}

for NAME in $SYNC_PROFILES; do
  F="$PROFILE_DIR/$NAME"
  # .sync 가 true 가 아니면(없음·false·파일 없음) 건너뛴다 — 동기화는 파일마다 옵트인이다.
  # 끄는 것은 회수가 아니다: 전에 올린 파일은 gist 에 남아 다른 PC 의 /download 가 계속 복원한다.
  # 남아 있으면 알리기만 한다 — 삭제는 외부 쓰기라 사용자가 직접 실행한다.
  if ! { [ -f "$F" ] && [ "$(jq -r '.sync == true' "$F" 2>/dev/null | tr -d '\r')" = "true" ]; }; then
    if gh gist view "$GIST_ID" --filename "$NAME" >/dev/null 2>&1; then
      echo "⚠️ $NAME: 로컬 .sync 가 꺼져 있지만 gist 에 이전 업로드가 남아 있다." >&2
      echo "   회수하려면 사용자가 직접: gh gist edit $GIST_ID --remove $NAME" >&2
      echo "   (gist 리비전 이력에는 남는다 — 완전 삭제는 gist 자체 삭제뿐)" >&2
    fi
    continue
  fi
  # 스캔한 바이트와 올리는 바이트를 같게 한다 — 원본을 올리면 중복 키({"k":"<토큰>","k":"<정상>"})가
  # jq 파싱에서 마지막 값만 남아 스캔을 비켜 간 채 원본 그대로 나간다. 정규화 사본을 스캔하고 그 사본을 올린다.
  # 사본 파일 이름은 gist 파일 이름과 같아야 한다(--add 는 basename 을 파일 이름으로 쓴다). CR 은 뗀다.
  NT="$(mktemp -d)"; N="$NT/$NAME"
  # 스캔이 실패하면(jq 미설치·JSON 파손) "깨끗함"이 아니라 중단이다 — fail-closed.
  # rc 를 버리고 출력이 비었는지만 보면, 스캔이 안 돈 파일이 그대로 올라간다.
  if ! jq -S . "$F" > "$N.raw" 2>/dev/null || ! tr -d '\r' < "$N.raw" > "$N" \
     || ! HITS="$(wl_scan "$N" "$NAME")"; then
    echo "⚠️ $NAME 업로드 중단 — 민감정보 스캔 실패(jq 미설치·JSON 파손 등)." >&2
    echo "   스캔이 돌지 않은 파일은 올리지 않는다." >&2
  elif [ -n "$HITS" ]; then
    echo "⚠️ $NAME 업로드 중단 — 민감 의심 값 경로(값은 표시하지 않는다):" >&2
    # "$HITS" 를 인용하지 않으면 경로 안의 * ? [ 가 글로브로 전개돼 진짜 히트가 묻힌다.
    printf '%s\n' "$HITS" | sed 's/^/  - /' >&2
  else
    gh gist edit "$GIST_ID" --filename "$NAME" --add "$N"

    # 6) 업로드 검증: gist의 형제 파일이 스캔한 사본과 값 기준으로 동일한지
    diff <(gh gist view "$GIST_ID" --filename "$NAME" | jq -S .) \
         <(jq -S . "$N") >/dev/null \
      && echo "$NAME 프로필 업로드 검증 OK" \
      || echo "⚠️ $NAME 프로필 불일치 — 재시도"
  fi
  rm -rf "$NT"
done

rm -f /tmp/mccm.json /tmp/mccm2.json /tmp/cmd.lf
```

### 9. 완료 보고

- 추출된 마켓플레이스 수
- 추출된 플러그인 수
- 추출된 MCP 서버 수
- 추출된 hook 수
- 추출된 설정 항목 수
- CLAUDE.md 포함 여부 (줄 수) 및 검증 결과
- 프로필(`worklog.json`·`jira-task.json`) 파일별 업로드 여부 (`.sync` 꺼짐으로 건너뜀 / 스캔 중단 / 업로드·검증 OK)
- 삭제된 Gist 전용 항목 (있는 경우)
