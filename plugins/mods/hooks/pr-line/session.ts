import type { PrLine, PrRef } from '../../types'

// 현재 세션의 PR: 이 세션에서 Bash·PowerShell 로 만들거나 머지·코멘트한 PR.
// 엔진이 툴 결과에 실어 주는 gitOperation.pr(번호·URL·동작)로 잡는다 — gh 출력을 다시 파싱하지 않는다.

// 세션 PR 은 최근 것 몇 개만 기억한다.
export const MAX_SESSION = 3

// 툴 결과에서 gitOperation.pr 을 꺼낸다. 없거나 모양이 이상하면 null.
export function pickGitPr(result: unknown): PrRef | null {
  if (typeof result !== 'object' || result === null) return null
  const op = (result as { gitOperation?: unknown }).gitOperation
  if (typeof op !== 'object' || op === null) return null
  const pr = (op as { pr?: unknown }).pr
  if (typeof pr !== 'object' || pr === null) return null
  const { number, url } = pr as { number?: unknown; url?: unknown }
  if (typeof number !== 'number' || !Number.isInteger(number) || number <= 0) return null
  // gh 에 그대로 넘기는 값이라 GitHub PR URL 모양만 받는다.
  const okUrl = typeof url === 'string' && /^https:\/\/[^\s/]+\/[^\s/]+\/[^\s/]+\/pull\/\d+$/.test(url)
  return { number, url: okUrl ? url : null }
}

// 같은 PR 인가: 둘 다 URL 이 있으면 URL 로, 아니면 번호로 견준다.
export function samePr(a: { number: number; url: string | null }, b: { number: number; url: string | null }): boolean {
  if (a.url && b.url) return a.url === b.url
  return a.number === b.number
}

// 세션 PR 목록 맨 앞에 넣는다. 이미 있으면 맨 앞으로 옮기고, URL 을 몰랐으면 채운다.
export function remember(list: readonly PrRef[], ref: PrRef): PrRef[] {
  const old = list.find(r => samePr(r, ref))
  const next: PrRef = { number: ref.number, url: ref.url ?? old?.url ?? null }
  return [next, ...list.filter(r => !samePr(r, next))].slice(0, MAX_SESSION)
}

// 세션 PR 줄을 맨 앞에, 나머지 열린 PR 은 그 뒤에. 겹치는 열린 PR 은 세션 줄로 한 번만.
export function combine(session: readonly PrLine[], open: readonly PrLine[]): PrLine[] {
  const rest = open.filter(o => !session.some(s => samePr(s, o)))
  return [...session.map(s => ({ ...s, session: true })), ...rest.map(o => ({ ...o, session: false }))]
}
