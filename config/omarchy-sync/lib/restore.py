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

    # Читаем целевой shell.json или используем мастер как основу
    target_shell_path = HOME / ".config/omarchy/shell.json"
    if target_shell_path.exists():
        # Резервная копия на целевой машине
        shutil.copy2(target_shell_path, target_shell_path.with_suffix(".json.bak"))
        with open(target_shell_path, "r", encoding="utf-8") as f:
            target_shell = json.load(f)
    else:
        target_shell = json.loads(json.dumps(master_shell))

    # Фильтруем секции бара
    bar_layout = master_shell.get("bar", {}).get("layout", {})
    new_layout = {"left": [], "center": [], "right": []}

    plugins_to_copy = set()

    for section in ["left", "center", "right"]:
        for item in bar_layout.get(section, []):
            item_id = item.get("id")
            if item_id in selected_widget_ids:
                new_layout[section].append(item)
                if item_id.startswith("yar."):
                    plugins_to_copy.add(item_id)

    # Фильтруем фоновые системные плагины (idle, lock, background, notifications)
    active_plugins = []
    for plugin in master_shell.get("plugins", []):
        p_id = plugin.get("id")
        if p_id in selected_widget_ids or p_id.startswith("yar."):
            active_plugins.append(plugin)
            if p_id.startswith("yar."):
                plugins_to_copy.add(p_id)

    # Обновляем целевой shell
    if "bar" not in target_shell:
        target_shell["bar"] = master_shell["bar"]
    target_shell["bar"]["layout"] = new_layout
    target_shell["bar"]["position"] = master_shell.get("bar", {}).get("position", "bottom")
    target_shell["bar"]["transparent"] = master_shell.get("bar", {}).get("transparent", false if "false" in str(master_shell) else False)
    target_shell["plugins"] = active_plugins

    # Записываем обновленный shell.json
    target_shell_path.parent.mkdir(parents=True, exist_ok=True)
    with open(target_shell_path, "w", encoding="utf-8") as f:
        json.dump(target_shell, f, indent=2, ensure_ascii=False)
    print(" [+] Сформирован персональный shell.json с выбранными виджетами.")

    # Копируем только те плагины, которые требуются для выбранных виджетов
    repo_plugins = repo_dir / "config/omarchy/plugins"
    target_plugins = HOME / ".config/omarchy/plugins"
    target_plugins.mkdir(parents=True, exist_ok=True)

    for p_id in plugins_to_copy:
        src_p = repo_plugins / p_id
        if src_p.exists():
            copy_path(src_p, target_plugins / p_id)
            print(f" [+] Скопирован исходный код плагина: {p_id}")

    # Копируем расширения
    repo_ext = repo_dir / "config/omarchy/extensions"
    if repo_ext.exists():
        copy_path(repo_ext, HOME / ".config/omarchy/extensions")

    # Перезапускаем шелл, если графическая сессия активна
    subprocess.run(["omarchy", "restart", "shell"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
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

def restore_all_autonomous(repo_dir: Path):
    print("🚀 === Автономное полное восстановление системы ===")
    
    # 1. Hyprland (все файлы кроме monitors.lua)
    restore_hyprland_files(repo_dir, ["all"])

    # 2. Виджеты и плагины бара
    master_shell_path = repo_dir / "config/omarchy/shell.json"
    if master_shell_path.exists():
        with open(master_shell_path, "r", encoding="utf-8") as f:
            mshell = json.load(f)
        all_w = []
        for sec in ["left", "center", "right"]:
            for item in mshell.get("bar", {}).get("layout", {}).get(sec, []):
                all_w.append(item.get("id"))
        restore_shell_widgets(repo_dir, all_w)

    # 3. Темы и обои
    restore_themes_and_wallpapers(repo_dir, True, True)

    # 4. Среда разработки и AI
    restore_dev_and_ai(repo_dir, ["antigravity", "opencode", "git", "shell"])

    # 5. Пользовательские скрипты и службы
    restore_user_scripts(repo_dir, ["all"])

    print("✔ Базовая автономная конфигурация полностью применена!")
    return True

def restore_themes_and_wallpapers(repo_dir: Path, restore_themes: bool, restore_backgrounds: bool):
    print("=== Восстановление тем оформления и фонов ===")
    if restore_themes:
        copy_path(repo_dir / "config/omarchy/themes", HOME / ".config/omarchy/themes")
        copy_path(repo_dir / "config/omarchy/current", HOME / ".config/omarchy/current")
        print(" [+] Темы оформления и текущая цветовая схема перенесены.")
    if restore_backgrounds:
        copy_path(repo_dir / "config/omarchy/backgrounds", HOME / ".config/omarchy/backgrounds")
        print(" [+] Коллекция обоев перенесена.")

def restore_dev_and_ai(repo_dir: Path, selected_tools: list):
    print("=== Восстановление среды разработки и AI-инструментов ===")
    if "antigravity" in selected_tools:
        gemini_target = HOME / ".gemini/antigravity-cli"
        copy_path(repo_dir / "dev/gemini/rules", gemini_target / "rules")
        copy_path(repo_dir / "dev/gemini/skills", gemini_target / "skills")
        copy_path(repo_dir / "dev/gemini/sounds", gemini_target / "sounds")
        print(" [+] Antigravity: правила, скиллы и звуковые темы восстановлены.")

    if "opencode" in selected_tools:
        opencode_dst = HOME / ".config/opencode"
        copy_path(repo_dir / "dev/opencode/opencode.json", opencode_dst / "opencode.json")
        copy_path(repo_dir / "dev/opencode/plugins", opencode_dst / "plugins")
        print(" [+] Opencode: настройки и плагины восстановлены.")

    if "git" in selected_tools:
        copy_path(repo_dir / "dev/git/config", HOME / ".config/git/config")
        copy_path(repo_dir / "dev/git/gitconfig", HOME / ".gitconfig")
        copy_path(repo_dir / "dev/lazygit", HOME / ".config/lazygit")
        print(" [+] Git и Lazygit: глобальные настройки восстановлены.")

    if "shell" in selected_tools:
        copy_path(repo_dir / "config/ghostty", HOME / ".config/ghostty")
        copy_path(repo_dir / "config/starship.toml", HOME / ".config/starship.toml")
        copy_path(repo_dir / "shell/zshrc", HOME / ".zshrc")
        print(" [+] Терминал Ghostty, Starship и .zshrc восстановлены.")

def restore_user_scripts(repo_dir: Path, selected_scripts: list):
    print("=== Восстановление пользовательских скриптов (~/.local/bin) ===")
    bin_src = repo_dir / "bin"
    bin_dst = HOME / ".local/bin"
    bin_dst.mkdir(parents=True, exist_ok=True)

    for item in bin_src.iterdir():
        if item.is_file() and (item.name in selected_scripts or "all" in selected_scripts):
            copy_path(item, bin_dst / item.name)
            (bin_dst / item.name).chmod(0o755)
            print(f" [+] Скрипт {item.name} скопирован и сделан исполняемым.")

    # Восстановление пользовательских служб systemd
    sysd_src = repo_dir / "systemd/user"
    if sysd_src.exists():
        copy_path(sysd_src, HOME / ".config/systemd/user")
        subprocess.run(["systemctl", "--user", "daemon-reload"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        print(" [+] Пользовательские юниты systemd обновлены.")

def restore_work_projects(archive_path: Path):
    print(f"=== Восстановление рабочих проектов из {archive_path} ===")
    if not archive_path.exists():
        print(f"ОШИБКА: Архив проектов {archive_path} не найден!")
        return False

    cmd = ["sudo", "tar", "--zstd", "-xvf", str(archive_path), "-C", str(HOME)] if str(archive_path).endswith(".zst") else ["sudo", "tar", "-xvf", str(archive_path), "-C", str(HOME)]
    subprocess.run(cmd)
    # Корректируем права владения на пользователя
    subprocess.run(["sudo", "chown", "-R", f"{HOME.name}:{HOME.name}", str(HOME / "interprocom")])
    if (HOME / "odoo_projects").exists():
        subprocess.run(["sudo", "chown", "-R", f"{HOME.name}:{HOME.name}", str(HOME / "odoo_projects")])
    print("✔ Рабочие проекты interprocom и odoo_projects успешно восстановлены.")
    return True
