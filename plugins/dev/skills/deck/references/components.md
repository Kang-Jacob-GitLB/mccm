# house 컴포넌트 카탈로그

`assets/house.css` 가 정의하는 마크업. upstream `references/layouts.md` 의 컴포넌트(정의 2단·하이라이트+행·프로세스 레일 등)도 그대로 쓸 수 있지만, 그 컴포넌트의 `h2`(80px 문장형)와 테두리 카드는 이 스킬의 계약과 어긋난다 — 가져다 쓸 때는 제목을 아래 `.hd` 블록으로, 카드를 `.card` 로 바꿔 끼운다.

모든 콘텐츠 장은 `section.slide.hs` + `.hd` 제목 + `.body` 그림 영역이다. **장의 주인공은 도식(4~8절)이다.** 아이콘 카드(9절)는 비교·지표·요약에만 쓰는 보조 부품이다 — 구조·흐름·상호작용을 카드 나열로 설명하지 않는다.

## 1. 콘텐츠 장 골격 (제목 교체)

```html
<section class="slide hs" data-label="한눈에">
  <div class="stage-pad">
    <div class="hd">
      <span class="eyebrow">도구가 찾고, AI가 제안하고, 사람이 결정합니다</span>   <!-- 작은 제목 = 메시지 문장 -->
      <h2>한눈에 · <span class="en">Overview</span></h2>                          <!-- 큰 제목 = 짧은 라벨 -->
    </div>
    <div class="body">
      <!-- 그림 하나: 도식(svg.dg) / 실제 화면 / 보조 카드 -->
    </div>
  </div>
  <div class="footer-rule"></div>
  <div class="copyright">Copyright@LITBIG Inc. All rights reserved.</div>
  <div class="pageno">02 / 14</div>
</section>
```

- 라벨은 `한글 · English` 형태, 영문(또는 숫자 포함 꼬리 `4 Jobs`)만 `.en` 으로 오렌지. 영문 꼬리가 없으면(`Human in the loop` 처럼 영문뿐이면) 전체를 `.en` 으로 감싼다.
- eyebrow 는 **한 줄**. 넘치면 문장을 줄인다 — 줄바꿈하지 않는다.

## 2. 표지 (네이비 고정 + 오른쪽 흐름 그림)

```html
<!doctype html><html lang="ko" data-cover="navy">   <!-- 미리보기도 곤색으로 보이게 정적으로 박는다 -->
...
<section class="slide s-cover" data-label="Title">
  <div class="stage-pad">
    <img class="logo ci-color" src="logo-litbig-vertical.png" alt="LITBIG"/>
    <img class="logo ci-white" src="logo-litbig-white.png" alt="LITBIG"/>
    <div class="mid">
      <span class="eyebrow">PR 하나로 검사부터 머지까지</span>
      <h1>CI/CD<br/><em class="accent-orange">Quality Gate</em></h1>
      <div class="lede">빌드서버가 <b>검사</b>하고, Claude가 <b>수정을 제안</b>하고,<br/>사람이 <b>승인</b>해 머지합니다.</div>
    </div>
    <div><div class="hair"></div><div class="meta"><div>PRODUCT · TOPIC</div><div>팀 공유 · 2026.10</div></div></div>
  </div>
  <div class="cover-visual">
    <div class="cv-node"><div class="tile sm"><svg viewBox="0 0 24 24">…</svg></div><div><b>PR</b><small>개발자가 올린다</small></div></div>
    <div class="cv-node"><div class="tile sm">…</div><div><b>품질 게이트</b><small>사내 서버 · 자동</small></div></div>
    <div class="cv-node on"><div class="tile sm">…</div><div><b>승인 · 머지</b><small>사람이 결정</small></div></div>
  </div>
  <div class="copyright">Copyright@LITBIG Inc. All rights reserved.</div>
</section>
```

`cover-visual` 노드는 3~4개. 덱 전체를 한 줄로 요약하는 흐름이다. `.on` 은 마지막(결론) 노드 하나만.

## 3. 그림 고르기 — 내용이 그림을 정한다

