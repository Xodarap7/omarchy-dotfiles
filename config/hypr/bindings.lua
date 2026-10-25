-- Keep only your personal keybinding overrides here. Add new bindings or
-- unbind defaults before replacing them.

-- See current bindings and descriptions:
--   omarchy menu keybindings --print

-- To disable every Omarchy default binding, set this in
-- ~/.config/hypr/hyprland.lua before require("default.hypr.omarchy"), then add
-- only the bindings you want below:
--   omarchy_default_bindings = false

-- To disable all preinstalled app/webapp bindings, set:
--   omarchy_preinstalled_bindings = false

-- Add a new binding.
-- o.bind("SUPER + SHIFT + R", "SSH", "alacritty -e ssh your-server")

-- Change an existing binding by unbinding it first, then binding the key again.
-- This example changes SUPER+SPACE from the launcher to the Omarchy root menu.
-- hl.unbind("SUPER + SPACE")
-- o.bind("SUPER + SPACE", "Omarchy menu", "omarchy-menu toggle root")

-- Disable a default binding without replacing it.
-- hl.unbind("SUPER + SHIFT + B")

-- Отключены: меню тем и смена обоев
hl.unbind("SUPER + CTRL + SPACE")
hl.unbind("SUPER + SHIFT + CTRL + SPACE")

-- Antigravity CLI
o.bind("SUPER + A", "Antigravity CLI", { tui = "agy" })

-- OpenCode TUI
o.bind("SUPER + ALT + A", "OpenCode", { tui = "opencode" })

-- Antigravity IDE (ранее SUPER + SHIFT + A было привязано к ChatGPT)
hl.unbind("SUPER + SHIFT + A")
o.bind("SUPER + SHIFT + A", "Antigravity IDE", { launch = "antigravity-ide --new-window" })

-- Отключен хоткей Google Maps
hl.unbind("SUPER + SHIFT + S")

-- Виджеты (ВК Музыка и Telegram) на скретчпаде (ранее SUPER + S был стандартным скретчпадом)
hl.unbind("SUPER + S")
o.bind("SUPER + S", "Виджеты (ВК Музыка и Telegram)", "~/.local/bin/omarchy-scratchpad-music")

-- Pixel-perfect HD скриншоты без мыла и интерполяции (ранее PRINT был omarchy-capture-screenshot)
hl.unbind("PRINT")
o.bind("PRINT", "Снимок экрана (HD)", "~/.local/bin/omarchy-screenshot-hd")




-- Logitech MX Keys examples:
-- o.bind("SUPER + SHIFT + S", nil, "omarchy-capture-screenshot")
-- o.bind("SUPER + H", nil, "voxtype record toggle")
-- o.bind("SUPER + PERIOD", nil, "omarchy-shell shell toggle omarchy.emojis")
