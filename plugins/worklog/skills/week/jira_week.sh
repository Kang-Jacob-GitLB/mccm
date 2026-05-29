#!/usr/bin/env bash
# jira_week.sh — 한 주(기본: 이번 주 월~오늘, KST) 동안 내가 등록한 Jira 워크로그를
#   조회·집계해 JSONL + 결정적 요약으로 출력한다. 노션 등 주간보고 텍스트의 입력 데이터.
#
# ⚠ 읽기 전용 — 워크로그를 입력/수정/삭제하지 않는다(REST GET + jira issue list 만 사용).
#
# 출력(stdout) 2단:
#   1) 워크로그 레코드 JSONL (1줄=1워크로그). comment 는 ADF 를 평탄화한 텍스트:
#      {"date","key","summary","status","started","seconds","time","comment"}
#   2) "===SUMMARY===" 구분선 후 결정적 집계(기간/총합/이슈별/일자별) — 사람이 읽는 텍스트.
#      (LLM 이 1)로 서술을 쓰고 2)로 정확한 시간 합계를 검증한다.)
#
# 사용법:
#   jira_week.sh                 # 이번 주 (월~오늘, KST)
#   jira_week.sh --last-week     # 지난 주 (지난 월~일)
#   jira_week.sh START END       # 명시적 범위 (YYYY-MM-DD YYYY-MM-DD, 양끝 포함)
# 옵션:
#   --tz <IANA>   기간 경계 해석 타임존 (기본 Asia/Seoul).
#   -h, --help
#
# 요구: jira CLI(설정 완료: `jira init` + config) · JIRA_API_TOKEN env · curl · jq · base64.
#   worklogAuthor=currentUser() 로 이슈를 찾고, 각 이슈의 /rest/api/3/issue/{key}/worklog
#   를 조회해 내 계정(accountId/emailAddress) + 기간 내 워크로그만 추린다.
set -euo pipefail

TZ_IANA="Asia/Seoul"
LASTWK=0
POS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --last-week) LASTWK=1; shift ;;
    --tz)        TZ_IANA="${2:?--tz 인자 필요}"; shift 2 ;;
    -h|--help)   sed -n '2,/^set -/p' "$0" | sed '$d; s/^# \{0,1\}//'; exit 0 ;;
    -*)          echo "unknown arg: $1" >&2; exit 2 ;;
    *)           POS+=("$1"); shift ;;
  esac
done

# 의존 도구 확인 (필수)
for t in jira curl jq base64; do
  command -v "$t" >/dev/null 2>&1 || { echo "ERROR: '$t' 없음 — 요구사항(jira/curl/jq/base64) 설치 후 재시도." >&2; exit 1; }
done

# 공통 TZ 유틸 (tzdata 부재 환경에서도 날짜 경계가 9시간 어긋나지 않게).
. "$(dirname "${BASH_SOURCE[0]}")/_tz.sh"
tz_setup "$TZ_IANA"

valid_date() { case "$1" in [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) return 0 ;; *) return 1 ;; esac; }

# ── 기간 결정 ────────────────────────────────────────────────
TODAY="$(tz_today)"
if [ "${#POS[@]}" -ge 2 ]; then
  START="${POS[0]}"; END="${POS[1]}"
  valid_date "$START" && valid_date "$END" || { echo "ERROR: 날짜는 YYYY-MM-DD 형식 (받음: '$START' '$END')" >&2; exit 2; }
elif [ "${#POS[@]}" -eq 1 ]; then
  echo "ERROR: 명시적 범위는 START END 2개가 필요하다 (1개만 받음). 단일일은 'today' 스킬을 쓴다." >&2; exit 2
