#!/usr/bin/env python3
import json
import shutil
import subprocess
from pathlib import Path

HOME = Path.home()

def copy_path(src: Path, dst: Path, ignore_patterns=None):
    if not src.exists():
        return False
    dst.parent.mkdir(parents=True, exist_ok=True)
    if src.is_dir():
        if dst.exists():
            shutil.rmtree(dst)
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

    # 1. Всегда гарантируем наличие ВСЕХ плагинов (включая yar.bar, yar.clock, yar.player и т.д.)
    repo_plugins = repo_dir / "config/omarchy/plugins"
    target_plugins = HOME / ".config/omarchy/plugins"
    if repo_plugins.exists():
        copy_path(repo_plugins, target_plugins, ignore_patterns=["*.bak*"])
        print(" [+] Все плагины бара (включая yar.bar с плавающими блоками и скруглениями) скопированы.")

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

    # Записываем результирующий shell.json
    target_shell_path.parent.mkdir(parents=True, exist_ok=True)
    with open(target_shell_path, "w", encoding="utf-8") as f:
        json.dump(target_shell, f, indent=2, ensure_ascii=False)
    print(" [+] Сформирован shell.json.")

    return True

def restore_hyprland_files(repo_dir: Path, selected_files: list):
    print("=== Восстановление конфигураций Hyprland ===")
    hypr_src = repo_dir / "config/hypr"
    hypr_dst = HOME / ".config/hypr"
    hypr_dst.mkdir(parents=True, exist_ok=True)

    if hypr_src.exists():
        for item in hypr_src.iterdir():
            # monitors.lua не перезаписываем чтобы не ломать дисплей ноутбука
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
        # Применяем тему системным переключателем Omarchy
        print(" [+] Активация темы Cyber Phuket...")
        subprocess.run(["omarchy", "theme", "set", "Cyber Phuket"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

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
        print(" [+] Antigravity: правила, скиллы и звуковые темы восстановлены.")

    if "opencode" in selected_tools or "all" in selected_tools:
        opencode_dst = HOME / ".config/opencode"
        copy_path(repo_dir / "dev/opencode/opencode.json", opencode_dst / "opencode.json")
        copy_path(repo_dir / "dev/opencode/plugins", opencode_dst / "plugins")
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

        # Проверяем наличие Oh My Zsh
        zsh_dir = HOME / ".oh-my-zsh"
        if not zsh_dir.exists():
            print(" [+] Установка Oh My Zsh с GitHub...")
            subprocess.run(["git", "clone", "--depth=1", "https://github.com/ohmyzsh/ohmyzsh.git", str(zsh_dir)])
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
        # Включаем и запускаем фоновые службы виджетов
        subprocess.run(["systemctl", "--user", "enable", "--now", "omarchy-sysinfo.service", "vk-mpris-bridge.service", "ag-unlocker-watchdog.service"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        print(" [+] Пользовательские службы (мониторинг sysinfo, MPRIS bridge) активированы.")

def install_official_apps():
    print("=== Проверка и установка официальных приложений ===")

    # 1. Telegram Desktop
    tg_bin = HOME / ".local/bin/telegram"
    if not tg_bin.exists():
        print(" [+] Скачивание официального Telegram Desktop...")
        cmd = "curl -sSL 'https://telegram.org/dl/desktop/linux' | tar -xJ -C ~/.local/share/ 2>/dev/null && ln -sf ~/.local/share/Telegram/Telegram ~/.local/bin/telegram"
        subprocess.run(cmd, shell=True)
        print("✔ Telegram Desktop установлен.")
    else:
        print("✔ Telegram Desktop уже присутствует.")

    # 2. Antigravity CLI
    if not shutil.which("antigravity") and not (HOME / ".local/bin/antigravity").exists():
        print(" [+] Установка официального Antigravity CLI...")
        subprocess.run("curl -fsSL https://antigravity.google/cli/install.sh | bash", shell=True)
        print("✔ Antigravity CLI установлен.")
    else:
        print("✔ Antigravity CLI уже присутствует.")

    # 3. Antigravity IDE (если архив подготовлен)
    ide_archive = HOME / "antigravity-ide.tar.zst"
    if ide_archive.exists() and not (HOME / ".local/share/antigravity-ide").exists():
        print(" [+] Распаковка Antigravity IDE...")
        subprocess.run(["tar", "-xvf", str(ide_archive), "-C", str(HOME / ".local/share")])
        (HOME / ".local/bin/antigravity-ide").unlink(missing_ok=True)
        (HOME / ".local/bin/antigravity-ide").symlink_to(HOME / ".local/share/antigravity-ide/bin/antigravity-ide")
        print("✔ Antigravity IDE установлена.")

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

def restore_all_autonomous(repo_dir: Path):
    print("🚀 === Автономное полное восстановление системы ===")

    # 1. Hyprland
    restore_hyprland_files(repo_dir, ["all"])

    # 2. Виджеты, плагины и кастомный бар (yar.bar)
    restore_shell_widgets(repo_dir, ["all"])

    # 3. Темы и обои + активация Cyber Phuket
    restore_themes_and_wallpapers(repo_dir, True, True)

    # 4. Среда разработки, Opencode, Git, Shell, Oh My Zsh
    restore_dev_and_ai(repo_dir, ["all"])

    # 5. Пользовательские скрипты и демоны
    restore_user_scripts(repo_dir, ["all"])

    # 6. Официальные приложения (Telegram, Antigravity)
    install_official_apps()

    # 7. Перезапуск интерфейса
    subprocess.run(["hyprctl", "reload"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(["omarchy", "restart", "shell"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    print("✔ Базовая автономная конфигурация полностью применена!")
    return True
