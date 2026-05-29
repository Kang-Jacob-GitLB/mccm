---
name: today
description: Claude Code 세션 트랜스크립트(~/.claude/projects)에서 오늘(또는 지정일) 작업 내역을 읽어 시간대·프로젝트·커밋·prompt 주제로 요약하고 Jira worklog 입력 후보 표를 생성. 선택적으로 jira CLI 로 워크로그를 dry-run 미리보기/실제 입력까지 수행. gws(권장, npm `@googleworkspace/cli`) 연동 시 Google Calendar 회의 일정을 병합해 회의 시간도 워크로그로 인지. hook 불필요. "오늘 워크로그", "오늘 한 일 정리", "워크로그 요약", "worklog today", "어제 워크로그", "지난주 워크로그", "jira 워크로그 입력", "워크로그 등록 dry-run" 등에 사용.
---

# 오늘 워크로그 요약

## 목적
Claude Code 가 **세션마다 자동으로 남기는 트랜스크립트**(`~/.claude/projects/<cwd-slug>/<session-id>.jsonl`)를 읽어 하루치 작업을 정리한다. 별도 hook 설치가 **필요 없다** — Claude Code 가 항상 기록하는 대화 로그를 직접 파싱한다. 최종 출력은 사람이 Jira worklog 에 그대로 옮길 수 있는 표를 포함한다.

> 과거 버전은 `UserPromptSubmit`/`PostToolUse`/`SessionStart/Stop` hook 이 쌓은 `worklog-*.jsonl` 을 읽었으나, 동일 정보가 Claude Code 트랜스크립트에 이미 들어있어 hook 의존을 제거했다. 새 머신에서도 셋업 0 으로 바로 동작한다.

## 요구사항 (사전 준비)
이 스킬의 **핵심 요약 기능**(절차 1~4: 활동 수집·타임라인·주제 요약)은 Claude Code 트랜스크립트만 읽으므로 **추가 설치가 전혀 필요 없다**. 아래 도구는 **확장 기능**에만 필요하다.

| 도구 | 등급 | 용도 | 미설치 시 동작 |
|---|---|---|---|
| **jira CLI** (`jira`) | **필수** (워크로그 입력 시) | 절차 5 — Jira 워크로그 dry-run/실제 입력 | 아래 설치 가이드 안내 후 **입력 단계 중단** (요약은 정상 출력) |
| **gws** (npm `@googleworkspace/cli`) | **권장** | 절차 2-2 — Google Calendar 회의 일정 병합 (회의 시간을 워크로그로 인지·겹침회피) | 설치 **권장 안내**만 하고 **캘린더 없이 진행** (작업 트랜스크립트 기반으로만 요약) |

> 원칙: 스킬 진입 시 필요한 CLI 가 없으면 **묻기 전에 먼저 `command -v` 로 존재 확인** → 없으면 등급에 맞게 (필수=중단+가이드 / 권장=안내 후 스킵) 처리. 토큰·비밀번호는 출력·스킬에 **절대 하드코딩 금지** (env/config 참조만).