else
  # 이번 주 월요일(=오늘 - (요일-1)일). 요일 %u: 월=1..일=7.
  dow="$(date -d "$TODAY" +%u 2>/dev/null)" || { echo "ERROR: date -d 미지원 환경 — GNU date 필요." >&2; exit 1; }
  MON="$(date -d "$TODAY -$((dow-1)) days" +%F)"
  if [ "$LASTWK" -eq 1 ]; then
    START="$(date -d "$MON -7 days" +%F)"; END="$(date -d "$MON -1 day" +%F)"
  else
    START="$MON"; END="$TODAY"
  fi
fi
[ "$START" \> "$END" ] && { echo "ERROR: START($START) 가 END($END) 보다 늦다." >&2; exit 2; }

# ── Jira 인증/계정 ───────────────────────────────────────────
cfg="$HOME/.config/.jira/.config.yml"
[ -f "$cfg" ] || { echo "ERROR: jira config 없음 ($cfg). 먼저 'jira init' 로 서버/로그인 구성." >&2; exit 1; }
server=$(grep -E '^server:' "$cfg" | head -1 | sed -E 's/^server:[[:space:]]*//; s/"//g')
login=$(grep -E '^login:'  "$cfg" | head -1 | sed -E 's/^login:[[:space:]]*//; s/"//g')
[ -n "$server" ] && [ -n "$login" ] || { echo "ERROR: config 에서 server/login 파싱 실패." >&2; exit 1; }
[ -n "${JIRA_API_TOKEN:-}" ] || { echo "ERROR: JIRA_API_TOKEN env 미설정. (Atlassian API 토큰을 env 로 노출)" >&2; exit 1; }
auth=$(printf '%s:%s' "$login" "$JIRA_API_TOKEN" | base64 -w0)

api() {  # $1=경로(/rest/...) → stdout JSON. 실패해도 비치명적(빈 출력).
  curl -s -H "Authorization: Basic $auth" -H "Accept: application/json" "$server$1" 2>/dev/null || true
}

# 내 계정 식별(accountId 가 가장 신뢰도 높음; emailAddress 는 GDPR 로 가려질 수 있음).
myself=$(api "/rest/api/3/myself")
my_acct=$(printf '%s' "$myself"  | jq -r '.accountId // ""' 2>/dev/null || echo "")
my_email=$(printf '%s' "$myself" | jq -r '.emailAddress // ""' 2>/dev/null || echo "")
[ -n "$my_acct" ]  || my_acct="$login"    # 폴백
[ -n "$my_email" ] || my_email="$login"

# ── 기간 내 내 워크로그가 있는 이슈 조회 (jira-cli, JQL) ───────
# START/END 는 위에서 YYYY-MM-DD 로 검증됨 → JQL 삽입 안전.
jql="worklogAuthor = currentUser() AND worklogDate >= \"$START\" AND worklogDate <= \"$END\""
keys=$(jira issue list --jql "$jql" --plain --no-headers --columns KEY --paginate 0:100 2>/dev/null \
        | sed -E 's/\x1b\[[0-9;]*m//g' | tr -d ' \t' | sed '/^$/d' | sort -u || true)

TMP="$(mktemp)"; trap 'rm -f "$TMP"' EXIT

