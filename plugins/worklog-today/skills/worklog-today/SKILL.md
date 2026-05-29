---
name: worklog-today
description: Claude Code 세션 트랜스크립트(~/.claude/projects)에서 오늘(또는 지정일) 작업 내역을 읽어 시간대·프로젝트·커밋·prompt 주제로 요약하고 Jira worklog 입력 후보 표를 생성. 선택적으로 jira CLI 로 워크로그를 dry-run 미리보기/실제 입력까지 수행. gws-cli(권장) 연동 시 Google Calendar 회의 일정을 병합해 회의 시간도 워크로그로 인지. hook 불필요. "오늘 워크로그", "오늘 한 일 정리", "워크로그 요약", "worklog today", "어제 워크로그", "지난주 워크로그", "jira 워크로그 입력", "워크로그 등록 dry-run" 등에 사용.
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
| **gws-cli** | **권장** | 절차 2-2 — Google Calendar 회의 일정 병합 (회의 시간을 워크로그로 인지·겹침회피) | 설치 **권장 안내**만 하고 **캘린더 없이 진행** (작업 트랜스크립트 기반으로만 요약) |

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

### gws-cli (권장 — 회의 일정 병합용)
```bash
command -v gws-cli >/dev/null || echo "gws-cli 미설치 — 회의 병합 기능은 건너뜀(권장 설치)"
```
**설치** (Python 패키지, Python 3.10+):
- `pip install gws-cli`  (또는 격리 설치 `pipx install gws-cli`)
- 검증: `gws-cli --version`

**환경 구성** (Google OAuth):
1. [Google Cloud Console](https://console.cloud.google.com/)에서 프로젝트 생성 → **Google Calendar API** 사용 설정.
2. OAuth 클라이언트 ID(애플리케이션 유형: **데스크톱 앱**) 생성 → `client_secret.json` 다운로드.
3. 자격증명 가져오기(암호화 저장): `gws-cli auth import-credentials <client_secret.json 경로>`
4. 인증(브라우저 OAuth 동의): `gws-cli auth`  — 토큰은 `~/.config/gws-cli/token.json` 에 저장.
5. 검증: `gws-cli auth status` 가 `authenticated` 이면 정상. 다계정은 `--account <이름>` 또는 `GWS_ACCOUNT` env.

> 회사가 OAuth 릴레이 서버를 운영하면 `gws-cli auth server-login` + `gws-cli config set-mode server` 로도 인증 가능.

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
  -name collect.sh -path '*worklog-today*' 2>/dev/null | head -1)")"
DATE="2026-05-26"                      # 대상일(KST). 생략하면 오늘.
"$SKILL_DIR/collect.sh" "$DATE" > today.jsonl
#  - 자동으로 ~/.claude/projects (+ WSL 이면 Windows 측) 전 프로젝트를 훑어
#    그 날짜(KST) 라인만 정규화해 epoch 오름차순으로 낸다.
#  - 옵션: --tz <IANA>(기본 Asia/Seoul), --root <DIR>(루트 추가, 반복 가능)
```
이후 모든 분석/시각화는 `today.jsonl` 만 소비한다. `timeline.sh`·`jira_worklog.sh` 도 같은 `$SKILL_DIR` 에 있다.

### 2-1. 시각 변환 규칙 (⚠ +9h 는 단 한 번)
`collect.sh` 는 `epoch`(raw UTC 초)와 `ts`(UTC ISO)를 낸다. KST 표기 시 **+9h 이중적용**을 조심한다.
(실제 발생: 오전 09:53 작업이 저녁 18:53 으로 잘못 표기됨 — +9 한 값을 awk strftime 에 또 넘겨 +9 재적용.)

- 표준(권장): jq 는 `epoch`(raw UTC)만 내보내고, `export TZ=Asia/Seoul` 상태의 `awk strftime` 으로 포맷한다 → +9 산술을 **직접 쓰지 않는다**.
- 🚫 금지: `epoch + 9*3600` 한 값을 다시 `awk`/`date` strftime 에 넘기기.

출력 표준 (raw epoch 보존 → TZ=Asia/Seoul awk):
```bash
export TZ=Asia/Seoul
#  ⚠ prompt/subject 의 개행은 awk -F'\t' 레코드를 쪼갠다 → jq 에서 gsub 로 한 줄 평탄화.
jq -r 'select(.event=="prompt" or .event=="commit")
       | "\(.epoch)\t\(.event)\t\((.subject // .prompt // "") | gsub("\\s+"; " "))"' today.jsonl \
  | sort -n | awk -F'\t' '{ printf "%s  %-8s %s\n", strftime("%H:%M:%S",$1), $2, $3 }'