장마다 "이 장이 설명하는 것"을 먼저 정하고 아래 표에서 그림을 고른다. **왼쪽 다섯 줄에 해당하는 장에 카드를 고르지 않는다.**

| 이 장이 설명하는 것 | 그림 | 절 |
|---|---|---|
| 무엇으로 이루어졌고 어떻게 연결되나 (구성·계층·경계) | 아키텍처 다이어그램 | 5 |
| 무엇이 어떤 순서로 어디를 거쳐 가나 (처리 흐름·파이프라인) | 시스템 플로우 | 6 |
| 누가 누구에게 무엇을 주고받나 (주체 간 상호작용·타이밍) | 시퀀스 다이어그램 | 7 |
| 조건에 따라 어디로 갈리나 / 상태가 어떻게 바뀌나 | 플로우차트 · 상태도 | 8 |
| 전과 후가 무엇이 다른가 | 전/후 대비(같은 도식 두 벌) | 8 |
| 숫자 추이·비교 | 차트(`dataviz` 스킬) | — |
| 실제로 어떻게 보이나 | 실제 화면 캡처 | 9 |
| 병렬 항목의 비교·지표·요약 (순서·연결이 없는 것) | 카드 그리드 · 숫자 타일 | 9 |

판단이 애매하면 "항목 사이에 화살표를 그을 수 있나"를 묻는다. 그을 수 있으면 도식이고, 못 그으면 그때 카드다.

## 4. 도식 공통 — 좌표계·치수·검산

도식은 **인라인 SVG 한 장**이다. HTML 카드를 깔고 위에 연결선 SVG 를 덮는 방식은 좌표계가 둘이라 선이 어긋나므로 쓰지 않는다. 색·굵기·그림자는 `house.css` 5절 클래스가 주고, 마크업에는 좌표와 글자만 적는다.

```html
<div class="body">
  <svg class="dg" viewBox="0 0 1700 720" role="img" aria-label="그림이 말하는 결론 한 문장">
    <defs>
      <!-- 마커 id 는 문서 전체에서 유일해야 한다 → 장 번호를 붙인다(ah3, ah3o …) -->
      <marker id="ah3"  viewBox="0 0 10 10" refX="9" refY="5" markerWidth="6" markerHeight="6" orient="auto-start-reverse"><path class="ah"    d="M0 0L10 5L0 10z"/></marker>
      <marker id="ah3o" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="6" markerHeight="6" orient="auto-start-reverse"><path class="ah on" d="M0 0L10 5L0 10z"/></marker>
      <marker id="ah3w" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="6" markerHeight="6" orient="auto-start-reverse"><path class="ah weak" d="M0 0L10 5L0 10z"/></marker>
    </defs>
    …
  </svg>
  <div class="dg-cap">결론 한 줄 — <b>강조할 말</b>만 굵게</div>   <!-- 선택. 쓰면 viewBox 높이를 640 으로 -->
</div>
```

| 요소 | 클래스 · 값 |
|---|---|
| 캔버스 | `viewBox="0 0 1700 720"`(캡션 있으면 `1700 640`). 콘텐츠 장 그림 영역이 1700×약 730 이다 |
| 노드 | `<rect class="n" rx="18">` 기본 `w=300 h=96`. 주인공 `.n.core`(네이비 채움, 글자 `.t-inv`), 결론·변경점 `.n.on`(장당 하나), 외부 시스템 `.n.ext`, 사라진 것 `.n.del` |
| 노드 글자 | 제목 26px(기본 `text`), 부제 `.t-sub` 19px. 한 줄이면 `y = 노드y + 57`, 두 줄이면 제목 `y+42`·부제 `y+72`. 모두 `text-anchor="middle"`, `x = 노드 중심` |
| 영역 | `<rect class="grp" rx="24">` 레이어·존·레인. 격리·샌드박스 `.grp.dash`, 이웃 구분 `.grp.alt`. 이름은 `.grp-t`(18px 대문자 자간) |
| 연결선 | `<path class="e" marker-end="url(#ah3)">`. 핵심 경로 `.e.on`(장당 하나, 오렌지 마커), 비동기·응답 `.e.async`, 보조 `.e.weak`. 꺾이면 `H`·`V` 직각 경로만 — 사선 금지 |
| 선 라벨 | `.t-lbl` 20px, 흰 halo 가 선을 끊어 준다. 핵심 경로 라벨은 `.t-lbl.on` |
| 순번 | `<circle class="no" r="20">` + `<text class="no-t">`(시스템 플로우). 결론 단계만 `.no.on` |

