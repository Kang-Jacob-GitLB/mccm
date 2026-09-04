#!/usr/bin/env bash
# _jira.sh — jira 공통 헬퍼 (config 파싱·프로젝트 자동해결·후보/워크로그 조회).
#            prep.sh / jira_worklog.sh 가 source 한다.
#
# 배경: jira-cli 의 기본 프로젝트가 빈 문자열로 읽히는 환경이 있어
#   `jira issue list --jql ...` 가 `project ""` 로 빈 결과를 낸다(겹침회피·후보조회 무력화).
#   → 모든 조회에서 프로젝트 키를 config 에서 해결해 `-p` 로 명시한다.
#
# 모든 함수는 자격(jira config + JIRA_API_TOKEN) / 도구(jira·curl·jq) 부재 시
# 조용히 빈 출력으로 degrade 한다(에러로 호출부를 죽이지 않는다).

JIRA_CFG="${JIRA_CFG:-$HOME/.config/.jira/.config.yml}"

# server/login 을 전역(JIRA_SERVER/JIRA_LOGIN)에 로드. 둘 다 있으면 rc0.
jira_load_cfg() {
  [ -f "$JIRA_CFG" ] || return 1
  JIRA_SERVER=$(grep -E '^server:' "$JIRA_CFG" 2>/dev/null | head -1 | sed -E 's/^server:[[:space:]]*//; s/"//g; s/\r//g') || true
  JIRA_LOGIN=$(grep -E '^login:'  "$JIRA_CFG" 2>/dev/null | head -1 | sed -E 's/^login:[[:space:]]*//; s/"//g; s/\r//g') || true
  [ -n "${JIRA_SERVER:-}" ] && [ -n "${JIRA_LOGIN:-}" ] || return 1
  JIRA_SERVER="${JIRA_SERVER%/}"                 # 후행 슬래시 → "//rest" 이중 슬래시 방지
  # Basic 자격을 평문으로 흘리지 않는다 — https 가 아니면 토큰을 보내지 않고 물러난다.
  # 이 파일의 계약대로 호출부를 죽이지 않고 조용히 degrade 하되, 이유는 1 회 알린다.
  case "$(printf '%s' "$JIRA_SERVER" | tr 'A-Z' 'a-z')" in
    https://*) ;;
    *) [ -n "${_JIRA_SCHEME_WARNED:-}" ] || {
         echo "WARN: jira config 의 server 가 https:// 가 아니라 Jira 조회를 건너뛴다 (Basic 자격 평문 전송 방지)." >&2
         _JIRA_SCHEME_WARNED=1
       }
       return 1 ;;
  esac
}

# 프로젝트 키 해결: $1(명시) > config flat 'project: KEY' > nested 'project:\n  key: KEY'.
jira_project() {
  if [ -n "${1:-}" ]; then printf '%s' "$1"; return 0; fi
  [ -f "$JIRA_CFG" ] || return 0
  local p=""
  p=$(grep -E '^project:[[:space:]]*[A-Za-z0-9_]' "$JIRA_CFG" 2>/dev/null | head -1 \
        | sed -E 's/^project:[[:space:]]*//; s/"//g; s/\r//g') || true
  if [ -z "$p" ]; then
    p=$(awk '/^project:/{f=1;next}
             f&&/^[[:space:]]+key:/{sub(/^[[:space:]]+key:[[:space:]]*/,"");gsub(/"|\r/,"");print;exit}
             f&&/^[^[:space:]#]/{exit}' "$JIRA_CFG" 2>/dev/null) || true
  fi
  printf '%s' "$p"
}

# REST GET (Basic auth). $1=path. 자격 없으면 rc1 + 빈 출력.
# ⚠ Authorization 헤더를 argv 가 아닌 stdin(-H @-)으로 넘긴다 — argv 는 같은 호스트의
#    ps/proc cmdline 에 노출되므로(base64 는 인코딩일 뿐) 토큰이 새지 않게 한다.
jira_rest() {
  jira_load_cfg || return 1
  [ -n "${JIRA_API_TOKEN:-}" ] || return 1
  command -v curl >/dev/null 2>&1 && command -v base64 >/dev/null 2>&1 || return 1
  local auth; auth=$(printf '%s:%s' "$JIRA_LOGIN" "$JIRA_API_TOKEN" | base64 -w0)
  printf 'Authorization: Basic %s\n' "$auth" \
    | curl -s -H @- -H "Accept: application/json" "$JIRA_SERVER$1" 2>/dev/null
}

# 한 이슈의 내 당일 워크로그 → "startedISO<TAB>timeSpent<TAB>timeSpentSeconds" 줄들.
# $1=KEY $2=YYYY-MM-DD
# ⚠ Windows(MSYS) 의 jq -r 는 줄 끝에 CR(\r) 을 붙이는 경우가 있어, 마지막 필드를
#    숫자로 쓰면 arithmetic 오류가 난다 → tr 로 CR 제거 후 반환한다.
jira_issue_worklogs() {
  jira_load_cfg || return 0
  command -v jq >/dev/null 2>&1 || return 0
  jira_rest "/rest/api/3/issue/$1/worklog" \
    | jq -r --arg me "$JIRA_LOGIN" --arg day "$2" '.worklogs[]?
        | select((.author.emailAddress // "")==$me)
        | select(.started|startswith($day))
        | "\(.started)\t\(.timeSpent)\t\(.timeSpentSeconds)"' 2>/dev/null \
    | tr -d '\r' || true
}

# 당일 내 워크로그가 있는 이슈 키들(공백 구분 1열). $1=YYYY-MM-DD $2=PROJECT(옵션).
jira_worklog_issues() {
  command -v jira >/dev/null 2>&1 || return 0
  local day="$1" proj; proj=$(jira_project "${2:-}")
  jira issue list ${proj:+-p "$proj"} \
      --jql "worklogAuthor = currentUser() AND worklogDate = \"$day\"" \
      --plain --no-headers --columns KEY --paginate 0:50 2>/dev/null \
    | sed -E 's/\x1b\[[0-9;]*m//g' | tr -d ' \r' || true
}

# 워크로그 후보 이슈(활성 우선 + 최근접근, KEY 중복제거). $1=PROJECT(옵션).
# 출력: jira --plain 한 줄(KEY STATUS SUMMARY ...).
jira_candidates() {
  command -v jira >/dev/null 2>&1 || return 0
  local proj me; proj=$(jira_project "${1:-}"); me=$(jira me 2>/dev/null) || true
  { jira issue list ${proj:+-p "$proj"} ${me:+-a "$me"} -q "statusCategory != Done" \
       --order-by updated --reverse --plain --no-headers \
       --columns KEY,STATUS,SUMMARY --paginate 0:20 2>/dev/null
    jira issue list ${proj:+-p "$proj"} --history \
       --plain --no-headers --columns KEY,STATUS,SUMMARY --paginate 0:15 2>/dev/null
  } | sed -E 's/\x1b\[[0-9;]*m//g; s/[[:space:]]+$//' | awk 'NF{k=$1; if(!seen[k]++) print}' || true
}
