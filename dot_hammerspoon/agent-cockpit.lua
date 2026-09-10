-- agent-cockpit.lua — Claude Code · Codex 세션 상태 콕핏
--
-- ~/.claude/hooks/agent-cockpit.sh (Claude Code) 와 ~/.codex/hooks/agent-cockpit-codex.sh (Codex) 가
-- 보내는 hammerspoon://agent?state=…&agent=… 이벤트를 받아
--   · 세션 목록을 오버레이에 번호와 함께 표시하고 (대기 → 완료 → 작업 중 → 대기 없음 순)
--   · Hyper(F18)+숫자 로 그 세션의 터미널 탭으로 점프하고
--   · 에이전트가 일하는 동안(working) 시스템 잠자기를 막고
--   · 메뉴바에 상태 개수를 보여준다.
-- 오버레이 스타일(폭·헤더·행·색·드래그)은 overlay-style.lua 에서 가져온다 (Agent Shortcuts 와 공용).
--
-- 키 (hyper.lua 의 F18 모달 사용):
--   hyper+`        : 가장 급한 세션(대기 중 가장 오래된 것, 없으면 1번)으로 점프
--   hyper+1 ~ 9    : 오버레이 n번 세션으로 점프
--   hyper+0        : 오버레이 숨김/표시
--   hyper+shift+0  : 목록 전체 비우기
--
-- URL (Karabiner shell_command 등 외부 연동용):
--   hammerspoon://agent-jump?i=N   n번 세션으로 점프 (i 생략 시 가장 급한 세션)
--   hammerspoon://agent-toggle     오버레이 숨김/표시
--   hammerspoon://agent-clear      목록 비우기
--   hammerspoon://agent-move?x=&y= 오버레이 위치 지정 (파라미터 없으면 기본 위치로)
--   hammerspoon://agent-diag       진단 정보를 상태 파일에 기록
--   hammerspoon://agent-scan       실행 중 claude/codex 프로세스 재스캔 (기본 60초마다 자동, hyper+shift+`)
--
-- 세션 소스는 둘이다. 훅 이벤트(상태 변화·알림 메시지·창 기억)와 프로세스 스캔(bin/agent-scan.py,
-- 터미널에 붙은 claude/codex 전부·Claude 자체 상태·세션 이름·tty). 두 소스는 세션 ID 로 병합된다.
--
-- 오버레이 헤더를 드래그해 옮길 수 있고, 위치는 상태 파일에 저장돼 리로드 뒤에도 유지된다.
-- 기본 위치는 Agent Shortcuts 패널 바로 아래.
-- 상태 파일: ~/.hammerspoon/agent-cockpit.state.json (리로드 뒤 복원, 외부 도구가 읽을 수 있음)

local S = require("overlay-style")

local M = {}
M.version = "2026-09-10.3"   -- 로드된 코드 판별용 (상태 파일 version 필드)

local config = {
  stateFile = os.getenv("HOME") .. "/.hammerspoon/agent-cockpit.state.json",
  ttlSeconds = 24 * 3600,          -- 이보다 오래 갱신 없는 세션은 버림
  overlay = {
    autoShow = true,               -- 주목할 세션(대기·완료)이 생기면 자동 표시
    autoHide = true,               -- 주목할 세션이 없으면 자동 숨김 (hyper+0 으로 고정하면 유지)
    stackBelowShortcuts = true,    -- 기본 위치를 Agent Shortcuts 패널 아래로
    offsetY = 300,                 -- Shortcuts 패널 위치를 모를 때의 기본 y
  },
  scan = {                         -- 실행 중인 claude/codex 프로세스를 주기적으로 스캔해 목록을 채운다
    enabled = true,
    intervalSec = 60,
    python = "/usr/bin/python3",
    script = os.getenv("HOME") .. "/.hammerspoon/bin/agent-scan.py",
    maxRows = 24,                  -- 오버레이에 그릴 최대 행 (넘치면 "외 n개" 표시)
  },
  caffeinate = true,               -- working 세션이 있으면 systemIdle 잠자기 방지
  menubar = true,                  -- 메뉴바 항목 (노치 Mac 에서 항목이 많으면 숨겨질 수 있음)
  terminals = {                    -- TERM_PROGRAM → bundle id
    ghostty = "com.mitchellh.ghostty",
    kitty = "net.kovidgoyal.kitty",
    WezTerm = "com.github.wez.wezterm",
    ["iTerm.app"] = "com.googlecode.iterm2",
    Apple_Terminal = "com.apple.Terminal",
  },
  defaultTerminal = "com.mitchellh.ghostty",
  tmuxBin = "/opt/homebrew/bin/tmux",
  herdrBin = "/opt/homebrew/bin/herdr",
}

