---
name: download
description: Gist의 mccm.json을 로컬 settings.json과 전역 CLAUDE.md에 적용한다. "/download", "환경 다운로드", "download env" 등의 요청에 사용한다.
allowed-tools: Bash, Read, Edit
---

## 현재 상태

- mccm.json (gist): !`GIST_ID=$(gh api gists --jq '.[] | select(.files["mccm.json"] != null) | .id' 2>/dev/null | head -1); [ -n "$GIST_ID" ] && gh gist view "$GIST_ID" --filename mccm.json 2>/dev/null || echo "not found — gist에 mccm.json 파일이 없습니다"`
- settings.json: !`cat "$HOME/.claude/settings.json" 2>/dev/null || echo "not found"`
- ccstatusline: !`cat "$HOME/.config/ccstatusline/settings.json" 2>/dev/null || echo "not found"`
- CLAUDE.md: !`f="$HOME/.claude/CLAUDE.md"; [ -f "$f" ] && echo "존재 ($(wc -l < "$f") 줄) — 내용은 전사하지 말고 jq 파이프로 복원" || echo "not found"`
- worklog.json (gist): !`GIST_ID=$(gh api gists --jq '.[] | select(.files["mccm.json"] != null) | .id' 2>/dev/null | head -1); [ -n "$GIST_ID" ] && gh gist view "$GIST_ID" --filename worklog.json >/dev/null 2>&1 && echo "존재 (내용은 민감할 수 있어 표시하지 않음)" || echo "not found"`

## 변수 치환 규칙

mccm.json의 문자열 값에서 아래 변수를 치환한다:
- `${HOME}` → 현재 OS의 홈 디렉토리 (`$HOME` 또는 `$USERPROFILE`)
- `${USER}` → 현재 사용자명

## 작업 지침

Gist의 mccm.json을 기준으로 로컬 환경을 구성한다.

### 0. gist 확인

`gh api gists`로 `mccm.json`을 포함하는 gist를 검색한다.

- **0개**: 사용자에게 안내한다 — `gh gist create --desc "mccm env"` 으로 mccm.json gist를 먼저 생성하라고.
- **1개**: 해당 gist를 사용한다.
- **2개 이상**: ID와 description을 목록으로 보여주고 사용자에게 선택을 받는다. `head -1`으로 자동 선택하지 않는다.

### 1. 마켓플레이스

mccm.json의 `marketplaces`를 settings.json의 `extraKnownMarketplaces`와 비교한다.
- 미등록 마켓플레이스: `claude plugin marketplace add` 실행
- 등록 완료: `claude plugin marketplace update` 실행

### 2. 플러그인

mccm.json의 `plugins`를 settings.json의 `enabledPlugins`와 비교한다.
- 미설치: `claude plugin install` 실행
- 기설치: `claude plugin update` 실행

### 3. CLI 도구

mccm.json의 `clis`를 확인한다.

**⚠️ 보안:** `check`와 `install` 값은 셸 명령으로 실행되므로, 실행 전 반드시 사용자에게 명령 전문을 보여주고 승인을 받는다.

각 CLI 항목에 대해:
1. `check`와 `install` 명령을 사용자에게 표시한다
2. 사용자가 승인하면 `check` 명령으로 설치 여부를 판단한다
3. 미설치: 사용자가 승인한 `install` 명령 실행
4. 기설치: 스킵

사용자가 거부한 항목은 스킵하고 완료 보고에 "스킵됨"으로 기록한다.

### 4. ccstatusline 설정 복원

mccm.json에 `ccstatusline.config` 객체가 있으면 위젯 디자인 본체를 `$HOME/.config/ccstatusline/settings.json`에 복원한다. (바이너리 설치는 3단계 `clis`에서, statusLine 연결은 5단계 `settings`에서 처리되므로 여기서는 디자인 본체만 다룬다.)

> **⚠️ 글리프 주의 (필독):** `ccstatusline.config`의 `powerline.separators / startCaps / endCaps` 에는 화면상 **빈 칸으로 보이는 Nerd Font PUA 글리프**(U+E0B0~U+E0BF 등)가 들어 있다. Read·Edit·수기 전사로 다루면 글리프가 보이지 않아 **빈 문자열로 소실**된다.
> - 이 파일은 **반드시 아래 `jq` 파이프로 전체 덮어쓰기**한다. Read·Edit·수기 전사 금지.
> - "한 필드만 다른 것 같아도" 부분 Edit 하지 말고 **무조건 전체를 `jq`로 다시 쓴다** (gist가 이 파일의 단일 진실원).
> - 동일/다름 판정도 눈이 아니라 **바이트로** 한다(아래 `diff`).

