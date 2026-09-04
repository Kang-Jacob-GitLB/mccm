# mccm

**m**y-**c**laude-**c**ode-**m**arketplace — Claude Code 플러그인 마켓플레이스.

## 플러그인

### env — 환경 동기화

새 PC나 다른 장비에서 Claude Code를 쓸 때마다 플러그인, MCP 서버, hooks, settings를 하나씩 다시 설정해야 하고, 팀원에게 구두로 전달하거나 문서를 따로 만들어야 하며, 설정이 각 PC에 흩어져 있어서 어디가 최신인지 알 수 없고, settings.json을 직접 복사하면 경로(홈 디렉토리, 사용자명)가 달라서 그대로 안 된다.

env 플러그인은 `mccm.json` 파일 하나에 환경 전체를 선언적으로 정의하고, GitHub Gist에 저장해서 어디서든 동기화할 수 있게 한다. 경로의 머신 의존값은 `${HOME}`, `${USER}` 변수로 자동 치환되어 OS/사용자가 달라도 동작한다.

| 스킬 | 설명 |
|------|------|
| [download](plugins/env/skills/download/) | Gist → 로컬 적용 — 충돌 시 사용자 확인, 로컬 전용 항목 삭제 선택 |
| [upload](plugins/env/skills/upload/) | 로컬 → Gist 업로드 — Gist 전용 항목 삭제 선택, 사용자 확인 후 반영 |

