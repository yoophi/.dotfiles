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

## Kiro CLI
- `kiro-cli` 실행 시 항상 trust mode로 진행하며, `kiro-cli chat --trust-all-tools` 명령을 사용한다.

## 작업 완료 알림 (기본 규칙)
- 모든 프로젝트에서 개별 작업의 구현 및 필요한 검증을 완료할 때마다 `https://ntfy.sh/yoophi` 채널로 완료 푸시 메시지를 발송한다.
- 메시지에는 간결한 완료 요약과, 해당하는 경우 프로젝트명 및 이슈 번호를 포함한다. 비밀값이나 민감한 작업 내용은 보내지 않는다.
- ntfy 메시지 발송 시 `Title`, `Priority`, `Tags` 헤더와 메시지 본문(`body`)을 모두 명시한다. `Tags`에는 반드시 해당 프로젝트명과 Codex 를 포함한다.
- 일반 완료 알림은 `Priority: default`를 사용하고, `Title`에는 프로젝트명과 완료 내용을 간결하게 적는다. 본문에는 완료 요약과 해당하는 경우 이슈 번호를 포함한다.
- 발송 예시:
  ```sh
  curl --fail-with-body \
    -H "Title: box.md task completed" \
    -H "Priority: default" \
    -H "Tags: box.md,codex,white_check_mark" \
    -d "box.md: 작업 구현 및 필요한 검증 완료 (gh-123)." \
    https://ntfy.sh/yoophi
  ```
- 미완료 작업이나 진행 상황을 완료로 알리지 않는다. 발송 실패는 사용자에게 명시적으로 보고한다.
- 사용자가 명시적으로 요청한 기본 동작이므로 매번 발송 승인을 다시 묻지 않는다.

<!-- td-agent-instructions:start -->
<!-- td-agent-instructions:version=3 -->

## Working with td

td keeps task context durable across sessions. In a new context, run `td usage --new-session -q` to see current work.

Use your judgment about how much tracking a task needs. For substantive work: `td start <id>`, record progress with `td log`, hand off with `td handoff <id>`, then `td review <id>`.

Closing needs a review. Say who did it (default trusted mode; delegated/strict allow only the first):

- independent session: `td approve <id> --reason "..."`
- a sub-agent: `td approve <id> --reviewed-by "<who>"`
- you: `td approve <id> --self-review --reason "..."`

Prefer a reviewer with its own `TD_CONTEXT_ID`; never name one who did not review.

Run `td usage` or `td <command> --help`.

<!-- td-agent-instructions:end -->
