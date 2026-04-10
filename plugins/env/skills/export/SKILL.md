---
name: export
description: 현재 PC의 settings.json에서 env.json을 생성/갱신한다. "/export", "환경 내보내기", "export env" 등의 요청에 사용한다.
allowed-tools: Bash, Read, Edit
---

## 현재 상태

- settings.json: !`cat "$HOME/.claude/settings.json" 2>/dev/null || echo "not found"`
- 현재 env.json (gist): !`gh gist view 7360c28bfd37c47cd7d19d4106224e45 --filename env.json 2>/dev/null || echo "not found"`

## 변수 치환 규칙 (역방향)

settings.json의 값을 env.json에 저장할 때, 머신 의존 경로를 변수로 치환한다:
- 홈 디렉토리 경로 (`$HOME` 또는 `$USERPROFILE` 값) → `${HOME}`
- 사용자명 (`$USER` 또는 `$USERNAME` 값) → `${USER}`

## 작업 지침

현재 PC의 settings.json을 분석하여 env.json을 생성한다.

### 1. settings.json 분석

settings.json에서 아래 섹션을 추출한다:

| settings.json 키 | env.json 매핑 |
|---|---|
| `extraKnownMarketplaces` | `marketplaces` 배열 |
| `enabledPlugins` (값이 `true`인 것만) | `plugins` 객체 (`"latest"`) |
| `mcpServers` | `mcpServers` 객체 |
| `hooks` | `hooks` 객체 |
| 나머지 포터블 설정 | `settings` 객체 |

**제외 항목** (머신별 상태이므로):
- `feedbackSurveyState`
- `permissions` (비어있으면)
- `enabledPlugins` (plugins 섹션으로 이동)
- `extraKnownMarketplaces` (marketplaces 섹션으로 이동)

### 2. 변수 치환 (역방향)

모든 문자열 값에서 머신 의존 경로를 `${HOME}`, `${USER}` 변수로 교체한다.

### 3. env.json 생성

위에서 추출한 데이터를 env.json 형식으로 구성한다:

```json
{
  "marketplaces": [...],
  "plugins": { "name@marketplace": "latest", ... },
  "mcpServers": { ... },
  "hooks": { ... },
  "settings": { ... }
}
```

### 4. 사용자 확인

생성된 env.json 내용을 사용자에게 보여주고 확인을 받는다.

### 5. gist 업데이트

```bash
# env.json을 임시 파일에 저장
cat > /tmp/mccm-env.json <<'EOF'
{생성된 env.json 내용}
EOF

# gist 업데이트
gh gist edit 7360c28bfd37c47cd7d19d4106224e45 --filename env.json --add /tmp/mccm-env.json
rm -f /tmp/mccm-env.json
```

### 6. 완료 보고

- 추출된 마켓플레이스 수
- 추출된 플러그인 수
- 추출된 MCP 서버 수
- 추출된 hook 수
- 추출된 설정 항목 수
