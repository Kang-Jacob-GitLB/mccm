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

// where-line: 현재 세션의 PR 하나 — 툴 결과 gitOperation.pr 에서 얻은 번호와 URL(없으면 null)
export type SessionPr = {
  number: number
  url: string | null
}

declare module 'claude-code' {
  interface PluginState {
    mods: {
      // pr-line
      prLinePrs: Shaped<PrLine[]>
      // where-line
      whereLineWhere: WhereLine | null
      // 이 세션에서 다룬 PR, 최근 것이 앞(최대 3개)
      whereLineSessionPrs: SessionPr[]
      // version-tag: 'v2.1.319' 같은 표시 문자열
      versionTagVersion: string | null
    }
  }
}
