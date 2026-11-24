#!/usr/bin/env bash
# collect.sh — Claude Code 트랜스크립트에서 대상 날짜(KST)의 활동을 정규화 JSONL 로 추출.
#
# hook 없이 동작한다. Claude Code 가 직접 남기는 세션 트랜스크립트
#   ~/.claude/projects/<cwd-slug>/<session-id>.jsonl
# (WSL 이면 Windows 측 /mnt/c/Users/*/.claude/projects/... 도,
#  Windows(Git Bash/MSYS) 이면 WSL 측 //wsl.localhost/<distro>/home/*/.claude/projects 도) 를 읽어,
# 기존 hook JSONL 과 **동일한 스키마**의 라인을 stdout 으로 낸다:
#   {ts, env, event(prompt|commit|session_start|session_stop), session_id,
#    cwd, branch, prompt?|sha?+subject?, epoch}
# epoch 은 raw UTC (초). 출력은 epoch 오름차순. timeline.sh / 하위 분석이 그대로 소비.
#
# 사용법:
#   collect.sh YYYY-MM-DD            # 대상일(KST)
#   collect.sh                       # 오늘(KST)
# 옵션:
#   --tz <IANA>     날짜 경계 해석 타임존 (기본 Asia/Seoul).
#   --root <DIR>    트랜스크립트 루트 추가(반복 가능). 자동 탐지 루트에 더해진다.
#   추가 루트 파일  ~/.config/mccm/worklog-roots (WORKLOG_ROOTS_FILE env 로 변경) —
#                   한 줄에 디렉터리 하나, # 주석·빈 줄 무시. 원격 머신 홈을 마운트한
#                   경로(예: /z/.claude/projects)를 두면 매번 --root 없이 합쳐진다.
#                   --root·추가 루트 파일의 이벤트는 env "remote" 로 찍힌다.
#   원격 호스트 파일 ~/.config/mccm/worklog-remotes (WORKLOG_REMOTES_FILE env 로 변경) —
#                   한 줄에 "<ssh 호스트> [linux|windows]", # 주석·빈 줄 무시. 마운트 없이
#                   ssh 로 이 스크립트(+_tz.sh)를 원격에서 --local-only 로 돌려 이벤트만
#                   받아 합친다(원격엔 bash·jq 만 있으면 된다, 플러그인 설치 불필요).
#                   windows 는 기본 셸이 PowerShell 인 Windows OpenSSH — Git Bash 로 실행한다.
#                   원격 이벤트에는 host 필드가 붙는다. 연결 안 되면 WARN 으로 남기고 넘어간다
#                   (BatchMode·ConnectTimeout — 비밀번호 프롬프트로 멈추지 않는다).
#   --local-only    자동 탐지 루트(로컬 홈·WSL)만 읽는다 — 추가 루트·원격 호스트 파일을
#                   건너뛴다. 원격 호출이 쓴다(재귀 방지, 그 머신의 마운트 루트와의 중복 방지).
#   stderr          읽은 루트는 "ROOT<TAB>env<TAB>dir"(원격은 env@host), 없는(미연결) 추가
#                   루트·원격은 "WARN<TAB>dir" 로 낸다 — prep.sh 가 SOURCES 섹션으로 옮긴다.
#   --since <HH:MM> 대상일 내 그 로컬 시각 이후(>=) 이벤트만 출력.
#   --until <HH:MM> 대상일 내 그 로컬 시각 이전(<) 이벤트만 출력.
#   -h|--help
#
# 추출 규칙:
#   prompt  = 사용자가 실제로 입력한 텍스트. tool_result / <task-notification> /
#             <local-command-*> / 서브에이전트(isSidechain) / "[Request interrupted...]"
#             는 제외. 슬래시 명령은 <command-name>+<command-args> 로 "/cmd args" 복원.
#   commit  = "git commit" 을 실행한 Bash tool_use 의 결과에 찍힌 "[branch sha] subject"
#             만 인정(= git log/show/rebase 출력의 동일 패턴은 배제). sha 로 dedup.
#   session_start/stop = 세션파일별 그 날짜 라인의 min/max 타임스탬프(활동창 근사).
set -euo pipefail

