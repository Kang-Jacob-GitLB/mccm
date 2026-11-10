import type { ActionRun } from '../../types'
import { clean } from '../shared/clean'

// `gh run list --json …` 출력을 action-line 이 보여 줄 실행 목록으로 바꾼다.
// 프로세스·엔진에 의존하지 않는 순수 함수라 따로 테스트한다.

export const RUN_FIELDS = 'databaseId,workflowDatabaseId,workflowName,headBranch,event,status,conclusion,createdAt'
// PR 실행이 많은 저장소에서도 며칠 전 release 가 창 안에 들게 넉넉히 받는다(필드는 최소로).
export const RUN_LIMIT = 100
export const MAX_RUNS = 5

type Raw = {
  databaseId?: unknown
  workflowDatabaseId?: unknown
  workflowName?: unknown
  headBranch?: unknown
  event?: unknown
  status?: unknown
  conclusion?: unknown
  createdAt?: unknown
}

const str = (v: unknown) => (typeof v === 'string' ? v : '')

// PR 의 CI 는 pr-line 이 보여 주므로 pull_request 로 시작하는 이벤트(pull_request_target 포함)는 뺀다.
export const isPrEvent = (event: string) => event.startsWith('pull_request')

// workflow 마다 가장 최근 실행 하나만, 최근 순으로 MAX_RUNS 개. JSON 이 아니거나 배열이 아니면 null.
export function summarizeRuns(stdout: string, max = MAX_RUNS): ActionRun[] | null {
  let raw: unknown
  try {
    raw = JSON.parse(stdout)
  } catch {
    return null
  }
  if (!Array.isArray(raw)) return null
  const runs = (raw as Raw[])
    .map(r => ({
      id: typeof r.databaseId === 'number' ? r.databaseId : 0,
      workflow: clean(str(r.workflowName)),
      branch: clean(str(r.headBranch)),
      event: clean(str(r.event)),
      // 화면에 그대로 나갈 수 있는 값(모르는 conclusion 은 label 로 쓴다)이라 이것도 거른다.
      status: clean(str(r.status)).toLowerCase(),
      conclusion: clean(str(r.conclusion)).toLowerCase(),
      createdAt: str(r.createdAt),
      // 중복 제거 키: 같은 표시 이름(name: Build)을 쓰는 다른 workflow 파일도 따로 보이게 ID 로. 없으면 이름으로.
      wf: typeof r.workflowDatabaseId === 'number' ? `id:${r.workflowDatabaseId}` : `name:${clean(str(r.workflowName))}`,
    }))
    .filter(r => r.workflow !== '' && !isPrEvent(r.event))
    // ISO 8601 UTC 는 문자열 비교가 곧 시간 비교다. 같으면 id 가 큰(나중) 쪽이 앞.
    .sort((a, b) => b.createdAt.localeCompare(a.createdAt) || b.id - a.id)
  const seen = new Set<string>()
  const out: ActionRun[] = []
  for (const { createdAt: _, wf, ...r } of runs) {
    if (seen.has(wf)) continue
    seen.add(wf)
    out.push(r)
    if (out.length >= max) break
  }
  return out
}

export type RunMark = { mark: string; color: string | undefined; label: string }

// status·conclusion → 기호·색·짧은 설명. 끝나지 않았으면 status 로, 끝났으면 conclusion 으로 본다.
export function runMark(status: string, conclusion: string): RunMark {
  if (status !== 'completed') {
    if (status === 'in_progress') return { mark: '◐', color: 'yellow', label: '진행 중' }
    return { mark: '◌', color: 'yellow', label: '대기' } // queued·waiting·pending·requested
  }
  switch (conclusion) {
    case 'success':
      return { mark: '✔', color: 'green', label: '성공' }
    case 'failure':
    case 'startup_failure':
      return { mark: '✘', color: 'red', label: '실패' }
    case 'timed_out':
      return { mark: '✘', color: 'red', label: '시간 초과' }
    case 'cancelled':
      return { mark: '⊘', color: 'gray', label: '취소' }
    case 'action_required':
      return { mark: '!', color: 'yellow', label: '승인 필요' }
    case 'skipped':
      return { mark: '–', color: 'gray', label: '건너뜀' }
    default:
      return { mark: '–', color: 'gray', label: conclusion || '?' } // neutral·stale 등
  }
}
