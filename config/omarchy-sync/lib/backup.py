#!/usr/bin/env python3
import os
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

def run_backup(repo_dir: Path):
    print(f"=== Резервное копирование конфигураций в: {repo_dir} ===")
    repo_dir.mkdir(parents=True, exist_ok=True)

    # 1. Omarchy UI & Shell
    print(" [+] Экспорт Omarchy UI (shell.json, plugins, themes, backgrounds)...")
    copy_path(HOME / ".config/omarchy/shell.json", repo_dir / "config/omarchy/shell.json")
    copy_path(HOME / ".config/omarchy/plugins", repo_dir / "config/omarchy/plugins", ignore_patterns=["*.bak*"])
    copy_path(HOME / ".config/omarchy/extensions", repo_dir / "config/omarchy/extensions")
    copy_path(HOME / ".config/omarchy/themes", repo_dir / "config/omarchy/themes")
    copy_path(HOME / ".config/omarchy/current", repo_dir / "config/omarchy/current")
    copy_path(HOME / ".config/omarchy/backgrounds", repo_dir / "config/omarchy/backgrounds")
    copy_path(HOME / ".config/omarchy/branding", repo_dir / "config/omarchy/branding")

    # 2. Hyprland (исключаем monitors.lua для безопасности)
    print(" [+] Экспорт конфигураций Hyprland...")
    hypr_files = ["bindings.lua", "looknfeel.lua", "hyprland.lua", "workspaces.lua", "autostart.lua", "input.lua"]
    for f in hypr_files:
        src = HOME / ".config/hypr" / f
        if src.exists():
            copy_path(src, repo_dir / "config/hypr" / f)

    # 3. Терминал и Шелл
    print(" [+] Экспорт Ghostty, Starship, Zsh...")
    copy_path(HOME / ".config/ghostty", repo_dir / "config/ghostty")
    copy_path(HOME / ".config/starship.toml", repo_dir / "config/starship.toml")
    copy_path(HOME / ".zshrc", repo_dir / "shell/zshrc")
    copy_path(HOME / ".bashrc", repo_dir / "shell/bashrc")
    copy_path(HOME / ".config/environment.d", repo_dir / "config/environment.d")

    # 4. Dev & AI Tools
    print(" [+] Экспорт Antigravity (rules, skills, sounds), Opencode, Git...")
    copy_path(HOME / ".gemini/antigravity-cli/rules", repo_dir / "dev/gemini/rules")
    copy_path(HOME / ".gemini/antigravity-cli/skills", repo_dir / "dev/gemini/skills")
    copy_path(HOME / ".gemini/antigravity-cli/sounds", repo_dir / "dev/gemini/sounds")
    copy_path(HOME / ".config/opencode/opencode.json", repo_dir / "dev/opencode/opencode.json")
    copy_path(HOME / ".config/opencode/plugins", repo_dir / "dev/opencode/plugins")
    copy_path(HOME / ".config/git/config", repo_dir / "dev/git/config")
    copy_path(HOME / ".gitconfig", repo_dir / "dev/git/gitconfig")
    copy_path(HOME / ".config/lazygit", repo_dir / "dev/lazygit")
    copy_path(HOME / ".config/lazydocker", repo_dir / "dev/lazydocker")
    copy_path(HOME / ".config/mise", repo_dir / "dev/mise")

    # 5. Пользовательские скрипты (~/.local/bin)
    print(" [+] Экспорт пользовательских скриптов (~/.local/bin)...")
    local_bin = HOME / ".local/bin"
    target_bin = repo_dir / "bin"
    target_bin.mkdir(parents=True, exist_ok=True)
    if local_bin.exists():
        for item in local_bin.iterdir():
            # Пропускаем огромные бинарники вроде bazel и временные ссылки
            if item.name in ["bazel", "telegram"]:
                continue
            if item.is_file() and not item.is_symlink():
                copy_path(item, target_bin / item.name)

    # 6. Пользовательские systemd службы
    print(" [+] Экспорт пользовательских служб systemd...")
    copy_path(HOME / ".config/systemd/user", repo_dir / "systemd/user", ignore_patterns=["*.wants*"])

    # 7. Копируем манифесты
    manifests_src = HOME / ".config/omarchy-sync/manifests"
    if manifests_src.exists():
        copy_path(manifests_src, repo_dir / "manifests")

    # 8. Инициализация/обновление Git
    print(" [+] Проверка Git-репозитория...")
    subprocess.run(["git", "init"], cwd=repo_dir, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    
    # Добавляем .gitignore
    gitignore = repo_dir / ".gitignore"
    with open(gitignore, "w", encoding="utf-8") as f:
        f.write("*.bak*\n*.log\n*.tar.gz\nsecrets*\n.DS_Store\n")

    subprocess.run(["git", "add", "."], cwd=repo_dir, stdout=subprocess.DEVNULL)
    status = subprocess.run(["git", "status", "--porcelain"], cwd=repo_dir, capture_output=True, text=True)
    if status.stdout.strip():
        subprocess.run(["git", "commit", "-m", "chore: sync omarchy configurations"], cwd=repo_dir, stdout=subprocess.DEVNULL)
        print("✔ Изменения успешно закоммичены в локальный Git-репозиторий.")
    else:
        print("✔ Конфигурации актуальны, изменений нет.")

    print(f"\nГотово! Репозиторий дотфайлов находится в: {repo_dir}")
    print("Чтобы отправить его на GitHub/GitLab:")
    print(f"  cd {repo_dir}")
    print("  git remote add origin git@github.com:<username>/<repo>.git")
    print("  git push -u origin master")

if __name__ == "__main__":
    import sys
    target = Path(sys.argv[1]) if len(sys.argv) > 1 else (HOME / "omarchy-dotfiles")
    run_backup(target)
