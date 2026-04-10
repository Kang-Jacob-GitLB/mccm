# mccm

**m**y-**c**laude-**c**ode-**m**arketplace — Claude Code 플러그인 마켓플레이스.

## 플러그인

### dev — 개발 스킬팩

| 스킬 | 설명 |
|------|------|
| [commit](plugins/dev/skills/commit/) | Git 커밋 스킬 — 보안 검토, 브랜치 생성, 스테이징, 커밋 메시지 작성 |
| [pr](plugins/dev/skills/pr/) | PR 생성 스킬 — push, 제목/본문 생성, assignee, label 자동 설정, Actions 체크 추적 |
| [cleanup](plugins/dev/skills/cleanup/) | 리모트 동기화 스킬 — 기본 브랜치 이동, pull, prune, 로컬 브랜치 정리 |
| [md-to-pdf](plugins/dev/skills/md-to-pdf/) | Markdown → PDF 변환 — GitHub 웹 스타일 렌더링 |
| [md-to-gdoc](plugins/dev/skills/md-to-gdoc/) | Markdown → Google Docs 변환 — GitHub 스타일 서식, gws CLI 사용 |

### env — 환경 동기화

여러 PC에서 동일한 Claude Code 환경을 유지. GitHub Gist의 `mccm.json`에 플러그인, MCP 서버, hooks, settings를 선언하고 동기화한다. 각 사용자는 자기 GitHub 계정의 gist에 `mccm.json` 파일을 만들어 사용한다.

| 스킬 | 설명 |
|------|------|
| [download](plugins/env/skills/download/) | Gist → 로컬 적용 — 충돌 시 사용자 확인, 로컬 전용 항목 삭제 선택 |
| [upload](plugins/env/skills/upload/) | 로컬 → Gist 업로드 — Gist 전용 항목 삭제 선택, 사용자 확인 후 반영 |

**사전 요구사항:** [GitHub CLI (`gh`)](https://cli.github.com/) 설치 및 인증 (`gh auth login`)

**mccm.json 관리 범위:**

| 항목 | mccm.json 키 | settings.json 매핑 |
|------|------------|-------------------|
| 마켓플레이스 | `marketplaces` | `extraKnownMarketplaces` |
| 플러그인 | `plugins` | `enabledPlugins` |
| CLI 도구 | `clis` | — (check/install 명령으로 관리) |
| MCP 서버 | `mcpServers` | `mcpServers` |
| hooks | `hooks` | `hooks` |
| 설정 | `settings` | 최상위 키 (language, env 등) |

경로에 머신 의존값이 포함되면 변수 치환을 사용한다: `${HOME}`, `${USER}`

## 설치 방법

```bash
claude plugin marketplace add Kang-Jacob-GitLB/mccm
claude plugin install env@mccm
```

설치 후 `/download` 실행하면 Gist의 mccm.json 기반으로 전체 환경(플러그인, MCP, hooks, settings)이 구성된다.

환경을 변경한 후 `/upload`로 Gist에 반영하면 다른 PC에서 `/download`로 동기화할 수 있다.

## 프로젝트별 커스터마이즈

각 스킬은 프로젝트의 `CLAUDE.md`에서 해당 섹션을 찾아 **명시된 슬롯만** 오버라이드한다. 명시되지 않은 슬롯은 기본값을 사용한다. 각 슬롯의 기본값은 해당 SKILL.md를 참조한다.

| 스킬 | CLAUDE.md 섹션 | 슬롯 |
|------|---------------|------|
| commit | `## mccm:Commit Conventions` | language, title-format, types, title-max-length, body, branch-prefixes, branch-format |
| pr | `## mccm:PR Conventions` | base-branch, language, title-format, types, title-max-length, body-format, label-map, auto-assignee, checks-timeout |
| cleanup | `## mccm:Cleanup Conventions` | default-branch, protected-branches |

예시 (`CLAUDE.md`):

```markdown
## mccm:Commit Conventions
- language: 한글
- title-format: {제목}
- types: add, fix, update, remove
- title-max-length: 40
- body: 필수

## mccm:PR Conventions
- language: 한글
- title-format: [{타입}] {제목}
- label-map: feat→enhancement, fix→bug

## mccm:Cleanup Conventions
- protected-branches: main, master, develop
```

## 플러그인 구조

```
mccm/
├── .claude-plugin/
│   └── marketplace.json
└── plugins/
    ├── dev/
    │   ├── .claude-plugin/
    │   │   └── plugin.json
    │   └── skills/
    │       ├── commit/
    │       │   └── SKILL.md
    │       ├── pr/
    │       │   └── SKILL.md
    │       ├── cleanup/
    │       │   └── SKILL.md
    │       ├── md-to-pdf/
    │       │   └── SKILL.md
    │       └── md-to-gdoc/
    │           └── SKILL.md
    └── env/
        ├── .claude-plugin/
        │   └── plugin.json
        └── skills/              ← mccm.json은 gist로 관리
            ├── download/
            │   └── SKILL.md
            └── upload/
                └── SKILL.md
```

## 새 스킬 추가 방법

1. `plugins/{플러그인}/skills/{skill-name}/SKILL.md` 작성
2. PR 생성 → 리뷰 → 머지
3. 사용자는 세션 시작 시 자동 업데이트 (또는 `claude plugin marketplace update mccm`)