local sessions = {}      -- key → entry
local canvas = nil
local menubar = nil
local pinned = false     -- 비어 있어도 계속 표시
local userHidden = false -- 사용자가 hyper+0 으로 숨긴 상태 (새 대기 이벤트가 오면 해제)
local overlayPos = nil   -- 사용자가 헤더를 드래그해 옮긴 위치 {x,y}. nil 이면 기본 위치
local hyperBound = false
local lastAction = nil   -- 마지막 점프/토글 기록 (진단용)
local stopDragging = nil
local log = hs.logger.new("cockpit", "info")

local STATE_ORDER = { waiting = 1, done = 2, working = 3, idle = 4 }
local STATE_ICON = { waiting = "⏳", done = "✅", working = "⚙︎", idle = "·" }
local AGENT_TAG = { claude = "CC", codex = "CX", kiro = "KR", hermes = "HM" }

-- ---------------------------------------------------------------- 유틸
local function now() return os.time() end

local function ago(t)
  local d = now() - (t or now())
  if d < 60 then return d .. "s" end
  if d < 3600 then return math.floor(d / 60) .. "m" end
  return string.format("%.1fh", d / 3600)
end

local function agentTag(e) return AGENT_TAG[e.agent or "claude"] or string.upper(string.sub(e.agent or "?", 1, 2)) end

local function isTerminalBundle(b)
  if not b then return false end
  for _, v in pairs(config.terminals) do if v == b then return true end end
  return b == config.defaultTerminal
end

local function saveState()
  local list = {}
  for _, e in pairs(sessions) do table.insert(list, e) end
  local mb = nil
  if menubar then
    local okv, vis = pcall(function() return menubar:isInMenuBar() end)
    local okf, fr = pcall(function() return menubar:frame() end)
    mb = { inMenuBar = (okv and vis) or false, title = menubar:title() }
    if okf and fr then mb.frame = { x = fr.x, y = fr.y, w = fr.w, h = fr.h } end
  end
  local okEnc, payload = pcall(hs.json.encode, {
    savedAt = now(), version = M.version, pinned = pinned, userHidden = userHidden, overlayPos = overlayPos,
    hyperBound = hyperBound, lastAction = lastAction, overlayShowing = canvas and canvas:isShowing() or false,
    menubar = mb, sessions = list,
  }, true)
  if not okEnc then log.e("state encode failed: " .. tostring(payload)); return end
  local tmp = config.stateFile .. ".tmp"
  local f = io.open(tmp, "w")
  if f then f:write(payload); f:close(); os.rename(tmp, config.stateFile) end
end

local function loadState()
  local f = io.open(config.stateFile, "r")
  if not f then return end
  local raw = f:read("*a"); f:close()
  local ok, data = pcall(hs.json.decode, raw)
  if not ok or type(data) ~= "table" then return end
  for _, e in ipairs(data.sessions or {}) do
    if e.key and (now() - (e.updatedAt or 0)) < config.ttlSeconds then sessions[e.key] = e end
  end
  pinned = data.pinned or false
  userHidden = data.userHidden or false
  if type(data.overlayPos) == "table" and data.overlayPos.x and data.overlayPos.y then overlayPos = data.overlayPos end
end

local function note(msg) lastAction = { at = now(), msg = msg }; log.i(msg); saveState() end

