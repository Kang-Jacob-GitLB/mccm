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

// ---- where-line ----
export type WhereLine = {
  // 세션 cwd, 홈은 ~ 로 줄인 표기
  cwd: string
  // git 저장소가 아니면 null
  git: {
    branch: string
    // 링크된 워크트리면 그 폴더 이름, 주 체크아웃이면 null
    worktree: string | null
    repo: string
  } | null
}

declare module 'claude-code' {
  interface PluginState {
    mods: {
      // pr-line
      prLinePrs: Shaped<PrLine[]>
      // where-line
      whereLineWhere: WhereLine | null
      // version-tag: 'v2.1.319' 같은 표시 문자열
      versionTagVersion: string | null
    }
  }
}