- 로컬 파일이 **없으면**: `mkdir -p`로 디렉토리를 만든 뒤 바로 기록한다.
- 로컬 파일이 mccm.json `config`와 **동일**하면(아래 `diff`가 무출력): 스킵.
- **다르면(충돌)**: 사용자에게 차이를 보여주고 물어본다:
  - **(1) 취소** (기존 로컬 설정 유지) / **(2) 대치** (gist 설정으로 교체)
  - 사용자 선택에 따라 적용한다.

```bash
GIST_ID=<선택된 gist id>
DST="$HOME/.config/ccstatusline/settings.json"

# 동일/다름 판정 (바이트 비교 — 보이지 않는 글리프 차이까지 잡힘)
diff <(gh gist view "$GIST_ID" --filename mccm.json | jq -S '.ccstatusline.config') \
     <(jq -S . "$DST" 2>/dev/null) >/dev/null \
  && { echo "동일 → 스킵"; } \
  || echo "다름 → (사용자 확인 후) 대치"

# 대치(또는 신규): 전체 덮어쓰기로만 기록 — 절대 전사/Edit 하지 않는다 (글리프 보존)
mkdir -p "$HOME/.config/ccstatusline"
gh gist view "$GIST_ID" --filename mccm.json | jq '.ccstatusline.config' > "$DST"

# 기록 후 검증: 로컬이 gist와 바이트 동일한지 재확인 (글리프 포함)
diff <(gh gist view "$GIST_ID" --filename mccm.json | jq -S '.ccstatusline.config') \
     <(jq -S . "$DST") >/dev/null \
  && echo "검증 OK (글리프 포함 일치)" \
  || echo "⚠️ 불일치 — jq 파이프로 재시도(전사 금지)"
```

### 4-b. worklog 프로필 복원

gist에 `worklog.json` 형제 파일이 있으면 `$HOME/.config/mccm/worklog.json`에 복원한다. (업로드 쪽 2-b 참고 — 이 파일은 mccm.json 안이 아니라 gist의 별도 파일이다.)

> **⚠️ 전사 금지:** `ccstatusline.config`·`claudeMd`와 같은 이유다. **`jq` 파이프로 전체 덮어쓰기**만 한다. 부분 Edit 금지 — gist가 단일 진실원이다.

- gist에 `worklog.json` 파일 자체가 **없으면**: "건너뜀" — 로컬 프로필을 절대 건드리지 않는다. (10단계 `claudeMd` null 가드와 같은 실패 방어다.)
- gist 내용을 **임시 파일에 한 번만** 받아 JSON 객체인지 검증한 뒤 그 임시 파일로만 판정·기록한다 — `gh gist view`를 여러 번 따로 호출하면 판정과 기록 사이에 gist가 바뀔 수 있다(TOCTOU).
- `> "$DST"` 리다이렉트로 직접 받지 않는다. 리다이렉트는 `gh` 실행 전에 `$DST`를 0바이트로 자르므로, 네트워크 실패·인증 만료 시 유일한 로컬 프로필이 빈 파일로 파괴된다.
- 로컬 파일이 **없으면**: `mkdir -p` 후 바로 기록한다.
- **동일**하면(아래 `diff`가 무출력): 스킵.
- **다르면(충돌)**: 차이를 보여주고 **사용자 승인을 받기 전에는 절대 쓰지 않는다** — **(1) 취소**(로컬 유지) / **(2) 대치**(gist로 교체).
- 기록 전에 기존 파일을 타임스탬프 `.bak`으로 백업해 되돌릴 수 있게 한다.
- 승인은 **코드 조건**이며, 플래그가 아니라 **내용 해시**에 묶인다 — 「다름」 분기는 `WL_APPROVED`가
  현재 gist 내용의 sha256과 일치할 때만 기록한다. 첫 실행이 차이와 함께 `WL_APPROVED=<해시>`를 출력하므로,
  사용자가 **(2) 대치**를 고른 경우에만 그 줄을 그대로 붙여 다시 실행한다.
  승인 후 gist가 바뀌었으면 해시가 어긋나 기록되지 않는다 — 사용자가 본 diff가 아닌 내용은 쓰지 않는다.

