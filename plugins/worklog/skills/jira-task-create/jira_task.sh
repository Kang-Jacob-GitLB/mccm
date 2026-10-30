#!/usr/bin/env bash
# jira_task.sh — jira-task-create 스킬의 Jira REST 도구 (조회 + 승인 후 생성).
#
# 사용:  jira_task.sh <subcommand> [args...]
#   me                         내 accountId·표시명
#   profile                    로컬 프로필(~/.config/mccm/jira-task.json) JSON. 없으면 {}
#   issue KEY...               이슈 필드 요약(JSON 1줄/이슈) — 에픽·참고 티켓·생성 검증 공용
#   resolve NUM [PROJ...]      번호만 받은 티켓 → PROJ-NUM 후보를 각각 GET(404 는 건너뜀)
#   epics [DAYS]               에픽 추천 후보 TSV (최근 DAYS일 내 담당 티켓의 parent + 프로필 프로젝트 미완료 에픽)
#   children EPIC              에픽 아래 내 담당 티켓 TSV (중복 생성 확인)
#   createmeta PROJ [TYPE]     생성 화면 필드 TSV (fieldId·필수·이름) — 기본 TYPE=작업
#   bizdays START END          양끝 포함 영업일 수(주말만 제외)
#   create --confirm FILE      ⚠ 외부 쓰기. 승인받은 payload JSON 을 POST /rest/api/3/issue
#   epictype PROJ              프로젝트의 에픽 이슈 유형 "name<TAB>id" (jira-epic-create 용)
#   create-epic --confirm FILE ⚠ 외부 쓰기. parent 없는 에픽 payload 를 POST (유형이 에픽인지 사전 검사)
#   editmeta KEY               편집 화면 필드 TSV — 생성 화면에 없는 필드를 생성 후 넣을 수 있는지 확인
#   update --confirm KEY FILE  ⚠ 외부 쓰기. {"fields":{...}} 를 PUT (생성 화면에 없던 필드 보충)
#   transitions KEY           가능한 상태 전환 목록 TSV
#   transition --confirm KEY ID  ⚠ 외부 쓰기. 상태 전환
#
# 인증·서버는 ../today/_jira.sh 의 jira_load_cfg(~/.config/.jira/.config.yml, https 강제)와
# JIRA_API_TOKEN env 를 쓴다. 토큰은 argv 가 아니라 stdin(-H @-)으로만 curl 에 넘긴다.
# JIRA_API_TOKEN 은 로그인 셸에서만 잡히므로 `bash -lc` 로 실행한다.
# 결과 출력은 항상 CR 을 제거한다(Windows jq 가 줄 끝에 \r 을 붙이는 경우 대비).

set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../today/_jira.sh
. "$HERE/../today/_jira.sh" || { echo "ERROR: ../today/_jira.sh 를 찾지 못했다 (worklog 플러그인 설치 확인)" >&2; exit 1; }

command -v jq >/dev/null 2>&1 || { echo "ERROR: jq 필요" >&2; exit 1; }

KEY_RE='^[A-Z][A-Z0-9_]+-[0-9]+$'
PROJ_RE='^[A-Z][A-Z0-9_]+$'
DATE_RE='^[0-9]{4}-[0-9]{2}-[0-9]{2}$'

die() { echo "ERROR: $*" >&2; exit 1; }
need_key()  { [[ "$1" =~ $KEY_RE ]]  || die "이슈 키 형식이 아니다: '$1' (예: ABC-123)"; }
need_proj() { [[ "$1" =~ $PROJ_RE ]] || die "프로젝트 키 형식이 아니다: '$1'"; }

