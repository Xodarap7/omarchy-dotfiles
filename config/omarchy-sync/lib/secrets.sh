#!/usr/bin/env bash
set -euo pipefail

create_secrets_archive() {
    local target_archive="${1:-$HOME/backup/keys.tar.zst}"
    local tmp_dir
    tmp_dir="$(mktemp -d /tmp/omarchy-secrets-XXXXXX)"

    echo "=== Создание архива секретов: $target_archive ==="
    mkdir -p "$tmp_dir/data" "$(dirname "$target_archive")"

    # 1. SSH ключи
    if [ -d "$HOME/.ssh" ]; then
        echo " [+] Упаковка SSH ключей (~/.ssh)..."
        cp -a "$HOME/.ssh" "$tmp_dir/data/ssh"
    fi

    # 2. Keyrings
    if [ -d "$HOME/.local/share/keyrings" ]; then
        echo " [+] Упаковка системной связки паролей (~/.local/share/keyrings)..."
        mkdir -p "$tmp_dir/data/local_share"
        cp -a "$HOME/.local/share/keyrings" "$tmp_dir/data/local_share/keyrings"
    fi

    # 3. Opencode Auth
    mkdir -p "$tmp_dir/data/opencode"
    if [ -f "$HOME/.local/share/opencode/auth.json" ]; then
        echo " [+] Упаковка авторизации Opencode (auth.json)..."
        cp -a "$HOME/.local/share/opencode/auth.json" "$tmp_dir/data/opencode/auth.json"
    fi
    if command -v opencode >/dev/null 2>&1; then
        echo " [+] Экспорт учетных записей Opencode (opencode auth export)..."
        opencode auth export > "$tmp_dir/data/opencode/auth_export.json" 2>/dev/null || true
    fi

    # 4. Antigravity CLI Auth & State
    mkdir -p "$tmp_dir/data/antigravity-cli"
    if command -v secret-tool >/dev/null 2>&1; then
        local agy_token
        agy_token="$(secret-tool lookup service gemini username antigravity 2>/dev/null || true)"
        if [ -n "$agy_token" ]; then
            echo " [+] Упаковка Google OAuth токена для Antigravity CLI..."
            echo "$agy_token" > "$tmp_dir/data/antigravity-cli/token.json"
            chmod 600 "$tmp_dir/data/antigravity-cli/token.json"
        fi
    fi
    if [ -d "$HOME/.gemini/antigravity-cli" ]; then
        echo " [+] Упаковка состояния онбординга Antigravity CLI..."
        for f in jetski_state.pbtxt installation_id settings.json; do
            if [ -f "$HOME/.gemini/antigravity-cli/$f" ]; then
                cp -a "$HOME/.gemini/antigravity-cli/$f" "$tmp_dir/data/antigravity-cli/"
            fi
        done
    fi
    if [ -d "$HOME/.gemini/config" ]; then
        cp -a "$HOME/.gemini/config" "$tmp_dir/data/antigravity-cli/config"
    fi

    # 5. Antigravity IDE
    if [ -d "$HOME/.local/share/antigravity-ide" ]; then
        echo " [+] Упаковка Antigravity IDE (~/.local/share/antigravity-ide)..."
        cp -a "$HOME/.local/share/antigravity-ide" "$tmp_dir/data/antigravity-ide"
    fi

    # 6. Wi-Fi профили NetworkManager (если есть доступ к sudo)
    if sudo -n true 2>/dev/null; then
        echo " [+] Упаковка Wi-Fi профилей (/etc/NetworkManager/system-connections)..."
        mkdir -p "$tmp_dir/data/network"
        sudo cp -a /etc/NetworkManager/system-connections "$tmp_dir/data/network/" 2>/dev/null || true
        sudo chown -R "$(id -u):$(id -g)" "$tmp_dir/data/network" 2>/dev/null || true
    fi

    if [[ "$target_archive" == *.zst ]]; then
        tar --zstd -cf "$target_archive" -C "$tmp_dir/data" .
    else
        tar -czf "$target_archive" -C "$tmp_dir/data" .
    fi
    rm -rf "$tmp_dir"
    chmod 600 "$target_archive"
    echo "✔ Архив секретов успешно создан: $target_archive (права 600)"
}