```bash
GIST_ID=<선택된 gist id>
DST="$HOME/.config/mccm/worklog.json"

# 0) 가드 — gist에 worklog.json 파일 자체가 없으면 아무것도 하지 않는다 (claudeMd 가드와 동일한 이유).
# gist 에 파일이 없는 것과 gh 가 실패한 것(네트워크·인증)을 구분한다.
# 둘 다 로컬을 건드리지 않지만, 원인이 다르면 사용자가 할 일도 다르다.
if ! gh api "gists/$GIST_ID" --jq .id >/dev/null 2>&1; then
  echo "⚠️ gist 를 읽지 못했다 (네트워크·인증·gist id 확인) → 로컬 프로필을 건드리지 않는다"
elif ! gh gist view "$GIST_ID" --filename worklog.json >/dev/null 2>&1; then
  echo "gist 에 worklog.json 없음 → 건너뜀 (로컬 프로필을 건드리지 않는다)"
else
  # 1) gist 내용을 임시 파일에 한 번만 받고 JSON 객체인지 검증한다 (claudeMd 가드와 동등한 수준).
  #    이후 판정·기록은 전부 이 임시 파일로만 한다 — gh 를 다시 호출하지 않는다(TOCTOU 제거).
  #    임시 파일은 대상과 같은 디렉터리에 만든다 — /tmp 가 다른 파일시스템이면
  #    아래 mv 가 cross-device 로 실패해 원자성이 깨진다.
  mkdir -p "$HOME/.config/mccm"
  TMPF="$(mktemp "${DST}.XXXXXX")"
  if ! gh gist view "$GIST_ID" --filename worklog.json > "$TMPF" 2>/dev/null \
     || ! jq -e 'type=="object"' "$TMPF" >/dev/null 2>&1; then
    rm -f "$TMPF"
    echo "⚠️ gist 의 worklog.json 을 못 읽거나 JSON 객체가 아님 → 로컬 유지"
  else
    # 2) 없음 / 동일 / 다름 3분기 (JSON 값끼리 비교)
    #    디렉터리·심링크 등 "일반 파일이 아닌 무언가"가 자리를 차지하고 있으면
    #    없음으로 오판하면 안 된다 — mv 가 그 안으로 성공해 쓰레기 파일을 흘린다.
    if [ -e "$DST" ] && [ ! -f "$DST" ]; then
      STATE="비정상"
    elif [ ! -e "$DST" ]; then
      STATE="없음"
    elif diff <(jq -S . "$TMPF") <(jq -S . "$DST" 2>/dev/null) >/dev/null; then
      STATE="동일"
    else
      STATE="다름"
    fi
    echo "판정: $STATE"

    # 3) 기록. 승인 게이트는 산문이 아니라 아래 코드 조건이다 — 주석은 게이트가 아니다.
    #    "다름"은 기존 로컬 프로필을 덮어쓰는 유일한 분기라, diff 를 보여준 뒤
    #    WL_APPROVED 가 아래 WL_TOKEN(내용 해시)과 일치할 때만 쓴다.
    #    플래그가 아니라 해시다 — 이 주석을 "1 이면 된다"로 되돌리지 마라.
    #    없거나 어긋나면 아무것도 쓰지 않고 로컬을 유지한다.
    #    기록은 전체 덮어쓰기로만 — 전사/부분 Edit 금지.
    # 승인 토큰 = 지금 받아 둔 내용의 해시. "승인했다"가 아니라 "이 내용을 승인했다"여야 한다.
    # 사용자가 diff 를 보고 승인하는 사이 gist 가 바뀌면, 플래그 하나로는 본 적 없는
    # 내용이 그대로 기록된다 — 승인 루프가 두 번의 실행에 걸쳐 있어 TOCTOU 가 되살아난다.
    # sha256sum 이 없으면 파이프가 끊겨 jq 가 EPIPE 오류를 뱉으므로 양쪽 다 잠재운다.
    # ⚠ 아래 -z 검사가 잡는 것은 sha256sum 부재뿐이다. jq 가 실패하면 빈 스트림이 해싱돼
    #   e3b0c442… 라는 "비어 있지 않고 그럴듯한" 토큰이 나온다. 그래도 안전한 이유는
    #   TMPF 가 바로 위에서 jq -e 'type=="object"' 로 검증됐기 때문이다.
    #   이 패턴을 검증 없는 입력에 옮기면 fail-open 이 된다 — 전제를 함께 옮겨라.
    WL_TOKEN="$( { jq -S . "$TMPF" 2>/dev/null | sha256sum 2>/dev/null; } | cut -d' ' -f1)"

    wl_write() {   # $1=1 이면 기존 파일을 백업한다. 성공 시 rc0.
      local bak
      # sha256sum 이 없으면 해시 승인이 성립하지 않는다.
      # 덮어쓰기($1=1)는 파괴적이므로 중단하고, 새로 만드는 경로는 잃을 것이 없으니
      # 기록하되 검증을 생략한다고 밝힌다 — 위험이 다른 두 경로를 같게 다루지 않는다.
      if [ -z "${WL_TOKEN:-}" ]; then
        if [ "$1" = 1 ]; then
          echo "⚠️ sha256sum 을 쓸 수 없어 승인·검증이 불가능하다 → 덮어쓰지 않는다"
          rm -f "$TMPF"; return 1
        fi
        echo "⚠️ sha256sum 없음 → 기록하되 사후 검증은 생략한다"
        mv "$TMPF" "$DST" || { rm -f "$TMPF"; return 1; }
        return 0
      fi
      if [ "$1" = 1 ]; then
        # 같은 초에 두 번 대치해도 백업이 덮이지 않도록 mktemp 로 유일한 이름을 받는다.
        bak="$(mktemp --suffix=.bak "$DST.$(date +%Y%m%d-%H%M%S).XXXXXX" 2>/dev/null)" \
          || bak="$DST.$(date +%Y%m%d-%H%M%S).$$.bak"
        cp "$DST" "$bak" || { echo "⚠️ 백업 실패 → 기록하지 않는다"; rm -f "$TMPF"; return 1; }
        echo "백업: $bak"
      fi
      mv "$TMPF" "$DST" || { rm -f "$TMPF"; return 1; }   # 원자적 교체 — 부분 기록 없음
      # 검증 기준값은 mv 전에 뜬 해시다 — 기록 후 gh 를 다시 부르면 위에서 없앤 TOCTOU 가 되살아난다.
      [ "$( { jq -S . "$DST" 2>/dev/null | sha256sum 2>/dev/null; } | cut -d' ' -f1)" = "$WL_TOKEN" ]
    }

    case "$STATE" in
      비정상)
        rm -f "$TMPF"
        echo "⚠️ $DST 가 일반 파일이 아니다(디렉터리·특수파일) → 손대지 않는다"
        echo "   직접 확인하고 치운 뒤 다시 실행해라."
        ;;
      동일)
        rm -f "$TMPF"
        echo "동일 → 스킵"
        ;;
      없음)
        # 덮어쓸 로컬 파일이 없으므로 파괴 위험이 없다 → 승인 없이 기록한다.
        wl_write 0 && echo "worklog 프로필 복원 OK" || echo "⚠️ 복원 실패 → 로컬 유지"
        ;;
      다름)
        echo "--- 차이 (< 로컬 / > gist) ---"
        diff <(jq -S . "$DST") <(jq -S . "$TMPF") | head -60
        if [ -z "$WL_TOKEN" ]; then
          # 승인 토큰을 만들 수 없다. gist 가 바뀐 것이 아니므로 그렇게 말하지 않는다.
          rm -f "$TMPF"
          echo "⚠️ sha256sum 을 쓸 수 없어 승인 토큰을 만들 수 없다 → 로컬 유지"
          echo "   이 PC 에서는 덮어쓰기 복원을 할 수 없다. coreutils 를 설치하거나"
          echo "   위 차이를 보고 직접 편집해라."
        elif [ -n "${WL_APPROVED:-}" ] && [ "$WL_APPROVED" = "$WL_TOKEN" ]; then
          wl_write 1 && echo "worklog 프로필 대치 OK" || echo "⚠️ 대치 실패 → 백업으로 되돌릴 수 있다"
        elif [ -n "${WL_APPROVED:-}" ]; then
          # 승인은 받았는데 내용이 그 사이 바뀌었다 — 사용자가 본 diff 가 아니다.
          rm -f "$TMPF"
          echo "⚠️ 승인 토큰이 현재 gist 내용과 일치하지 않는다 → 로컬 유지 (아무것도 쓰지 않았다)"
          echo "   승인 이후 gist 가 바뀌었다. 위 차이를 다시 확인받고 새 토큰으로 실행해라."
        else
          rm -f "$TMPF"
          echo "⚠️ 승인 없음 → 로컬 유지 (아무것도 쓰지 않았다)"
          echo "   위 차이를 사용자에게 보여주고 (1) 취소 / (2) 대치 를 물어라."
          echo "   '대치'를 고른 경우에만 아래를 붙여 이 블록을 다시 실행한다:"
          echo "     WL_APPROVED=$WL_TOKEN"
        fi
        ;;
    esac
  fi
fi
```