```
검증: 출력 첫 시각이 상식적 업무시간대(예: 오전 9~10시)와 맞는지 확인. 12시간 어긋나면 이중변환 의심.

### 2-2. (선택·권장) 회의 일정 병합 — gws-cli
`gws-cli` 가 설치·인증돼 있으면 그날 Google Calendar 회의를 가져와 타임라인·워크로그 후보에 합친다. **없으면 이 단계를 조용히 건너뛰고** 트랜스크립트 기반으로만 진행한다(권장 안내 1회).

```bash
command -v gws-cli >/dev/null && gws-cli auth status >/dev/null 2>&1 || {
  echo "gws-cli 미설치/미인증 → 회의 병합 생략 (요구사항 섹션의 gws-cli 가이드 참고, 권장)"; }
# 그날 회의 조회 (KST). 시간 플래그는 --from/--to (ISO8601), -n 으로 개수 상향.
gws-cli calendar list --from "${DATE}T00:00:00+09:00" \
                      --to "${DATE}T23:59:59+09:00" -n 50
```
- ⚠ `gws-cli`(Python)의 `calendar list` 에는 `--format json` 옵션이 **없다**(출력은 사람이 읽는 표 형식). Claude 가 그 출력에서 각 이벤트의 **시작·종료 시각·제목·참석여부**를 읽어 정규화한다. (npm `gws calendar events list --format json` 이 설치돼 있으면 JSON 으로 받아 파싱해도 된다.)
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
- 그룹마다: 활동 시간 합산(`Nh Mm`), 첫 활동 시각(STARTED), 한 줄 코멘트.
- 브랜치에 `[A-Z]+-[0-9]+` 가 있으면 그 키를 절차 5 추정의 **최우선 힌트**로 들고 간다. (이 리포의 `feat/...` 브랜치엔 키가 없으므로 보통 비어 있음 → 절차 5 가 조회·추정으로 채움.)

### 5. Jira 워크로그 입력 (옵션 — `jira` CLI 연동)
**기본은 요약 출력까지만.** 입력/등록/dry-run 을 요청할 때만 진입.
입력 단위 = **태스크(이슈) 1건 = 워크로그 1건 = 소요시간(h) + 한 줄 코멘트**.

> **dry-run 의 목적은 두 가지**: (a) 등록될 `jira issue worklog add` 명령 미리보기, (b) **내 Jira 이슈 중 오늘 작업과 맞을 이슈를 추정해 워크로그 가안(초안)을 제시** → 사용자가 검토·수정 후 확정. 브랜치에 키가 없으므로 (b) 가 핵심이다 — 매번 빈칸을 묻지 말고 **먼저 추정안을 보여주고** 사용자는 고치기만 한다.

#### 5.0 사전: jira config 확인
`jira me` 가 동작해야 한다(config `~/.config/.jira/.config.yml`). 실패하면 최초 `jira init`(서버 URL + 로그인) 안내 후 중단. 겹침회피의 워크로그 조회(REST)와 `--apply` 는 config 의 `server`·`login` + `JIRA_API_TOKEN` env 를 쓴다. **토큰/비밀번호는 스킬·출력에 절대 하드코딩 금지** (기존 env/config 참조만).

#### 5.1 내 이슈 후보 조회
오늘 작업과 매칭할 후보를 가져온다 (담당 + 최근 접근):
```bash
ME=$(jira me)
jira issue list -a "$ME" --order-by updated --reverse \
  --plain --no-headers --columns KEY,STATUS,SUMMARY --paginate 0:20   # 내 담당, 최근 업데이트 순
jira issue list --history \
  --plain --no-headers --columns KEY,STATUS,SUMMARY --paginate 0:20   # 최근 접근 이슈로 보강
