#!/usr/bin/env bash

# Цветовая палитра под тему Omarchy
CLR_PRIMARY="212"
CLR_ACCENT="141"
CLR_MUTED="245"
CLR_SUCCESS="120"

ui_banner() {
    clear >&2 2>/dev/null || true
    gum style \
        --foreground "$CLR_PRIMARY" \
        --border double \
        --border-foreground "$CLR_ACCENT" \
        --padding "1 2" \
        --margin "0 1" \
        --align center \
        "🌟 OMARCHY SYNC 🌟" \
        "Утилита гранулярной миграции и синхронизации окружения" >&2
}

ui_section() {
    local title="$1"
    gum style \
        --foreground "$CLR_SUCCESS" \
        --bold \
        --margin "1 0 0 1" \
        "▶ $title" >&2
}

ui_info() {
    local msg="$1"
    gum style --foreground "$CLR_MUTED" "  $msg" >&2
}

ui_select_main_action() {
    ui_banner
    gum choose \
        --cursor="➤ " \
        --cursor.foreground="$CLR_PRIMARY" \
        "📦 Создать полный бэкап (Git + Архив секретов)" \
        "🚀 Восстановить конфигурацию (Интерактивный мастер)" \
        "🔐 Экспортировать только архив секретов (secrets-bundle.tar.gz)" \
        "🔑 Восстановить только секреты из архива" \
        "⚙️ Отправить репозиторий на GitHub / GitLab" \
        "❌ Выход"
}

ui_select_categories() {
    ui_section "Выберите категории компонентов для восстановления:"
    ui_info "Навигация: [Стрелки], Выбор/Снятие: [Пробел], Подтвердить: [Enter]"

    gum choose --no-limit \
        --selected="Виджеты нижней панели (Omarchy Shell),Hyprland (хоткеи и стиль),Темы оформления и обои,Среда разработки (Antigravity / Opencode / Git),Пользовательские скрипты (~/.local/bin),Пакеты программ (Pacman / AUR),Секреты и сессии (из secrets-bundle)" \
        "Виджеты нижней панели (Omarchy Shell)" \
        "Hyprland (хоткеи и стиль)" \
        "Темы оформления и обои" \
        "Среда разработки (Antigravity / Opencode / Git)" \
        "Пользовательские скрипты (~/.local/bin)" \
        "Пакеты программ (Pacman / AUR)" \
        "Секреты и сессии (из secrets-bundle)" \
        "Рабочие проекты (interprocom + odoo_projects)"
}

ui_select_widgets() {
    ui_section "Настройка нижней панели: выберите нужные виджеты"
    ui_info "Отметьте только те виджеты, которые хотите видеть в баре:"

    gum choose --no-limit \
        --selected="yar.clock (Часы и дата),yar.workspaces (Рабочие столы),yar.player (Медиаплеер),yar.tray (Системный трей),yar.agents (Индикатор AI-агентов),yar.agents-manager (Менеджер AI),yar.sysinfo (Монитор CPU/RAM),omarchy.audio (Громкость),omarchy.network (Сеть Wi-Fi),omarchy.bluetooth (Bluetooth),omarchy.power (Батарея и питание),omarchy.keyboard-layout (Раскладка языка),omarchy.indicators (Индикаторы),omarchy.weather (Погода),omarchy.system-update (Обновления системы)" \
        "yar.clock (Часы и дата)" \
        "yar.workspaces (Рабочие столы)" \
        "yar.player (Медиаплеер)" \
        "yar.tray (Системный трей)" \
        "yar.agents (Индикатор AI-агентов)" \
        "yar.agents-manager (Менеджер AI)" \
        "yar.sysinfo (Монитор CPU/RAM)" \
        "omarchy.audio (Громкость)" \
        "omarchy.network (Сеть Wi-Fi)" \
        "omarchy.bluetooth (Bluetooth)" \
        "omarchy.power (Батарея и питание)" \
        "omarchy.keyboard-layout (Раскладка языка)" \
        "omarchy.indicators (Индикаторы)" \
        "omarchy.weather (Погода)" \
        "omarchy.system-update (Обновления системы)"
}

ui_select_hyprland() {
    ui_section "Hyprland: выберите файлы настроек"
    gum choose --no-limit \
        --selected="bindings.lua (Все горячие клавиши),looknfeel.lua (Рамки, зазоры, блюр, анимации),hyprland.lua (Главный конфиг),workspaces.lua (Правила рабочих столов),autostart.lua (Автозапуск программ)" \
        "bindings.lua (Все горячие клавиши)" \
        "looknfeel.lua (Рамки, зазоры, блюр, анимации)" \
        "hyprland.lua (Главный конфиг)" \
        "workspaces.lua (Правила рабочих столов)" \
        "autostart.lua (Автозапуск программ)"
}

ui_select_dev_tools() {
    ui_section "Среда разработки и AI"
    gum choose --no-limit \
        --selected="antigravity (Правила, скиллы, звуковые темы),opencode (Конфиги opencode.json и плагины),git (Глобальный gitconfig и lazygit),shell (Терминал Ghostty, Starship, zshrc)" \
        "antigravity (Правила, скиллы, звуковые темы)" \
        "opencode (Конфиги opencode.json и плагины)" \
        "git (Глобальный gitconfig и lazygit)" \
        "shell (Терминал Ghostty, Starship, zshrc)"
}

ui_select_packages() {
    ui_section "Пакеты программ для установки"
    gum choose --no-limit \
        --selected="dev_tooling (Разработка, Docker, компиляторы),terminal_cli (Ghostty, Starship, Zsh, утилиты поиска),desktop_apps (Офис, графические редакторы, просмотрщики),multimedia_tools (MPV, скриншоты, распознавание текста),aur_custom (Antigravity CLI, zapret, wallpicker)" \
        "dev_tooling (Разработка, Docker, компиляторы)" \
        "terminal_cli (Ghostty, Starship, Zsh, утилиты поиска)" \
        "desktop_apps (Офис, графические редакторы, просмотрщики)" \
        "multimedia_tools (MPV, скриншоты, распознавание текста)" \
        "aur_custom (Antigravity CLI, zapret, wallpicker)" \
        "gaming_streaming (Steam, Sunshine, Heroic - опционально)"
}

ui_select_secrets() {
    ui_section "Секреты и авторизации (из архива secrets-bundle.tar.gz)"
    gum choose --no-limit \
        --selected="ssh (SSH ключи id_rsa),keyrings (Системная связка паролей),opencode_auth (Авторизация Opencode auth.json),wifi (Профили Wi-Fi сетей)" \
        "ssh (SSH ключи id_rsa)" \
        "keyrings (Системная связка паролей)" \
        "opencode_auth (Авторизация Opencode auth.json)" \
        "wifi (Профили Wi-Fi сетей)"
}