복원(또는 스킵) 후 진단 CLI로 결과를 확인한다:

```bash
PROFILE_SH="$(find "$HOME/.claude/plugins/cache" "$HOME/.claude/skills" \
  -path '*/worklog/skills/today/_profile.sh' 2>/dev/null | sort -r | head -1)"
[ -n "$PROFILE_SH" ] && bash "$PROFILE_SH" --check || echo "worklog 플러그인 미설치 — 진단 생략"
```

### 5. settings

mccm.json의 `settings`를 settings.json과 비교한다. 변수 치환 적용 후 비교.

**충돌이 없는 경우** (mccm.json에만 있는 키): 바로 추가.

**충돌이 있는 경우** (같은 키에 다른 값): 사용자에게 물어본다:
- 각 충돌 항목을 표시: `키: mccm.json 값 vs settings.json 값`
- 선택지 제시: **(1) 취소** (기존 유지) / **(2) 대치** (mccm.json 값으로 교체)
- 사용자 선택에 따라 적용

> `statusLine` 블록이 mccm.json에 있으면 settings.json에 반영한다. 단 이 블록은 ccstatusline 바이너리가 PATH에 있어야 정상 동작하므로, 3단계에서 ccstatusline 설치를 건너뛴/거부한 경우 statusLine 적용도 보류하고 사용자에게 알린다.

