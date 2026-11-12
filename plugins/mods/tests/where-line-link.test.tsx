// where-line 의 현재 브랜치 PR #번호가 PR 웹페이지 링크로 그려지는지 본다. 실행: claude plugin test plugins/mods
import { expect, test } from 'claude-code/testing'
import type { TestBody } from 'claude-code/testing'

type On = Parameters<TestBody>[1]

const BAND = {
  plugin: 'mods',
  component: 'AbovePrompt',
  surface: 'terminal',
  props: { hasSurvey: false, isCollapsed: false, isWorking: false, maxRows: 10, bodyColumns: 120, scroll: { offset: 0, bodyRows: 10 }, view: {} },
} as const

const URL = 'https://github.com/o/r/pull/52'
const WHERE = { cwd: '~/x', git: { branch: 'feat', worktree: 'wt', repo: 'r' } }

function seed(on: On, values: Record<string, unknown>) {
  on('state.get', (_, e) => {
    const key: string = e.key
    return { value: key in values ? { value: values[key], version: 1 } : { value: undefined, version: 0 } }
  })
  on('clock.now', () => ({ value: 1_000 }))
}

test('현재 브랜치 PR #번호는 PR 웹페이지 링크다', async ($, on) => {
  seed(on, {
    whereLineWhere: WHERE,
    whereLineBranchPr: { shape: 'branch-pr-1', value: { key: 'k', pr: { number: 52, url: URL, isDraft: false } } },
  })
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const ui = await $.ui.mount(BAND as any)
  const hrefs = (await ui.findAll({ type: 'Link' })).map(l => l.props.href)
  expect(hrefs).toEqual([URL])
  expect((await ui.find({ type: 'Text', text: /#52/ })) === undefined).toBe(false)
  await ui.unmount()
})

test('PR 이 없으면 링크도 없다', async ($, on) => {
  seed(on, { whereLineWhere: WHERE, whereLineBranchPr: { shape: 'branch-pr-1', value: { key: 'k', pr: null } } })
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const ui = await $.ui.mount(BAND as any)
  expect((await ui.findAll({ type: 'Link' })).length).toBe(0)
  await ui.unmount()
})
