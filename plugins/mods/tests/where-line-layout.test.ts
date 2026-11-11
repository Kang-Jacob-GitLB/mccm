// where-line 줄 나누기 테스트. 실행: claude plugin test plugins/mods
import { describe, expect, test } from 'claude-code/testing'

import { cellWidth, packLines } from '../hooks/where-line/layout'

describe('cellWidth', () => {
  test('이모지·한글은 두 칸, ⎇·ASCII 는 한 칸', () => {
    expect(cellWidth('📦 mccm')).toBe(7)
    expect(cellWidth('⎇ main')).toBe(6)
    expect(cellWidth('🌿 wt')).toBe(5)
    expect(cellWidth('git 아님')).toBe(8)
    expect(cellWidth(' · ')).toBe(3)
  })
})

describe('packLines', () => {
  // 실제 값: 📦 mccm · | ⎇ worktree-where-line-single-row · | 🌿 where-line-single-row · | 📁 ~/…/where-line-single-row · #58
  const W = [10, 35, 27, 63]

  test('넓으면 한 줄 — 넓은 창에서 여러 줄로 나뉘지 않는다', () => {
    expect(packLines(W, 200, 200 - 9)).toEqual([[0, 1, 2, 3]])
  })

  test('딱 맞으면 한 줄, 한 칸 모자라면 마지막 항목만 넘어간다', () => {
    expect(packLines(W, 144, 135)).toEqual([[0, 1, 2, 3]])
    expect(packLines(W, 143, 134)).toEqual([[0, 1, 2], [3]])
  })

  test('좁으면 항목 단위로 넘어가고, 첫 줄은 버전 자리를 뺀다', () => {
    expect(packLines(W, 81, 72)).toEqual([[0, 1, 2], [3]])
    expect(packLines(W, 80, 71)).toEqual([[0, 1], [2], [3]])
    expect(packLines(W, 60, 51)).toEqual([[0, 1], [2], [3]])
  })

  test('한 줄보다 긴 항목은 혼자 한 줄', () => {
    expect(packLines(W, 30, 21)).toEqual([[0], [1], [2], [3]])
  })

  test('폭을 모르면 한 줄, 항목이 없으면 빈 목록', () => {
    expect(packLines(W, 0)).toEqual([[0, 1, 2, 3]])
    expect(packLines([], 80)).toEqual([])
  })
})
