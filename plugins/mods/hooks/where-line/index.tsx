import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register } from 'claude-code'

import type { WhereLine } from '../../types'

// 입력창 위에 지금 어디서 작업 중인지 한 줄로 보여 준다.
//   ⎇ 브랜치  ·  🏠 main checkout · 저장소  |  🌿 worktree <이름> · 저장소  ·  📁 cwd
// 주 체크아웃은 노랑(워크트리에서 작업하라는 규칙을 상기), 워크트리는 초록.
// 세션 시작·턴 끝·툴 호출 직후에 git 으로 다시 읽고, 값이 바뀔 때만 다시 그린다.

const where = atom({ plugin: 'mods', key: 'whereLineWhere' } as const, null)

// Windows 에서 실행 파일을 현재 폴더(열어 둔 저장소)에서 먼저 찾지 않게 한다.
const RUN_INIT = { env: { NoDefaultCurrentDirectoryInExePath: '1' }, timeoutMs: 5_000 }

const ICON = { branch: '⎇', tree: '🌿', home: '🏠', folder: '📁' }

// 경로 표기를 통일한다: 역슬래시 → 슬래시, 끝 슬래시 제거.
const norm = (p: string) => p.trim().replace(/\\/g, '/').replace(/\/+$/, '')
const base = (p: string) => p.split('/').pop() ?? p
// 홈 디렉터리는 ~ 로 줄인다 (Windows·Linux·macOS 홈 패턴).
const tilde = (p: string) => p.replace(/^([A-Za-z]:\/Users\/[^/]+|\/home\/[^/]+|\/Users\/[^/]+)/, '~')

async function refresh($: EngineInterface) {
  try {
    const cwd = tilde(norm(await $.session.cwd()))
    const r = await $.process.run(
      ['git', 'rev-parse', '--path-format=absolute', '--abbrev-ref', 'HEAD', '--show-toplevel', '--git-dir', '--git-common-dir'],
      RUN_INIT,
    )
    let next: WhereLine = { cwd, git: null }
    if (r.exitCode === 0) {
      const [head = '', top = '', gitDir = '', commonDir = ''] = r.stdout.split(/\r?\n/).map(norm)
      // 링크된 워크트리는 git-dir(.git/worktrees/<name>)이 공용 .git 과 다르다.
      const isWorktree = gitDir.toLowerCase() !== commonDir.toLowerCase()
      next = {
        cwd,
        git: {
          branch: head === 'HEAD' ? '(detached)' : head,
          worktree: isWorktree ? base(top) : null,
          repo: base(commonDir.replace(/\/\.git$/, '')),
        },
      }
    }
    // 값이 그대로면 쓰지 않는다 — 쓰기는 밴드를 다시 그린다.
    if (JSON.stringify(await read($, where)) !== JSON.stringify(next)) await update($, where, () => next)
  } catch {
    // 표시용이라 실패는 조용히 넘기고 다음 갱신에서 다시 시도한다.
  }
}

// session.start · turn.complete · tool.call 은 matcher 가 없어 mods 진입점이 한 번만 걸고 부른다.
export async function sessionStart($: EngineInterface) {
  await refresh($)
}

export async function turnComplete($: EngineInterface) {
  await refresh($)
}

// 툴 호출 직후 — 턴 도중 EnterWorktree·git switch 를 바로 반영. 툴 결과를 붙잡지 않게 기다리지 않는다.
export function toolCallDone($: EngineInterface) {
  void refresh($)
}

// matcher 가 있는 훅만 여기서 직접 건다.
export const register: Register = on => {
  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    const w = await read($, where)
    const below = await next(e)
    if (w === null || e.props.hasSurvey) return below

    const { Box, Text } = $.ui.resolve(e)
    const sep = <Text dimColor>{'  ·  '}</Text>

    return (
      <Box flexDirection="column">
        {below}
        <Box>
          {w.git === null ? (
            <Text color="subtle">git 아님</Text>
          ) : (
            <Box>
              <Text color="suggestion" bold>{`${ICON.branch} ${w.git.branch}`}</Text>
              {sep}
              {w.git.worktree === null ? (
                <Text color="warning">{`${ICON.home} main checkout · ${w.git.repo}`}</Text>
              ) : (
                <Text color="success">{`${ICON.tree} worktree ${w.git.worktree} · ${w.git.repo}`}</Text>
              )}
            </Box>
          )}
          {sep}
          <Text color="subtle">{`${ICON.folder} ${w.cwd}`}</Text>
        </Box>
      </Box>
    )
  })
}
