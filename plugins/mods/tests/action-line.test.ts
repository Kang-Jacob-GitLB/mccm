// action-line 의 gh run list 판정 테스트. 실행: claude plugin test plugins/mods
import { describe, expect, test } from 'claude-code/testing'

import { isPrEvent, runMark, summarizeRuns } from '../hooks/action-line/runs'

type R = { databaseId: number; workflowName: string; headBranch: string; event: string; status: string; conclusion: string; createdAt: string }
const run = (o: Partial<R>): R => ({
  databaseId: 1,
  workflowName: 'release',
  headBranch: 'main',
  event: 'push',
  status: 'completed',
  conclusion: 'success',
  createdAt: '2026-11-10T08:00:00Z',
  ...o,
})
const list = (...rs: R[]) => JSON.stringify(rs)

describe('summarizeRuns', () => {
  test('PR 이벤트(pull_request·pull_request_target)는 뺀다', () => {
    const out = summarizeRuns(
      list(
        run({ databaseId: 3, workflowName: 'build', event: 'pull_request', createdAt: '2026-11-10T09:00:00Z' }),
        run({ databaseId: 2, workflowName: 'label', event: 'pull_request_target', createdAt: '2026-11-10T08:30:00Z' }),
        run({ databaseId: 1, workflowName: 'release', event: 'push' }),
      ),
    )
    expect(out?.map(r => r.workflow)).toEqual(['release'])
  })

  test('workflow 마다 가장 최근 실행 하나만, 최근 순', () => {
    const out = summarizeRuns(
      list(
        run({ databaseId: 1, workflowName: 'nightly', event: 'schedule', conclusion: 'failure', createdAt: '2026-11-09T00:00:00Z' }),
        run({ databaseId: 5, workflowName: 'nightly', event: 'schedule', conclusion: 'success', createdAt: '2026-11-10T00:00:00Z' }),
        run({ databaseId: 4, workflowName: 'release', headBranch: 'v1.2.0', createdAt: '2026-11-10T05:00:00Z' }),
      ),
    )
    expect(out).toEqual([
      { id: 4, workflow: 'release', branch: 'v1.2.0', event: 'push', status: 'completed', conclusion: 'success' },
      { id: 5, workflow: 'nightly', branch: 'main', event: 'schedule', status: 'completed', conclusion: 'success' },
    ])
  })

  test('표시 이름이 같아도 workflow ID 가 다르면 따로 보인다', () => {
    const out = summarizeRuns(
      JSON.stringify([
        { ...run({ databaseId: 2, workflowName: 'Build', conclusion: 'success', createdAt: '2026-11-10T02:00:00Z' }), workflowDatabaseId: 100 },
        { ...run({ databaseId: 1, workflowName: 'Build', conclusion: 'failure', createdAt: '2026-11-10T01:00:00Z' }), workflowDatabaseId: 200 },
        { ...run({ databaseId: 0, workflowName: 'Build', conclusion: 'failure', createdAt: '2026-11-10T00:00:00Z' }), workflowDatabaseId: 100 },
      ]),
    )
    expect(out?.map(r => r.conclusion)).toEqual(['success', 'failure'])
  })

  test('최대 개수에서 자른다', () => {
    const rs = [1, 2, 3, 4, 5, 6, 7].map(i => run({ databaseId: i, workflowName: `w${i}`, createdAt: `2026-11-10T0${i}:00:00Z` }))
    expect(summarizeRuns(list(...rs))?.map(r => r.workflow)).toEqual(['w7', 'w6', 'w5', 'w4', 'w3'])
    expect(summarizeRuns(list(...rs), 2)?.length).toBe(2)
  })

  test('진행 중이면 conclusion 이 빈 문자열, 대소문자는 소문자로', () => {
    const out = summarizeRuns(list(run({ status: 'IN_PROGRESS', conclusion: '' })))
    expect(out?.[0]?.status).toBe('in_progress')
    expect(out?.[0]?.conclusion).toBe('')
  })

  test('GitHub 글자에서 제어 문자를 지운다', () => {
    const out = summarizeRuns(list(run({ workflowName: 'rel' + String.fromCharCode(0x1b) + '[31mease', headBranch: 'ma' + String.fromCharCode(0x202e) + 'in' })))
    expect(out?.[0]?.workflow).toBe('rel[31mease')
    expect(out?.[0]?.branch).toBe('main')
    // 모르는 conclusion 은 label 로 화면에 나가므로 이것도 거른다
    const odd = summarizeRuns(list(run({ conclusion: 'we' + String.fromCharCode(0x1b) + 'ird' })))
    expect(odd?.[0]?.conclusion).toBe('weird')
  })

  test('빈 목록은 빈 배열, JSON 이 아니거나 배열이 아니면 null', () => {
    expect(summarizeRuns('[]')).toEqual([])
    expect(summarizeRuns('')).toBe(null)
    expect(summarizeRuns('{"a":1}')).toBe(null)
  })
})

describe('isPrEvent', () => {
  test('pull_request 로 시작하면 PR 이벤트', () => {
    expect(isPrEvent('pull_request')).toBe(true)
    expect(isPrEvent('pull_request_target')).toBe(true)
    expect(isPrEvent('push')).toBe(false)
    expect(isPrEvent('release')).toBe(false)
  })
})

describe('runMark', () => {
  test('끝나기 전: 진행 중 ◐ / 대기 ◌', () => {
    expect(runMark('in_progress', '')).toEqual({ mark: '◐', color: 'yellow', label: '진행 중' })
    expect(runMark('queued', '').label).toBe('대기')
    expect(runMark('waiting', '').label).toBe('대기')
  })
  test('끝난 뒤: conclusion 으로', () => {
    expect(runMark('completed', 'success')).toEqual({ mark: '✔', color: 'green', label: '성공' })
    expect(runMark('completed', 'failure').mark).toBe('✘')
    expect(runMark('completed', 'startup_failure').label).toBe('실패')
    expect(runMark('completed', 'timed_out')).toEqual({ mark: '✘', color: 'red', label: '시간 초과' })
    expect(runMark('completed', 'cancelled').label).toBe('취소')
    expect(runMark('completed', 'skipped').label).toBe('건너뜀')
    expect(runMark('completed', 'action_required').label).toBe('승인 필요')
    expect(runMark('completed', 'neutral').label).toBe('neutral')
  })
})