**치수 규칙** (`report` 스킬 `references/diagram-recipes.md` 의 좌표 문법을 1920 캔버스로 키운 것이다)

- 화살표는 노드 경계에서 **6px 떨어져** 시작하고 6px 앞에서 끝낸다. 딱 맞추면 화살촉이 박스를 파고든다.
- 라벨은 선과 같은 x(세로선) · 같은 y(가로선)에 두지 않는다 — 가로선이면 `y = 선y − 16`, 세로선이면 `x = 선x + 16`(`text-anchor="start"`).
- 한글 1자 ≈ font-size, 라틴 1자 ≈ font-size × 0.55. 노드 안 글자 폭이 `노드 폭 − 40` 을 넘으면 **글자를 줄인다**(노드를 키우지 말고). 26px 제목은 300 폭에 한글 9자까지.
- 노드는 장당 **12개 이하**, 연결선 **10개 이하**. 넘으면 장을 둘로 나누거나 한 단계 추상화한다.
- 글자는 18px 미만으로 내리지 않는다 — 1920 캔버스가 회의실 화면에서 절반으로 줄어든다.
- 그린 뒤 **산술로 검산한다**: 모든 x 가 0~1700, y 가 viewBox 높이 안인가 / 각 글자 폭이 노드 안인가 / 이웃 라벨 y 간격 ≥ font-size+4 인가. SVG 는 넘친 요소를 경고 없이 잘라 버린다.

## 5. 아키텍처 다이어그램 (레이어 + 컴포넌트 + 연결)

"무엇으로 이루어졌나"를 보인다. 가로 띠(레이어)를 위→아래로 쌓고, 왼쪽 240px 레일에 레이어 이름을 둔다. 노드는 3열 격자(`x = 360 / 820 / 1280`, 중심 `510 / 970 / 1430`)에 맞춘다 — 열을 맞춰야 세로선이 곧게 떨어진다.

