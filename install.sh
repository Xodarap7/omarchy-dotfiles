#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SYNC_DIR="$HOME/.config/omarchy-sync"
DOTFILES_DIR="${OMARCHY_DOTFILES_DIR:-$HOME/omarchy-dotfiles}"

# Авто-обновление из Git при запуске из репозитория
if [ -d "$SCRIPT_DIR/.git" ]; then
    git -C "$SCRIPT_DIR" fetch git@github.com:Xodarap7/omarchy-dotfiles.git master 2>/dev/null || git -C "$SCRIPT_DIR" fetch https://github.com/Xodarap7/omarchy-dotfiles.git master 2>/dev/null || git -C "$SCRIPT_DIR" fetch origin master 2>/dev/null || true
    git -C "$SCRIPT_DIR" reset --hard FETCH_HEAD 2>/dev/null || git -C "$SCRIPT_DIR" reset --hard origin/master 2>/dev/null || true
fi

# Самоустановка / Bootstrap при запуске
mkdir -p "$SYNC_DIR" "$HOME/.local/bin"
if [ -d "$SCRIPT_DIR/config/omarchy-sync" ]; then
    cp -a "$SCRIPT_DIR/config/omarchy-sync/"* "$SYNC_DIR/"
elif [ -d "$DOTFILES_DIR/config/omarchy-sync" ]; then
    cp -a "$DOTFILES_DIR/config/omarchy-sync/"* "$SYNC_DIR/"
fi
cp -a "$SCRIPT_DIR/$(basename "${BASH_SOURCE[0]}")" "$HOME/.local/bin/omarchy-sync" 2>/dev/null || true
chmod +x "$HOME/.local/bin/omarchy-sync" "$SYNC_DIR/lib/"*.py "$SYNC_DIR/lib/"*.sh 2>/dev/null || true

# Подключаем библиотеки
source "$SYNC_DIR/lib/ui.sh"
source "$SYNC_DIR/lib/secrets.sh"

