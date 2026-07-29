# 개인 설정

## 다이어그램 / 그래프
- 문서에 다이어그램이나 그래프를 포함할 때는 항상 **Mermaid Chart** 문법을 사용한다.
- ASCII art 그래프를 사용하지 않는다.

## 할 일 관리 (Things 3)
- "할 일 기록해줘", "things에 추가", "할 일 조사/조회해줘" 등 할 일 관련 요청은 **`/Applications/Things3.app`** 을 사용한다.
- 쓰기(추가/수정): AppleScript(`osascript`) 또는 URL scheme(`open "things:///add?title=..."`)만 사용 — SQLite DB 직접 쓰기 금지(Things Cloud 동기화 깨짐).
- 읽기(조회): AppleScript 또는 Things SQLite DB(`~/Library/Group Containers/JLMPQHK86H.com.culturedcode.ThingsMac/`) 읽기 전용 쿼리 허용.