-- 오버레이 표시·점프 번호 순서: waiting(오래된 것부터) → done(최근 것부터) → working → idle
local function visibleList()
  local list = {}
  for _, e in pairs(sessions) do table.insert(list, e) end
  table.sort(list, function(a, b)
    if a.state ~= b.state then return STATE_ORDER[a.state] < STATE_ORDER[b.state] end
    if a.state == "waiting" then return (a.stateSince or 0) < (b.stateSince or 0) end
    return (a.stateSince or 0) > (b.stateSince or 0)
  end)
  return list
end

-- 주목 대상(waiting·done) 만
local function attentionList()
  local list = {}
  for _, e in ipairs(visibleList()) do
    if e.state == "waiting" or e.state == "done" then table.insert(list, e) end
  end
  return list
end

local function counts()
  local c = { waiting = 0, done = 0, working = 0, idle = 0 }
  for _, e in pairs(sessions) do c[e.state] = (c[e.state] or 0) + 1 end
  return c
end

-- ---------------------------------------------------------------- 점프
local function shellQuote(s) return "'" .. tostring(s):gsub("'", "'\\''") .. "'" end

local function runShell(cmd)
  hs.task.new("/bin/bash", function(code, out, err)
    if code ~= 0 then log.w("shell rc=" .. code .. " " .. (err or "") .. (out or "")) end
  end, { "-lc", cmd }):start()
end

local function jumpTo(e)
  if not e then return end
  local bundle = e.winApp or config.terminals[e.term or ""] or config.defaultTerminal
  local win = e.winId and hs.window.get(e.winId) or nil
  if win then
    win:focus()                      -- Ghostty 탭은 창 단위로 노출되므로 해당 탭이 앞으로 온다
    note(string.format("focus win %d (%s)", e.winId, tostring(win:title())))
  else
    hs.application.launchOrFocusByBundleID(bundle)
  end

  if e.herdrPane and e.herdrPane ~= "" then
    -- herdr 서버가 있으면 에이전트 포커스, 없으면 조용히 실패
    runShell(string.format("%s agent focus %s 2>/dev/null || %s pane focus %s 2>/dev/null || true",
      config.herdrBin, shellQuote(e.herdrPane), config.herdrBin, shellQuote(e.herdrPane)))
  end
  if e.tmuxPane and e.tmuxPane ~= "" then
    local sockOpt = (e.tmuxSock and e.tmuxSock ~= "") and ("-S " .. shellQuote(e.tmuxSock)) or ""
    local t = shellQuote(e.tmuxPane)
    -- 첫 클라이언트를 해당 pane 의 세션으로 전환한 뒤 창·pane 선택
    runShell(string.format(
      "T=%s; C=$(%s %s list-clients -F '#{client_name}' 2>/dev/null | head -1); " ..
      "[ -n \"$C\" ] && %s %s switch-client -c \"$C\" -t %s 2>/dev/null; " ..
      "%s %s select-window -t %s 2>/dev/null; %s %s select-pane -t %s 2>/dev/null; true",
      config.tmuxBin, config.tmuxBin, sockOpt, config.tmuxBin, sockOpt, t,
      config.tmuxBin, sockOpt, t, config.tmuxBin, sockOpt, t))
  end

  if e.state == "done" then      -- 결과를 확인한 것으로 보고 목록에서 내림
    sessions[e.key] = nil
    M.refresh()
  end
  hs.alert.show("→ " .. ((e.label or "") ~= "" and (e.label .. " ") or "") .. (e.project or "?"), 0.8)
end

-- ---------------------------------------------------------------- 오버레이
local function defaultPosition()
  if config.overlay.stackBelowShortcuts then
    local f = hs.settings.get("agentShortcuts.overlayFrame")
    if type(f) == "table" and f.x and f.y and f.h and S.onAnyScreen(f.x, f.y, S.width, S.headerHeight) then
      return { x = f.x, y = f.y + f.h + S.margin.gap }
    end
  end
  return S.defaultTopRight(config.overlay.offsetY)
