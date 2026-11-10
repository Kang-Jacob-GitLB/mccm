import { atom, read, update } from 'claude-code'
import type { EngineInterface } from 'claude-code'

// Claude Code 버전을 읽어 둔다. 그리는 것은 where-line 이 한다 — 입력창 위 브랜치 줄 맨 오른쪽.
//   📦 mccm · ⎇ main · 🌿 x · 📁 ~/project/mccm                 v2.1.319
// version-tag 를 끄면 값이 null 로 남아 where-line 이 버전 없이 그린다.
// 버전은 세션 동안 바뀌지 않으므로 세션 시작에 한 번 읽는다(리로드 때도 session.start 가 다시 돈다).

const version = atom({ plugin: 'mods', key: 'versionTagVersion' } as const, null)

export async function sessionStart($: EngineInterface) {
  try {
    const v = await $.session.version()
    // 개발 빌드의 긴 버전(…-dev.날짜.sha) 대신 base(2.1.280-dev)를 쓴다.
    const label = `v${v.base ?? v.version}`
    if ((await read($, version)) !== label) await update($, version, () => label)
  } catch {
    // 표시용이라 실패는 조용히 넘긴다.
  }
}
