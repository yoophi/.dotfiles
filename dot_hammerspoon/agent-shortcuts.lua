-- Agent prompt shortcuts for Hammerspoon.
-- Put this file at ~/.hammerspoon/agent-shortcuts.lua.

local M = {}

-- Edit this section to add, remove, or change shortcuts.
local defaults = {
  -- Wait after pasting before sending Return. Increase this for slower TUI apps.
  returnDelaySeconds = 0.15,

  -- Wait after Return before restoring the previous clipboard.
  clipboardRestoreDelaySeconds = 0.10,

  overlay = {
    -- Show the shortcut reference automatically when Hammerspoon reloads.
    showOnStart = true,

    -- Use this shortcut to show or hide the overlay.
    toggleModifiers = { "cmd", "alt" },
    toggleKey = "0",

    width = 520,
    headerHeight = 38,
    rowHeight = 30,
    bottomPadding = 8,
    backgroundOpacity = 0.82,
  },

  shortcuts = {
    {
      modifiers = { "ctrl", "alt", "shift" },
      key = "1",
      prompt = "계속 진행해주세요",
    },
    {
      modifiers = { "ctrl", "alt", "shift" },
      key = "2",
      prompt = "최근 진행한 작업을 아래 형식으로 요약해주세요\n---\n시간: 작업내용(2줄 이내)",
    },
    {
      modifiers = { "ctrl", "alt", "shift" },
      key = "3",
      prompt = "현재 작업 디렉토리를 출력해주세요",
    },
    {
      modifiers = { "ctrl", "alt", "shift" },
      key = "5",
      prompt = "eli5 스킬을 이용하여 내용을 정리하고 화면에 출력해주세요",
    },
    {
      modifiers = { "ctrl", "alt", "shift" },
      key = "0",
      prompt = "commit 하고 push 해주세요.",
    },
    {
      modifiers = { "ctrl", "alt", "shift" },
      key = "9",
      prompt = "내용을 정리하여 logseq 문서로 저장해주세요",
    },
    {
      modifiers = { "ctrl", "alt", "shift" },
      key = "b",
      prompt = "빌드하고 /applications 위치에 설치해주세요",
    },
  },
}

local activeHotkeys = {}
local activeConfig = nil
local overlayCanvas = nil
local dragEventTap = nil
local dragOffset = nil
local overlayPositionSetting = "agentShortcuts.overlayPosition"

local function valueOrDefault(value, fallback)
  if value == nil then
    return fallback
  end
  return value
end

local function buildConfig(overrides)
  overrides = overrides or {}
  local overlayOverrides = overrides.overlay or {}

  return {
    returnDelaySeconds = overrides.returnDelaySeconds
      or defaults.returnDelaySeconds,
    clipboardRestoreDelaySeconds = overrides.clipboardRestoreDelaySeconds
      or defaults.clipboardRestoreDelaySeconds,
    shortcuts = overrides.shortcuts or defaults.shortcuts,
    overlay = {
      showOnStart = valueOrDefault(
        overlayOverrides.showOnStart,
        defaults.overlay.showOnStart
      ),
      toggleModifiers = overlayOverrides.toggleModifiers
        or defaults.overlay.toggleModifiers,
      toggleKey = overlayOverrides.toggleKey or defaults.overlay.toggleKey,
      width = overlayOverrides.width or defaults.overlay.width,
      headerHeight = overlayOverrides.headerHeight
        or defaults.overlay.headerHeight,
      rowHeight = overlayOverrides.rowHeight or defaults.overlay.rowHeight,
      bottomPadding = overlayOverrides.bottomPadding
        or defaults.overlay.bottomPadding,
      backgroundOpacity = overlayOverrides.backgroundOpacity
        or defaults.overlay.backgroundOpacity,
    },
  }
end

local modifierSymbols = {
  cmd = "⌘",
  command = "⌘",
  alt = "⌥",
  option = "⌥",
  ctrl = "⌃",
  control = "⌃",
  shift = "⇧",
  fn = "fn",
}

local function shortcutLabel(modifiers, key)
  local parts = {}
  for _, modifier in ipairs(modifiers) do
    table.insert(parts, modifierSymbols[modifier] or modifier)
  end
  table.insert(parts, string.upper(key))
  return table.concat(parts)
end

local function singleLine(text)
  return text:gsub("[\r\n]+", " ↵ ")
end