# ── 프로필 ────────────────────────────────────────────────────────────────
jt_profile_path() {
  local c u
  for c in "${JIRA_TASK_PROFILE:-}" \
           "${XDG_CONFIG_HOME:+${XDG_CONFIG_HOME}/mccm/jira-task.json}" \
           "${HOME:+${HOME}/.config/mccm/jira-task.json}"; do
    [ -n "$c" ] && [ -f "$c" ] && { printf '%s' "$c"; return 0; }
  done
  if [ -n "${USERPROFILE:-}" ]; then
    u="$USERPROFILE"
    command -v cygpath >/dev/null 2>&1 && u="$(cygpath -u "$u")"
    [ -f "$u/.config/mccm/jira-task.json" ] && { printf '%s' "$u/.config/mccm/jira-task.json"; return 0; }
  fi
  return 1
}
jt_profile() {
  local p out
  p="$(jt_profile_path)" || { echo '{}'; return 0; }
  out="$(jq -c 'if type == "object" then . else error("not object") end' "$p" 2>/dev/null)" \
    || { echo "WARN: 프로필 JSON 이 손상돼 무시한다: $p" >&2; echo '{}'; return 0; }
  printf '%s\n' "$out" | tr -d '\r'
}
PROFILE="$(jt_profile)"
pf() { printf '%s' "$PROFILE" | jq -r "$1 // empty" | tr -d '\r'; }

# 커스텀 필드 ID — 기본값은 작성자 인스턴스 실측. 인스턴스마다 다르니 프로필 .fields 로 덮는다.
F_WS="$(pf '.fields.workspace')";   F_WS="${F_WS:-customfield_10192}"
F_REF="$(pf '.fields.reference')";  F_REF="${F_REF:-customfield_10091}"
F_START="$(pf '.fields.start')";    F_START="${F_START:-customfield_10015}"
F_END="$(pf '.fields.end')";        F_END="${F_END:-customfield_10082}"
F_LPE="$(pf '.fields.difficulty')"; F_LPE="${F_LPE:-customfield_10911}"
# JQL 의 issuetype 은 영문 기본 이름(Epic)으로만 매칭된다 — 표시 이름("에픽")은 0건이 된다(실측).
EPIC_TYPE="$(pf '.epic_issuetype')"; EPIC_TYPE="${EPIC_TYPE:-Epic}"

# ── REST ─────────────────────────────────────────────────────────────────
# jt_req METHOD PATH OUTFILE [DATAFILE] → stdout 에 HTTP 코드(타임아웃·연결실패는 000). 본문은 OUTFILE.
jt_req() {
  jira_load_cfg || die "jira config(server/login) 없음 또는 server 가 https 가 아니다: $JIRA_CFG"
  [ -n "${JIRA_API_TOKEN:-}" ] || die "JIRA_API_TOKEN 미설정 — 'bash -lc' 로 실행했는지 확인"
  command -v curl >/dev/null 2>&1 && command -v base64 >/dev/null 2>&1 || die "curl·base64 필요"
  local auth code
  auth=$(printf '%s:%s' "$JIRA_LOGIN" "$JIRA_API_TOKEN" | base64 -w0)
  if [ -n "${4:-}" ]; then
    code=$(printf 'Authorization: Basic %s\n' "$auth" \
      | curl -s --max-time 30 -o "$3" -w '%{http_code}' -X "$1" -H @- \
          -H 'Accept: application/json' -H 'Content-Type: application/json' \
          --data-binary "@$4" "$JIRA_SERVER$2")
  else
    code=$(printf 'Authorization: Basic %s\n' "$auth" \
      | curl -s --max-time 30 -o "$3" -w '%{http_code}' -X "$1" -H @- \
          -H 'Accept: application/json' "$JIRA_SERVER$2")
  fi
  printf '%s' "${code:-000}"
}

TMP="$(mktemp -d)" && [ -n "$TMP" ] || die "mktemp 실패"; trap 'rm -rf "$TMP"' EXIT

# GET → 본문 stdout. 2xx 가 아니면 에러 요약 후 rc1.
jt_get() {
  local code; code="$(jt_req GET "$1" "$TMP/body")"
  case "$code" in 2*) tr -d '\r' < "$TMP/body" ;;
    *) echo "ERROR: GET $1 → HTTP $code $(jq -c '{errorMessages, errors}' "$TMP/body" 2>/dev/null | tr -d '\r')" >&2; return 1 ;;
  esac
}
# JQL 검색(POST /search/jql — JQL 을 URL 에 싣지 않아 인코딩 사고가 없다). $1=JQL $2=fields(JSON 배열) $3=max
jt_search() {
  jq -n --arg jql "$1" --argjson f "$2" --argjson m "${3:-50}" \
     '{jql: $jql, fields: $f, maxResults: $m}' > "$TMP/q.json"
  local code; code="$(jt_req POST /rest/api/3/search/jql "$TMP/sr" "$TMP/q.json")"
  case "$code" in 2*) tr -d '\r' < "$TMP/sr" ;;
    *) echo "ERROR: JQL 검색 실패 HTTP $code: $(jq -c '{errorMessages, errors}' "$TMP/sr" 2>/dev/null | tr -d '\r')" >&2; return 1 ;;
  esac
}