# 워크로그 정규화 jq (단일 인용 — bash 확장 없음; 동적 값은 전부 --arg).
read -r -d '' JQWL <<'JQ' || true
def adf2txt:
  if type=="string" then .
  elif type=="object" then
    if .type=="text" then (.text // "")
    elif .type=="hardBreak" then "\n"
    elif .type=="paragraph" then ((.content // []) | map(adf2txt) | join("")) + "\n"
    else ((.content // []) | map(adf2txt) | join("")) end
  elif type=="array" then (map(adf2txt) | join(""))
  else "" end;
.worklogs[]?
| select(((.author.accountId // "")==$acct)
         or ((.author.emailAddress // "")!="" and (.author.emailAddress // "")==$email))
| (.started[0:10]) as $d
| select($d >= $s and $d <= $e)
| { date:$d, key:$key, summary:$summary, status:$status,
    started:.started, seconds:(.timeSpentSeconds // 0), time:(.timeSpent // ""),
    comment:((.comment // "") | adf2txt | gsub("\n+";" / ") | gsub("^ */ *| */ *$";"")) }
JQ

set -f   # $keys 워드 분할 시 글롭 확장 방지(키에 *,?,[ 가 와도 파일명 확장 안 함)
for k in $keys; do
  [ -n "$k" ] || continue
  # 이슈 요약/상태 (REST — jira-cli plain 파싱보다 신뢰도 높음)
  meta=$(api "/rest/api/3/issue/$k?fields=summary,status")
  summary=$(printf '%s' "$meta" | jq -r '.fields.summary // ""' 2>/dev/null || echo "")
  status=$(printf '%s'  "$meta" | jq -r '.fields.status.name // ""' 2>/dev/null || echo "")
  # 해당 이슈에서 내 계정 + 기간 내 워크로그만 정규화해 emit
  api "/rest/api/3/issue/$k/worklog" \
    | jq -c --arg key "$k" --arg summary "$summary" --arg status "$status" \
           --arg acct "$my_acct" --arg email "$my_email" --arg s "$START" --arg e "$END" \
           "$JQWL" 2>/dev/null >> "$TMP" || true
done
set +f

# ── 출력 1단: 레코드 JSONL (started 기준 정렬) ────────────────
jq -c -s 'sort_by(.started)[]' "$TMP" 2>/dev/null || true

# ── 출력 2단: 결정적 집계 ────────────────────────────────────
sec2hm() { local s=${1:-0} h m o=""; h=$((s/3600)); m=$(((s%3600)/60)); [ "$h" -gt 0 ] && o="${h}h"; [ "$m" -gt 0 ] && o="${o:+$o }${m}m"; echo "${o:-0m}"; }
wd() { local u; u=$(date -d "$1" +%u 2>/dev/null) || { echo "?"; return; }; local a=(월 화 수 목 금 토 일); echo "${a[$((u-1))]}"; }

echo "===SUMMARY==="
echo "기간: ${START}($(wd "$START")) ~ ${END}($(wd "$END"))"

total_sec=$(jq -s 'map(.seconds)|add // 0' "$TMP" 2>/dev/null || echo 0)
n_issue=$(jq -s '[.[].key]|unique|length' "$TMP" 2>/dev/null || echo 0)
n_day=$(jq -s '[.[].date]|unique|length' "$TMP" 2>/dev/null || echo 0)
n_wl=$(jq -s 'length' "$TMP" 2>/dev/null || echo 0)

if [ "${n_wl:-0}" -eq 0 ]; then
  echo "(이 기간에 내가 등록한 Jira 워크로그가 없다.)"
  exit 0
fi

echo "총합: $(sec2hm "$total_sec") · 이슈 ${n_issue}건 · 근무일 ${n_day}일 · 워크로그 ${n_wl}건"
echo
echo "[이슈별] (시간 내림차순)"
jq -r -s 'group_by(.key)
          | map({key:.[0].key, summary:.[0].summary, status:.[0].status,
                 sec:(map(.seconds)|add), cnt:length})
          | sort_by(-.sec)[]
          | "\(.key)\t\(.sec)\t\(.cnt)\t\(.status)\t\(.summary)"' "$TMP" 2>/dev/null \
  | while IFS=$'\t' read -r key sec cnt status summary; do
      printf '  %-18s %-8s (%s건)  %-12s %s\n' "$key" "$(sec2hm "$sec")" "$cnt" "${status:-?}" "$summary"
    done
echo
echo "[일자별]"
jq -r -s 'group_by(.date)
          | map({date:.[0].date, sec:(map(.seconds)|add), cnt:length})
          | sort_by(.date)[]
          | "\(.date)\t\(.sec)\t\(.cnt)"' "$TMP" 2>/dev/null \
  | while IFS=$'\t' read -r d sec cnt; do
      printf '  %s(%s)  %-8s (%s건)\n' "$d" "$(wd "$d")" "$(sec2hm "$sec")" "$cnt"
    done
