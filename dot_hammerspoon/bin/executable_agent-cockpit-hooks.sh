#!/bin/bash
# agent-cockpit-hooks.sh — Agent Cockpit 훅을 Claude Code / Codex 설정에 넣거나 뺀다.
#
#   agent-cockpit-hooks.sh install   [--dry-run]   콕핏 훅 항목을 병합한다 (멱등: 이미 최신이면 아무것도 안 씀)
#   agent-cockpit-hooks.sh uninstall [--dry-run]   콕핏 훅 항목만 제거한다 (다른 도구의 훅은 그대로)
#   agent-cockpit-hooks.sh status                  설치 상태와 의존성을 점검한다
#
# 왜 별도 스크립트인가
#   ~/.claude/settings.json 과 ~/.codex/hooks.json 에는 다른 도구의 훅, API 키, 기기별 설정이 함께 들어 있어
#   chezmoi 로 파일 전체를 관리할 수 없다. 대신 이 스크립트가 콕핏 항목만 골라 병합한다.
#   chezmoi 소스의 .chezmoiscripts/run_onchange_after_10-agent-cockpit-hooks.sh.tmpl 이 apply 때 install 을 부른다.
#
# 규칙
#   - command 문자열에 MARKER(agent-cockpit.sh / agent-cockpit-codex.sh) 가 들어간 훅 항목을 콕핏 소유로 본다.
#   - install 은 기존 콕핏 항목을 모두 지운 뒤 정의를 각 이벤트 배열의 "끝"에 덧붙인다.
#     Codex 는 훅 신뢰 해시를 (이벤트, 배열 인덱스) 위치로 저장하므로(~/.codex/config.toml [hooks.state]) 다른 항목의
#     순서를 흔들면 그 훅들이 다시 "review required" 가 된다. 끝에 붙이면 기존 위치가 유지된다.
#   - 내용이 실제로 달라질 때만 쓴다. 쓸 때는 <파일>.cockpit-backup-<시각> 으로 백업하고 임시 파일 → mv 로 교체한다.
#   - 테스트용 경로 덮어쓰기: COCKPIT_CLAUDE_SETTINGS, COCKPIT_CODEX_HOOKS
set -eu

CLAUDE_SETTINGS="${COCKPIT_CLAUDE_SETTINGS:-$HOME/.claude/settings.json}"
CODEX_HOOKS="${COCKPIT_CODEX_HOOKS:-$HOME/.codex/hooks.json}"
CLAUDE_HOOK="$HOME/.claude/hooks/agent-cockpit.sh"
CODEX_HOOK="$HOME/.codex/hooks/agent-cockpit-codex.sh"
CLAUDE_MARKER="agent-cockpit.sh"
CODEX_MARKER="agent-cockpit-codex.sh"

# chezmoi 스크립트·cron 등 PATH 가 최소 구성인 곳에서도 찾도록 Homebrew 경로를 폴백으로 둔다.
JQ="$(command -v jq 2>/dev/null || ls /opt/homebrew/bin/jq /usr/local/bin/jq 2>/dev/null | head -1 || true)"

DRY_RUN=0
LAST_CHANGED=0

usage() {
  cat <<'USAGE'
사용법: agent-cockpit-hooks.sh <install|uninstall|status> [--dry-run]

  install    콕핏 훅을 ~/.claude/settings.json, ~/.codex/hooks.json 에 병합 (멱등)
  uninstall  콕핏 훅 항목만 제거
  status     설치 상태·의존성 점검
  --dry-run  install/uninstall 에서 파일을 쓰지 않고 diff 만 출력
USAGE
  exit "${1:-2}"
}

die() { echo "agent-cockpit-hooks: $*" >&2; exit 1; }

need_jq() { [ -n "$JQ" ] || die "jq 가 필요합니다: brew install jq"; }

