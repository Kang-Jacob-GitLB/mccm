# 다이어그램 좌표 레시피

손으로 SVG를 쓸 때 가장 흔한 실패는 미학이 아니라 **정렬**이다 — 박스가 몇 픽셀씩 어긋나고, 화살표가 박스를 파고들고, 라벨이 선에 겹친다. 아래 좌표계는 그 계산을 대신 해준다. 그대로 쓰고 내용만 바꾸면 된다.

`artifact-diagramming` 스킬이 SVG 일반 기법(viewBox, currentColor, 마커, 접근성)을 담당한다. 여기 있는 것은 이 보고서에 반복해서 나오는 세 가지 그림의 **치수표와 골격**이다.

## 목차

- [색 규약](#색-규약) — 변경을 나타내는 색은 의미가 고정이다
- [공통 치수](#공통-치수)
- [Before/After 블록다이어그램](#beforeafter-블록다이어그램) — 완전한 예시 포함
- [시퀀스 다이어그램](#시퀀스-다이어그램) — 완전한 예시 포함
- [상태 전이도](#상태-전이도)
- [한글 텍스트 치수](#한글-텍스트-치수) — 영문 기준 간격이 한글에서 겹치는 이유
- [겹침 방지](#겹침-방지)
- [흔한 실패](#흔한-실패)

## 색 규약

변경을 나타내는 색은 장식이 아니라 범례다. 페이지 CSS에 토큰으로 정의하고 SVG에서 `var()`로 참조하면 테마 전환이 저절로 따라온다 (인라인 SVG는 CSS 변수를 상속받는다).

```css
:root {
  --dg-add: #15803d;   /* 새로 생긴 것 */
  --dg-del: #b91c1c;   /* 사라진 것 */
  --dg-mod: #a16207;   /* 교체·이동된 것 */
}
:root:not([data-theme="light"]) {
  @media (prefers-color-scheme: dark) {
    --dg-add: #4ade80; --dg-del: #f87171; --dg-mod: #fbbf24;
  }
}
:root[data-theme="dark"] {
  --dg-add: #4ade80; --dg-del: #f87171; --dg-mod: #fbbf24;
}
```

`artifact-design`이 정한 팔레트와 어긋나면 그쪽 색조를 따르되, **세 색이 서로 구별되고 양쪽 테마에서 읽히는 것**만 지킨다.

바뀌지 않은 요소는 전부 `currentColor`로 둔다. 색이 붙은 것이 곧 "여기를 보라"는 신호이므로, 안 바뀐 것에 색을 주면 신호가 지워진다.

## 공통 치수

| 요소 | 값 |
|---|---|
| 박스 | `w=132 h=44 rx=6` |
| 박스 가로 간격 | 98 (좌표 간격 230) |
| 박스 세로 간격 | 36 (좌표 간격 80) |
| 박스 테두리 | `stroke-width=1.5` |
| 화살표 선 | `stroke-width=1.5`, 박스 경계에서 6px 띄우고 시작·종료 |
| 본문 텍스트 | `font-size=12`, 박스 안은 `text-anchor="middle"` |
| 라벨 텍스트 | `font-size=11`, `opacity=.85`, 선 위 8px |
| 패널 제목 | `font-size=13 font-weight=600` |

박스 안 텍스트의 세로 중심은 `y = 박스y + 27` (기준선 보정 포함).

## Before/After 블록다이어그램

**패널을 위아래로 쌓는다.** 좌우로 나란히 놓으면 각 패널이 절반 폭으로 눌려 박스 3개도 안 들어간다. 위아래로 쌓으면 같은 x 좌표를 두 패널이 공유하므로, **안 바뀐 박스가 정확히 같은 세로선 위에 놓여** 눈이 차이만 집어낸다. 그게 이 그림의 전부다.

박스가 양쪽 합쳐 4개 이하로 아주 단순할 때만 좌우 배치를 고려한다.

### 좌표

```
viewBox="0 0 680 320"

Before 패널   제목 y=24
             박스 y=48  (텍스트 y=75)
구분선        y=140     (dasharray 4 4, opacity .25)
After 패널    제목 y=180
             박스 y=204 (텍스트 y=231)
우회 경로     y=286

박스 x: 40 / 270 / 500          (박스 오른쪽 끝 = x+132)
화살표: x1 = 앞박스끝+6, x2 = 뒷박스시작-6   예) 178 → 264
라벨 x = 두 박스 중심의 중간, y = 화살표y - 8
```

박스가 4개면 폭을 `910`으로 늘리고 x에 `730`을 더한다. 두 패널을 가르는 구분선의 `x2`도 함께 `894`로 늘린다(폭 − 16). 5개를 넘으면 그림이 아니라 목록이 필요한 신호다 — 논지에 걸리는 것만 남기고 잘라낸다.

### 골격

아래는 "요청이 `SessionCache`를 거치지 않고 `Store`로 직행하게 됐다"를 그린 것이다. 구조를 유지한 채 이름과 라벨만 바꿔 쓴다.

```html
<figure>
  <svg viewBox="0 0 680 320" role="img"
       aria-label="변경 전에는 Handler가 SessionCache를 거쳐 Store를 조회했고, 변경 후에는 Handler가 Store를 직접 조회한다"
       style="max-width:100%; height:auto">
    <defs>
      <marker id="ar" viewBox="0 0 8 8" refX="7" refY="4" markerWidth="7" markerHeight="7" orient="auto">
        <path d="M0,0 L8,4 L0,8 z" fill="currentColor"/>
      </marker>
      <marker id="ar-add" viewBox="0 0 8 8" refX="7" refY="4" markerWidth="7" markerHeight="7" orient="auto">
        <path d="M0,0 L8,4 L0,8 z" fill="var(--dg-add)"/>
      </marker>
    </defs>

    <!-- 변경 전 -->
    <text x="16" y="24" font-size="13" font-weight="600">변경 전</text>
    <g fill="none" stroke="currentColor" stroke-width="1.5">
      <rect x="40"  y="48" width="132" height="44" rx="6"/>
      <rect x="270" y="48" width="132" height="44" rx="6"/>
      <rect x="500" y="48" width="132" height="44" rx="6"/>
      <line x1="178" y1="70" x2="264" y2="70" marker-end="url(#ar)"/>
      <line x1="408" y1="70" x2="494" y2="70" marker-end="url(#ar)"/>
    </g>
    <g font-size="12" text-anchor="middle" fill="currentColor">
      <text x="106" y="75">Handler</text>
      <text x="336" y="75">SessionCache</text>
      <text x="566" y="75">Store</text>
    </g>
    <g font-size="11" text-anchor="middle" fill="currentColor" opacity=".85">
      <text x="221" y="62">조회</text>
      <text x="451" y="62">miss 시 조회</text>
    </g>

    <line x1="16" y1="140" x2="664" y2="140" stroke="currentColor"
          stroke-dasharray="4 4" opacity=".25"/>

    <!-- 변경 후 -->
    <text x="16" y="180" font-size="13" font-weight="600">변경 후</text>
    <g fill="none" stroke="currentColor" stroke-width="1.5">
      <rect x="40"  y="204" width="132" height="44" rx="6"/>
      <rect x="500" y="204" width="132" height="44" rx="6"/>
    </g>
    <!-- 제거된 컴포넌트: 점선 + 흐리게, 같은 자리에 남겨 차이를 보이게 한다 -->
    <g opacity=".35">
      <rect x="270" y="204" width="132" height="44" rx="6" fill="none"
            stroke="var(--dg-del)" stroke-width="1.5" stroke-dasharray="5 4"/>
      <text x="336" y="231" font-size="12" text-anchor="middle"
            fill="var(--dg-del)">SessionCache</text>
      <text x="336" y="196" font-size="11" text-anchor="middle"
            fill="var(--dg-del)">제거됨</text>
    </g>
    <g font-size="12" text-anchor="middle" fill="currentColor">
      <text x="106" y="231">Handler</text>
      <text x="566" y="231">Store</text>
    </g>
    <!-- 새 경로: 제거된 박스 아래로 우회 -->
    <polyline points="106,254 106,286 566,286 566,254" fill="none"
              stroke="var(--dg-add)" stroke-width="1.5" marker-end="url(#ar-add)"/>
    <text x="336" y="278" font-size="11" text-anchor="middle"
          fill="var(--dg-add)">직접 조회</text>
  </svg>
  <figcaption>세션 조회가 캐시 계층을 건너뛰고 <code>Store</code>로 직행한다 — 캐시 무효화 경로가 통째로 사라졌다.</figcaption>
</figure>
```

캡션은 그림의 결론을 문장으로 못 박는 자리다. "변경 전후 구조"처럼 그림 제목을 반복하는 캡션은 아무 일도 하지 않는다.

## 시퀀스 다이어그램

"누가 누구에게 무엇을 어떤 순서로"가 논지일 때 쓴다. **참여자 4개, 메시지 8개를 넘기면** 읽는 사람이 순번을 놓친다 — 그때는 구간을 나눠 두 그림으로 쪼개거나, 한 단계 위로 추상해서 블록다이어그램으로 바꾼다.

### 좌표

```
참여자 x: 100 / 300 / 500 / 700     (간격 200)
헤더 박스: x-70, y=10, w=140, h=32   (텍스트 y=31)
lifeline:  x 고정, y1=42, y2=H-14
메시지 1번 y=78, 이후 40씩 증가
라벨 y = 메시지y - 8, 중앙 정렬
viewBox 폭  W = 마지막 참여자 x + 100   (3명이면 600, 4명이면 800)
viewBox 높이 H = 마지막 메시지 y + 30
             단, 마지막이 자기 호출이면 y + 56
```

**W를 빼먹으면 마지막 참여자가 통째로 잘린다.** 헤더 박스가 `x-70`부터 `x+70`까지 쓰므로 4번째 참여자(x=700)는 770까지 간다 — 폭을 600으로 두면 헤더도 lifeline도 화살표도 렌더되지 않고, 그림은 아무 경고 없이 조용히 3명짜리로 보인다.

**마지막이 자기 호출일 때 H가 다른 이유**는 ㄷ자가 `y`부터 `y+26`까지를 쓰기 때문이다. 거기에 다른 경우와 같은 30px 여백을 주면 `y+56`이고, 그래야 `lifeline y2 = H-14 = y+42`가 ㄷ자 하단보다 아래에 온다. `y+30`으로 두면 화살촉이 잘리고 lifeline이 화살표보다 10px 위에서 끊겨 허공을 가리킨다.

- **요청**은 실선, **응답**은 `stroke-dasharray="4 3"` + 반대 방향 화살표.
- **자기 호출**은 오른쪽으로 나갔다 돌아오는 ㄷ자:
  `M x,y L x+34,y L x+34,y+26 L x+6,y+26` (`marker-end`).
  ㄷ자가 `y`부터 `y+26`까지를 쓰므로 **다음 메시지는 평소대로 `+40`**이면 14px 여유로 비껴간다.
- **새로 생긴 메시지만** `var(--dg-add)`. 기존 흐름은 `currentColor`.
- 화살표 x는 lifeline에서 시작해 목표 lifeline보다 6px 앞에서 끝낸다 (`x2 = 294` 식).

### 골격

```html
<figure>
  <svg viewBox="0 0 600 268" role="img"
       aria-label="Client가 Handler에 요청하면 Handler가 Store를 조회하고, 새로 추가된 감사 로그 기록 후 응답한다"
       style="max-width:100%; height:auto">
    <defs>
      <marker id="sq" viewBox="0 0 8 8" refX="7" refY="4" markerWidth="7" markerHeight="7" orient="auto">
        <path d="M0,0 L8,4 L0,8 z" fill="currentColor"/>
      </marker>
      <marker id="sq-add" viewBox="0 0 8 8" refX="7" refY="4" markerWidth="7" markerHeight="7" orient="auto">
        <path d="M0,0 L8,4 L0,8 z" fill="var(--dg-add)"/>
      </marker>
    </defs>

    <!-- 참여자 헤더 + lifeline -->
    <g fill="none" stroke="currentColor" stroke-width="1.5">
      <rect x="30"  y="10" width="140" height="32" rx="6"/>
      <rect x="230" y="10" width="140" height="32" rx="6"/>
      <rect x="430" y="10" width="140" height="32" rx="6"/>
    </g>
    <g font-size="12" text-anchor="middle" fill="currentColor">
      <text x="100" y="31">Client</text>
      <text x="300" y="31">Handler</text>
      <text x="500" y="31">Store</text>
    </g>
    <g stroke="currentColor" opacity=".3" stroke-dasharray="3 4">
      <line x1="100" y1="42" x2="100" y2="254"/>
      <line x1="300" y1="42" x2="300" y2="254"/>
      <line x1="500" y1="42" x2="500" y2="254"/>
    </g>

    <!-- 메시지 -->
    <g stroke="currentColor" stroke-width="1.5" fill="none">
      <line x1="100" y1="78"  x2="294" y2="78"  marker-end="url(#sq)"/>
      <line x1="300" y1="118" x2="494" y2="118" marker-end="url(#sq)"/>
      <line x1="500" y1="158" x2="306" y2="158" marker-end="url(#sq)" stroke-dasharray="4 3"/>
      <line x1="300" y1="238" x2="106" y2="238" marker-end="url(#sq)" stroke-dasharray="4 3"/>
    </g>
    <!-- 새로 추가된 자기 호출 -->
    <path d="M300,198 L334,198 L334,224 L306,224" fill="none"
          stroke="var(--dg-add)" stroke-width="1.5" marker-end="url(#sq-add)"/>

    <g font-size="11" text-anchor="middle" fill="currentColor" opacity=".85">
      <text x="197" y="70">GET /session/:id</text>
      <text x="397" y="110">fetch(id)</text>
      <text x="403" y="150">record</text>
      <text x="203" y="230">200 OK</text>
    </g>
    <text x="344" y="192" font-size="11" fill="var(--dg-add)">감사 로그 기록 (신규)</text>
  </svg>
  <figcaption>응답 직전에 감사 로그 기록 단계가 끼어든다 — 실패하면 응답까지 막히는 경로다.</figcaption>
</figure>
```

> 검산: 메시지가 `78 · 118 · 158 · (자기 호출 198) · 238`이므로 `H = 238 + 30 = 268`이고, lifeline은 `y2 = 268 − 14 = 254`에서 끝난다 — 위 코드의 값과 정확히 맞는다. 자기 호출의 ㄷ자 하단이 `224`이고 다음 메시지가 `238`이라 겹치지 않는다.

## 상태 전이도

수명주기·상태 머신 변경에 쓴다. 노드는 알약 모양(`rect w=120 h=40 rx=20`)으로 두고, 배치는 **왼→오 진행 + 되돌아가는 전이는 아래로 우회**가 가장 읽기 쉽다.

- 새로 생긴 상태는 테두리 `var(--dg-add)`, 사라진 상태는 점선 + `var(--dg-del)` + `opacity .35`로 자리에 남긴다 (Before/After와 같은 규칙).
- **전이 조건을 반드시 화살표에 쓴다.** 조건 없는 상태도는 상자 목록에 지나지 않는다.
- 시작점은 지름 7의 채운 원, 종료점은 이중 원.

## 한글 텍스트 치수

SVG는 텍스트를 자동으로 줄바꿈하지도, 넘쳤다고 알려주지도 않는다. 한글은 라틴 문자와 치수가 크게 달라서 **영문 감각으로 잡은 간격이 한글에서는 그대로 겹침이 된다.**

| | 글자 폭 | 세로 |
|---|---|---|
| 한글 | ≈ `font-size` × 1.0 | 어센더가 거의 1em을 채운다 |
| 라틴 소문자 | ≈ `font-size` × 0.55 | 여백이 남는다 |

- **두 줄 라벨의 baseline 간격은 최소 `font-size + 4`** — 11px 폰트면 15px 이상. 간격 8px에 10.5px·11px 폰트를 얹으면 글리프가 실제로 겹친다(계산상 1.6px 중첩).
- **박스 안 텍스트 폭 ≈ (한글 자수 × font-size) + (라틴 자수 × font-size × 0.55).** 이 값이 `박스 폭 − 24`를 넘으면 글자를 줄이거나 박스를 넓힌다. 폴백 폰트(Malgun Gothic 등)는 더 넓게 잡히므로 한계에 붙지 않게 여유를 둔다.
- 라벨이 길어지면 **줄이는 쪽이 맞다.** 설명 문장은 그림이 아니라 `<figcaption>`의 몫이다.

## 겹침 방지

- **선과 텍스트가 같은 x(또는 y)를 쓰면 관통한다.** 세로 구간이 `x=566`인 화살표와 `text-anchor="middle" x="566"`인 라벨은 폰트와 무관하게 반드시 겹친다. 라벨을 옆으로 비키거나(`text-anchor="start"`, `x = 선x + 8`) 선을 옮긴다.
- **두 경로가 같은 구간을 공유하면 뒤에 그린 것이 앞을 덮는다.** 색이 곧 범례인 그림에서는 의미가 지워진다 — 검은 경로와 초록 경로가 한 구간을 공유하면 그 구간 전체가 초록으로 보이고, 독자는 갈래가 어디서 나뉘는지 잘못 읽는다. 공유 구간은 4~6px 어긋나게 그리거나 갈라지는 지점을 앞당긴다.
- 그리고 나서 좌표를 **산술로 한 번 검산한다.** 각 텍스트의 x 범위(위 폭 공식)가 박스 안인가, **모든 x가 `viewBox` 폭 안인가**, 최하단 요소의 y가 `viewBox` 높이 안인가, 이웃한 두 라벨의 y 간격이 폰트 크기보다 큰가. 폭을 넘긴 요소는 오류를 내지 않고 그냥 사라지므로, 이 항목을 빠뜨리면 잘린 줄도 모른다. 좌표는 전부 파일에 숫자로 적혀 있으니 눈이 아니라 계산으로 판정할 수 있다.

## 흔한 실패

| 증상 | 원인 | 대응 |
|---|---|---|
| 화살표 끝이 박스를 파고든다 | `x2`를 박스 좌표에 딱 맞춤 | 박스 경계에서 6px 앞에서 끊는다 |
| 다크 모드에서 그림이 사라진다 | 검정 하드코딩 | 안 바뀐 요소는 전부 `currentColor` |
| 화살표 머리 색이 선과 다르다 | 마커를 하나만 정의하고 재사용 | 색마다 마커를 따로 정의한다 (`ar`, `ar-add`, `ar-del`) |
| 라벨이 선에 겹친다 | 라벨 y를 선과 같게 둠 | 선 위 8px (`y = 선y - 8`) |
| 좁은 화면에서 잘린다 | 고정 `width` 지정 | `viewBox` + `max-width:100%; height:auto` |
| Before/After가 비교되지 않는다 | 두 패널의 좌표가 다름 | 안 바뀐 박스는 두 패널에서 x를 똑같이 |
| 한글 라벨 두 줄이 겹친다 | 영문 감각으로 잡은 8px 간격 | baseline 간격 ≥ `font-size + 4` |
| 화살표가 라벨을 관통한다 | 선과 텍스트가 같은 x를 씀 | 라벨을 8px 비키거나 선을 옮긴다 |
| 색이 다른 두 경로가 한 색으로 보인다 | 같은 좌표 구간을 공유 | 4~6px 어긋나게 그린다 |
| 박스 안 글자가 넘친다 | 한글 폭을 라틴 기준으로 어림 | 한글 1자 ≈ `font-size` 로 계산 |
