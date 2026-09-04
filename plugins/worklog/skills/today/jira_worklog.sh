#!/usr/bin/env bash
# jira_worklog.sh — 워크로그 후보를 Jira 워크로그로 입력 (기본 dry-run)
#
# ankitpokhrel/jira-cli 의 `jira issue worklog add` 를 감싼다. CLI 자체엔
# dry-run 이 없으므로 이 스크립트가 게이팅한다: --apply 가 없으면 실행할
# 명령만 출력하고 실제 입력은 하지 않는다.
#
# 입력: stdin, 탭(TAB) 구분 4컬럼. 한 줄 = 한 워크로그(= 한 태스크).
#   KEY        Jira 이슈 키 (예: ABC-123). "-" 이면 SKIP.
#   TIME_SPENT 시간 형식. 공백 구분·붙여쓰기 모두 허용 — "2h" / "1h 30m" / "1h30m"
#              / "90m" / "1d2h30m" (1d=8h). 소수점("1.5h")·주 단위("1w")·같은 단위
#              중복("2h2h")·합계 72h 초과는 불가. 읽을 수 없는 형식이거나 0분으로
#              해석되면 그 행을 FAIL 로 끊는다(0m 으로 조용히 넘어가지 않음).
#   ⚠ 어느 칸도 비우지 마라 — read 의 IFS 가 탭이라 연속 탭이 하나로 뭉개져 뒤 컬럼이
#     통째로 당겨진다(빈 TIME 이면 STARTED 가 TIME 자리로 온다). SKIP 시키려면 칸을
#     비우는 대신 KEY 만 "-" 로 두고 나머지 3칸은 그대로 채운다 — 그래야 SKIP 줄에
#     무엇이 빠졌는지 남는다.
#   STARTED    시작 시각 "YYYY-MM-DD HH:MM:00" (KST 로컬 시각으로 표기).
#   COMMENT    워크로그 코멘트. 리터럴 '\n'(역슬래시+n)은 실제 줄바꿈으로 확장된다
#              → 멀티라인 코멘트를 TSV 한 줄로 표현·입력 가능(손수 jira 호출 불필요).
#              확장되는 건 '\n' 뿐이다 — '\t'·'\033' 등은 글자 그대로 남는다(트랜스크립트
#              에서 옮겨 온 문자열이 터미널 제어문자로 되살아나지 않게).
#   '#' 로 시작하는 줄은 주석/헤더로 무시.
#
# 옵션:
#   --apply         실제 입력. 미지정 시 dry-run(실행할 명령만 출력).
#   --tz <IANA>     타임존 (기본 Asia/Seoul).
#   --project <KEY> jira -p 프로젝트 (선택).
#   --round <MIN>   TIME_SPENT 와 STARTED 를 MIN 분 단위로 nearest 반올림 (기본 30).
#                   TIME_SPENT 는 0<시간은 최소 MIN 보장. STARTED 는 30분 그리드로 정렬
#                   (예: 09:53 → 10:00). 0 이면 둘 다 반올림 끔. 1d=8h 환산.
#   --overlap-ok    내 같은 날 기존 워크로그와 시간대 겹침을 허용. 기본은 겹치지 않게
#                   자동 배치: 같은 날 내가 이미 단 워크로그 구간을 REST 로 조회해
#                   충돌 시 STARTED 를 빈 슬롯(다음 그리드)으로 밀어낸다. 연속 입력
#                   행끼리도 안 겹치게 누적. config/JIRA_API_TOKEN 없으면 자동 무력화.
#   --lunch <범위>  점심시간을 겹침회피 대상에 추가 (기본 "12:00-13:00"). 워크로그가
#                   이 구간과 겹치면 그 뒤로 밀린다. "none" 이면 점심 회피 끔.
#   -h, --help      이 도움말.
#
# 종료코드: FAIL 이 하나라도 있으면 1 (dry-run 도 동일 — 파이프라인이 조용히
#           통과하지 않게). 그 외 0.
#
# 예:
#   printf 'ABC-1\t1h 36m\t2026-05-27 09:53:00\tcal 실패마커 6/2/1 전환\n' \
#     | jira_worklog.sh                 # dry-run (1h 36m → 30분단위 반올림 1h 30m)
#   ... | jira_worklog.sh --apply       # 실제 입력
set -euo pipefail