TZ_IANA="Asia/Seoul"
DATE=""
SINCE=""
UNTIL=""
LOCAL_ONLY=0
EXTRA_ROOTS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --local-only) LOCAL_ONLY=1; shift ;;
    --tz)    TZ_IANA="${2:?}"; shift 2 ;;
    --root)  EXTRA_ROOTS+=("${2:?}"); shift 2 ;;
    --since) SINCE="${2:?}"; shift 2 ;;   # 대상일 내 HH:MM 이후만 (로컬)
    --until) UNTIL="${2:?}"; shift 2 ;;   # 대상일 내 HH:MM 이전만 (로컬)
    -h|--help) sed -n '2,/^set -/p' "$0" | sed '$d; s/^# \{0,1\}//'; exit 0 ;;
    -*) echo "unknown arg: $1" >&2; exit 2 ;;
    *)  DATE="$1"; shift ;;
  esac
done
command -v jq >/dev/null 2>&1 || { echo "ERROR: jq 없음" >&2; exit 1; }

# 공통 TZ 유틸 로드 → tzdata 부재(Windows Git Bash 등) 환경에서도 날짜 경계가
# UTC 로 9시간 어긋나지 않게 한다.
# 원격 실행 때는 _tz.sh 를 이 스크립트 앞에 이어 붙여 보내므로 이미 정의돼 있다.
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if ! type tz_setup >/dev/null 2>&1; then
  # 원격(--local-only)으로 받은 스트림에 _tz.sh 가 빠졌으면 옆 파일을 찾지 않는다 — 남의 파일 source 방지.
  if [ "$LOCAL_ONLY" = 1 ] && [ ! -O "$SELF_DIR/_tz.sh" ]; then echo "ERROR: tz_setup 없음" >&2; exit 3; fi
  . "$SELF_DIR/_tz.sh"
fi
tz_setup "$TZ_IANA"

[ -n "$DATE" ] || DATE="$(tz_today)"
# 입력 검증 — 이 값들은 원격 ssh 명령줄에 실린다(셸 인젝션 차단). 전체 매칭.
[[ "$DATE" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || { echo "잘못된 날짜: $DATE" >&2; exit 2; }
[[ "$TZ_IANA" =~ ^[A-Za-z][A-Za-z0-9_+/-]*$ ]] || { echo "잘못된 타임존: $TZ_IANA" >&2; exit 2; }
for v in "$SINCE" "$UNTIL"; do
  [ -z "$v" ] || [[ "$v" =~ ^[0-2][0-9]:[0-5][0-9]$ ]] || { echo "잘못된 시각(HH:MM): $v" >&2; exit 2; }
done
# 대상일(로컬 TZ) 자정 ~ 익일 자정 → UTC epoch 경계
START=$(tz_midnight "$DATE")
END=$(( START + 86400 ))
# --since/--until (대상일 내 HH:MM 로컬) → epoch 경계. 미지정이면 빈 문자열.
SINCE_EPOCH=""; UNTIL_EPOCH=""
[ -n "$SINCE" ] && SINCE_EPOCH=$(l2e "$DATE ${SINCE}:00" 2>/dev/null) || true
[ -n "$UNTIL" ] && UNTIL_EPOCH=$(l2e "$DATE ${UNTIL}:00" 2>/dev/null) || true

# 현재 머신 env 판별
THIS_ENV="linux"
case "$(uname -s)" in
  Darwin)               THIS_ENV="macos" ;;
  Linux)                grep -qi microsoft /proc/version 2>/dev/null && THIS_ENV="wsl" ;;
  MINGW*|MSYS*|CYGWIN*) THIS_ENV="windows" ;;
esac

