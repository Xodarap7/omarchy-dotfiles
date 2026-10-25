#!/usr/bin/env python3
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

HOME = Path.home()

def copy_path(src: Path, dst: Path, ignore_patterns=None):
    if not src.exists():
        return False
    dst.parent.mkdir(parents=True, exist_ok=True)
    if dst.exists():
        if dst.is_dir():
            shutil.rmtree(dst)
        else:
            try:
                dst.unlink()
            except Exception:
                pass
    if src.is_dir():
        shutil.copytree(src, dst, ignore=shutil.ignore_patterns(*(ignore_patterns or [])))
    else:
        shutil.copy2(src, dst)
    return True

def restore_shell_widgets(repo_dir: Path, selected_widget_ids: list):
    master_shell_path = repo_dir / "config/omarchy/shell.json"
    if not master_shell_path.exists():
        print("ОШИБКА: Мастер-конфиг shell.json не найден в репозитории!")
        return False

    with open(master_shell_path, "r", encoding="utf-8") as f:
        master_shell = json.load(f)

    # 1. Копируем все плагины бара
    repo_plugins = repo_dir / "config/omarchy/plugins"
    target_plugins = HOME / ".config/omarchy/plugins"
    if repo_plugins.exists():
        copy_path(repo_plugins, target_plugins, ignore_patterns=["*.bak*"])
        print(" [+] Базовые плагины бара скопированы.")

    # Копируем расширения
    repo_ext = repo_dir / "config/omarchy/extensions"
    if repo_ext.exists():
        copy_path(repo_ext, HOME / ".config/omarchy/extensions")

    # 2. Фильтруем секции бара если передан список
    target_shell_path = HOME / ".config/omarchy/shell.json"
    target_shell = json.loads(json.dumps(master_shell))

    if selected_widget_ids and "all" not in selected_widget_ids:
        bar_layout = master_shell.get("bar", {}).get("layout", {})
        new_layout = {"left": [], "center": [], "right": []}
        for section in ["left", "center", "right"]:
            for item in bar_layout.get(section, []):
                item_id = item.get("id")
                if item_id in selected_widget_ids:
                    new_layout[section].append(item)
        target_shell["bar"]["layout"] = new_layout

    target_shell_path.parent.mkdir(parents=True, exist_ok=True)
    with open(target_shell_path, "w", encoding="utf-8") as f:
        json.dump(target_shell, f, indent=2, ensure_ascii=False)
    print(" [+] Сформирован shell.json.")

    return True

