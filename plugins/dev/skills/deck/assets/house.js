/* dev:deck — 아티팩트 미리보기에서 1920px 슬라이드를 창 너비에 맞춰 줄인다.
   build_pdf.py·build_pptx.py 는 deck.html 을 file:// 로 열어 캡처하므로 거기서는
   아무것도 하지 않는다. 이 가드를 지우면 검증용 PNG 가 축소된 채 찍힌다. */
(function () {
  if (location.protocol === 'file:') return;
  var root = document.documentElement;
  root.classList.add('fit');
  function fit() { root.style.setProperty('--fit', Math.min(1, (window.innerWidth - 48) / 1920)); }
  fit();
  window.addEventListener('resize', fit);
})();
