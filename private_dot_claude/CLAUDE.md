# 개인 설정

## Logseq
- 기본 그래프는 `/Users/yoophi/docs/private-zk`에 있다.
- Logseq 페이지를 조회하거나 기록할 때 이 디렉터리를 사용한다.

## 다이어그램 / 그래프
- 문서에 다이어그램이나 그래프를 포함할 때는 항상 **Mermaid Chart** 문법을 사용한다.
- ASCII art 그래프를 사용하지 않는다.

## 할 일 관리 (Things 3)
- "할 일 기록해줘", "things에 추가", "할 일 조사/조회해줘" 등 할 일 관련 요청은 **`/Applications/Things3.app`** 을 사용한다.
- 쓰기(추가/수정): AppleScript(`osascript`) 또는 URL scheme(`open "things:///add?title=..."`)만 사용 — SQLite DB 직접 쓰기 금지(Things Cloud 동기화 깨짐).
- **PARA 규칙으로 관리한다.** 할 일 추가 시 반드시 PARA 분류에 맞는 Area/Project 에 배치하고, Inbox 에 방치하지 않는다.
  - `Projects` — 명확한 완료 기준과 기한이 있는 것
  - `Areas` — 기한 없이 지속적으로 유지·관리하는 책임 영역
  - `Resources` — 참고 자료 / 나중에 볼 것
  - `Archives` — 완료·비활성
  - 기존 프로젝트에 속하는 할 일이면 `things projects` 로 확인 후 해당 프로젝트에 넣는다.
- 읽기(조회): AppleScript 또는 Things SQLite DB(`~/Library/Group Containers/JLMPQHK86H.com.culturedcode.ThingsMac/`) 읽기 전용 쿼리 허용.
- `things update` 등 쓰기용 auth token 은 `$THINGS_AUTH_TOKEN` 환경변수에 있다(`~/.zshrc`). 사용자에게 다시 묻지 말 것.