```html
<svg class="dg" viewBox="0 0 1700 720" role="img" aria-label="API 서버가 주문 DB 와 새 이벤트 큐에 쓰고, 인증은 외부 IdP 로 위임한다">
  <defs>… ah3 · ah3o · ah3w (4절) …</defs>
  <!-- 레이어 띠: 높이 200, 간격 60 -->
  <rect class="grp"     x="0" y="0"   width="1700" height="200" rx="24"/>
  <rect class="grp alt" x="0" y="260" width="1700" height="200" rx="24"/>
  <rect class="grp"     x="0" y="520" width="1700" height="200" rx="24"/>
  <text class="grp-t" x="40" y="96">CLIENT</text>  <text class="t-sub" x="40" y="128">사용자 접점</text>
  <text class="grp-t" x="40" y="356">SERVICE</text> <text class="t-sub" x="40" y="388">사내 서버</text>
  <text class="grp-t" x="40" y="616">DATA</text>    <text class="t-sub" x="40" y="648">저장 · 전달</text>

  <!-- 노드: 레이어 y + 52 -->
  <rect class="n" x="360"  y="52" width="300" height="96" rx="18"/> <text x="510"  y="109" text-anchor="middle">웹 콘솔</text>
  <rect class="n" x="820"  y="52" width="300" height="96" rx="18"/> <text x="970"  y="109" text-anchor="middle">모바일 앱</text>
  <rect class="n ext" x="1280" y="52" width="300" height="96" rx="18"/> <text x="1430" y="109" text-anchor="middle">외부 IdP</text>

  <rect class="n core" x="360" y="312" width="760" height="96" rx="18"/>          <!-- 두 열에 걸친 주인공 -->
  <text class="t-inv" x="740" y="354" text-anchor="middle">API 서버</text>
  <text class="t-inv t-sub" x="740" y="384" text-anchor="middle">인증 · 주문 · 알림</text>
  <rect class="n" x="1280" y="312" width="300" height="96" rx="18"/> <text x="1430" y="369" text-anchor="middle">인증 서비스</text>

  <rect class="n"    x="360"  y="572" width="300" height="96" rx="18"/> <text x="510"  y="629" text-anchor="middle">주문 DB</text>
  <rect class="n on" x="820"  y="572" width="300" height="96" rx="18"/> <text x="970"  y="629" text-anchor="middle">이벤트 큐</text>
  <rect class="n"    x="1280" y="572" width="300" height="96" rx="18"/> <text x="1430" y="629" text-anchor="middle">감사 로그</text>

  <!-- 연결: 노드 경계 ±6 -->
  <path class="e" d="M510 154 V306" marker-end="url(#ah3)"/>  <text class="t-lbl" x="526" y="238">HTTPS</text>
  <path class="e" d="M970 154 V306" marker-end="url(#ah3)"/>  <text class="t-lbl" x="986" y="238">HTTPS</text>
  <path class="e" d="M1126 360 H1274" marker-end="url(#ah3)"/> <text class="t-lbl" x="1200" y="344" text-anchor="middle">인증 요청</text>
  <path class="e async weak" d="M1430 306 V154" marker-end="url(#ah3w)"/> <text class="t-lbl" x="1446" y="238">토큰 검증</text>
  <path class="e" d="M510 414 V566" marker-end="url(#ah3)"/>  <text class="t-lbl" x="526" y="498">주문 저장</text>
  <path class="e on" d="M970 414 V566" marker-end="url(#ah3o)"/> <text class="t-lbl on" x="986" y="498">신규 · 이벤트 발행</text>
  <path class="e weak" d="M1430 414 V566" marker-end="url(#ah3w)"/> <text class="t-lbl" x="1446" y="498">기록</text>
</svg>
```

- 레이어가 2개면 띠 높이를 300 으로, 4개면 띠 150·간격 40 으로 다시 나눈다(노드 h 는 96 유지, 노드 y = 띠 y + (띠 높이 − 96)/2).
- 경계(사내/사외, 샌드박스)가 논지면 띠 대신 세로 존(6절 배치)에 `.grp.dash` 를 쓴다.

## 6. 시스템 플로우 (존 + 순번 붙은 흐름)

"요청이 어디를 어떤 순서로 거치나"를 보인다. 주체·시스템마다 세로 존을 두고, 화살표에 **순번 배지**를 붙여 읽는 순서를 강제한다. 존 4개면 `x = 0 / 440 / 880 / 1320`, 폭 380, 간격 60. 노드는 존 안 `x + 40`, 폭 300(중심 = 존 x + 190).

