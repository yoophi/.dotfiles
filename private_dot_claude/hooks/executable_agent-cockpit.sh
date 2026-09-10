#!/bin/bash
# Claude Code hook → Hammerspoon 에이전트 콕핏 (hammerspoon://agent)
#
#   agent-cockpit.sh waiting  -> Notification      (권한/질문 대기: 사용자의 확인이 필요)
#   agent-cockpit.sh done     -> Stop              (턴 완료: 결과 확인 필요)
#   agent-cockpit.sh working  -> UserPromptSubmit  (사용자가 응답했고 에이전트가 다시 일함)
#   agent-cockpit.sh idle     -> SessionStart      (세션 시작, 아직 프롬프트 없음)
#   agent-cockpit.sh gone     -> SessionEnd        (세션 종료 → 목록에서 제거)
#
# stdin 의 hook JSON(session_id, cwd, message …)과 환경변수(TERM_PROGRAM, TMUX, TMUX_PANE,
# HERDR_PANE_ID)를 URL 파라미터로 실어 보낸다. Codex 는 ~/.codex/hooks/agent-cockpit-codex.sh 어댑터가
# COCKPIT_AGENT=codex 로 이 스크립트를 호출한다(Codex 훅은 stdout 에 JSON 을 요구하므로 어댑터가 {} 를 낸다). Hammerspoon 쪽 처리는 ~/.hammerspoon/agent-cockpit.lua.
# 실패해도 Claude Code 를 막지 않도록 항상 exit 0.

STATE="${1:-done}"
INPUT="${COCKPIT_INPUT:-$(cat 2>/dev/null)}"
AGENT="${COCKPIT_AGENT:-claude}"          # claude | codex … (어댑터가 지정)

# 훅 프로세스의 PATH 가 최소 구성일 수 있어(Codex) 절대 경로로 폴백
JQ="$(command -v jq 2>/dev/null || ls /opt/homebrew/bin/jq /usr/local/bin/jq 2>/dev/null | head -1)"
LOG="${COCKPIT_LOG:-$HOME/.cache/agent-cockpit.log}"
dbg() { [ -n "$COCKPIT_DEBUG" ] && printf '%s %s\n' "$(date +%H:%M:%S)" "$*" >> "$LOG"; }
[ -n "$JQ" ] || { dbg "jq 없음 PATH=$PATH"; exit 0; }
jq() { "$JQ" "$@"; }
/usr/bin/pgrep -xq Hammerspoon || { dbg "Hammerspoon 미실행"; exit 0; }

SESSION="$(printf '%s' "$INPUT" | jq -r '.session_id // .thread_id // empty' 2>/dev/null)"
CWD="$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)"
[ -z "$CWD" ] && CWD="$PWD"
PROJECT="$(basename "$CWD")"
case "$PROJECT" in main|master|dev|develop|src|app|repo) PROJECT="$(basename "$(dirname "$CWD")")/$PROJECT" ;; esac
MSG="$(printf '%s' "$INPUT" | jq -r '(.message // .title // "") | .[0:120]' 2>/dev/null)"
NTYPE="$(printf '%s' "$INPUT" | jq -r '.notification_type // empty' 2>/dev/null)"
TMUX_SOCK="${TMUX%%,*}"

enc() { printf '%s' "$1" | jq -sRr @uri; }

URL="hammerspoon://agent?state=$(enc "$STATE")"
URL="$URL&session=$(enc "${SESSION:-$CWD}")"
URL="$URL&project=$(enc "$PROJECT")"
URL="$URL&cwd=$(enc "$CWD")"
URL="$URL&term=$(enc "${TERM_PROGRAM:-}")"
URL="$URL&tmux_sock=$(enc "$TMUX_SOCK")"
URL="$URL&tmux_pane=$(enc "${TMUX_PANE:-}")"
URL="$URL&herdr_pane=$(enc "${HERDR_PANE_ID:-}")"
URL="$URL&label=$(enc "${NOTIFY_AGENT_LABEL:-}")"
URL="$URL&msg=$(enc "$MSG")"
URL="$URL&ntype=$(enc "$NTYPE")"
URL="$URL&agent=$(enc "$AGENT")"

dbg "agent=$AGENT state=$STATE project=$PROJECT session=${SESSION:-$CWD} term=${TERM_PROGRAM:-} tmux=${TMUX_PANE:-} herdr=${HERDR_PANE_ID:-}"
# -g: 포커스를 뺏지 않음. 백그라운드로 던지고 즉시 반환.
/usr/bin/open -g "$URL" >/dev/null 2>&1 &
exit 0
