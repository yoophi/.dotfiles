-- overlay-style.lua — Agent Shortcuts / Agent Cockpit 공용 오버레이 스타일
--
-- 두 오버레이가 같은 폭·헤더·행 높이·색·글꼴·둥근 모서리·드래그 동작을 쓰도록 토큰과 헬퍼를 모아 둔다.
-- 값을 바꾸면 두 패널이 함께 바뀐다.

local S = {}

-- ---------------------------------------------------------------- 토큰
S.width = 520
S.headerHeight = 36
S.rowHeight = 30
S.bottomPadding = 8
S.radius = 12
S.opacity = 0.84
S.margin = { right = 20, top = 20, gap = 12 }      -- 화면 우상단 기준 여백, 패널 사이 간격

S.colors = {
  background = { red = 0.08, green = 0.09, blue = 0.11 },
  headerFill = { white = 1, alpha = 0.08 },
  title      = { white = 1, alpha = 0.94 },
  hint       = { white = 0.62, alpha = 1 },
  text       = { white = 1, alpha = 0.92 },
  muted      = { white = 0.72, alpha = 1 },
  accent     = { red = 0.45, green = 0.78, blue = 1.00, alpha = 1 },   -- 키 라벨·번호
  waiting    = { red = 1.00, green = 0.62, blue = 0.25, alpha = 1 },
  done       = { red = 0.45, green = 0.85, blue = 0.55, alpha = 1 },
  working    = { red = 0.55, green = 0.75, blue = 1.00, alpha = 1 },
  idle       = { white = 0.70, alpha = 1 },
  badgeClaude = { red = 1.00, green = 0.80, blue = 0.60, alpha = 1 },
  badgeCodex  = { red = 0.75, green = 0.85, blue = 1.00, alpha = 1 },
  dragHandle = { white = 1, alpha = 0.001 },
}

S.fonts = { title = "HelveticaNeue-Medium", key = "Menlo-Bold", mono = "Menlo" }
S.sizes = { title = 14, hint = 12, key = 13, text = 13, meta = 12, badge = 11 }

-- 행 안 컬럼 x 좌표 (두 패널이 같은 격자를 쓴다)
S.col = { key = 14, keyW = 84, text = 104 }

-- ---------------------------------------------------------------- 크기·위치
function S.height(rows)
  return S.headerHeight + math.max(rows, 1) * S.rowHeight + S.bottomPadding
end

function S.rowY(i) return S.headerHeight + (i - 1) * S.rowHeight end

function S.onAnyScreen(x, y, w, h)
  for _, s in ipairs(hs.screen.allScreens()) do
    local f = s:frame()
    if x < f.x + f.w and x + w > f.x and y < f.y + f.h and y + h > f.y then return true end
  end
  return false
end

-- 주 화면 우상단 기본 위치. offsetY 를 주면 그만큼 아래로.
function S.defaultTopRight(offsetY)
  local f = hs.screen.primaryScreen():frame()
  return { x = f.x + f.w - S.width - S.margin.right, y = f.y + (offsetY or S.margin.top) }
end

function S.clampToScreen(pos, w, h)
  local scr = hs.mouse.getCurrentScreen() or hs.screen.mainScreen()
  local f = scr:frame()
  return { x = math.max(f.x, math.min(pos.x, f.x + f.w - w)), y = math.max(f.y, math.min(pos.y, f.y + f.h - h)) }
end

-- ---------------------------------------------------------------- 요소
-- 배경 + 헤더 띠 + 제목(왼쪽) + 힌트(오른쪽). 캔버스 폭은 S.width 로 가정.
function S.baseElements(title, hint)
  local bg = { red = S.colors.background.red, green = S.colors.background.green, blue = S.colors.background.blue, alpha = S.opacity }
  return {
    { type = "rectangle", action = "fill", frame = { x = 0, y = 0, w = "100%", h = "100%" },
      fillColor = bg, roundedRectRadii = { xRadius = S.radius, yRadius = S.radius } },
    { type = "rectangle", action = "fill", frame = { x = 0, y = 0, w = "100%", h = S.headerHeight },
      fillColor = S.colors.headerFill, roundedRectRadii = { xRadius = S.radius, yRadius = S.radius } },
    { type = "text", frame = { x = S.col.key, y = 9, w = 200, h = 20 }, text = title,
      textColor = S.colors.title, textFont = S.fonts.title, textSize = S.sizes.title, textLineBreak = "truncateTail" },
    { type = "text", frame = { x = 200, y = 11, w = S.width - 200 - S.col.key, h = 18 }, text = hint or "",
      textColor = S.colors.hint, textSize = S.sizes.hint, textAlignment = "right", textLineBreak = "truncateTail" },
  }
end

-- 헤더 위에 얹는 투명 드래그 핸들. 항상 마지막 요소로 append 한다.
function S.dragHandleElement()
  return { id = "dragHandle", type = "rectangle", action = "fill", frame = { x = 0, y = 0, w = "100%", h = S.headerHeight },
    fillColor = S.colors.dragHandle, trackMouseDown = true, trackMouseByBounds = true }
end

function S.newCanvas(frame)
  local c = hs.canvas.new(frame)
  c:level("floating"):behavior({ "canJoinAllSpaces", "stationary", "ignoresCycle" }):clickActivating(false)
  return c
end

-- 헤더 드래그. 놓으면 화면 안으로 보정한 위치를 onDrop({x,y}) 로 넘긴다. 반환값은 드래그 중단 함수.
function S.attachDrag(canvas, onDrop)
  local tap, offset
  local function stop()
    if tap then tap:stop(); tap = nil end
    offset = nil
  end
  canvas:mouseCallback(function(_, msg, elementId)
    if msg ~= "mouseDown" or elementId ~= "dragHandle" or not hs.eventtap.checkMouseButtons().left then return end
    stop()
    local m = hs.mouse.absolutePosition()
    local tl = canvas:topLeft()
    offset = { x = m.x - tl.x, y = m.y - tl.y }
    tap = hs.eventtap.new({ hs.eventtap.event.types.leftMouseDragged, hs.eventtap.event.types.leftMouseUp }, function(ev)
      if not offset then stop(); return false end
      if ev:getType() == hs.eventtap.event.types.leftMouseDragged then
        local mm = hs.mouse.absolutePosition()
        canvas:topLeft({ x = mm.x - offset.x, y = mm.y - offset.y })
      else
        local fr = canvas:frame()
        local final = S.clampToScreen(canvas:topLeft(), fr.w, fr.h)
        canvas:topLeft(final)
        stop()
        if onDrop then onDrop({ x = final.x, y = final.y }) end
      end
      return false
    end):start()
  end)
  return stop
end

return S
