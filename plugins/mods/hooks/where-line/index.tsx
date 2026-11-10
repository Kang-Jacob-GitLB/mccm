import { atom, read, update } from 'claude-code'
import type { EngineInterface, RenderNode } from 'claude-code'

import type { SessionPr, WhereLine } from '../../types'
import { norm, parseRevParse } from './parse'
import { pickGitPr, remember } from './session-pr'

type BandEvent = Parameters<EngineInterface['ui']['resolve']>[0]

// 입력창 위에 지금 어디서 작업 중인지 한 줄로 보여 준다.
//   📦 저장소  ·  ⎇ 브랜치  ·  🏠 main(주 체크아웃)  |  🌿 <워크트리 이름>  ·  📁 cwd  ·  #52
// #52 는 현재 세션의 PR(이 세션에서 만들거나 머지·코멘트·수정한 PR, 최근 것이 앞) — 노랑.
// 주 체크아웃은 노랑(워크트리에서 작업하라는 규칙을 상기), 워크트리는 초록.
// 세션 시작·턴 끝·툴 호출 직후에 git 으로 다시 읽고, 값이 바뀔 때만 다시 그린다.

const where = atom({ plugin: 'mods', key: 'whereLineWhere' } as const, null)
// version-tag 가 세션 시작에 써 두는 Claude Code 버전. 줄 맨 오른쪽에 그린다(version-tag 를 끄면 null).
// 검증기가 상태 키를 정적으로 읽으므로 import 하지 않고 같은 키로 이 파일에서 다시 만든다.
const version = atom({ plugin: 'mods', key: 'versionTagVersion' } as const, null)
// 현재 세션의 PR. $.state 라 리로드돼도 세션 동안 남는다.
const sessionPrs = atom({ plugin: 'mods', key: 'whereLineSessionPrs' } as const, [] as SessionPr[])

// Windows 에서 실행 파일을 현재 폴더(열어 둔 저장소)에서 먼저 찾지 않게 한다.
const RUN_INIT = { env: { NoDefaultCurrentDirectoryInExePath: '1' }, timeoutMs: 5_000 }

const ICON = { repo: '📦', branch: '⎇', tree: '🌿', home: '🏠', folder: '📁' }
// 📦 상자 이모지의 황갈색에 맞춘 저장소 이름 색
const REPO_COLOR = '#D4A373'

// 홈 디렉터리는 ~ 로 줄인다 (Windows·Linux·macOS 홈 패턴).
const tilde = (p: string) => p.replace(/^([A-Za-z]:\/Users\/[^/]+|\/home\/[^/]+|\/Users\/[^/]+)/, '~')

async function refresh($: EngineInterface) {
  try {
    // git < 2.31 의 상대경로 출력은 tilde() 전 원본 cwd 기준으로 절대경로화한다.
    const rawCwd = norm(await $.session.cwd())
    const cwd = tilde(rawCwd)
    const r = await $.process.run(
      ['git', 'rev-parse', '--path-format=absolute', '--abbrev-ref', 'HEAD', '--show-toplevel', '--git-dir', '--git-common-dir'],
      RUN_INIT,
    )
    let next: WhereLine = { cwd, git: null }
    if (r.exitCode === 0) next = { cwd, git: parseRevParse(r.stdout, rawCwd) }
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
// Bash·PowerShell 결과에 PR 동작(생성·머지·코멘트·수정 …)이 실려 있으면 현재 세션의 PR 로 기억한다.
export function toolCallDone($: EngineInterface, tool: string, result: unknown) {
  void refresh($)
  if (tool !== 'Bash' && tool !== 'PowerShell') return
  const pr = pickGitPr(result)
  if (pr) void update($, sessionPrs, list => remember(list ?? [], pr)).catch(() => {})
}

// 입력창 위 band 에 그릴 한 줄. band 훅은 mods 진입점(register.tsx)이 하나로 걸고
// 각 mod 의 줄을 모아 간격을 맞춘다 — 그릴 것이 없으면 null.
export async function abovePrompt($: EngineInterface, e: BandEvent): Promise<RenderNode | null> {
    const w = await read($, where)
    const ver = await read($, version)
    const prs = await read($, sessionPrs)
    if (w === null) return null

    const { Box, Text } = $.ui.resolve(e)
    const sep = <Text dimColor>{'  ·  '}</Text>

    return (
        <Box justifyContent="space-between">
          <Box>
          {w.git === null ? (
            <Text color="subtle">git 아님</Text>
          ) : (
            <Box>
              {/* 저장소 이름은 맨 앞, 📦 상자와 비슷한 황갈색 */}
              <Text color={REPO_COLOR} bold>{`${ICON.repo} ${w.git.repo}`}</Text>
              {sep}
              <Text color="suggestion" bold>{`${ICON.branch} ${w.git.branch}`}</Text>
              {sep}
              {w.git.worktree === null ? (
                <Text color="warning">{`${ICON.home} main`}</Text>
              ) : (
                <Text color="success">{`${ICON.tree} ${w.git.worktree}`}</Text>
              )}
            </Box>
          )}
          {sep}
          <Text color="subtle">{`${ICON.folder} ${w.cwd}`}</Text>
          {/* 현재 세션의 PR, 노랑 — cwd 뒤 */}
          {prs.length > 0 && (
            <Box>
              {sep}
              <Text color="yellow">{prs.map(p => `#${p.number}`).join(' ')}</Text>
            </Box>
          )}
          </Box>
          {/* version-tag 가 읽어 둔 Claude Code 버전, 줄 맨 오른쪽 */}
          {ver !== null && <Text color="claude">{ver}</Text>}
        </Box>
    )
}
