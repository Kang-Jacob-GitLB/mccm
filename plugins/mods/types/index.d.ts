// ---- pr-line ----
export type PrLine = {
  number: number
  // PR 웹페이지. 모양이 이상하면 빈 문자열(링크 없이 번호만)
  url: string
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

// ---- action-line ----
// GitHub Actions 실행 하나(workflow 마다 최신 것, PR 실행 포함)
export type ActionRun = {
  id: number
  // workflow 안의 실행 번호(#324). 모르면 0
  number: number
  // 실행 웹페이지. 모양이 이상하면 빈 문자열(링크 없이 번호만)
  url: string
  workflow: string
  branch: string
  // push, schedule, workflow_dispatch, release …
  event: string
  // queued, in_progress, completed … (소문자)
  status: string
  // success, failure, cancelled … (끝나기 전엔 빈 문자열)
  conclusion: string
  // 완료 시각 ISO 8601(gh 의 updatedAt). 끝나기 전엔 빈 문자열
  finishedAt: string
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

// where-line: 현재 브랜치의 열린 PR — gh pr view 로 얻는다
export type BranchPr = {
  number: number
  url: string
  isDraft: boolean
}

// where-line: 어느 (toplevel, 브랜치) 키에서 읽은 PR 인가. 열린 PR 이 없으면 pr 이 null
export type WhereLineBranchPr = {
  key: string
  pr: BranchPr | null
}

declare module 'claude-code' {
  interface PluginState {
    mods: {
      // pr-line
      prLinePrs: Shaped<PrLine[]>
      // action-line: workflow 마다 최신 실행, 최근 순(최대 3개)
      actionLineRuns: Shaped<ActionRun[]>
      // where-line
      whereLineWhere: WhereLine | null
      // 현재 브랜치의 PR. git 아님·detached HEAD 면 null
      whereLineBranchPr: Shaped<WhereLineBranchPr | null>
      // version-tag: 'v2.1.319' 같은 표시 문자열
      versionTagVersion: string | null
    }
  }
}
