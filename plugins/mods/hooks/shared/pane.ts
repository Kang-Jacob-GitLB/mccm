import type { EngineInterface, Timer } from 'claude-code'

// Flightdeck 패널(requestId 'flightdeck')에 붙어 있는지 — pr-line·action-line 이 함께 쓴다.
// 패널 안에 그리는 동안은 입력창 위 대체 줄을 끄고, 한동안 안 그려지면(패널을 닫으면) 다시 켠다.
// 모듈 변수라 리로드되면 '안 붙음'부터 시작한다.

const PANE_FRESH_MS = 45_000
const WATCH_MS = 15_000

let paneAt = 0
let paneShown = false
let watch: Timer | undefined

export function isPaneShown(): boolean {
  return paneShown
}

// 패널 안에 그렸다. 처음 붙었으면 입력창 위 대체 줄을 지우러 다시 그린다.
export async function markPane($: EngineInterface) {
  paneAt = await $.clock.now()
  if (!paneShown) {
    paneShown = true
    $.ui.invalidate('ui.render')
  }
}

async function checkPane($: EngineInterface) {
  if (paneShown && (await $.clock.now()) - paneAt > PANE_FRESH_MS) {
    paneShown = false
    $.ui.invalidate('ui.render')
  }
}

// 세션 시작에 건다. 리로드로 다시 불려도 타이머가 겹치지 않게 옛 것을 먼저 끈다.
export function startPaneWatch($: EngineInterface) {
  watch?.cancel()
  watch = $.clock.every(WATCH_MS, () => {
    void checkPane($)
  })
}
