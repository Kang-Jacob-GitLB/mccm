// Flightdeck 패널에 pr-line·action-line 상자가 붙는지 그려 본다. 실행: claude plugin test plugins/mods
import { expect, test } from 'claude-code/testing'
import type { TestBody } from 'claude-code/testing'

type On = Parameters<TestBody>[1]

// 패널은 Flightdeck 이 연다 — 실제처럼 plugin 을 'flightdeck' 으로 둔다. 단, 테스트 킷은 매처의 plugin 기본값
// (생략하면 자기 플러그인 것만)을 적용하지 않아 register.tsx 매처에서 plugin: '*' 가 빠져도 여기선 통과한다.
const PANE = {
  plugin: 'flightdeck',
  component: 'Pane',
  requestId: 'flightdeck',
  surface: 'terminal',
  props: {
    title: 'Flightdeck',
    isFocused: false,
    bodyColumns: 60,
    placement: 'dock',
    scroll: { offset: 0, bodyRows: 20 },
    view: {},
  },
} as const

const PR_URL = 'https://github.com/o/r/pull/7'
const RUN_URL = 'https://github.com/o/r/actions/runs/9'
const PR = { number: 7, url: PR_URL, title: 'feat: x', branch: 'feat', isDraft: false, pass: 1, fail: 0, pending: 0, current: '', merge: 'CLEAN' }
const RUN = { id: 9, number: 324, url: RUN_URL, workflow: 'release', branch: 'v1.2.0', event: 'push', status: 'completed', conclusion: 'failure', finishedAt: '' }

// 상태 저장소를 대신한다: 키마다 shape 태그를 단 값을 돌려준다(없는 키는 쓰인 적 없음).
// 쓰기(state.set)는 테스트 킷이 받아 준다.
function seed(on: On, values: Record<string, unknown>) {
  on('state.get', (_, e) => {
    const key: string = e.key
    return { value: key in values ? { value: values[key], version: 1 } : { value: undefined, version: 0 } }
  })
  // 패널에 붙은 시각을 적을 때 쓴다
  on('clock.now', () => ({ value: 1_000 }))
  // 엔진이 그리는 Flightdeck 본문 자리
  on('ui.render', ($, e) => {
    const { Text } = $.ui.resolve(e)
    return <Text>flightdeck body</Text>
  })
}

test('PR 상자 아래에 actions 상자가 붙는다', async ($, on) => {
  seed(on, {
    prLinePrs: { shape: 'prs-3', value: [PR] },
    actionLineRuns: { shape: 'runs-4', value: [RUN] },
  })
  const ui = await $.ui.mount(PANE)
  const body = await ui.find({ type: 'Text', text: /flightdeck body/ })
  const prHead = await ui.find({ type: 'Text', text: /pull requests/ })
  const runHead = await ui.find({ type: 'Text', text: /^actions/ })
  const fail = await ui.find({ type: 'Text', text: /✘ 실패/ })
  expect(body === undefined).toBe(false)
  expect(prHead === undefined).toBe(false)
  expect(runHead === undefined).toBe(false)
  expect(fail === undefined).toBe(false)
  expect((await ui.find({ type: 'Text', text: /#324/ })) === undefined).toBe(false)
  // 그린 순서: 본문 → pull requests → actions
  const texts = (await ui.findAll({ type: 'Text' })).map(t => t.text)
  const at = (re: RegExp) => texts.findIndex(t => re.test(t))
  expect(at(/flightdeck body/) < at(/pull requests/)).toBe(true)
  expect(at(/pull requests/) < at(/^actions/)).toBe(true)
  await ui.unmount()
})

test('PR 이 없어도 actions 상자만 붙는다', async ($, on) => {
  seed(on, { actionLineRuns: { shape: 'runs-4', value: [RUN] } })
  const ui = await $.ui.mount(PANE)
  expect((await ui.find({ type: 'Text', text: /pull requests/ })) === undefined).toBe(true)
  expect((await ui.find({ type: 'Text', text: /^actions/ })) === undefined).toBe(false)
  await ui.unmount()
})

test('둘 다 비면 Flightdeck 본문만 그대로', async ($, on) => {
  seed(on, {})
  const ui = await $.ui.mount(PANE)
  expect((await ui.find({ type: 'Text', text: /flightdeck body/ })) === undefined).toBe(false)
  expect((await ui.find({ type: 'Text', text: /pull requests|^actions/ })) === undefined).toBe(true)
  await ui.unmount()
})

test('옛 shape 로 저장된 실행 목록은 비어 있는 것으로 읽는다', async ($, on) => {
  seed(on, { actionLineRuns: { shape: 'runs-3', value: [RUN] } })
  const ui = await $.ui.mount(PANE)
  expect((await ui.find({ type: 'Text', text: /^actions/ })) === undefined).toBe(true)
  await ui.unmount()
})

test('#번호는 PR·실행 웹페이지 링크다', async ($, on) => {
  seed(on, {
    prLinePrs: { shape: 'prs-3', value: [PR] },
    actionLineRuns: { shape: 'runs-4', value: [RUN] },
  })
  const ui = await $.ui.mount(PANE)
  const hrefs = (await ui.findAll({ type: 'Link' })).map(l => l.props.href)
  expect(hrefs).toEqual([PR_URL, RUN_URL])
  await ui.unmount()
})

test('url 이 비면 링크 없이 번호만 그린다', async ($, on) => {
  seed(on, {
    prLinePrs: { shape: 'prs-3', value: [{ ...PR, url: '' }] },
    actionLineRuns: { shape: 'runs-4', value: [{ ...RUN, url: '' }] },
  })
  const ui = await $.ui.mount(PANE)
  expect((await ui.findAll({ type: 'Link' })).length).toBe(0)
  expect((await ui.find({ type: 'Text', text: /#324/ })) === undefined).toBe(false)
  expect((await ui.find({ type: 'Text', text: /#7/ })) === undefined).toBe(false)
  await ui.unmount()
})

test('옛 shape 로 저장된 PR 목록(url 없음)은 비어 있는 것으로 읽는다', async ($, on) => {
  seed(on, { prLinePrs: { shape: 'prs-2', value: [PR] } })
  const ui = await $.ui.mount(PANE)
  expect((await ui.find({ type: 'Text', text: /pull requests/ })) === undefined).toBe(true)
  await ui.unmount()
})
