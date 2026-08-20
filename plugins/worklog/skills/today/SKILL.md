---
name: today
description: Claude Code 세션 트랜스크립트(~/.claude/projects)에서 오늘(또는 지정일) 작업 내역을 읽어 시간대·프로젝트·커밋·prompt 주제로 요약하고 Jira worklog 입력 후보 표를 생성. 선택적으로 jira CLI 로 워크로그를 dry-run 미리보기/실제 입력까지 수행. gws(권장, npm `@googleworkspace/cli`) 연동 시 Google Calendar 회의 일정을 병합해 회의 시간도 워크로그로 인지. hook 불필요. "오늘 워크로그", "오늘 한 일 정리", "워크로그 요약", "worklog today", "어제 워크로그", "지난주 워크로그", "jira 워크로그 입력", "워크로그 등록 dry-run" 등에 사용.
---

# 오늘 워크로그 요약

## 목적
Claude Code 가 **세션마다 자동으로 남기는 트랜스크립트**(`~/.claude/projects/<cwd-slug>/<session-id>.jsonl`)를 읽어 하루치 작업을 정리한다. hook 설치 **불필요** — 항상 기록되는 대화 로그를 직접 파싱한다. 최종 출력은 사람이 Jira worklog 에 그대로 옮길 수 있는 간트/표를 포함한다.

## ⚡ 핵심 원칙 — 스크립트가 다 한다 (ad-hoc 금지)
이 스킬의 데이터 수집·가공은 **전부 스크립트**(`prep.sh`·`collect.sh`·`timeline.sh`·`jira_worklog.sh`)가 처리한다.

> 🚫 **`jq`/`awk`/`date`/`curl` 을 직접 작성하지 말 것.** 시각변환(UTC→KST), Windows/Unix 경로 basename, jira 프로젝트 `-p` 해결, 워크로그 REST 조회, 토큰 상한은 모두 스크립트가 한다. 직접 짜면 정규식 char-class·백슬래시 이스케이프·TZ 폴백 버그로 **에러 덤프 + 왕복으로 토큰을 낭비**한다(과거 실패 사례). 스크립트 출력 **텍스트를 읽고 판단만** 한다.

스킬 디렉토리 자동 탐색(플러그인 캐시/로컬 어디든):
```bash
SKILL_DIR="$(dirname "$(find "$HOME/.claude/plugins/cache" "$HOME/.claude/skills" \
  -name prep.sh -path '*/skills/today/prep.sh' 2>/dev/null | sort -r | head -1)")"
```

## 스크립트 도구
| 스크립트 | 역할 |
|---|---|
| `prep.sh` | **1차 진입점.** 활동·커밋·jira 후보·당일 워크로그를 **동시 수집**해 압축 리포트 1회 출력 |
| `collect.sh` | 트랜스크립트 → 정규화 JSONL (prep.sh 가 내부 호출; 단독으로도 사용 가능) |
| `timeline.sh` | JSONL → 30분 슬롯 밀도 타임라인 |
| `jira_worklog.sh` | TSV → jira 워크로그 dry-run/`--apply` (30분 반올림·겹침회피·멀티라인 코멘트) |
| `_tz.sh` / `_jira.sh` | 공통 유틸(TZ 변환 / jira config·프로젝트해결·REST). 직접 호출 안 함 |

## 요구사항
| 도구 | 등급 | 용도 | 미설치 시 |
|---|---|---|---|
| `jq` | **필수** | 모든 파싱 | 중단 |
| `jira` (ankitpokhrel/jira-cli) | 워크로그 입력 시 필수 | 후보 조회·dry-run·apply | 안내 후 요약만 |
| `curl`+`base64` | 겹침회피 시 | 당일 워크로그 REST 조회 | 회피 없이 진행 |
| `gws` (npm `@googleworkspace/cli`) | 권장 | 회의 일정 병합 | 조용히 스킵 |

- **jira 설정**: `jira init`(server/login) + `JIRA_API_TOKEN` env. `jira me` 가 본인 계정을 내면 정상. config 는 `~/.config/.jira/.config.yml`. 프로젝트 키는 `_jira.sh` 가 config 에서 자동 해결(`-p` 누락으로 `project ""` 빈 결과가 나던 문제 방지).
- **gws 설정**: `gws auth login`(Google Calendar API + OAuth 데스크톱 앱). 미설치/미인증 시 회의 병합만 생략.
- 🔒 토큰/비밀번호는 스킬·출력에 **절대 하드코딩 금지** (env/config 참조만).

