#!/usr/bin/env bash
# _tz.sh — tzdata 부재 환경에서도 타임존을 올바르게 다루기 위한 공통 유틸.
#          collect.sh / timeline.sh / jira_worklog.sh 가 source 한다.
#
# 배경: Windows Git Bash/MSYS 에는 tzdata 가 없어 `TZ=Asia/Seoul` 같은 IANA 지정이
#       무시되고 전부 UTC 로 폴백된다 → 모든 시각이 9시간 어긋나 "새벽"으로 표기되는
#       증상이 난다(epoch 은 raw UTC 인데 KST 로 변환되지 않음). 반대로 Linux/WSL/macOS
#       는 tzdata 가 있어 `export TZ` 가 정상 동작한다.
#
# 동작: tz_setup 이 환경을 런타임 감지한다.
#   - TZ 가 먹히면(native)  : 기존대로 `export TZ=<IANA>`, 오프셋 가산 0.
#   - 안 먹히면(offset)     : `export TZ=UTC` 로 strftime/date 를 결정적으로 만들고,
#                             대상 IANA 의 UTC 오프셋(TZ_OFF, 초)을 직접 더해 환산한다.
# 이후 모든 epoch↔로컬 변환은 l2e/e2l/tz_today/tz_midnight 만 쓰면 양쪽이 동일해진다.
# awk strftime 을 직접 쓸 때는 `strftime(fmt, epoch + TZ_OFF)` 로 호출한다.

# "+0900"/"-0530" → 초
_tz_parse() {
  local z=$1 s
  case "$z" in [+-][0-9][0-9][0-9][0-9]) ;; *) echo 0; return ;; esac
  s=$(( 10#${z:1:2}*3600 + 10#${z:3:2}*60 ))
  [ "${z:0:1}" = "-" ] && s=$(( -s ))
  echo "$s"
}

# IANA 고정 오프셋(초). tzdata 가 없을 때만 쓰는 근사표(DST 없는 존 위주).
_tz_fixed() {
  case "$1" in
    UTC|GMT|Etc/UTC|Etc/GMT)                                                 echo 0 ;;   # DST 관측 존(Europe/London 등)은 일부러 제외 → date +%z 폴백
    Asia/Seoul|Asia/Tokyo|Asia/Pyongyang)                                    echo 32400 ;;  # +9
    Asia/Shanghai|Asia/Hong_Kong|Asia/Taipei|Asia/Singapore|Asia/Manila|Australia/Perth) echo 28800 ;;  # +8
    Asia/Bangkok|Asia/Jakarta|Asia/Ho_Chi_Minh)                              echo 25200 ;;  # +7
    Asia/Kolkata|Asia/Calcutta)                                              echo 19800 ;;  # +5:30
    Asia/Dubai|Asia/Muscat)                                                  echo 14400 ;;  # +4
    *) return 1 ;;
  esac
}

# 전역 TZ_MODE(native|offset), TZ_OFF(초), TZ_NAME 을 설정한다. 인자: IANA(기본 Asia/Seoul).
tz_setup() {
  TZ_NAME="${1:-Asia/Seoul}"
  # epoch 0(=1970-01-01T00:00:00Z)을 Asia/Seoul 로 찍어 09 시가 나오면 tzdata 동작.
  if [ "$(TZ=Asia/Seoul date -d @0 +%H 2>/dev/null)" = "09" ]; then
    TZ_MODE="native"; TZ_OFF=0; export TZ="$TZ_NAME"
  else
    TZ_MODE="offset"; export TZ="UTC"
    if TZ_OFF=$(_tz_fixed "$TZ_NAME"); then :
    else
      TZ_OFF=$(_tz_parse "$(date +%z)")
      echo "WARN: tzdata 부재 + '$TZ_NAME' 오프셋 미상 → 시스템 로컬($(date +%z)) 사용" >&2
    fi
    echo "INFO: tzdata 부재 환경 감지 → '$TZ_NAME' 오프셋(${TZ_OFF}s) 직접 적용" >&2
  fi
}

# 로컬 표기 "YYYY-MM-DD HH:MM[:SS]" → epoch(UTC 초). 파싱 실패 시 rc=1 전파
# (offset 분기에서 빈 출력이 0 으로 평가돼 -OFF 가짜값을 rc=0 으로 반환하던 버그 방지 —
#  native 분기와 실패 동작을 동일하게 맞춰 호출부 방어코드가 정상 작동하게 한다).
l2e() {
  if [ "${TZ_MODE:-native}" = native ]; then date -d "$1" +%s
  else local u; u=$(date -u -d "$1" +%s) || return 1; echo $(( u - TZ_OFF )); fi
}
# epoch(UTC 초) → 로컬 표기. $2=strftime 포맷(기본 "%Y-%m-%d %H:%M:%S")
e2l() {
  local f=${2:-%Y-%m-%d %H:%M:%S}
  if [ "${TZ_MODE:-native}" = native ]; then date -d "@$1" +"$f"
  else date -u -d "@$(( $1 + TZ_OFF ))" +"$f"; fi
}
# 오늘 로컬 날짜 YYYY-MM-DD
tz_today() {
  if [ "${TZ_MODE:-native}" = native ]; then date +%F
  else date -u -d "@$(( $(date +%s) + TZ_OFF ))" +%F; fi
}
# 로컬 날짜의 자정 epoch
tz_midnight() { l2e "$1 00:00:00"; }