# 트랜스크립트 루트 수집: "<env>\t<dir>" 줄
roots_tsv() {
  [ -d "$HOME/.claude/projects" ] && printf '%s\t%s\n' "$THIS_ENV" "$HOME/.claude/projects"
  if [ "$THIS_ENV" = "wsl" ]; then
    for d in /mnt/c/Users/*/.claude/projects; do
      [ -d "$d" ] && printf '%s\t%s\n' "windows" "$d"
    done
  elif [ "$THIS_ENV" = "windows" ] && command -v reg.exe >/dev/null 2>&1; then
    # WSL 배포판 자동 탐색 — wsl.exe 를 부르지 않고 등록 레지스트리(Lxss)를 읽는다.
    # WSL 을 지워도 system32\wsl.exe 스텁은 남아, 호출하면 "아무 키나 눌러 설치" 창이
    # 60초간 뜬다. 레지스트리는 배포판이 없으면 조용히 빈 결과다.
    # MSYS2_ARG_CONV_EXCL: Git Bash 가 /s·/v 를 경로로 바꾸지 않게 한다.
    while IFS= read -r distro; do
      [ -n "$distro" ] || continue
      for d in "//wsl.localhost/${distro}/home"/*/.claude/projects; do
        [ -d "$d" ] && printf '%s\t%s\n' "wsl" "$d"
      done
    done < <(MSYS2_ARG_CONV_EXCL='*' reg.exe query 'HKCU\Software\Microsoft\Windows\CurrentVersion\Lxss' \
               /s /v DistributionName 2>/dev/null </dev/null \
             | tr -d '\r' | awk '$1=="DistributionName" && $2=="REG_SZ" { sub(/^[[:space:]]*DistributionName[[:space:]]+REG_SZ[[:space:]]+/, ""); print }')
  fi
  for r in ${EXTRA_ROOTS+"${EXTRA_ROOTS[@]}"}; do
    if [ -d "$r" ]; then printf '%s\t%s\n' "remote" "$r"
    else printf 'WARN\t%s\n' "$r" >&2; fi
  done
}

# 추가 루트 파일(원격 머신 마운트 등). 줄을 경로 문자열로만 쓴다 — 셸로 평가하지 않는다.
ROOTS_FILE="${WORKLOG_ROOTS_FILE:-$HOME/.config/mccm/worklog-roots}"
if [ "$LOCAL_ONLY" != 1 ] && [ -f "$ROOTS_FILE" ]; then
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    line="${line#"${line%%[![:space:]]*}"}"; line="${line%"${line##*[![:space:]]}"}"
    case "$line" in ''|'#'*) continue ;; esac
    EXTRA_ROOTS+=("$line")
  done < "$ROOTS_FILE"
fi

# jq 프로그램(-n 모드): inputs 로 여러 트랜스크립트 파일을 한 번에 읽어
# prompt/commit/session 이벤트 추출. input_filename 으로 파일경계를 보존한다.
read -r -d '' JQPROG <<'JQ' || true
def epoch($s): ($s | sub("\\.[0-9]+Z$";"Z") | fromdateiso8601);
# 자동 생성/시스템 메시지(실제 입력 아님)는 prompt 에서 제외
def isnoise($t):
  ($t|test("^\\[Request interrupted"))
  or ($t == "Continue from where you left off.")
  or (($t|gsub("\\s";"")|length) == 0);