### 6. mcpServers

mccm.json의 `mcpServers`를 settings.json의 `mcpServers`와 비교한다. 변수 치환 적용.

- 새 서버: 바로 추가
- 기존 서버와 충돌: 5단계와 동일하게 사용자에게 물어본다

### 7. hooks

mccm.json의 `hooks`를 settings.json의 `hooks`와 비교한다. 변수 치환 적용.

**⚠️ 보안:** hooks는 Claude Code 세션에서 자동 실행되므로, 새 hook과 충돌 hook 모두 사용자 확인이 필수이다.

- 새 hook: event, matcher, command를 보여주고 사용자 승인 후 추가
- 기존 hook과 충돌 (동일 event + matcher에 다른 command): 사용자에게 물어본다

사용자가 거부한 hook은 스킵하고 완료 보고에 "스킵됨"으로 기록한다.

### 8. 로컬 전용 항목 감지 (완전 동기화)

settings.json에는 있지만 mccm.json에는 없는 항목을 감지한다:

- `enabledPlugins`에 있지만 mccm.json `plugins`에 없는 플러그인
- `mcpServers`에 있지만 mccm.json `mcpServers`에 없는 서버
- `hooks`에 있지만 mccm.json `hooks`에 없는 hook

감지된 항목이 있으면 사용자에게 목록을 보여주고 물어본다:
> 아래 항목은 로컬에만 존재하고 Gist에는 없습니다:
> - (항목 목록)
>
> **(1) 유지** (로컬에만 남김) / **(2) 삭제** (Gist 기준으로 완전 동기화)

사용자가 **(2) 삭제**를 선택하면:
- 플러그인: `claude plugin uninstall` 실행
- mcpServers, hooks: settings.json에서 제거

### 9. settings.json 저장

모든 변경을 적용하여 `$HOME/.claude/settings.json`에 저장한다.