local function overlayHeight(config)
  return config.overlay.headerHeight
    + (#config.shortcuts * config.overlay.rowHeight)
    + config.overlay.bottomPadding
end

local function rectanglesOverlap(first, second)
  return first.x < second.x + second.w
    and second.x < first.x + first.w
    and first.y < second.y + second.h
    and second.y < first.y + first.h
end

local function savedOrDefaultOverlayPosition(config)
  local saved = hs.settings.get(overlayPositionSetting)
  local width = config.overlay.width

  if type(saved) == "table"
    and type(saved.x) == "number"
    and type(saved.y) == "number"
  then
    local savedHeader = {
      x = saved.x,
      y = saved.y,
      w = width,
      h = config.overlay.headerHeight,
    }

    for _, screen in ipairs(hs.screen.allScreens()) do
      if rectanglesOverlap(savedHeader, screen:frame()) then
        return { x = saved.x, y = saved.y }
      end
    end
  end

  local frame = hs.screen.mainScreen():frame()
  return {
    x = frame.x + frame.w - width - 20,
    y = frame.y + 20,
  }
end

local function clampOverlayToCurrentScreen(position, config)
  local screen = hs.mouse.getCurrentScreen() or hs.screen.mainScreen()
  local frame = screen:frame()
  local width = config.overlay.width
  local height = overlayHeight(config)
  local maximumX = math.max(frame.x, frame.x + frame.w - width)
  local maximumY = math.max(frame.y, frame.y + frame.h - height)

  return {
    x = math.max(frame.x, math.min(position.x, maximumX)),
    y = math.max(frame.y, math.min(position.y, maximumY)),
  }
end

local function stopDragging()
  if dragEventTap then
    dragEventTap:stop()
    dragEventTap = nil
  end
  dragOffset = nil
end

local function beginDragging(canvas)
  stopDragging()

  local mousePosition = hs.mouse.absolutePosition()
  local canvasPosition = canvas:topLeft()
  dragOffset = {
    x = mousePosition.x - canvasPosition.x,
    y = mousePosition.y - canvasPosition.y,
  }

  dragEventTap = hs.eventtap.new({
    hs.eventtap.event.types.leftMouseDragged,
    hs.eventtap.event.types.leftMouseUp,
  }, function(event)
    if not overlayCanvas or not dragOffset then
      stopDragging()
      return false
    end

    if event:getType() == hs.eventtap.event.types.leftMouseDragged then
      local currentMousePosition = hs.mouse.absolutePosition()
      overlayCanvas:topLeft({
        x = currentMousePosition.x - dragOffset.x,
        y = currentMousePosition.y - dragOffset.y,
      })
    else
      local finalPosition = clampOverlayToCurrentScreen(
        overlayCanvas:topLeft(),
        activeConfig
      )
      overlayCanvas:topLeft(finalPosition)
      hs.settings.set(overlayPositionSetting, finalPosition)
      stopDragging()
    end

    return false
  end):start()
end

local function createOverlay(config)
  local position = savedOrDefaultOverlayPosition(config)
  local width = config.overlay.width
  local height = overlayHeight(config)
  local headerHeight = config.overlay.headerHeight

  overlayCanvas = hs.canvas.new({
    x = position.x,
    y = position.y,
    w = width,
    h = height,
  })

  overlayCanvas:appendElements({
    type = "rectangle",
    action = "fill",
    frame = { x = 0, y = 0, w = "100%", h = "100%" },
    fillColor = {
      red = 0.08,
      green = 0.09,
      blue = 0.11,
      alpha = config.overlay.backgroundOpacity,
    },
    roundedRectRadii = { xRadius = 12, yRadius = 12 },
  }, {
    type = "rectangle",
    action = "fill",
    frame = { x = 0, y = 0, w = "100%", h = headerHeight },
    fillColor = { white = 1, alpha = 0.08 },
    roundedRectRadii = { xRadius = 12, yRadius = 12 },
  }, {
    type = "text",
    text = "Agent Shortcuts  ·  "
      .. shortcutLabel(
        config.overlay.toggleModifiers,
        config.overlay.toggleKey
      )
      .. " 표시/숨김",
    frame = { x = 14, y = 9, w = width - 28, h = 22 },
    textColor = { white = 1, alpha = 0.94 },
    textSize = 14,
    textLineBreak = "truncateTail",
  })

  for index, shortcut in ipairs(config.shortcuts) do
    local y = headerHeight + ((index - 1) * config.overlay.rowHeight)

    overlayCanvas:appendElements({
      type = "text",
      text = shortcutLabel(shortcut.modifiers, shortcut.key),
      frame = { x = 16, y = y + 7, w = 82, h = 20 },
      textColor = { red = 0.45, green = 0.78, blue = 1, alpha = 1 },
      textFont = "Menlo-Bold",
      textSize = 13,
      textLineBreak = "truncateTail",
    }, {
      type = "text",
      text = singleLine(shortcut.prompt),
      frame = { x = 104, y = y + 6, w = width - 120, h = 21 },
      textColor = { white = 1, alpha = 0.92 },
      textSize = 13,
      textLineBreak = "truncateTail",
    })
  end

  -- Only the header captures mouse clicks; the rest is a reference display.
  overlayCanvas:appendElements({
    id = "dragHandle",
    type = "rectangle",
    action = "fill",
    frame = { x = 0, y = 0, w = "100%", h = headerHeight },
    fillColor = { white = 1, alpha = 0.001 },
    trackMouseDown = true,
    trackMouseByBounds = true,
  })

  overlayCanvas
    :level("floating")
    :behavior({ "canJoinAllSpaces", "stationary", "ignoresCycle" })
    :clickActivating(false)
    :mouseCallback(function(_, message, elementId)
      if message == "mouseDown"
        and elementId == "dragHandle"
        and hs.eventtap.checkMouseButtons().left
      then
        beginDragging(overlayCanvas)
      end
    end)

  if config.overlay.showOnStart then
    overlayCanvas:show()
  end
end

local function captureClipboard()
  local data = hs.pasteboard.readAllData()
  local hadData = data ~= nil and next(data) ~= nil
  return data, hadData
end

local function restoreClipboard(data, hadData)
  if hadData then
    hs.pasteboard.writeAllData(data)
  else
    hs.pasteboard.clearContents()
  end
end

local function pasteAndEnter(prompt, config)
  local previousClipboard, hadPreviousClipboard = captureClipboard()

  if not hs.pasteboard.setContents(prompt) then
    hs.alert.show("Agent shortcut: 클립보드에 프롬프트를 복사하지 못했습니다.")
    return
  end

  -- Record the temporary clipboard version so a new user copy is never
  -- overwritten by the delayed restoration below.
  local temporaryChangeCount = hs.pasteboard.changeCount()

  hs.eventtap.keyStroke({ "cmd" }, "v")

  hs.timer.doAfter(config.returnDelaySeconds, function()
    -- Send a real Return key event instead of embedding a newline in the text.
    hs.eventtap.keyStroke({}, "return")

    hs.timer.doAfter(config.clipboardRestoreDelaySeconds, function()
      if hs.pasteboard.changeCount() == temporaryChangeCount then
        restoreClipboard(previousClipboard, hadPreviousClipboard)
      end
    end)
  end)
end

function M.stop()
  stopDragging()

  if overlayCanvas then
    overlayCanvas:delete()
    overlayCanvas = nil
  end

  for _, hotkey in ipairs(activeHotkeys) do
    hotkey:delete()
  end
  activeHotkeys = {}
  activeConfig = nil
  return M
end

function M.showOverlay()
  if overlayCanvas then
    overlayCanvas:show(0.12)
  end
  return M
end

function M.hideOverlay()
  if overlayCanvas then
    overlayCanvas:hide(0.12)
  end
  return M
end

function M.toggleOverlay()
  if overlayCanvas then
    if overlayCanvas:isShowing() then
      M.hideOverlay()
    else
      M.showOverlay()
    end
  end
  return M
end

function M.start(overrides)
  M.stop()
  local config = buildConfig(overrides)
  activeConfig = config

  for _, shortcut in ipairs(config.shortcuts) do
    local modifiers = shortcut.modifiers
    local key = shortcut.key
    local prompt = shortcut.prompt

    local hotkey = hs.hotkey.bind(modifiers, key, function()
      pasteAndEnter(prompt, config)
    end)
    table.insert(activeHotkeys, hotkey)
  end

  createOverlay(config)

  local overlayToggleHotkey = hs.hotkey.bind(
    config.overlay.toggleModifiers,
    config.overlay.toggleKey,
    M.toggleOverlay
  )
  table.insert(activeHotkeys, overlayToggleHotkey)

  return M
end

return M
