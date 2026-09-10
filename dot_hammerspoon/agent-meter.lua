-- agent-meter.lua — agentmeter 사용량 패널
--
-- agentmeter(~/project/agentmeter) 가 `agentmeter web --live --port 9999` 로 띄우는 대시보드의
-- /api/dashboard JSON 을 주기적으로 받아, Agent Shortcuts·Agent Cockpit 과 같은 스타일의 오버레이에
-- 에이전트별 한도 소진율을 차트로 그린다. 서버에 접속할 수 없으면 실행할 명령을 보여 준다.
--
-- 데이터 형식(agentmeter src/adapters/presentation/web.rs):
--   panes[] { name, display, origin, source, error, reset_credits{label, expiry_label}, meters[] }
--   meter { title, delta, used_percent, label, level(normal|warning|critical), emphasized, reset,
--           window{started_at, resets_at}, quota_summary, chart{ area_path, line_path, markers[{x, kind}] } }
--   chart 경로는 viewBox "0 0 1000 48" 좌표계의 SVG path("M x y L x y … Z").
--   x 는 창 시작~리셋을 0~1000 으로, y 는 47 - 소진율 × 0.43. markers 는 hour/midnight 경계의 x.
--   hs.canvas 에는 path 요소가 없어 점 목록으로 파싱해 segments(면·선)로 그린다.
--
-- 단축키: hyper+u 표시/숨김, hyper+shift+u 즉시 새로고침
-- URL:   hammerspoon://agentmeter-toggle · agentmeter-refresh · agentmeter-move?x=&y= (파라미터 없으면 기본 위치)

local S = require("overlay-style")
local log = hs.logger.new("agent-meter", "info")

local M = {}
M.version = "2026-09-10.2"

M.config = {
  url = "http://localhost:9999/api/dashboard",
  startCommand = "agentmeter web --live --port 9999",
  pollSec = 30,            -- next_refresh_at 을 읽지 못했을 때의 기본 주기
  retrySec = 20,           -- 접속 실패 시 재시도 주기
  showOnStart = true,
  offsetY = 620,           -- 기본 위치: Cockpit 아래 → Shortcuts 아래 → 주 화면 우상단 offsetY
  chartHeight = 40,
  compactEmpty = true,     -- 0% 이고 차트가 없는 meter 는 한 줄로
}
local config = M.config

-- agentmeter 웹 UI 팔레트 (web.html :root) — 두 화면의 색이 같은 뜻을 갖도록 그대로 쓴다
local C = {
  normal   = { hex = "#9290d2" },
  warning  = { hex = "#ae9559" },
  critical = { hex = "#bd6974" },
  accent   = { hex = "#79999a" },
  name     = { hex = "#cbd1de" },
  areaFill = { red = 121 / 255, green = 153 / 255, blue = 154 / 255, alpha = 0.55 },
  grid     = { white = 1, alpha = 0.10 },
  midnight = { white = 1, alpha = 0.30 },
  hour     = { white = 1, alpha = 0.18 },
  track    = { white = 1, alpha = 0.10 },
  timeFill = { white = 0.78, alpha = 0.75 },
  chartBg  = { white = 1, alpha = 0.03 },
  cmdBg    = { white = 1, alpha = 0.08 },
}
local LEVEL = { normal = C.normal, warning = C.warning, critical = C.critical }

-- 레이아웃 (폭은 S.width, 좌우 여백 S.col.key)
local L = {
  x = S.col.key, w = S.width - 2 * S.col.key,
  paneHead = 24, errLine = 16, meter = 92, compact = 20, credits = 16, paneGap = 8,
}

local POS_KEY = "agentMeter.overlayPosition"
local state = { data = nil, offline = nil, canvas = nil, pos = nil, timer = nil, userHidden = false, stopDrag = nil }

-- ---------------------------------------------------------------- 유틸
local function txt(t, x, y, w, h, color, size, opts)
  local e = { type = "text", text = t or "", frame = { x = x, y = y, w = w, h = h },
    textColor = color, textSize = size, textLineBreak = "truncateTail" }
  if opts then for k, v in pairs(opts) do e[k] = v end end
  return e