Read 도구로 파일을 읽고, 변경 사항을 Edit 도구로 적용한다.

### 10. CLAUDE.md 복원

mccm.json에 `claudeMd` 문자열이 있으면 `$HOME/.claude/CLAUDE.md`에 복원한다.

> **⚠️ 전사 금지:** `ccstatusline.config`와 같은 이유다. 모델이 읽어 옮겨 적으면 줄바꿈·들여쓰기가 어긋나거나 긴 내용이 잘린다. **`jq -r` 파이프로 전체 덮어쓰기**만 한다. 부분 Edit 금지 — gist가 단일 진실원이다.

- 로컬 파일이 **없으면**: 바로 기록한다.
- **동일**하면(아래 `diff`가 무출력): 스킵.
- **다르면(충돌)**: 차이를 보여주고 물어본다 — **(1) 취소**(로컬 유지) / **(2) 대치**(gist로 교체).

플러그인이 hook으로 주입하는 정책(예: `mccm/dev`의 `model-routing.md`)은 CLAUDE.md에 들어 있지 않다. 로컬 CLAUDE.md에 그런 내용이 남아 있으면 중복이니 사용자에게 알린다.

```bash
GIST_ID=<선택된 gist id>
DST="$HOME/.claude/CLAUDE.md"
gh gist view "$GIST_ID" --filename mccm.json > /tmp/mccm.json

# 0) 가드 — claudeMd 가 없거나 null 이면 아무것도 하지 않는다.
#    이 가드가 없으면 jq 가 리터럴 "null" 을 출력해 로컬 CLAUDE.md 를 파괴하고,
#    다음 upload 가 그 "null" 을 gist 에 올려 모든 PC 로 퍼진다.
if [ "$(jq -r 'has("claudeMd") and (.claudeMd != null)' /tmp/mccm.json)" != "true" ]; then
  echo "gist 에 claudeMd 없음 → 건너뜀 (로컬 CLAUDE.md 를 건드리지 않는다)"
else
  # 1) 세 갈래를 명시적으로 구분한다: 없음 / 동일 / 다름.
  #    비교는 원시 바이트가 아니라 JSON 값끼리 한다 — jq 의 raw 출력은
  #    플랫폼에 따라 줄바꿈이 달라져 바이트 비교가 상시 "다름"으로 나온다.
  if [ ! -f "$DST" ]; then
    STATE="없음"
  elif diff <(jq '.claudeMd' /tmp/mccm.json) <(sed 's/$//' "$DST" | jq -Rs .) >/dev/null; then
    STATE="동일"
  else
    STATE="다름"
  fi
  echo "판정: $STATE"

  # 2) "없음"이면 바로 기록, "다름"이면 사용자 확인 후 기록, "동일"이면 스킵.
  #    기록은 전체 덮어쓰기로만 — 전사/부분 Edit 금지.
  #    쓸 때 LF 로 정규화한다(Windows jq 는 raw 출력에서 CRLF 를 낸다).
  if [ "$STATE" != "동일" ]; then
    mkdir -p "$HOME/.claude"
    jq -j '.claudeMd' /tmp/mccm.json | sed 's/$//' > "$DST"

    # 3) 기록 후 검증
    diff <(jq '.claudeMd' /tmp/mccm.json) <(sed 's/$//' "$DST" | jq -Rs .) >/dev/null       && echo "검증 OK (원문 일치)"       || echo "⚠️ 불일치 — jq 파이프로 재시도(전사 금지)"
  fi
fi
rm -f /tmp/mccm.json
```

### 11. 완료 보고

- 등록/업데이트된 마켓플레이스
- 설치/업데이트된 플러그인
- 복원된 ccstatusline 설정 (라인/항목 수, 충돌 해결 결과)
- 병합된 settings 항목
- 추가된 mcpServers
- 추가된 hooks
- 설치된 CLI 도구
- 충돌 해결 결과
- 삭제된 로컬 전용 항목 (있는 경우)
- **worklog 프로필 적용/미적용 (반드시 명시)** — 어느 한 PC만 `/upload`에서 worklog 동기화를 켜지 않았을 때 보고서 형식이 조용히 달라지는 것을 사람이 알아챌 수 있는 유일한 장치이므로, "없어서 생략"도 항목 자체는 반드시 남긴다