ISSUE_FIELDS="summary,status,project,issuetype,parent,assignee,priority,labels,duedate,timetracking,$F_WS,$F_REF,$F_START,$F_END,$F_LPE"
issue_summary_jq() {
  jq -c --arg ws "$F_WS" --arg ref "$F_REF" --arg st "$F_START" --arg en "$F_END" --arg lpe "$F_LPE" '
    {key, summary: .fields.summary, status: .fields.status.name,
     project: {key: .fields.project.key, id: .fields.project.id},
     issuetype: {name: .fields.issuetype.name, id: .fields.issuetype.id},
     parent: .fields.parent.key,
     assignee: {name: .fields.assignee.displayName, accountId: .fields.assignee.accountId},
     priority: .fields.priority.name, labels: .fields.labels,
     originalEstimate: .fields.timetracking.originalEstimate,
     start: .fields[$st], duedate: .fields.duedate, end: .fields[$en],
     workspace: (.fields[$ws] | if . then {id, key, name} else null end),
     reference: [.fields[$ref][]? | {name: .displayName, accountId}],
     difficulty: (.fields[$lpe] | if . then {id, value} else null end)}'
}

# 프로젝트의 에픽 이슈 유형 → "name\tid". hierarchyLevel 1 로 판정하고, 응답에 그 값이 없으면
# 프로필 epic_issuetype·"에픽" 이름으로 대신 찾는다(표시 이름이 인스턴스 언어를 따른다).
epic_type_of() {
  jt_get "/rest/api/3/issue/createmeta/$1/issuetypes?maxResults=50" \
    | jq -r --arg n "$EPIC_TYPE" '(.issueTypes // .values // []) as $t
        | ([$t[] | select(.hierarchyLevel == 1)] + [$t[] | select(.name == $n or .name == "에픽")])
        | first // empty | [.name, .id] | @tsv' | tr -d '\r' | grep . \
    || { echo "ERROR: $1 에서 에픽 이슈 유형을 찾지 못했다" >&2; return 1; }
}

cmd="${1:-}"; [ $# -gt 0 ] && shift
# 네트워크를 쓰는 명령은 자격을 먼저 확인한다 — jt_req 는 $(...) 안에서 돌아 die 가 호출부를 못 멈춘다.
case "$cmd" in
  ""|profile|bizdays) ;;
  *) jira_load_cfg || die "jira config(server/login) 없음 또는 server 가 https 가 아니다: $JIRA_CFG"
     [ -n "${JIRA_API_TOKEN:-}" ] || die "JIRA_API_TOKEN 미설정 — 'bash -lc' 로 실행했는지 확인" ;;