```html
<svg class="dg" viewBox="0 0 1700 720" role="img" aria-label="PR 이 빌드서버 검사를 거쳐 Claude 제안이 코멘트로 돌아오고, 사람이 승인해 머지한다">
  <defs>… ah4 · ah4o …</defs>
  <rect class="grp"      x="0"    y="0" width="380" height="720" rx="24"/> <text class="grp-t" x="28"   y="48">개발자</text>
  <rect class="grp alt"  x="440"  y="0" width="380" height="720" rx="24"/> <text class="grp-t" x="468"  y="48">GITHUB</text>
  <rect class="grp"      x="880"  y="0" width="380" height="720" rx="24"/> <text class="grp-t" x="908"  y="48">빌드서버</text>
  <rect class="grp dash" x="1320" y="0" width="380" height="720" rx="24"/> <text class="grp-t" x="1348" y="48">CLAUDE · 읽기 전용</text>

  <rect class="n"      x="40"   y="120" width="300" height="96" rx="18"/> <text x="190"  y="177" text-anchor="middle">코드 수정</text>
  <rect class="n"      x="480"  y="120" width="300" height="96" rx="18"/> <text x="630"  y="177" text-anchor="middle">Pull Request</text>
  <rect class="n core" x="920"  y="120" width="300" height="96" rx="18"/>
  <text class="t-inv" x="1070" y="162" text-anchor="middle">품질 게이트</text>
  <text class="t-inv t-sub" x="1070" y="192" text-anchor="middle">빌드 · 테스트 · 분석</text>
  <rect class="n"      x="1360" y="120" width="300" height="96" rx="18"/> <text x="1510" y="177" text-anchor="middle">수정 제안</text>
  <rect class="n on"   x="40"   y="420" width="300" height="96" rx="18"/> <text x="190"  y="477" text-anchor="middle">승인 · 머지</text>
  <rect class="n"      x="480"  y="420" width="300" height="96" rx="18"/> <text x="630"  y="477" text-anchor="middle">리뷰 코멘트</text>

  <path class="e"    d="M346 168 H474"  marker-end="url(#ah4)"/>
  <path class="e"    d="M786 168 H914"  marker-end="url(#ah4)"/>
  <path class="e"    d="M1226 168 H1354" marker-end="url(#ah4)"/>
  <path class="e"    d="M1510 222 V468 H786" marker-end="url(#ah4)"/>
  <path class="e on" d="M474 468 H346"  marker-end="url(#ah4o)"/>

  <!-- 순번: 선 중간점에 배지, 라벨은 배지 아래 50 -->
  <g><circle class="no" cx="410"  cy="168" r="20"/><text class="no-t" x="410"  y="174" text-anchor="middle">1</text></g>
  <g><circle class="no" cx="850"  cy="168" r="20"/><text class="no-t" x="850"  y="174" text-anchor="middle">2</text></g>
  <g><circle class="no" cx="1290" cy="168" r="20"/><text class="no-t" x="1290" y="174" text-anchor="middle">3</text></g>
  <g><circle class="no" cx="1070" cy="468" r="20"/><text class="no-t" x="1070" y="474" text-anchor="middle">4</text></g>
  <g><circle class="no on" cx="410" cy="468" r="20"/><text class="no-t" x="410" y="474" text-anchor="middle">5</text></g>
  <text class="t-lbl" x="410"  y="218" text-anchor="middle">PR 생성</text>
  <text class="t-lbl" x="850"  y="218" text-anchor="middle">웹훅</text>
  <text class="t-lbl" x="1290" y="218" text-anchor="middle">실패 로그</text>
  <text class="t-lbl" x="1070" y="518" text-anchor="middle">제안을 코멘트로</text>
  <text class="t-lbl on" x="410" y="518" text-anchor="middle">사람이 결정</text>
</svg>
```

- 단계는 **7개 이하**. 넘으면 앞뒤 두 장으로 나눈다.
- 되돌아오는 흐름은 노드 아래 행(y=420)으로 내려 오른쪽→왼쪽으로 그린다 — 같은 행에서 왕복시키면 선이 겹친다.
- 존 이름이 길면 `.grp-t` 를 존 폭 − 56 안에서 끊는다(18px 대문자, 한글 1자 ≈ 18px).

## 7. 시퀀스 다이어그램 (주체 간 주고받기)

"누가 누구에게 무엇을 어떤 순서로"가 논지일 때. 참여자 **4명·메시지 8개 이하**.

```
참여자 중심 x: 200 / 650 / 1100 / 1550         (간격 450, 3명이면 250 / 850 / 1450)
헤더 노드:   rect.n  x = 중심−150, y=0, w=300, h=80   글자 y=52
lifeline:   line.life  x = 중심, y1=86, y2=H−10
메시지:      첫 y=160, 이후 +72      요청 = path.e,  응답 = path.e.async(반대 방향)
라벨:        y = 메시지y − 16, x = 두 lifeline 중간, text-anchor=middle
자기 호출:   M x,y H x+60 V y+40 H x+6  (marker-end) — 다음 메시지는 평소대로 +72
H(viewBox 높이) = 마지막 메시지 y + 60 (자기 호출이면 +100), 최대 720
```

