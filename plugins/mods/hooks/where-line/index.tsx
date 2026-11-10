import { atom, read, update } from 'claude-code'
import type { EngineInterface, RenderNode } from 'claude-code'

import type { BranchPr, WhereLine, WhereLineBranchPr } from '../../types'
import { invalidatesPr, needsFetch, parseGhPrView } from './branch-pr'
import type { LastFetch } from './branch-pr'
import { norm, parseRevParse, revParsePrKey } from './parse'

type BandEvent = Parameters<EngineInterface['ui']['resolve']>[0]

// 입력창 위에 지금 어디서 작업 중인지 한 줄로 보여 준다.
//   📦 저장소  ·  ⎇ 브랜치  ·  🏠 main(주 체크아웃)  |  🌿 <워크트리 이름>  ·  📁 cwd  ·  #52
// #52 는 현재 브랜치의 열린 PR — 노랑, draft 면 흐리게. 머지·닫힘·PR 없음이면 표시하지 않는다.
// 저장소의 모든 PR 은 pr-line 이 보여 주므로 여기서는 지금 브랜치의 PR 하나만.
// 주 체크아웃은 노랑(워크트리에서 작업하라는 규칙을 상기), 워크트리는 초록.
// 세션 시작·턴 끝·툴 호출 직후에 git 으로 다시 읽고, 값이 바뀔 때만 다시 그린다.

const where = atom({ plugin: 'mods', key: 'whereLineWhere' } as const, null)
// version-tag 가 세션 시작에 써 두는 Claude Code 버전. 줄 맨 오른쪽에 그린다(version-tag 를 끄면 null).
// 검증기가 상태 키를 정적으로 읽으므로 import 하지 않고 같은 키로 이 파일에서 다시 만든다.
const version = atom({ plugin: 'mods', key: 'versionTagVersion' } as const, null)
// 현재 브랜치의 PR. $.state 라 리로드돼도 남고, shape 태그로 다른 모양의 옛 값은 null 로 읽는다.
const branchPr = atom({ plugin: 'mods', key: 'whereLineBranchPr' } as const, null, { shape: 'branch-pr-1' })

// Windows 에서 실행 파일을 현재 폴더(열어 둔 저장소)에서 먼저 찾지 않게 한다.
const RUN_INIT = { env: { NoDefaultCurrentDirectoryInExePath: '1' }, timeoutMs: 5_000 }
// gh 는 네트워크를 타므로 pr-line 과 같은 20초.
const GH_INIT = { env: { NoDefaultCurrentDirectoryInExePath: '1' }, timeoutMs: 20_000 }

// PR 조회 조율용 모듈 변수 — 리로드되면 처음부터(그러면 한 번 다시 조회한다).
// prKey 는 리로드 직후 undefined(아직 모름)라, 현재 키가 null 이어도 '바뀜'으로 보고 옛 PR 을 지운다.
let prKey: string | null | undefined = undefined // 지금 (toplevel, 브랜치) 키
let prCwd = '' // 마지막으로 본 cwd — gh 를 여기서 띄운다
let last: LastFetch = null // 마지막 조회. 무효화하면 null
let gen = 0 // 무효화 세대. 조회 도중 바뀌면 그 결과는 버리고 다시 읽는다
let busy = false // 동시에 gh 를 둘 띄우지 않는다
let pending = false // busy 중에 들어온 요청 — 끝나고 한 번 더 돈다
// 마지막으로 쓴 값. 이 값의 쓰기 주체는 이 모듈뿐이라 비교는 여기에 한다 —
// $.state.get 은 한 dispatch 안에서 같은 순간을 읽어, 떼어 낸 루프의 두 번째 읽기가 낡을 수 있다.
let shown: WhereLineBranchPr | null | undefined = undefined

async function writePr($: EngineInterface, next: WhereLineBranchPr | null) {
  if (shown === undefined) shown = (await read($, branchPr)) ?? null // 리로드 직후 한 번만 읽는다
  if (JSON.stringify(shown) === JSON.stringify(next)) return // 그대로면 쓰지 않는다 — 쓰기는 밴드를 다시 그린다
  shown = next
  await update($, branchPr, () => next)
}

// 인자 없는 gh pr view: 현재 브랜치의 PR. PR 이 없거나(종료코드 ≠ 0) gh 가 없거나 실패하면 null.
async function viewPr($: EngineInterface, cwd: string): Promise<BranchPr | null> {
  try {
    const r = await $.process.run(['gh', 'pr', 'view', '--json', 'number,url,state,isDraft'], { ...GH_INIT, cwd })
    return r.exitCode === 0 ? parseGhPrView(r.stdout) : null
  } catch {
    return null
  }
}

