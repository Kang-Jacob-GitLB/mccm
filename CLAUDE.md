# jacob-plugin 개발 규칙

## 스킬 변경 시 체크리스트

스킬 추가/수정/삭제 시 아래 항목을 반드시 수행한다:

1. `plugins/devpack/skills/{skill-name}/SKILL.md` 작성/수정/삭제
2. `plugins/devpack/.claude-plugin/plugin.json` — description, keywords 반영
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
- .omc/ 디렉토리는 스테이징하지 않는다
