#!/usr/bin/env bash
set -euo pipefail

create_secrets_archive() {
    local target_archive="${1:-$HOME/secrets-bundle.tar.gz}"
    local tmp_dir
    tmp_dir="$(mktemp -d /tmp/omarchy-secrets-XXXXXX)"

    echo "=== Создание архива секретов: $target_archive ==="
    mkdir -p "$tmp_dir/data"

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
    if [ -f "$HOME/.local/share/opencode/auth.json" ]; then
        echo " [+] Упаковка авторизации Opencode (auth.json)..."
        mkdir -p "$tmp_dir/data/opencode"
        cp -a "$HOME/.local/share/opencode/auth.json" "$tmp_dir/data/opencode/auth.json"
    fi

    # 5. Wi-Fi профили NetworkManager (если есть доступ к sudo)
    if sudo -n true 2>/dev/null; then
        echo " [+] Упаковка Wi-Fi профилей (/etc/NetworkManager/system-connections)..."
        mkdir -p "$tmp_dir/data/network"
        sudo cp -a /etc/NetworkManager/system-connections "$tmp_dir/data/network/" 2>/dev/null || true
        sudo chown -R "$(id -u):$(id -g)" "$tmp_dir/data/network" 2>/dev/null || true
    fi

    tar -czf "$target_archive" -C "$tmp_dir/data" .
    rm -rf "$tmp_dir"
    chmod 600 "$target_archive"
    echo "✔ Архив секретов успешно создан: $target_archive (права 600)"
}

restore_secrets_archive() {
    local source_archive="$1"
    local selected_items="${2:-all}" # "ssh,keyrings,opencode_auth,wifi"

    if [ ! -f "$source_archive" ]; then
        echo "ОШИБКА: Файл архива $source_archive не найден!" >&2
        return 1
    fi

    local tmp_dir
    tmp_dir="$(mktemp -d /tmp/omarchy-restore-secrets-XXXXXX)"
    tar -xzf "$source_archive" -C "$tmp_dir"

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
        fi
    fi

    # Opencode Auth
    if [[ "$selected_items" == "all" || "$selected_items" =~ "opencode_auth" ]]; then
        if [ -f "$tmp_dir/opencode/auth.json" ]; then
            echo " [+] Восстановление авторизации Opencode..."
            mkdir -p "$HOME/.local/share/opencode"
            cp -a "$tmp_dir/opencode/auth.json" "$HOME/.local/share/opencode/"
            chmod 600 "$HOME/.local/share/opencode/auth.json"
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
        create_secrets_archive "${2:-$HOME/secrets-bundle.tar.gz}"
    elif [ "$action" == "restore" ]; then
        restore_secrets_archive "${2:-$HOME/secrets-bundle.tar.gz}" "${3:-all}"
    fi
fi
