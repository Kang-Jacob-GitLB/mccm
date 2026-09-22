#!/usr/bin/env bash
# prep.sh — 워크로그 작성에 필요한 데이터를 1회 호출·동시 수집으로 산출.
#
# 트랜스크립트 활동(collect.sh, 느림)과 jira 조회(후보·당일 워크로그)를 백그라운드
# 병렬 실행한 뒤, LLM 이 바로 워크로그 가안을 쓸 수 있는 압축 리포트를 섹션별로 낸다.
# 이 스크립트가 시각변환(_tz.sh)·cwd basename·프로젝트 해결·토큰 상한을 모두 처리하므로
# 호출부(LLM)는 ad-hoc jq/awk/date 를 다시 짤 필요가 없다(= 정규식 버그·왕복·토큰 절감).
#
# 사용법:
#   prep.sh [DATE] [--since HH:MM] [--until HH:MM] [--issue KEY] [--project KEY] [--max N]
#     DATE        대상일 YYYY-MM-DD (기본 오늘 KST).
#     --since/--until  대상일 내 시간대 한정(로컬 HH:MM).
#     --issue KEY 그 이슈 상세를 ## ISSUE 섹션에 포함(워크로그 대상 확인용).
#     --project KEY  jira 프로젝트 키(미지정 시 config 에서 자동 해결).
#     --max N      섹션당 최대 줄수(기본 60, 토큰 방어).
#     -h|--help
#
# 출력 섹션: PROFILE / ISSUE(옵션) / CALENDAR(회의) / ACTIVITY(prompts) / COMMITS /
#            JIRA_CANDIDATES / WORKLOGS_TODAY.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/_tz.sh"
. "$DIR/_jira.sh"
. "$DIR/_profile.sh"

DATE="" SINCE="" UNTIL="" ISSUE="" PROJECT="" MAX=60
while [ $# -gt 0 ]; do
  case "$1" in
    --since)   SINCE="${2:?}"; shift 2 ;;
    --until)   UNTIL="${2:?}"; shift 2 ;;
    --issue)   ISSUE="${2:?}"; shift 2 ;;
    --project) PROJECT="${2:?}"; shift 2 ;;
    --max)     MAX="${2:?}"; shift 2 ;;
    -h|--help) sed -n '2,/^set -/p' "$0" | sed '$d; s/^# \{0,1\}//'; exit 0 ;;
    -*) echo "unknown arg: $1" >&2; exit 2 ;;
    *)  DATE="$1"; shift ;;
  esac
done

command -v jq >/dev/null 2>&1 || { echo "ERROR: jq 없음" >&2; exit 1; }
tz_setup "Asia/Seoul" >/dev/null 2>&1
[ -n "$DATE" ] || DATE="$(tz_today)"

# 입력 검증(셸/JQL 인젝션 차단) — DATE/시각/이슈키/프로젝트 형식 강제.
case "$DATE" in [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) ;; *) echo "잘못된 날짜: $DATE" >&2; exit 2 ;; esac
for v in "$SINCE" "$UNTIL"; do
  case "$v" in ""|[0-2][0-9]:[0-5][0-9]) ;; *) echo "잘못된 시각(HH:MM): $v" >&2; exit 2 ;; esac
done
# 전체 매칭으로 검증(후행 잔여문자 차단) — 빈 값은 허용.
[ -z "$ISSUE" ]   || [[ "$ISSUE"   =~ ^[A-Za-z0-9]+-[0-9]+$ ]] || { echo "잘못된 이슈키: $ISSUE" >&2; exit 2; }
[ -z "$PROJECT" ] || [[ "$PROJECT" =~ ^[A-Za-z0-9_]+$ ]]       || { echo "잘못된 프로젝트키: $PROJECT" >&2; exit 2; }
case "$MAX"     in *[!0-9]*|"") MAX=60 ;; esac

# 캘린더 조회창에 쓸 UTC 오프셋(±HH:MM).
# ⚠ TZ_OFF 를 그대로 쓰면 안 된다 — 그건 "대상 존의 오프셋"이 아니라 "strftime 에 더할
# 가산 보정값"이라 native 모드(tzdata 있음)에서는 0 이다(_tz.sh:44). 0 을 쓰면 조회창이
# UTC 자정 기준이 돼 오전 회의가 통째로 빠지고 다음날 새벽 건이 딸려 온다.
if [ "${TZ_MODE:-native}" = native ]; then
  CAL_Z="$(date -d "$DATE 12:00:00" +%z 2>/dev/null || true)"  # TZ export 됨 → DST 까지 반영
else
  CAL_Z="$(tz_offset_str)"                                     # "+0900"
