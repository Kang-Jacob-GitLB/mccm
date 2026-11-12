// gh 가 준 GitHub 웹 URL 검사(where-line·pr-line·action-line 공용).
// `#번호` 를 Link 로 감쌀 때 href 로 그대로 터미널(OSC 8)에 나가므로, 모양이 맞는 https URL 만 통과시킨다.
// 칸마다 허용 글자만 받아 ESC·BEL·방향 문자 같은 제어 글자가 끼어들 틈을 없앤다.
// 맞지 않으면 빈 문자열 — 그리는 쪽은 링크 없이 번호만 보인다.

// host(GHES 의 :포트 허용) / owner / repo
const BASE = String.raw`^https://[A-Za-z0-9.-]+(?::\d+)?/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+`
const PR_URL = new RegExp(`${BASE}/pull/\\d+$`)
const RUN_URL = new RegExp(`${BASE}/actions/runs/\\d+$`)

export const isPrUrl = (v: unknown): v is string => typeof v === 'string' && PR_URL.test(v)

export const prUrl = (v: unknown): string => (isPrUrl(v) ? v : '')

export const runUrl = (v: unknown): string => (typeof v === 'string' && RUN_URL.test(v) ? v : '')
