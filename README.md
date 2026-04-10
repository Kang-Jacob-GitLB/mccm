# mccm

개인용 Claude Code 플러그인 마켓플레이스.

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

여러 PC에서 동일한 Claude Code 환경을 유지. `env.json`에 플러그인, MCP 서버, hooks, settings를 선언하고 동기화한다.

| 스킬 | 설명 |
|------|------|
| [sync](plugins/env/skills/sync/) | env.json 기반 동기화 — 충돌 시 사용자에게 취소/대치/추가 선택 |
| [add](plugins/env/skills/add/) | 환경에 항목 추가 — env.json 수정, git push, 즉시 적용 |
| [export](plugins/env/skills/export/) | 현재 PC의 settings.json에서 env.json 자동 생성 |

**env.json 관리 범위:**

| 항목 | env.json 키 | settings.json 매핑 |
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

설치 후 `/sync` 실행하면 env.json 기반으로 전체 환경(플러그인, MCP, hooks, settings)이 구성된다.

이후 환경 변경은 `/add`로 추가하면 git에 자동 반영되어 다른 PC에서 `/sync`로 동기화된다.

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
        └── skills/              ← env.json은 gist로 관리
            ├── sync/
            │   └── SKILL.md
            ├── add/
            │   └── SKILL.md
            └── export/
                └── SKILL.md
```

## 새 스킬 추가 방법

1. `plugins/{플러그인}/skills/{skill-name}/SKILL.md` 작성
2. PR 생성 → 리뷰 → 머지
3. 사용자는 세션 시작 시 자동 업데이트 (또는 `claude plugin marketplace update mccm`)
