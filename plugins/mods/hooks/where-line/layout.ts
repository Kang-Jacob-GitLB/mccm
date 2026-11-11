// where-line 의 줄 나누기. 엔진의 flexWrap 에 맡기면 넓은 창에서도 여러 줄로 나뉘어,
// band 폭(e.props.bodyColumns)과 각 항목의 칸 수로 직접 나눈다. 순수 함수라 테스트로 고정한다.

// 터미널에서 두 칸을 차지하는 글자: 이모지(📦 🌿 🏠 📁 …)·한글·CJK·전각.
// 폭 0: 결합 문자·변이 선택자·zero-width. ⎇(U+2387) 같은 기술 기호는 한 칸.
function charWidth(cp: number): number {
  if (cp === 0x200b || cp === 0x200c || cp === 0x200d || cp === 0xfe0e || cp === 0xfe0f) return 0
  if (cp >= 0x0300 && cp <= 0x036f) return 0
  if (
    (cp >= 0x1100 && cp <= 0x115f) || // 한글 자모
    (cp >= 0x2e80 && cp <= 0x303e) || // CJK 부수·기호
    (cp >= 0x3041 && cp <= 0x33ff) || // 가나·호환 자모
    (cp >= 0x3400 && cp <= 0x4dbf) ||
    (cp >= 0x4e00 && cp <= 0x9fff) ||
    (cp >= 0xa960 && cp <= 0xa97f) ||
    (cp >= 0xac00 && cp <= 0xd7a3) || // 한글 음절
    (cp >= 0xf900 && cp <= 0xfaff) ||
    (cp >= 0xfe30 && cp <= 0xfe4f) ||
    (cp >= 0xff00 && cp <= 0xff60) || // 전각
    (cp >= 0xffe0 && cp <= 0xffe6) ||
    (cp >= 0x1f300 && cp <= 0x1f64f) || // 이모지(기호·그림·이모티콘)
    (cp >= 0x1f680 && cp <= 0x1f6ff) ||
    (cp >= 0x1f900 && cp <= 0x1faff) ||
    (cp >= 0x20000 && cp <= 0x3fffd)
  ) {
    return 2
  }
  return 1
}

export function cellWidth(s: string): number {
  let w = 0
  for (const ch of s) w += charWidth(ch.codePointAt(0) ?? 0)
  return w
}

// 항목 폭(뒤에 붙는 구분점 포함)을 앞에서부터 채워 줄로 나눈다.
// 첫 줄은 오른쪽 끝 버전 자리를 뺀 firstCols, 나머지 줄은 cols. 한 줄보다 긴 항목은 혼자 한 줄(그리다 잘린다).
// cols 를 모르면(0 이하) 한 줄로 둔다. 돌려주는 것은 줄마다 항목 번호.
export function packLines(widths: number[], cols: number, firstCols: number = cols): number[][] {
  if (widths.length === 0) return []
  if (!(cols > 0)) return [widths.map((_, i) => i)]
  const lines: number[][] = []
  let line: number[] = []
  let used = 0
  widths.forEach((w, i) => {
    const room = lines.length === 0 ? firstCols : cols
    if (line.length > 0 && used + w > room) {
      lines.push(line)
      line = []
      used = 0
    }
    line.push(i)
    used += w
  })
  lines.push(line)
  return lines
}