def restore_profile(repo_dir: Path, profile_name: str = "laptop"):
    print(f"=== Применение профиля системы: {profile_name.upper()} ===")
    profile_file = HOME / ".config/omarchy/profile"
    profile_file.parent.mkdir(parents=True, exist_ok=True)
    profile_file.write_text(profile_name, encoding="utf-8")
    profile_dir = repo_dir / "profiles" / profile_name
    if not profile_dir.exists():
        print(f" [!] Каталог профиля {profile_dir} не найден, пропускаем оверлей.")
        return False

    plugins_overlay = profile_dir / "plugins"
    target_plugins = HOME / ".config/omarchy/plugins"
    if plugins_overlay.exists():
        for plugin in plugins_overlay.iterdir():
            if plugin.is_dir():
                target_dest = target_plugins / plugin.name
                target_dest.mkdir(parents=True, exist_ok=True)
                for item in plugin.rglob("*"):
                    if item.is_file():
                        rel = item.relative_to(plugin)
                        dest_file = target_dest / rel
                        dest_file.parent.mkdir(parents=True, exist_ok=True)
                        shutil.copy2(item, dest_file)
                print(f" [+] Профиль '{profile_name}': применен оверлей для {plugin.name}")

    if profile_name == "laptop":
        laptop_bg = HOME / ".config/omarchy/themes/cyber-phuket/backgrounds/phuket-cyberpunk-laptop-right.jpg"
        if laptop_bg.exists():
            current_bg = HOME / ".local/state/omarchy/current/background"
            current_bg.parent.mkdir(parents=True, exist_ok=True)
            try:
                current_bg.unlink(missing_ok=True)
                current_bg.symlink_to(laptop_bg)
                subprocess.run(["omarchy", "restart", "background"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                print(" [+] Профиль 'laptop': установлены обои правой части (phuket-cyberpunk-laptop-right.jpg)")
            except Exception as e:
                print(f" [!] Ошибка установки обоев ноутбука: {e}")

    return True

def restore_hyprland_files(repo_dir: Path, selected_files: list):
    print("=== Восстановление конфигураций Hyprland ===")
    hypr_src = repo_dir / "config/hypr"
    hypr_dst = HOME / ".config/hypr"
    hypr_dst.mkdir(parents=True, exist_ok=True)

    if hypr_src.exists():
        for item in hypr_src.iterdir():
            if item.name.startswith("monitors.lua") or ".bak" in item.name or item.name.startswith("."):
                continue
            if item.is_file():
                copy_path(item, hypr_dst / item.name)
                print(f" [+] Скопирован {item.name}")

    subprocess.run(["hyprctl", "reload"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return True

def restore_themes_and_wallpapers(repo_dir: Path, restore_themes: bool, restore_backgrounds: bool):
    print("=== Восстановление тем оформления и фонов ===")
    if restore_themes:
        copy_path(repo_dir / "config/omarchy/themes", HOME / ".config/omarchy/themes")
        copy_path(repo_dir / "config/omarchy/current", HOME / ".config/omarchy/current")
        print(" [+] Темы оформления скопированы.")
        print(" [+] Активация темы Cyber Phuket...")
        subprocess.run(["omarchy", "theme", "set", "cyber-phuket"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    if restore_backgrounds:
        copy_path(repo_dir / "config/omarchy/backgrounds", HOME / ".config/omarchy/backgrounds")
        print(" [+] Коллекция обоев перенесена.")

def restore_dev_and_ai(repo_dir: Path, selected_tools: list):
    print("=== Восстановление среды разработки и AI-инструментов ===")
    if "antigravity" in selected_tools or "all" in selected_tools:
        gemini_target = HOME / ".gemini/antigravity-cli"
        copy_path(repo_dir / "dev/gemini/rules", gemini_target / "rules")
        copy_path(repo_dir / "dev/gemini/skills", gemini_target / "skills")
        copy_path(repo_dir / "dev/gemini/sounds", gemini_target / "sounds")
        if (repo_dir / "dev/gemini/settings.json").exists():
            copy_path(repo_dir / "dev/gemini/settings.json", gemini_target / "settings.json")
        usage_src = repo_dir / "dev/agents/usage"
        usage_dst = HOME / ".local/state/omarchy/agents/usage"
        if usage_src.exists():
            copy_path(usage_src, usage_dst)
        print(" [+] Antigravity: правила, скиллы, звуки и кэш лимитов восстановлены.")

    if "opencode" in selected_tools or "all" in selected_tools:
        opencode_dst = HOME / ".config/opencode"
        copy_path(repo_dir / "dev/opencode/opencode.json", opencode_dst / "opencode.json")
        copy_path(repo_dir / "dev/opencode/plugins", opencode_dst / "plugins")
        if (repo_dir / "config/mise/config.toml").exists():
            copy_path(repo_dir / "config/mise/config.toml", HOME / ".config/mise/config.toml")
        if shutil.which("mise"):
            print(" [+] Установка инструментов mise (opencode, python, node)...")
            subprocess.run(["mise", "install", "-y"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        print(" [+] Opencode: модель deepseek-flash и плагины настроены.")

    if "git" in selected_tools or "all" in selected_tools:
        copy_path(repo_dir / "dev/git/config", HOME / ".config/git/config")
        copy_path(repo_dir / "dev/git/gitconfig", HOME / ".gitconfig")
        copy_path(repo_dir / "dev/lazygit", HOME / ".config/lazygit")
        print(" [+] Git и Lazygit: глобальные настройки восстановлены.")

    if "shell" in selected_tools or "all" in selected_tools:
        copy_path(repo_dir / "config/ghostty", HOME / ".config/ghostty")
        copy_path(repo_dir / "config/starship.toml", HOME / ".config/starship.toml")
        copy_path(repo_dir / "shell/zshrc", HOME / ".zshrc")
        copy_path(repo_dir / "shell/bashrc", HOME / ".bashrc")
        copy_path(repo_dir / "config/environment.d", HOME / ".config/environment.d")

        # Oh My Zsh + zsh-autosuggestions
        zsh_dir = HOME / ".oh-my-zsh"
        if not zsh_dir.exists():
            print(" [+] Установка Oh My Zsh с GitHub...")
            subprocess.run(["git", "clone", "--depth=1", "https://github.com/ohmyzsh/ohmyzsh.git", str(zsh_dir)])
        zsh_auto = zsh_dir / "custom/plugins/zsh-autosuggestions"
        if not zsh_auto.exists():
            print(" [+] Установка плагина zsh-autosuggestions...")
            subprocess.run(["git", "clone", "--depth=1", "https://github.com/zsh-users/zsh-autosuggestions.git", str(zsh_auto)])
        print(" [+] Терминал Ghostty, Starship, Zsh и Oh My Zsh настроены.")

def restore_user_scripts(repo_dir: Path, selected_scripts: list):
    print("=== Восстановление пользовательских скриптов (~/.local/bin) ===")
    bin_src = repo_dir / "bin"
    bin_dst = HOME / ".local/bin"
    bin_dst.mkdir(parents=True, exist_ok=True)

    if bin_src.exists():
        for item in bin_src.iterdir():
            if item.is_file() and (item.name in selected_scripts or "all" in selected_scripts):
                copy_path(item, bin_dst / item.name)
                (bin_dst / item.name).chmod(0o755)
        print(" [+] Пользовательские скрипты скопированы в ~/.local/bin/.")

    # Восстановление пользовательских служб systemd
    sysd_src = repo_dir / "systemd/user"
    if sysd_src.exists():
        copy_path(sysd_src, HOME / ".config/systemd/user")
        subprocess.run(["systemctl", "--user", "daemon-reload"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        subprocess.run(["systemctl", "--user", "enable", "--now", "omarchy-sysinfo.service", "vk-mpris-bridge.service", "ag-unlocker-watchdog.service"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        print(" [+] Пользовательские службы (мониторинг sysinfo, MPRIS bridge) активированы.")

def restore_desktop_apps_and_icons(repo_dir: Path):
    print("=== Восстановление ярлыков и иконок приложений ===")
    apps_src = repo_dir / "desktop/applications"
    icons_src = repo_dir / "desktop/icons"
    apps_dst = HOME / ".local/share/applications"
    icons_dst = HOME / ".local/share/icons/hicolor/256x256/apps"

    apps_dst.mkdir(parents=True, exist_ok=True)
    icons_dst.mkdir(parents=True, exist_ok=True)

    if apps_src.exists():
        for item in apps_src.iterdir():
            if item.is_file():
                copy_path(item, apps_dst / item.name)
        print(" [+] Ярлыки .desktop скопированы в ~/.local/share/applications.")

    if icons_src.exists():
        for item in icons_src.iterdir():
            if item.is_file():
                copy_path(item, icons_dst / item.name)
        print(" [+] Иконки скопированы в ~/.local/share/icons.")

    subprocess.run(["update-desktop-database", str(apps_dst)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

def install_official_apps(repo_dir: Path):
    print("=== Проверка и установка официальных приложений ===")

    # 1. Telegram Desktop
    tg_bin = HOME / ".local/bin/telegram"
    if not tg_bin.exists():
        print(" [+] Установка официального Telegram Desktop...")
        # Сначала пробуем через официальный репозиторий pacman
        res = subprocess.run(["sudo", "pacman", "-S", "--needed", "--noconfirm", "telegram-desktop"])
        if res.returncode == 0 and Path("/usr/bin/telegram-desktop").exists():
            tg_bin.symlink_to("/usr/bin/telegram-desktop")
            print("✔ Telegram Desktop успешно установлен через официальный pacman.")
        else:
            print(" [+] Скачивание официального бинарника Telegram с официального сайта...")
            cmd = "curl -sSL 'https://telegram.org/dl/desktop/linux' | tar -xJ -C ~/.local/share/ 2>/dev/null && ln -sf ~/.local/share/Telegram/Telegram ~/.local/bin/telegram"
            subprocess.run(cmd, shell=True)
            print("✔ Telegram Desktop установлен.")
    else:
        print("✔ Telegram Desktop уже присутствует.")

    # 2. Antigravity CLI
    agy_bin_path = HOME / ".local/bin/agy.bin"
    has_agy = (shutil.which("agy") and not (HOME / ".local/bin/agy").exists()) or agy_bin_path.exists() or Path("/usr/bin/agy").exists() or Path("/usr/local/bin/agy").exists()
    if not has_agy:
        print(" [+] Установка официального Antigravity CLI с Google...")
        subprocess.run("curl -fsSL https://antigravity.google/cli/install.sh | bash", shell=True)
        # Если скачанный бинарник лежит в ~/.local/bin/agy, перемещаем его в agy.bin
        downloaded = HOME / ".local/bin/agy"
        if downloaded.exists() and not downloaded.is_symlink() and downloaded.stat().st_size > 1000000:
            downloaded.rename(agy_bin_path)
            print(" [+] Бинарник Antigravity сохранен как ~/.local/bin/agy.bin")

    # Гарантируем наличие универсального wrapper'а и symlink antigravity
    if (repo_dir / "bin/agy").exists():
        copy_path(repo_dir / "bin/agy", HOME / ".local/bin/agy")
        (HOME / ".local/bin/agy").chmod(0o755)
    (HOME / ".local/bin/antigravity").unlink(missing_ok=True)
    (HOME / ".local/bin/antigravity").symlink_to(HOME / ".local/bin/agy")
    print("✔ Antigravity CLI настроен.")

    # Фоновое обновление кэша лимитов
    subprocess.run(["omarchy-agent-usage-update"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    # 3. Antigravity IDE
    ide_target = HOME / ".local/share/antigravity-ide"
    if not ide_target.exists():
        # Поиск архива IDE в домашней папке, на флешках или на ПК
        candidates = [
            HOME / "antigravity-ide.tar.zst",
            HOME / "Downloads/Antigravity IDE.tar.gz"
        ]
        for u in Path("/run/media").glob("*/*"):
            candidates.append(u / "antigravity-ide.tar.zst")

        found_archive = None
        for c in candidates:
            if c.exists():
                found_archive = c
                break

        if not found_archive:
            # Пробуем rsync с основного ПК по локальной сети
            print(" [+] Проверка наличия архива Antigravity IDE на основном ПК (192.168.1.170)...")
            r = subprocess.run(["rsync", "-e", "ssh -o ConnectTimeout=2 -o StrictHostKeyChecking=no", "-P", "yar@192.168.1.170:~/antigravity-ide.tar.zst", str(HOME / "antigravity-ide.tar.zst")], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            if r.returncode == 0 and (HOME / "antigravity-ide.tar.zst").exists():
                found_archive = HOME / "antigravity-ide.tar.zst"

        if found_archive:
            print(f" [+] Распаковка Antigravity IDE из {found_archive}...")
            ide_target.parent.mkdir(parents=True, exist_ok=True)
            if str(found_archive).endswith(".zst"):
                subprocess.run(["tar", "--zstd", "-xvf", str(found_archive), "-C", str(ide_target.parent)])
            else:
                subprocess.run(["tar", "-xvf", str(found_archive), "-C", str(ide_target.parent)])
            (HOME / ".local/bin/antigravity-ide").unlink(missing_ok=True)
            (HOME / ".local/bin/antigravity-ide").symlink_to(ide_target / "bin/antigravity-ide")
            print("✔ Antigravity IDE распакована и привязана.")
        else:
            print(" [!] Внимание: архив antigravity-ide.tar.zst не найден. Скопируйте его с ПК для работы IDE.")

    # Настройки Antigravity IDE
    if (repo_dir / "dev/antigravity-ide/settings.json").exists():
        ide_cfg = HOME / ".config/Antigravity IDE/User"
        ide_cfg.mkdir(parents=True, exist_ok=True)
        copy_path(repo_dir / "dev/antigravity-ide/settings.json", ide_cfg / "settings.json")

def restore_work_projects(archive_path: Path):
    print(f"=== Восстановление рабочих проектов из {archive_path} ===")
    if not archive_path.exists():
        print(f"ОШИБКА: Архив проектов {archive_path} не найден!")
        return False

    cmd = ["sudo", "tar", "--zstd", "-xvf", str(archive_path), "-C", str(HOME)] if str(archive_path).endswith(".zst") else ["sudo", "tar", "-xvf", str(archive_path), "-C", str(HOME)]
    subprocess.run(cmd)
    subprocess.run(["sudo", "chown", "-R", f"{HOME.name}:{HOME.name}", str(HOME / "interprocom")])
    if (HOME / "odoo_projects").exists():
        subprocess.run(["sudo", "chown", "-R", f"{HOME.name}:{HOME.name}", str(HOME / "odoo_projects")])
    print("✔ Рабочие проекты interprocom и odoo_projects успешно восстановлены.")
    return True

def restore_all_autonomous(repo_dir: Path, profile: str = "laptop"):
    print(f"🚀 === Автономное полное восстановление системы [ПРОФИЛЬ: {profile.upper()}] ===")

    # 1. Hyprland
    restore_hyprland_files(repo_dir, ["all"])

    # 2. Виджеты, плагины и кастомный бар (yar.bar)
    restore_shell_widgets(repo_dir, ["all"])

    # 3. Применение профиля (ноутбучный или десктопный оверлей)
    restore_profile(repo_dir, profile)

    # 4. Темы и обои + активация Cyber Phuket
    restore_themes_and_wallpapers(repo_dir, True, True)

    # 5. Среда разработки, Opencode, Git, Shell, Oh My Zsh
    restore_dev_and_ai(repo_dir, ["all"])

    # 6. Пользовательские скрипты и демоны
    restore_user_scripts(repo_dir, ["all"])

    # 7. Ярлыки приложений и иконки
    restore_desktop_apps_and_icons(repo_dir)

    # 8. Официальные приложения (Telegram, Antigravity)
    install_official_apps(repo_dir)

    # 9. Перезапуск интерфейса
    subprocess.run(["hyprctl", "reload"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(["omarchy", "restart", "shell"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    print("✔ Базовая автономная конфигурация полностью применена!")
    return True
