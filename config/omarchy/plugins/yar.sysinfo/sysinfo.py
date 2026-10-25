#!/usr/bin/env python3
import os
import sys
import glob
import json
import time
import subprocess

def collect_all():
    t0 = time.time()

    # 1. Sample CPU initial stat
    f1 = None
    try:
        with open("/proc/stat") as f:
            f1 = [float(x) for x in f.readline().strip().split()[1:8]]
    except Exception:
        pass

    # 2. CPU Model Name
    cpu_model = "CPU"
    try:
        with open("/proc/cpuinfo") as f:
            for line in f:
                if "model name" in line:
                    cpu_model = line.split(":", 1)[1].strip()
                    break
    except Exception:
        pass

    # 3. CPU Temperature
    cpu_temp = 0
    for p in glob.glob("/sys/class/hwmon/hwmon*/name"):
        try:
            with open(p) as f:
                name = f.read().strip()
            if name in ("coretemp", "k10temp", "zenpower"):
                d = os.path.dirname(p)
                temp1 = os.path.join(d, "temp1_input")
                if os.path.exists(temp1):
                    with open(temp1) as tf:
                        cpu_temp = round(int(tf.read().strip()) / 1000.0)
                        break
        except Exception:
            pass
    if cpu_temp == 0:
        for tz in glob.glob("/sys/class/thermal/thermal_zone*/temp"):
            try:
                with open(tz) as tf:
                    t = int(tf.read().strip()) / 1000.0
                    if 20 < t < 115:
                        cpu_temp = round(t)
                        break
            except Exception:
                pass

    # 4. RAM Usage (used/total)
    mem = {}
    try:
        with open("/proc/meminfo") as f:
            for line in f:
                p = line.split(":")
                if p[0] in ("MemTotal", "MemAvailable"):
                    mem[p[0]] = int(p[1].split()[0])
    except Exception:
        pass

    total_kb = mem.get("MemTotal", 1)
    avail_kb = mem.get("MemAvailable", 0)
    used_kb = total_kb - avail_kb
    ram_used_gb = round(used_kb / 1024 / 1024, 1)
    ram_total_gb = round(total_kb / 1024 / 1024, 1)
    ram_percent = round(used_kb / total_kb * 100)

    # 5. RAM Temperature (spd5118 or jc42)
    ram_temps = []
    for p in glob.glob("/sys/class/hwmon/hwmon*/name"):
        try:
            with open(p) as f:
                name = f.read().strip()
            if "spd" in name or "jc42" in name:
                d = os.path.dirname(p)
                for t in glob.glob(os.path.join(d, "temp*_input")):
                    with open(t) as tf:
                        v = int(tf.read().strip()) / 1000.0
                        if 0 < v < 120:
                            ram_temps.append(v)
        except Exception:
            pass
    ram_temp = round(max(ram_temps)) if ram_temps else 0

    # 6. GPU Metrics
    gpu_name = "GPU"
    gpu_util = 0
    gpu_temp = 0
    gpu_mem_used = 0.0
    gpu_mem_total = 0.0
    try:
        res = subprocess.check_output(
            ["nvidia-smi", "--query-gpu=name,utilization.gpu,temperature.gpu,memory.used,memory.total", "--format=csv,noheader,nounits"],
            timeout=1
        ).decode().strip()
        parts = [p.strip() for p in res.split(",")]
        gpu_name = parts[0]
        gpu_util = int(parts[1])
        gpu_temp = int(parts[2])
        gpu_mem_used = round(int(parts[3]) / 1024, 1)
        gpu_mem_total = round(int(parts[4]) / 1024, 1)
    except Exception:
        for p in glob.glob("/sys/class/drm/card*/device/gpu_busy_percent"):
            try:
                with open(p) as f:
                    gpu_util = int(f.read().strip())
                    break
            except Exception:
                pass
        for p in glob.glob("/sys/class/drm/card*/device/hwmon/hwmon*/temp1_input"):
            try:
                with open(p) as f:
                    gpu_temp = round(int(f.read().strip()) / 1000.0)
                    break
            except Exception:
                pass

    # 7. Complete CPU sampling over interval (120ms minimum)
    cpu_util = 0
    elapsed = time.time() - t0
    target_interval = 0.12
    if elapsed < target_interval:
        time.sleep(target_interval - elapsed)

    if f1:
        try:
            with open("/proc/stat") as f:
                f2 = [float(x) for x in f.readline().strip().split()[1:8]]
            d_idle = (f2[3] + f2[4]) - (f1[3] + f1[4])
            d_total = sum(f2) - sum(f1)
            if d_total > 0:
                cpu_util = round(max(0.0, min(100.0, (1.0 - d_idle / d_total) * 100)))
        except Exception:
            pass

    return {
        "cpu": {
            "model": cpu_model,
            "util": cpu_util,
            "temp": cpu_temp
        },
        "ram": {
            "used_gb": ram_used_gb,
            "total_gb": ram_total_gb,
            "percent": ram_percent,
            "temp": ram_temp
        },
        "gpu": {
            "name": gpu_name,
            "util": gpu_util,
            "temp": gpu_temp,
            "mem_used_gb": gpu_mem_used,
            "mem_total_gb": gpu_mem_total
        }
    }

if __name__ == "__main__":
    print(json.dumps(collect_all()))