end

local function hhmm(iso) return iso and iso:match("T(%d%d:%d%d)") or "?" end

-- ISO 8601 을 로컬 시각으로 해석. 서버(같은 Mac)와 오프셋이 같다는 전제이며, 결과는 대기 시간 계산에만 쓰고 클램프한다.
local function isoToTime(iso)
  if type(iso) ~= "string" then return nil end
  local Y, m, d, H, Mi, Sec = iso:match("(%d+)%-(%d+)%-(%d+)T(%d+):(%d+):(%d+)")
  if not Y then return nil end
  return os.time({ year = tonumber(Y), month = tonumber(m), day = tonumber(d), hour = tonumber(H), min = tonumber(Mi), sec = tonumber(Sec) })
end

-- "Resets Sep 16 at 1:00am (Asia/Seoul)" 의 시간대 접미는 응답의 timezone 과 같으면 뗀다 (좁은 패널에서 자리 확보)
local function stripTz(text, tz)
  if type(text) ~= "string" then return "" end
  if tz and tz ~= "" then
    local suffix = " (" .. tz .. ")"
    if text:sub(-#suffix) == suffix then return text:sub(1, -#suffix - 1) end
  end
  return text
end

local function leftLabel(resetsAt)
  local r = math.max(0, math.floor(resetsAt - os.time()))
  if r == 0 then return "reset pending" end
  local d, h, mnt = math.floor(r / 86400), math.floor(r % 86400 / 3600), math.floor(r % 3600 / 60)
  if d > 0 then return string.format("%dd %dh left", d, h) end
  if h > 0 then return string.format("%dh %dm left", h, mnt) end
  return string.format("%dm left", mnt)
end

-- "M x y L x y … Z" → { {pts = {{x,y},…}, closed = bool}, … }  (M 마다 새 서브패스)
local function parsePath(d)
  local subs, cur = {}, nil
  for cmd, rest in (d or ""):gmatch("([MLZ])([^MLZ]*)") do
    if cmd == "Z" then
      if cur then cur.closed = true end
    else
      local x, y = rest:match("(%-?[%d%.]+)%s+(%-?[%d%.]+)")
      if cmd == "M" then cur = { pts = {}, closed = false }; subs[#subs + 1] = cur end
      if cur and x then cur.pts[#cur.pts + 1] = { tonumber(x), tonumber(y) } end
    end
  end
  return subs
end

-- x 간격이 step(1000 단위) 미만인 점을 건너뛴다. 처음·끝 2점은 유지해 면의 바닥선이 보존된다.
local function thin(pts, step)
  local out, lastX = {}, -math.huge
  for i, p in ipairs(pts) do
    if i <= 2 or i >= #pts - 1 or p[1] - lastX >= step then
      out[#out + 1] = p
      lastX = p[1]
    end
  end
  return out
end

local function chartElements(chart, rect)
  local els = {}
  local function px(x) return rect.x + x / 1000 * rect.w end
  local function py(y) return rect.y + y / 48 * rect.h end
  for _, gy in ipairs({ 8, 24, 40 }) do                                   -- 웹 UI 와 같은 3개 격자선
    els[#els + 1] = { type = "segments", action = "stroke", strokeColor = C.grid, strokeWidth = 1, strokeDashPattern = { 2, 6 },
      coordinates = { { x = rect.x, y = py(gy) }, { x = rect.x + rect.w, y = py(gy) } } }
  end
  for _, mk in ipairs(chart and chart.markers or {}) do                   -- hour / midnight 경계
    els[#els + 1] = { type = "segments", action = "stroke", strokeWidth = 1, strokeDashPattern = { 3, 4 },
      strokeColor = mk.kind == "midnight" and C.midnight or C.hour,
      coordinates = { { x = px(mk.x), y = rect.y }, { x = px(mk.x), y = rect.y + rect.h } } }
  end
  local step = 1000 / (rect.w * 1.5)
  for _, sub in ipairs(parsePath(chart and chart.area_path)) do
    local coords = {}
    for _, p in ipairs(thin(sub.pts, step)) do coords[#coords + 1] = { x = px(p[1]), y = py(p[2]) } end
    if #coords >= 3 then
      els[#els + 1] = { type = "segments", action = "fill", fillColor = C.areaFill, closed = true, coordinates = coords }
    end
  end
  for _, sub in ipairs(parsePath(chart and chart.line_path)) do
    local coords = {}
    for _, p in ipairs(thin(sub.pts, step)) do coords[#coords + 1] = { x = px(p[1]), y = py(p[2]) } end
    if #coords >= 2 then
      els[#els + 1] = { type = "segments", action = "stroke", strokeColor = C.accent, strokeWidth = 1.2, closed = false, coordinates = coords }
    end
  end
  return els
end

local function meterIsEmpty(m)
  return (tonumber(m.used_percent) or 0) <= 0 and (not m.chart or (m.chart.line_path or "") == "")
end

-- ---------------------------------------------------------------- 본문 구성
local function build(data)
  local els, y = {}, S.headerHeight + 6
  for _, pane in ipairs(data.panes or {}) do
    els[#els + 1] = txt(pane.display or pane.name, L.x, y + 3, 200, 18, S.colors.title, 13, { textFont = S.fonts.title })
    els[#els + 1] = txt(pane.origin, L.x + 200, y + 5, L.w - 200, 16, S.colors.muted, 11, { textAlignment = "right" })
    y = y + L.paneHead
    if pane.error and pane.error ~= "" then
      els[#els + 1] = txt(pane.error, L.x + 8, y, L.w - 8, 14, C.critical, 11)
      y = y + L.errLine
    end
    for _, m in ipairs(pane.meters or {}) do
      local lvl = LEVEL[m.level] or C.normal
      if config.compactEmpty and meterIsEmpty(m) then
        els[#els + 1] = txt(string.format("%s   %s   %s", m.title or "", m.label or "", stripTz(m.reset, data.timezone)),
          L.x + 8, y + 2, L.w - 8, 16, S.colors.muted, 11)
        y = y + L.compact
      else
        local title = (m.emphasized and "› " or "") .. (m.title or "")
        if m.delta then title = title .. "   " .. m.delta end
        els[#els + 1] = txt(title, L.x + 8, y, L.w - 110, 18, C.name, 13)
        els[#els + 1] = txt(m.label, L.x + L.w - 100, y, 100, 18, lvl, 13, { textFont = S.fonts.key, textAlignment = "right" })

        local rect = { x = L.x + 8, y = y + 21, w = L.w - 8, h = config.chartHeight }
        els[#els + 1] = { type = "rectangle", action = "fill", fillColor = C.chartBg, frame = rect }
        for _, e in ipairs(chartElements(m.chart, rect)) do els[#els + 1] = e end

        -- 두 줄 게이지: 위 = 한도 소진율(레벨 색), 아래 = 창의 시간 경과(무채색). 둘을 견주면 페이스가 읽힌다.
        local by = rect.y + rect.h + 4
        local used = math.max(0, math.min(100, tonumber(m.used_percent) or 0)) / 100
        local elapsed = 0
        local w = m.window
        if w and w.started_at and w.resets_at and w.resets_at > w.started_at then
          elapsed = math.max(0, math.min(1, (os.time() - w.started_at) / (w.resets_at - w.started_at)))
        end
        els[#els + 1] = { type = "rectangle", action = "fill", fillColor = C.track, frame = { x = rect.x, y = by, w = rect.w, h = 3 } }
        els[#els + 1] = { type = "rectangle", action = "fill", fillColor = lvl, frame = { x = rect.x, y = by, w = rect.w * used, h = 3 } }
        els[#els + 1] = { type = "rectangle", action = "fill", fillColor = C.track, frame = { x = rect.x, y = by + 5, w = rect.w, h = 3 } }
        els[#els + 1] = { type = "rectangle", action = "fill", fillColor = C.timeFill, frame = { x = rect.x, y = by + 5, w = rect.w * elapsed, h = 3 } }

        local ty = by + 11
        els[#els + 1] = txt(stripTz(m.reset, data.timezone), rect.x, ty, 200, 14, S.colors.muted, 11)
        local right = m.quota_summary or (w and w.resets_at and leftLabel(w.resets_at)) or ""
        els[#els + 1] = txt(right, rect.x + 204, ty, rect.w - 204, 14, S.colors.muted, 11, { textAlignment = "right" })
        y = y + L.meter
      end
    end
    local rc = pane.reset_credits
    if type(rc) == "table" and rc.label then
      els[#els + 1] = txt(rc.label .. (rc.expiry_label and ("  ·  " .. rc.expiry_label) or ""), L.x + 8, y, L.w - 8, 14, S.colors.muted, 11)
      y = y + L.credits
    end
    y = y + L.paneGap
  end
  if #(data.panes or {}) == 0 then
    els[#els + 1] = txt("표시할 에이전트가 없습니다", L.x, y, L.w, 18, S.colors.muted, 12)
    y = y + 22
  end
  return els, y + S.bottomPadding
end

local function buildOffline(reason)
  local els, y = {}, S.headerHeight + 8
  local host = (config.url:gsub("^https?://", ""):gsub("/.*$", ""))
  els[#els + 1] = txt("agentmeter 에 연결할 수 없습니다  (" .. host .. ")", L.x, y, L.w, 18, C.critical, 13)
  y = y + 26
  els[#els + 1] = txt("터미널에서 실행:", L.x, y + 1, 104, 16, S.colors.muted, 12)
  els[#els + 1] = { id = "startCmd", type = "rectangle", action = "fill", fillColor = C.cmdBg,
    roundedRectRadii = { xRadius = 6, yRadius = 6 }, frame = { x = L.x + 104, y = y - 4, w = L.w - 104, h = 26 }, trackMouseDown = true }
  els[#els + 1] = txt(config.startCommand, L.x + 114, y, L.w - 124, 18, S.colors.text, 13,
    { id = "startCmdText", textFont = S.fonts.mono, trackMouseDown = true })
  y = y + 30
  els[#els + 1] = txt(string.format("클릭하면 명령을 복사합니다 · %s · %d초마다 재시도", reason or "", config.retrySec),
    L.x, y, L.w, 14, S.colors.muted, 11)
  return els, y + 16 + S.bottomPadding
end

-- ---------------------------------------------------------------- 오버레이
local function defaultPosition()
  local okC, cockpit = pcall(require, "agent-cockpit")
  local f = okC and type(cockpit) == "table" and cockpit.frame and cockpit.frame()
  if f and S.onAnyScreen(f.x, f.y, S.width, S.headerHeight) then
    return { x = f.x, y = f.y + f.h + S.margin.gap }
  end
  local sf = hs.settings.get("agentShortcuts.overlayFrame")
  if type(sf) == "table" and sf.x and sf.y and sf.h and S.onAnyScreen(sf.x, sf.y, S.width, S.headerHeight) then
    return { x = sf.x, y = sf.y + sf.h + S.margin.gap }
  end
  return S.defaultTopRight(config.offsetY)
end

local function onClick(elementId)
  if elementId == "startCmd" or elementId == "startCmdText" then
    hs.pasteboard.setContents(config.startCommand)
    hs.alert.show("복사됨: " .. config.startCommand, 1.5)
  end
end

local function redraw()
  local els, h
  if state.offline then
    els, h = buildOffline(state.offline)
  elseif state.data then
    els, h = build(state.data)
  else
    els, h = { txt("agentmeter 불러오는 중…", L.x, S.headerHeight + 8, L.w, 18, S.colors.muted, 12) }, S.height(1)
  end

  -- 사용자가 드래그해 둔 위치가 있으면 그대로, 없으면 매번 기본 위치(콕핏 아래 → Shortcuts 아래 → 우상단)를
  -- 다시 계산한다. 콕핏은 세션 수에 따라 높이가 바뀌고 시작 직후에는 캔버스가 없을 수 있어, 한 번만 계산하면 겹친다.
  local pos
  if state.pos and S.onAnyScreen(state.pos.x, state.pos.y, S.width, S.headerHeight) then
    pos = state.pos
  else
    pos = S.clampToScreenAt(defaultPosition(), S.width, h)
  end
  local frame = { x = pos.x, y = pos.y, w = S.width, h = h }

  if not state.canvas then
    state.canvas = S.newCanvas(frame)
    state.stopDrag = S.attachDrag(state.canvas, function(p)
      state.pos = p
      hs.settings.set(POS_KEY, p)
    end, onClick)
  else
    state.canvas:frame(frame)
  end

  local hint
  if state.offline then
    hint = "hyper+U 숨김 · ⇧U 새로고침 · 오프라인"
  elseif state.data then
    local d = state.data
    hint = string.format("hyper+U 숨김 · ⇧U 새로고침 · %s 갱신%s", hhmm(d.generated_at),
      d.refreshing and " · 갱신 중" or (d.next_refresh_at and (" · 다음 " .. hhmm(d.next_refresh_at)) or ""))
  else
    hint = "hyper+U 숨김 · ⇧U 새로고침 · 불러오는 중"
  end
  local all = S.baseElements("Agent Meter", hint)
  for _, e in ipairs(els) do all[#all + 1] = e end
  all[#all + 1] = S.dragHandleElement()
  state.canvas:replaceElements(table.unpack(all))
  if not state.userHidden then state.canvas:show() end
end

-- ---------------------------------------------------------------- 데이터
local function schedule(sec)
  if state.timer then state.timer:stop() end
  state.timer = hs.timer.doAfter(sec, function() M.refresh() end)
end

function M.refresh()
  hs.http.asyncGet(config.url, nil, function(status, body)
    if status ~= 200 or type(body) ~= "string" then
      state.offline = "HTTP " .. tostring(status)
      state.data = nil
      redraw()
      schedule(config.retrySec)
      return
    end
    local ok, data = pcall(hs.json.decode, body)
    if not ok or type(data) ~= "table" or type(data.panes) ~= "table" then
      state.offline = "응답 해석 실패"
      redraw()
      schedule(config.retrySec)
      return
    end
    state.data, state.offline = data, nil
    redraw()
    local wait = config.pollSec
    local n = isoToTime(data.next_refresh_at)
    if n then wait = math.max(5, math.min(120, n - os.time() + 2)) end
    if data.refreshing then wait = 4 end
    schedule(wait)
  end)
  return M
end

-- ---------------------------------------------------------------- 공개 API
function M.toggle()
  if not state.canvas then redraw() end
  if state.canvas:isShowing() then
    state.userHidden = true
    state.canvas:hide(0.12)
  else
    state.userHidden = false
    state.canvas:show(0.12)
  end
  return M
end

function M.frame() return state.canvas and state.canvas:frame() or nil end

function M.move(x, y)
  if x and y then
    state.pos = { x = tonumber(x), y = tonumber(y) }
    hs.settings.set(POS_KEY, state.pos)
  else
    state.pos = nil
    hs.settings.clear(POS_KEY)
  end
  redraw()
  return M
end

function M.stop()
  if state.timer then state.timer:stop(); state.timer = nil end
  if state.stopDrag then state.stopDrag(); state.stopDrag = nil end
  if state.canvas then state.canvas:delete(); state.canvas = nil end
  return M
end

function M.start(overrides)
  M.stop()
  for k, v in pairs(overrides or {}) do config[k] = v end
  local saved = hs.settings.get(POS_KEY)
  if type(saved) == "table" and type(saved.x) == "number" and type(saved.y) == "number" then state.pos = saved end
  state.userHidden = not config.showOnStart

  hs.urlevent.bind("agentmeter-toggle", function() M.toggle() end)
  hs.urlevent.bind("agentmeter-refresh", function() M.refresh() end)
  hs.urlevent.bind("agentmeter-move", function(_, p) p = p or {}; M.move(p.x, p.y) end)

  local ok, hyper = pcall(require, "hyper")
  if ok and hyper and hyper.hyperMode then
    hyper.bindKey("u", M.toggle)
    hyper.bindShiftKey("u", M.refresh)
  else
    log.w("hyper 모듈 없음: hammerspoon://agentmeter-* URL 만 동작")
  end

  redraw()
  M.refresh()
  log.i("agent-meter " .. M.version .. " 시작")
  return M
end

return M