def ptext($c):
  ( if ($c|type)=="string" then
      if ($c|test("<command-name>")) then
        (($c|capture("<command-name>(?<n>[^<]*)</command-name>")|.n) // "") as $n
        | (($c|capture("<command-args>(?<a>[^<]*)</command-args>")|.a) // "") as $a
        | (($n + " " + $a) | gsub("^\\s+|\\s+$";""))
      elif ($c|startswith("<")) then null
      else $c end
    elif ($c|type)=="array" then
      ([ $c[] | select(.type=="text") | .text ] | join("\n")) as $t
      | (if ($t|startswith("<")) then null else $t end)
    else null end ) as $r
  | if ($r == null) then null elif (isnoise($r)) then null else $r end;
def restext($rc):
  if ($rc|type)=="string" then $rc
  elif ($rc|type)=="array" then ([ $rc[]? | .text // empty ] | join("\n"))
  else "" end;

# 여러 파일을 한 jq(-n)로 읽되, 각 라인에 출처 파일(__f)을 태깅해 파일경계를 보존한다.
([ inputs | . + {__f: input_filename} ]) as $lines

# git commit 을 실행한 tool_use id 집합
| (reduce $lines[] as $l ({};
   if $l.type=="assistant" then
     reduce ($l.message.content[]? | select((.type=="tool_use") and ((.name//"")|test("Bash")))) as $tu (.;
       if (($tu.input.command // "") | test("git[ \t]+commit")) then .[$tu.id]=true else . end)
   else . end)) as $cids

# 그 날짜 범위 라인만 (__f 보존)
| [ $lines[] | select((.timestamp // null) != null) | select((epoch(.timestamp)) as $e | $e >= $start and $e < $end) ] as $rows

# session_start / session_stop = 파일(__f)별 min/max (종전 per-file 의미 그대로 유지).
# 파일마다 jq 를 새로 띄우는 대신 input_filename 으로 파일을 구분 → 1회 처리로 동치 결과.
| ( $rows
    | group_by(.__f)
    | .[]
    | (map(epoch(.timestamp))) as $eps
    | (.[0]) as $f
    | ( {event:"session_start", epoch:($eps|min)},
        {event:"session_stop",  epoch:($eps|max)} )
    | . + {ts:(.epoch|todateiso8601), env:$env, session_id:($f.sessionId//""),
           cwd:($f.cwd//""), branch:($f.gitBranch//"")} )
,
# prompts + commits
( $rows[]
  | epoch(.timestamp) as $e
  | if (.type=="user" and (.isSidechain!=true) and (ptext(.message.content) != null)) then
      {ts:.timestamp, env:$env, event:"prompt", session_id:(.sessionId//""),
       cwd:(.cwd//""), branch:(.gitBranch//""), prompt:ptext(.message.content), epoch:$e}
    elif (.type=="user") then
      ( .message.content
        | if type=="array" then
            .[] | select(.type=="tool_result" and ($cids[.tool_use_id] == true))
          else empty end ) as $tr
      | (restext($tr.content)) as $txt
      | ($txt | capture("\\[(?<br>[^\\] ]+) (?<sha>[0-9a-f]{7,40})\\][ ]?(?<sub>[^\\n]*)") ) as $m
      | {ts:.timestamp, env:$env, event:"commit", session_id:(.sessionId//""),
         cwd:(.cwd//""), branch:$m.br, sha:$m.sha, subject:$m.sub, epoch:$e}
    else empty end )
JQ

TMP="$(mktemp)"; RTMP="$(mktemp -d)"; trap 'rm -rf "$TMP" "$RTMP"' EXIT

# ── 원격 호스트(ssh) — 로컬 루트를 읽는 동안 병렬로 돈다 ──
# 원격에서는 stdin 으로 받은 스크립트를 임시파일에 다 받은 뒤 실행한다 — bash -s 로 바로
# 돌리면 스크립트 실행 중의 자식(reg.exe 등)이 남은 스크립트 바이트를 stdin 으로 먹을 수 있다.
# 큰따옴표를 쓰지 않는다: Windows PowerShell 5.1 은 네이티브 인자 속 " 를 이스케이프하지 않아
# Git Bash 에 깨져 도착한다. 인자는 위에서 검증한 공백 없는 토큰뿐이다.
# 개인(0700) 임시 디렉터리에 받는다 — 원격의 SELF_DIR 이 공용 /tmp 가 되지 않게. 다 받았을 때만 실행.
REMOTE_RUNNER='d=$(mktemp -d) || exit 97; f=$d/collect.sh; cat >$f && bash $f $@; rc=$?; rm -rf -- $d; exit $rc'
REMOTE_HOSTS=()   # "host<TAB>kind"
REMOTE_PIDS=()
REMOTES_FILE="${WORKLOG_REMOTES_FILE:-$HOME/.config/mccm/worklog-remotes}"
if [ "$LOCAL_ONLY" != 1 ] && [ -f "$REMOTES_FILE" ]; then
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"; line="${line%%#*}"
    h=""; k=""
    read -r h k _ <<<"$line" || true
    [ -n "$h" ] || continue
    # 호스트는 ssh 옵션으로 읽힐 수 없게(선행 -) 안전한 문자만. 줄을 셸로 평가하지 않는다.
    if ! [[ "$h" =~ ^[A-Za-z0-9][A-Za-z0-9._@-]*$ ]]; then printf 'WARN\tssh:(잘못된 호스트 이름 무시)\n' >&2; continue; fi
    case "${k:-linux}" in
      linux|windows) REMOTE_HOSTS+=("$h"$'\t'"${k:-linux}") ;;
      *) printf 'WARN\tssh:%s (알 수 없는 종류 %s — linux|windows)\n' "$h" "$k" >&2 ;;
    esac
  done < "$REMOTES_FILE"
fi

remote_collect() {   # host kind outprefix
  local h="$1" k="$2" o="$3" pre args
  args="$DATE --tz $TZ_IANA --local-only${SINCE:+ --since $SINCE}${UNTIL:+ --until $UNTIL}"
  case "$k" in
    # PATH: 비대화형 ssh 는 ~/.local/bin 을 안 넣는 배포판이 많다(jq 를 거기 두는 경우).
    linux)   pre='PATH=$HOME/.local/bin:$PATH bash -c' ;;
    # 맨 bash 는 System32\bash.exe(WSL 런처)로 풀린다 — Git Bash 를 명시한다.
    windows) pre='& "$env:ProgramFiles\Git\bin\bash.exe" -c' ;;
  esac
  # set -e 아래에서 실패한 파이프라인이 서브셸을 끝내기 전에 rc 를 남긴다(if 문맥).
  if { cat "$SELF_DIR/_tz.sh"; cat "$SELF_DIR/collect.sh"; } \
     | ssh -T -o BatchMode=yes -o ConnectTimeout=6 -o ServerAliveInterval=5 -o ServerAliveCountMax=3 \
           -o ForwardAgent=no -o ForwardX11=no -o ClearAllForwardings=yes -o PermitLocalCommand=no \
           -- "$h" "$pre '$REMOTE_RUNNER' wl $args" > "$o.out" 2> "$o.err"; then
    echo 0 > "$o.rc"
  else
    echo "$?" > "$o.rc"
  fi
}

i=0
for hk in ${REMOTE_HOSTS+"${REMOTE_HOSTS[@]}"}; do
  i=$(( i + 1 ))
  remote_collect "${hk%%$'\t'*}" "${hk#*$'\t'}" "$RTMP/$i" </dev/null &
  REMOTE_PIDS+=("$!")
done

SEEN_ROOTS=$'\n'   # 연관배열 대신 문자열 — macOS 기본 bash 3.2 호환
while IFS=$'\t' read -r env root; do
  [ -n "$root" ] || continue
  case "$SEEN_ROOTS" in *$'\n'"$root"$'\n'*) continue ;; esac   # 자동 탐지·추가 루트가 겹쳐도 1회만
  SEEN_ROOTS="$SEEN_ROOTS$root"$'\n'
  printf 'ROOT\t%s\t%s\n' "$env" "$root" >&2
  # 대상일 자정(로컬) 이후 수정된 파일만 (그 이전 파일엔 그 날 라인이 있을 수 없음).
  # @epoch 로 넘겨 tzdata 부재 환경에서도 경계가 어긋나지 않게 한다.
  # 파일들을 모아 jq 를 루트당 1회만 띄운다 — 파일마다 jq 를 새로 spawn 하면
  # Windows 에서 수십 회 프로세스 생성이 일어나 collect 의 주 병목이 된다.
  files=()
  while IFS= read -r f; do [ -n "$f" ] && files+=("$f"); done \
    < <(find "$root" -type f -name '*.jsonl' -newermt "@$START" 2>/dev/null)
  [ "${#files[@]}" -gt 0 ] || continue
  jq -c -n --argjson start "$START" --argjson end "$END" --arg env "$env" \
     "$JQPROG" "${files[@]}" 2>/dev/null >> "$TMP" || true
done < <(roots_tsv)

# 원격 결과 합치기 — fail-closed: 원격 자신의 ROOT 줄이 와야만 성공으로 본다.
# 연결 실패(255)·jq 없음·스크립트 오류는 모두 SOURCES 에 미연결로 남는다.
i=0
for hk in ${REMOTE_HOSTS+"${REMOTE_HOSTS[@]}"}; do
  i=$(( i + 1 )); h="${hk%%$'\t'*}"; o="$RTMP/$i"
  wait "${REMOTE_PIDS[$(( i - 1 ))]}" 2>/dev/null || true
  rc="$(cat "$o.rc" 2>/dev/null || echo '?')"
  if [ "$rc" = 0 ] && grep -q $'^ROOT\t' "$o.err" 2>/dev/null; then
    # 원격 stderr 는 원격 계정이 쓴 텍스트다(.bashrc echo 등) — 허용 문자만 남기고 줄 수를 제한한다.
    awk -F'\t' -v h="$h" 'n<20 && ($1=="ROOT"||$1=="WARN") { n++
        for (i=2; i<=3; i++) gsub(/[^A-Za-z0-9._\/:@~ -]/, "?", $i)
        if ($1=="ROOT") printf "ROOT\t%s@%s\t%s\n", $2, h, $3; else printf "WARN\t%s:%s\n", h, $2 }' "$o.err" >&2
    jq -c --arg h "$h" '. + {host:$h}' "$o.out" >> "$TMP" 2>/dev/null || true
  else
    # 사유는 ssh 클라이언트 자신의 오류(rc 255, "ssh: …")만 정제해 싣는다 — 원격 자유 텍스트는 버린다.
    why=""
    if [ "$rc" = 255 ]; then
      why="$(grep -e '^ssh: ' "$o.err" 2>/dev/null | tail -n 1 | tr -cd 'A-Za-z0-9._/:@ -' | cut -c1-120)"
    fi
    printf 'WARN\tssh:%s (rc=%s%s)\n' "$h" "$rc" "${why:+ · $why}" >&2
  fi
done

# commit 은 sha 로 dedup(최초 epoch 유지). 나머지는 같은 세션의 같은 이벤트가 두 경로
# (예: 마운트 루트 + ssh 원격)로 들어와도 한 번만 남긴다. --since/--until 지정 시 epoch 로 필터.
# 전체 epoch 오름차순 출력.
jq -c -s --arg since "${SINCE_EPOCH:-}" --arg until "${UNTIL_EPOCH:-}" '
  (if $since=="" then null else ($since|tonumber) end) as $s
  | (if $until=="" then null else ($until|tonumber) end) as $u
  | ([ .[] | select(.event=="commit" and (.sha//"")!="") ] | group_by(.sha)
     | map(sort_by((.host != null), .epoch) | .[0])) as $commits   # 같은 sha 면 로컬 기록 우선(원격이 덮지 못함)
  | ([ .[] | select(.event!="commit") ] | unique_by([.event, .session_id, .epoch, (.prompt//"")])) + $commits
  | map(select( ($s==null or .epoch>=$s) and ($u==null or .epoch<$u) ))
  | sort_by(.epoch) | .[]
' "$TMP"
