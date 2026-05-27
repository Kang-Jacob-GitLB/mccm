---
name: worklog-today
description: 공유 worklog JSONL 에서 오늘(또는 지정일) 작업 내역을 읽어 시간대·프로젝트·커밋·prompt 주제로 요약하고 Jira worklog 입력 후보 표를 생성. 선택적으로 jira CLI 로 워크로그를 dry-run 미리보기/실제 입력까지 수행. "오늘 워크로그", "오늘 한 일 정리", "워크로그 요약", "worklog today", "어제 워크로그", "지난주 워크로그", "jira 워크로그 입력", "워크로그 등록 dry-run" 등에 사용.
---

# 오늘 워크로그 요약

## 목적
WSL/Windows 양쪽 Claude Code 세션의 `UserPromptSubmit`, `PostToolUse(git commit)`, `SessionStart/Stop` hook 이 남긴 JSONL 을 읽어 하루치 작업을 정리한다. 최종 출력은 사람이 Jira worklog 에 그대로 옮길 수 있는 표를 포함한다.

## 주 용도: 퇴근 전 일일 루틴
이 스킬의 1차 목적은 **매일 퇴근 전 1회 호출로 Jira 워크로그 입력을 반자동화**하는 것이다. 표준 흐름:

1. 절차 1~4 수행 — 오늘 활동 수집·분석·주제 그룹화.
2. **하루 타임라인 시각화**(30분 슬롯, `timeline.sh`) + 요약 출력.
3. **dry-run 가안 제시** (절차 5) — 내 Jira 이슈를 조회해 오늘 작업과 **자동 추정 매핑**하고, 등록될 `jira issue worklog add` 명령을 워크로그 **가안**으로 보여준다. 시간·시작시각 모두 **30분 그리드 반올림**(시간은 0<최소 30m), **같은 날 기존 워크로그 + 점심시간(기본 12:00–13:00)을 피해 시작시각 자동 배치**. 브랜치에 키가 없으므로 추정 + 사용자 검토가 핵심.
4. 사용자가 가안을 검토·수정(틀린 이슈 매핑 교정)하고 확인하면 `--apply` 로 실제 입력, OK/SKIP/FAIL 보고.

자동화 범위는 **수동 호출 + 확인 후 apply** (cron 무인 입력 아님). "미리보기"만 원하면 3번(추정 가안 dry-run)에서 멈춘다.

## 데이터 위치 (OS별)
`WORKLOG_DIR` env 가 설정돼 있으면 **항상 그것을 우선** 사용. 없으면 OS 별 기본 경로:

