---
name: md-to-pdf
description: Markdown 파일을 GitHub 웹 스타일 PDF로 변환한다. "/md-to-pdf", "마크다운 PDF로 변환", "md를 pdf로", "convert md to pdf" 등의 요청에 사용한다.
disable-model-invocation: true
allowed-tools: Bash, Read
---

## 사전 요구사항

- Node.js 설치 필요
- `md-to-pdf`는 스킬 실행 시 npx로 자동 호출 (별도 설치 불필요)

## 작업 지침

### 1. 입력 파일 확인

대상 파일: `$ARGUMENTS`

`$ARGUMENTS`가 비어 있으면 사용자에게 변환할 마크다운 파일 경로를 물어본다. 파일이 존재하는지 확인한다.

### 2. GitHub 스타일 CSS 생성

변환에 사용할 GitHub 스타일 CSS를 임시 파일로 생성한다.

```bash
cat > /tmp/github-markdown.css << 'CSSEOF'
body {
  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", "Noto Sans", Helvetica, Arial, sans-serif;
  font-size: 16px;
  line-height: 1.5;
  word-wrap: break-word;
  color: #1f2328;
  background-color: #ffffff;
  max-width: 980px;
  margin: 0 auto;
  padding: 45px;
}
h1, h2, h3, h4, h5, h6 {
  margin-top: 24px;
  margin-bottom: 16px;
  font-weight: 600;
  line-height: 1.25;
}
h1 { font-size: 2em; padding-bottom: 0.3em; border-bottom: 1px solid #d1d9e0; }
h2 { font-size: 1.5em; padding-bottom: 0.3em; border-bottom: 1px solid #d1d9e0; }
h3 { font-size: 1.25em; }
h4 { font-size: 1em; }
code {
  padding: 0.2em 0.4em;
  margin: 0;
  font-size: 85%;
  white-space: break-spaces;
  background-color: rgba(175,184,193,0.2);
  border-radius: 6px;
  font-family: ui-monospace, SFMono-Regular, "SF Mono", Menlo, Consolas, "Liberation Mono", monospace;
}
pre {
  padding: 16px;
  overflow: auto;
  font-size: 85%;
  line-height: 1.45;
  background-color: #f6f8fa;
  border-radius: 6px;
}
pre code {
  padding: 0;
  background-color: transparent;
  border-radius: 0;
}
table {
  border-spacing: 0;
  border-collapse: collapse;
  display: block;
  width: max-content;
  max-width: 100%;
  overflow: auto;
  margin-top: 0;
  margin-bottom: 16px;
}
table th, table td {
  padding: 6px 13px;
  border: 1px solid #d1d9e0;
}
table th {
  font-weight: 600;
  background-color: #f6f8fa;
}
table tr:nth-child(2n) {
  background-color: #f6f8fa;
}
blockquote {
  margin: 0;
  padding: 0 1em;
  color: #656d76;
  border-left: 0.25em solid #d1d9e0;
}
a { color: #0969da; text-decoration: none; }
a:hover { text-decoration: underline; }
hr {
  height: 0.25em;
  padding: 0;
  margin: 24px 0;
  background-color: #d1d9e0;
  border: 0;
}
ul, ol { padding-left: 2em; }
li + li { margin-top: 0.25em; }
img { max-width: 100%; }
CSSEOF
```

### 3. PDF 변환

`md-to-pdf`를 사용하여 GitHub 스타일 CSS를 적용한 PDF를 생성한다.

```bash
npx --yes md-to-pdf {입력파일} \
  --stylesheet /tmp/github-markdown.css \
  --pdf-options '{"format": "A4", "margin": {"top": "20mm", "right": "20mm", "bottom": "20mm", "left": "20mm"}}' \
  --dest {출력파일}
```

- 출력 파일명: 입력 파일과 같은 이름에 확장자만 `.pdf`로 변경
- 출력 경로: 입력 파일과 같은 디렉토리

### 4. 완료 보고

- 생성된 PDF 파일 경로
- 파일 크기