fi
case "$CAL_Z" in [+-][0-9][0-9][0-9][0-9]) ;; *) CAL_Z="+0900" ;; esac
CAL_OFF="${CAL_Z:0:3}:${CAL_Z:3:2}"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# ── 동시 수집: 트랜스크립트(느림) ∥ jira 후보 ∥ 당일 워크로그 ∥ 이슈상세 ──
"$DIR/collect.sh" "$DATE" ${SINCE:+--since "$SINCE"} ${UNTIL:+--until "$UNTIL"} \
  > "$TMP/act.jsonl" 2>/dev/null &
jira_candidates "$PROJECT" > "$TMP/cand.tsv" 2>/dev/null &
(
  : > "$TMP/wl.tsv"
  for k in $(jira_worklog_issues "$DATE" "$PROJECT"); do
    [ -n "$k" ] || continue
    jira_issue_worklogs "$k" "$DATE" | sed "s/^/${k}\t/" >> "$TMP/wl.tsv"
  done
) &
if [ -n "$ISSUE" ]; then
  jira issue view "$ISSUE" --plain 2>/dev/null \
    | sed -E 's/\x1b\[[0-9;]*m//g' | sed -E '/^[[:space:]]*$/d' | head -22 > "$TMP/issue.txt" &
fi
# 회의(Google Calendar via gws). 실패해도 전체를 멈추지 않되, 왜 비었는지를 마커로 남긴다 —
# 조용히 스킵하면 호출부(LLM)가 "회의 없음"과 "조회 실패"를 구분하지 못해 매번 누락된다.
(
  # fail-closed: 먼저 실패로 찍어 두고 성공 경로에서만 덮는다. 중간에 죽어 파일이 없으면
  # 아래 출력부가 빈 문자열을 "회의 없음"으로 읽어, 이 수정이 없애려던 혼동이 되살아난다.
  echo "__GWSFAIL__" > "$TMP/cal.tsv"
  if ! command -v gws >/dev/null 2>&1; then
    echo "__NOGWS__" > "$TMP/cal.tsv"
  else
    # timeZone 을 지정해 타 타임존에서 만든 초대도 캘린더 TZ 로 정규화시킨다 —
    # 안 그러면 응답이 Z 로 와서 아래 substr 이 UTC 시각을 "로컬시각"이라 찍는다.
    CAL_PARAMS="$(jq -nc --arg d "$DATE" --arg o "$CAL_OFF" --arg tz "${TZ_NAME:-Asia/Seoul}" \
      '{calendarId:"primary",timeMin:($d+"T00:00:00"+$o),timeMax:($d+"T23:59:59"+$o),
        timeZone:$tz,singleEvents:true,orderBy:"startTime",maxResults:50}')"
    # gws 는 stdout=JSON, stderr=keyring 배너 → stderr 는 버린다. stdin 은 닫는다
    # (인증 프롬프트가 뜨면 아래 wait 가 영원히 멈춘다).
    if ! gws calendar events list --format json --params "$CAL_PARAMS" \
           > "$TMP/cal.json" 2>/dev/null </dev/null; then
      echo "__GWSFAIL__" > "$TMP/cal.tsv"
    elif ! jq -e 'has("items")' "$TMP/cal.json" >/dev/null 2>&1; then
      # 200 으로 온 오류 응답(미인증 등)에 .items 가 없다 — 빈 일정과 혼동하면 안 된다.
      echo "__GWSFAIL__" > "$TMP/cal.tsv"
    else
      # 종일 일정(.start.date)과 본인이 거절(declined)한 건은 제외.
      # 제목은 외부인이 보낸 초대에서 온 문자열이다 — 제어문자(ESC·VT·FF·잔여 CR)와
      # 유니코드 줄바꿈류(U+0085·U+2028·U+2029)를 없애고 길이를 잘라 낸다
      # (ACTIVITY 110자·PROFILE 300자와 같은 취지).
      # [[:cntrl:]] 만으로는 U+2028 이 남아 [[:space:]] 를 겹쳐 쓴다(실측 확인).
      # \uXXXX 이스케이프를 쓰지 않는 이유: 원시 바이트로 저장되면 grep 에 안 걸려
      # 조용히 지워져도 아무 테스트가 실패하지 않는다(e34b9e4 의 리터럴 CR 과 같은 함정).
      # 자르기는 jq 에서 한다 — 코드포인트 단위라 한글이 중간에서 깨지지 않는다.
      jq -r '.items[]? | select((.start.dateTime//null)!=null)
             | select([.attendees[]?|select(.self==true)|.responseStatus]|(index("declined")|not))
             | [(.start.dateTime),(.end.dateTime),
                ((.summary // "(제목없음)")
                   | gsub("[[:cntrl:][:space:]]+";" ")
                   | .[0:120])]
             | @tsv' "$TMP/cal.json" > "$TMP/cal.tsv" 2>/dev/null \
        || echo "__GWSFAIL__" > "$TMP/cal.tsv"
    fi
  fi
) &
wait 2>/dev/null || true

