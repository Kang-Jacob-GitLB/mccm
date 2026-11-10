// pr-line 의 현재 세션 PR 헬퍼 테스트. 실행: claude plugin test plugins/mods
import { describe, expect, test } from 'claude-code/testing'

import type { PrLine } from '../types'
import { combine, pickGitPr, remember } from '../hooks/pr-line/session'

const URL_A = 'https://github.com/o/r/pull/12'
const URL_B = 'https://github.com/o/r/pull/13'

function line(number: number, url: string, state = 'OPEN'): PrLine {
  return { number, title: `t${number}`, branch: 'b', isDraft: false, pass: 0, fail: 0, pending: 0, current: '', merge: 'CLEAN', url, state, session: false }
}

describe('pickGitPr', () => {
  test('gitOperation.pr 의 번호와 URL 을 꺼낸다', () => {
    expect(pickGitPr({ gitOperation: { pr: { number: 12, url: URL_A, action: 'created' } } })).toEqual({ number: 12, url: URL_A })
  })
  test('URL 이 없거나 PR 주소 모양이 아니면 번호만', () => {
    expect(pickGitPr({ gitOperation: { pr: { number: 12, action: 'merged' } } })).toEqual({ number: 12, url: null })
    expect(pickGitPr({ gitOperation: { pr: { number: 12, url: '--repo x', action: 'merged' } } })).toEqual({ number: 12, url: null })
  })
  test('PR 동작이 없거나 번호가 이상하면 null', () => {
    expect(pickGitPr(undefined)).toBe(null)
    expect(pickGitPr({ stdout: 'x' })).toBe(null)
    expect(pickGitPr({ gitOperation: { commit: { sha: 'a', kind: 'committed' } } })).toBe(null)
    expect(pickGitPr({ gitOperation: { pr: { number: -1 } } })).toBe(null)
  })
})

describe('remember', () => {
  test('새 PR 을 맨 앞에 넣고 3개까지만 남긴다', () => {
    let list = remember([], { number: 1, url: null })
    list = remember(list, { number: 2, url: null })
    list = remember(list, { number: 3, url: null })
    list = remember(list, { number: 4, url: null })
    expect(list.map(r => r.number)).toEqual([4, 3, 2])
  })
  test('같은 PR 은 맨 앞으로 옮기고 몰랐던 URL 을 채운다', () => {
    const list = remember([{ number: 12, url: null }, { number: 13, url: URL_B }], { number: 12, url: URL_A })
    expect(list).toEqual([{ number: 12, url: URL_A }, { number: 13, url: URL_B }])
    expect(remember(list, { number: 13, url: null })).toEqual([{ number: 13, url: URL_B }, { number: 12, url: URL_A }])
  })
})

describe('combine', () => {
  test('세션 PR 이 맨 앞, 겹치는 열린 PR 은 한 번만', () => {
    const out = combine([line(13, URL_B, 'MERGED'), line(12, URL_A)], [line(12, URL_A), line(20, 'https://github.com/o/r/pull/20')])
    expect(out.map(p => [p.number, p.session])).toEqual([[13, true], [12, true], [20, false]])
  })
})
