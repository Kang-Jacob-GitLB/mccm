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
#   --tz <IANA>   날짜 경계 해석 타임존 (기본 Asia/Seoul).
#   --root <DIR>  트랜스크립트 루트 추가(반복 가능). 미지정 시 자동 탐지.
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
EXTRA_ROOTS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --tz)   TZ_IANA="${2:?}"; shift 2 ;;
    --root) EXTRA_ROOTS+=("${2:?}"); shift 2 ;;
    -h|--help) sed -n '2,/^set -/p' "$0" | sed '$d; s/^# \{0,1\}//'; exit 0 ;;
    -*) echo "unknown arg: $1" >&2; exit 2 ;;
    *)  DATE="$1"; shift ;;
  esac
done
command -v jq >/dev/null 2>&1 || { echo "ERROR: jq 없음" >&2; exit 1; }

# 공통 TZ 유틸 로드 → tzdata 부재(Windows Git Bash 등) 환경에서도 날짜 경계가
# UTC 로 9시간 어긋나지 않게 한다.
. "$(dirname "${BASH_SOURCE[0]}")/_tz.sh"
tz_setup "$TZ_IANA"

[ -n "$DATE" ] || DATE="$(tz_today)"
# 대상일(로컬 TZ) 자정 ~ 익일 자정 → UTC epoch 경계
START=$(tz_midnight "$DATE")
END=$(( START + 86400 ))

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
  elif [ "$THIS_ENV" = "windows" ] && command -v wsl.exe >/dev/null 2>&1; then
    # WSL 배포판 자동 탐색 — wsl.exe -l -q 출력은 UTF-16LE(+ NUL/CR) 이라 정리.
    while IFS= read -r distro; do
      [ -n "$distro" ] || continue
      for d in "//wsl.localhost/${distro}/home"/*/.claude/projects; do
        [ -d "$d" ] && printf '%s\t%s\n' "wsl" "$d"
      done
    done < <(wsl.exe -l -q 2>/dev/null | tr -d '\000\r' | sed -e 's/[[:space:]]*$//' -e '/^$/d')
  fi
  for r in ${EXTRA_ROOTS+"${EXTRA_ROOTS[@]}"}; do
    [ -d "$r" ] && printf '%s\t%s\n' "$THIS_ENV" "$r"
  done
}

# jq 프로그램: 한 트랜스크립트 파일(slurp)에서 prompt/commit/session 이벤트 추출.
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

# git commit 을 실행한 tool_use id 집합
(reduce .[] as $l ({};
   if $l.type=="assistant" then
     reduce ($l.message.content[]? | select((.type=="tool_use") and ((.name//"")|test("Bash")))) as $tu (.;
       if (($tu.input.command // "") | test("git[ \t]+commit")) then .[$tu.id]=true else . end)
   else . end)) as $cids

# 그 날짜 범위 라인만
| [ .[] | select((.timestamp // null) != null) | select((epoch(.timestamp)) as $e | $e >= $start and $e < $end) ] as $rows
| ($rows | map(epoch(.timestamp))) as $eps

# session_start / session_stop (min/max)
| ( if ($rows|length) > 0 then
      ($rows[0]) as $f
      | ($eps|min) as $mn | ($eps|max) as $mx
      | ( {event:"session_start", epoch:$mn},
          {event:"session_stop",  epoch:$mx} )
      | . + {ts:(.epoch|todateiso8601), env:$env, session_id:($f.sessionId//""),
             cwd:($f.cwd//""), branch:($f.gitBranch//"")}
    else empty end )
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

TMP="$(mktemp)"; trap 'rm -f "$TMP"' EXIT

while IFS=$'\t' read -r env root; do
  [ -n "$root" ] || continue
  # 대상일 자정(로컬) 이후 수정된 파일만 (그 이전 파일엔 그 날 라인이 있을 수 없음).
  # @epoch 로 넘겨 tzdata 부재 환경에서도 경계가 어긋나지 않게 한다.
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    jq -c -s --argjson start "$START" --argjson end "$END" --arg env "$env" "$JQPROG" "$f" 2>/dev/null >> "$TMP" || true
  done < <(find "$root" -type f -name '*.jsonl' -newermt "@$START" 2>/dev/null)
done < <(roots_tsv)

# commit 은 sha 로 dedup(최초 epoch 유지), 전체 epoch 오름차순 출력.
jq -c -s '
  ([ .[] | select(.event=="commit" and (.sha//"")!="") ] | group_by(.sha) | map(min_by(.epoch))) as $commits
  | ([ .[] | select(.event!="commit") ] + $commits)
  | sort_by(.epoch) | .[]
' "$TMP"