end

local function overlayFrame(rows)
  local h = S.height(rows)
  local pos = (overlayPos and S.onAnyScreen(overlayPos.x, overlayPos.y, S.width, S.headerHeight)) and overlayPos or defaultPosition()
  return { x = pos.x, y = pos.y, w = S.width, h = h }
end

local function redrawOverlay()
  local list = visibleList()
  local attention = #attentionList()
  local frame = overlayFrame(#list)
  if not canvas then
    canvas = S.newCanvas(frame)
    stopDragging = S.attachDrag(canvas, function(pos)
      overlayPos = pos
      saveState()
    end)
  else
    canvas:frame(frame)
  end

  local c = counts()
  local hint = string.format("세션 %d  ·  ⏳%d ✅%d ⚙︎%d  ·  hyper+n 점프 · hyper+0 숨김", #list, c.waiting, c.done, c.working)
  local maxRows = config.scan.maxRows or 24
  local overflow = 0
  if #list > maxRows then overflow = #list - maxRows + 1; list = { table.unpack(list, 1, maxRows - 1) } end
  frame = overlayFrame(#list + (overflow > 0 and 1 or 0)); canvas:frame(frame)
  canvas:replaceElements(table.unpack(S.baseElements("Agent Cockpit", hint)))

  if #list == 0 then
    canvas:appendElements({
      type = "text", frame = { x = S.col.key + 2, y = S.rowY(1) + 6, w = S.width - 32, h = 20 },
      text = "추적 중인 세션 없음", textColor = S.colors.muted, textSize = S.sizes.text,
    })
  end

  for i, e in ipairs(list) do
    local y = S.rowY(i)
    local detail = ((e.label or "") ~= "" and (e.label .. " ") or "") .. (e.project or "?")
    local meta = {}
    if e.name and e.name ~= "" then table.insert(meta, e.name) end
    if e.tty then table.insert(meta, e.tty) end
    table.insert(meta, ago(e.stateSince))
    if e.msg and e.msg ~= "" then table.insert(meta, e.msg) end
    local right = table.concat(meta, "  ·  ")
    local dim = (e.state == "working" or e.state == "idle") and 0.6 or 1
    local stateColor = S.colors[e.state] or S.colors.idle
    local badgeColor = (e.agent == "codex") and S.colors.badgeCodex or S.colors.badgeClaude
    canvas:appendElements({
      type = "text", frame = { x = S.col.key, y = y + 7, w = 54, h = 20 },
      text = string.format("%d %s", i, STATE_ICON[e.state]), textColor = stateColor, textFont = S.fonts.key, textSize = S.sizes.key,
    }, {
      type = "text", frame = { x = S.col.key + 56, y = y + 8, w = 30, h = 18 },
      text = agentTag(e), textColor = { red = badgeColor.red, green = badgeColor.green, blue = badgeColor.blue, alpha = dim },
      textFont = S.fonts.mono, textSize = S.sizes.badge,
    }, {
      type = "text", frame = { x = S.col.text, y = y + 6, w = 200, h = 21 },
      text = detail, textColor = { white = 1, alpha = 0.92 * dim }, textSize = S.sizes.text, textLineBreak = "truncateTail",
    }, {
      type = "text", frame = { x = S.col.text + 206, y = y + 7, w = S.width - (S.col.text + 206) - 14, h = 20 },
      text = right, textColor = { white = 0.72, alpha = dim }, textSize = S.sizes.meta, textLineBreak = "truncateTail",
    })
  end

  if overflow > 0 then
    canvas:appendElements({
      type = "text", frame = { x = S.col.key + 2, y = S.rowY(#list + 1) + 6, w = S.width - 32, h = 20 },
      text = string.format("… 외 %d개 (메뉴바에서 전체 보기)", overflow), textColor = S.colors.muted, textSize = S.sizes.meta,
    })
  end
  canvas:appendElements(S.dragHandleElement())

  local shouldShow = (not userHidden) and (pinned or (config.overlay.autoShow and attention > 0))
  if shouldShow then canvas:show() elseif config.overlay.autoHide or userHidden then canvas:hide() end
end

-- ---------------------------------------------------------------- 메뉴바
local function updateMenubar()
  if not menubar then return end
  local c = counts()
  local parts = {}
  if c.waiting > 0 then table.insert(parts, "⏳" .. c.waiting) end
  if c.done > 0 then table.insert(parts, "✅" .. c.done) end
  if c.working > 0 then table.insert(parts, "⚙︎" .. c.working) end
  menubar:setTitle(#parts > 0 and table.concat(parts, " ") or "🤖")
  menubar:setMenu(function()
    local items = {}
    for _, e in ipairs(visibleList()) do
      table.insert(items, {
        title = string.format("%s [%s] %s%s  (%s, %s)", STATE_ICON[e.state], agentTag(e),
          (e.label or "") ~= "" and (e.label .. " ") or "", e.project or "?", e.state, ago(e.stateSince)),
        fn = function() jumpTo(e) end,
      })
    end
    if #items == 0 then table.insert(items, { title = "추적 중인 세션 없음", disabled = true }) end
    table.insert(items, { title = "-" })
    table.insert(items, { title = (canvas and canvas:isShowing()) and "오버레이 숨김" or "오버레이 표시", fn = M.toggleOverlay })
    table.insert(items, { title = "지금 스캔", fn = runScan })
    table.insert(items, { title = "목록 비우기", fn = M.clear })
    table.insert(items, { title = "기본 위치로", fn = function() overlayPos = nil; M.refresh() end })
    table.insert(items, { title = "상태 파일 열기", fn = function() hs.execute("open -R " .. shellQuote(config.stateFile)) end })
    return items
  end)
end

-- ---------------------------------------------------------------- 카페인
local function updateCaffeine()
  if not config.caffeinate then return end
  local want = counts().working > 0
  if hs.caffeinate.get("systemIdle") ~= want then
    hs.caffeinate.set("systemIdle", want, true)
    log.i("caffeinate systemIdle=" .. tostring(want))
  end
end

-- ---------------------------------------------------------------- 프로세스 스캔
local scanning = false
local function applyScan(list)
  local seen = {}
  local changed = false
  for _, p in ipairs(list) do
    local key = p.key
    seen[key] = true
    local e = sessions[key]
    if not e then
      e = { key = key, createdAt = now(), stateSince = p.started or now(), label = "" }
      sessions[key] = e
      changed = true
    end
    e.agent = p.agent or e.agent
    e.pid = p.pid; e.tty = p.tty; e.startedAt = p.started
    e.cwd = p.cwd or e.cwd
    e.project = p.project or e.project
    e.name = p.name
    if (not e.term or e.term == "") and p.term then e.term = p.term end
    e.scannedAt = now()
    -- 훅이 준 waiting/done 은 유지. 그 외에는 Claude 의 자체 상태(busy → working, 나머지 → idle)를 따른다.
    if e.state ~= "waiting" and e.state ~= "done" then
      local st = (p.status == "busy") and "working" or "idle"
      if e.state ~= st then e.state = st; e.stateSince = (e.state == "idle" and p.started) or now(); changed = true end
    end
    e.updatedAt = now()
  end
  -- 스캔에서 사라진 프로세스 기반 세션은 종료된 것으로 본다 (훅만으로 생긴 세션도 2분 넘게 스캔에 안 보이면 정리)
  for k, e in pairs(sessions) do
    if not seen[k] then
      if e.scannedAt or (now() - (e.createdAt or 0)) > 120 then sessions[k] = nil; changed = true end
    end
  end
  if changed then M.refresh() else saveState() end
end

local function runScan()
  if scanning or not config.scan.enabled then return end
  scanning = true
  hs.task.new(config.scan.python, function(code, out, err)
    scanning = false
    if code ~= 0 then log.w("scan rc=" .. code .. " " .. (err or "")); return end
    local ok, list = pcall(hs.json.decode, out)
    if ok and type(list) == "table" then applyScan(list) else log.w("scan parse failed") end
  end, { config.scan.script }):start()
end
M.scan = runScan

-- ---------------------------------------------------------------- 이벤트 처리
local function pruneStale()
  local changed = false
  for k, e in pairs(sessions) do
    if (now() - (e.updatedAt or 0)) > config.ttlSeconds then sessions[k] = nil; changed = true end
  end
  if changed then M.refresh() end
end

local function nonEmpty(v) return v ~= nil and v ~= "" end

local function handleEvent(params)
  local state = params.state or "done"
  local key = params.session or params.cwd or params.project or "?"
  if state == "gone" then
    sessions[key] = nil
  else
    local e = sessions[key] or { key = key, createdAt = now() }
    if e.state ~= state then
      e.stateSince = now()
      if state == "waiting" then userHidden = false end   -- 확인이 필요한 세션이 생기면 다시 보인다
    end
    e.state = (STATE_ORDER[state] and state) or "done"
    e.project = params.project or e.project or "?"
    e.cwd = params.cwd or e.cwd
    if nonEmpty(params.term) then e.term = params.term end
    if nonEmpty(params.tmux_sock) then e.tmuxSock = params.tmux_sock end
    if nonEmpty(params.tmux_pane) then e.tmuxPane = params.tmux_pane end
    if nonEmpty(params.herdr_pane) then e.herdrPane = params.herdr_pane end
    e.label = params.label or e.label or ""
    e.msg = (state == "waiting") and (params.msg or "") or ""
    e.ntype = params.ntype
    e.agent = params.agent or e.agent or "claude"
    e.updatedAt = now()
    if state == "idle" or state == "working" then
      -- 프롬프트를 제출한 직후라 포커스된 터미널 창이 이 세션의 탭일 확률이 높다
      local fw = hs.window.focusedWindow()
      local app = fw and fw:application()
      if fw and app and isTerminalBundle(app:bundleID()) and (fw:id() or 0) > 0 then
        e.winId = fw:id(); e.winTitle = fw:title(); e.winApp = app:bundleID()
      end
    end
    sessions[key] = e
  end
  M.refresh()
  if state == "idle" then hs.timer.doAfter(2, runScan) end   -- 새 세션은 잠시 뒤 스캔해 pid·이름을 붙인다
end

function M.refresh()
  redrawOverlay()
  updateMenubar()
  updateCaffeine()
  saveState()
end

function M.toggleOverlay()
  if canvas and canvas:isShowing() then
    userHidden = true; pinned = false
    canvas:hide()
    hs.alert.show("Agent Cockpit 숨김 (hyper+0 로 다시 표시)", 0.9)
  else
    userHidden = false; pinned = true
    redrawOverlay()
    hs.alert.show("Agent Cockpit 표시", 0.6)
  end
  saveState()
end

function M.clear()
  sessions = {}
  M.refresh()
  hs.alert.show("Agent Cockpit 비움", 0.6)
end

function M.jumpFirst()
  local e = attentionList()[1] or visibleList()[1]
  if not e then hs.alert.show("Agent Cockpit: 추적 중인 세션 없음", 0.9); note("jumpFirst → 없음"); return end
  note("jumpFirst → " .. (e.project or "?")); jumpTo(e)
end

function M.jumpIndex(i)
  local list = visibleList()
  local e = list[i]
  if not e then
    hs.alert.show(string.format("Agent Cockpit: %d번 세션 없음 (현재 %d개)", i, #list), 0.9)
    note(string.format("jump i=%d → 없음 (%d개)", i, #list)); return
  end
  note(string.format("jump i=%d → %s [%s]", i, e.project or "?", e.state)); jumpTo(e)
end

-- 현재 오버레이 프레임·표시 여부 (진단용)
function M.frame()
  if not canvas then return nil end
  local f = canvas:frame()
  return { x = f.x, y = f.y, w = f.w, h = f.h, showing = canvas:isShowing() }
end

function M.stop()
  if stopDragging then stopDragging(); stopDragging = nil end
  if canvas then canvas:delete(); canvas = nil end
  if menubar then menubar:delete(); menubar = nil end
  if M.timer then M.timer:stop(); M.timer = nil end
  if M.scanTimer then M.scanTimer:stop(); M.scanTimer = nil end
  return M
end

function M.start(overrides)
  M.stop()
  for k, v in pairs(overrides or {}) do
    if type(v) == "table" and type(config[k]) == "table" then for kk, vv in pairs(v) do config[k][kk] = vv end else config[k] = v end
  end
  loadState()
  if config.menubar then menubar = hs.menubar.new() end

  hs.urlevent.bind("agent", function(_, params) handleEvent(params or {}) end)
  hs.urlevent.bind("agent-clear", function() M.clear() end)
  hs.urlevent.bind("agent-toggle", function() M.toggleOverlay() end)
  hs.urlevent.bind("agent-diag", function()
    local wins = {}
    for term, bundle in pairs(config.terminals) do
      for _, app in ipairs(hs.application.applicationsForBundleID(bundle)) do
        for _, w in ipairs(app:allWindows()) do table.insert(wins, { term = term, title = w:title(), id = w:id(), std = w:isStandard() }) end
      end
    end
    local fw = hs.window.focusedWindow()
    lastAction = { at = now(), msg = "diag", termWindows = wins, focused = fw and (fw:application():name() .. " | " .. tostring(fw:title())) or nil,
      shortcutsFrame = hs.settings.get("agentShortcuts.overlayFrame") }
    saveState(); hs.alert.show("cockpit diag → state file", 0.6)
  end)
  hs.urlevent.bind("agent-focus-win", function(_, params)   -- 테스트용: hammerspoon://agent-focus-win?id=N
    local id = tonumber((params or {}).id or ""); local w = id and hs.window.get(id)
    if w then w:focus(); note("focus-win " .. id .. " → " .. tostring(w:title())) else note("focus-win 없음 " .. tostring(id)) end
    local fw = hs.window.focusedWindow(); lastAction.focusedAfter = fw and fw:title() or nil; saveState()
  end)
  hs.urlevent.bind("agent-move", function(_, params)          -- hammerspoon://agent-move?x=100&y=50 / 파라미터 없으면 기본 위치로
    local x, y = tonumber((params or {}).x or ""), tonumber((params or {}).y or "")
    overlayPos = (x and y) and { x = x, y = y } or nil
    M.refresh()
  end)
  hs.urlevent.bind("agent-scan", function() runScan() end)   -- 실행 중 프로세스 재스캔
  hs.urlevent.bind("agent-jump", function(_, params)          -- hammerspoon://agent-jump?i=1 (i 생략 시 가장 급한 세션)
    local i = tonumber((params or {}).i or "")
    if i then M.jumpIndex(i) else M.jumpFirst() end
  end)

  -- hyper.lua 의 F18 모달에 바인딩 (init.lua 가 hyper.install('F18') 을 먼저 호출해야 함)
  local ok, hyper = pcall(require, "hyper")
  if ok and hyper and hyper.hyperMode then
    hyper.bindKey("`", M.jumpFirst)
    for i = 1, 9 do hyper.bindKey(tostring(i), function() M.jumpIndex(i) end) end
    hyper.bindKey("0", M.toggleOverlay)
    hyper.bindShiftKey("0", M.clear)
    hyper.bindShiftKey("`", runScan)
    hyperBound = true
  else
    log.w("hyper 모듈 없음: 단축키 대신 hammerspoon://agent-* URL 만 동작")
  end

  M.timer = hs.timer.doEvery(300, pruneStale)
  if config.scan.enabled then
    M.scanTimer = hs.timer.doEvery(config.scan.intervalSec, runScan)
    hs.timer.doAfter(1, runScan)
  end
  M.refresh()
  log.i("agent-cockpit " .. M.version .. " 시작")
  return M
end

return M