| OS | 기본 경로 | 비고 |
|---|---|---|
| **Windows** | `C:\Users\<user>\worklog\` | WSL 과 **동일 위치 공유** |
| **WSL** | `/mnt/c/Users/<user>/worklog/` | 위 Windows 경로의 마운트 = **같은 파일**. Windows/WSL 양쪽 세션 로그가 한 곳에 쌓인다 |
| **macOS** | `~/worklog/` (`/Users/<user>/worklog/`) | 해당 머신 로컬 |
| **Linux (Ubuntu 등)** | `~/worklog/` (`/home/<user>/worklog/`) | 해당 머신 로컬 |

> Windows·WSL 은 같은 물리 디렉토리(C 드라이브)를 가리켜 로그를 **공유**한다. macOS·native Linux 는 각자 홈 `~/worklog/` 에 **독립 저장**. WSL 의 Windows username 이 위 `<user>` 와 다르거나 위치를 바꾸려면 `WORKLOG_DIR` 로 지정한다.

파일 패턴: `worklog-{env}-{YYYY-MM}.jsonl` (env = `wsl` / `windows` / `macos` / `linux`).

각 라인 스키마:
```json
{"ts":"ISO8601","env":"wsl|windows","event":"prompt|commit|session_start|session_stop","session_id":"...","cwd":"...","branch":"...","prompt":"...","sha":"...","subject":"...","body":"..."}
```

## 의존성 (외부 도구)
| 도구 | 필요 시점 | 비고 |
|---|---|---|
| `node` | hook 로깅 (필수) | hook 스크립트가 Node. 없으면 JSONL 이 안 쌓임 |
| `jq` | 분석·시각화 (필수) | 절차 2~3, `timeline.sh`, 겹침회피 파싱 |
| `jira` | 워크로그 입력 (절차 5) | **ankitpokhrel/jira-cli**. `jira init`(server/login) + `JIRA_API_TOKEN` env 선행. 없으면 절차 1~3(요약·시각화)만 동작 |
| `curl`, `base64` | 겹침회피 (절차 5) | 같은 날 기존 워크로그 REST 조회. 없으면 회피 없이 진행 |

## 데이터 생성 hook (이 plugin 에 포함)
이 스킬은 로그를 **직접 만들지 않는다** — 아래 hook 이 JSONL 을 쌓는다. **이 plugin 이 hook 을 함께 포함**하므로(`plugin.json` 의 `hooks`), plugin 을 활성화하면 **자동 등록**된다 (별도 settings.json 설정 불필요).

- 스크립트: `${CLAUDE_PLUGIN_ROOT}/hooks/{log-session,log-prompt,log-commit}.js` (Node)
- 데이터 경로/env: `WORKLOG_DIR`·`WORKLOG_ENV` 가 있으면 우선, 없으면 스크립트가 **OS 자동 감지**(데이터 위치 표대로 — WSL→`/mnt/c/Users/user/worklog`·`wsl`, macOS/Linux→`~/worklog`·`macos`/`linux`, Windows→`%USERPROFILE%\worklog`·`windows`).

| 이벤트 | 스크립트 | 기록되는 `event` |
|---|---|---|
| `SessionStart` | `log-session.js` | `session_start` |
| `Stop` | `log-session.js` | `session_stop` |
| `UserPromptSubmit` | `log-prompt.js` | `prompt` |
| `PostToolUse` (matcher: `Bash`) | `log-commit.js` | `commit` (git commit 감지) |

> ⚠ **중복 주의**: 이전에 `~/.claude/settings.json` 의 `hooks` 에 같은 worklog hook 을 수동 등록해 뒀다면, 이 plugin 과 **둘 다 실행되어 로그가 2배로 쌓인다**. plugin 으로 일원화하려면 settings.json 의 worklog hook 4개(`SessionStart`/`Stop`/`UserPromptSubmit`/`PostToolUse`)를 제거한다. (단 `env` 의 `WORKLOG_DIR`/`WORKLOG_ENV` 는 두어도 무방 — 스크립트가 우선 사용.)

## 절차

### 1. 대상 날짜 결정
- 기본: `date -I` 의 오늘 (KST). 사용자가 "어제", "5/24", "지난주 월요일" 등 지정하면 그에 맞춰 변환.
- 출력 시 KST (`+09:00`) 기준으로 표기. JSONL `ts` 는 UTC 이므로 **2-1 시각 변환 규칙**을 반드시 따른다 (+9h 이중적용 주의).

### 2. 라인 수집
```bash
# WORKLOG_DIR 우선, 없으면 OS 별 기본 (데이터 위치 표 참조)
DIR="${WORKLOG_DIR:-$(
  case "$(uname -s)" in
    Darwin) echo "$HOME/worklog" ;;                                   # macOS
    Linux)  if grep -qi microsoft /proc/version 2>/dev/null; then
              echo "/mnt/c/Users/user/worklog"                        # WSL (Windows 와 공유; username 다르면 WORKLOG_DIR)
            else echo "$HOME/worklog"; fi ;;                          # native Linux (Ubuntu 등)
    *)      echo "$HOME/worklog" ;;
  esac )}"
DATE="2026-05-26"      # 예시 (KST 기준 대상일)
YM="${DATE%-*}"        # 2026-05
export TZ=Asia/Seoul   # awk/date strftime 출력을 KST 로 고정 (2-1 규칙 참조)

# 해당 월 모든 env 파일 합치고, KST 기준 그 날짜만 추출
#  ⚠ ts 는 밀리초(...29.306Z)를 포함할 수 있다. jq fromdateiso8601 은
#    "%Y-%m-%dT%H:%M:%SZ" 만 받으므로 sub() 로 소수부를 반드시 strip (안 하면 전 라인 에러).
for f in "$DIR"/worklog-*-"$YM".jsonl; do [ -f "$f" ] && cat "$f"; done \
  | jq -c --arg d "$DATE" '
      (.ts | sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601) as $utc   # 항상 UTC epoch
      | (($utc + 9*3600) | strftime("%Y-%m-%d")) as $kst_date     # jq strftime=UTC고정 → 날짜만 +9 가산
      | select($kst_date == $d)
      | . + {epoch: $utc}'   # 출력 시각용 raw UTC epoch 보존 (awk 에 그대로 넘김)
```

### 2-1. 시각 변환 규칙 (⚠ +9h 는 단 한 번)
`ts` 는 UTC. KST 표기 시 **+9h 가 두 번 적용되는 이중변환** 을 조심한다.
(실제 발생: 오전 09:53 작업이 저녁 18:53 으로 잘못 표기됨 — jq 에서 +9 한 epoch 을 awk strftime 에 넘겨 awk 가 로컬 TZ 로 +9 를 또 적용.)

- `jq` 의 `fromdateiso8601` 은 항상 **UTC epoch** 을 낸다. `jq` 의 `strftime` 도 **UTC 고정**.
- `awk` / `date` 의 `strftime` 은 **로컬 TZ** (이 환경 = KST=+9) 를 적용한다.
- 그래서 시각 포맷은 둘 중 한 방식으로만 **일관**되게:
  - **awk 로 출력 (권장)**: jq 는 `epoch`(raw UTC) 만 내보내고 awk 에 그 raw epoch 을 넘긴다. `export TZ=Asia/Seoul` 만 해두면 awk strftime 이 KST 로 찍는다 → +9 산술을 **직접 쓰지 않는다**.
  - **jq 로 출력**: jq 안에서 `($utc + 9*3600) | strftime(...)`. 이 값은 awk/date 로 **다시 포맷하지 않는다**.
- 🚫 금지: `jq` 에서 `+9*3600` 한 값을 `awk`/`date` strftime 에 넘기기 (← 이중변환 원인).

출력 표준 (raw epoch 보존 → TZ=Asia/Seoul awk):
```bash
export TZ=Asia/Seoul
#  ⚠ prompt/subject 본문의 개행은 awk -F'\t' 레코드를 쪼개 "epoch 빈 줄"(09:00 으로 보임)을
#    만든다 → jq 단계에서 gsub("\n";" ") 로 한 줄로 평탄화한 뒤 awk 에 넘긴다.
jq -r 'select(.event=="prompt" or .event=="commit")
       | "\(.epoch)\t\(.event)\t\((.subject // .prompt // "") | gsub("\\s+"; " "))"' "$F" \
  | sort -n | awk -F'\t' '{ printf "%s  %-8s %s\n", strftime("%H:%M:%S",$1), $2, $3 }'
