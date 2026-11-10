// GitHub 에서 온 글자(제목·브랜치·check·workflow 이름)에서 제어 문자와 방향 바꿈 문자를 지운다.
// 터미널 제어 시퀀스나 거꾸로 쓰기로 화면을 꾸며 낼 수 없게. pr-line·action-line 이 함께 쓴다.
export function clean(s: string): string {
  return s.replace(/[\u0000-\u001f\u007f-\u009f\u200b-\u200f\u202a-\u202e\u2066-\u2069]/g, '')
}