esac
case "$cmd" in
  me)
    jt_get /rest/api/3/myself | jq -c '{accountId, displayName}' | tr -d '\r' ;;

  profile)
    printf '%s\n' "$PROFILE" ;;

  issue)
    [ $# -ge 1 ] || die "사용: issue KEY..."
    for k in "$@"; do
      need_key "$k"
      jt_get "/rest/api/3/issue/$k?fields=$ISSUE_FIELDS" | issue_summary_jq | tr -d '\r'
    done ;;

  resolve)
    num="${1:-}"; [[ "$num" =~ ^[0-9]+$ ]] || die "사용: resolve NUM [PROJ...]"; shift
    projs=("$@")
    p="$(pf '.project')"; [ -n "$p" ] && projs+=("$p")
    while IFS= read -r p; do [ -n "$p" ] && projs+=("$p"); done < <(pf '.epic_projects[]?')
    [ ${#projs[@]} -gt 0 ] || die "후보 프로젝트가 없다 — 프로젝트 키를 인자로 주거나 프로필 .project 를 채워라"
    me_id="$(jt_get /rest/api/3/myself | jq -r '.accountId' | tr -d '\r')"
    found=0
    for p in $(printf '%s\n' "${projs[@]}" | awk '!s[$0]++'); do
      need_proj "$p"
      code="$(jt_req GET "/rest/api/3/issue/$p-$num?fields=summary,assignee,status" "$TMP/r")"
      case "$code" in
        2*) found=1
            jq -r --arg me "$me_id" '[.key, (if .fields.assignee.accountId == $me then "mine" else "other" end),
               .fields.status.name, .fields.summary] | @tsv' "$TMP/r" | tr -d '\r' ;;
        404) ;;
        *) echo "WARN: $p-$num 조회 HTTP $code" >&2 ;;
      esac
    done
    [ "$found" = 1 ] || echo "(후보 없음)" ;;

  epics)
    days="${1:-90}"; [[ "$days" =~ ^[0-9]+$ ]] || die "DAYS 는 정수"
    # JQL 문자열 리터럴에 들어가므로 따옴표·역슬래시·제어문자를 거부한다.
    [[ "$EPIC_TYPE" =~ ^[^\"\\[:cntrl:]]+$ ]] || die "프로필 epic_issuetype 에 따옴표·역슬래시·제어문자를 쓸 수 없다"
    printf 'key\tsource\tuses\tstatus\tduedate\tsummary\n'
    # (a) 최근 내가 담당한 티켓의 parent 에픽 — 사용 횟수 집계 (응답의 이름은 표시 이름이라 hierarchyLevel 로 판정)
    jt_search "assignee = currentUser() AND updated >= -${days}d AND parent is not EMPTY ORDER BY updated DESC" \
              '["parent"]' 100 \
      | jq -r '
          [.issues[]?.fields.parent | select(. != null) | select(.fields.issuetype.hierarchyLevel == 1)]
          | group_by(.key) | map({key: .[0].key, n: length, st: .[0].fields.status.name,
                                 cat: .[0].fields.status.statusCategory.key, s: .[0].fields.summary})
          | sort_by(-.n)[] | select(.cat != "done")
          | [.key, "recent", (.n|tostring), .st, "", .s] | @tsv' | tr -d '\r' > "$TMP/recent.tsv"
    cat "$TMP/recent.tsv"
    # (b) 프로필 프로젝트의 미완료 에픽 — (a) 에 이미 나온 키는 빼서 중복 행을 막는다
    eps=()
    while IFS= read -r p; do [ -n "$p" ] && { need_proj "$p"; eps+=("$p"); }; done < <(pf '.epic_projects[]?')
    if [ ${#eps[@]} -gt 0 ]; then
      plist="$(IFS=,; echo "${eps[*]}")"
      jt_search "project in ($plist) AND issuetype = \"$EPIC_TYPE\" AND statusCategory != Done ORDER BY updated DESC" \
                '["summary","status","duedate"]' 50 \
        | jq -r '.issues[]? | [.key, "open", "0", .fields.status.name, (.fields.duedate // ""), .fields.summary] | @tsv' \
        | tr -d '\r' | awk -F'\t' -v f="$TMP/recent.tsv" \
            'BEGIN { while ((getline l < f) > 0) { split(l, a, "\t"); seen[a[1]] = 1 } } !($1 in seen)'
    fi ;;

  children)
    [ $# -eq 1 ] || die "사용: children EPIC"; need_key "$1"
    printf 'key\tstatus\tcreated\tsummary\n'
    jt_search "parent = $1 AND assignee = currentUser() ORDER BY created DESC" '["summary","status","created"]' 30 \
      | jq -r '.issues[]? | [.key, .fields.status.name, (.fields.created[0:10]), .fields.summary] | @tsv' | tr -d '\r' ;;

  createmeta)
    proj="${1:-}"; need_proj "$proj"; tname="${2:-작업}"
    tid="$(jt_get "/rest/api/3/issue/createmeta/$proj/issuetypes?maxResults=50" \
           | jq -r --arg n "$tname" '(.issueTypes // .values // [])[] | select(.name == $n) | .id' | head -1 | tr -d '\r')"
    [ -n "$tid" ] || die "$proj 에서 이슈 유형 '$tname' 을 찾지 못했다"
    echo "issuetype	$tname	$tid"
    printf 'fieldId\trequired\tname\n'
    jt_get "/rest/api/3/issue/createmeta/$proj/issuetypes/$tid?maxResults=200" \
      | jq -r '(.fields // .values // [])[] | [.fieldId, (if .required then "REQUIRED" else "-" end), .name] | @tsv' \
      | tr -d '\r' ;;

  bizdays)
    s="${1:-}"; e="${2:-}"
    [[ "$s" =~ $DATE_RE && "$e" =~ $DATE_RE ]] || die "사용: bizdays YYYY-MM-DD YYYY-MM-DD"
    si=$(date -d "$s" +%s 2>/dev/null) && ei=$(date -d "$e" +%s 2>/dev/null) || die "날짜 해석 실패"
    [ "$si" -le "$ei" ] || die "기한($e)이 시작일($s)보다 앞선다"
    n=0; d="$s"
    while :; do
      dow=$(date -d "$d" +%u); [ "$dow" -le 5 ] && n=$((n+1))
      [ "$d" = "$e" ] && break
      d=$(date -d "$d + 1 day" +%F)
    done
    echo "$n" ;;

  create)
    [ "${1:-}" = "--confirm" ] || die "외부 쓰기다 — 사용자 승인 후 'create --confirm FILE' 로만 호출한다"
    f="${2:-}"; [ -f "$f" ] || die "payload 파일이 없다: $f"
    jq -e . "$f" >/dev/null 2>&1 || die "payload 가 유효한 JSON 이 아니다"
    jq -e '.fields.reporter' "$f" >/dev/null 2>&1 && die "payload 에 reporter 가 있다 — 화면에 없는 필드라 생성이 실패하니 빼라"
    jq -e '.fields.timetracking.originalEstimate | strings | length > 0' "$f" >/dev/null 2>&1 \
      || die "payload 에 timetracking.originalEstimate 가 없다 — 필수 필드다"
    jq -e '.fields.parent.key and .fields.project and .fields.issuetype and .fields.summary' "$f" >/dev/null 2>&1 \
      || die "payload 에 parent.key·project·issuetype·summary 중 빠진 것이 있다"
    code="$(jt_req POST /rest/api/3/issue "$TMP/c" "$f")"
    echo "HTTP $code"
    case "$code" in
      2*)  k="$(jq -r '.key' "$TMP/c" | tr -d '\r')"
           echo "CREATED $k"; echo "URL $JIRA_SERVER/browse/$k" ;;
      000) echo "TIMEOUT_OR_NETWORK — 생성됐을 수 있다. 재POST 전에 'children EPIC' 으로 먼저 확인할 것"; exit 2 ;;
      *)   jq -c '{errorMessages, errors}' "$TMP/c" 2>/dev/null | tr -d '\r' || tr -d '\r' < "$TMP/c"; exit 1 ;;
    esac ;;

  epictype)
    [ $# -eq 1 ] || die "사용: epictype PROJ"; need_proj "$1"
    epic_type_of "$1" ;;

  create-epic)
    [ "${1:-}" = "--confirm" ] || die "외부 쓰기다 — 사용자 승인 후 'create-epic --confirm FILE' 로만 호출한다"
    f="${2:-}"; [ -f "$f" ] || die "payload 파일이 없다: $f"
    jq -e . "$f" >/dev/null 2>&1 || die "payload 가 유효한 JSON 이 아니다"
    jq -e '.fields.reporter' "$f" >/dev/null 2>&1 && die "payload 에 reporter 가 있다 — 화면에 없는 필드라 생성이 실패하니 빼라"
    jq -e '.fields.parent' "$f" >/dev/null 2>&1 && die "에픽 payload 에 parent 가 있다 — 작업 티켓은 'create' 로 만든다"
    jq -e '.fields.timetracking.originalEstimate | strings | length > 0' "$f" >/dev/null 2>&1 \
      || die "payload 에 timetracking.originalEstimate 가 없다 — 필수 필드다"
    jq -e '.fields.project.key and .fields.issuetype.id and .fields.summary' "$f" >/dev/null 2>&1 \
      || die "payload 에 project.key·issuetype.id·summary 중 빠진 것이 있다"
    # name·id 를 섞어 넣으면 검사한 값과 Jira 가 쓰는 값이 갈릴 수 있어 키 하나만 받는다.
    jq -e '(.fields.issuetype | keys) == ["id"] and (.fields.project | keys) == ["key"]' "$f" >/dev/null 2>&1 \
      || die "issuetype 은 {\"id\"} 만, project 는 {\"key\"} 만 넣는다"
    proj="$(jq -r '.fields.project.key' "$f" | tr -d '\r')"; need_proj "$proj"
    tid="$(jq -r '.fields.issuetype.id | tostring' "$f" | tr -d '\r')"
    [[ "$tid" =~ ^[0-9]+$ ]] || die "issuetype.id 는 숫자 문자열이어야 한다: '$tid'"
    # 작업 티켓을 parent 없이 만드는 우회로로 쓰이지 않게, 유형이 그 프로젝트의 에픽인지 POST 전에 확인한다.
    # pipefail 이 없어 파이프로 받으면 조회 실패가 묻히므로 결과를 먼저 받고 자른다.
    et="$(epic_type_of "$proj")" || exit 1
    eid="${et##*$'\t'}"; [[ "$eid" =~ ^[0-9]+$ ]] || die "$proj 의 에픽 유형 id 를 얻지 못했다"
    [ "$tid" = "$eid" ] || die "issuetype.id '$tid' 는 $proj 의 에픽 유형($eid)이 아니다"
    code="$(jt_req POST /rest/api/3/issue "$TMP/c" "$f")"
    echo "HTTP $code"
    case "$code" in
      2*)  k="$(jq -r '.key' "$TMP/c" | tr -d '\r')"
           echo "CREATED $k"; echo "URL $JIRA_SERVER/browse/$k" ;;
      000) echo "TIMEOUT_OR_NETWORK — 생성됐을 수 있다. 재POST 전에 'epics' 로 같은 제목의 에픽이 생겼는지 먼저 확인할 것"; exit 2 ;;
      *)   jq -c '{errorMessages, errors}' "$TMP/c" 2>/dev/null | tr -d '\r' || tr -d '\r' < "$TMP/c"; exit 1 ;;
    esac ;;

  editmeta)
    [ $# -eq 1 ] || die "사용: editmeta KEY"; need_key "$1"
    jt_get "/rest/api/3/issue/$1/editmeta" \
      | jq -r '.fields | to_entries[] | [.key, (if .value.required then "REQUIRED" else "-" end), .value.name] | @tsv' \
      | tr -d '\r' ;;

  update)
    [ "${1:-}" = "--confirm" ] || die "외부 쓰기다 — 사용자 승인 후 'update --confirm KEY FILE' 로만 호출한다"
    need_key "${2:-}"; f="${3:-}"; [ -f "$f" ] || die "payload 파일이 없다: $f"
    jq -e '.fields | type == "object"' "$f" >/dev/null 2>&1 || die "payload 는 {\"fields\": {...}} 형태여야 한다"
    code="$(jt_req PUT "/rest/api/3/issue/$2" "$TMP/u" "$f")"
    echo "HTTP $code"; case "$code" in 2*) ;; *) jq -c '{errorMessages, errors}' "$TMP/u" 2>/dev/null | tr -d '\r'; exit 1 ;; esac ;;

  transitions)
    [ $# -eq 1 ] || die "사용: transitions KEY"; need_key "$1"
    jt_get "/rest/api/3/issue/$1/transitions" | jq -r '.transitions[]? | [.id, .name, .to.name] | @tsv' | tr -d '\r' ;;

  transition)
    [ "${1:-}" = "--confirm" ] || die "외부 쓰기다 — 사용자 요청 후 'transition --confirm KEY ID' 로만 호출한다"
    need_key "${2:-}"; [[ "${3:-}" =~ ^[0-9]+$ ]] || die "전환 ID 는 숫자"
    jq -n --arg id "$3" '{transition: {id: $id}}' > "$TMP/t.json"
    code="$(jt_req POST "/rest/api/3/issue/$2/transitions" "$TMP/t" "$TMP/t.json")"
    echo "HTTP $code"; case "$code" in 2*) ;; *) tr -d '\r' < "$TMP/t"; echo; exit 1 ;; esac ;;

  *)
    awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "${BASH_SOURCE[0]}"
    [ -z "$cmd" ] || exit 1 ;;
esac