# ---------------------------------------------------------------- 훅 정의
# Claude Code: settings.json 의 hooks.<Event>[] 항목. Claude Code 가 직접 쓰는 형식(type/command/timeout/async)을 따른다.
claude_defs() {
  "$JQ" -n --arg hook "$CLAUDE_HOOK" '
    def entry($state): { hooks: [ { type: "command", command: ("bash \u0027" + $hook + "\u0027 " + $state), timeout: 5, async: true } ] };
    { Notification:     [ entry("waiting") ],
      Stop:             [ entry("done") ],
      UserPromptSubmit: [ entry("working") ],
      SessionStart:     [ entry("idle") ],
      SessionEnd:       [ entry("gone") ] }'
}

# Codex: hooks.json 의 hooks.<Event>[] 항목. async 필드가 없고 SessionEnd 는 3초로 클램프되므로 3 을 준다.
codex_defs() {
  "$JQ" -n --arg hook "$CODEX_HOOK" '
    def entry($state; $t): { hooks: [ { type: "command", command: ($hook + " " + $state), timeout: $t } ] };
    { SessionStart:      [ entry("idle"; 5) ],
      UserPromptSubmit:  [ entry("working"; 5) ],
      Stop:              [ entry("done"; 5) ],
      PermissionRequest: [ entry("waiting"; 5) ],
      SessionEnd:        [ entry("gone"; 3) ] }'
}

# ---------------------------------------------------------------- 병합
read_json() {                       # 파일 → JSON 문자열. 없거나 비어 있으면 {}. 깨진 JSON 은 건드리지 않고 중단.
  local file="$1"
  if [ -f "$file" ] && [ -s "$file" ]; then
    "$JQ" -e . "$file" >/dev/null 2>&1 || die "$file: JSON 파싱 실패. 손대지 않고 중단합니다."
    cat "$file"
  else
    echo '{}'
  fi
}