// 키가 바뀌면 옛 PR 을 바로 지우고 즉시, 같은 키면 TTL 이 지났거나 무효화됐을 때만 gh 를 띄운다.
async function syncPr($: EngineInterface, key: string | null, cwd: string) {
  // 같은 키라도 cwd 는 옮겨질 수 있다(하위 폴더 이동·삭제) — 늘 최신 cwd 에서 gh 를 띄운다.
  prCwd = cwd
  if (key !== prKey) {
    prKey = key
    // 리로드 직후처럼 이미 같은 키의 값이 있으면 그대로 두고, 아니면 응답 전까지 비우고 캐시도 버린다.
    if (key !== null) {
      if (shown === undefined) shown = (await read($, branchPr)) ?? null
      if (shown?.key !== key) {
        last = null
        await writePr($, { key, pr: null })
      }
    }
  }
  // git 아님·detached HEAD: 조회하지 않고 지운다(값이 같으면 writePr 가 쓰지 않는다).
  if (key === null) {
    await writePr($, null)
    return
  }
  if (busy) {
    pending = true // 돌고 있는 조회가 끝나면 한 번 더 돈다
    return
  }
  busy = true
  try {
    // 조회 도중 무효화되거나 키가 바뀌면 결과를 캐시하지 않고 한 번 더. 무한히 돌지 않게 3번까지.
    for (let i = 0; i < 3; i++) {
      // 시각을 먼저 얻고 키·last 를 읽는다 — await 중에 들어온 무효화·키 변경을 놓치지 않게.
      const now = await $.clock.now()
      const k: string | null | undefined = prKey
      if (k === null || k === undefined || !needsFetch(last, k, now)) break
      const g = gen
      const pr = await viewPr($, prCwd)
      const at = await $.clock.now()
      // 검사와 last 기록 사이에 await 를 두지 않는다 — 그 사이 무효화를 덮어쓰지 않게.
      if (g !== gen || k !== prKey) continue
      // PR 없음·실패도 기록해 TTL 동안 다시 띄우지 않는다.
      last = { key: k, at }
      await writePr($, { key: k, pr })
    }
  } finally {
    busy = false
    if (pending) {
      pending = false
      if (prKey !== undefined) void syncPr($, prKey, prCwd).catch(() => {})
    }
  }
}

function invalidatePr() {
  gen++
  last = null
}

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
    let key: string | null = null
    if (r.exitCode === 0) {
      next = { cwd, git: parseRevParse(r.stdout, rawCwd) }
      key = revParsePrKey(r.stdout)
    }
    // 값이 그대로면 쓰지 않는다 — 쓰기는 밴드를 다시 그린다.
    if (JSON.stringify(await read($, where)) !== JSON.stringify(next)) await update($, where, () => next)
    // gh 는 최대 20초라 기다리지 않는다 — 세션 시작·턴 끝이 gh 에 붙잡히지 않게.
    void syncPr($, key, rawCwd).catch(() => {})
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
// Bash·PowerShell 결과에 PR 동작(생성·머지 …)이 실려 있으면 PR 캐시를 버리고 다시 읽는다 — 머지 직후 바로 사라지게.
// 무효화를 refresh 보다 먼저 해야 refresh 가 신선한 캐시를 보고 건너뛰지 않는다.
export function toolCallDone($: EngineInterface, tool: string, result: unknown) {
  if (invalidatesPr(tool, result)) invalidatePr()
  void refresh($)
}

// 입력창 위 band 에 그릴 한 줄. band 훅은 mods 진입점(register.tsx)이 하나로 걸고
// 각 mod 의 줄을 모아 간격을 맞춘다 — 그릴 것이 없으면 null.
export async function abovePrompt($: EngineInterface, e: BandEvent): Promise<RenderNode | null> {
    const w = await read($, where)
    const ver = await read($, version)
    const pr = (await read($, branchPr))?.pr ?? null
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
          {/* 현재 브랜치의 열린 PR, 노랑(draft 면 흐리게) — cwd 뒤 */}
          {pr !== null && (
            <Box>
              {sep}
              <Text color="yellow" dimColor={pr.isDraft}>{`#${pr.number}`}</Text>
            </Box>
          )}
          </Box>
          {/* version-tag 가 읽어 둔 Claude Code 버전, 줄 맨 오른쪽 */}
          {ver !== null && <Text color="claude">{ver}</Text>}
        </Box>
    )
}
