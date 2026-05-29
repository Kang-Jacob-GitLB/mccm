#!/usr/bin/env bash
# timeline.sh — 하루 일과를 30분 슬롯 텍스트 타임라인으로 시각화.
#
# 입력: stdin = 절차 2 수집 결과 JSONL (라인마다 .epoch(raw UTC) + .event 필드).
# 출력: 슬롯별 "HH:MM │막대│ 프롬프트수 ✦커밋마커" 행. 주제 라벨은 LLM 이
#       각 행 오른쪽에 덧붙인다(이 스크립트는 밀도 막대까지만 결정적으로 생성).
#
# 옵션:
#   --tz <IANA>   타임존 (기본 Asia/Seoul).
#   --width <N>   막대 칸 수 (기본 10).
#   -h, --help    도움말.
#
# 예: cat today.jsonl | timeline.sh
set -euo pipefail

TZ_IANA="Asia/Seoul"
WIDTH=10
while [ $# -gt 0 ]; do
  case "$1" in
    --tz)    TZ_IANA="${2:?}"; shift 2 ;;
    --width) WIDTH="${2:?}"; shift 2 ;;
    -h|--help) sed -n '2,/^set -/p' "$0" | sed '$d; s/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done
# 공통 TZ 유틸 로드 → tzdata 부재(Windows Git Bash 등) 환경에서도 올바른 로컬 시각.
. "$(dirname "${BASH_SOURCE[0]}")/_tz.sh"
tz_setup "$TZ_IANA"

command -v jq >/dev/null 2>&1 || { echo "ERROR: jq 없음" >&2; exit 1; }

# task-notification / 빈 prompt 는 제외. commit 은 모두 포함.
jq -r 'select(.event=="commit" or (.event=="prompt" and ((.prompt//"")|test("task-notification")|not) and ((.prompt//"")|length>0)))
       | "\(.epoch)\t\(.event)"' \
  | awk -F'\t' -v W="$WIDTH" -v OFF="$TZ_OFF" '
      # $1=raw UTC epoch. OFF 더해 로컬 epoch 로 만든 뒤 슬롯·표기에 사용
      # (native 모드는 OFF=0 + TZ=IANA, offset 모드는 OFF=오프셋 + TZ=UTC → 양쪽 동일).
      { e=$1+OFF; slot=int(e/1800)*1800
        if($2=="commit") c[slot]++; else p[slot]++
        all[slot]=1; if(p[slot]>mx) mx=p[slot] }
      END{
        if(length(all)==0){ print "(활동 없음)"; exit }
        n=0; for(s in all) keys[n++]=s
        for(i=0;i<n;i++) for(j=i+1;j<n;j++) if(keys[i]>keys[j]){t=keys[i];keys[i]=keys[j];keys[j]=t}
        tot_p=0; tot_c=0
        for(i=0;i<n;i++){ s=keys[i]; pc=p[s]+0; cc=c[s]+0; tot_p+=pc; tot_c+=cc
          fill=(mx>0)?int(pc/mx*W+0.5):0; bar=""
          for(k=0;k<W;k++) bar=bar (k<fill?"█":"░")
          mark=""; for(k=0;k<cc;k++) mark=mark "✦"
          printf "%s │%s│ %2d %s\n", strftime("%H:%M",s), bar, pc, mark
        }
        printf "── 프롬프트 %d · 커밋 %d · █=밀도(max %d) ✦=커밋 ──\n", tot_p, tot_c, mx
      }'