cmd_restore_autonomous() {
    ui_banner
    local repo_path="$DOTFILES_DIR"
    if [ ! -d "$repo_path" ] || [ ! -f "$repo_path/config/omarchy/shell.json" ]; then
        repo_path="$SCRIPT_DIR"
    fi

    local profile="${1:-}"
    if [ -z "$profile" ]; then
        local choice
        choice="$(gum choose --header="Выберите вариант конфигурации системы:" \
            "💻 Ноутбучный вариант (5 рабочих столов, адаптивный бар, CPU/RAM без GPU)" \
            "🖥️ Полная копия ПК (8 рабочих столов, полный бар с GPU и VRAM)")"
        if [[ "$choice" =~ "Ноутбучный" ]]; then
            profile="laptop"
        else
            profile="desktop"
        fi
    fi

    echo "⚡ Запуск автономного полного восстановления [Профиль: $profile]..."
    
    # 0. Настройка бесконечного sudo без пароля (для Opencode, скриптов и фоновых процессов)
    local target_user="${USER:-$(id -un)}"
    local sudoers_file="/etc/sudoers.d/10-nopasswd"
    if [ ! -f "$sudoers_file" ] || ! grep -q "$target_user ALL=(ALL) NOPASSWD: ALL" "$sudoers_file" 2>/dev/null; then
        echo "🔐 Настройка бесконечного sudo без пароля (NOPASSWD: ALL)..."
        echo "$target_user ALL=(ALL) NOPASSWD: ALL" | sudo tee "$sudoers_file" >/dev/null
        sudo chmod 0440 "$sudoers_file"
        echo "✔ Правило NOPASSWD: ALL успешно записано в $sudoers_file"
    fi

    # 0.1 Настройка таймаута загрузчика (Limine -> 0.5 сек)
    if [ -f /boot/limine.conf ]; then
        echo "⚡ Настройка таймаута загрузчика Limine (0.5 сек)..."
        if grep -qE '^#?timeout:' /boot/limine.conf; then
            sudo sed -i -E 's/^#?timeout:.*/timeout: 0.5/' /boot/limine.conf
        else
            sudo sed -i '1a timeout: 0.5' /boot/limine.conf
        fi
        echo "✔ Таймаут загрузчика Limine установлен в 0.5 сек."
    fi

    # 0.2 Настройка тачпада для профиля ноутбука (kernel bug #220783 i2c_designware)
    if [ "$profile" = "laptop" ]; then
        local fix_script="$repo_path/profiles/laptop/bin/touchpad-irq-fix.sh"
        local svc_boot="$repo_path/profiles/laptop/systemd/touchpad-irq-fix.service"
        local svc_resume="$repo_path/profiles/laptop/systemd/touchpad-irq-fix-resume.service"
        if [ -f "$fix_script" ] && [ -f "$svc_boot" ] && [ -f "$svc_resume" ]; then
            echo "🖱️ Применение фикса тачпада для ноутбука (kernel #220783)..."
            sudo install -m 755 "$fix_script" /usr/local/bin/touchpad-irq-fix.sh
            sudo install -m 644 "$svc_boot" /etc/systemd/system/touchpad-irq-fix.service
            sudo install -m 644 "$svc_resume" /etc/systemd/system/touchpad-irq-fix-resume.service
            sudo systemctl daemon-reload
            sudo systemctl enable touchpad-irq-fix.service touchpad-irq-fix-resume.service 2>/dev/null || true
            sudo /usr/local/bin/touchpad-irq-fix.sh 2>/dev/null || true
            echo "✔ Сервисы авто-восстановления тачпада установлены и включены."
        fi
    fi

    # 1. Установка официальных системных пакетов из pacman/omarchy
    if [ -f "$repo_path/manifests/packages.json" ]; then
        echo "📦 Проверка и установка официальных системных пакетов..."
        python3 "$SYNC_DIR/lib/pkg_manager.py" "$repo_path/manifests/packages.json" "dev_tooling,terminal_cli,desktop_apps,multimedia_tools,aur_custom" || true
    fi

    # 2. Применяем базовые конфигурации и оверлей профиля
    python3 -c "
import sys
from pathlib import Path
sys.path.append('$SYNC_DIR/lib')
import restore
restore.restore_all_autonomous(Path(sys.argv[1]), sys.argv[2])
" "$repo_path" "$profile"

    # 3. Авто-поиск и применение архива ключей и секретов (keys.tar.zst)
    local sec_found=""
    if [ -f "$HOME/backup/keys.tar.zst" ]; then
        sec_found="$HOME/backup/keys.tar.zst"
    elif [ -f "$HOME/backups/keys.tar.zst" ]; then
        sec_found="$HOME/backups/keys.tar.zst"
    elif [ -f "$HOME/keys.tar.zst" ]; then
        sec_found="$HOME/keys.tar.zst"
    elif [ -f "$HOME/backup/secrets-bundle.tar.zst" ]; then
        sec_found="$HOME/backup/secrets-bundle.tar.zst"
    elif [ -f "$HOME/secrets-bundle.tar.zst" ]; then
        sec_found="$HOME/secrets-bundle.tar.zst"
    elif [ -f "$SCRIPT_DIR/backup/keys.tar.zst" ]; then
        sec_found="$SCRIPT_DIR/backup/keys.tar.zst"
    elif [ -f "$SCRIPT_DIR/keys.tar.zst" ]; then
        sec_found="$SCRIPT_DIR/keys.tar.zst"
    else
        for u in /run/media/*/*; do
            if [ -f "$u/backup/keys.tar.zst" ]; then
                sec_found="$u/backup/keys.tar.zst"
                break
            elif [ -f "$u/keys.tar.zst" ]; then
                sec_found="$u/keys.tar.zst"
                break
            elif [ -f "$u/secrets-bundle.tar.zst" ]; then
                sec_found="$u/secrets-bundle.tar.zst"
                break
            fi
        done
    fi

    if [ -z "$sec_found" ]; then
        if ping -c 1 -W 1 192.168.1.170 &>/dev/null; then
            echo " [+] Обнаружен основной ПК в сети (192.168.1.170). Пробуем скачать ~/backup..."
            mkdir -p "$HOME/backup"
            if rsync -e "ssh -o ConnectTimeout=3 -o StrictHostKeyChecking=no" -P -r yar@192.168.1.170:~/backup/ "$HOME/backup/" 2>/dev/null; then
                if [ -f "$HOME/backup/keys.tar.zst" ]; then
                    sec_found="$HOME/backup/keys.tar.zst"
                    echo "✔ Папка ~/backup успешно скачана с основного ПК!"
                fi
            fi
        fi
    fi

    if [ -n "$sec_found" ]; then
        echo " [+] Автоматически обнаружен архив секретов: $sec_found"
        restore_secrets_archive "$sec_found" "all"
    else
        echo ""
        gum style --foreground 214 --bold "⚠️ Внимание: архив keys.tar.zst не обнаружен в ~/backup или на USB-носителе!"
        echo "   Для переноса всех секретов и проектов выполните одну команду на ноутбуке:"
        echo "   scp -r yar@192.168.1.170:~/backup ~/"
        echo "   omarchy-sync secrets-restore ~/backup/keys.tar.zst"
        echo ""
    fi

    # 4. Авто-поиск архива рабочих проектов (projects.tar.zst)
    local proj_found=""
    if [ -f "$HOME/backup/projects.tar.zst" ]; then
        proj_found="$HOME/backup/projects.tar.zst"
    elif [ -f "$HOME/backups/projects.tar.zst" ]; then
        proj_found="$HOME/backups/projects.tar.zst"
    elif [ -f "$HOME/projects.tar.zst" ]; then
        proj_found="$HOME/projects.tar.zst"
    elif [ -f "$HOME/interprocom-backup.tar.zst" ]; then
        proj_found="$HOME/interprocom-backup.tar.zst"
    elif [ -f "$SCRIPT_DIR/backup/projects.tar.zst" ]; then
        proj_found="$SCRIPT_DIR/backup/projects.tar.zst"
    elif [ -f "$SCRIPT_DIR/projects.tar.zst" ]; then
        proj_found="$SCRIPT_DIR/projects.tar.zst"
    else
        for u in /run/media/*/*; do
            if [ -f "$u/backup/projects.tar.zst" ]; then
                proj_found="$u/backup/projects.tar.zst"
                break
            elif [ -f "$u/projects.tar.zst" ]; then
                proj_found="$u/projects.tar.zst"
                break
            fi
        done
    fi

    if [ -n "$proj_found" ]; then
        echo " [+] Автоматически обнаружен архив проектов: $proj_found"
        python3 -c "
import sys
from pathlib import Path
sys.path.append('$SYNC_DIR/lib')
import restore
restore.restore_work_projects(Path(sys.argv[1]))
" "$proj_found"
    fi

    # Перезагружаем интерфейс
    hyprctl reload 2>/dev/null || true
    omarchy restart shell 2>/dev/null || true

    echo ""
    gum style --foreground 120 --bold "🎉 Система полностью и автономно восстановлена [Профиль: $profile]!"
    echo "Все файлы разложены по местам, хоткеи, виджеты и темы активны."
}