- 화살표는 출발 lifeline 에서 시작해 도착 lifeline 6px 앞에서 끝낸다(`M200 160 H644`).
- 핵심 메시지 하나만 `.e.on` + `.t-lbl.on`. 나머지는 기본색 — 색이 곧 "여기를 보라"다.
- 라벨 앞에 순번을 붙인다(`① 요청`) — 시퀀스는 위→아래가 순서지만 회의실에선 손가락으로 짚을 번호가 필요하다.

## 8. 플로우차트 · 상태도 · 전/후 대비

**플로우차트(분기)** — 왼→오 주 경로 한 줄(y=360)에 노드를 놓고, 분기는 마름모에서 아래로 뺀다.

```html
<path class="dia" d="M850 300 L960 360 L850 420 L740 360 Z"/>   <!-- 중심 (850,360), 반폭 110 · 반높이 60 -->
<text x="850" y="369" text-anchor="middle">통과?</text>          <!-- 마름모 안은 한글 4자까지 -->
<path class="e"  d="M966 360 H1074" marker-end="url(#ah8)"/>  <text class="t-lbl" x="1020" y="344" text-anchor="middle">예</text>
<path class="e weak" d="M850 426 V554" marker-end="url(#ah8w)"/> <text class="t-lbl" x="866" y="494">아니오</text>
```

**상태도** — 노드를 알약(`rect.n` `rx = h/2`)으로, 왼→오 진행 + 되돌아가는 전이는 아래로 우회. **전이 조건을 반드시 선 라벨로 적는다** — 조건 없는 상태도는 상자 목록이다. 시작점은 `<circle class="no" r="10">`.

**전/후 대비** — 같은 도식을 위(전)·아래(후)로 쌓고, 안 바뀐 노드는 **두 패널에서 x 를 똑같이** 둔다. 사라진 것은 `.n.del` 로 자리에 남기고, 새로 생긴 것만 `.n.on` / `.e.on`. 좌우로 놓으면 각 패널이 절반 폭으로 눌려 노드 3개도 안 들어간다.

## 9. 보조 부품 — 카드 흐름·카드 그리드·숫자 타일·화면 캡처

3절 표의 아래 세 줄(비교·지표·요약·실제 화면)에만 쓴다. **상한**: 아이콘 카드가 주인공인 장은 콘텐츠 장의 1/4 이하, 연속 두 장 금지, 한 장에 아이콘 6개 이하.

```html
<!-- 카드 흐름: 단계가 3~4개뿐인 요약 장에만. 단계 사이에 주체·시스템이 바뀌면 6절 시스템 플로우로 -->
<div class="flow">
  <div class="card">
    <div class="tile"><svg viewBox="0 0 24 24"><!-- search --></svg></div>
    <div class="kicker">Step 1</div>
    <h3>검사</h3>
    <p>빌드 · 단위 테스트<br/>정적분석 · 보안분석</p>
    <div class="foot"><svg viewBox="0 0 24 24"><!-- server --></svg>빌드서버</div>
  </div>
  <div class="arr"><svg class="i" viewBox="0 0 24 24"><path d="M5 12h14M13 6l6 6-6 6"/></svg></div>
  <!-- … -->
  <div class="card on"><div class="tile on">…</div> …</div>   <!-- 결론 카드 하나만 on -->
</div>
<div class="chips">
  <span class="chip"><svg viewBox="0 0 24 24"><!-- clock --></svg>PR 1회 약 5~6분</span>
  <span class="chip on"><svg viewBox="0 0 24 24"><!-- lock --></svg>AI는 커밋 · 머지 권한 없음</span>
</div>

<!-- 카드 그리드 + 숫자: 순서·연결이 없는 병렬 항목의 비교 -->
<div class="grid g4">
  <div class="card sm">
    <div class="row"><div class="tile sm">…</div><span class="meta">4m 27s</span></div>
    <h3>정적·동적 분석</h3>
    <div class="tags"><span class="tag">ASan</span><span class="tag">clang-tidy</span></div>
    <div class="foot">테스트 통과·실패 수 · 코드 결함</div>
  </div>
  …
</div>

<!-- 화면 캡처 + 숫자 타일 -->
<div class="grid g2">
  <div><div class="card shot"><img src="shot-example.png" alt="실행 화면"/></div>
       <div class="caption">시험 실행 화면 (YYYY-MM-DD)</div></div>
  <div style="display:flex;flex-direction:column;gap:20px">
    <div class="card stat"><div class="num">5:29</div><div class="lbl">PR 1회<small>바뀐 파일만 정적분석</small></div></div>
    <div class="card stat"><div class="num">0원</div><div class="lbl">추가 비용<small>기존 서버에서 실행</small></div></div>
  </div>
</div>
```

