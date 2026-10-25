-- Learn how to configure Hyprland: https://wiki.hypr.land/Configuring/Start/

-- Omarchy's bootstrap keeps path setup out of this user config.
dofile((os.getenv("OMARCHY_PATH") or "/usr/share/omarchy") .. "/default/hypr/bootstrap.lua")

-- Disable all Omarchy default bindings. Add your own in hypr/bindings.lua.
-- omarchy_default_bindings = false
--
-- Or disable only bindings for Omarchy's preinstalled apps/web apps while
-- keeping core window-manager bindings:
-- omarchy_preinstalled_bindings = false

-- Русские описания хоткеев в меню SUPER + K (см. hypr/descriptions_ru.lua).
-- Обёртка ставится до загрузки дефолтов, поэтому биндинги сразу получают
-- переведённое описание.
require("default.hypr.helpers")
local descriptions_ru = require("hypr.descriptions_ru")
local omarchy_bind = o.bind
o.bind = function(keys, description, dispatcher, options)
  return omarchy_bind(keys, descriptions_ru.translate(description), dispatcher, options)
end

-- Load Omarchy defaults.
require("default.hypr.omarchy")

-- Put your personal overrides in these files. They're loaded after Omarchy's
-- defaults so package updates can improve the defaults without rewriting your
-- ~/.config/hypr files.
require("hypr.monitors")
require("hypr.workspaces")
require("hypr.input")
require("hypr.bindings")
require("hypr.looknfeel")
require("hypr.autostart")

-- Set default shell
hl.env("SHELL", "/usr/bin/zsh")

-- Toggle config flags dynamically.
require("default.hypr.toggles")

-- Add any other personal Hyprland configuration below.
-- o.window("qemu", { workspace = "5" })

-- Steam по умолчанию открывается как нормальное тайлинговое окно (не плавающее)
o.window({ class = "^[sS]team$" }, {
  tile = true,
})
o.window({ class = "^[sS]team$", title = "Friends List" }, { float = true, size = { 460, 800 } })
o.window({ class = "^[sS]team$", title = ".* - Chat.*" }, { float = true })
o.window({ class = "^[sS]team$", title = "Steam Settings" }, { float = true })
o.window({ class = "^[sS]team$", title = "Settings" }, { float = true })

-- Игры (Steam, Proton, Wine) по умолчанию запускаются на маленьком 16:9 мониторе (DP-2)
o.window({ class = "^steam$", title = ".*Big Picture.*" }, {
  monitor = "DP-2",
  fullscreen = true,
  immediate = true,
  idle_inhibit = "focus",
})
o.window({ initial_title = "Steam Big Picture Mode" }, {
  monitor = "DP-2",
  fullscreen = true,
  immediate = true,
  idle_inhibit = "focus",
})

-- Режим Steam Big Picture всегда должен быть в полноэкранном режиме (в том числе после выхода из игр)
local function ensure_steam_bigpicture_fullscreen(w)
  if not w then return end
  local title = w.title or ""
  local initial_title = w.initial_title or ""
  local class = w.class or ""
  if class == "steam" and (initial_title == "Steam Big Picture Mode" or string.find(title, "Big Picture")) then
    if w.fullscreen == 0 then
      hl.dispatch(hl.dsp.window.fullscreen({ mode = "fullscreen" }))
    end
    hl.timer(function()
      local curr = hl.get_active_window()
      if curr and curr.class == "steam" and (curr.initial_title == "Steam Big Picture Mode" or string.find(curr.title or "", "Big Picture")) then
        if curr.fullscreen == 0 then
          hl.dispatch(hl.dsp.window.fullscreen({ mode = "fullscreen" }))
        end
      end
    end, { timeout = 150, type = "oneshot" })
  end
end

hl.on("window.active", function(w)
  ensure_steam_bigpicture_fullscreen(w)
end)

o.window({ class = "^steam_app_.*$" }, {
  monitor = "DP-2",
  fullscreen = true,
  immediate = true,
  idle_inhibit = "focus",
})
o.window({ class = "^.*\\.exe$" }, {
  monitor = "DP-2",
  fullscreen = true,
  immediate = true,
  idle_inhibit = "focus",
})

-- Исключение: Rocket League всегда запускается на большом ультрашироком мониторе (DP-3)
o.window({ class = "^steam_app_252950$" }, {
  monitor = "DP-3",
  fullscreen = true,
  immediate = true,
  idle_inhibit = "focus",
})
o.window({ class = ".*[rR]ocket[lL]eague.*" }, {
  monitor = "DP-3",
  fullscreen = true,
  immediate = true,
  idle_inhibit = "focus",
})
o.window({ initial_class = ".*[rR]ocket[lL]eague.*" }, {
  monitor = "DP-3",
  fullscreen = true,
  immediate = true,
  idle_inhibit = "focus",
})
o.window({ title = ".*Rocket League.*" }, {
  monitor = "DP-3",
  fullscreen = true,
  immediate = true,
  idle_inhibit = "focus",
})
o.window({ initial_title = ".*Rocket League.*" }, {
  monitor = "DP-3",
  fullscreen = true,
  immediate = true,
  idle_inhibit = "focus",
})

-- Telegram в качестве виджета на скретчпаде (всплывающее окно в правом нижнем углу над статус-баром, ширина 1/4 экрана)
o.window({ class = ".*[tT]elegram.*" }, {
  workspace = "special:scratchpad",
  float = true,
  size = { 550, 550 },
})

-- VK Музыка (WebApp) виджет на скретчпаде (над Telegram, ширина пол-монитора)
o.window({ class = "^chrome-(music\\.vk\\.com|vk\\.com__audio).*$" }, {
  workspace = "special:scratchpad",
  float = true,
  size = { 1100, 542 },
})