## 데이터 소스 (Claude Code 트랜스크립트)
- 위치: `~/.claude/projects/<cwd-slug>/<session-id>.jsonl` (Windows `C:\Users\<user>\.claude\projects\...`).
- **머신 자동 병합**: WSL 실행 시 Windows(`/mnt/c/...`)도, Windows(Git Bash/MSYS) 실행 시 WSL(`//wsl.localhost/<distro>/...`)도 함께 스캔. 한쪽만 있으면 단독 진행.
- `collect.sh` 정규화 출력 스키마(과거 hook JSONL 과 동일):
  ```json
  {"ts":"ISO8601(UTC)","env":"wsl|windows|...","event":"prompt|commit|session_start|session_stop","session_id":"...","cwd":"...","branch":"...","prompt":"...","sha":"...","subject":"...","epoch":1716...}
  ```
- 추출 규칙(collect.sh 내장):
  - **prompt** = 실제 사용자 입력. tool_result·`<task-notification>`·`<local-command-*>`·서브에이전트(`isSidechain`)·`[Request interrupted...]` 제외. 슬래시 명령은 `/cmd args` 로 복원.
  - **commit** = `git commit` 을 실행한 Bash tool_use 결과의 `[branch sha] subject` 만(= log/show/rebase 출력 배제). sha 로 dedup. ⚠ **로컬 commit 만** — GitHub squash/rebase 머지 SHA 는 누락될 수 있다(PR 로 확인).
  - **session_start/stop** = 세션파일별 그 날 라인의 min/max(활동창 근사).

## 절차

### 1. 대상 날짜
기본 오늘(KST). "어제"/"5/24"/"지난주 월요일" 등은 `YYYY-MM-DD` 로 변환해 인자로 넘긴다. 표기는 KST. 못 알아들으면 1회 확인.

### 2. 데이터 수집 — prep.sh 1회 (동시 수집)
```bash
"$SKILL_DIR/prep.sh" 2026-05-29                          # 하루 전체
"$SKILL_DIR/prep.sh" 2026-05-29 --since 18:30 --issue WDSW2D2510-297
#  옵션: [DATE]  --since/--until HH:MM  --issue KEY(상세 포함)  --project KEY  --max N(섹션당 줄수)
```
출력 섹션을 그대로 읽어 쓴다:
- `ACTIVITY` — prompt 들(로컬시각 `HH:MM` + `[프로젝트basename]` + 본문). 시각·basename 변환 완료됨.
- `COMMITS` — `HH:MM sha [branch] subject`.
- `JIRA_CANDIDATES` — 활성 우선 + 최근접근(KEY STATUS SUMMARY). 워크로그 매핑 후보.
- `WORKLOGS_TODAY` — 당일 내 기존 워크로그(KEY 시작 시간 timeSpent). **겹침회피 참고.**
- `ISSUE` — `--issue` 준 경우 그 이슈 상세(상태 확인용).

> 타임라인 막대가 필요하면: `"$SKILL_DIR/collect.sh" DATE | "$SKILL_DIR/timeline.sh"` (밀도 막대 + 커밋 마커를 결정적으로 렌더 → 각 행 우측에 주제 라벨을 LLM 이 채움).

### 3. 분석
prep.sh 출력으로 분류:
- **활동 시간대**: `session_start/stop` 합집합(겹치는 세션은 1회 카운트). 회의 병합 시 회의 구간 포함.
- **프로젝트별**: `ACTIVITY` 의 `[basename]` 으로 그룹(워크트리는 별 slug).
- **prompt 주제 요약**: 본문을 의미 단위 5–10줄로. 잡담/오타/한 글자/슬래시 노이즈 제외.

### 4. 작업 주제 그룹화
워크로그 단위가 될 **주제 그룹**을 만든다(보통 1~4개). 그룹마다: 활동시간 합산(`Nh Mm`), 첫 활동 시각(STARTED), **시간 비례 멀티라인 코멘트**(시간당 ~1줄). 브랜치에 `[A-Z]+-[0-9]+` 키가 있으면 절차 5 추정의 최우선 힌트(이 환경 `feat/...` 브랜치엔 키 없음 → JIRA_CANDIDATES 로 추정).

