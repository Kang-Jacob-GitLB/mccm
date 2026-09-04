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
# 출력 섹션: PROFILE / ISSUE(옵션) / ACTIVITY(prompts) / COMMITS / JIRA_CANDIDATES / WORKLOGS_TODAY.
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
