---
name: deck
description: litbig-deck(리트빅 표준 덱)을 사내 취향으로 덧씌운 래퍼. 표지·엔드는 곤색(네이비) 고정, PDF 전에 HTML 아티팩트로 먼저 보여 주고 승인받은 뒤 PDF 를 뽑는다. 글보다 도식(아키텍처 다이어그램·시스템 플로우·시퀀스·상태도 — 인라인 SVG) 위주로 그리고 아이콘 카드는 비교·지표에만 절제해 쓰며, 모든 콘텐츠 장의 제목은 큰 제목=짧은 라벨(`한글 · English`)·작은 제목=메시지 문장으로 원본과 뒤바꾸고, 카드는 둥근 모서리 + 그림자 스타일로 그린다. "리트빅 덱 만들어줘", "리트빅 PPT 만들어줘", "litbig deck", "회사 양식 PDF 로 팀 공유 자료", "/deck" 등 litbig-deck 이 받을 요청은 이 스킬이 먼저 받는다 — 원본을 그대로 쓰라고 명시한 경우만 litbig-deck 을 직접 쓴다. 사용자가 PPTX 를 명시하면 그때만 원본의 네이티브 PPTX 경로를 함께 탄다.
allowed-tools: Read, Glob, Grep, Skill, Bash(mkdir -p *), Bash(ls -d *), Write(~/Downloads/decks/**), Edit(~/Downloads/decks/**), mcp__claude-artifacts__guide, mcp__claude-artifacts__publish_files, mcp__claude-artifacts__get_artifact
---

# dev:deck — litbig-deck 사내 래퍼

이 스킬은 **덱 생성기를 새로 만들지 않는다.** 구도·브랜드·내보내기는 원본 `litbig-deck` 이 갖고 있고, 이 스킬은 그 위에 사내에서 확정한 6가지 규칙을 덧씌운다. 규칙의 근거는 사용자가 이 규칙으로 확정한 팀 공유용 14장 덱이고, 그 수치를 `assets/house.css` 에 옮겨 두었다.

## 이 스킬이 부를 수 있는 것

`allowed-tools` 는 확인 없이 도는 범위를 작업 폴더 생성·쓰기·게시로만 묶어 둔다. 파이썬 실행(`setup_env.py`·`build_pdf.py`·검증 렌더)과 `cp` 는 **일부러 빼 두었다** — 코드를 실행하는 단계는 매번 확인 창을 거치고, `cp` 는 접두사 규칙으로 대상 경로를 묶을 수 없어 허용하면 작업 폴더에 쓴 파일을 설정·훅 위치로 확인 없이 옮길 수 있다. 그 밖의 범위는 아래와 같다.

- **Skill** — `litbig-deck:litbig-deck`(필수), 숫자를 차트로 그릴 때 `dataviz`. 커밋·PR·환경 동기화 스킬은 부르지 않는다.
- **Write/Edit** — 작업 폴더 `~/Downloads/decks/<deck-name>/` 안의 파일만. 저장소·`.claude/`·설정 파일은 쓰지 않는다.
- **Bash** — 폴더 생성(`mkdir -p`, 확인 없이), 에셋 복사와 최종 PDF 복사(`cp`, 확인 창 경유), 원본이 문서화한 `setup_env.py`(전용 venv `~/.cache/litbig-deck-venv` 에 playwright·python-pptx 를 pip 설치 — 원본 0단계 그대로이며 이 스킬이 새로 더한 네트워크 동작이 아니다)와 `build_pdf.py` 실행, 검증용 PDF→PNG 렌더. `git`·원격 명령은 없다.
- **claude-artifacts** — 이 덱의 미리보기 게시·재게시만. 공유 범위 변경·삭제는 하지 않는다(서버도 못 한다).

`<deck-name>` 은 사용자가 준 것이든 **모델이 PR 제목·문서 제목에서 지은 것이든** `^[0-9A-Za-z가-힣][0-9A-Za-z가-힣._-]{0,79}$` 에 맞고 `..` 를 포함하지 않아야 한다. 안 맞으면 사용자에게 고친 이름을 제안한다 — 셸 명령에 들어가는 유일한 사용자 입력이다. 경로에 쓸 때는 항상 큰따옴표로 감싼다.

## 0. 원본 로드

1. `Skill(litbig-deck:litbig-deck)` 로 원본 지침을 로드한다. 없으면 **멈추고** "claude-skill 마켓플레이스의 litbig-deck 플러그인이 필요하다"고 알린다 — 원본 없이 흉내 내지 않는다.
2. `BASE` = 1에서 로드한 원본 스킬의 **"Base directory for this skill"** 경로. 읽은 지침과 실행할 스크립트가 반드시 같은 플러그인에서 나오게 하려는 것이다. 그 경로가 안 보일 때만 마켓플레이스를 `claude-skill` 로 고정해 버전 칸만 정렬한다:
   ```bash
   ls -d ~/.claude/plugins/cache/claude-skill/litbig-deck/*/skills/litbig-deck | sort -V | tail -1
   ```
   `cache/*/litbig-deck` 처럼 마켓플레이스를 와일드카드로 두지 마라 — 전체 경로 정렬이라 이름이 뒤인 다른 마켓플레이스의 같은 이름 플러그인(포크·남은 캐시)이 뽑혀 그 코드가 실행된다.
   `HOUSE` = 이 SKILL.md 가 있는 디렉터리(`assets/house.css`·`assets/house.js`·`references/components.md`).
3. `$BASE/references/layouts.md` 와 이 스킬의 `references/components.md` 를 읽는다.

**원본 계약(크기·네이비 잉크·오렌지 절제·Pretendard·로고는 표지만·EOD 회사정보·카피라이트·페이지 번호)은 전부 유효하다.** 아래 표만 원본을 덮는다.

## 덮어쓰는 규칙

| # | 원본 litbig-deck | 이 스킬 | 이유 |
|---|---|---|---|
| 1 | 표지 흰색/곤색을 **매번 묻는다**(계약 5) | **곤색 고정, 묻지 않는다.** `<html data-cover="navy">` 를 deck.html 에 정적으로 박고 `--cover navy` 로 렌더. EOD 도 곤색. 사용자가 흰색을 **명시**할 때만 흰색 | 팀 공유 덱은 늘 곤색으로 냈다 |
| 2 | 바로 PDF·PPTX 렌더 | **HTML 아티팩트로 먼저 게시 → 피드백 반영 → 승인 후 PDF** | PDF 는 고치기 비싸다. 내용·구도는 링크로 먼저 합의한다 |
| 3 | 문장형 본문·행 목록 위주 컴포넌트 | **도식 위주.** 장마다 그림 하나가 주인공이고, 그 그림은 기본이 **도식**(아키텍처 다이어그램·시스템 플로우·시퀀스·플로우차트·상태도 — 인라인 SVG)이다. 아이콘 카드는 비교·지표·요약에만 쓰는 보조 부품이고 콘텐츠 장의 1/4 이하·연속 두 장 금지. 글은 eyebrow 문장 하나 + 노드·카드마다 짧은 이름 | 팀원은 읽지 않고 본다. 아이콘 카드만 나열하면 무엇이 무엇과 어떻게 이어지는지가 안 보인다 |
| 4 | eyebrow = 짧은 라벨(17px, 대문자·자간), h2 = 문장(80px) | **뒤바꾼다.** eyebrow = 메시지 문장(22px 오렌지, 자간·대문자 없음, 한 줄), h2 = 짧은 라벨 `한글 · English`(56px 네이비, 영문만 `.en` 오렌지) | 큰 글씨는 위치 표지, 작은 글씨는 요지 |
| 5 | 1px 테두리·상단 보더 카드, 각진 하이라이트 박스 | **그림자 카드.** 테두리 없음·반경 24px·네이비 틴트 그림자, 80px 네이비 아이콘 타일, 결론 카드 하나만 `.on`(오렌지 2px 윤곽 + 오렌지 타일) | 참고 PDF 의 확정 스타일 |
| 6 | PDF + 네이티브 PPTX 기본 | **PDF 만.** PPTX 는 사용자가 명시하면 원본 3-b 경로로 추가 | 네이티브 PPTX 는 그림자를 지우는 규칙이라(원본 `pptx_lib`) 카드 스타일이 평평해지고 작업량이 두 배다 |
| 7 | 현재 디렉터리 `output/<deck-name>/` | **`~/Downloads/decks/<deck-name>/`**, 최종 PDF 는 `~/Downloads/<deck-name>.pdf` | 작업 중인 저장소를 더럽히지 않는다 |

구체 수치·마크업은 `assets/house.css` 와 `references/components.md` 가 정본이다. 여기 형용사와 어긋나면 그 두 파일을 따른다.

## 1. 스토리보드

쓰기 전에 장마다 한 줄씩 정한다: **이 장이 설명하는 것 / eyebrow 문장 / h2 라벨 / 그림 종류**. 그림 종류는 `components.md` 3절 표가 정한다 — 구성·연결은 아키텍처 다이어그램, 처리 순서는 시스템 플로우, 주체 간 주고받기는 시퀀스, 분기·상태는 플로우차트·상태도, 전후 차이는 전/후 대비. 한 장에 그림 둘을 욱여넣지 말고 장을 나눈다.

스토리보드를 확정하기 전에 세어 본다:

- 콘텐츠 장의 **절반 이상이 도식**인가. 덱이 시스템·구조·절차를 다루는데 도식이 그보다 적으면 카드로 때운 장이 있다는 뜻이다.
- **아이콘 카드가 주인공인 장**(카드 흐름·카드 그리드)은 콘텐츠 장의 1/4 이하이고 연속 두 장이 없는가.
- 카드를 고른 장마다 표의 "그림" 칸 옆에 **왜 도식이 아닌지 한 줄**을 적는다("순서·연결 없는 4개 지표 비교" 처럼). 사유를 못 쓰면 도식으로 바꾼다 — 항목 사이에 화살표를 그을 수 있으면 도식이다.

- 덱 이름(`<deck-name>`)은 `<제품>-<주제>-<용도>-<YYYY-MM-DD>` 꼴(예: `<제품>-<주제>-팀공유-2026-10-28`).
- 표지 오른쪽 `cover-visual` 에 덱 전체를 3~4단계 흐름으로 요약한다.
- 스토리보드는 채팅에 표로 보여 주되 확인을 기다리지 않는다 — 검토 지점은 아티팩트다.

## 2. 작업 폴더

명령마다 따로, 경로는 변수 대신 **실제 경로를 풀어 쓴다**(대입이 앞에 붙으면 `Bash(mkdir -p *)` 규칙에 안 걸린다). `W` 는 `~/Downloads/decks/<deck-name>` 을 가리키는 표기일 뿐이다.

```bash
mkdir -p "$HOME/Downloads/decks/<deck-name>"
cp "<BASE>"/assets/{build_pdf.py,colors_and_type.css,logo-litbig-vertical.png,logo-litbig-white.png} "<W>"/
cp "<BASE>/assets/template-deck.html" "<W>/deck.html"
cp "<HOUSE>"/assets/{house.css,house.js} "<W>"/
```

폴더가 이미 있으면 덮기 전에 사용자에게 알린다(이전 덱의 수정본일 수 있다).

## 3. deck.html 작성

- `<html lang="ko" data-cover="navy">` 로 바꾼다(규칙 1).
- upstream `<style>…</style>` 은 **건드리지 않고**, 그 **바로 뒤**에 넣는다:
  ```html
  <link rel="stylesheet" href="house.css">
  <script src="house.js" defer></script>
  ```
  `<style>` 앞에 두면 upstream `.eyebrow` 가 이겨서 제목 교체가 안 먹는다.
- `<body>` 의 예시 슬라이드는 지우고 표지(`s-cover`)·콘텐츠(`section.slide.hs`)·EOD(`s-eod`, upstream 마크업 그대로)로 채운다. 콘텐츠 장은 `components.md` 1절 골격을 쓴다 — upstream 의 `.s4`·`.s-eff` 등 예시 클래스를 콘텐츠 장에 붙이면 80px h2 가 되살아난다.
- `.pageno` 분모를 실제 총 장수로 맞춘다.
- 오렌지 면적은 `.tile.on`·`.chip.on`·결론 카드 윤곽·`.badge`·도식의 `.n.on`/`.e.on`(장당 하나씩)까지. 카드 배경을 오렌지로 칠하지 않는다.
- 도식은 `components.md` 4절 공통 규칙(좌표계·치수·마커 id·검산)을 읽고 5~8절 골격에서 시작한다. 그린 뒤 좌표를 **산술로 검산**한다 — SVG 는 viewBox 밖으로 나간 요소를 경고 없이 잘라 버린다.

## 4. 아티팩트 게시 (PDF 전에)

1. 세션 첫 게시면 `mcp__claude-artifacts__guide(topic="pages")` 를 먼저 읽는다.
2. **게시 전 점검.** 사용자가 기밀·사내 한정이라고 했거나, 캡처·본문에 토큰·내부 호스트/URL·고객 식별정보가 보이면 게시하지 않는다 — `deck.html` 경로만 알리고 게시 여부를 묻는다. 아티팩트는 비공개로 시작하지만 조직 밖 호스팅으로 올라가는 것이다.
3. `publish_files` 로 올린다 — `deck.html` 을 `index.html` 로, 나머지는 같은 이름으로:
   `index.html`·`colors_and_type.css`·`house.css`·`house.js`·로고 2종·캡처 PNG 전부. `title` 은 덱 제목, `icon` 은 `slides`. 아티팩트 타입(slide deck)은 쓰지 않는다 — 산출물은 이 HTML 을 렌더한 PDF 다.
4. 링크를 주며 "PDF 전 미리보기"임을 한 줄로 밝힌다. 알릴 것:
   - 미리보기 글꼴은 Pretendard 가 PC 에 설치돼 있지 않으면 Noto Sans KR 로 보인다(아티팩트가 Pretendard CDN 을 막는다). **PDF 가 픽셀 기준**이다.
   - 슬라이드는 창 너비에 맞춰 축소돼 보인다(`house.js`).

## 5. 피드백 루프

수정 요청을 deck.html 에 반영하고, 마지막 게시 결과의 `slug`·`version` 으로 재게시한다(`publish_files` + `slug`·`base_version`, 바뀐 파일만). 충돌로 거절되면 `get_artifact` 로 현재 버전을 다시 읽고 로컬 deck.html 기준으로 재게시한다.

사용자가 승인("좋아", "PDF 뽑아", "이대로")하기 전에는 PDF 를 만들지 않는다.

## 6. PDF 렌더

```bash
python "<BASE>/assets/setup_env.py"          # 마지막 줄 READY: <venv python> 을 <V> 로
"<V>" "<W>/build_pdf.py" --cover navy --name "<deck-name>"
cp "<W>/<deck-name>-navy.pdf" "$HOME/Downloads/<deck-name>.pdf"
```

`build_pdf.py` 는 navy 일 때 `-navy` 접미사를 붙인다. 사용자에게 주는 최종본은 접미사 없는 `~/Downloads/<deck-name>.pdf` 다(규칙 7). 흰색 표지를 명시받았으면 `--cover white` 로 돌리고 접미사 없는 파일을 그대로 복사한다.

## 7. 검증 (건너뛰지 마라)

PDF 를 PNG 로 떠서(PyMuPDF `fitz` 가 있으면 그것, 없으면 `pdftoppm`) 표지·EOD·도식 장 전부·카드가 많은 장을 **눈으로** 본다. 원본 5단계 점검에 더해:

- [ ] 표지·EOD 곤색, 표지에 흰색 CI, 오른쪽 흐름 그림이 lede 와 겹치지 않음
- [ ] 모든 콘텐츠 장: 위에 작은 오렌지 문장(한 줄) → 아래 큰 네이비 라벨, 영문만 오렌지
- [ ] 카드에 그림자가 찍혔고(인쇄 배경 포함) 테두리 선이 이중으로 보이지 않음
- [ ] 결론 카드 `.on` 은 장당 최대 하나, 오렌지 면적 과다 없음
- [ ] 카드 본문 2줄 초과·텍스트 넘침·연결선 어긋남 없음
- [ ] 도식 장: 화살촉이 노드를 파고들지 않고, 라벨이 선·노드에 겹치지 않고, 잘린 노드·글자가 없음
- [ ] 콘텐츠 장 절반 이상이 도식, 아이콘 카드 장은 1/4 이하·연속 두 장 없음
- [ ] `.pageno` 분모 = 총 장수

문제가 있으면 deck.html 을 고쳐 **아티팩트를 재게시하고** PDF 를 다시 뽑는다 — 아티팩트와 PDF 가 같은 원본을 가리키게 유지한다.

## 8. PPTX (요청 시에만)

사용자가 PPTX 를 명시하면 원본 3-b(`deck_native.py`)·4단계(`build_pptx.py --cover navy`)를 따른다. 넘기기 전에 **"네이티브 PPTX 는 그림자·둥근 아이콘 타일이 평평한 도형으로 바뀐다"**고 알린다. 그림자까지 그대로 필요하면 `--mode image`(편집 불가) 밖에 없다는 점도 함께 말하고 고르게 한다.

## 흔한 실수

- **house.css 를 `<style>` 앞에 link** → eyebrow 가 17px 대문자 라벨로 돌아간다.
- **콘텐츠 장에 upstream 예시 클래스(`.s4` 등)** → h2 가 80px 문장형으로 커진다. `.hs` + `.hd` 만 쓴다.
- **eyebrow 문장이 두 줄** → 문장을 줄인다. 큰 라벨 위에 두 줄 오렌지 글씨는 시선을 뺏는다.
- **라벨 전체를 오렌지** → 영문 꼬리만 `.en`. 한글 부분은 네이비.
- **`.card` 에 border 추가** → 그림자와 겹쳐 선이 이중으로 보인다. 강조는 `.on` 하나로.
- **아이콘 카드 도배** → 장마다 "아이콘 타일 + 제목 + 두 줄" 카드를 3~5개씩 늘어놓으면 덱 전체가 같은 모양이 되고, 무엇이 무엇과 어떻게 이어지는지는 하나도 안 보인다. 구조·흐름·상호작용은 도식으로 그린다(`components.md` 3절 표).
- **구조를 카드 나열로** → "구성 요소 4개" 를 카드 4장으로 늘어놓으면 연결이 사라진다. 연결이 논지면 아키텍처 다이어그램이다.
- **HTML 카드 위에 SVG 선을 덮는 구조도** → 좌표계가 둘이라 창 크기·글꼴에 따라 선이 어긋난다. 노드·선을 SVG 한 장에 그린다.
- **도식 노드에 아이콘** → 도식이 다시 아이콘 카드 벽이 된다. 노드는 이름만.
- **마커 id 재사용** → 여러 장이 `id="ah"` 를 공유하면 앞 장의 마커가 잡힌다. 장 번호를 붙인다(`ah3`).
- **원격 이미지·아이콘 CDN** → 아티팩트에서 안 뜬다. 캡처는 own file, 아이콘은 인라인 SVG(`components.md` 10절).
- **절대 배치를 `top:50%` + `translateY(-50%)` 로 가운데 정렬** → 화면·아티팩트에선 멀쩡한데 PDF 에서만 아래쪽이 다음 페이지 조각으로 밀린다(인쇄 분할이 변환 전 박스로 계산된다). `top:0; bottom:0` + flex 가운데 정렬로 쓴다. 미리보기로는 안 잡히니 PDF PNG 로 확인한다.
- **house.js 의 `file:` 가드 제거** → 렌더 스크립트 캡처가 축소된다.
- **승인 전에 PDF** → 규칙 2 위반. 아티팩트 링크가 먼저다.