# merge <현재 JSON> <marker> <defs JSON> → 콕핏 항목을 제거한 뒤 defs 를 각 이벤트 끝에 덧붙인 JSON
merge() {
  local cur="$1" marker="$2" defs="$3"
  printf '%s' "$cur" | "$JQ" --arg marker "$marker" --argjson defs "$defs" '
    def cockpit: any((.hooks // [])[]; ((.command // "") | tostring | contains($marker)));
    . as $root
    | (($root.hooks // {}) | with_entries(.value |= map(select(cockpit | not)))) as $kept
    | reduce ($defs | to_entries[]) as $d ($kept; .[$d.key] = ((.[$d.key] // []) + $d.value))
    | with_entries(select(.value | length > 0))
    | . as $hooks | $root | .hooks = $hooks'
}

canon() { printf '%s' "$1" | "$JQ" -S .; }   # 키 순서 무시 비교용 정규형

# apply_file <라벨> <파일> <현재 JSON> <새 JSON>
apply_file() {
  local label="$1" file="$2" cur="$3" new="$4"
  LAST_CHANGED=0
  if [ "$(canon "$cur")" = "$(canon "$new")" ]; then
    echo "$label: 변경 없음  ($file)"
    return 0
  fi
  if [ "$DRY_RUN" = 1 ]; then
    echo "$label: 변경 예정  ($file)"
    diff -u <(printf '%s\n' "$cur" | "$JQ" .) <(printf '%s\n' "$new" | "$JQ" .) | sed 's/^/    /' || true
    LAST_CHANGED=1
    return 0
  fi
  mkdir -p "$(dirname "$file")"
  [ -f "$file" ] && cp -p "$file" "$file.cockpit-backup-$(date +%Y%m%d-%H%M%S)"
  local tmp
  tmp="$(mktemp "$file.tmp.XXXXXX")"
  printf '%s\n' "$new" | "$JQ" --indent 2 . >"$tmp" && mv "$tmp" "$file"
  echo "$label: 갱신  ($file)"
  LAST_CHANGED=1
}

codex_trust_note() {
  echo "Codex: hooks.json 이 바뀌었습니다. 다음에 codex 를 대화형으로 실행하면 새 훅에 대해 'review required' 신뢰 확인이 뜹니다."
}

do_install() {
  local cur
  cur="$(read_json "$CLAUDE_SETTINGS")"
  apply_file "Claude Code" "$CLAUDE_SETTINGS" "$cur" "$(merge "$cur" "$CLAUDE_MARKER" "$(claude_defs)")"
  cur="$(read_json "$CODEX_HOOKS")"
  apply_file "Codex" "$CODEX_HOOKS" "$cur" "$(merge "$cur" "$CODEX_MARKER" "$(codex_defs)")"
  [ "$LAST_CHANGED" = 1 ] && [ "$DRY_RUN" = 0 ] && codex_trust_note
  return 0
}

do_uninstall() {
  local cur
  if [ -f "$CLAUDE_SETTINGS" ]; then
    cur="$(read_json "$CLAUDE_SETTINGS")"
    apply_file "Claude Code" "$CLAUDE_SETTINGS" "$cur" "$(merge "$cur" "$CLAUDE_MARKER" '{}')"
  else
    echo "Claude Code: 설정 파일 없음, 건너뜀  ($CLAUDE_SETTINGS)"
  fi
  if [ -f "$CODEX_HOOKS" ]; then
    cur="$(read_json "$CODEX_HOOKS")"
    apply_file "Codex" "$CODEX_HOOKS" "$cur" "$(merge "$cur" "$CODEX_MARKER" '{}')"
    [ "$LAST_CHANGED" = 1 ] && [ "$DRY_RUN" = 0 ] && codex_trust_note
  else
    echo "Codex: 설정 파일 없음, 건너뜀  ($CODEX_HOOKS)"
  fi
  return 0
}

# ---------------------------------------------------------------- 상태
report() {                          # 이벤트별로 설치된 콕핏 항목 수를 정의와 대조한다
  local label="$1" file="$2" marker="$3" defs="$4"
  if [ ! -f "$file" ]; then
    echo "$label: 설정 파일 없음  ($file)"
    return 0
  fi
  "$JQ" -r --arg marker "$marker" --argjson defs "$defs" --arg label "$label" '
    def cockpit: any((.hooks // [])[]; ((.command // "") | tostring | contains($marker)));
    (.hooks // {}) as $h
    | ($defs | keys_unsorted[]) as $ev
    | (($h[$ev] // []) | map(select(cockpit)) | length) as $n
    | "  \($label) \($ev): \(if $n == ($defs[$ev] | length) then "OK" else "누락 (\($n)/\($defs[$ev] | length))" end)"' "$file"
  local cur
  cur="$(read_json "$file")"
  if [ "$(canon "$cur")" = "$(canon "$(merge "$cur" "$marker" "$defs")")" ]; then
    echo "  $label: install 해도 변경 없음 (최신)"
  else
    echo "  $label: install 필요 (정의와 다름)"
  fi
}

do_status() {
  echo "jq: ${JQ:-없음 (brew install jq)}"
  if /usr/bin/pgrep -xq Hammerspoon; then echo "Hammerspoon: 실행 중"; else echo "Hammerspoon: 미실행"; fi
  local f
  for f in "$CLAUDE_HOOK" "$CODEX_HOOK" "$HOME/.hammerspoon/agent-cockpit.lua" "$HOME/.hammerspoon/bin/agent-scan.py"; do
    if [ -x "$f" ] || { [ -f "$f" ] && [ "${f##*.}" = lua ]; }; then echo "파일 OK      $f"; else echo "파일 없음    $f"; fi
  done
  [ -n "$JQ" ] || return 0
  report "Claude Code" "$CLAUDE_SETTINGS" "$CLAUDE_MARKER" "$(claude_defs)"
  report "Codex" "$CODEX_HOOKS" "$CODEX_MARKER" "$(codex_defs)"
}

# ---------------------------------------------------------------- main
cmd="${1:-}"
[ $# -gt 0 ] && shift
for a in "$@"; do
  case "$a" in
    --dry-run|-n) DRY_RUN=1 ;;
    *) usage ;;
  esac
done

case "$cmd" in
  install)   need_jq; do_install ;;
  uninstall) need_jq; do_uninstall ;;
  status)    do_status ;;
  ""|-h|--help|help) usage 0 ;;
  *) usage ;;
esac
