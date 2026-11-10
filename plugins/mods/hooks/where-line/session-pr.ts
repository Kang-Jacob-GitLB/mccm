import type { SessionPr } from '../../types'

// 현재 세션의 PR: 이 세션에서 Bash·PowerShell 로 만들거나 머지·코멘트·수정한 PR.
// 엔진이 툴 결과에 실어 주는 gitOperation.pr(번호·URL·동작)로 잡는다 — gh 출력을 다시 파싱하지 않는다.

// 최근 것 몇 개만 기억한다.
export const MAX_SESSION_PRS = 3

// 툴 결과에서 gitOperation.pr 을 꺼낸다. 없거나 모양이 이상하면 null.
export function pickGitPr(result: unknown): SessionPr | null {
  if (typeof result !== 'object' || result === null) return null
  const op = (result as { gitOperation?: unknown }).gitOperation
  if (typeof op !== 'object' || op === null) return null
  const pr = (op as { pr?: unknown }).pr
  if (typeof pr !== 'object' || pr === null) return null
  const { number, url } = pr as { number?: unknown; url?: unknown }
  if (typeof number !== 'number' || !Number.isInteger(number) || number <= 0) return null
  const okUrl = typeof url === 'string' && /^https:\/\/[^\s/]+\/[^\s/]+\/[^\s/]+\/pull\/\d+$/.test(url)
  return { number, url: okUrl ? url : null }
}

// 같은 PR 인가: 둘 다 URL 이 있으면 URL 로, 아니면 번호로 견준다.
export function samePr(a: SessionPr, b: SessionPr): boolean {
  if (a.url && b.url) return a.url === b.url
  return a.number === b.number
}

// 맨 앞에 넣는다. 이미 있으면 맨 앞으로 옮기고, 몰랐던 URL 은 채운다.
export function remember(list: readonly SessionPr[], pr: SessionPr): SessionPr[] {
  const old = list.find(r => samePr(r, pr))
  const next: SessionPr = { number: pr.number, url: pr.url ?? old?.url ?? null }
  return [next, ...list.filter(r => !samePr(r, next))].slice(0, MAX_SESSION_PRS)
}
