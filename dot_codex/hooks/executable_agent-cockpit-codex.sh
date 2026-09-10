#!/bin/bash
# Codex hook → Hammerspoon 에이전트 콕핏 어댑터.
#   agent-cockpit-codex.sh idle|working|done|waiting|gone
# Codex 는 hook JSON 을 stdin 으로 주고, 성공 응답으로 stdout 에 JSON 을 요구한다.
# 실제 전송은 Claude Code 와 같은 ~/.claude/hooks/agent-cockpit.sh 가 맡고, 여기서는
# 에이전트 종류(codex)와 표시 라벨만 얹는다.
INPUT="$(cat 2>/dev/null || true)"
COCKPIT_AGENT=codex COCKPIT_DEBUG="${COCKPIT_DEBUG:-1}" COCKPIT_INPUT="$INPUT" NOTIFY_AGENT_LABEL="${NOTIFY_AGENT_LABEL:-코덱스}" \
  bash "$HOME/.claude/hooks/agent-cockpit.sh" "${1:-done}" >/dev/null 2>&1 </dev/null || true
printf '{}\n'
exit 0
