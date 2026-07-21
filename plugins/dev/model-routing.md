<model_routing>
서브에이전트(Agent 툴)와 워크플로 stage는 **항상 아래 티어 에이전트 중 하나로 라우팅한다.**
`agentType`을 지정하지 않으면 부모 세션 모델을 그대로 상속하므로, 미지정은 금지한다.

T0 `haiku`  — 기계적·읽기전용·대량 출력
  `dev:explorer`      파일/심볼 위치 탐색, 넓은 grep·glob 스윕
  `dev:log-sifter`    빌드·테스트·CI 로그에서 에러/경고만 추출
  `dev:build-runner`  빌드·테스트 명령 실행 후 성패+에러 요약만 반환

T1 `sonnet` — 표준 작업
  `dev:researcher`    코드 동작 조사, 호출 경로 추적, 공식 문서 조회
  `dev:executor`      명세가 분명한 코드 수정
  `dev:test-writer`   테스트·재현 하네스 작성
  `dev:writer`        한국어 문서·주석·커밋/PR 본문

T2 `opus`   — 판단·판정 (강등 금지)
  `dev:architect`     설계·트레이드오프·구현 계획
  `dev:code-reviewer` 코드 리뷰
  `dev:verifier`      적대적 검증(반증 시도)
  `dev:synthesizer`   다중 결과 합성·최종 판정

## 업무량 축 (중요도와 별개로 적용)

- fan-out이 **8개 항목 이상**이면 항목당 stage를 한 티어 강등한다. 비용은 티어가 아니라 티어×개수에서 난다.
- 단 **최종 verify/judge stage는 강등 예외** — 판정이 틀리면 그 위의 모든 작업이 무의미해진다.
- 로그·빌드 출력·대용량 파일은 T0로 1차 필터링한 뒤 **요약만** 상위 티어에 넘긴다.
- 강등한 stage가 실패하거나 저품질로 반환하면 **그 항목만** 한 티어 승격해 재시도한다(staged escalation). 전체를 승격하지 않는다.

## 주의

- 내장 `Explore`/`general-purpose`/`Plan`은 정의 파일이 없어 티어링이 걸리지 않는다(= 부모 모델 상속). 위 에이전트로 대체해 쓴다.
- 워크플로 `agent(prompt, {model, effort})` per-call 오버라이드는 frontmatter를 이긴다. 정책에서 벗어나야 할 때만 쓰고, 이유를 `log()`로 남긴다.
- `CLAUDE_CODE_SUBAGENT_MODEL` / `CLAUDE_CODE_EFFORT_LEVEL` 환경변수는 **비워 둔다.** 이 둘은 해석 순서 1순위라 per-call 오버라이드와 frontmatter를 **둘 다** 덮어써서 티어링을 통째로 무력화한다. (전부 싸게 돌리는 한시적 킬스위치로만 사용)
- 에이전트 정의는 이 플러그인(`mccm/dev`)이 제공한다. 플러그인 에이전트는 우선순위 **최하위**이므로, 로컬 `~/.claude/agents/`나 프로젝트 `.claude/agents/`에 같은 이름이 있으면 그쪽이 이긴다.
</model_routing>
