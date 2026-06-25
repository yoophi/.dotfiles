-- local ctrlLastPress = 0
-- local ctrlTap = hs.eventtap.new({hs.eventtap.event.types.flagsChanged}, function(event)
--     local flags = event:getFlags()
--     local now = hs.timer.secondsSinceEpoch()

--     -- ctrl 눌림 감지
--     if flags.ctrl then
--         hs.alert.show("Ctrl! ctrlLastPress=" .. ctrlLastPress)
--         if (now - ctrlLastPress) < 0.3 then
--             -- 여기서 원하는 동작 실행
--             hs.alert.show("Double Ctrl!")
--             --
--             local screen = hs.mouse.getCurrentScreen()
--             local nextScreen = screen:next()
--             local rect = nextScreen:fullFrame()
--             local center = hs.geometry.rectMidPoint(rect)
--             hs.mouse.absolutePosition(center)
--         end
--         ctrlLastPress = now
--     end
-- end)

-- ctrlTap:start()

hs.hotkey.bind({"cmd", "alt", "ctrl"}, "X", function()
  hs.notify.new({title="Hammerspoon", informativeText="Hello World"}):send()
end)


local chooser = hs.chooser.new(function (choice)
    hs.alert.show(choice.text)
end)

hs.hotkey.bind({'option'}, 'd', function ()
    local list = {}
    table.insert(list, {
        text = 'YYYY-mm-dd 복사',
        subText = '2025-03-14 형식으로 클립보드에 복사합니다.',
    })
    table.insert(list, {
        text = 'YYmmdd',
        subText = '250314 형식으로 클립보드에 복사합니다.',
    })
    chooser:choices(list)
    chooser:show()
end)

hs.hotkey.bind({'option'}, 'l', function ()
    local list = {}
    table.insert(list, {
        text = 'alert1',
        subText = '화면에 첫 번째 알림을 띄웁니다',
        -- image = hs.image.imageFromPath( 이미지 주소 .. '.jpg'),
    })
    table.insert(list, {
        text = 'alert2',
        subText = '화면에 두 번째 알림을 띄웁니다',
        -- image = hs.image.imageFromPath( 이미지 주소 .. '.jpg'),
    })
    chooser:choices(list)
    chooser:show()
end)

-- 회사에서 사용하는 코드 가져옴 
--
require('inputsource_aurora')

function open(app)
  return function()
    hs.application.launchOrFocus(app)
  end
end

function open_url(url)
  return function()
    hs.urlevent.openURL(url)
  end
end

local mChooser = hs.chooser.new(function (choice)
    if choice.url ~= nil then
      open_url(choice.url)()
    else
      open(choice.text)()
    end
end)

function change_output_device()
  local currentOutputDevice = hs.audiodevice.defaultOutputDevice()
  local devices = hs.audiodevice.allOutputDevices()
  local index = hs.fnutils.indexOf(devices, currentOutputDevice)
  local device
  if index == #devices then
    device = devices[1]
  else
    device = devices[index +1]
  end
  device:setDefaultOutputDevice()
  hs.alert(device:name())
end

function change_input_device()
  local currentInputDevice = hs.audiodevice.defaultInputDevice()
  local devices = hs.audiodevice.allInputDevices()
  local index = hs.fnutils.indexOf(devices, currentInputDevice)
  local device
  if index == #devices then
    device = devices[1]
  else
    device = devices[index +1]
  end
  device:setDefaultInputDevice()
  hs.alert(device:name())
end

function lock_screen()
  hs.caffeinate.systemSleep()
end

function window_left()
  local win = hs.window.focusedWindow()
  local f = win:frame()
  local screen = win:screen()
  local max = screen:frame()
  f.x = max.x
  f.y = max.y
  f.w = max.w / 2
  f.h = max.h
  win:setFrame(f)
end

function window_right()
  local win = hs.window.focusedWindow()
  local f = win:frame()
  local screen = win:screen()
  local max = screen:frame()
  f.x = max.x + (max.w / 2)
  f.y = max.y
  f.w = max.w / 2
  f.h = max.h
  win:setFrame(f)
end

function window_up()
  local win = hs.window.focusedWindow()
  local f = win:frame()
  local screen = win:screen()
  local max = screen:frame()
  f.x = max.x
  f.y = max.y
  f.w = max.w
  f.h = max.h / 2
  win:setFrame(f)
end

function window_down()
  local win = hs.window.focusedWindow()
  local f = win:frame()
  local screen = win:screen()
  local max = screen:frame()
  f.x = max.x
  f.y = max.y + (max.h / 2)
  f.w = max.w
  f.h = max.h / 2
  win:setFrame(f)
end

function window_full()
  local win = hs.window.focusedWindow()
  local f = win:frame()
  local screen = win:screen()
  local max = screen:frame()
  f.x = max.x
  f.y = max.y
  f.w = max.w
  f.h = max.h
  win:setFrame(f)
end

function mirrorStop()
  local screen = hs.screen.mainScreen()
  hs.alert(screen)
  screen:mirrorStop();
end

