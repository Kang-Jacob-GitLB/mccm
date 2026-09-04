# mccm 개발 규칙

## 환경 동기화

GitHub Gist의 `mccm.json`으로 여러 PC의 Claude Code 환경(플러그인, MCP, hooks, settings, CLI 도구)을 동기화한다. `/download`로 Gist→로컬 적용, `/upload`로 로컬→Gist 업로드.

## 스킬 변경 시 체크리스트

스킬 추가/수정/삭제 시 아래 항목을 반드시 수행한다:

1. `plugins/{플러그인}/skills/{skill-name}/SKILL.md` 작성/수정/삭제
2. `plugins/{플러그인}/.claude-plugin/plugin.json` — description, keywords 반영
3. `.claude-plugin/marketplace.json` — description 반영
4. `README.md` — 스킬 목록 테이블, 플러그인 구조 트리 반영
5. 워크로그 프로필 스키마를 바꿀 때는 `_profile.sh`(today·week **두 사본** — `diff`로 동일 확인), today·week SKILL.md의 대체 규칙, `worklog.example.json`, env의 download/upload 단계, README를 **함께** 고친다. (`_profile.sh`는 두 벌 존재한다 — 기존 `_tz.sh` 두 사본이 이미 어긋나 있는 것이 선례다: today 86행 / week 75행. 그래서 `bash plugins/worklog/skills/today/_profile.sh --check`에 두 사본 `cmp` 자기 검사를 넣어 두었다: 어긋나면 rc2로 실패한다. 어느 쪽에서 실행해도 발화하지만 **호출해야만 돈다** — 커밋 전에 직접 돌려라.)
6. 버전업 — `plugin.json` + `marketplace.json` 동시 변경
   - 호환 깨지는 변경 (스킬 삭제, 슬롯 이름 변경): major (1.1.0 → 2.0.0)
   - 새 기능 추가 (스킬 추가): minor (1.1.0 → 1.2.0)
   - 버그 수정, 문구 수정: patch (1.1.0 → 1.1.1)
   - 여러 변경이 섞이면 가장 높은 단계를 따른다 (major > minor > patch)

## 에이전트 변경 시 체크리스트

서브에이전트(`plugins/dev/agents/*.md`) 추가/수정/삭제 시 아래 항목을 반드시 수행한다:

1. `plugins/dev/agents/{name}.md` 작성/수정/삭제 — frontmatter의 `tools` allowlist와 `model` 티어를 확인한다. `tools`를 생략하면 MCP 하드웨어 제어 툴까지 전부 상속하므로 쓰기 권한 에이전트에는 반드시 명시.
2. `plugins/dev/model-routing.md` — 위임 권한(하네스 기본 지시 대비 우선순위)·티어 목록·라우팅표·강등/위임 규칙·부작용 축에 반영. SessionStart 훅으로 주입되는 라이브 문서이므로 실제 로스터와 어긋나면 안 된다. 에이전트의 부작용 등급이나 거부 조항을 바꿨으면 「부작용 축」도 함께 고친다.
3. `README.md` — 에이전트 목록 테이블, 플러그인 구조 트리 반영.
4. 참조 확인 — 삭제·개명 시 이 에이전트를 참조하는 스킬·훅·CLAUDE.md 절차가 있는지 grep으로 확인.
5. 버전업 — `plugin.json` + `marketplace.json` 동시 변경
   - 호환 깨지는 변경 (에이전트 삭제·개명): major
   - 새 에이전트 추가: minor
   - 프롬프트·문구 수정: patch
   - 여러 변경이 섞이면 가장 높은 단계를 따른다 (major > minor > patch)

## 커밋 규칙

- 형식: `{type}: {제목}` (본문은 선택)
- 타입: feat, fix, refactor, docs, chore
- 여러 커밋이 쌓여 있으면 squash하여 하나로 커밋
- 커밋 전 위 체크리스트 완료 여부 확인

## 스킬 보안 검토 (커밋 전 필수)

스킬(SKILL.md)이 추가/수정된 커밋에는 반드시 아래 보안 검토를 수행한다. 검토 통과 전까지 커밋하지 않는다.

### 검토 항목

1. **명령어 인젝션** — 사용자 입력이 `!`백틱 명령이나 `Bash` 호출에 검증 없이 삽입되는지
2. **위험 명령** — `rm -rf`, `curl | sh`, `eval`, `exec`, `--force`, `--no-verify` 등 파괴적/우회 명령 사용 여부
3. **민감 정보 노출** — 토큰, 키, 비밀번호, 내부 URL이 하드코딩되어 있는지
4. **권한 과다** — `allowed-tools`에 불필요한 도구(Write, Edit 등)가 포함되어 있는지
5. **외부 통신** — 의도하지 않은 외부 서버로의 데이터 전송(`curl`, `wget`, `gh api` 등)이 있는지
6. **경로 탈출** — `../`, 절대 경로 등으로 의도하지 않은 디렉토리에 접근하는지

### 절차

1. `dev:security-reviewer` 에이전트를 spawn하여 변경된 파일을 검토한다. (플러그인 미설치 등으로 없으면 OMC의 `oh-my-claudecode:security-reviewer`로 폴백한다.)
2. **문제 없음** → "보안 검토 통과" 보고 후 커밋 진행.
3. **문제 발견** → 항목별로 위험 내용과 수정안을 보고하고, 수정 후 재검토한다.

## Skill routing

When the user's request matches an available skill, ALWAYS invoke it using the Skill
tool as your FIRST action. Do NOT answer directly, do NOT use other tools first.
The skill has specialized workflows that produce better results than ad-hoc answers.

Key routing rules:
- Product ideas, "is this worth building", brainstorming → invoke office-hours
- Bugs, errors, "why is this broken", 500 errors → invoke investigate
- Ship, deploy, push, create PR → invoke ship
- QA, test the site, find bugs → invoke qa
- Code review, check my diff → invoke review
- Update docs after shipping → invoke document-release
- Weekly retro → invoke retro
- Design system, brand → invoke design-consultation
- Visual audit, design polish → invoke design-review
- Architecture review → invoke plan-eng-review
- Save progress, checkpoint, resume → invoke checkpoint
- Code quality, health check → invoke health