### 5. Jira 워크로그 입력 (옵션)
**기본은 요약까지만.** 입력/dry-run 요청 시만 진입. 입력 단위 = **이슈 1건 = 워크로그 1건 = 소요시간 + 시간 비례 멀티라인 코멘트**.

#### 5.1 후보·기존 워크로그
절차 2 `prep.sh` 의 `JIRA_CANDIDATES`(상태 포함)와 `WORKLOGS_TODAY`(겹침회피)를 이미 받았다 — **다시 조회하지 않는다**. `jira me` 실패 시 `jira init` 안내 후 중단.

#### 5.2 추정 매핑 (가안)
각 주제 그룹을 `JIRA_CANDIDATES` 와 매칭(키워드 ↔ SUMMARY 유사도). 추정마다 **근거 + 확신도(높음/낮음)**.
- 브랜치 키 있으면 최우선. 애매하면 확신 높은 1개 + `(추정)` 병기, 도저히 못 정하면 KEY=`-`(SKIP).
- 🚫 **완료(Done/Closed/해결됨) 이슈엔 워크로그 금지**(재오픈·집계왜곡). 활성 차선 후보 우선, 없으면 `-`(SKIP) + `완료 티켓 OOO-NN 와만 매칭 — 확인요망` 명시. 가안 표 `확신` 칸에 `완료(부적절)` 표기.
- 🚫 **상위 에픽이 Backlog(미진행) 인 이슈도 금지** — 일부 Jira 자동화가 워크로그를 **자동 삭제**한다. 잡무성 이슈(예: 연간 지원)는 `--issue` 또는 `jira issue view <KEY>` 로 에픽 상태 확인 후, Backlog 면 SKIP/다른 활성 이슈.

추정 매핑 표를 **먼저** 보여준다(예시 — 실제는 후보 조회로 채움):
| 주제 그룹 | 추정 이슈 | 근거 | 확신 | 시간 | 코멘트(시간 비례, ~1줄/h) |
|---|---|---|---|---|---|
| System Setting 시간/언어 | WDSW2D2510-297 | SUMMARY ↔ Time/Language | 높음 | 2h | (2줄) … |

#### 5.3 dry-run → 멀티라인 코멘트
추정 매핑을 TSV(`KEY \t TIME \t STARTED \t COMMENT`)로 만들어 `jira_worklog.sh` 에 넘긴다. **코멘트 멀티라인은 `COMMENT` 안에 리터럴 `\n` 으로** 넣는다 — 스크립트가 apply 시 실제 줄바꿈으로 확장한다(손수 `jira` 호출 불필요). 확장되는 건 `\n` **뿐이다**(`\t`·`\033` 등은 글자 그대로 남는다 — 트랜스크립트에서 옮겨 온 문자열이 터미널 제어문자로 되살아나지 않게).
```bash
SH="$SKILL_DIR/jira_worklog.sh"
printf '%s\n' \
  $'WDSW2D2510-297\t2h\t2026-05-29 18:30:00\t- Time Settings 미세조정(년 하한 2000)\\n- Language 한글 기본 + 보드 반영' \
  | "$SH"            # dry-run (시간·시작시각 30분 반올림, 겹침회피, (N줄) 표기)
```
- **TIME 허용 형식**: `"2h"` / `"1h 30m"` / `"1h30m"` / `"90m"` — 1d=8h. 공백 구분·붙여쓰기 모두 된다(`1d2h30m` 도 가능). **소수점(`1.5h`)·주 단위(`1w`)·같은 단위 중복(`2h2h`)은 불가** — 전부 FAIL.
  - **읽을 수 없는 형식(`2x30y`)이나 0분으로 해석되는 값(`0m`)은 그 행이 FAIL** — 사유가 stderr 로 나가고 0분 워크로그는 등록되지 않는다. 나머지 행은 계속 진행하며, FAIL 이 있으면 dry-run 도 종료코드 1.
  - ⚠ **어느 칸도 비우지 말 것.** `read` 의 IFS 가 탭이라 연속 탭이 하나로 뭉개져 뒤 컬럼이 통째로 당겨진다(빈 TIME 이면 STARTED 가 TIME 자리로 옴). SKIP 시키려면 칸을 비우는 대신 **KEY 만 `-` 로** 두고 나머지 3칸은 그대로 채운다 — 그래야 SKIP 줄에 무엇이 빠졌는지 남는다.