### jira CLI (필수 — 워크로그 입력용)
```bash
command -v jira >/dev/null || echo "jira CLI 미설치"
```
**설치** (ankitpokhrel/jira-cli):
- Windows: `scoop install jira-cli` 또는 [릴리스](https://github.com/ankitpokhrel/jira-cli/releases)에서 `jira_*_windows_x86_64.zip` 받아 PATH 에 추가
- macOS: `brew install ankitpokhrel/jira-cli/jira-cli`
- Go: `go install github.com/ankitpokhrel/jira-cli/cmd/jira@latest`

**환경 구성**:
1. Atlassian API 토큰 발급: <https://id.atlassian.com/manage-profile/security/api-tokens>
2. 토큰을 env 로 노출 (PowerShell: `$env:JIRA_API_TOKEN="..."`, bash: `export JIRA_API_TOKEN=...`). 영구 적용은 셸 프로파일/시스템 환경변수에 등록.
3. `jira init` → 서버 URL(예: `https://your-org.atlassian.net`) + 로그인 이메일 입력. config 는 `~/.config/.jira/.config.yml` 에 저장.
4. 검증: `jira me` 가 본인 계정을 출력하면 정상. (절차 5.0 의 사전 확인과 동일.)

### gws (권장 — 회의 일정 병합용)
```bash
command -v gws >/dev/null || echo "gws 미설치 — 회의 병합 기능은 건너뜀(권장 설치)"
```
**설치** (npm 패키지 `@googleworkspace/cli`, Node 18+):
- `npm install -g @googleworkspace/cli`  — 바이너리 이름은 `gws`
- 검증: `gws --version`

**환경 구성** (Google OAuth):
1. [Google Cloud Console](https://console.cloud.google.com/)에서 프로젝트 생성 → **Google Calendar API** 사용 설정.
2. OAuth 클라이언트 ID(애플리케이션 유형: **데스크톱 앱**) 생성 → `client_secret.json` 다운로드 후 `~/.config/gws/client_secret.json` 에 둔다. (또는 `gws auth setup` 으로 GCP 프로젝트+OAuth 클라이언트를 대화식 구성 — `gcloud` 필요.)
3. 인증(브라우저 OAuth 동의): `gws auth login`  — 토큰은 OS 키링(기본) 또는 `~/.config/gws/` 에 저장.
4. 검증: `gws auth status` 가 JSON 으로 `auth_method`·`credential_source`·`client_config_exists:true` 를 출력하면 정상. 자격증명/토큰이 없으면 auth 에러(exit 2).
5. env 대안: `GOOGLE_WORKSPACE_CLI_TOKEN`(미리 받은 액세스 토큰, 최우선)·`GOOGLE_WORKSPACE_CLI_CREDENTIALS_FILE`·`GOOGLE_WORKSPACE_CLI_CONFIG_DIR`(기본 `~/.config/gws`)·`GOOGLE_WORKSPACE_CLI_KEYRING_BACKEND`(`keyring` 기본 / `file`).

> ⚠ `gws` 는 stdout 에 JSON 을, stderr 에 `Using keyring backend: keyring` 같은 진단 라인을 낸다 → JSON 파싱 전 반드시 `2>/dev/null` 로 stderr 를 분리한다.
> 참고: 과거 버전은 Python 패키지 `gws-cli`(`pip install gws-cli`, `gws-cli auth`)를 썼다. npm `gws`(`@googleworkspace/cli`)로 전환했으니 `gws-cli` 만 설치돼 있다면 `npm install -g @googleworkspace/cli` 로 설치한다.

## 주 용도: 퇴근 전 일일 루틴
이 스킬의 1차 목적은 **매일 퇴근 전 1회 호출로 Jira 워크로그 입력을 반자동화**하는 것이다. 표준 흐름:

1. 절차 1~4 수행 — 오늘 활동 수집·분석·주제 그룹화.
2. **하루 타임라인 시각화**(30분 슬롯, `timeline.sh`) + 요약 출력.
3. **dry-run 가안 제시** (절차 5) — 내 Jira 이슈를 조회해 오늘 작업과 **자동 추정 매핑**하고, 등록될 `jira issue worklog add` 명령을 워크로그 **가안**으로 보여준다. 시간·시작시각 모두 **30분 그리드 반올림**(시간은 0<최소 30m), **같은 날 기존 워크로그 + 점심시간(기본 12:00–13:00)을 피해 시작시각 자동 배치**. 브랜치에 키가 없으므로 추정 + 사용자 검토가 핵심.
4. 사용자가 가안을 검토·수정(틀린 이슈 매핑 교정)하고 확인하면 `--apply` 로 실제 입력, OK/SKIP/FAIL 보고.

자동화 범위는 **수동 호출 + 확인 후 apply** (cron 무인 입력 아님). "미리보기"만 원하면 3번(추정 가안 dry-run)에서 멈춘다.

## 데이터 소스 (Claude Code 트랜스크립트)
Claude Code 는 모든 세션을 다음 위치에 JSONL 로 기록한다 — 이게 이 스킬의 **유일한 입력**이다.

| OS | 트랜스크립트 루트 | 비고 |
|---|---|---|
| **Linux / WSL** | `~/.claude/projects/<cwd-slug>/<session-id>.jsonl` | cwd 경로별 디렉토리(워크트리 포함) |
| **macOS** | `~/.claude/projects/...` | 동일 |
| **Windows** | `C:\Users\<user>\.claude\projects\...` | WSL 에선 `/mnt/c/Users/<user>/.claude/projects/` 로, Git Bash/MSYS 에선 `//wsl.localhost/<distro>/home/<user>/.claude/projects` 로 상호 접근 |

- **WSL 에서 실행하면 자동으로 양쪽**(WSL `~/.claude/projects` + Windows `/mnt/c/Users/*/.claude/projects`)을 읽어 머신 병합한다. env 는 경로로 태깅(`wsl`/`windows`/`macos`/`linux`).
- **Windows(Git Bash/MSYS) 에서 실행해도 자동으로 양쪽**을 읽는다 — `wsl.exe -l -q` 로 설치된 배포판을 조회해 각 배포판의 `//wsl.localhost/<distro>/home/*/.claude/projects` 도 함께 스캔한다. `wsl.exe` 가 없거나 배포판이 없으면 조용히 Windows 단독으로 진행.
- 트랜스크립트 user 라인엔 `timestamp`(UTC ISO)·`cwd`·`gitBranch`·`sessionId`·`message`(prompt)·`isSidechain` 등이 있어 워크로그에 필요한 정보가 모두 들어있다.
- 수집·정규화는 `collect.sh` 가 담당한다. 출력은 과거 hook JSONL 과 **동일 스키마**라 `timeline.sh` 와 하위 분석은 그대로 재사용된다:
  ```json
  {"ts":"ISO8601(UTC)","env":"wsl|windows|...","event":"prompt|commit|session_start|session_stop","session_id":"...","cwd":"...","branch":"...","prompt":"...","sha":"...","subject":"...","epoch":1716...}
  ```

### 추출 규칙 (collect.sh 내장)
- **prompt** = 사용자가 실제로 입력한 텍스트. 다음은 제외: tool_result, `<task-notification>`, `<local-command-*>`, 서브에이전트 입력(`isSidechain==true`), `"[Request interrupted...]"`. 슬래시 명령은 `<command-name>`+`<command-args>` 로 `"/cmd args"` 형태로 복원해 포함.
- **commit** = `git commit` 을 실행한 **Bash tool_use 의 결과**에 찍힌 `"[branch sha] subject"` 만 인정한다(= `git log`/`show`/`rebase` 출력에 섞인 동일 패턴은 배제). `sha` 로 dedup, 최초 시각 유지.
  - ⚠ **로컬 `git commit` 만** 잡힌다. **GitHub 측 squash/rebase 머지**로 생성된 main 커밋(예: PR 머지 결과 SHA)은 로컬 commit 이 아니라 **누락될 수 있다**(PR 로 확인). 반대로 폐기성 로컬 커밋(`feat: test` 등)도 실제 커밋이면 잡힌다.
- **session_start / session_stop** = 세션파일별 그 날짜 라인의 min/max 타임스탬프(활동창 근사). hook 시절의 명시적 이벤트 대체.

## 절차

### 1. 대상 날짜 결정
- 기본: 오늘 (KST). 사용자가 "어제", "5/24", "지난주 월요일" 등 지정하면 그에 맞춰 변환해 `collect.sh` 인자로 넘긴다.
- 출력 시 KST (`+09:00`) 기준으로 표기. `epoch` 는 raw UTC 이므로 **2-1 시각 변환 규칙**을 따른다.

### 2. 라인 수집
```bash
# 이 스킬 디렉토리 자동 탐색 — 플러그인 캐시/로컬 스킬 어디에 설치됐든 동작.
SKILL_DIR="$(dirname "$(find "$HOME/.claude/plugins/cache" "$HOME/.claude/skills" \
  -name collect.sh -path '*/skills/today/collect.sh' 2>/dev/null | sort -r | head -1)")"
DATE="2026-05-26"                      # 대상일(KST). 생략하면 오늘.
"$SKILL_DIR/collect.sh" "$DATE" > today.jsonl
#  - 자동으로 ~/.claude/projects (+ WSL 이면 Windows 측) 전 프로젝트를 훑어
#    그 날짜(KST) 라인만 정규화해 epoch 오름차순으로 낸다.
#  - 옵션: --tz <IANA>(기본 Asia/Seoul), --root <DIR>(루트 추가, 반복 가능)
```
이후 모든 분석/시각화는 `today.jsonl` 만 소비한다. `timeline.sh`·`jira_worklog.sh` 도 같은 `$SKILL_DIR` 에 있다.

### 2-1. 시각 변환 규칙 (⚠ 트랜스크립트는 UTC — KST 변환은 단 한 번)
**대전제: 트랜스크립트의 모든 시각은 UTC 다.** `collect.sh` 의 `ts` 는 UTC ISO(끝에 `Z`), `epoch` 은 raw UTC 초다. 화면 표기는 KST(`+09:00`)이므로 **UTC→KST 변환을 정확히 한 번만** 적용한다. 안 하면 9시간 뒤(UTC 그대로), 두 번 하면 9시간 앞으로 어긋난다.
(실제 발생 ①: 오전 09:53 작업이 저녁 18:53 으로 — +9 한 값을 awk strftime 에 또 넘겨 +9 재적용. ②: 오전 09:33 작업이 00:33 으로 — `TZ=Asia/Seoul` 가 안 먹혀 UTC 그대로 표기, 아래 MSYS 함정.)

> ✅ **스크립트는 이미 자동 처리한다.** `collect.sh`·`timeline.sh`·`jira_worklog.sh` 는 공통 `_tz.sh` 를 source 해 환경을 런타임 감지한다 — TZ 가 먹으면(Linux/WSL/macOS) `export TZ`, 안 먹으면(Windows Git Bash/MSYS) 오프셋(+9h)을 직접 더해 환산한다(`tzdata 부재 환경 감지` INFO 1회 출력). 그래서 **이 세 스크립트만 쓰면 시각은 항상 올바른 로컬(KST)** 이다. 아래 진단/변환 가이드는 **`jq`/`awk` 로 epoch 를 직접 다룰 때만** 적용한다.

#### 🚫 가장 흔한 함정 — Windows Git Bash/MSYS 에서 `TZ=Asia/Seoul` 이 조용히 UTC 로 폴백
MSYS/Git Bash 에는 `Asia/Seoul` zoneinfo 가 없을 수 있어 **`export TZ=Asia/Seoul` 이 해석 실패 → 경고 없이 UTC 로 떨어진다.** 그러면 `awk strftime`/`date` 가 UTC 를 그대로 찍고, "KST" 라벨만 붙어 **모든 시각이 9시간 뒤로** 표기된다.
```bash
# 진단: 두 값이 같으면 TZ=Asia/Seoul 이 안 먹는 환경(=UTC 폴백). 다르면 정상.
[ "$(TZ=Asia/Seoul date +%H)" = "$(TZ=UTC date +%H)" ] && echo "⚠ TZ 미해석(UTC 폴백) — 아래 안전 변환 사용" || echo "TZ OK"
```

#### 변환 방법 (환경별 안전 선택)
- **A. 시스템 로컬이 이미 KST 인 경우(권장)**: `TZ` 를 **오버라이드하지 말고** 시스템 로컬 `date -d @<epoch>` 를 쓴다. KST 머신이면 이게 자동으로 KST 다. awk 의 `strftime` 도 TZ 미설정이면 시스템 로컬을 따른다.
- **B. TZ=Asia/Seoul 이 실제로 먹는 환경(Linux/WSL/macOS)**: `export TZ=Asia/Seoul` 후 `awk strftime` — 산술 +9 를 직접 쓰지 않는다.
- **C. KST 가 아닌 머신에서 KST 를 강제해야 하는데 TZ 가 안 먹는 경우(MSYS 등)**: **딱 한 번** `epoch + 32400`(=9h) 한 값을 `TZ=UTC` strftime 으로 찍는다(이중적용 금지 — 이때만 의도적 1회).
- 🚫 금지: TZ 가 먹는데도 `epoch + 9*3600` 을 또 더하기 / TZ=Asia/Seoul 이라 믿고 검증 없이 strftime 하기.

출력 표준 (A안 — 시스템 로컬 KST, TZ 오버라이드 없음):
```bash
#  ⚠ prompt/subject 의 개행은 awk -F'\t' 레코드를 쪼갠다 → jq 에서 gsub 로 한 줄 평탄화.
jq -r 'select(.event=="prompt" or .event=="commit")
       | "\(.epoch)\t\(.event)\t\((.subject // .prompt // "") | gsub("[ \t\n\r]+"; " "))"' today.jsonl \
  | sort -n \
  | awk -F'\t' '$1 !~ /^[0-9]+$/ { next }   # 방어: epoch 은 정수만 — 비정상 값은 셸로 안 보냄
                { cmd="date -d @"$1" +%H:%M:%S"; cmd|getline t; close(cmd); printf "%s  %-8s %s\n", t, $2, $3 }'
#  (B안이면 맨 앞에 export TZ=Asia/Seoul 후 awk strftime("%H:%M:%S",$1) 사용 가능)
```
**검증(필수)**: 그날 직접 만든 커밋이 있으면 워크로그 시각을 `git log -1 --date=iso` 의 author 시각과 대조한다 — 9시간(또는 12시간) 어긋나면 위 변환을 잘못 고른 것이다. 없으면 "첫 시각이 상식적 업무시간대(오전 9~10시)인가"로 1차 점검.

### 2-2. (선택·권장) 회의 일정 병합 — gws (npm `@googleworkspace/cli`)
`gws` 가 설치·인증돼 있으면 그날 Google Calendar 회의를 가져와 타임라인·워크로그 후보에 합친다. **없으면 이 단계를 조용히 건너뛰고** 트랜스크립트 기반으로만 진행한다(권장 안내 1회).

```bash
command -v gws >/dev/null || { echo "gws 미설치 → 회의 병합 생략 (요구사항 섹션의 gws 가이드 참고, 권장)"; }
# ⚠ DATE 는 사용자 입력에서 유도되므로 셸 명령에 끼우기 전 형식을 강제한다(인젝션 차단).
case "$DATE" in
  [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) ;;            # YYYY-MM-DD 만 허용
  *) echo "잘못된 날짜 형식: $DATE" >&2; exit 2 ;;
esac
# --params JSON 은 값 splicing 대신 jq --arg 로 안전하게 조립한다.
PARAMS=$(jq -nc --arg d "$DATE" '{
  calendarId:"primary",
  timeMin:($d+"T00:00:00+09:00"),
  timeMax:($d+"T23:59:59+09:00"),
  singleEvents:true, orderBy:"startTime", maxResults:50}')
# 그날 회의 조회 (KST). ⚠ stderr(keyring 진단)는 2>/dev/null 로 버리고 stdout(JSON)만 파싱.
gws calendar events list --format json --params "$PARAMS" 2>/dev/null > cal.json
# 인증 안돼 있으면 exit 2(auth 에러) + 빈/에러 출력 → 회의 병합 생략하고 진행.
jq -r '.items[]?
  | select((.start.dateTime // null) != null)        # 종일(all-day) 제외
  | select([.attendees[]? | select(.self==true) | .responseStatus] | (index("declined") | not))  # 거절 제외
  | "\(.start.dateTime)\t\(.end.dateTime)\t\(.summary // "(제목없음)")"' cal.json
```
- ⚠ npm `gws` 는 stdout 에 **JSON**(`--format json`), stderr 에 `Using keyring backend: keyring` 진단 라인을 낸다 → **반드시 `2>/dev/null`** 로 분리해야 jq 가 파싱한다. (구 Python `gws-cli` 의 `calendar list` 표 출력이 아니다.)
- 각 이벤트의 **시작·종료 시각(`start.dateTime`/`end.dateTime`)·제목(`summary`)·본인 참석상태(`attendees[].self==true` 의 `responseStatus`)** 를 읽어 정규화한다.
- 읽어낸 각 회의를 `collect.sh` 와 **동일 스키마**의 라인으로 정규화해 `today.jsonl` 에 합친다 (event 종류는 `meeting`):
  ```json
  {"ts":"ISO8601(UTC)","env":"gcal","event":"meeting","subject":"<회의 제목>","epoch":<시작 UTC초>,"end_epoch":<종료 UTC초>}
  ```
- 종일(all-day)·참석 거절(RSVP=`declined`) 이벤트는 제외. 본인이 주최/수락한 회의만 활동으로 인정.
- 병합 후 효과:
  - **타임라인**: 회의 구간을 별도 마커(예: `▣`)로 표기해 코딩 작업과 구분.
  - **활동 시간대**: 회의 구간도 활동으로 합산(트랜스크립트 공백 시간이 회의로 설명됨).
  - **워크로그 후보**: 회의 자체를 1건의 후보(예: "회의: <제목> 1h")로 제안. 절차 5 의 **겹침회피**에서 회의 구간을 "이미 찬 구간"으로 넘겨, 코딩 워크로그 시작시각이 회의와 안 겹치게 자동 배치(점심시간 회피와 동일 메커니즘).

### 3. 섹션별 분석
모은 라인을 다음 묶음으로 분류:
- **활동 시간대**: `session_start`/`session_stop`(세션파일별 min/max) 구간의 합집합. 동시 진행 세션은 겹치는 구간을 한 번만 카운트. (절차 2-2 로 병합한 `event=="meeting"` 구간도 활동에 포함.)
- **프로젝트별 통계**: `cwd` basename 으로 그룹(워크트리는 별도 slug 로 보일 수 있음). 각 그룹의 prompt 수, commit 수, 첫/마지막 활동 시각.
- **커밋 목록**: `event=="commit"` 라인. SHA(short) + branch + subject 한 줄.
- **prompt 주제 요약**: Claude 가 prompt 본문들을 읽고 5-10 줄로 의미 단위 요약(질문/검토/디버깅/문서작성/etc.). 잡담/오타/한 글자 입력·슬래시 명령 노이즈는 제외.
- **하루 타임라인(30분 슬롯)**: `timeline.sh` 로 슬롯별 밀도 막대(`█`)와 커밋 마커(`✦`)를 결정적으로 렌더한 뒤, Claude 가 각 행 오른쪽에 그 시간대 **주제 라벨 한 줄**을 채운다.
  ```bash
  cat today.jsonl | "$SKILL_DIR/timeline.sh"
  ```

### 4. 작업 주제 그룹화
워크로그 입력 단위가 될 **주제 그룹**을 만든다 (이슈 키 결정은 절차 5 에서).
- prompt 주제 + 커밋 subject + 브랜치를 의미 단위로 묶는다. 보통 하루 1~4 그룹.
- 그룹마다: 활동 시간 합산(`Nh Mm`), 첫 활동 시각(STARTED), **시간 비례 멀티라인 코멘트**(소요시간만큼 작업 항목을 라인별로 분해, 시간당 ~1줄 기준).
- 브랜치에 `[A-Z]+-[0-9]+` 가 있으면 그 키를 절차 5 추정의 **최우선 힌트**로 들고 간다. (이 리포의 `feat/...` 브랜치엔 키가 없으므로 보통 비어 있음 → 절차 5 가 조회·추정으로 채움.)

### 5. Jira 워크로그 입력 (옵션 — `jira` CLI 연동)
**기본은 요약 출력까지만.** 입력/등록/dry-run 을 요청할 때만 진입.
입력 단위 = **태스크(이슈) 1건 = 워크로그 1건 = 소요시간(h) + 시간 비례 멀티라인 코멘트**.

> **코멘트 작성 규칙(중요)**: 코멘트는 한 줄로 압축하지 말고 **소요시간에 비례해 여러 라인(작업 항목별 불릿)으로** 작성한다. 기준은 **시간당 ~1줄**(예: 3h30m → 약 4줄, 1h30m → 약 2줄). 멀티라인이라 `jira_worklog.sh`(TSV 한 줄=1 레코드)로는 표현이 안 되므로, **실제 입력은 스크립트를 우회해** `jira issue worklog add <KEY> <TIME> --started '<KST>' --timezone 'Asia/Seoul' --no-input --comment $'1줄\n2줄\n…'` 로 직접 호출한다(STARTED·30분 반올림·겹침회피는 5.3 dry-run 으로 산출한 값을 그대로 사용). dry-run 가안 표·간트의 코멘트 칸에도 라인 수를 함께 표기한다.

> **dry-run 의 목적은 두 가지**: (a) 등록될 `jira issue worklog add` 명령 미리보기, (b) **내 Jira 이슈 중 오늘 작업과 맞을 이슈를 추정해 워크로그 가안(초안)을 제시** → 사용자가 검토·수정 후 확정. 브랜치에 키가 없으므로 (b) 가 핵심이다 — 매번 빈칸을 묻지 말고 **먼저 추정안을 보여주고** 사용자는 고치기만 한다.

#### 5.0 사전: jira config 확인
`jira me` 가 동작해야 한다(config `~/.config/.jira/.config.yml`). 실패하면 최초 `jira init`(서버 URL + 로그인) 안내 후 중단. 겹침회피의 워크로그 조회(REST)와 `--apply` 는 config 의 `server`·`login` + `JIRA_API_TOKEN` env 를 쓴다. **토큰/비밀번호는 스킬·출력에 절대 하드코딩 금지** (기존 env/config 참조만).

#### 5.1 내 이슈 후보 조회
오늘 작업과 매칭할 후보를 가져온다 (담당 + 최근 접근). **워크로그 대상은 활성(미완료) 이슈가 원칙**이므로 미완료를 먼저, 완료는 참고용으로 분리해 가져온다:
```bash
ME=$(jira me)
# ① 워크로그 1순위 후보 — 내 담당 '미완료'(statusCategory != Done)
jira issue list -a "$ME" -q "statusCategory != Done" --order-by updated --reverse \
  --plain --no-headers --columns KEY,STATUS,SUMMARY --paginate 0:20
# ② 최근 접근 이슈로 보강(상태 무관)
jira issue list --history \
  --plain --no-headers --columns KEY,STATUS,SUMMARY --paginate 0:20
# ③ (참고용) 완료 이슈 — 매칭 근거 확인에만 쓰고 워크로그 대상으로는 기본 제외(5.2 규칙)
jira issue list -a "$ME" -q "statusCategory = Done" --order-by updated --reverse \
  --plain --no-headers --columns KEY,STATUS,SUMMARY --paginate 0:20
```
> `STATUS` 컬럼을 반드시 함께 받아 각 후보의 완료 여부를 안다(5.2 에서 완료 티켓을 거른다).

#### 5.2 추정 매핑 (가안 생성)
각 주제 그룹(절차 4)을 조회된 이슈와 매칭한다 — 주제/커밋/브랜치 **키워드 ↔ 이슈 SUMMARY** 유사도.
- 추정마다 **근거**(어떤 키워드가 어느 이슈와 맞았는지) + **확신도**(높음/낮음)를 붙인다.
- 브랜치 `[A-Z]+-[0-9]+` 키가 있으면 최우선(확신 높음).
- 애매하면 가안엔 확신 높은 1개를 넣되 `(추정)` 표시 + 후보 병기. 도저히 못 정하면 KEY=`-`(SKIP).
- 🚫 **완료(Done/Closed/해결됨) 상태 이슈에는 워크로그를 달지 않는다.** 이미 종료된 티켓에 시간 기록은 부적절하다(재오픈 유발·집계 왜곡).
  - 키워드가 완료 티켓과 가장 잘 맞더라도, **활성(미완료) 이슈 중 차선 후보를 우선 채택**한다.
  - 활성 후보가 없으면 그 행은 `-`(SKIP) 로 두고 **`완료 티켓 OOО-NN 와만 매칭됨 — 확인요망`** 을 근거에 명시한다. (그 작업이 실제로 종료 티켓의 후속이면 사용자가 티켓 재오픈/신규 생성/다른 활성 티켓 지정 중 택한다.)
  - 가안 표의 `확신` 칸에 완료 티켓이면 반드시 `완료(워크로그 부적절)` 를 표기해 사용자가 한눈에 알게 한다.

추정 매핑 표를 **먼저** 보여준다 (가안):
| 주제 그룹 | 추정 이슈 | 근거 | 확신 | 시간 | 코멘트(시간 비례 라인, ~1줄/h) |
|---|---|---|---|---|---|
| cal 실패마커 6/2/1 | PROJ-42 | SUMMARY "Calibration…" ↔ 작업 키워드 | 높음 | 1h 30m | (2줄) cal 실패마커 6/2/1 게이트 전환 / cal 콘솔 명령 추가 |
| FactoryReset 롤백 | PROJ-50? | 약한 매칭 | 낮음(확인요망) | 30m | (1줄) FactoryReset 4/1/1→4/4/1 롤백 |

> 위 키는 **예시**다. 실제로는 5.1 조회 결과로 채운다.

#### 5.3 dry-run 가안 미리보기
추정 매핑을 TSV 로 만들어 `jira_worklog.sh` dry-run (30분 반올림·STARTED 포함):
```bash
SH="$SKILL_DIR/jira_worklog.sh"   # 절차 2 에서 구한 $SKILL_DIR
# 추정 매핑 → TSV (KEY \t TIME \t STARTED \t COMMENT). 확신 없으면 "-".
printf '%s\n' \
  $'PROJ-42\t1h 36m\t2026-05-27 09:53:00\tcal 실패마커 6/2/1 게이트 전환 + cal 콘솔 명령' \
  $'-\t30m\t2026-05-27 10:27:00\tFactoryReset 4/1/1→4/4/1 롤백 (추정 실패 — 확인요망)' \
  | "$SH"            # dry-run: 추정 가안 명령 미리보기
```
TSV 컬럼: `KEY`(추정 이슈, 미정은 `-`) · `TIME_SPENT`(원본 그대로 넘기면 스크립트가 30분 nearest 반올림) · `STARTED`(첫 활동 KST `YYYY-MM-DD HH:MM:00`) · `COMMENT`(dry-run 표시용 1줄 요약 — 실제 등록은 아래 멀티라인 규칙을 따른다).
옵션: `--apply` · `--tz`(기본 Asia/Seoul) · `--project` · `--round`(기본 30) · `--overlap-ok`(겹침회피 끔) · `--lunch <범위>`(기본 `12:00-13:00`, `none`=끔).

> **멀티라인 코멘트 = 기본값**(5 입력 단위의 코멘트 규칙). `jira_worklog.sh` 는 TSV 한 줄=1 레코드라 멀티라인을 표현 못 하므로, **dry-run 으로는 STARTED·30분 반올림·겹침회피 값만 산출**하고(COMMENT 는 1줄 요약), **`--apply` 대신 그 산출값으로 `jira issue worklog add <KEY> <TIME> --started '<KST>' --timezone 'Asia/Seoul' --no-input --comment $'1줄\n2줄\n…'` 를 이슈마다 직접 호출**한다. 라인 수는 소요시간당 ~1줄(예: 2h30m → 3줄). 사용자 확인 후 호출하며, 확인 없는 입력은 금지.

**시작시각 처리** (스크립트가 자동):
- `TIME_SPENT` 와 마찬가지로 `STARTED` 도 30분 그리드로 nearest 반올림 (예: 09:53 → 10:00).
- **겹침회피(기본 켬)**: 같은 날 내가 이미 단 워크로그 구간 **+ 점심시간(기본 12:00–13:00) + (절차 2-2 병합 시) 회의 구간** 을 피해, 새 워크로그가 겹치면 빈 슬롯(다음 그리드)으로 STARTED 를 밀어낸다. 연속 입력 행끼리도 누적해 안 겹치게 한다. `--overlap-ok` 로 겹침회피를, `--lunch none` 으로 점심회피를 끈다.
  - jira-cli 에 worklog 조회가 없어 워크로그 조회는 **REST API** 사용: config 의 `server`·`login` + `JIRA_API_TOKEN` env. ⚠ 구 `/rest/api/3/search` 는 **삭제(HTTP 410)** — 이슈 검색은 `jira issue list --jql` (CLI) 로, 각 이슈 워크로그는 `GET /rest/api/3/issue/{key}/worklog` 로 조회. 자격이 없으면 회피 없이 진행.
  - 조회 범위: `worklogAuthor = currentUser() AND worklogDate = "<그 날>"` 로 내 당일 워크로그가 있는 이슈를 찾아 각 이슈의 내 워크로그 구간을 모은다.
  - 예: 오전(09:30–12:00)이 이미 차 있으면 1h30m 워크로그는 점심을 건너뛰어 13:00–14:30 으로 배치된다.

#### 5.4 사용자 검토·수정
추정 가안을 보여주고 **틀린 매핑을 사용자가 고친다**. 확신 낮음/`-` 행은 반드시 확인 — `AskUserQuestion`(5.1 후보 top + Other 직접입력)으로 키를 받거나 SKIP 유지.
- ⚠ 매핑된 이슈가 **완료 상태**인 행은 apply 전 **반드시 사용자에게 확인**한다(5.2 규칙). 사용자가 명시적으로 "그래도 그 완료 티켓에 달아라" 라고 하지 않는 한 그 행은 입력하지 않는다 — 활성 티켓 재지정 또는 SKIP 으로 처리.

#### 5.5 apply
확정된 TSV 에 `--apply` 추가해 실제 입력하고 OK/SKIP/FAIL 보고. **사용자 확인 없이 `--apply` 금지** (외부 반영 행위).

## 출력 포맷

**시각화·dry-run 은 표 대신 "간트 24h 축" 스타일로 그린다.** 코드블록(monospace) 안에서 문자만으로 렌더한다. 아래 구조를 따른다 (값은 예시 — 실제 데이터로 채움):

```
워크로그 · {YYYY-MM-DD} ({요일})                       활동 {합계} · 커밋 {N}

           0    3    6    9    12   15   18   21   24
          ┌────┬────┬────┬────┬────┬────┬────┬────┐
 코딩  ▓  │··················▓▓····························│ 09:33–10:14 · 41m
 회의  █  │································████············│ 16:00–17:00 · 1h
 점심  ▒  │························▒▒····················· │ 12:00–13:00 (회피)
          └──────────────────────────────────────────┘

 주요 작업
   ▸ {topic 1 — 1줄}
   ▸ {topic 2}

 DRY-RUN · jira worklog                       ▸ 30m grid · ⏎=apply
 ▐ WDSW2D2510-296 ▌ ████░░░░  10:00  TCC8030 카메라0대 welcome 멈춤   진행중  ✔
 ▐ WDSW2D2510-252 ▌ ████░░░░  09:30  keep_previous · 보드빌드         ⚠완료·보류
 ▐ 타운홀미팅      ▌ ████████  16:00  타운홀미팅                       이슈미정
 ▐ skip           ▌ ········  ──     {주제} ({사유})                  ∅
 ────────────────────────────────────────────────────────────────────
 등록 예정 {전체KEY}({시간}) · 보류 {완료 전체KEY} · 확인 {미정/회의}
```

렌더 규칙:
- **24h 축**: 폭 W(예: 44~48열). 각 행 막대의 시작/끝 열 = `round(hour/24*W)`. hour 는 **KST 소수시간**(절차 2-1 의 올바른 변환값; ⚠ UTC 로 그리지 말 것). 막대 문자: 코딩 `▓` · 회의 `█` · 점심/회피 `▒`, 빈칸 `·`.
- 축 눈금(0·3·6·…·24)과 막대 영역의 좌측 경계 `│` 를 세로로 맞춘다.
- **활동 시간대**(상단 우측 요약)와 각 막대 우측의 `HH:MM–HH:MM · 길이` 가 활동 시간 정보를 겸한다(별도 표 불필요).
- **DRY-RUN 행**: `▐ KEY ▌` 배지 + `30m grid` 채움막대(`█`=소요, `░`=잔여 슬롯) + `STARTED` + 코멘트(1줄 요약 + `(N줄)` 라인 수 표기) + 상태 꼬리표. 실제 등록 코멘트는 소요시간 비례 멀티라인(시간당 ~1줄)이며, apply 직전 각 이슈의 전체 멀티라인 코멘트를 펼쳐 사용자에게 확인받는다.
  - ⚠ 배지의 `KEY` 는 **전체 이슈 키**(예: `WDSW2D2510-296`)로 표기한다 — 숫자만(`296`) 줄이지 않는다(잘못된 이슈 입력 방지). 요약줄·근거 표기도 전체 키 사용.
  - 상태 꼬리표: `진행중 ✔`(활성·등록예정) · `⚠완료·보류`(완료 티켓 — 5.2 규칙, 입력 안 함) · `이슈미정`(회의/매칭없음) · `∅`(SKIP).
  - 완료(`⚠`) 행과 `이슈미정`/`∅` 행은 **apply 대상에서 제외**. 마지막 요약줄에 등록예정/보류/확인 건수를 적는다.
- 커밋 목록이 필요하면 막대 아래 `커밋` 소제목으로 `sha [branch] subject` 를 간단히 덧붙인다(선택).

> 각 DRY-RUN 행이 워크로그 1건. 이슈 키는 **절차 5.1 조회 + 5.2 추정** 결과(위 키는 예시). `⚠완료`·`이슈미정`·확신 낮음은 apply 전 반드시 사용자 확인. 시간은 30분 반올림 후 값.

## 인자 처리

사용자 입력 예:
- "오늘 워크로그" → 오늘
- "어제 워크로그" / "yesterday" → 오늘 - 1
- "5/24 워크로그" / "2026-05-24" → 해당 날짜
- "이번주 워크로그" → 월~오늘 모두 합산해 같은 포맷, 단 활동 시간대 섹션은 일자별 소계 추가
- "지난주" → 지난주 월~일
- "jira 워크로그 입력 dry-run" / "워크로그 등록 미리보기" → 절차 1~4 후 **절차 5 의 dry-run**(명령만 출력).
- "jira 워크로그 입력해" / "워크로그 등록해" / "...apply" → 절차 5 진행: **dry-run 으로 보여주고 사용자 확인 후 `--apply`**.

날짜를 못 알아들으면 사용자에게 1회 확인. 입력/등록 의도가 모호하면 dry-run 으로 처리한다(안전 기본값).

## 주의 사항
- prompt 본문이 길거나 민감 정보(토큰/비번)가 보이면 출력에 그대로 노출하지 말고 "{생략}" 처리.
- `session_id` 가 같으면 같은 Claude Code 세션. 활동 시간대 산출 시 세션 단위로 묶기.
- 트랜스크립트는 **전 프로젝트**를 포함한다(워크트리는 별도 cwd slug). 특정 프로젝트만 원하면 결과를 cwd 로 필터.
- 서브에이전트(`isSidechain`) 입력은 prompt 에서 제외된다. 슬래시 명령(`/release` 등)은 prompt 로 복원되어 포함된다.
- 커밋은 **로컬 `git commit` 만** 캡처된다 — GitHub 측 squash/rebase 머지 SHA 는 누락될 수 있다(PR 로 확인). 폐기성 로컬 커밋도 잡힐 수 있으니 요약 시 한 번 걸러낸다.
- `collect.sh` 가 한 줄도 못 내면(그 날 세션 없음/트랜스크립트 경로 부재) "해당 날짜 활동 없음"으로 안내.