```

#### 5.2 추정 매핑 (가안 생성)
각 주제 그룹(절차 4)을 조회된 이슈와 매칭한다 — 주제/커밋/브랜치 **키워드 ↔ 이슈 SUMMARY** 유사도.
- 추정마다 **근거**(어떤 키워드가 어느 이슈와 맞았는지) + **확신도**(높음/낮음)를 붙인다.
- 브랜치 `[A-Z]+-[0-9]+` 키가 있으면 최우선(확신 높음).
- 애매하면 가안엔 확신 높은 1개를 넣되 `(추정)` 표시 + 후보 병기. 도저히 못 정하면 KEY=`-`(SKIP).

추정 매핑 표를 **먼저** 보여준다 (가안):
| 주제 그룹 | 추정 이슈 | 근거 | 확신 | 시간 | 코멘트(한 줄) |
|---|---|---|---|---|---|
| cal 실패마커 6/2/1 | PROJ-42 | SUMMARY "Calibration…" ↔ 작업 키워드 | 높음 | 1h 30m | … |
| FactoryReset 롤백 | PROJ-50? | 약한 매칭 | 낮음(확인요망) | 30m | … |

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
TSV 컬럼: `KEY`(추정 이슈, 미정은 `-`) · `TIME_SPENT`(원본 그대로 넘기면 스크립트가 30분 nearest 반올림) · `STARTED`(첫 활동 KST `YYYY-MM-DD HH:MM:00`) · `COMMENT`(한 줄).
옵션: `--apply` · `--tz`(기본 Asia/Seoul) · `--project` · `--round`(기본 30) · `--overlap-ok`(겹침회피 끔) · `--lunch <범위>`(기본 `12:00-13:00`, `none`=끔).

> 여러 줄 코멘트가 필요하면 이 스크립트(TSV 한 줄=1 레코드)를 우회해 `jira issue worklog add ... --comment $'1줄\n2줄'` 로 직접 호출한다.

**시작시각 처리** (스크립트가 자동):
- `TIME_SPENT` 와 마찬가지로 `STARTED` 도 30분 그리드로 nearest 반올림 (예: 09:53 → 10:00).
- **겹침회피(기본 켬)**: 같은 날 내가 이미 단 워크로그 구간 **+ 점심시간(기본 12:00–13:00) + (절차 2-2 병합 시) 회의 구간** 을 피해, 새 워크로그가 겹치면 빈 슬롯(다음 그리드)으로 STARTED 를 밀어낸다. 연속 입력 행끼리도 누적해 안 겹치게 한다. `--overlap-ok` 로 겹침회피를, `--lunch none` 으로 점심회피를 끈다.
  - jira-cli 에 worklog 조회가 없어 워크로그 조회는 **REST API** 사용: config 의 `server`·`login` + `JIRA_API_TOKEN` env. ⚠ 구 `/rest/api/3/search` 는 **삭제(HTTP 410)** — 이슈 검색은 `jira issue list --jql` (CLI) 로, 각 이슈 워크로그는 `GET /rest/api/3/issue/{key}/worklog` 로 조회. 자격이 없으면 회피 없이 진행.
  - 조회 범위: `worklogAuthor = currentUser() AND worklogDate = "<그 날>"` 로 내 당일 워크로그가 있는 이슈를 찾아 각 이슈의 내 워크로그 구간을 모은다.
  - 예: 오전(09:30–12:00)이 이미 차 있으면 1h30m 워크로그는 점심을 건너뛰어 13:00–14:30 으로 배치된다.

#### 5.4 사용자 검토·수정
추정 가안을 보여주고 **틀린 매핑을 사용자가 고친다**. 확신 낮음/`-` 행은 반드시 확인 — `AskUserQuestion`(5.1 후보 top + Other 직접입력)으로 키를 받거나 SKIP 유지.

#### 5.5 apply
확정된 TSV 에 `--apply` 추가해 실제 입력하고 OK/SKIP/FAIL 보고. **사용자 확인 없이 `--apply` 금지** (외부 반영 행위).

## 출력 포맷

다음 마크다운 구조로 출력:

```markdown
# 워크로그 — {YYYY-MM-DD} ({요일})

## 활동 시간대 (KST)
- HH:MM — HH:MM ({Nh Mm}) · {env}
- HH:MM — HH:MM ({Nh Mm}) · {env}
- **총 활동: {합계}**

## 하루 타임라인 (30분 슬롯)
09:30 │██░░░░░░░░│  2   캘리브레이션 실패 패턴 진단 API 조사 + main rebase
10:00 │████████░░│  8 ✦ FactoryReset persist 삭제 결정 + 실패마커 6/2/1 게이트 전환
10:30 │██████████│ 10 ✦✦ debugUI Enter/Exit 연동·뷰모드 정정·can-inject 패킷
11:00 │███░░░░░░░│  3 ✦ 코드리뷰·top 유지 정정·커밋
11:30 │██░░░░░░░░│  2   PR 생성 + test plan + cleanup
── 프롬프트 25 · 커밋 4 · █=밀도(max 10) ✦=커밋 ──

## 프로젝트별
| 프로젝트(cwd basename) | 활동시간 | prompts | commits | 브랜치 |
|----|----|----|----|----|
| avmc-app | 5h 10m | 12 | 2 | feat/calibration-debug-buttons |

## 커밋
- `75d7c29` [feat/calibration-debug-buttons] feat: Calibration 디버그 패널…
- …

## 주요 작업 주제
1. {topic 1 — 1줄 요약}
2. {topic 2}
…

## Jira 워크로그 가안 (추정 매핑)
| 추정 이슈 | 확신 | 시간(h) | started (KST) | 한 줄 코멘트 |
|----|----|----|----|----|
| PROJ-42 | 높음 | 1h 30m | 2026-05-27 09:53 | cal 실패마커 6/2/1 게이트 전환 + cal 콘솔 명령 |
| PROJ-50? | 낮음(확인요망) | 30m | 2026-05-27 10:27 | FactoryReset 4/1/1→4/4/1 롤백 |
| - (미정) | — | 30m | 2026-05-27 11:11 | PR + cleanup (매칭 이슈 없음 → SKIP) |
```
> 각 행이 워크로그 1건. 이슈 키는 **절차 5.1 조회 + 5.2 추정** 결과(위 키는 예시). `확신` 낮음/미정은 apply 전 반드시 사용자 확인. `시간(h)`은 30분 반올림 후 값.

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
