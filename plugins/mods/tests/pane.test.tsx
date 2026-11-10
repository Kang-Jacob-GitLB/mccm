// Flightdeck 패널에 pr-line·action-line 상자가 붙는지 그려 본다. 실행: claude plugin test plugins/mods
import { expect, test } from 'claude-code/testing'
import type { TestBody } from 'claude-code/testing'

type On = Parameters<TestBody>[1]

const PANE = {
  plugin: 'mods',
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

const PR = { number: 7, title: 'feat: x', branch: 'feat', isDraft: false, pass: 1, fail: 0, pending: 0, current: '', merge: 'CLEAN' }
const RUN = { id: 9, workflow: 'release', branch: 'v1.2.0', event: 'push', status: 'completed', conclusion: 'failure' }

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
    prLinePrs: { shape: 'prs-2', value: [PR] },
    actionLineRuns: { shape: 'runs-1', value: [RUN] },
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
  // 그린 순서: 본문 → pull requests → actions
  const texts = (await ui.findAll({ type: 'Text' })).map(t => t.text)
  const at = (re: RegExp) => texts.findIndex(t => re.test(t))
  expect(at(/flightdeck body/) < at(/pull requests/)).toBe(true)
  expect(at(/pull requests/) < at(/^actions/)).toBe(true)
  await ui.unmount()
})

test('PR 이 없어도 actions 상자만 붙는다', async ($, on) => {
  seed(on, { actionLineRuns: { shape: 'runs-1', value: [RUN] } })
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
  seed(on, { actionLineRuns: { shape: 'runs-0', value: [RUN] } })
  const ui = await $.ui.mount(PANE)
  expect((await ui.find({ type: 'Text', text: /^actions/ })) === undefined).toBe(true)
  await ui.unmount()
})
