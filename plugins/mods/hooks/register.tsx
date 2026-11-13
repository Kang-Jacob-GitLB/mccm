import type { Register } from 'claude-code'

import {
  abovePrompt as actionLineBand,
  paneBox as actionLinePane,
  sessionStart as actionLineStart,
  turnComplete as actionLineTurn,
} from './action-line/index'
import {
  abovePrompt as prLineBand,
  paneBox as prLinePane,
  sessionStart as prLineStart,
  turnComplete as prLineTurn,
} from './pr-line/index'
import { markPane, startPaneWatch } from './shared/pane'
import {
  abovePrompt as whereLineBand,
  sessionStart as whereLineStart,
  toolCallDone as whereLineTool,
  turnComplete as whereLineTurn,
} from './where-line/index'
import { sessionStart as versionTagStart } from './version-tag/index'

// mods: 여러 mod 를 한 플러그인에 담는다.
//
// 플러그인 하나는 hooks 모듈을 하나만 가질 수 있고, matcher 없는 같은 이벤트
// (session.start, turn.complete 등)를 두 번 걸 수 없다. 그래서
//   - 각 mod 는 hooks/<mod>/index.tsx 에 두고, 그릴 것·할 일을 함수로 내보낸다.
//   - 훅은 여기서 한 번만 걸고 각 mod 의 함수를 차례로 부른다. 같은 자리(Flightdeck 패널, 입력창 위)에
//     여러 mod 가 그리면 같은 플러그인 안 훅의 순서가 문서에 정해져 있지 않으니, 여기서 모아 순서를 고정한다.
//   - mod 끼리 함께 쓰는 것은 hooks/shared/ 에 둔다(패널 부착 상태, GitHub 글자 정리).
//   - 상태 키는 mod 이름을 앞에 붙인다(prLinePrs). 타입은 types/index.d.ts 한 곳에.
// mod 를 끄려면 플러그인 설정 disabled 에 이름을 쉼표로 적는다(예: "pr-line").

function disabledSet(value: unknown): Set<string> {
  const text = Array.isArray(value) ? value.join(',') : typeof value === 'string' ? value : ''
  return new Set(text.split(',').map(s => s.trim()).filter(Boolean))
}

export const register: Register = (on, options) => {
  const off = disabledSet(options.disabled)
  const prLineOn = !off.has('pr-line')
  const actionLineOn = !off.has('action-line')
  const whereLineOn = !off.has('where-line')
  const versionTagOn = !off.has('version-tag')
  const paneOn = prLineOn || actionLineOn

  // Flightdeck 패널 맨 아래에 위에서부터 pull requests 상자, actions 상자를 붙인다.
  // Flightdeck 의 패널 훅은 next 를 부르지 않아 mods 가 그보다 바깥에서 돌 때만 여기 온다.
  // 같은 사용자 설치 mod 끼리의 순서는 정해져 있지 않으므로 plugin.json dependencies 로 고정한다
  // (의존하는 쪽이 먼저 = 바깥). 둘 다 그릴 것이 없으면 패널을 그대로 둔다.
  if (paneOn) {
    on('ui.render', { component: 'Pane', requestId: 'flightdeck' }, async ($, e, next) => {
      const inner = await next(e)
      const prBox = prLineOn ? await prLinePane($, e) : null
      const runBox = actionLineOn ? await actionLinePane($, e) : null
      if (prBox === null && runBox === null) return inner
      await markPane($)
      const { Box } = $.ui.resolve(e)
      // 패널 높이만큼 늘리고 가운데를 빈 칸으로 채워 상자들을 맨 아래에 붙인다.
      // Flightdeck 내용이 패널보다 길면 늘어난 만큼 그대로 아래로 이어진다.
      const rows = e.props.scroll?.bodyRows ?? 0
      return (
        <Box flexDirection="column" minHeight={rows > 0 ? rows : undefined}>
          {inner}
          <Box flexGrow={1} />
          {prBox}
          {runBox}
        </Box>
      )
    })
  }

  // 입력창 위 band 도 여기서 한 번만 건다 — 각 mod 의 줄을 모아 한 번에 그린다.
  // 위에 한 줄 띄워 스피너(Brewing… 등)와 떼어 놓는다. 입력창과의 사이 빈 줄은 엔진이 그리는 여백이라
  // band 안에서는 지울 수 없다(marginBottom -1 은 band 밖으로 밀려 줄이 잘려 보이지 않았다).
  if (paneOn || whereLineOn) {
    on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
      const below = await next(e)
      if (e.props.hasSurvey) return below
      const prRows = prLineOn ? await prLineBand($, e) : null
      const runRows = actionLineOn ? await actionLineBand($, e) : null
      const whereRow = whereLineOn ? await whereLineBand($, e) : null
      if (prRows === null && runRows === null && whereRow === null) return below
      const { Box } = $.ui.resolve(e)
      return (
        <Box flexDirection="column" marginTop={1}>
          {below}
          {prRows}
          {runRows}
          {whereRow}
        </Box>
      )
    })
  }

  on('session.start', async ($, e, next) => {
    if (paneOn) startPaneWatch($)
    if (prLineOn) await prLineStart($)
    if (actionLineOn) await actionLineStart($)
    if (whereLineOn) await whereLineStart($)
    if (versionTagOn) await versionTagStart($)
    return next(e)
  })

  on('turn.complete', async ($, e, next) => {
    if (prLineOn) await prLineTurn($)
    if (actionLineOn) await actionLineTurn($)
    if (whereLineOn) await whereLineTurn($)
    return next(e)
  })

  // 툴 호출은 그대로 통과시키고, 끝난 뒤에만 각 mod 에 알린다. 실패해도 툴 호출을 막지 않는다.
  if (whereLineOn) {
    on('tool.call', async ($, e, next) => {
      const r = await next(e)
      whereLineTool($, e.tool, r.result)
      return r
    }).catch(($, e, next) => next(e))
  }
}