restore_secrets_archive() {
    local source_archive="${1:-$HOME/backup/keys.tar.zst}"
    local selected_items="${2:-all}" # "ssh,keyrings,opencode_auth,wifi,ide"

    if [ ! -f "$source_archive" ]; then
        echo "ОШИБКА: Файл архива $source_archive не найден!" >&2
        return 1
    fi

    local tmp_dir
    tmp_dir="$(mktemp -d /tmp/omarchy-restore-secrets-XXXXXX)"
    if [[ "$source_archive" == *.zst ]]; then
        tar --zstd -xf "$source_archive" -C "$tmp_dir"
    else
        tar -xzf "$source_archive" -C "$tmp_dir"
    fi

    # SSH
    if [[ "$selected_items" == "all" || "$selected_items" =~ "ssh" ]]; then
        if [ -d "$tmp_dir/ssh" ]; then
            echo " [+] Восстановление SSH ключей..."
            mkdir -p "$HOME/.ssh"
            cp -a "$tmp_dir/ssh/"* "$HOME/.ssh/" 2>/dev/null || true
            chmod 700 "$HOME/.ssh"
            find "$HOME/.ssh" -type f -exec chmod 600 {} +
            find "$HOME/.ssh" -name "*.pub" -exec chmod 644 {} + 2>/dev/null || true
        fi
    fi

    # Keyrings
    if [[ "$selected_items" == "all" || "$selected_items" =~ "keyrings" ]]; then
        if [ -d "$tmp_dir/local_share/keyrings" ]; then
            echo " [+] Восстановление системного Keyring..."
            mkdir -p "$HOME/.local/share/keyrings"
            cp -a "$tmp_dir/local_share/keyrings/"* "$HOME/.local/share/keyrings/"
            chmod 700 "$HOME/.local/share/keyrings"
            chmod 600 "$HOME/.local/share/keyrings/"* 2>/dev/null || true
            chmod 644 "$HOME/.local/share/keyrings/default" 2>/dev/null || true
            # Перезапуск сервиса связки паролей для немедленного чтения файлов с диска
            killall -q gnome-keyring-daemon 2>/dev/null || true
            eval $(gnome-keyring-daemon --start --components=secrets 2>/dev/null) || true
        fi
    fi

    # Antigravity CLI Auth & State
    if [[ "$selected_items" == "all" || "$selected_items" =~ "antigravity" || "$selected_items" =~ "agy" ]]; then
        if [ -d "$tmp_dir/antigravity-cli" ]; then
            echo " [+] Восстановление Antigravity CLI (OAuth токен и состояние)..."
            mkdir -p "$HOME/.gemini/antigravity-cli"
            for f in jetski_state.pbtxt installation_id settings.json; do
                if [ -f "$tmp_dir/antigravity-cli/$f" ]; then
                    cp -a "$tmp_dir/antigravity-cli/$f" "$HOME/.gemini/antigravity-cli/"
                fi
            done
            if [ -d "$tmp_dir/antigravity-cli/config" ]; then
                mkdir -p "$HOME/.gemini"
                cp -a "$tmp_dir/antigravity-cli/config" "$HOME/.gemini/"
            fi
            if [ -f "$tmp_dir/antigravity-cli/token.json" ] && command -v secret-tool >/dev/null 2>&1; then
                cat "$tmp_dir/antigravity-cli/token.json" | secret-tool store --label="Password for 'antigravity' on 'gemini'" service gemini username antigravity 2>/dev/null || true
                echo "✔ Google OAuth токен для Antigravity CLI успешно зарегистрирован в связке ключей."
            fi
        fi
    fi

    # Opencode Auth
    if [[ "$selected_items" == "all" || "$selected_items" =~ "opencode" || "$selected_items" =~ "opencode_auth" ]]; then
        if [ -f "$tmp_dir/opencode/auth.json" ]; then
            echo " [+] Восстановление авторизации Opencode (Deepseek)..."
            mkdir -p "$HOME/.local/share/opencode"
            cp -a "$tmp_dir/opencode/auth.json" "$HOME/.local/share/opencode/"
            chmod 600 "$HOME/.local/share/opencode/auth.json"
        fi
        if [ -f "$tmp_dir/opencode/auth_export.json" ] && command -v opencode >/dev/null 2>&1; then
            echo " [+] Импорт учетных записей в базу данных Opencode..."
            opencode auth import < "$tmp_dir/opencode/auth_export.json" 2>/dev/null || true
            echo "✔ Учетные записи Opencode успешно импортированы."
        fi
    fi

    # Antigravity IDE
    if [[ "$selected_items" == "all" || "$selected_items" =~ "ide" ]]; then
        if [ -d "$tmp_dir/antigravity-ide" ]; then
            echo " [+] Восстановление Antigravity IDE..."
            mkdir -p "$HOME/.local/share"
            cp -a "$tmp_dir/antigravity-ide" "$HOME/.local/share/"
            mkdir -p "$HOME/.local/bin"
            ln -sf "$HOME/.local/share/antigravity-ide/bin/antigravity-ide" "$HOME/.local/bin/antigravity-ide"
            echo "✔ Antigravity IDE успешно развернута."
        fi
    fi

    # Wi-Fi
    if [[ "$selected_items" == "all" || "$selected_items" =~ "wifi" ]]; then
        if [ -d "$tmp_dir/network/system-connections" ]; then
            echo " [+] Восстановление Wi-Fi профилей..."
            if sudo -n true 2>/dev/null; then
                sudo cp -a "$tmp_dir/network/system-connections/"* /etc/NetworkManager/system-connections/ 2>/dev/null || true
                sudo chown root:root /etc/NetworkManager/system-connections/* 2>/dev/null || true
                sudo chmod 600 /etc/NetworkManager/system-connections/* 2>/dev/null || true
                sudo systemctl reload NetworkManager 2>/dev/null || true
            else
                echo " [!] Для применения Wi-Fi профилей требуются права sudo."
            fi
        fi
    fi

    rm -rf "$tmp_dir"
    echo "✔ Восстановление выбранных секретов завершено."
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    action="${1:-backup}"
    if [ "$action" == "backup" ]; then
        create_secrets_archive "${2:-$HOME/backup/keys.tar.zst}"
    elif [ "$action" == "restore" ]; then
        restore_secrets_archive "${2:-$HOME/backup/keys.tar.zst}" "${3:-all}"
    fi
fi