APPLY=0
TZ_IANA="Asia/Seoul"
PROJECT=""
ROUND=30
NOOVL=1
LUNCH="12:00-13:00"
while [ $# -gt 0 ]; do
  case "$1" in
    --apply)      APPLY=1; shift ;;
    --tz)         TZ_IANA="${2:?--tz 인자 필요}"; shift 2 ;;
    --project)    PROJECT="${2:?--project 인자 필요}"; shift 2 ;;
    --round)      ROUND="${2:?--round 인자 필요}"; shift 2 ;;
    --overlap-ok) NOOVL=0; shift ;;
    --lunch)      LUNCH="${2:?--lunch 인자 필요}"; [ "$LUNCH" = none ] && LUNCH=""; shift 2 ;;
    -h|--help)    sed -n '2,/^set -/p' "$0" | sed '$d; s/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

# ROUND 도 산술($(()))에 들어가므로 정수만 허용(명령 인젝션 차단).
case "$ROUND" in ''|*[!0-9]*) echo "잘못된 --round (0 이상 정수): $ROUND" >&2; exit 2 ;; esac

if ! command -v jira >/dev/null 2>&1; then
  echo "ERROR: 'jira' CLI 가 없다 (ankitpokhrel/jira-cli)." >&2
  exit 1
fi

# 공통 TZ 유틸 로드 → STARTED 파싱/반올림/겹침회피를 워크로그 timezone 으로 해석.
# tzdata 부재(Windows Git Bash 등) 환경에서도 9시간 어긋나지 않게 l2e/e2l 로 변환.
. "$(dirname "${BASH_SOURCE[0]}")/_tz.sh"
tz_setup "$TZ_IANA"
# jira 공통 헬퍼(프로젝트 자동해결·워크로그 조회) — 겹침회피 조회에 사용.
. "$(dirname "${BASH_SOURCE[0]}")/_jira.sh"

