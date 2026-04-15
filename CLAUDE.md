# mccm 개발 규칙

## 환경 동기화

GitHub Gist의 `mccm.json`으로 여러 PC의 Claude Code 환경(플러그인, MCP, hooks, settings, CLI 도구)을 동기화한다. `/download`로 Gist→로컬 적용, `/upload`로 로컬→Gist 업로드.

## 스킬 변경 시 체크리스트

스킬 추가/수정/삭제 시 아래 항목을 반드시 수행한다:

1. `plugins/{플러그인}/skills/{skill-name}/SKILL.md` 작성/수정/삭제
2. `plugins/{플러그인}/.claude-plugin/plugin.json` — description, keywords 반영
3. `.claude-plugin/marketplace.json` — description 반영
4. `README.md` — 스킬 목록 테이블, 플러그인 구조 트리 반영
5. 버전업 — `plugin.json` + `marketplace.json` 동시 변경
   - 호환 깨지는 변경 (스킬 삭제, 슬롯 이름 변경): major (1.1.0 → 2.0.0)
   - 새 기능 추가 (스킬 추가): minor (1.1.0 → 1.2.0)
   - 버그 수정, 문구 수정: patch (1.1.0 → 1.1.1)
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

1. OMC의 `security-reviewer` 에이전트(`oh-my-claudecode:security-reviewer`)를 spawn하여 변경된 파일을 검토한다.
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
