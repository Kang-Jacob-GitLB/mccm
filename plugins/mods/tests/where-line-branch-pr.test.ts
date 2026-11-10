// where-line 의 현재 브랜치 PR 판정 테스트. 실행: claude plugin test plugins/mods
import { describe, expect, test } from 'claude-code/testing'

import { PR_TTL_MS, invalidatesPr, needsFetch, parseGhPrView, pickGitPr } from '../hooks/where-line/branch-pr'
import { revParsePrKey } from '../hooks/where-line/parse'

const URL_A = 'https://github.com/o/r/pull/12'
const view = (o: Record<string, unknown>) => JSON.stringify({ number: 12, url: URL_A, isDraft: false, ...o })

describe('parseGhPrView', () => {
  test('OPEN 이면 번호·URL·draft 를 돌려준다', () => {
    expect(parseGhPrView(view({ state: 'OPEN' }))).toEqual({ number: 12, url: URL_A, isDraft: false })
  })
  test('OPEN draft 는 isDraft true', () => {
    expect(parseGhPrView(view({ state: 'OPEN', isDraft: true }))).toEqual({ number: 12, url: URL_A, isDraft: true })
  })
  test('MERGED·CLOSED 는 표시하지 않는다', () => {
    expect(parseGhPrView(view({ state: 'MERGED' }))).toBe(null)
    expect(parseGhPrView(view({ state: 'CLOSED' }))).toBe(null)
  })
  test('JSON 이 아니거나 모양이 이상하면 null', () => {
    expect(parseGhPrView('')).toBe(null)
    expect(parseGhPrView('no pull requests found for branch "x"')).toBe(null)
    expect(parseGhPrView('null')).toBe(null)
    expect(parseGhPrView(view({ state: 'OPEN', number: 0 }))).toBe(null)
    expect(parseGhPrView(view({ state: 'OPEN', url: '--repo x' }))).toBe(null)
  })
})

describe('needsFetch', () => {
  const K = '/home/u/repo\nfeat'
  test('키가 없으면(git 아님·detached) 띄우지 않는다', () => {
    expect(needsFetch(null, null, 0)).toBe(false)
    expect(needsFetch({ key: K, at: 0 }, null, 999_999)).toBe(false)
  })
  test('처음이거나 무효화됐으면(last null) 바로', () => {
    expect(needsFetch(null, K, 0)).toBe(true)
  })
  test('키가 바뀌면 TTL 안이라도 바로', () => {
    expect(needsFetch({ key: K, at: 1000 }, '/home/u/repo\nmain', 1001)).toBe(true)
    expect(needsFetch({ key: K, at: 1000 }, '/home/u/repo/.claude/worktrees/wt\nfeat', 1001)).toBe(true)
  })
  test('같은 키는 TTL(30초) 동안 캐시, 경계에서 다시', () => {
    expect(PR_TTL_MS).toBe(30_000)
    expect(needsFetch({ key: K, at: 1000 }, K, 1000)).toBe(false)
    expect(needsFetch({ key: K, at: 1000 }, K, 1000 + PR_TTL_MS - 1)).toBe(false)
    expect(needsFetch({ key: K, at: 1000 }, K, 1000 + PR_TTL_MS)).toBe(true)
  })
})

describe('invalidatesPr', () => {
  const merged = { gitOperation: { pr: { number: 12, url: URL_A, action: 'merged' } } }
  test('Bash·PowerShell 결과에 gitOperation.pr 이 있으면 무효화', () => {
    expect(invalidatesPr('Bash', merged)).toBe(true)
    expect(invalidatesPr('PowerShell', merged)).toBe(true)
  })
  test('다른 툴이거나 PR 동작이 없으면 무효화하지 않는다', () => {
    expect(invalidatesPr('Read', merged)).toBe(false)
    expect(invalidatesPr('Bash', { stdout: 'x' })).toBe(false)
    expect(invalidatesPr('Bash', { gitOperation: { commit: { sha: 'a', kind: 'committed' } } })).toBe(false)
  })
  test('pickGitPr 는 번호가 이상하면 null', () => {
    expect(pickGitPr(undefined)).toBe(null)
    expect(pickGitPr({ gitOperation: { pr: { number: -1 } } })).toBe(null)
    expect(pickGitPr(merged)).toEqual({ number: 12 })
  })
})

describe('revParsePrKey', () => {
  const out = (...lines: string[]) => lines.join('\n') + '\n'
  test('toplevel + 브랜치', () => {
    expect(revParsePrKey(out('feat', '/home/u/repo', '/home/u/repo/.git', '/home/u/repo/.git'))).toBe('/home/u/repo\nfeat')
  })
  test('Windows CRLF·역슬래시도 같은 키', () => {
    expect(revParsePrKey('feat\r\nC:\\u\\repo\r\nC:/u/repo/.git\r\nC:/u/repo/.git\r\n')).toBe('C:/u/repo\nfeat')
  })
  test('git < 2.31 의 --path-format 줄은 버린다', () => {
    expect(revParsePrKey(out('--path-format=absolute', 'main', '/home/u/repo', '.git', '.git'))).toBe('/home/u/repo\nmain')
  })
  test('워크트리는 같은 브랜치라도 키가 다르다', () => {
    const a = revParsePrKey(out('feat', '/home/u/repo', '/home/u/repo/.git', '/home/u/repo/.git'))
    const b = revParsePrKey(out('feat', '/home/u/repo/.claude/worktrees/wt', '/home/u/repo/.git/worktrees/wt', '/home/u/repo/.git'))
    expect(a === b).toBe(false)
  })
  test('detached HEAD 나 빈 출력이면 null', () => {
    expect(revParsePrKey(out('HEAD', '/home/u/repo', '/home/u/repo/.git', '/home/u/repo/.git'))).toBe(null)
    expect(revParsePrKey('')).toBe(null)
  })
})
