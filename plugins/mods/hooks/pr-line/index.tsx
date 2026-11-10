import { atom, read, update } from 'claude-code'
import type { EngineInterface, RenderNode, Timer } from 'claude-code'

import type { PrLine } from '../../types'
import { clean } from '../shared/clean'
import { isPaneShown } from '../shared/pane'

// 내가 연 열린 PR(최대 5개)의 제목과 CI 상태를 한 줄씩 보여 준다.
// 1) Flightdeck 패널(requestId 'flightdeck') 맨 아래에 "pull requests" 상자로 붙이고,
// 2) 그 패널에 붙어 있지 않으면 입력창 위에 같은 목록을 보여 준다.
// 순서: 현재 브랜치의 PR 이 맨 앞, 나머지는 최근 갱신 순. 15초마다와 턴이 끝날 때 gh 로 다시 읽는다.
// 패널 훅은 mods 진입점(register.tsx)이 하나로 걸어 action-line 상자와 순서를 맞춘다.

const POLL_MS = 15_000

// 상태는 mods 플러그인 이름 아래에 둔다. 키에 mod 이름을 붙여 다른 mod 와 겹치지 않게.
const prs = atom({ plugin: 'mods', key: 'prLinePrs' } as const, [], { shape: 'prs-2' })
const MAX_PRS = 5

let poll: Timer | undefined
let busy = false

type Check = { __typename?: string; name?: string; context?: string; status?: string; conclusion?: string | null; state?: string }
type Raw = {
  number: number
  title: string
  headRefName: string
  isDraft: boolean
  statusCheckRollup?: Check[]
  mergeStateStatus: string
  updatedAt?: string
}

// Windows 에서 실행 파일을 현재 폴더(열어 둔 저장소)에서 먼저 찾지 않게 한다.
const RUN_INIT = { env: { NoDefaultCurrentDirectoryInExePath: '1' }, timeoutMs: 20_000 }

const FIELDS = 'number,title,headRefName,isDraft,statusCheckRollup,mergeStateStatus,updatedAt'

async function gh($: EngineInterface, args: string[]): Promise<string | undefined> {
  try {
    const r = await $.process.run(['gh', ...args], RUN_INIT)
    return r.exitCode === 0 ? r.stdout : undefined
  } catch {
    return undefined
  }
}

async function currentBranch($: EngineInterface): Promise<string | undefined> {
  try {
    const r = await $.process.run(['git', 'branch', '--show-current'], RUN_INIT)
    return r.exitCode === 0 ? r.stdout.trim() : undefined
  } catch {
    return undefined
  }
}

async function findPrs($: EngineInterface): Promise<Raw[]> {
  const list = await gh($, ['pr', 'list', '--author', '@me', '--state', 'open', '--limit', String(MAX_PRS), '--json', FIELDS])
  if (!list) return []
  const all = JSON.parse(list) as Raw[]
  const branch = await currentBranch($)
  all.sort((a, b) => {
    if (a.headRefName === branch) return -1
    if (b.headRefName === branch) return 1
    return (b.updatedAt ?? '').localeCompare(a.updatedAt ?? '')
  })
  return all.slice(0, MAX_PRS)
}

function summarize(raw: Raw): PrLine {
  let pass = 0
  let fail = 0
  let pending = 0
  let current = ''
  let failed = ''
  for (const c of raw.statusCheckRollup ?? []) {
    const name = c.name ?? c.context ?? '?'
    // CheckRun: status/conclusion, StatusContext: state
    const state = c.__typename === 'StatusContext' ? (c.state ?? '') : c.status === 'COMPLETED' ? (c.conclusion ?? '') : 'PENDING'
    if (state === 'SUCCESS' || state === 'SKIPPED' || state === 'NEUTRAL') pass++
    else if (state === 'PENDING' || state === 'EXPECTED' || state === 'QUEUED' || state === 'IN_PROGRESS') {
      pending++
      if (!current) current = name
    } else {
      fail++
      if (!failed) failed = name
    }
  }
  return {
    number: raw.number,
    title: clean(raw.title),
    branch: clean(raw.headRefName),
    isDraft: raw.isDraft,
    pass,
    fail,
    pending,
    current: clean(current || failed),
    merge: /^[A-Z_]+$/.test(raw.mergeStateStatus) ? raw.mergeStateStatus : 'UNKNOWN',
  }
}

async function refresh($: EngineInterface) {
  if (busy) return
  busy = true
  try {
    const next = (await findPrs($)).map(summarize)
    const prev = await read($, prs)
    // 바뀐 게 없으면 쓰지 않는다(쓸 때마다 패널이 다시 그려진다).
    if (JSON.stringify(prev) !== JSON.stringify(next)) await update($, prs, () => next)
  } catch {
    // gh 가 없거나 인증·네트워크 실패: 다음 주기에 다시 본다.
  } finally {
    busy = false
  }
}

