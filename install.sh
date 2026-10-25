#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SYNC_DIR="$HOME/.config/omarchy-sync"
DOTFILES_DIR="${OMARCHY_DOTFILES_DIR:-$HOME/omarchy-dotfiles}"

# Авто-обновление из Git при запуске из репозитория
if [ -d "$SCRIPT_DIR/.git" ]; then
    git -C "$SCRIPT_DIR" fetch origin master 2>/dev/null || true
    git -C "$SCRIPT_DIR" reset --hard origin/master 2>/dev/null || true
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

    echo "⚡ Запуск автономного полного восстановления..."
    
    # 1. Применяем конфигурации
    python3 -c "
import sys
from pathlib import Path
sys.path.append('$SYNC_DIR/lib')
import restore
restore.restore_all_autonomous(Path(sys.argv[1]))
" "$repo_path"

    # 2. Авто-поиск и применение архива секретов
    local sec_found=""
    if [ -f "$HOME/secrets-bundle.tar.gz" ]; then
        sec_found="$HOME/secrets-bundle.tar.gz"
    else
        for u in /run/media/*/*; do
            if [ -f "$u/secrets-bundle.tar.gz" ]; then
                sec_found="$u/secrets-bundle.tar.gz"
                break
            fi
        done
    fi

    if [ -n "$sec_found" ]; then
        echo " [+] Автоматически обнаружен архив секретов: $sec_found"
        restore_secrets_archive "$sec_found" "all"
    fi

    # 3. Авто-поиск архива interprocom
    local proj_found=""
    if [ -f "$HOME/interprocom-backup.tar.zst" ]; then
        proj_found="$HOME/interprocom-backup.tar.zst"
    elif [ -f "$HOME/interprocom-backup.tar.gz" ]; then
        proj_found="$HOME/interprocom-backup.tar.gz"
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
    gum style --foreground 120 --bold "🎉 Система полностью и автономно восстановлена!"
    echo "Все файлы разложены по местам, хоткеи, виджеты и темы активны."
}

cmd_backup() {
    ui_banner
    echo "Запуск полного резервного копирования..."
    python3 "$SYNC_DIR/lib/backup.py" "$DOTFILES_DIR"
    echo ""
    create_secrets_archive "$HOME/secrets-bundle.tar.gz"
    echo ""
    gum style --foreground 120 --bold "🎉 Полный бэкап успешно завершен!"
    echo "1. Открытые конфиги сохранены в локальный репозиторий: $DOTFILES_DIR"
    echo "2. Защищенный архив секретов создан: $HOME/secrets-bundle.tar.gz"
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
    local target_archive="${1:-$HOME/interprocom-backup.tar.zst}"
    echo "=== Архивация проектов interprocom и odoo_projects ==="
    echo "Целевой архив: $target_archive"
    echo "Упаковываем ~/interprocom и ~/odoo_projects с сохранением прав и БД..."
    
    sudo tar --zstd -cvf "$target_archive" -C "$HOME" interprocom odoo_projects
    sudo chown "$(id -u):$(id -g)" "$target_archive"
    gum style --foreground 120 --bold "✔ Архив проектов успешно создан: $target_archive"
}

# Роутер аргументов
ACTION="${1:-}"

case "$ACTION" in
    backup|--backup|-b)
        cmd_backup
        ;;
    backup-projects)
        cmd_backup_projects "${2:-$HOME/interprocom-backup.tar.zst}"
        ;;
    restore|--restore|-r)
        cmd_restore
        ;;
    secrets-backup|--secrets-backup)
        create_secrets_archive "${2:-$HOME/secrets-bundle.tar.gz}"
        ;;
    secrets-restore|--secrets-restore)
        restore_secrets_archive "${2:-$HOME/secrets-bundle.tar.gz}" "${3:-all}"
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
        echo "  backup, -b          Создать бэкап в Git + архив секретов"
        echo "  restore, -r         Запустить гранулярный мастер восстановления"
        echo "  secrets-backup      Создать только архив секретов"
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
                create_secrets_archive "$HOME/secrets-bundle.tar.gz"
                ;;
            *"Восстановить только секреты"*)
                restore_secrets_archive "$HOME/secrets-bundle.tar.gz" "all"
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