cmd_backup() {
    ui_banner
    echo "Запуск полного резервного копирования..."
    python3 "$SYNC_DIR/lib/backup.py" "$DOTFILES_DIR"
    echo ""
    mkdir -p "$HOME/backup"
    create_secrets_archive "$HOME/backup/keys.tar.zst"
    echo ""
    gum style --foreground 120 --bold "🎉 Полный бэкап успешно завершен!"
    echo "1. Открытые конфиги сохранены в локальный репозиторий: $DOTFILES_DIR"
    echo "2. Защищенный архив секретов создан: $HOME/backup/keys.tar.zst"
}

cmd_restore() {
    ui_banner
    local repo_path="$DOTFILES_DIR"

    if [ ! -d "$repo_path" ]; then
        repo_path="$(gum input --value="$DOTFILES_DIR" --placeholder="Путь к репозиторию omarchy-dotfiles")"
        if [ ! -d "$repo_path" ]; then
            gum style --foreground 196 "Ошибка: репозиторий по пути '$repo_path' не найден!"
            return 1
        fi
    fi

    # 1. Выбор категорий
    mapfile -t selected_cats < <(ui_select_categories)
    if [ ${#selected_cats[@]} -eq 0 ]; then
        echo "Ничего не выбрано. Отмена."
        return 0
    fi

    echo ""
    echo "Выбранные категории: ${#selected_cats[@]}"

    # 2. Обработка Виджетов бара
    for cat in "${selected_cats[@]}"; do
        if [[ "$cat" =~ "Виджеты нижней панели" ]]; then
            mapfile -t raw_widgets < <(ui_select_widgets)
            widget_ids=()
            for w in "${raw_widgets[@]}"; do
                w_id="$(echo "$w" | awk '{print $1}')"
                if [[ -n "$w_id" && "$w_id" != "▶"* && "$w_id" != "Отметьте"* ]]; then
                    widget_ids+=("$w_id")
                fi
            done

            python3 -c "
import sys
from pathlib import Path
sys.path.append('$SYNC_DIR/lib')
import restore
restore.restore_shell_widgets(Path(sys.argv[1]), sys.argv[2:])
" "$repo_path" "${widget_ids[@]}"
        fi
    done

    # 3. Обработка Hyprland
    for cat in "${selected_cats[@]}"; do
        if [[ "$cat" =~ "Hyprland" ]]; then
            mapfile -t raw_hypr < <(ui_select_hyprland)
            hypr_files=()
            for h in "${raw_hypr[@]}"; do
                h_file="$(echo "$h" | awk '{print $1}')"
                if [[ -n "$h_file" && "$h_file" != "▶"* && "$h_file" != "Отметьте"* ]]; then
                    hypr_files+=("$h_file")
                fi
            done

            python3 -c "
import sys
from pathlib import Path
sys.path.append('$SYNC_DIR/lib')
import restore
restore.restore_hyprland_files(Path(sys.argv[1]), sys.argv[2:])
" "$repo_path" "${hypr_files[@]}"
        fi
    done

    # 4. Обработка тем и обоев
    for cat in "${selected_cats[@]}"; do
        if [[ "$cat" =~ "Темы оформления и обои" ]]; then
            python3 -c "
import sys
from pathlib import Path
sys.path.append('$SYNC_DIR/lib')
import restore
restore.restore_themes_and_wallpapers(Path(sys.argv[1]), True, True)
" "$repo_path"
        fi
    done

    # 5. Обработка Dev & AI
    for cat in "${selected_cats[@]}"; do
        if [[ "$cat" =~ "Среда разработки" ]]; then
            mapfile -t raw_dev < <(ui_select_dev_tools)
            dev_tools=()
            for d in "${raw_dev[@]}"; do
                d_id="$(echo "$d" | awk '{print $1}')"
                if [[ -n "$d_id" && "$d_id" != "▶"* && "$d_id" != "Отметьте"* ]]; then
                    dev_tools+=("$d_id")
                fi
            done

            python3 -c "
import sys
from pathlib import Path
sys.path.append('$SYNC_DIR/lib')
import restore
restore.restore_dev_and_ai(Path(sys.argv[1]), sys.argv[2:])
" "$repo_path" "${dev_tools[@]}"
        fi
    done

    # 6. Обработка скриптов
    for cat in "${selected_cats[@]}"; do
        if [[ "$cat" =~ "Пользовательские скрипты" ]]; then
            python3 -c "
import sys
from pathlib import Path
sys.path.append('$SYNC_DIR/lib')
import restore
restore.restore_user_scripts(Path('$repo_path'), ['all'])
"
        fi
    done

    # 7. Обработка пакетов софта
    for cat in "${selected_cats[@]}"; do
        if [[ "$cat" =~ "Пакеты программ" ]]; then
            mapfile -t raw_pkgs < <(ui_select_packages)
            pkg_cats=()
            for p in "${raw_pkgs[@]}"; do
                p_id="$(echo "$p" | awk '{print $1}')"
                pkg_cats+=("$p_id")
            done

            if [ ${#pkg_cats[@]} -gt 0 ]; then
                python3 "$SYNC_DIR/lib/pkg_manager.py" "$repo_path/manifests/packages.json" "$(IFS=,; echo "${pkg_cats[*]}")"
            fi
        fi
    done

    # 8. Обработка секретов
    for cat in "${selected_cats[@]}"; do
        if [[ "$cat" =~ "Секреты и сессии" ]]; then
            local sec_path="$HOME/secrets-bundle.tar.gz"
            if [ ! -f "$sec_path" ]; then
                sec_path="$(gum input --value="$HOME/secrets-bundle.tar.gz" --placeholder="Путь к secrets-bundle.tar.gz")"
            fi
            if [ -f "$sec_path" ]; then
                mapfile -t raw_sec < <(ui_select_secrets)
                sec_items=()
                for s in "${raw_sec[@]}"; do
                    s_id="$(echo "$s" | awk '{print $1}')"
                    sec_items+=("$s_id")
                done
                restore_secrets_archive "$sec_path" "$(IFS=,; echo "${sec_items[*]}")"
            else
                gum style --foreground 196 "Файл секретов $sec_path не найден. Пропуск восстановления секретов."
            fi
        fi
    done

    # 9. Обработка рабочих проектов (interprocom)
    for cat in "${selected_cats[@]}"; do
        if [[ "$cat" =~ "Рабочие проекты" ]]; then
            local proj_archive="$HOME/interprocom-backup.tar.zst"
            if [ ! -f "$proj_archive" ]; then
                proj_archive="$HOME/interprocom-backup.tar.gz"
            fi
            if [ ! -f "$proj_archive" ]; then
                proj_archive="$(gum input --value="$HOME/interprocom-backup.tar.zst" --placeholder="Путь к архиву проектов interprocom")"
            fi
            if [ -f "$proj_archive" ]; then
                python3 -c "
import sys
from pathlib import Path
sys.path.append('$SYNC_DIR/lib')
import restore
restore.restore_work_projects(Path('$proj_archive'))
"
            else
                gum style --foreground 196 "Файл архива $proj_archive не найден. Пропуск восстановления проектов."
            fi
        fi
    done

    echo ""
    gum style --foreground 120 --bold "✨ Выборочное восстановление компонентов успешно завершено!"
    echo "Интерфейс и службы обновлены."
}

cmd_git_push() {
    ui_banner
    if [ ! -d "$DOTFILES_DIR/.git" ]; then
        gum style --foreground 196 "Ошибка: каталог $DOTFILES_DIR не является Git-репозиторием. Сначала выполните бэкап."
        return 1
    fi

    cd "$DOTFILES_DIR"
    local current_remote
    current_remote="$(git remote get-url origin 2>/dev/null || true)"

    if [ -z "$current_remote" ]; then
        echo "Удаленный репозиторий еще не привязан."
        local remote_url
        remote_url="$(gum input --placeholder="git@github.com:username/omarchy-dotfiles.git")"
        if [ -n "$remote_url" ]; then
            git remote add origin "$remote_url"
            echo " [+] Добавлен remote origin: $remote_url"
        else
            echo "Отмена."
            return 0
        fi
    else
        echo "Текущий репозиторий: $current_remote"
    fi

    if gum confirm "Отправить текущие изменения в Git?"; then
        git push -u origin master || git push -u origin main
        gum style --foreground 120 "✔ Изменения успешно отправлены в Git!"
    fi
}

cmd_backup_projects() {
    ui_banner
    local target_archive="${1:-$HOME/backup/projects.tar.zst}"
    echo "=== Архивация проектов interprocom и odoo_projects ==="
    echo "Целевой архив: $target_archive"
    echo "Упаковываем ~/interprocom и ~/odoo_projects с сохранением прав и БД..."
    mkdir -p "$(dirname "$target_archive")"
    sudo tar --zstd -cvf "$target_archive" -C "$HOME" interprocom odoo_projects
    sudo chown "$(id -u):$(id -g)" "$target_archive"
    gum style --foreground 120 --bold "✔ Архив проектов успешно создан: $target_archive"
}

# Роутер аргументов
ACTION="${1:-}"

case "$ACTION" in
    laptop|--laptop)
        cmd_restore_autonomous "laptop"
        ;;
    desktop|--desktop)
        cmd_restore_autonomous "desktop"
        ;;
    backup|--backup|-b)
        cmd_backup
        ;;
    backup-projects)
        cmd_backup_projects "${2:-$HOME/backup/projects.tar.zst}"
        ;;
    backup-all)
        mkdir -p "$HOME/backup"
        create_secrets_archive "$HOME/backup/keys.tar.zst"
        cmd_backup_projects "$HOME/backup/projects.tar.zst"
        ;;
    restore|--restore|-r)
        cmd_restore
        ;;
    secrets-backup|--secrets-backup)
        create_secrets_archive "${2:-$HOME/backup/keys.tar.zst}"
        ;;
    secrets-restore|--secrets-restore)
        restore_secrets_archive "${2:-$HOME/backup/keys.tar.zst}" "${3:-all}"
        ;;
    push|--push)
        cmd_git_push
        ;;
    help|--help|-h)
        ui_banner
        echo "Использование: omarchy-sync [КОМАНДА]"
        echo ""
        echo "Команды:"
        echo "  (без параметров)    Запуск интерактивного TUI меню"
        echo "  backup, -b          Создать бэкап в Git + архив секретов ~/backup/keys.tar.zst"
        echo "  backup-projects     Создать архив проектов ~/backup/projects.tar.zst"
        echo "  backup-all          Создать бэкап всех секретов и проектов в ~/backup/"
        echo "  restore, -r         Запустить гранулярный мастер восстановления"
        echo "  secrets-backup      Создать только архив секретов (~/backup/keys.tar.zst)"
        echo "  secrets-restore     Восстановить секреты из архива"
        echo "  push, --push        Отправить локальный репозиторий в GitHub/GitLab"
        echo "  help, -h            Показать эту справку"
        ;;
    "")
        # Интерактивное главное меню
        CHOICE="$(ui_select_main_action)"
        case "$CHOICE" in
            *"Автономное полное восстановление"*)
                cmd_restore_autonomous
                ;;
            *"Выборочное восстановление"*)
                cmd_restore
                ;;
            *"Создать полный бэкап"*)
                cmd_backup
                ;;
            *"Экспортировать только архив секретов"*)
                create_secrets_archive "$HOME/backup/keys.tar.zst"
                ;;
            *"Восстановить только секреты"*)
                restore_secrets_archive "$HOME/backup/keys.tar.zst" "all"
                ;;
            *"Отправить репозиторий"*)
                cmd_git_push
                ;;
            *)
                echo "Выход."
                exit 0
                ;;
        esac
        ;;
    *)
        echo "Неизвестная команда: $ACTION. Используйте 'omarchy-sync --help'"
        exit 1
        ;;
esac
