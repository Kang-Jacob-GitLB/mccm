import type { Register } from 'claude-code'

import {
  abovePrompt as prLineBand,
  register as prLineRegister,
  sessionStart as prLineStart,
  toolCallDone as prLineTool,
  turnComplete as prLineTurn,
} from './pr-line/index'
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
//   - 각 mod 는 hooks/<mod>/index.tsx 에 두고, matcher 있는 훅만 자기 register 로 건다.
//   - matcher 없는 공용 이벤트는 여기서 한 번만 걸고 각 mod 의 함수를 차례로 부른다.
//   - 상태 키는 mod 이름을 앞에 붙인다(prLinePrs). 타입은 types/index.d.ts 한 곳에.
// mod 를 끄려면 플러그인 설정 disabled 에 이름을 쉼표로 적는다(예: "pr-line").

function disabledSet(value: unknown): Set<string> {
  const text = Array.isArray(value) ? value.join(',') : typeof value === 'string' ? value : ''
  return new Set(text.split(',').map(s => s.trim()).filter(Boolean))
}

export const register: Register = (on, options) => {
  const off = disabledSet(options.disabled)
  const prLineOn = !off.has('pr-line')
  const whereLineOn = !off.has('where-line')
  const versionTagOn = !off.has('version-tag')

  if (prLineOn) prLineRegister(on, options)

  // 입력창 위 band 는 여기서 한 번만 건다. 같은 플러그인 안 훅의 순서는 문서에 정해져 있지 않아,
  // mod 마다 따로 걸면 어느 쪽이 바깥에 그려질지 알 수 없다 — 그래서 각 mod 의 줄을 모아 한 번에 그린다.
  // 위에 한 줄 띄워 스피너(Brewing… 등)와 떼어 놓는다. 입력창과의 사이 빈 줄은 엔진이 그리는 여백이라
  // band 안에서는 지울 수 없다(marginBottom -1 은 band 밖으로 밀려 줄이 잘려 보이지 않았다).
  if (prLineOn || whereLineOn) {
    on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
      const below = await next(e)
      if (e.props.hasSurvey) return below
      const prRows = prLineOn ? await prLineBand($, e) : null
      const whereRow = whereLineOn ? await whereLineBand($, e) : null
      if (prRows === null && whereRow === null) return below
      const { Box } = $.ui.resolve(e)
      return (
        <Box flexDirection="column" marginTop={1}>
          {below}
          {prRows}
          {whereRow}
        </Box>
      )
    })
  }

  on('session.start', async ($, e, next) => {
    if (prLineOn) await prLineStart($)
    if (whereLineOn) await whereLineStart($)
    if (versionTagOn) await versionTagStart($)
    return next(e)
  })

  on('turn.complete', async ($, e, next) => {
    if (prLineOn) await prLineTurn($)
    if (whereLineOn) await whereLineTurn($)
    return next(e)
  })

  // 툴 호출은 그대로 통과시키고, 끝난 뒤에만 각 mod 에 알린다. 실패해도 툴 호출을 막지 않는다.
  if (prLineOn || whereLineOn) {
    on('tool.call', async ($, e, next) => {
      const r = await next(e)
      if (whereLineOn) whereLineTool($)
      if (prLineOn) void prLineTool($, e.tool, r.result).catch(() => {})
      return r
    }).catch(($, e, next) => next(e))
  }
}