hs.hotkey.bind({"cmd", "alt", "ctrl"}, "l", open("Logseq"))
hs.hotkey.bind({"cmd", "alt", "ctrl"}, 'c', open("Google Chrome"))
hs.hotkey.bind({"cmd", "alt", "ctrl"}, 'f', open("ForkLift"))
hs.hotkey.bind({"cmd", "alt", "ctrl"}, 'i', open("iTerm"))
hs.hotkey.bind({"cmd", "alt", "ctrl"}, 'i', open("iTerm"))
hs.hotkey.bind({"cmd", "alt", "ctrl"}, 'k', open("kitty"))
hs.hotkey.bind({"cmd", "alt", "ctrl"}, 'n', open("Notion"))
hs.hotkey.bind({"cmd", "alt", "ctrl"}, 's', open("Slack"))
hs.hotkey.bind({"cmd", "alt", "ctrl"}, 't', function () 
  local list = {
    {
      text = 'ChatGPT',
      subText = 'open ChatGPT',
    },
    {
      text = 'Claude',
      subText = 'open Claude',
    }
  }
  mChooser:choices(list)
  mChooser:show()
end)

hs.hotkey.bind({"cmd", "alt", "ctrl"}, 'v', function () 
  local list = {
    {
      text = 'Visual Studio Code',
      subText = 'open Visual Studio Code',
    },
  }
  mChooser:choices(list)
  mChooser:show()
end)
hs.hotkey.bind({"cmd", "alt", "ctrl"}, 'w', open("WezTerm"))
hs.hotkey.bind({"cmd", "alt", "ctrl"}, 'g', open("Ghostty"))
hs.hotkey.bind({"cmd", "alt", "ctrl"}, 'r', function () 
  local list = {
    {
      text = 'Calendar',
      subText = 'Google Calendar',
      url = 'https://calendar.google.com/',
    },
    {
      text = 'BusyCal',
      subText = 'open BusyCal app',
    }
  }
  mChooser:choices(list)
  mChooser:show()
end)

hs.hotkey.bind({"cmd", "alt", "ctrl"}, 'm', function ()
    local list = {
        {
            text = 'Gmail',
            subText = 'gmail',
            url = 'https://mail.google.com/',
        },
        {
            text = 'Messages',
            subText = 'messages',
        }
    }
    mChooser:choices(list)
    mChooser:show()
end)

hs.hotkey.bind({"cmd", "alt", "ctrl"}, "space", window_full)

hs.hotkey.bind({"cmd", "alt", "ctrl", "shift"}, "Left", window_left)
hs.hotkey.bind({"cmd", "alt", "ctrl", "shift"}, "Right", window_right)
hs.hotkey.bind({"cmd", "alt", "ctrl", "shift"}, "Up", window_up)
hs.hotkey.bind({"cmd", "alt", "ctrl", "shift"}, "Down", window_down)

hs.hotkey.bind({'option', 'cmd'}, 'r', function() 
  hs.reload() 
  hs.notify.new({title="Hammerspoon", informativeText="Hammerspoon 설정을 reload 했음"}):send()
end)

hs.window.animationDuration = 0

local inputEnglish = "com.apple.keylayout.ABC"
local esc_keycode = hs.keycodes.map.escape
local esc_reposting = false
local esc_pending = false

if escape_input_tap then
  escape_input_tap:stop()
end

-- esc 키가 눌렸을 때, 영문으로 전환 후 esc 키 이벤트를 발생시킴
local function post_escape()
  hs.eventtap.event.newKeyEvent({}, "escape", true):post()
  hs.eventtap.event.newKeyEvent({}, "escape", false):post()
end

escape_input_tap = hs.eventtap.new({
  hs.eventtap.event.types.keyDown,
  hs.eventtap.event.types.keyUp,
}, function(event)
  if event:getKeyCode() ~= esc_keycode then
    return false
  end

  if esc_reposting then
    return false  -- 재발행한 가짜 esc 는 통과
  end

  -- 원본 keyDown/keyUp 은 esc_pending 동안 모두 삼킴
  if event:getType() == hs.eventtap.event.types.keyUp then
    return esc_pending
  end

  -- 이미 영문이면 그대로 통과 (esc 정상 동작)
  if hs.keycodes.currentSourceID() == inputEnglish then
    return false
  end

  -- 한글모드: 영문 전환 후, 전환이 실제로 끝나면 esc 발행
  hs.keycodes.currentSourceID(inputEnglish)
  esc_pending = true

  local tries = 0
  local function fire()
    tries = tries + 1
    if hs.keycodes.currentSourceID() == inputEnglish or tries > 20 then
      esc_reposting = true
      post_escape()
      esc_pending = false
      hs.timer.doAfter(0.03, function()
        esc_reposting = false
      end)
    else
      hs.timer.doAfter(0.01, fire)  -- 최대 ~200ms 까지 10ms 간격 폴링
    end
  end
  hs.timer.doAfter(0.01, fire)

  return true
end)

escape_input_tap:start()

-- Load and install the Hyper key extension. Binding to F18
local hyper = require('hyper')
hyper.install('F18')

-- Quick Reloading of Hammerspoon
hyper.bindKey('r', hs.reload)

hyper.bindShiftKey('p', function()
    hs.spotify.displayCurrentTrack()
  end)

-- Disabled: `am` is not defined in this config.
-- hyper.bindKey(']', function()
--     am.switchToAndFromApp("com.googlecode.iterm2")
--   end)
