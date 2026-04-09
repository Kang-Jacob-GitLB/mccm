# jacob-plugin

개인용 Claude Code 플러그인 마켓플레이스.

## 플러그인 목록

| 플러그인 | 설명 |
|---------|------|
| [commit](plugins/commit/) | Git 커밋 스킬 — 보안 검토, 브랜치 생성, 스테이징, 커밋 메시지 작성 |
| [pr](plugins/pr/) | PR 생성 스킬 — push, 제목/본문 생성, assignee, label 자동 설정 |
| [cleanup](plugins/cleanup/) | 리모트 동기화 스킬 — 기본 브랜치 이동, pull, prune, 로컬 브랜치 정리 |

## 설치 방법

### 1. 마켓플레이스 등록 (1회)

```bash
claude plugin marketplace add Kang-Jacob-GitLB/jacob-plugin
```

### 2. 플러그인 설치

#### 개별 설치

```bash
claude plugin install <plugin-name>@jacob-plugin
```

#### 전체 설치

```bash
claude plugin install commit@jacob-plugin
claude plugin install pr@jacob-plugin
claude plugin install cleanup@jacob-plugin
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

각 플러그인은 아래 구조를 따른다:

```
plugins/{plugin-name}/
├── .claude-plugin/
│   └── plugin.json           ← 플러그인 메타데이터 (필수)
├── skills/
│   └── {skill-name}/
│       └── SKILL.md          ← 스킬 정의 (필수)
├── scripts/                  ← 설치/유틸 스크립트 (선택)
│   └── install.sh
└── evals/                    ← 트리거 평가 (선택)
    └── trigger-eval.json
```

### plugin.json 형식

```json
{
  "name": "plugin-name",
  "version": "1.0.0",
  "description": "플러그인 설명",
  "author": {
    "name": "jacob",
    "email": "jacob@litbig.com"
  },
  "license": "MIT",
  "keywords": ["git", "workflow"],
  "skills": "./skills/"
}
```

## 새 플러그인 배포 방법

1. `plugins/{plugin-name}/` 디렉토리 생성
2. `.claude-plugin/plugin.json` 작성
3. `skills/{skill-name}/SKILL.md` 작성
4. PR 생성 → 리뷰 → 머지
5. 사용자는 `claude plugin marketplace update jacob-plugin` 후 설치

## 플러그인 업데이트

```bash
claude plugin marketplace update jacob-plugin
claude plugin update {plugin-name}@jacob-plugin
```