- **시간/시작시각 30분 그리드 nearest 반올림**(시간은 0<최소 30m; 09:53→10:00). `--round 0` 으로 끔(반올림만 꺼지고 파싱은 동일).
- **겹침회피(기본 켬)**: 당일 내 기존 워크로그 + 점심(기본 12:00–13:00) + (병합 시) 회의 구간을 피해 빈 슬롯으로 STARTED 밀어냄. 연속 행끼리도 누적. `--overlap-ok`/`--lunch none` 으로 끔.
- 옵션: `--apply` · `--tz`(기본 Asia/Seoul) · `--project`(미지정 시 config 자동) · `--round` · `--overlap-ok` · `--lunch`.
- ⚠ tzdata 부재(Windows MSYS) 환경에선 jira-cli 가 IANA `--timezone` 을 거부 → 스크립트가 `--started` 에 오프셋(`+0900`)을 자동 부착해 처리한다(LLM 이 신경 쓸 필요 없음).
- 코멘트 **줄 수**를 소요시간에 비례해 잡는다 — 1시간당 ~1줄(예: 소요 `2h 30m` → 코멘트 3줄). dry-run 은 첫 줄 + `(N줄)` 로 미리보기.

#### 5.4 검토 → 5.5 apply
가안을 보여주고 **틀린 매핑을 사용자가 교정**. 확신 낮음/`-`/완료 행은 `AskUserQuestion`(후보 top + Other) 으로 확인. 확정 TSV 에 `--apply` 추가해 입력하고 OK/SKIP/FAIL 보고. **사용자 확인 없이 `--apply` 금지**(외부 반영). 완료 이슈는 사용자가 명시 동의하지 않는 한 입력하지 않는다.

### (선택) 회의 일정 병합 — gws
`gws` 설치·인증 시 그날 Google Calendar 회의를 타임라인·워크로그 후보에 합친다(없으면 조용히 스킵, 권장 안내 1회).
```bash
case "$DATE" in [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) ;; *) echo "잘못된 날짜: $DATE" >&2; exit 2 ;; esac
PARAMS=$(jq -nc --arg d "$DATE" '{calendarId:"primary",timeMin:($d+"T00:00:00+09:00"),timeMax:($d+"T23:59:59+09:00"),singleEvents:true,orderBy:"startTime",maxResults:50}')
gws calendar events list --format json --params "$PARAMS" 2>/dev/null \
  | jq -r '.items[]? | select((.start.dateTime//null)!=null)
      | select([.attendees[]?|select(.self==true)|.responseStatus]|(index("declined")|not))
      | "\(.start.dateTime)\t\(.end.dateTime)\t\(.summary // "(제목없음)")"'
```
- ⚠ `gws` 는 stdout=JSON, stderr=`Using keyring backend...` → 반드시 `2>/dev/null`.
- 종일·참석거절(`declined`) 제외. 회의를 `event:"meeting"` 라인으로 합쳐 간트 회의 막대(`█`)·활동시간 합산·겹침회피 대상(찬 구간)으로 사용.

