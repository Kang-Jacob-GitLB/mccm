// where-line 의 git rev-parse 출력 파서 테스트. 실행: claude plugin test plugins/mods
import { describe, expect, test } from 'claude-code/testing'

import { absolutize, parseRevParse } from '../hooks/where-line/parse'

const out = (...lines: string[]) => lines.join('\n') + '\n'
const OLD = '--path-format=absolute' // git < 2.31 이 그대로 되돌려 주는 줄

describe('parseRevParse', () => {
  test('(a) 최신 git, 일반 저장소', () => {
    const stdout = out('main', '/home/u/repo', '/home/u/repo/.git', '/home/u/repo/.git')
    expect(parseRevParse(stdout, '/home/u/repo')).toEqual({ branch: 'main', worktree: null, repo: 'repo' })
  })

  test('(a\') 최신 git, Windows 일반 저장소(CRLF)', () => {
    const stdout = 'main\r\nC:/Users/u/repo\r\nC:/Users/u/repo/.git\r\nC:/Users/u/repo/.git\r\n'
    expect(parseRevParse(stdout, 'C:\\Users\\u\\repo')).toEqual({ branch: 'main', worktree: null, repo: 'repo' })
  })

  test('(b) 최신 git, 링크된 워크트리', () => {
    const stdout = out('feat', '/home/u/repo/.claude/worktrees/wt', '/home/u/repo/.git/worktrees/wt', '/home/u/repo/.git')
    expect(parseRevParse(stdout, '/home/u/repo/.claude/worktrees/wt')).toEqual({ branch: 'feat', worktree: 'wt', repo: 'repo' })
  })

  test('(c) git 2.17 출력, 일반 저장소 루트 (실측 샘플)', () => {
    const stdout = out(OLD, 'main', '/home3/jacob/github-litbig-runners', '.git', '.git')
    expect(parseRevParse(stdout, '/home3/jacob/github-litbig-runners')).toEqual({
      branch: 'main',
      worktree: null,
      repo: 'github-litbig-runners',
    })
  })

  test('(d) git 2.17 출력, 서브디렉터리(../.git)', () => {
    const stdout = out(OLD, 'main', '/home/u/repo', '../.git', '../.git')
    expect(parseRevParse(stdout, '/home/u/repo/src')).toEqual({ branch: 'main', worktree: null, repo: 'repo' })
  })

  test('(d\') git 2.17 출력, 깊은 서브디렉터리에서 상대·절대 혼합', () => {
    const stdout = out(OLD, 'main', '/home/u/repo', '../../.git', '/home/u/repo/.git')
    expect(parseRevParse(stdout, '/home/u/repo/a/b')).toEqual({ branch: 'main', worktree: null, repo: 'repo' })
  })

  test('(e) git 2.17 출력, 링크된 워크트리(git-dir 절대 · common-dir 상대)', () => {
    const cwd = '/home/u/repo/.claude/worktrees/wt'
    const stdout = out(OLD, 'feat', cwd, '/home/u/repo/.git/worktrees/wt', '../../../.git')
    expect(parseRevParse(stdout, cwd)).toEqual({ branch: 'feat', worktree: 'wt', repo: 'repo' })
  })

  test('(e\') git 2.17 출력, 링크된 워크트리(둘 다 절대)', () => {
    const cwd = '/home/u/repo/.claude/worktrees/wt'
    const stdout = out(OLD, 'feat', cwd, '/home/u/repo/.git/worktrees/wt', '/home/u/repo/.git')
    expect(parseRevParse(stdout, cwd)).toEqual({ branch: 'feat', worktree: 'wt', repo: 'repo' })
  })

  test('(f) detached HEAD — 최신 git', () => {
    const stdout = out('HEAD', '/home/u/repo', '/home/u/repo/.git', '/home/u/repo/.git')
    expect(parseRevParse(stdout, '/home/u/repo')).toEqual({ branch: '(detached)', worktree: null, repo: 'repo' })
  })

  test('(f\') detached HEAD — git 2.17', () => {
    const stdout = out(OLD, 'HEAD', '/home/u/repo', '.git', '.git')
    expect(parseRevParse(stdout, '/home/u/repo')).toEqual({ branch: '(detached)', worktree: null, repo: 'repo' })
  })
})

describe('absolutize', () => {
  test('절대경로는 그대로 둔다 (POSIX · Windows 드라이브)', () => {
    expect(absolutize('/a/b/.git', '/x')).toBe('/a/b/.git')
    expect(absolutize('C:/a/b/.git', 'D:/x')).toBe('C:/a/b/.git')
  })

  test('상대경로는 cwd 에 붙이고 . · .. 를 접는다', () => {
    expect(absolutize('.git', '/a/b')).toBe('/a/b/.git')
    expect(absolutize('../.git', '/a/b')).toBe('/a/.git')
    expect(absolutize('./../../.git', 'C:/a/b/c')).toBe('C:/a/.git')
  })

  test('뿌리 위로는 올라가지 않는다', () => {
    expect(absolutize('../../.git', '/a')).toBe('/.git')
    expect(absolutize('../../.git', 'C:/a')).toBe('C:/.git')
  })
})
