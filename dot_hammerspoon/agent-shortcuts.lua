-- Agent prompt shortcuts for Hammerspoon.
-- Put this file at ~/.hammerspoon/agent-shortcuts.lua.
--
-- 오버레이 스타일(폭·헤더·행·색·드래그)은 overlay-style.lua 에서 가져온다 (Agent Cockpit 과 공용).

local S = require("overlay-style")

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
    toggleModifiers = {},
    toggleKey = "0",
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
local overlayToggleHotkey = nil
local overlayToggleModal = nil
local activeConfig = nil
local overlayCanvas = nil
local stopDragging = nil
local overlayPositionSetting = "agentShortcuts.overlayPosition"
local overlayFrameSetting = "agentShortcuts.overlayFrame"     -- Agent Cockpit 이 아래에 붙기 위해 읽는다

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

local function savedOrDefaultOverlayPosition()
  local saved = hs.settings.get(overlayPositionSetting)
  if type(saved) == "table" and type(saved.x) == "number" and type(saved.y) == "number"
    and S.onAnyScreen(saved.x, saved.y, S.width, S.headerHeight) then
    return { x = saved.x, y = saved.y }
  end
  return S.defaultTopRight()
end

local function publishFrame()
  if overlayCanvas then
    local f = overlayCanvas:frame()
    hs.settings.set(overlayFrameSetting, { x = f.x, y = f.y, w = f.w, h = f.h })
  end
end

local function createOverlay(config)
  local position = savedOrDefaultOverlayPosition()
  local height = S.height(#config.shortcuts)

  overlayCanvas = S.newCanvas({ x = position.x, y = position.y, w = S.width, h = height })

  local hint = "hyper+" .. shortcutLabel(config.overlay.toggleModifiers, config.overlay.toggleKey) .. " 표시/숨김 · 드래그 이동"
  overlayCanvas:replaceElements(table.unpack(S.baseElements("Agent Shortcuts", hint)))

  for index, shortcut in ipairs(config.shortcuts) do
    local y = S.rowY(index)
    overlayCanvas:appendElements({
      type = "text",
      text = shortcutLabel(shortcut.modifiers, shortcut.key),
      frame = { x = S.col.key, y = y + 7, w = S.col.keyW, h = 20 },
      textColor = S.colors.accent,
      textFont = S.fonts.key,
      textSize = S.sizes.key,
      textLineBreak = "truncateTail",
    }, {
      type = "text",
      text = singleLine(shortcut.prompt),
      frame = { x = S.col.text, y = y + 6, w = S.width - S.col.text - 16, h = 21 },
      textColor = S.colors.text,
      textSize = S.sizes.text,
      textLineBreak = "truncateTail",
    })
  end

  -- Only the header captures mouse clicks; the rest is a reference display.
  overlayCanvas:appendElements(S.dragHandleElement())
  stopDragging = S.attachDrag(overlayCanvas, function(pos)
    hs.settings.set(overlayPositionSetting, pos)
    publishFrame()
  end)

  publishFrame()
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
  if overlayToggleHotkey then
    overlayToggleHotkey:delete()
    for i, hotkey in ipairs(overlayToggleModal.keys) do
      if hotkey == overlayToggleHotkey then table.remove(overlayToggleModal.keys, i); break end
    end
    overlayToggleHotkey, overlayToggleModal = nil, nil
  end

  if stopDragging then stopDragging(); stopDragging = nil end

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

-- 현재 오버레이 프레임 (다른 패널이 아래에 붙을 때 사용)
function M.frame()
  return overlayCanvas and overlayCanvas:frame() or nil
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

  overlayToggleModal = require("hyper").hyperMode
  overlayToggleModal:bind(
    config.overlay.toggleModifiers,
    config.overlay.toggleKey,
    M.toggleOverlay
  )
  overlayToggleHotkey = overlayToggleModal.keys[#overlayToggleModal.keys]

  return M
end

return M