const MERGE_TEXT: Record<string, [string, string | undefined]> = {
  CLEAN: ['머지 가능', 'green'],
  HAS_HOOKS: ['머지 가능', 'green'],
  UNSTABLE: ['머지 가능(실패 check)', 'yellow'],
  BLOCKED: ['차단', 'red'],
  BEHIND: ['base 뒤처짐', 'yellow'],
  DIRTY: ['충돌', 'red'],
  DRAFT: ['draft', undefined],
  UNKNOWN: ['계산 중', undefined],
}

// session log 처럼 상자 하나에 PR 한 줄씩: 왼쪽 "#번호 제목…", 오른쪽 CI 기호와 통과 수.
function prBox($: EngineInterface, e: Parameters<EngineInterface['ui']['resolve']>[0], list: PrLine[]): RenderNode {
  const { Box, Text } = $.ui.resolve(e)
  return (
    <Box flexDirection="column" borderStyle="round" borderDimColor paddingX={1}>
      <Text dimColor>pull requests · {list.length} open</Text>
      {list.map(p => {
        const total = p.pass + p.fail + p.pending
        const ciMark = total === 0 ? '–' : p.pending > 0 ? '◐' : p.fail > 0 ? '✘' : '✔'
        const ciColor = total === 0 ? undefined : p.pending > 0 ? 'yellow' : p.fail > 0 ? 'red' : 'green'
        return (
          <Box>
            <Box flexGrow={1} flexShrink={1} minWidth={0}>
              <Text wrap="truncate-end">
                {/* #번호는 늘 노랑. 제목·숫자는 draft 면 회색, 아니면 흰색 */}
                <Text color="yellow">#{p.number}</Text>
                <Text color={p.isDraft ? 'gray' : 'white'}> {p.title}</Text>
              </Text>
            </Box>
            <Box flexShrink={0} marginLeft={2}>
              <Text color={ciColor}>{ciMark}</Text>
              <Text color={p.isDraft ? 'gray' : 'white'}> {total === 0 ? '–' : `${p.pass}/${total}`}</Text>
            </Box>
          </Box>
        )
      })}
    </Box>
  )
}

function line($: EngineInterface, e: Parameters<EngineInterface['ui']['resolve']>[0], p: PrLine): RenderNode {
  const { Box, Text } = $.ui.resolve(e)
  const total = p.pass + p.fail + p.pending
  const ciMark = total === 0 ? '–' : p.pending > 0 ? '◐' : p.fail > 0 ? '✘' : '✔'
  const ciColor = total === 0 ? undefined : p.pending > 0 ? 'yellow' : p.fail > 0 ? 'red' : 'green'
  const ciText = total === 0 ? 'check 없음' : `${p.pass}/${total}${p.current ? ` ${p.current}` : ''}`
  const [mergeText, mergeColor] = MERGE_TEXT[p.merge] ?? [p.merge.toLowerCase(), undefined]
  return (
    <Box>
      <Box flexGrow={1} flexShrink={1} minWidth={0}>
        <Text wrap="truncate-end">
          <Text bold>#{p.number}</Text> {p.title}
        </Text>
      </Box>
      <Box flexShrink={0} marginLeft={1}>
        <Text color={ciColor}>CI {ciMark} </Text>
        <Text>{ciText}</Text>
        <Text dimColor> · </Text>
        <Text color={mergeColor}>{mergeText}</Text>
      </Box>
    </Box>
  )
}

// 세션 시작: 15초 주기 갱신을 건다. (session.start 는 mods 진입점이 한 번만 걸고 이 함수를 부른다)
export async function sessionStart($: EngineInterface) {
  poll?.cancel()
  poll = $.clock.every(POLL_MS, () => {
    void refresh($)
  })
  void refresh($)
}

// 턴 끝: 바로 한 번 더 읽는다. (turn.complete 도 진입점이 한 번만 건다)
export async function turnComplete($: EngineInterface) {
  void refresh($)
}

// 1) Flightdeck 패널 맨 아래에 붙일 PR 목록 상자(한 PR 한 줄). 패널 훅은 진입점이 걸고 이 상자를 모은다.
// 열린 PR 이 없으면 null.
export async function paneBox(
  $: EngineInterface,
  e: Parameters<EngineInterface['ui']['resolve']>[0],
): Promise<RenderNode | null> {
  const list = await read($, prs)
  return list.length === 0 ? null : prBox($, e, list)
}

// 2) Flightdeck 패널에 붙어 있지 않을 때만 입력창 위 band 에 PR 한 줄씩 보여 준다.
// band 훅은 mods 진입점(register.tsx)이 하나로 걸고 각 mod 의 줄을 모은다 — 그릴 것이 없으면 null.
export async function abovePrompt(
  $: EngineInterface,
  e: Parameters<EngineInterface['ui']['resolve']>[0],
): Promise<RenderNode | null> {
  const list = await read($, prs)
  if (list.length === 0 || isPaneShown()) return null
  const { Box } = $.ui.resolve(e)
  return <Box flexDirection="column">{list.map(p => line($, e, p))}</Box>
}