## 출력 포맷 — 간트 24h 축
**시각화·dry-run 은 표 대신 "간트 24h 축" 스타일**로 코드블록(monospace) 안에 렌더한다(값은 예시):
```
워크로그 · {YYYY-MM-DD} ({요일})                       활동 {합계} · 커밋 {N}

          0      3     6     9     12    15    18    21    24
          ┌──────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┐
 코딩  ▓  │···················▓····························│ 09:33–10:14 · 41m
 회의  █  │································██··············│ 16:00–17:00 · 1h
 점심  ·  │················································│ 12:00–13:00 (제외)
          └────────────────────────────────────────────────┘

 주요 작업
   ▸ {topic 1}
   ▸ {topic 2}

 DRY-RUN · jira worklog                       ▸ 30m grid · ⏎=apply
 ▐ WDSW2D2510-297 ▌ ████████  18:30  System Setting 시간/언어 (2줄)  진행중  ✔
 ▐ WDSW2D2510-252 ▌ ████░░░░  09:30  keep_previous · 보드빌드         ⚠완료·보류
 ▐ 타운홀미팅      ▌ ████░░░░  16:00  타운홀미팅                       이슈미정
 ▐ skip           ▌ ········  ──     {주제} ({사유})                  ∅
 ────────────────────────────────────────────────────────────────────
 등록 예정 {전체KEY}({시간}) · 보류 {완료 전체KEY} · 확인 {미정/회의}
```
렌더 규칙:
- **24h 축**: 폭 **W=48 고정 → 1칸 = 30분**. 막대 시작/끝 열 = `round(hour/24*48)`. hour 는 prep.sh 가 준 **로컬(KST) 시각**(⚠ UTC 로 그리지 말 것). 문자: 코딩 `▓`·회의 `█`·빈칸 `·`. 좌측 라벨을 한글 2자로 맞추면 축 눈금·`┌`·`│` 가 세로 정렬된다.
- **막대로 시간을 읽지 말 것 — 숫자는 우측 텍스트가 갖는다.** 두 막대는 축이 서로 다르다: 24h 축은 1칸=30분이라 소요가 30분 배수가 아니면 어긋나고(위 예시의 `41m` 이 1칸인 이유), DRY-RUN 막대는 시간 축이 아니라 **8칸 고정 비율 게이지**다(아래 참조). 정확한 값은 24h 축은 우측 `HH:MM–HH:MM · 길이`, DRY-RUN 행은 등록될 `시간` 표기가 갖는다.
- **제외 구간은 막대를 그리지 않는다.** 점심(기본 12:00–13:00)처럼 **워크로그에서 빼는 시간**은 빈칸 `·` 그대로 두고, 행 라벨과 우측 `HH:MM–HH:MM (제외)` 텍스트로만 표기한다(겹침회피로 비워 둔 구간도 동일). 채운 칸에 "일한 시간"만 남기는 게 목적이니 제외 구간에 `▓`/`█`/`▒`/`□` 같은 채움 문자를 쓰지 말 것. 범례 문자도 `·` 로 맞춘다.
- 각 막대 우측 `HH:MM–HH:MM · 길이` 가 활동시간 정보를 겸한다(별도 표 불필요).
- **DRY-RUN 행**: `▐ 전체KEY ▌`(숫자만 줄이지 말 것 — 오입력 방지) + 비율 게이지 + STARTED + 코멘트(첫줄 + `(N줄)`) + 꼬리표 `진행중 ✔`/`⚠완료·보류`/`이슈미정`/`∅`. `⚠완료`·`이슈미정`·`∅` 는 apply 제외. 마지막 줄에 등록예정/보류/확인 건수.
  - **비율 게이지는 8칸 고정**: 그 배치에서 **가장 긴 워크로그를 8칸(`████████`)** 으로 잡고 나머지를 그 비율로 채운다(`█`=소요, `░`=잔여). 위 예시는 최장이 `2h` 라 `2h`→8칸, `1h`→`████░░░░` 다. **시간이 정해지지 않은 `∅` 행만** `········` 로 비운다(`⚠완료·보류`·`이슈미정` 은 시간이 있으니 정상 게이지). **칸 수는 상대 비율일 뿐 시간이 아니다** — 실제 등록 시간은 스크립트 dry-run 출력의 값을 그대로 옮긴다.

## 인자 처리
- "오늘"→오늘 · "어제"/"yesterday"→오늘-1 · "5/24"/"2026-05-24"→해당일 · "이번주"→월~오늘 합산(활동시간대 섹션은 일자별 소계) · "지난주"→지난주 월~일.
- "dry-run"/"미리보기"→절차 1~4 후 5 dry-run(명령만). "입력해"/"등록해"/"apply"→dry-run 보여주고 **확인 후 `--apply`**.
- 날짜 불명 시 1회 확인. 입력 의도 모호하면 dry-run(안전 기본값).

## 주의 사항
- prompt 에 민감정보(토큰/비번) 보이면 출력에 `{생략}`.
- `session_id` 같으면 같은 세션 — 활동 시간대는 세션 단위로 묶기.
- 트랜스크립트는 **전 프로젝트** 포함(워크트리는 별 slug). 특정 프로젝트만 원하면 `ACTIVITY` 의 `[basename]` 으로 필터.
- `prep.sh`/`collect.sh` 가 빈 결과면 "해당 날짜 활동 없음" 안내.
