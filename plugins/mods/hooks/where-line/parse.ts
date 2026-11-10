import type { WhereLine } from '../../types'

// `git rev-parse --path-format=absolute --abbrev-ref HEAD --show-toplevel --git-dir --git-common-dir`
// 의 출력을 where-line 의 git 칸으로 바꾼다. 프로세스·엔진에 의존하지 않는 순수 함수라 따로 테스트한다.
//
// git < 2.31 은 --path-format 을 모르는데, rev-parse 는 모르는 옵션을 오류 없이 그대로 한 줄 출력하고
// 종료 코드도 0 이다. 그래서 첫 줄이 --path-format 이면 버린다(버전 확인용 프로세스를 더 띄우지 않는다).
// 이때 --git-dir · --git-common-dir 는 cwd 기준 상대경로(.git, ../.git)일 수 있어 cwd 로 절대경로화한다.

// 경로 표기를 통일한다: 역슬래시 → 슬래시, 끝 슬래시 제거.
export const norm = (p: string) => p.trim().replace(/\\/g, '/').replace(/\/+$/, '')
const base = (p: string) => p.split('/').pop() ?? p

// 절대경로의 뿌리: POSIX '/', Windows 드라이브 'C:/'. 없으면 상대경로.
const ROOT = /^(\/|[A-Za-z]:\/)/

// 상대경로면 cwd 에 붙이고, '.'·'..' 를 접어 정규화한다. 뿌리 위로는 올라가지 않는다.
export function absolutize(p: string, cwd: string): string {
  const joined = ROOT.test(p) ? p : `${cwd}/${p}`
  const root = joined.match(ROOT)?.[0] ?? ''
  const parts: string[] = []
  for (const seg of joined.slice(root.length).split('/')) {
    if (seg === '' || seg === '.') continue
    if (seg === '..') parts.pop()
    else parts.push(seg)
  }
  return root + parts.join('/')
}

export function parseRevParse(stdout: string, cwd: string): NonNullable<WhereLine['git']> {
  const lines = stdout.split(/\r?\n/).map(norm)
  if (lines[0]?.startsWith('--path-format')) lines.shift()
  const [head = '', top = '', rawGitDir = '', rawCommonDir = ''] = lines
  const root = norm(cwd)
  const gitDir = absolutize(rawGitDir, root)
  const commonDir = absolutize(rawCommonDir, root)
  // 링크된 워크트리는 git-dir(.git/worktrees/<name>)이 공용 .git 과 다르다.
  const isWorktree = gitDir.toLowerCase() !== commonDir.toLowerCase()
  return {
    branch: head === 'HEAD' ? '(detached)' : head,
    worktree: isWorktree ? base(top) : null,
    repo: base(commonDir.replace(/\/\.git$/, '')),
  }
}
