# jacob-plugin

개인용 Claude Code 플러그인.

## 스킬 목록

| 스킬 | 설명 |
|------|------|
| [commit](plugins/devpack/skills/commit/) | Git 커밋 스킬 — 보안 검토, 브랜치 생성, 스테이징, 커밋 메시지 작성 |
| [pr](plugins/devpack/skills/pr/) | PR 생성 스킬 — push, 제목/본문 생성, assignee, label 자동 설정, Actions 체크 추적 |
| [cleanup](plugins/devpack/skills/cleanup/) | 리모트 동기화 스킬 — 기본 브랜치 이동, pull, prune, 로컬 브랜치 정리 |
| [md-to-pdf](plugins/devpack/skills/md-to-pdf/) | Markdown → PDF 변환 — GitHub 웹 스타일 렌더링 |
| [md-to-gdoc](plugins/devpack/skills/md-to-gdoc/) | Markdown → Google Docs 변환 — GitHub 스타일 서식, gws CLI 사용 |

## 설치 방법

### 1. 마켓플레이스 등록 (1회)

```bash
claude plugin marketplace add Kang-Jacob-GitLB/jacob-plugin
```

### 2. 플러그인 설치

```bash
claude plugin install devpack@jacob-plugin
```

### 3. 플러그인 업데이트

세션 시작 시 자동으로 마켓플레이스가 업데이트된다. 수동으로 업데이트하려면:

```bash
claude plugin marketplace update jacob-plugin
claude plugin update devpack@jacob-plugin
```

## 프로젝트별 커스터마이즈

각 스킬은 프로젝트의 `CLAUDE.md`에서 해당 섹션을 찾아 **명시된 슬롯만** 오버라이드한다. 명시되지 않은 슬롯은 기본값을 사용한다. 각 슬롯의 기본값은 해당 SKILL.md를 참조한다.

| 스킬 | CLAUDE.md 섹션 | 슬롯 |
|------|---------------|------|
| commit | `## jacob-plugin:Commit Conventions` | language, title-format, types, title-max-length, body, branch-prefixes, branch-format |
| pr | `## jacob-plugin:PR Conventions` | base-branch, language, title-format, types, title-max-length, body-format, label-map, auto-assignee, checks-timeout |
| cleanup | `## jacob-plugin:Cleanup Conventions` | default-branch, protected-branches |

예시 (`CLAUDE.md`):

```markdown
## jacob-plugin:Commit Conventions
- language: 한글
- title-format: {제목}
- types: add, fix, update, remove
- title-max-length: 40
- body: 필수

## jacob-plugin:PR Conventions
- language: 한글
- title-format: [{타입}] {제목}
- label-map: feat→enhancement, fix→bug

## jacob-plugin:Cleanup Conventions
- protected-branches: main, master, develop
```

## 플러그인 구조

```
jacob-plugin/
├── .claude-plugin/
│   └── marketplace.json          ← 마켓플레이스 메타데이터
└── plugins/
    └── jacob-plugin/
        ├── .claude-plugin/
        │   └── plugin.json       ← 플러그인 메타데이터
        └── skills/
            ├── commit/
            │   └── SKILL.md
            ├── pr/
            │   └── SKILL.md
            ├── cleanup/
            │   └── SKILL.md
            ├── md-to-pdf/
            │   └── SKILL.md
            └── md-to-gdoc/
                └── SKILL.md
```

## 새 스킬 추가 방법

1. `skills/{skill-name}/SKILL.md` 작성
2. PR 생성 → 리뷰 → 머지
3. 사용자는 `claude plugin marketplace update jacob-plugin` 후 업데이트
