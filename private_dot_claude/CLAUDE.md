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

## Notion
- Notion 관련 작업은 **`ntn` CLI** (`/Users/yoophi/.local/bin/ntn`, `ntn --help`) 를 사용한다.
- Notion MCP 도구 대신 `ntn` 을 우선 사용한다.
- 주요 서브커맨드: `ntn pages`, `ntn datasources`, `ntn files`, `ntn api`(공개 API 직접 호출), `ntn whoami`, `ntn doctor`.

## 사용자 정보
- 전화번호: `01046242074` (E.164 `+821046242074`). 인증번호 수신·전화번호 로그인 등 본인 번호가 필요할 때 사용한다.

## 메시지 조회 (BlueBubbles)
- iMessage·SMS 조회는 로컬 **BlueBubbles Server** API `http://127.0.0.1:1234/api/v1` 를 사용한다. `~/Library/Messages/chat.db` 직접 접근은 TCC 로 막혀 있다.
- 비밀번호는 **`~/BLUEBUBBLE_SECRET.txt`** 에서 변수로 읽고, URL 인코딩해 `?password=` 로 넘긴다. **값을 출력·대화·명령줄 리터럴에 남기지 않는다.**
  ```bash
  P=$(tr -d '\n\r' < ~/BLUEBUBBLE_SECRET.txt)
  Q=$(python3 -c 'import urllib.parse,sys;print(urllib.parse.quote(sys.argv[1]))' "$P")
  curl -s -X POST "http://127.0.0.1:1234/api/v1/message/query?password=$Q" -H 'Content-Type: application/json' -d '{...}'
  ```
  - POST 는 JSON 본문을 쓰므로 `curl -G --data-urlencode` 불가(본문이 쿼리로 옮겨짐).
- 주요 API: `GET /server/info`, `POST /chat/query`, `POST /message/query`, `GET /chat/{guid}/message`.
  - 발신자 필터: `"with":["handle"], "where":[{"statement":"handle.id LIKE :addr","args":{"addr":"%15221902%"}}]`, 최신순 `"sort":"DESC"`, 시점 `"after":<unixMs>`.
  - 번호는 E.164(`+8215221902`)로 저장 → 부분 LIKE. `dateCreated` 는 Unix ms.
- Payhere 인증번호 문자는 **1522-1902** 에서 온다(`[Payhere Seller]`, `[Payhere HERO CX]`, `[Payhere 터미널]`, 개발계는 `개발 ` 접두). 같은 번호로 여러 서비스 코드가 오므로 **서비스명 + 발송 이후 시각**으로 거른다.
- 운영 원칙: Proxy Service 는 **LAN URL 유지**(Cloudflare·ngrok 터널 금지). 외부 노출 차단은 pf(`~/bin/bluebubbles-pf-setup.sh`, Things 프로젝트 "BlueBubbles 로컬 전용 구성").

## 전화번호 인증 로그인 자동화 (pc-seller 등 Electron 앱)
- 도구(`~/bin`):
  - `node ~/bin/cdp-eval.mjs <urlPrefix> '<js>'` — CDP(9222) 로 해당 페이지에서 JS 평가.
  - `node ~/bin/cdp-type.mjs <urlPrefix> '<selector>' <text>` — 실제 키 입력. 하이픈 자동삽입 같은 **controlled input 은 value 대입이 무시**되므로 이걸 쓴다.
  - `~/bin/bb-otp <sinceUnixMs> [Seller] [60]` — 발송 시각 이후 1522-1902 문자에서 6자리 인증번호만 출력(키워드로 서비스 구분).
- pc-seller 절차: `localhost:3000/#/login` → "바로 시작하기" → (QR/일회용번호 창) "전화번호 인증으로 로그인하시겠어요?" → `input[placeholder="전화번호 입력"]` 타이핑 → **`T=$(date +%s000)` 기록 후** "전송" → `bb-otp $T Seller` → `input[placeholder="인증번호 6자리 입력"]` 타이핑 → "확인" → `#/select-seller`.
- CDP 대상은 `curl -s localhost:9222/json/list` 로 확인(로그인 단계에서 `login.payhere.dev` 별도 창이 잠시 열림). 매장 선택은 사용자에게 묻는다.

## 작업 완료 알림 (기본 규칙)
- 모든 프로젝트에서 개별 작업의 구현 및 필요한 검증을 완료할 때마다 `https://ntfy.sh/yoophi` 채널로 완료 푸시 메시지를 발송한다.
- 메시지에는 간결한 완료 요약과, 해당하는 경우 프로젝트명 및 이슈 번호를 포함한다. 비밀값이나 민감한 작업 내용은 보내지 않는다.
- ntfy 메시지 발송 시 `Title`, `Priority`, `Tags` 헤더와 메시지 본문(`body`)을 모두 명시한다. `Tags`에는 반드시 해당 프로젝트명과 `claude` 를 포함한다.
- 일반 완료 알림은 `Priority: default`를 사용하고, `Title`에는 프로젝트명과 완료 내용을 간결하게 적는다. 본문에는 완료 요약과 해당하는 경우 이슈 번호를 포함한다.
- 발송 예시:
  ```sh
  curl --fail-with-body \
    -H "Title: box.md task completed" \
    -H "Priority: default" \
    -H "Tags: box.md,claude,white_check_mark" \
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
