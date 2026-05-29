#!/usr/bin/env bash
# jira_worklog.sh — 워크로그 후보를 Jira 워크로그로 입력 (기본 dry-run)
#
# ankitpokhrel/jira-cli 의 `jira issue worklog add` 를 감싼다. CLI 자체엔
# dry-run 이 없으므로 이 스크립트가 게이팅한다: --apply 가 없으면 실행할
# 명령만 출력하고 실제 입력은 하지 않는다.
#
# 입력: stdin, 탭(TAB) 구분 4컬럼. 한 줄 = 한 워크로그(= 한 태스크).
#   KEY        Jira 이슈 키 (예: AVMC-123). "-" 또는 빈칸이면 SKIP.
#   TIME_SPENT jira 시간 형식, 시간 단위 위주 (예: "2h", "1h 30m", "30m").
#   STARTED    시작 시각 "YYYY-MM-DD HH:MM:00" (KST 로컬 시각으로 표기).
#   COMMENT    워크로그 코멘트. 리터럴 '\n'(역슬래시+n)은 실제 줄바꿈으로 확장된다
#              → 멀티라인 코멘트를 TSV 한 줄로 표현·입력 가능(손수 jira 호출 불필요).
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
# 예:
#   printf 'AVMC-1\t1h 36m\t2026-05-27 09:53:00\tcal 실패마커 6/2/1 전환\n' \
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

# "1h 36m" / "2h" / "45m" / "1d 2h" → 분(정수). 알 수 없는 토큰은 무시.
# ⚠ 숫자부를 산술 전에 정수로 검증한다 — bash 산술은 a[$(cmd)] 형태 명령치환을
#    평가하므로, 미검증 입력을 $(()) 에 넣으면 명령 인젝션이 된다.
to_min() {
  local total=0 tok num mult
  for tok in $1; do
    case "$tok" in
      *d) num=${tok%d}; mult=480 ;;   # 1d=8h
      *h) num=${tok%h}; mult=60 ;;
      *m) num=${tok%m}; mult=1 ;;
      *)  continue ;;
    esac
    case "$num" in ''|*[!0-9]*) continue ;; esac   # 숫자만 허용
    total=$((total + num*mult))
  done
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
  if [ "$KEY" = "-" ] || [ -z "${TIME// }" ]; then
    echo "SKIP  (키 미정/시간 없음)  ${COMMENT:-}"
    skip=$((skip+1)); continue
  fi
  # KEY 형식 검증(선두 영숫자 앵커로 '--flag' 형태 argv 인젝션 차단).
  case "$KEY" in
    [A-Za-z0-9]*-[0-9]*) ;;
    *) echo "SKIP  (잘못된 이슈키: $KEY)"; skip=$((skip+1)); continue ;;
  esac

  # 30분(=ROUND) 단위 반올림. 원본과 다르면 표시용으로 보관.
  orig_min=$(to_min "$TIME")
  rnd_min=$(round_min "$orig_min")
  TIME=$(min_to_jira "$rnd_min")
  rnd_note=""
  [ "$rnd_min" -ne "$orig_min" ] && rnd_note="  (원본 $(min_to_jira "$orig_min") → ${ROUND}m단위)"

  # 시작시각도 ROUND분 그리드로 반올림 (예: 09:53 → 10:00).
  orig_started="$STARTED"
  STARTED=$(round_started "$STARTED")
  [ "$STARTED" != "$orig_started" ] && rnd_note="${rnd_note}  (시작 ${orig_started##* } → ${STARTED##* })"

  # 같은 날 내 기존 워크로그와 겹치지 않게 빈 슬롯으로 배치.
  # STARTED 파싱 실패 시(l2e rc!=0) 겹침회피를 건너뛰어 원본 STARTED 를 그대로 둔다.
  if [ "$NOOVL" -eq 1 ] && s_epoch=$(l2e "$STARTED"); then
    ensure_busy "${STARTED%% *}"
    new_epoch=$(place_no_overlap "$s_epoch" "$((rnd_min*60))")
    if [ "$new_epoch" -ne "$s_epoch" ]; then
      moved_from="${STARTED##* }"
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
  # bash ${//} glob·sed 는 환경별 백슬래시 처리가 제각각이라, 이식성 좋은 printf %b 사용.
  COMMENT_ML=$(printf '%b' "$COMMENT")
  cline=$(printf '%s\n' "$COMMENT_ML" | grep -c '^')
  c_first=${COMMENT_ML%%$'\n'*}
  ml_note=""; [ "$cline" -gt 1 ] && ml_note="  (${cline}줄)"

  if [ "$APPLY" -eq 1 ]; then
    args=("$KEY" "$TIME" --started "$started_arg" ${tz_args[@]+"${tz_args[@]}"} --comment "$COMMENT_ML" --no-input)
    [ -n "$PROJECT" ] && args=(-p "$PROJECT" "${args[@]}")
    if jira issue worklog add "${args[@]}" >/dev/null 2>"$errf"; then
      echo "OK    $KEY  $TIME  @${STARTED}  — ${c_first}${ml_note}${rnd_note}"
      ok=$((ok+1))
    else
      echo "FAIL  $KEY  $TIME  : $(tr '\n' ' ' <"$errf")"
      fail=$((fail+1))
    fi
  else
    proj_prefix=""
    [ -n "$PROJECT" ] && proj_prefix="-p $(sq "$PROJECT") "
    tz_show=""; [ "${#tz_args[@]}" -gt 0 ] && tz_show=" --timezone $(sq "$TZ_IANA")"
    # dry-run 은 한 줄로 미리보기(멀티라인은 첫 줄 + 줄 수 표기). 실제 apply 는 전체 확장.
    printf 'DRY   jira issue worklog add %s%s %s --started %s%s --comment %s --no-input%s%s\n' \
      "$proj_prefix" "$(sq "$KEY")" "$(sq "$TIME")" "$(sq "$started_arg")" "$tz_show" "$(sq "$c_first")" "$ml_note" "$rnd_note"
  fi
done

echo "---"
if [ "$APPLY" -eq 1 ]; then
  echo "결과: 입력 $n건 → OK=$ok SKIP=$skip FAIL=$fail"
  [ "$fail" -gt 0 ] && exit 1 || true
else
  echo "(dry-run) 대상 $n건, SKIP=$skip. 실제 입력하려면 동일 입력에 --apply 를 붙인다."
fi