```
검증: 출력 첫 시각이 그 날의 상식적 업무시간대(예: 오전 9~10시)와 맞는지 한 번 눈으로 확인한다. 12시간 어긋나면 이중변환을 의심.

### 3. 섹션별 분석
모은 라인을 다음 4개 묶음으로 분류:
- **활동 시간대**: `session_start` / `session_stop` 페어 + 마지막 prompt ts 로 활동 구간 산출 (세션이 stop 없이 끊긴 경우 마지막 prompt 시각을 종료로 간주).
- **프로젝트별 통계**: `cwd` basename 으로 그룹. 각 그룹의 prompt 수, commit 수, 첫/마지막 활동 시각.
- **커밋 목록**: `event=="commit"` 라인. SHA(short) + branch + subject 한 줄.
- **prompt 주제 요약**: Claude 가 prompt 본문들을 읽고 5-10 줄로 의미 단위 요약 (질문/검토/디버깅/문서작성/etc. 분류). 잡담/오타/한 글자 입력은 제외.
- **하루 타임라인(30분 슬롯)**: `timeline.sh` 로 슬롯별 밀도 막대(`█`)와 커밋 마커(`✦`)를 결정적으로 렌더한 뒤, Claude 가 각 행 오른쪽에 그 시간대 **주제 라벨 한 줄**을 채운다. `task-notification`·빈 prompt 는 제외된다.
  ```bash
  cat today.jsonl | "$HOME/.claude/skills/worklog-today/timeline.sh"   # today.jsonl = 절차 2 수집 결과
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
SH="$HOME/.claude/skills/worklog-today/jira_worklog.sh"
# 추정 매핑 → TSV (KEY \t TIME \t STARTED \t COMMENT). 확신 없으면 "-".
printf '%s\n' \
  $'PROJ-42\t1h 36m\t2026-05-27 09:53:00\tcal 실패마커 6/2/1 게이트 전환 + cal 콘솔 명령' \
  $'-\t30m\t2026-05-27 10:27:00\tFactoryReset 4/1/1→4/4/1 롤백 (추정 실패 — 확인요망)' \
  | "$SH"            # dry-run: 추정 가안 명령 미리보기
```
TSV 컬럼: `KEY`(추정 이슈, 미정은 `-`) · `TIME_SPENT`(원본 그대로 넘기면 스크립트가 30분 nearest 반올림) · `STARTED`(첫 활동 KST `YYYY-MM-DD HH:MM:00`) · `COMMENT`(한 줄).
옵션: `--apply` · `--tz`(기본 Asia/Seoul) · `--project` · `--round`(기본 30) · `--overlap-ok`(겹침회피 끔) · `--lunch <범위>`(기본 `12:00-13:00`, `none`=끔).

**시작시각 처리** (스크립트가 자동):
- `TIME_SPENT` 와 마찬가지로 `STARTED` 도 30분 그리드로 nearest 반올림 (예: 09:53 → 10:00).
- **겹침회피(기본 켬)**: 같은 날 내가 이미 단 워크로그 구간 **+ 점심시간(기본 12:00–13:00)** 을 피해, 새 워크로그가 겹치면 빈 슬롯(다음 그리드)으로 STARTED 를 밀어낸다. 연속 입력 행끼리도 누적해 안 겹치게 한다. `--overlap-ok` 로 겹침회피를, `--lunch none` 으로 점심회피를 끈다.
  - jira-cli 에 worklog 조회가 없어 **REST API** 사용: config 의 `server`·`login` + `JIRA_API_TOKEN` env 로 `GET /rest/api/3/issue/{key}/worklog` 조회. 자격이 없으면 회피 없이 진행.
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
- session_id 가 같으면 같은 Claude Code 세션. 활동 시간대 산출 시 세션 단위로 묶기.
- `event=="prompt"` 가 0인데 `session_start` 만 있는 세션은 활동 시간 0 으로 계산하지 말고 "세션 열림만" 으로 별도 표시.
- 양쪽 env 동시 활동인 경우 활동 시간대를 합집합으로 계산 (겹치는 구간은 한 번만 카운트).