# ── 출력(압축) ──
WIN="$DATE"; [ -n "$SINCE" ] && WIN="$WIN ${SINCE}~"; [ -n "$UNTIL" ] && WIN="$WIN~${UNTIL}"
printf '# WORKLOG PREP · %s\n' "$WIN"

# 개인 프로필(있으면). 설정이 없어도 항상 같은 형태로 낸다 — 섹션이 조건부로
# 나타났다 사라지면 SKILL.md 의 출력 섹션 목록과 실제가 어긋난다.
printf '\n'
wp_render || true

if [ -n "$ISSUE" ] && [ -s "$TMP/issue.txt" ]; then
  printf '\n## ISSUE %s\n' "$ISSUE"; cat "$TMP/issue.txt"
fi

# CALENDAR: 회의는 워크로그의 1급 항목이다. 조회 성공·일정 없음·조회 실패를 구분해
# 항상 출력한다 — 섹션이 사라지면 호출부가 회의를 통째로 빠뜨린다(반복 발생한 결함).
printf '\n## CALENDAR (회의 · 로컬시각 — 워크로그에 반드시 계상)\n'
CAL_HEAD="$(head -n1 "$TMP/cal.tsv" 2>/dev/null || true)"
case "$CAL_HEAD" in
  __NOGWS__)
    # 실행 가능한 명령을 그대로 적지 않는다 — Bash 를 쥔 호출부가 도구 출력의 명령을
    # 그대로 실행하는 실패 모드가 있고, 전역 npm 설치는 사용자 확인이 필요한 쓰기다.
    echo "(gws 미설치 — 회의 병합 생략. 사용자가 직접 설치·인증할 것: npm 패키지 @googleworkspace/cli 설치 후 gws 로그인)" ;;
  __GWSFAIL__)
    echo "(gws 조회 실패 — 미인증이거나 API 오류. 'gws auth login' 확인 필요)" ;;
  "")
    echo "(회의 없음 — 캘린더 조회는 성공, 해당일 일정 없음)" ;;
  *)
    awk -F'\t' '{ printf "%s-%s  %s\n", substr($1,12,5), substr($2,12,5), $3 }' \
      "$TMP/cal.tsv" | head -n "$MAX" ;;
esac

# ACTIVITY: 로컬 HH:MM + cwd basename(역슬래시/슬래시 양쪽 처리) + prompt(평탄화·110자).
# 시각변환은 awk strftime(epoch+TZ_OFF) — timeline.sh 와 동일(native:OFF0+TZ=IANA, offset:OFF+TZ=UTC).
printf '\n## ACTIVITY (prompts · 로컬시각)\n'
jq -r 'select(.event=="prompt")
       | [.epoch,(.cwd//""),((.prompt//"")|gsub("[\r\n\t]+";" "))] | @tsv' "$TMP/act.jsonl" \
  | awk -F'\t' -v OFF="${TZ_OFF:-0}" '
      { e=$1+OFF; cwd=$2; gsub(/\\/,"/",cwd); n=split(cwd,a,"/"); base=a[n]
        pr=$3; if(length(pr)>110) pr=substr(pr,1,110)
        printf "%s  [%s] %s\n", strftime("%H:%M",e), base, pr }' \
  | head -n "$MAX"

printf '\n## COMMITS\n'
jq -r 'select(.event=="commit")
       | [.epoch,(.sha//""),(.branch//""),((.subject//"")|gsub("[\r\n\t]+";" "))] | @tsv' "$TMP/act.jsonl" \
  | awk -F'\t' -v OFF="${TZ_OFF:-0}" '
      { e=$1+OFF; printf "%s  %s [%s] %s\n", strftime("%H:%M",e), substr($2,1,7), $3, $4 }' \
  | head -n "$MAX"

printf '\n## JIRA_CANDIDATES (활성 우선; 완료티켓엔 워크로그 부적절)\n'
if [ -s "$TMP/cand.tsv" ]; then head -n "$MAX" "$TMP/cand.tsv"; else echo "(없음/조회불가)"; fi

# WORKLOGS_TODAY: 겹침회피 참고. started ISO 의 +0900 로컬 wall-time HH:MM 를 문자열에서 추출.
printf '\n## WORKLOGS_TODAY (KEY 시작 시간 · 겹침회피 참고)\n'
if [ -s "$TMP/wl.tsv" ]; then
  while IFS=$'\t' read -r k started spent secs; do
    [ -n "$k" ] || continue
    printf '%s  %s  %s\n' "$k" "${started:11:5}" "$spent"
  done < "$TMP/wl.tsv" | sort -k2
else
  echo "(없음/조회불가 — 자격 없거나 당일 워크로그 없음)"
fi
