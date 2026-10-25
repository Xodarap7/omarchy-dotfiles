-- Change the default Omarchy look'n'feel.

-- https://wiki.hypr.land/Configuring/Basics/Variables/#general
-- hl.config({
--   general = {
--     -- No gaps between windows or borders.
--     gaps_in = 0,
--     gaps_out = 0,
--     border_size = 0,
--
--     -- Change to niri-like side-scrolling layout.
--     layout = "scrolling",
--   },
-- })

-- https://wiki.hypr.land/Configuring/Basics/Variables/#decoration
-- hl.config({
--   decoration = {
--     -- Use round window corners.
--     rounding = 8,
--
--     -- Dim unfocused windows (0.0 = no dim, 1.0 = fully dimmed).
--     dim_inactive = true,
--     dim_strength = 0.15,
--   },
-- })

-- https://wiki.hypr.land/Configuring/Basics/Variables/#animations
-- hl.config({
--   animations = {
--     -- Disable all animations.
--     enabled = false,
--   },
-- })

-- https://wiki.hypr.land/Configuring/Basics/Variables/#layout
-- hl.config({
--   layout = {
--     -- Avoid overly wide single-window layouts on wide screens.
--     single_window_aspect_ratio = { 1, 1 },
--   },
-- })

-- https://wiki.hypr.land/Configuring/Layouts/Scrolling-Layout/
-- hl.config({
--   scrolling = {
--     -- See only one column per screen instead of two.
--     column_width = 0.97,
--   },
-- })

-- Разрешить тиринг / разблокировать FPS для игр с immediate = true
-- Выделение активного окна зеленым цветом
local active_border_green = { colors = { "rgba(9ece6aee)", "rgba(73ca8aee)" }, angle = 45 }

hl.config({
  general = {
    gaps_in = 2,
    gaps_out = 5,
    allow_tearing = true,
    col = {
      active_border = active_border_green,
    },
  },
  decoration = {
    active_opacity = 0.97,
    inactive_opacity = 0.94,
    blur = {
      enabled = true,
      size = 4,
      passes = 2,
    },
  },
  group = {
    col = {
      border_active = active_border_green,
    },
  },
  misc = {
    -- Запретить фоновым окнам воровать фокус при запросе активации (уведомления, клики по ссылкам и т.д.)
    focus_on_activate = false,
    -- Отключено: иначе при вылете/закрытии полноэкранной игры фокусное окно (браузер, IDE и т.д.) распахивается на весь экран
    exit_window_retains_fullscreen = false,
  },
})

-- Очень лёгкая полупрозрачность (активное / неактивное / полноэкранное)
o.window({ tag = "default-opacity" }, { opacity = "0.97 0.94 1.0" })
o.window({ tag = "chromium-based-browser" }, { opacity = "0.99 0.96 1.0" })
o.window({ tag = "firefox-based-browser" }, { opacity = "0.99 0.96 1.0" })

