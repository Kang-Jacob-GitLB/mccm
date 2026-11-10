import type { BranchPr } from '../../types'

// 현재 브랜치의 PR — `gh pr view --json number,url,state,isDraft` 를 인자 없이 세션 cwd 에서 돌려 얻는다.
// 프로세스·엔진에 의존하지 않는 판정만 여기 두고 따로 테스트한다. 조회 자체는 index.tsx 가 한다.

// 같은 (toplevel, 브랜치) 에서 다시 조회하기까지의 시간. refresh 는 툴 호출마다 불린다.
export const PR_TTL_MS = 30_000

const PR_URL = /^https:\/\/[^\s/]+\/[^\s/]+\/[^\s/]+\/pull\/\d+$/

// gh pr view 의 JSON 을 표시할 PR 로 바꾼다. 열린(OPEN) PR 만 돌려주고,
// MERGED·CLOSED 이거나 모양이 이상하면 null(아무것도 표시하지 않는다).
export function parseGhPrView(stdout: string): BranchPr | null {
  let raw: unknown
  try {
    raw = JSON.parse(stdout)
  } catch {
    return null
  }
  if (typeof raw !== 'object' || raw === null) return null
  const { number, url, state, isDraft } = raw as { number?: unknown; url?: unknown; state?: unknown; isDraft?: unknown }
  if (state !== 'OPEN') return null
  if (typeof number !== 'number' || !Number.isInteger(number) || number <= 0) return null
  if (typeof url !== 'string' || !PR_URL.test(url)) return null
  return { number, url, isDraft: isDraft === true }
}

// 마지막 조회: 어느 키를 언제 읽었나. 없으면(처음·무효화됨) null.
export type LastFetch = { key: string; at: number } | null

// 지금 gh 를 띄워야 하나. 키가 없으면(git 아님·detached) 띄우지 않고,
// 키가 바뀌었거나 처음이면 바로, 같은 키면 TTL 이 지났을 때만.
export function needsFetch(last: LastFetch, key: string | null, now: number, ttlMs = PR_TTL_MS): boolean {
  if (key === null) return false
  if (last === null || last.key !== key) return true
  return now - last.at >= ttlMs
}

// 툴 결과에서 gitOperation.pr 을 꺼낸다. 없거나 모양이 이상하면 null.
// 엔진이 Bash·PowerShell 결과에 실어 주는 PR 동작(생성·머지·코멘트 …)이다 — gh 출력을 다시 파싱하지 않는다.
export function pickGitPr(result: unknown): { number: number } | null {
  if (typeof result !== 'object' || result === null) return null
  const op = (result as { gitOperation?: unknown }).gitOperation
  if (typeof op !== 'object' || op === null) return null
  const pr = (op as { pr?: unknown }).pr
  if (typeof pr !== 'object' || pr === null) return null
  const { number } = pr as { number?: unknown }
  if (typeof number !== 'number' || !Number.isInteger(number) || number <= 0) return null
  return { number }
}

// 이 툴 결과가 PR 캐시를 무효화하나: Bash·PowerShell 이 PR 을 건드렸을 때(머지 직후 바로 사라지게).
export function invalidatesPr(tool: string, result: unknown): boolean {
  return (tool === 'Bash' || tool === 'PowerShell') && pickGitPr(result) !== null
}
