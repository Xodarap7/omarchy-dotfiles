#!/usr/bin/env python3
import json
import shutil
import subprocess
from pathlib import Path

def detect_cpu_vendor():
    try:
        with open("/proc/cpuinfo", "r", encoding="utf-8") as f:
            for line in f:
                if line.startswith("vendor_id"):
                    return line.split(":")[1].strip()
    except Exception:
        pass
    return "unknown"

def has_nvidia_gpu():
    try:
        out = subprocess.run(["lspci"], capture_output=True, text=True).stdout
        return "NVIDIA" in out
    except Exception:
        return False

def install_packages(manifest_path: Path, selected_categories: list):
    if not manifest_path.exists():
        print(f"ОШИБКА: Манифест пакетов не найден по адресу: {manifest_path}")
        return

    with open(manifest_path, "r", encoding="utf-8") as f:
        data = json.load(f)

    categories = data.get("categories", [])
    hw_dep = data.get("hardware_dependent", {})
    skip_packages = set(hw_dep.get("skip_on_laptop_defaults", []))
    is_nvidia = has_nvidia_gpu()

    pacman_pkgs = []
    aur_pkgs = []

    for cat in categories:
        if cat["id"] in selected_categories:
            for pkg in cat.get("packages", []):
                if not is_nvidia and pkg in skip_packages:
                    print(f" [!] Пропуск NVIDIA-пакета на данном устройстве: {pkg}")
                    continue
                pacman_pkgs.append(pkg)
            for pkg in cat.get("aur_packages", []):
                aur_pkgs.append(pkg)

    # Добавляем правильный микрокод
    vendor = detect_cpu_vendor()
    ucode_map = hw_dep.get("microcode_rules", {})
    if vendor in ucode_map:
        ucode_pkg = ucode_map[vendor]
        print(f" [+] Обнаружен процессор ({vendor}), добавлен микрокод: {ucode_pkg}")
        pacman_pkgs.append(ucode_pkg)

    # 1. Установка официальных пакетов через pacman
    if pacman_pkgs:
        print(f"\n=== Установка официальных пакетов ({len(pacman_pkgs)} шт.) ===")
        cmd = ["sudo", "pacman", "-S", "--needed", "--noconfirm"] + pacman_pkgs
        print("Команда:", " ".join(cmd))
        subprocess.run(cmd)

    # 2. Установка AUR пакетов через yay или paru
    if aur_pkgs:
        aur_helper = "yay" if shutil.which("yay") else ("paru" if shutil.which("paru") else None)
        if aur_helper:
            print(f"\n=== Установка пакетов AUR через {aur_helper} ({len(aur_pkgs)} шт.) ===")
            cmd = [aur_helper, "-S", "--needed", "--noconfirm"] + aur_pkgs
            print("Команда:", " ".join(cmd))
            subprocess.run(cmd)
        else:
            print("\n[!] Внимание: AUR helper (yay/paru) не найден. Пакеты AUR пропущены:")
            print("    ", ", ".join(aur_pkgs))

if __name__ == "__main__":
    import sys
    manifest = Path(sys.argv[1]) if len(sys.argv) > 1 else Path.home() / ".config/omarchy-sync/manifests/packages.json"
    cats = sys.argv[2].split(",") if len(sys.argv) > 2 else ["dev_tooling", "terminal_cli"]
    install_packages(manifest, cats)