**사전 요구사항:** [GitHub CLI (`gh`)](https://cli.github.com/) 설치 및 인증 (`gh auth login`)

> **⚠️ 보안 주의:**
> - **MCP 토큰:** `env` 키(API 토큰 등)가 포함된 MCP 서버는 업로드 시 기본 제외됩니다. 명시적으로 선택해야 포함됩니다.
> - **설정 토큰:** `settings.json`의 `env`에 든 인증 정보(키 이름에 `TOKEN`·`KEY`·`SECRET`·`AUTH`·`PASS`·`PWD`·`CREDENTIAL`·`HEADER`·`DSN` 등이 있거나, 값에 `Basic`/`Bearer` 또는 URL 자격증명(`://user:pass@host`)이 포함된 항목)도 업로드 시 기본 제외됩니다. 명시적으로 선택해야 포함됩니다.
> - **CLI 도구:** `clis`의 `check`/`install` 명령은 실행 전 사용자 승인이 필요합니다.
> - **hooks:** 새 hook 추가 시 사용자 확인을 거칩니다.
> - **Gist 선택:** 동일 파일명의 Gist가 여러 개이면 자동 선택 없이 사용자가 직접 고릅니다.
> - **Gist 공개 범위:** 기본 secret으로 생성되지만, 기존에 `--public`으로 만든 Gist가 있다면 secret Gist로 재생성하세요. secret Gist도 URL을 아는 사람은 접근할 수 있으므로 URL 공유에 주의하세요.

**mccm.json 관리 범위:**

| 항목 | mccm.json 키 | settings.json 매핑 |
|------|------------|-------------------|
| 마켓플레이스 | `marketplaces` | `extraKnownMarketplaces` |
| 플러그인 | `plugins` | `enabledPlugins` |
| CLI 도구 | `clis` | — (check/install 명령으로 관리) |
| MCP 서버 | `mcpServers` | `mcpServers` |
| hooks | `hooks` | `hooks` |
| 설정 | `settings` | 최상위 키 (language, env 등) |

### dev — 개발 스킬팩

| 스킬 | 설명 |
|------|------|
| [commit](plugins/dev/skills/commit/) | Git 커밋 스킬 — 보안 검토, 브랜치 생성, 스테이징, 커밋 메시지 작성 |
| [pr](plugins/dev/skills/pr/) | PR 생성 스킬 — push, 제목/본문 생성, assignee, label 자동 설정, Actions 체크 추적 |
| [cleanup](plugins/dev/skills/cleanup/) | 리모트 동기화 스킬 — 기본 브랜치 이동, pull, prune, 로컬 브랜치 정리 |
| [report](plugins/dev/skills/report/) | 변경사항·PR 보고서 스킬 — 커밋/PR/브랜치 diff를 개발자 리뷰어용 HTML Artifact로. 변경 전후 대비 블록다이어그램·시퀀스 플로우를 인라인 SVG로 그리고 저장소 고유 용어 풀이와 리뷰 포인트를 붙인다 |
| [brief](plugins/dev/skills/brief/) | 비개발자용 브리핑 스킬 — 코드·PR부터 개념·기술 선택·일정까지 무엇이든 기획·PM·영업·경영진이 이해할 HTML Artifact로. 설명의 대부분을 인라인 SVG 그림이 지고 글은 그림이 못 하는 것만 남긴다. 은유는 독자의 업무(결재·재고·검사 라인 등)에서 가져오고, 「그래서 무엇을 하면 되는가」로 닫는다 |
| [meta-prompting](plugins/dev/skills/meta-prompting/) | goal 프롬프트 다듬기 — 대화형 인터뷰로 정보를 좁히고 `dev:explorer`로 코드 앵커를 찾아 4천 자 이내 명령형 프롬프트를 완성, 코드블록 출력 + 파일 저장 |

**서브에이전트 로스터 (모델 티어링)** — 워크플로·병렬 작업에서 `agentType`으로 라우팅하는 17종 전담 에이전트. 판단 난이도별 3티어(T0 haiku / T1 sonnet / T2 opus)와 위임 권한·부작용 축·강등 규칙은 [`model-routing.md`](plugins/dev/model-routing.md)에 정의되며, SessionStart 훅으로 메인 세션에 주입된다. 문서 최상단의 「위임 권한」 절은 위임을 억제하는 하네스 기본 지시와 충돌할 때 **이 정책이 우선**임을 규정한다 — 하네스는 위임 억제를 기본값으로 붙이지만, 사용자 통제 계층의 정책이 이를 덮는다.

| 티어 | 에이전트 | 역할 |
|------|---------|------|
| T0 `haiku` | explorer | 파일·심볼 위치 탐색 (읽기 전용) |
| T0 `haiku` | log-sifter | 큰 로그에서 에러·경고만 추출 |
| T0 `haiku` | build-runner | 빌드·테스트 실행 후 성패+에러 요약. 되돌릴 수 없는 명령(push·배포·하드웨어 송신)은 실행하지 않고 거부 반환 |
| T1 `sonnet` | researcher | 코드 동작 조사·호출 경로 추적·공식 문서 조회 |
| T1 `sonnet` | executor | 명세가 분명한 코드 수정 |
| T1 `sonnet` | test-writer | 테스트·재현 하네스 작성 |
| T1 `sonnet` | writer | 한국어 문서·주석·커밋/PR 본문 |
| T1 `sonnet` | code-simplifier | 기능 불변 단순화 (세션 diff 한정) |
| T1 `sonnet` | scientist | 데이터 통계 분석 (CAN 캡처·측정 로그) |
| T1 `sonnet` | designer | UI 구현 (프런트엔드 있는 저장소 한정) |
| T2 `opus` | architect | 설계·트레이드오프·구현 계획 (코드 안 씀) |
| T2 `opus` | code-reviewer | 코드 리뷰 (작성자와 다른 패스) |
| T2 `opus` | security-reviewer | 보안 결함 판정 (악용성×피해범위, 읽기 전용) |
| T2 `opus` | verifier | 적대적 검증 (반증 시도) |
| T2 `opus` | synthesizer | 다중 결과 합성·최종 판정 |
| T2 `opus` | debugger | 증상→원인 동적 진단 (유일한 T2 쓰기 권한) |
| T2 `opus` | advisor | 접근법 검토·막힌 지점 진단·완료 직전 점검 (메인만 호출) |

### worklog — 일일/주간 워크로그

`today`는 Claude Code가 세션마다 남기는 트랜스크립트(`~/.claude/projects/<cwd-slug>/<session-id>.jsonl`)를 직접 파싱해 하루치 작업을 정리한다. 별도 hook 설치가 필요 없어 새 머신에서도 셋업 0으로 동작한다. 데이터 수집은 `prep.sh` 한 번 호출로 활동·커밋·Jira 후보·당일 워크로그를 **동시 수집**해 압축 리포트로 내며(트랜스크립트 스캔과 Jira 조회를 병렬 실행, 시각변환·경로 basename·프로젝트 해결을 스크립트가 처리해 빠르고 토큰을 아낀다), 하루를 30분 슬롯 타임라인으로 시각화한다. 선택적으로 `jira` CLI로 워크로그 입력 후보를 추정·dry-run 미리보기·실제 입력까지 반자동화한다(30분 반올림, 같은 날 기존 워크로그·점심시간 회피, 멀티라인 코멘트). 주간보고가 필요하면 `week`가 이번 주(또는 지난주) 내 Jira 워크로그를 집계해 문서 도구 등에 붙여넣을 주간보고 텍스트를 만든다(읽기 전용).

| 스킬 | 설명 |
|------|------|
| [today](plugins/worklog/skills/today/) | 오늘(또는 지정일) 트랜스크립트 → `prep.sh` 동시 수집(활동·커밋·Jira 후보·당일 워크로그) → 시간대·프로젝트·커밋·prompt 주제 요약 + 30분 슬롯 타임라인 + Jira 워크로그 dry-run/apply(멀티라인 코멘트) |
| [week](plugins/worklog/skills/week/) | 이번 주(또는 지난주/지정 범위) 내 Jira 워크로그 집계 → 이슈별/일자별 시간 + 코멘트 기반 작업 서술을 문서 도구용 주간보고 마크다운으로 출력 (읽기 전용) |

**사전 요구사항:** `today` 요약은 `jq`만 있으면 동작(트랜스크립트 직접 파싱). Jira 워크로그 입력(`today`)·주간 집계(`week`)는 [`jira` CLI](https://github.com/ankitpokhrel/jira-cli)(`jira init` + `JIRA_API_TOKEN` env) + `curl`·`base64`·`jq` 필요.

**개인화(선택):** 표시 이름·보고서 문체·이슈키 예시·주간보고 템플릿 등을 자신에게 맞추려면 `plugins/worklog/worklog.example.json`을 `~/.config/mccm/worklog.json`으로 복사해 값을 채운다. 설정이 없어도 `today`·`week`는 SKILL.md 기본 규칙 그대로 동작한다 — 개인화는 선택이지 필수가 아니다. 자세한 위치·검증 방법은 아래 「워크로그 개인화」 절 참고.

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

## 워크로그 개인화

`worklog` 플러그인(`today`·`week`)은 표시 이름·보고서 문체·이슈키 예시·주간보고 템플릿 같은 개인·사내 고유값을 **저장소 밖** `~/.config/mccm/worklog.json`에서 읽는다. 이 저장소는 public이므로 저장소 안에는 중립 값의 `plugins/worklog/worklog.example.json`만 커밋되어 있다.

**설정 파일 탐색 순서** (`_profile.sh`가 첫 번째로 존재하는 경로 1개만 사용, 병합하지 않음):

1. `MCCM_WORKLOG_CONFIG` 환경변수가 가리키는 경로
2. `$XDG_CONFIG_HOME/mccm/worklog.json`
3. `$HOME/.config/mccm/worklog.json`
4. `%USERPROFILE%\.config\mccm\worklog.json` / `%APPDATA%\mccm\worklog.json` (Git Bash의 `HOME`이 Windows 사용자 폴더와 갈릴 때 대비)

**적용 방법:**

```bash
cp plugins/worklog/worklog.example.json ~/.config/mccm/worklog.json
# 이후 identity·examples·report 값을 자신에게 맞게 편집
```

**설정이 없어도 정상 동작한다.** `_profile.sh`가 존재하지 않는 설정을 rc0으로 처리하고, `today`·`week`는 각 SKILL.md의 기본 규칙으로 그대로 동작한다 — 개인화는 기능이 아니라 표현·문체에만 영향을 준다.

**검사:**

```bash
bash plugins/worklog/skills/today/_profile.sh --check
```
설정 없음(INFO), 스키마 위반(WARN), 파일 손상(FAIL) 상태를 알려준다. 겸해서 `today`·`week`의 `_profile.sh` 두 사본이 어긋났는지 `cmp`로 검사한다 — 이 파일은 프롬프트 주입 필터라 한쪽만 고치면 나머지 스킬이 조용히 취약해진다. 어긋나면 rc2로 실패하며, 어느 쪽 경로로 실행해도 발화한다.

> **⚠️ 비밀을 넣지 말 것:**
> - Jira API 토큰은 `worklog.json`이 아니라 `JIRA_API_TOKEN` 환경변수가 담당한다.
> - Jira 서버 주소·로그인 이메일은 `worklog.json`이 아니라 `~/.config/.jira/.config.yml`이 담당한다.
> - 여러 PC 동기화가 필요하면 `sync: true`로 두고 `/upload`가 env gist의 형제 파일 `worklog.json`으로 함께 올리게 할 수 있다. 다만 gist의 "secret"은 비공개가 아니라 **URL을 아는 누구나 접근 가능**하다는 뜻이므로 URL 공유에 주의한다.
>
> **금칙어:** 향후 `worklog.json`의 스칼라 값을 `settings.json`의 `env`로 빼서 관리할 경우, 변수명에 `TOKEN`·`KEY`·`SECRET`·`AUTH`·`PASS`·`PWD`·`CREDENTIAL`·`HEADER`·`DSN`이 들어가면 `/upload`가 gist에서 **조용히 지운다**(`plugins/env/skills/upload/SKILL.md`의 민감정보 필터).

## 플러그인 구조

```
mccm/
├── .claude-plugin/
│   └── marketplace.json
└── plugins/
    ├── env/
    │   ├── .claude-plugin/
    │   │   └── plugin.json
    │   └── skills/              ← mccm.json은 gist로 관리
    │       ├── download/
    │       │   └── SKILL.md
    │       └── upload/
    │           └── SKILL.md
    ├── dev/
    │   ├── .claude-plugin/
    │   │   └── plugin.json
    │   ├── model-routing.md         ← 티어 정책 (SessionStart 훅으로 주입)
    │   ├── agents/                  ← 서브에이전트 17종 (*.md)
    │   └── skills/
    │       ├── commit/
    │       │   └── SKILL.md
    │       ├── pr/
    │       │   └── SKILL.md
    │       ├── cleanup/
    │       │   └── SKILL.md
    │       ├── report/
    │       │   ├── SKILL.md
    │       │   └── references/
    │       │       └── diagram-recipes.md      ← SVG 좌표 레시피 (개발자용)
    │       ├── brief/
    │       │   ├── SKILL.md
    │       │   └── references/
    │       │       └── visual-vocabulary.md    ← 비개발자용 그림 어휘·은유·레시피
    │       └── meta-prompting/
    │           └── SKILL.md
    └── worklog/
        ├── .claude-plugin/
        │   └── plugin.json
        ├── worklog.example.json     ← 개인화 프로필 예시(중립값, 실값은 ~/.config/mccm/worklog.json)
        └── skills/
            ├── today/
            │   ├── SKILL.md
            │   ├── _tz.sh
            │   ├── _jira.sh
            │   ├── _profile.sh      ← 개인화 프로필 로더(+ --check 진단 CLI)
            │   ├── collect.sh
            │   ├── prep.sh
            │   ├── timeline.sh
            │   └── jira_worklog.sh
            └── week/
                ├── SKILL.md
                ├── _tz.sh
                ├── _profile.sh      ← today/_profile.sh 의 바이트 사본
                └── jira_week.sh
```

## 새 스킬 추가 방법

1. `plugins/{플러그인}/skills/{skill-name}/SKILL.md` 작성
2. PR 생성 → 리뷰 → 머지
3. 사용자는 세션 시작 시 자동 업데이트 (또는 `claude plugin marketplace update mccm`)
