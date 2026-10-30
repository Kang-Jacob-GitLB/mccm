# house 컴포넌트 카탈로그

`assets/house.css` 가 정의하는 마크업. upstream `references/layouts.md` 의 컴포넌트(정의 2단·하이라이트+행·프로세스 레일 등)도 그대로 쓸 수 있지만, 그 컴포넌트의 `h2`(80px 문장형)와 테두리 카드는 이 스킬의 계약과 어긋난다 — 가져다 쓸 때는 제목을 아래 `.hd` 블록으로, 카드를 `.card` 로 바꿔 끼운다.

모든 콘텐츠 장은 `section.slide.hs` + `.hd` 제목 + `.body` 그림 영역이다. 글은 eyebrow 문장 하나, 카드마다 h3 하나·p 최대 두 줄이 상한이다.

## 1. 콘텐츠 장 골격 (제목 교체)

```html
<section class="slide hs" data-label="한눈에">
  <div class="stage-pad">
    <div class="hd">
      <span class="eyebrow">도구가 찾고, AI가 제안하고, 사람이 결정합니다</span>   <!-- 작은 제목 = 메시지 문장 -->
      <h2>한눈에 · <span class="en">Overview</span></h2>                          <!-- 큰 제목 = 짧은 라벨 -->
    </div>
    <div class="body">
      <!-- 그림 하나: flow / grid / zone / shot -->
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

## 3. 단계 카드 흐름 (Overview 형)

```html
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
  <div class="card on">   <!-- 결론 카드 하나만 on: 오렌지 테두리 + 오렌지 타일 -->
    <div class="tile on">…</div> …
  </div>
</div>
<div class="chips">
  <span class="chip"><svg viewBox="0 0 24 24"><!-- clock --></svg>PR 1회 약 5~6분</span>
  <span class="chip on"><svg viewBox="0 0 24 24"><!-- lock --></svg>AI는 커밋 · 머지 권한 없음</span>
</div>
```

## 4. 작은 카드 그리드 + 숫자 타일 (구성·지표 형)

```html
<div class="grid g4">
  <div class="card sm">
    <div class="row"><div class="tile sm">…</div><span class="meta">4m 27s</span></div>
    <h3>정적·동적 분석</h3>
    <div class="tags"><span class="tag">ASan</span><span class="tag">clang-tidy</span></div>
    <div class="foot">테스트 통과·실패 수 · 코드 결함</div>
  </div>
  …
</div>
<div class="grid g2">
  <div><div class="card shot"><img src="shot-example.png" alt="실행 화면"/></div>
       <div class="caption">시험 실행 화면 (YYYY-MM-DD)</div></div>
  <div style="display:flex;flex-direction:column;gap:20px">
    <div class="card stat"><div class="num">5:29</div><div class="lbl">PR 1회<small>바뀐 파일만 정적분석</small></div></div>
    <div class="card stat"><div class="num">0원</div><div class="lbl">추가 비용<small>기존 서버에서 실행</small></div></div>
  </div>
</div>
```

실제 화면 캡처는 작업 폴더에 PNG 로 두고 상대 경로로 넣는다(아티팩트에는 own file 로 함께 올린다). 원격 이미지 URL 은 아티팩트에서 안 뜬다.

## 5. 구조도 (존 + 노드 카드 + SVG 연결선)

묶음은 `.zone`(격리·샌드박스면 `.zone.dash` + `.badge`), 그 안의 요소는 `.card.sm` 에 `.tile.sm`. 존 사이 연결선은 `.body` 위에 절대 배치한 인라인 SVG 로 그린다:

```html
<div class="body" style="position:relative">
  <div class="grid" style="grid-template-columns:.7fr 1.2fr 1.4fr">
    <div class="zone"><div class="zl"><svg class="i" …/>사람</div> … </div>
    <div class="zone"><div class="zl">GitHub</div> … </div>
    <div class="zone dash"><span class="badge">Sandbox · 읽기 전용</span> … </div>
  </div>
  <svg style="position:absolute;inset:0;pointer-events:none" viewBox="0 0 1700 760">
    <path d="M330 120 H420" stroke="#1E2A44" stroke-width="2" fill="none" marker-end="url(#ah)"/>
    <defs><marker id="ah" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="8" markerHeight="8" orient="auto">
      <path d="M0 0 L10 5 L0 10z" fill="#1E2A44"/></marker></defs>
  </svg>
</div>
```

연결선 좌표는 렌더 PNG 로 확인하며 맞춘다. 선 위 라벨은 `.chip` 을 절대 배치한다.

## 6. 아이콘 세트 (인라인 SVG, viewBox 0 0 24 24, 라인)

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
