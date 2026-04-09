---
name: md-to-gdoc
description: Markdown 파일을 GitHub 스타일 서식의 Google Docs 문서로 변환한다. "/md-to-gdoc", "마크다운을 구글독스로", "md to google docs" 등의 요청에 사용한다.
disable-model-invocation: true
allowed-tools: Bash, Read
---

## 사전 요구사항

- `gws` CLI 설치 및 인증 필요 (`gws auth login`)

## 작업 지침

### 1. 입력 파일 확인

대상 파일: `$ARGUMENTS`

`$ARGUMENTS`가 비어 있으면 사용자에게 변환할 마크다운 파일 경로를 물어본다. 파일이 존재하는지 확인한다.

### 2. Markdown 파싱

대상 마크다운 파일을 읽고 구조를 분석한다. 아래 요소를 식별한다:

- 헤딩 (`#` ~ `######`)
- 본문 텍스트
- **볼드**, *이탤릭*, `인라인 코드`
- 코드 블록 (``` 펜스)
- 테이블
- 순서 있는/없는 목록 (중첩 포함)
- 인용문 (`>`)
- 수평선 (`---`)
- 링크, 이미지

### 3. 업로드 위치 확인

사용자에게 Google Drive 내 업로드 위치를 물어본다. 폴더 ID 또는 Drive 내 경로를 받는다. 지정하지 않으면 내 드라이브 루트에 생성한다.

### 4. Google Docs 문서 생성

마크다운 파일명(확장자 제외)을 문서 제목으로 사용한다. 지정된 폴더가 있으면 해당 폴더에 생성한다.

```bash
# 폴더 미지정 시
gws docs documents create --json '{"title": "{문서제목}"}'

# 폴더 지정 시: 문서 생성 후 Drive에서 폴더로 이동
gws drive files update --params '{"fileId": "{documentId}", "addParents": "{folderId}", "removeParents": "root"}'
```

응답에서 `documentId`를 추출한다.

### 5. batchUpdate 요청 구성

파싱된 마크다운을 Google Docs API `batchUpdate` 요청으로 변환한다. **텍스트 삽입은 역순으로** 구성한다 (문서 끝부터 처음 순서로 삽입하면 인덱스가 밀리지 않는다).

#### GitHub 스타일 서식 매핑

**헤딩:**
- `#` → HEADING_1, 24pt, 볼드
- `##` → HEADING_2, 20pt, 볼드, 하단에 수평선 삽입
- `###` → HEADING_3, 16pt, 볼드
- `####` ~ `######` → HEADING_4~6, 14pt, 볼드

**텍스트 스타일:**
- 볼드 → `bold: true`
- 이탤릭 → `italic: true`
- 인라인 코드 → `weightedFontFamily: "Consolas"`, 배경색 `#f6f8fa`, fontSize 13pt

**코드 블록:**
- 전체 블록: `weightedFontFamily: "Consolas"`, fontSize 13pt, 배경색 `#f6f8fa`
- 들여쓰기 0으로 설정

**테이블:**
- `insertTable` 요청으로 행/열 생성
- 헤더 행: 배경색 `#f6f8fa`, 볼드
- 짝수 행: 배경색 `#f6f8fa`
- 테두리: `#d1d9e0`

**목록:**
- 순서 없는 목록 → `BULLET_DISC_CIRCLE_SQUARE`
- 순서 있는 목록 → `NUMBERED_DECIMAL_ALPHA_ROMAN`
- 중첩: `nestingLevel` 증가

**인용문:**
- 왼쪽 들여쓰기 36pt
- 텍스트 색상 `#656d76`
- 왼쪽 테두리 시뮬레이션: 인용 텍스트 앞에 `▎` 문자 + 색상 `#d1d9e0`

**링크:**
- `updateTextStyle`로 `link.url` 설정, 색상 `#0969da`

**수평선:**
- 빈 paragraph에 하단 테두리 추가

### 6. batchUpdate 실행

구성된 요청을 실행한다. 요청이 크면 여러 번에 나눠서 실행한다.

```bash
gws docs documents batchUpdate --params '{"documentId": "{documentId}"}' --json '{요청본문}'
```

### 7. 완료 보고

- 생성된 Google Docs URL: `https://docs.google.com/document/d/{documentId}/edit`
- 변환된 요소 수 요약 (헤딩, 테이블, 코드블록 등)