-- Автоматизация 3D-печати: Слайсер (PrusaSlicer / OrcaSlicer) и Fluidd на 3-м воркспейсе
-- Открытие одного открывает другой, закрытие одного закрывает другой
-- Пропорции: 75% ширина слайсера, 25% ширина Fluidd
o.window({ class = ".*([pP]rusa-[sS]licer|[pP]rusa[sS]licer|[oO]rca-[sS]licer|[oO]rca[sS]licer).*" }, {
  workspace = "3",
  tile = true,
})

o.window({ class = "^chrome-192\\.168\\.1\\.219.*$" }, {
  workspace = "3",
  tile = true,
})

o.window({ title = ".*[Ff]luidd.*" }, {
  workspace = "3",
  tile = true,
})

local function is_slicer_window(win)
  if not win then return false end
  local c = (win.class or ""):lower()
  local ic = (win.initial_class or ""):lower()
  return c:find("prusa%-slicer") ~= nil or c:find("prusaslicer") ~= nil or
         c:find("orca%-slicer") ~= nil or c:find("orcaslicer") ~= nil or
         ic:find("prusa%-slicer") ~= nil or ic:find("prusaslicer") ~= nil or
         ic:find("orca%-slicer") ~= nil or ic:find("orcaslicer") ~= nil
end

local function is_fluidd_window(win)
  if not win then return false end
  local c = (win.class or ""):lower()
  local t = (win.title or ""):lower()
  return c:find("192.168.1.219") ~= nil or t:find("fluidd") ~= nil
end

local function find_slicer_window()
  for _, win in ipairs(hl.get_windows()) do
    if is_slicer_window(win) and win.floating ~= 1 and win.floating ~= true then
      return win
    end
  end
  return nil
end

local function find_fluidd_window()
  for _, win in ipairs(hl.get_windows()) do
    if is_fluidd_window(win) and win.floating ~= 1 and win.floating ~= true then
      return win
    end
  end
  return nil
end

local had_slicer = (find_slicer_window() ~= nil)
local had_fluidd = (find_fluidd_window() ~= nil)
local is_syncing_action = false

local function adjust_slicer_fluidd_ratio()
  local slicer = find_slicer_window()
  local fluidd = find_fluidd_window()
  if not slicer or not fluidd then return end
  if not slicer.size or not fluidd.size or not slicer.at or not fluidd.at then return end

  local total_w = slicer.size.x + fluidd.size.x
  local target_slicer_w = math.floor(total_w * 0.75)
  local diff = target_slicer_w - slicer.size.x

  if math.abs(diff) < 50 then return end

  hl.dispatch(hl.dsp.focus({ window = "address:" .. slicer.address }))

  if slicer.at.x > fluidd.at.x then
    -- Слайсер справа от Fluidd: расширяем влево
    hl.dispatch(hl.dsp.window.resize({ x = -diff, y = 0, relative = true }))
  else
    -- Слайсер слева от Fluidd: расширяем вправо
    hl.dispatch(hl.dsp.window.resize({ x = diff, y = 0, relative = true }))
  end
end

local function on_window_open_handler(w)
  if not w then return end
  if w.floating == 1 or w.floating == true then return end

  local slicer_now = find_slicer_window()
  local fluidd_now = find_fluidd_window()

  if is_slicer_window(w) then
    had_slicer = true
    if not fluidd_now and not is_syncing_action then
      is_syncing_action = true
      hl.exec_cmd("google-chrome-stable --app=http://192.168.1.219/fluidd/")
      hl.timer(function() is_syncing_action = false end, { timeout = 2500, type = "oneshot" })
    end
    hl.timer(adjust_slicer_fluidd_ratio, { timeout = 600, type = "oneshot" })
    hl.timer(adjust_slicer_fluidd_ratio, { timeout = 1200, type = "oneshot" })
  elseif is_fluidd_window(w) then
    had_fluidd = true
    if not slicer_now and not is_syncing_action then
      is_syncing_action = true
      hl.exec_cmd("prusa-slicer")
      hl.timer(function() is_syncing_action = false end, { timeout = 2500, type = "oneshot" })
    end
    hl.timer(adjust_slicer_fluidd_ratio, { timeout = 600, type = "oneshot" })
    hl.timer(adjust_slicer_fluidd_ratio, { timeout = 1200, type = "oneshot" })
  end
end

local function on_window_destroy_handler(w)
  if is_syncing_action then return end

  hl.timer(function()
    if is_syncing_action then return end
    local slicer_now = find_slicer_window()
    local fluidd_now = find_fluidd_window()

    -- Если слайсер закрыт, но Fluidd открыт -> закрываем Fluidd
    if had_slicer and not slicer_now and fluidd_now then
      is_syncing_action = true
      had_slicer = false
      had_fluidd = false
      hl.dispatch(hl.dsp.window.close({ address = fluidd_now.address }))
      hl.timer(function() is_syncing_action = false end, { timeout = 1000, type = "oneshot" })
      return
    end

    -- Если Fluidd закрыт, но слайсер открыт -> закрываем слайсер
    if had_fluidd and not fluidd_now and slicer_now then
      is_syncing_action = true
      had_slicer = false
      had_fluidd = false
      hl.dispatch(hl.dsp.window.close({ address = slicer_now.address }))
      hl.timer(function() is_syncing_action = false end, { timeout = 1000, type = "oneshot" })
      return
    end

    had_slicer = (slicer_now ~= nil)
    had_fluidd = (fluidd_now ~= nil)
  end, { timeout = 150, type = "oneshot" })
end

hl.on("window.open", on_window_open_handler)
hl.on("window.destroy", on_window_destroy_handler)



