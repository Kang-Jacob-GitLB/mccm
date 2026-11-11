import { atom, read, update } from 'claude-code'
import type { EngineInterface, RenderNode, Timer } from 'claude-code'

import type { ActionRun } from '../../types'
import { isPaneShown } from '../shared/pane'
import { RUN_FIELDS, RUN_LIMIT, runMark, summarizeRuns } from './runs'

type PaneEvent = Parameters<EngineInterface['ui']['resolve']>[0]

// 현재 저장소의 GitHub Actions 실행(PR 실행 포함)을 workflow 마다 가장 최근 것 하나씩(최대 3개),
// 실행 번호(#324)·상태 기호와 함께 보여 준다. 순서는 GitHub Actions 목록과 같은 생성 시각 최근 순.
// 1) Flightdeck 패널 맨 아래, pr-line 의 "pull requests" 상자 밑에 "actions" 상자로 붙이고,
// 2) 그 패널에 붙어 있지 않으면 입력창 위에 같은 목록을 보여 준다.
// 30초마다와 턴이 끝날 때 `gh run list` 로 읽기만 한다.

const POLL_MS = 30_000

const runs = atom({ plugin: 'mods', key: 'actionLineRuns' } as const, [], { shape: 'runs-2' })

let poll: Timer | undefined
let busy = false

// Windows 에서 실행 파일을 현재 폴더(열어 둔 저장소)에서 먼저 찾지 않게 한다. timeout 은 pr-line 과 같다.
const RUN_INIT = { env: { NoDefaultCurrentDirectoryInExePath: '1' }, timeoutMs: 20_000 }

async function refresh($: EngineInterface) {
  if (busy) return
  busy = true
  try {
    const r = await $.process.run(['gh', 'run', 'list', '--limit', String(RUN_LIMIT), '--json', RUN_FIELDS], RUN_INIT)
    // gh 실패(저장소 아님·인증 없음)는 빈 목록, 출력이 잘렸거나 JSON 이 깨졌으면 이번 회차는 버린다.
    const next = r.exitCode !== 0 ? [] : r.isStdoutTruncated ? null : summarizeRuns(r.stdout)
    if (next === null) return
    // 바뀐 게 없으면 쓰지 않는다(쓸 때마다 패널이 다시 그려진다).
    if (JSON.stringify(await read($, runs)) !== JSON.stringify(next)) await update($, runs, () => next)
  } catch {
    // gh 가 없거나 시간 초과: 다음 주기에 다시 본다.
  } finally {
    busy = false
  }
}

function row($: EngineInterface, e: PaneEvent, r: ActionRun): RenderNode {
  const { Box, Text } = $.ui.resolve(e)
  const m = runMark(r.status, r.conclusion)
  return (
    <Box>
      <Box flexGrow={1} flexShrink={1} minWidth={0}>
        <Text wrap="truncate-end">
          <Text color="white">{r.workflow}</Text>
          {r.number > 0 ? <Text color="yellow">{` #${r.number}`}</Text> : null}
          <Text color="gray">{` ${r.branch} · ${r.event}`}</Text>
        </Text>
      </Box>
      <Box flexShrink={0} marginLeft={2}>
        <Text color={m.color}>{`${m.mark} ${m.label}`}</Text>
      </Box>
    </Box>
  )
}

// 1) Flightdeck 패널 맨 아래에 붙일 상자. 패널 훅은 진입점이 걸고 pr-line 상자 밑에 놓는다. 실행이 없으면 null.
export async function paneBox($: EngineInterface, e: PaneEvent): Promise<RenderNode | null> {
  const list = await read($, runs)
  if (list.length === 0) return null
  const { Box, Text } = $.ui.resolve(e)
  return (
    <Box flexDirection="column" borderStyle="round" borderDimColor paddingX={1}>
      <Text dimColor>actions · 최근 {list.length} workflow</Text>
      {list.map(r => row($, e, r))}
    </Box>
  )
}

// 2) Flightdeck 패널에 붙어 있지 않을 때만 입력창 위 band 에 한 줄씩. 그릴 것이 없으면 null.
export async function abovePrompt($: EngineInterface, e: PaneEvent): Promise<RenderNode | null> {
  const list = await read($, runs)
  if (list.length === 0 || isPaneShown()) return null
  const { Box } = $.ui.resolve(e)
  return <Box flexDirection="column">{list.map(r => row($, e, r))}</Box>
}

// 세션 시작: 30초 주기 갱신을 건다. 리로드로 다시 불려도 겹치지 않게 옛 타이머를 끈다.
export async function sessionStart($: EngineInterface) {
  poll?.cancel()
  poll = $.clock.every(POLL_MS, () => {
    void refresh($)
  })
  void refresh($)
}

// 턴 끝: 바로 한 번 더 읽는다(방금 태그를 push 했으면 release 실행이 곧 뜬다).
export async function turnComplete($: EngineInterface) {
  void refresh($)
}
