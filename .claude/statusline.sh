#!/bin/bash
# ccstatusline - plain text status line for Claude Code

input=$(cat)

# ---------------------------------------------------------------------------
# JSON parsing helper
# ---------------------------------------------------------------------------
parse() {
  local field="$1"
  local default="${2:-}"
  if command -v jq &>/dev/null; then
    echo "$input" | jq -r "${field} // \"${default}\""
  else
    local py
    py=$(command -v python3 || command -v python || true)
    [ -z "$py" ] && { echo "$default"; return; }
    echo "$input" | "$py" -c "
import sys, json
data = json.load(sys.stdin)
keys = '${field}'.strip('.').split('.')
val = data
for k in keys:
    val = val.get(k) if isinstance(val, dict) else None
    if val is None:
        break
print(val if val is not None else '${default}')
" 2>/dev/null || echo "$default"
  fi
}

# ---------------------------------------------------------------------------
# Data extraction
# ---------------------------------------------------------------------------
MODEL=$(parse '.model.display_name' 'Claude')

DIR=$(parse '.workspace.current_dir' '.')
DIRNAME="${DIR##*/}"
[ -z "$DIRNAME" ] && DIRNAME="/"

REM=$(parse '.context_window.remaining_percentage' '')
if [ -n "$REM" ] && [ "$REM" != "null" ]; then
  REM_INT=${REM%%.*}
  CTX_INT=$((100 - REM_INT))
else
  REM_INT=""
  CTX_INT=""
fi

RL5_RAW=$(parse '.rate_limits.five_hour.used_percentage' '')
RL7_RAW=$(parse '.rate_limits.seven_day.used_percentage' '')
RL5_RESET=$(parse '.rate_limits.five_hour.resets_at' '')
RL7_RESET=$(parse '.rate_limits.seven_day.resets_at' '')
[ "$RL5_RAW" = "null" ] && RL5_RAW=""
[ "$RL7_RAW" = "null" ] && RL7_RAW=""
[ "$RL5_RESET" = "null" ] && RL5_RESET=""
[ "$RL7_RESET" = "null" ] && RL7_RESET=""

VIM_MODE=$(parse '.vim.mode' '')
[ "$VIM_MODE" = "null" ] && VIM_MODE=""

# git branch
BRANCH=""
if [ -d "$DIR/.git" ] || git -C "$DIR" rev-parse --git-dir &>/dev/null 2>&1; then
  BRANCH=$(GIT_OPTIONAL_LOCKS=0 git -C "$DIR" branch --show-current 2>/dev/null || true)
  if [ -n "$BRANCH" ]; then
    if ! GIT_OPTIONAL_LOCKS=0 git -C "$DIR" diff --quiet HEAD 2>/dev/null; then
      BRANCH="${BRANCH} *"
    fi
  fi
fi

# ---------------------------------------------------------------------------
# Build plain text output
# ---------------------------------------------------------------------------
declare -a PARTS

# Vim mode
if [ -n "$VIM_MODE" ]; then
  if [ "$VIM_MODE" = "NORMAL" ]; then
    PARTS+=("[N]")
  else
    PARTS+=("[I]")
  fi
fi

# Directory
PARTS+=("${DIRNAME}")

# Git branch
if [ -n "$BRANCH" ]; then
  PARTS+=("(${BRANCH})")
fi

# Model
PARTS+=("${MODEL}")

# ASCII bar helper: ascii_bar <percentage> <width>
ascii_bar() {
  local pct="${1:-0}" width="${2:-10}"
  local filled=$(( pct * width / 100 ))
  local empty=$(( width - filled ))
  local bar=""
  for ((i=0; i<filled; i++)); do bar+="█"; done
  for ((i=0; i<empty; i++)); do bar+="░"; done
  printf '%s' "$bar"
}

# Format epoch to HH:MM local time
format_reset() {
  local raw="$1"
  [ -z "$raw" ] && return 1
  local epoch="${raw%%.*}"
  [[ "$epoch" =~ ^[0-9]+$ ]] || return 1
  date -d "@$epoch" '+%H:%M' 2>/dev/null \
    || date -r "$epoch" '+%H:%M' 2>/dev/null \
    || python3 -c "import datetime; print(datetime.datetime.fromtimestamp($epoch).strftime('%H:%M'))" 2>/dev/null
}

# Line 2: usage bars + reset times
declare -a LINE2_PARTS

# Context window
if [ -n "$CTX_INT" ]; then
  LINE2_PARTS+=("context[$(ascii_bar "$CTX_INT")]${CTX_INT}%")
fi

# Rate limits
if [ -n "$RL5_RAW" ]; then
  RL5_INT=${RL5_RAW%%.*}
  LINE2_PARTS+=("5h[$(ascii_bar "$RL5_INT")]${RL5_INT}%")
fi
if [ -n "$RL7_RAW" ]; then
  RL7_INT=${RL7_RAW%%.*}
  LINE2_PARTS+=("7d[$(ascii_bar "$RL7_INT")]${RL7_INT}%")
fi

# Reset times
declare -a RESET_PARTS
if [ -n "$RL5_RESET" ]; then
  R5=$(format_reset "$RL5_RESET")
  [ -n "$R5" ] && RESET_PARTS+=("5h@${R5}")
fi
if [ -n "$RL7_RESET" ]; then
  R7=$(format_reset "$RL7_RESET")
  [ -n "$R7" ] && RESET_PARTS+=("7d@${R7}")
fi

if [ ${#RESET_PARTS[@]} -gt 0 ]; then
  LINE2_PARTS+=("| resets at ${RESET_PARTS[*]}")
fi

# ---------------------------------------------------------------------------
# Output: two lines
# ---------------------------------------------------------------------------
LINE1="${PARTS[*]}"
LINE2="${LINE2_PARTS[*]}"

printf '%s\n%s' "$LINE1" "$LINE2"
