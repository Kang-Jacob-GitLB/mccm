// ---- pr-line ----
export type PrLine = {
  number: number
  title: string
  branch: string
  isDraft: boolean
  // CI: 통과·실패·진행 수와 진행 중(없으면 실패한) 첫 check 이름
  pass: number
  fail: number
  pending: number
  current: string
  // CLEAN, BLOCKED, BEHIND, DIRTY, UNSTABLE, DRAFT, UNKNOWN …
  merge: string
}

declare module 'claude-code' {
  interface PluginState {
    mods: {
      // pr-line
      prLinePrs: Shaped<PrLine[]>
    }
  }
}
