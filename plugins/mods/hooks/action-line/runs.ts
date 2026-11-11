import type { ActionRun } from '../../types'
import { clean } from '../shared/clean'

// `gh run list --json …` 출력을 action-line 이 보여 줄 실행 목록으로 바꾼다.
// 프로세스·엔진에 의존하지 않는 순수 함수라 따로 테스트한다.

export const RUN_FIELDS = 'databaseId,number,workflowDatabaseId,workflowName,headBranch,event,status,conclusion,createdAt,updatedAt'
// 실행이 드문 workflow(며칠 전 release 등)도 창 안에 들게 넉넉히 받는다(필드는 최소로).
export const RUN_LIMIT = 100
export const MAX_RUNS = 3

type Raw = {
  databaseId?: unknown
  number?: unknown
  workflowDatabaseId?: unknown
  workflowName?: unknown
  headBranch?: unknown
  event?: unknown
  status?: unknown
  conclusion?: unknown
  createdAt?: unknown
  updatedAt?: unknown
}

const str = (v: unknown) => (typeof v === 'string' ? v : '')

// PR 실행까지 포함해 workflow 마다 가장 최근 실행 하나만, 최근 순으로 MAX_RUNS 개(GitHub Actions 목록과 같은 순서). JSON 이 아니거나 배열이 아니면 null.
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
      // workflow 안의 실행 번호(GitHub 화면의 #324). 없으면 0 — 화면에 # 를 붙이지 않는다.
      number: typeof r.number === 'number' ? r.number : 0,
      workflow: clean(str(r.workflowName)),
      branch: clean(str(r.headBranch)),
      event: clean(str(r.event)),
      // 화면에 그대로 나갈 수 있는 값(모르는 conclusion 은 label 로 쓴다)이라 이것도 거른다.
      status: clean(str(r.status)).toLowerCase(),
      conclusion: clean(str(r.conclusion)).toLowerCase(),
      createdAt: str(r.createdAt),
      // gh run list 에는 completedAt 이 없다. 끝난 실행은 그 뒤로 바뀌지 않으니 updatedAt 을 완료 시각으로 쓴다.
      finishedAt: clean(str(r.status)).toLowerCase() === 'completed' ? str(r.updatedAt) : '',
      // 중복 제거 키: 같은 표시 이름(name: Build)을 쓰는 다른 workflow 파일도 따로 보이게 ID 로. 없으면 이름으로.
      wf: typeof r.workflowDatabaseId === 'number' ? `id:${r.workflowDatabaseId}` : `name:${clean(str(r.workflowName))}`,
    }))
    .filter(r => r.workflow !== '')
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

const pad = (n: number) => String(n).padStart(2, '0')

// 완료 시각(ISO 8601) → 로컬 시간 표시. 오늘이면 "18:30", 아니면 "11/9 18:30". 비었거나 못 읽으면 빈 문자열.
export function finishedLabel(iso: string, now: Date = new Date()): string {
  if (iso === '') return ''
  const d = new Date(iso)
  if (Number.isNaN(d.getTime())) return ''
  const hm = `${pad(d.getHours())}:${pad(d.getMinutes())}`
  const today = d.getFullYear() === now.getFullYear() && d.getMonth() === now.getMonth() && d.getDate() === now.getDate()
  return today ? hm : `${d.getMonth() + 1}/${d.getDate()} ${hm}`
}