# 작은따옴표 래핑(실행 안전 + 사람이 읽기 좋게). 내부 ' 는 '\'' 로 escape.
sq() { local s=${1//\'/\'\\\'\'}; printf "'%s'" "$s"; }

# 화면에 찍을 문자열 정제 — 제어문자 제거 + 길이 절단($2, 기본 64자).
# ⚠ ESC 가 그대로 나가면 ESC[2K(행 삭제)·CR 로 "FAIL "/"DRY " 접두를 지우고 가짜 OK
#    줄을 위조할 수 있다. 절차 5.4 의 사용자 검토가 바로 이 출력을 근거로 도는 단계라
#    표적이 된다. 그리고 TSV 내용은 Jira 이슈 요약·캘린더 제목·커밋 메시지에서 흘러오므로
#    남이 심을 수 있다 — stdout/stderr 로 나가는 값은 전부 이걸 통과시킨다.
#    (Jira 로 실제 전달되는 값에는 쓰지 않는다. argv 배열이라 셸 재해석이 없다.)
#    잘렸으면 '…' 를 붙인다 — 무음 절단은 잘린 값을 온전한 값으로 오인하게 만든다.
san() {
  local s=${1//[[:cntrl:]]/} n=${2:-64}
  if [ "${#s}" -gt "$n" ]; then printf '%s…' "${s:0:$n}"; else printf '%s' "$s"; fi
}

# "1h 36m" / "2h" / "45m" / "1d 2h" / "2h30m" / "1d2h30m" → 분(정수).
# 공백을 먼저 걷어낸 뒤 <숫자><단위> 쌍을 앞에서부터 떼어내므로, 공백 구분과
# 붙여쓰기가 같은 경로로 처리된다. 단위: d=480m(1d=8h) · h=60m · m=1m (대소문자 무시).
# ⚠ 읽지 못한 조각이 있으면 0 으로 뭉개지 말고 rc=1 + stderr 사유를 낸다 —
#    호출자가 그 행을 FAIL 로 끊는다. (예전엔 `continue` 로 삼켜 "2h30m" 이 한 토큰
#    이라 *m 케이스의 num="2h30" 이 되고, 숫자검증 탈락 후 조용히 버려져 0m 이 됐다.)
# ⚠ 숫자부를 산술 전에 정수로 검증한다 — bash 산술은 a[$(cmd)] 형태 명령치환을
#    평가하므로, 미검증 입력을 $(()) 에 넣으면 명령 인젝션이 된다. 단위별 자릿수와
#    전체 길이도 함께 제한해 64bit 랩어라운드를 막는다.
# ⚠ 실패 사유는 "사유만" stderr 로 낸다 — 호출자가 KEY·원문을 앞에 붙여 stderr 와
#    stdout FAIL 줄 양쪽에 같은 사유를 싣는다(stdout 만 캡처해도 이유를 알 수 있게).
to_min() {
  local raw="$1" rest num unit mult u seen="" total=0
  rest="${raw//[[:space:]]/}"
  if [ -z "$rest" ]; then
    printf "빈 값\n" >&2
    return 1
  fi
  # 정상 TIME 은 32자를 넘지 않는다("1d 23h 59m" 도 공백 빼면 8자). 상한이 없으면 매 반복
  # 잔여 문자열을 복사·재매칭하는 아래 루프가 O(n²) 로 늘어져 14KB 입력에 수십 초 멈춘다.
  if [ "${#rest}" -gt 32 ]; then
    printf "값이 너무 길다 (%s자, 최대 32자)\n" "${#rest}" >&2
    return 1
  fi
  while [ -n "$rest" ]; do
    if [[ $rest =~ ^([0-9]+)([dhmDHM])(.*)$ ]]; then
      num="${BASH_REMATCH[1]}"; unit="${BASH_REMATCH[2]}"; rest="${BASH_REMATCH[3]}"
    else
      printf "'%s' 를 <숫자><단위> 로 읽을 수 없다 (허용: 2h / 1h 30m / 1h30m / 90m / 1d2h30m — 1d=8h, 소수점 불가)\n" "$rest" >&2
      return 1
    fi
    # 정규식이 이미 숫자를 보장하지만 $(()) 앞 검증은 방어선으로 남긴다.
    case "$num" in ''|*[!0-9]*)
      printf "숫자가 아닌 값 '%s'\n" "$num" >&2; return 1 ;;
    esac
    # 선행 0 은 자릿수 판정에서 뺀다 — "0000000005m"(=5분)가 "너무 크다"로 걸리지 않게.
    while [ "${#num}" -gt 1 ] && [ "${num:0:1}" = "0" ]; do num="${num:1}"; done
    if [ "${#num}" -gt 6 ]; then
      printf "값이 너무 크다 '%s' (단위당 6자리까지)\n" "$num" >&2
      return 1
    fi
    case "$unit" in
      d|D) mult=480; u=d ;;   # 1d=8h
      h|H) mult=60;  u=h ;;
      m|M) mult=1;   u=m ;;
      *)   printf "알 수 없는 단위 '%s'\n" "$unit" >&2; return 1 ;;
    esac
    # 같은 단위가 두 번 나오면 오타다 — "2h2h" 가 4h 로 조용히 불어나는 것을 막는다.
    # (순서는 안 따진다: "30m 2h" 는 예전부터 되던 표기라 계속 받는다.)
    case "$seen" in *"$u"*)
      printf "단위 '%s' 가 두 번 나온다\n" "$u" >&2; return 1 ;;
    esac
    seen="$seen$u"
    total=$((total + num*mult))
  done
  # 총합 sanity — 단위당 6자리 캡만으로는 "999999d999999h999999m"(≈1029년)이 통과한다.
  # 단순히 값이 이상한 정도가 아니라, 그 구간이 겹침회피 BUSY 에 누적되면
  # place_no_overlap 이 뒤따르는 모든 행의 STARTED 를 수백 년 뒤로 밀어낸다.
  if [ "$total" -gt 4320 ]; then
    printf "합계가 비현실적이다 (%s분 = %sh %sm, 최대 4320분=72h)\n" "$total" "$((total/60))" "$((total%60))" >&2
    return 1
  fi
  echo "$total"
}

