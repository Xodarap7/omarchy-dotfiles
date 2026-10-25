#!/usr/bin/env bash
set -euo pipefail

SYNC_DIR="$HOME/.config/omarchy-sync"
DOTFILES_DIR="${OMARCHY_DOTFILES_DIR:-$HOME/omarchy-dotfiles}"

# Подключаем библиотеки
source "$SYNC_DIR/lib/ui.sh"
source "$SYNC_DIR/lib/secrets.sh"

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
                # Извлекаем ID (первое слово до пробела)
                w_id="$(echo "$w" | awk '{print $1}')"
                widget_ids+=("$w_id")
            done

            python3 -c "
import sys
from pathlib import Path
sys.path.append('$SYNC_DIR/lib')
import restore
restore.restore_shell_widgets(Path('$repo_path'), ${widget_ids[@]+$(printf "'%s', " "${widget_ids[@]}")[]})
"
        fi
    done

    # 3. Обработка Hyprland
    for cat in "${selected_cats[@]}"; do
        if [[ "$cat" =~ "Hyprland" ]]; then
            mapfile -t raw_hypr < <(ui_select_hyprland)
            hypr_files=()
            for h in "${raw_hypr[@]}"; do
                h_file="$(echo "$h" | awk '{print $1}')"
                hypr_files+=("$h_file")
            done

            python3 -c "
import sys
from pathlib import Path
sys.path.append('$SYNC_DIR/lib')
import restore
restore.restore_hyprland_files(Path('$repo_path'), ${hypr_files[@]+$(printf "'%s', " "${hypr_files[@]}")[]})
"
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
restore.restore_themes_and_wallpapers(Path('$repo_path'), True, True)
"
        fi
    done

    # 5. Обработка Dev & AI
    for cat in "${selected_cats[@]}"; do
        if [[ "$cat" =~ "Среда разработки" ]]; then
            mapfile -t raw_dev < <(ui_select_dev_tools)
            dev_tools=()
            for d in "${raw_dev[@]}"; do
                d_id="$(echo "$d" | awk '{print $1}')"
                dev_tools+=("$d_id")
            done

            python3 -c "
import sys
from pathlib import Path
sys.path.append('$SYNC_DIR/lib')
import restore
restore.restore_dev_and_ai(Path('$repo_path'), ${dev_tools[@]+$(printf "'%s', " "${dev_tools[@]}")[]})
"
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

# Роутер аргументов
ACTION="${1:-}"

case "$ACTION" in
    backup|--backup|-b)
        cmd_backup
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
            *"Создать полный бэкап"*)
                cmd_backup
                ;;
            *"Восстановить конфигурацию"*)
                cmd_restore
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