- 카드 그리드에 아이콘을 꼭 넣을 필요는 없다. 아이콘이 내용을 구별해 주지 못하면(모든 카드가 비슷한 상자·톱니) 빼고 숫자나 태그를 주인공으로 둔다.
- 실제 화면 캡처는 작업 폴더에 PNG 로 두고 상대 경로로 넣는다(아티팩트에는 own file 로 함께 올린다). 원격 이미지 URL 은 아티팩트에서 안 뜬다.

## 10. 아이콘 세트 (인라인 SVG, viewBox 0 0 24 24, 라인)

표지 `cover-visual`·칩·9절 카드용이다. **도식 노드 안에는 아이콘을 넣지 않는다** — 노드는 이름이 주인공이고, 아이콘을 박으면 도식이 다시 아이콘 카드 벽으로 돌아간다.

외부 아이콘 CDN 은 아티팩트 CSP 에 막히므로 쓰지 않는다. 아래 path 를 `<svg viewBox="0 0 24 24">…</svg>` 안에 넣는다(선 굵기·색은 house.css 가 준다). 필요한 아이콘이 없으면 같은 문법(라인, 둥근 끝, 24 그리드)으로 그린다.

| 이름 | 내용 |
|---|---|
| search | `<circle cx="11" cy="11" r="7"/><path d="m20 20-3.5-3.5"/>` |
| check | `<circle cx="12" cy="12" r="9"/><path d="m8 12 3 3 5-6"/>` |
| sparkles | `<path d="M12 3l1.8 4.7 4.7 1.8-4.7 1.8L12 16l-1.8-4.7-4.7-1.8 4.7-1.8z"/><path d="M19 15v4M17 17h4"/>` |
| user-check | `<circle cx="9" cy="8" r="4"/><path d="M3 20c0-3.3 2.7-6 6-6s6 2.7 6 6"/><path d="m16 11 2 2 4-4"/>` |
| server | `<rect x="3" y="4" width="18" height="7" rx="2"/><rect x="3" y="13" width="18" height="7" rx="2"/><path d="M7 7.5h.01M7 16.5h.01"/>` |
| message | `<path d="M4 5h16v11H8l-4 4z"/><path d="M8 9h8M8 12h5"/>` |
| shield | `<path d="M12 3 4 6v6c0 5 3.5 8 8 9 4.5-1 8-4 8-9V6z"/>` |
| flask | `<path d="M9 3h6M10 3v6L4.5 19a1.5 1.5 0 0 0 1.3 2h12.4a1.5 1.5 0 0 0 1.3-2L14 9V3"/><path d="M7 15h10"/>` |
| clock | `<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>` |
| lock | `<rect x="5" y="11" width="14" height="10" rx="2"/><path d="M8 11V7a4 4 0 0 1 8 0v4"/>` |
| refresh | `<path d="M20 11a8 8 0 0 0-14.9-3M4 4v4h4"/><path d="M4 13a8 8 0 0 0 14.9 3M20 20v-4h-4"/>` |
| arrow | `<path d="M5 12h14M13 6l6 6-6 6"/>` |
| pull-request | `<circle cx="6" cy="6" r="2.5"/><circle cx="6" cy="18" r="2.5"/><circle cx="18" cy="18" r="2.5"/><path d="M6 8.5v7M18 15.5V10a3 3 0 0 0-3-3h-4"/><path d="m13 5-2 2 2 2"/>` |
| box | `<path d="M21 8 12 3 3 8v8l9 5 9-5z"/><path d="M3 8l9 5 9-5M12 13v8"/>` |
| x-circle | `<circle cx="12" cy="12" r="9"/><path d="m9 9 6 6M15 9l-6 6"/>` |