# 분 → MIN 단위 nearest 반올림 (0<m 은 최소 MIN). ROUND=0 이면 그대로.
round_min() {
  local m=$1
  [ "$ROUND" -le 0 ] && { echo "$m"; return; }
  local r=$(( (m + ROUND/2) / ROUND * ROUND ))
  [ "$m" -gt 0 ] && [ "$r" -lt "$ROUND" ] && r=$ROUND
  echo "$r"
}

# 분 → jira 형식 "Nh Mm" (h/m). 0 이면 "0m".
min_to_jira() {
  local m=$1
  local h=$((m/60)) mm=$((m%60)) out=""
  [ "$h" -gt 0 ] && out="${h}h"
  [ "$mm" -gt 0 ] && out="${out:+$out }${mm}m"
  echo "${out:-0m}"
}

# "YYYY-MM-DD HH:MM:00" → ROUND분 그리드로 nearest 반올림 (예: 09:53 → 10:00).
# ROUND<=0 또는 파싱 실패 시 원본 유지.
round_started() {
  local s="$1"
  [ "$ROUND" -le 0 ] && { echo "$s"; return; }
  local e; e=$(l2e "$s" 2>/dev/null) || { echo "$s"; return; }
  [ -n "$e" ] || { echo "$s"; return; }
  local sec=$((ROUND*60))
  local r=$(( (e + sec/2) / sec * sec ))
  e2l "$r" "%Y-%m-%d %H:%M:00"
}

# ── 겹침 회피 ───────────────────────────────────────────────
# 내가 같은 날 단 기존 워크로그 구간을 REST 로 조회 → BUSY[] = "startEpoch:endEpoch".
BUSY=(); BUSY_DAY=""
load_busy() {  # $1=YYYY-MM-DD ; stdout: "started<TAB>timeSpentSeconds" 줄들
  # _jira.sh 헬퍼로 조회 — 프로젝트 키를 -p 로 명시(빈 'project ""' 로 빠지지 않게).
  # (예전엔 -p 누락으로 일부 환경에서 빈 결과 → 겹침회피가 조용히 무력화됐다.)
  local day="$1" k started spent secs
  for k in $(jira_worklog_issues "$day" "$PROJECT"); do
    [ -n "$k" ] || continue
    jira_issue_worklogs "$k" "$day" | while IFS=$'\t' read -r started spent secs; do
      [ -n "$started" ] || continue
      printf '%s\t%s\n' "$started" "$secs"
    done
  done
}
ensure_busy() {  # $1=YYYY-MM-DD ; BUSY[] 채움 (날짜 바뀌면 재조회)
  [ "$NOOVL" -eq 1 ] || return 0
  [ "$1" = "$BUSY_DAY" ] && return 0
  BUSY_DAY="$1"; BUSY=()
  local st sec e lse lee
  while IFS=$'\t' read -r st sec; do
    [ -n "$st" ] || continue
    # REST 의 started 는 offset 포함 ISO8601(절대시각) → -u 로 그대로 epoch 화.
    e=$(date -u -d "$st" +%s 2>/dev/null) || continue
    # sec 은 REST 응답(.timeSpentSeconds)에서 온 값이다. to_min 과 같은 이유로 산술
    # 앞에서 정수 검증한다 — bash 산술은 변수 "내용"을 재평가하므로 "x[$(cmd)]" 같은
    # 응답이 오면 그대로 실행된다(적대적·MITM 서버 가정).
    case "$sec" in ''|*[!0-9]*) continue ;; esac
    BUSY+=("$e:$((e+sec))")
  done < <(load_busy "$1")
  # 점심시간도 회피 대상에 추가 (offset 없는 로컬 시각 → l2e 로 변환).
  if [ -n "$LUNCH" ]; then
    lse=$(l2e "$1 ${LUNCH%-*}:00" 2>/dev/null) || lse=""
    lee=$(l2e "$1 ${LUNCH#*-}:00" 2>/dev/null) || lee=""
    [ -n "$lse" ] && [ -n "$lee" ] && BUSY+=("$lse:$lee")
  fi
}
# start_epoch dur_sec → 기존/기배치 구간과 안 겹치는 가장 이른 그리드 시각(epoch).
place_no_overlap() {
  local s=$1 dur=$2 grid moved iv bs be
  grid=$(( ROUND>0 ? ROUND*60 : 1800 ))
  moved=1
  while [ "$moved" -eq 1 ]; do
    moved=0
    for iv in "${BUSY[@]:-}"; do
      [ -n "$iv" ] || continue
      bs=${iv%:*}; be=${iv#*:}
      if [ "$s" -lt "$be" ] && [ "$bs" -lt "$((s+dur))" ]; then
        s=$(( (be + grid - 1) / grid * grid ))   # 그 구간 끝 이후, 그리드 올림
        moved=1
      fi
    done
  done
  echo "$s"
}

ok=0; skip=0; fail=0; n=0
errf="$(mktemp)"
trap 'rm -f "$errf"' EXIT

while IFS=$'\t' read -r KEY TIME STARTED COMMENT || [ -n "${KEY:-}" ]; do
  case "${KEY:-}" in ''|'#'*) continue ;; esac
  n=$((n+1))
  # 화면에 찍을 사본. 원문은 Jira 로 나가는 값에만 쓰고, 출력에는 정제본만 쓴다.
  k_show=$(san "$KEY" 32)
  if [ "$KEY" = "-" ] || [ -z "${TIME// }" ]; then
    # 사유를 갈라서 찍는다 — 헤더가 "칸을 비우지 말고 KEY 만 '-'" 로 안내하므로
    # 실제로 도달하는 건 대개 KEY='-' 쪽이다. 뭉뚱그리면 오해를 부른다.
    if [ "$KEY" = "-" ]; then skip_why="KEY 미정"; else skip_why="시간 없음"; fi
    echo "SKIP  ($skip_why)  $(san "${COMMENT:-}" 200)"
    skip=$((skip+1)); continue
  fi
  # KEY 형식 검증(선두 영숫자 앵커로 '--flag' 형태 argv 인젝션 차단).
  # 제어문자가 섞인 키는 글롭의 '*' 를 통과하므로 별도로 먼저 걸러낸다.
  case "$KEY" in
    *[!A-Za-z0-9_-]*) echo "SKIP  (잘못된 이슈키: $k_show)"; skip=$((skip+1)); continue ;;
    [A-Za-z0-9]*-[0-9]*) ;;
    *) echo "SKIP  (잘못된 이슈키: $k_show)"; skip=$((skip+1)); continue ;;
  esac

  # 30분(=ROUND) 단위 반올림. 원본과 다르면 표시용으로 보관.
  # 파싱 실패는 전체 중단이 아니라 그 행만 FAIL 로 끊는다(사유는 to_min 이 stderr 로).
  # 파싱 실패 줄에는 TIME 원문이 들어가므로 정제본으로 찍는다(san 주석 참조).
  t_show=$(san "$TIME")
  if ! orig_min=$(to_min "$TIME" 2>"$errf"); then
    reason=$(san "$(tr -d '\n' <"$errf")" 200)
    printf "TIME 파싱 실패: KEY=%s TIME=%s — %s\n" "$k_show" "$t_show" "$reason" >&2
    echo "FAIL  $k_show  $(sq "$t_show")  : TIME 파싱 실패 — $reason"
    fail=$((fail+1)); continue
  fi
  rnd_min=$(round_min "$orig_min")
  # 0분 워크로그가 Jira 로 나가는 경로는 없어야 한다. 빈 TIME 은 위에서 이미 SKIP 이므로
  # 여기서 0 이면 "값은 있는데 0분"이고, 그건 입력 실수다 — 등록하지 않고 FAIL.
  if [ "$orig_min" -le 0 ] || [ "$rnd_min" -le 0 ]; then
    printf "0분 워크로그 차단: '%s' 는 %s분으로 해석된다 (KEY=%s)\n" "$t_show" "$orig_min" "$k_show" >&2
    echo "FAIL  $k_show  $(sq "$t_show")  : 0분 워크로그 차단 (빈 값이 아닌데 0분으로 해석)"
    fail=$((fail+1)); continue
  fi
  TIME=$(min_to_jira "$rnd_min")
  rnd_note=""
  [ "$rnd_min" -ne "$orig_min" ] && rnd_note="  (원본 $(min_to_jira "$orig_min") → ${ROUND}m단위)"

  # 시작시각도 ROUND분 그리드로 반올림 (예: 09:53 → 10:00).
  orig_started="$STARTED"
  STARTED=$(round_started "$STARTED")
  # 원본 STARTED 는 파싱 실패 시 그대로 흐르므로 표시할 땐 정제한다. GNU date 가 후행
  # CR 을 공백으로 삼켜 l2e 가 성공해 버리는 탓에, 여기까지 CR 이 살아 오는 경로가 있다.
  [ "$STARTED" != "$orig_started" ] && rnd_note="${rnd_note}  (시작 $(san "${orig_started##* }" 32) → ${STARTED##* })"

  # 같은 날 내 기존 워크로그와 겹치지 않게 빈 슬롯으로 배치.
  # STARTED 파싱 실패 시(l2e rc!=0) 겹침회피를 건너뛰어 원본 STARTED 를 그대로 둔다.
  if [ "$NOOVL" -eq 1 ] && s_epoch=$(l2e "$STARTED"); then
    ensure_busy "${STARTED%% *}"
    new_epoch=$(place_no_overlap "$s_epoch" "$((rnd_min*60))")
    if [ "$new_epoch" -ne "$s_epoch" ]; then
      moved_from=$(san "${STARTED##* }" 32)   # 표시 전용 — 나머지 출력과 같게 정제
      STARTED=$(e2l "$new_epoch" "%Y-%m-%d %H:%M:00")
      rnd_note="${rnd_note}  (겹침회피 ${moved_from} → ${STARTED##* })"
    fi
    BUSY+=("$new_epoch:$((new_epoch + rnd_min*60))")   # 이후 행과도 안 겹치게 누적
  fi

  # tzdata 부재(offset) 환경에선 jira-cli 가 IANA --timezone 을 거부한다
  # ("timezone should be a valid IANA timezone"). 이때는 --timezone 을 생략하고
  # started 에 오프셋(예: +0900)을 직접 부착한다(jira datetime 형식). native 환경은 종전대로.
  off=$(tz_offset_str)
  if [ -n "$off" ]; then
    started_arg="${STARTED/ /T}.000${off}"; tz_args=()
  else
    started_arg="$STARTED"; tz_args=(--timezone "$TZ_IANA")
  fi

  # COMMENT 의 리터럴 \n(역슬래시+n) 을 실제 줄바꿈으로 확장(멀티라인 코멘트 지원).
  # ⚠ 예전엔 printf %b 를 썼는데, 그건 \n 말고 \033·\e·\r·\xNN 까지 **제어문자로 복원**한다.
  #    코멘트 내용은 Jira 이슈 요약·캘린더 제목·커밋 메시지에서 흘러오므로, 거기 심어 둔
  #    평문 6글자("\r\033[2K")만으로 DRY 줄을 지우고 가짜 OK 줄을 만들 수 있었다.
  #    문서화된 계약은 \n 뿐이니 치환도 \n 으로만 한정한다.
  COMMENT_ML=${COMMENT//\\n/$'\n'}
  # 후행 개행 제거 — 예전 $(printf %b) 는 명령치환이 이걸 대신 잘라 줬다. 안 자르면
  # 끝에 "\n" 하나 붙은 1줄 코멘트가 (2줄) 로 보고돼 검토 기준(1시간당 ~1줄)이 어긋난다.
  while [ "${COMMENT_ML%$'\n'}" != "$COMMENT_ML" ]; do COMMENT_ML=${COMMENT_ML%$'\n'}; done
  # 선행 개행도 없앤다 — 남겨 두면 c_first 가 빈 문자열이라 dry-run 이 코멘트를 통째로
  # 감춘다("--comment ''  (3줄)"). 검토자가 "코멘트 비었네" 로 오판하는 경로다.
  while [ "${COMMENT_ML#$'\n'}" != "$COMMENT_ML" ]; do COMMENT_ML=${COMMENT_ML#$'\n'}; done
  cline=$(printf '%s\n' "$COMMENT_ML" | grep -c '^')
  c_first=${COMMENT_ML%%$'\n'*}
  c_show=$(san "$c_first" 200)
  ml_note=""; [ "$cline" -gt 1 ] && ml_note="  (${cline}줄)"

  # 화면에 찍을 시각 사본. Jira 로 나가는 args 에는 원문 started_arg 를 그대로 쓴다.
  s_show=$(san "$STARTED" 32); sa_show=$(san "$started_arg" 48)

  if [ "$APPLY" -eq 1 ]; then
    args=("$KEY" "$TIME" --started "$started_arg" ${tz_args[@]+"${tz_args[@]}"} --comment "$COMMENT_ML" --no-input)
    [ -n "$PROJECT" ] && args=(-p "$PROJECT" "${args[@]}")
    if jira issue worklog add "${args[@]}" >/dev/null 2>"$errf"; then
      echo "OK    $k_show  $TIME  @${s_show}  — ${c_show}${ml_note}${rnd_note}"
      ok=$((ok+1))
    else
      echo "FAIL  $k_show  $TIME  : $(san "$(tr '\n' ' ' <"$errf")" 300)"
      fail=$((fail+1))
    fi
  else
    proj_prefix=""
    [ -n "$PROJECT" ] && proj_prefix="-p $(sq "$PROJECT") "
    tz_show=""; [ "${#tz_args[@]}" -gt 0 ] && tz_show=" --timezone $(sq "$TZ_IANA")"
    # dry-run 은 한 줄로 미리보기(멀티라인은 첫 줄 + 줄 수 표기). 실제 apply 는 전체 확장.
    printf 'DRY   jira issue worklog add %s%s %s --started %s%s --comment %s --no-input%s%s\n' \
      "$proj_prefix" "$(sq "$k_show")" "$(sq "$TIME")" "$(sq "$sa_show")" "$tz_show" "$(sq "$c_show")" "$ml_note" "$rnd_note"
  fi
done

echo "---"
if [ "$APPLY" -eq 1 ]; then
  echo "결과: 입력 $n건 → OK=$ok SKIP=$skip FAIL=$fail"
else
  # dry-run 도 FAIL 을 집계에 드러낸다 — 여기서 안 보이면 --apply 에서 처음 알게 된다.
  echo "(dry-run) 대상 $n건 → DRY=$((n-skip-fail)) SKIP=$skip FAIL=$fail. 실제 입력하려면 동일 입력에 --apply 를 붙인다."
fi
# FAIL 이 있으면 dry-run 도 비정상 종료 — 파이프라인이 조용히 통과하지 않게.
[ "$fail" -gt 0 ] && exit 1 || true
