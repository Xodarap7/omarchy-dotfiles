#!/usr/bin/env python3
"""
Lightweight background hardware metrics daemon for Omarchy sysinfo widget.
Polls hardware metrics every 2 seconds and writes JSON to /dev/shm/sysinfo.json.
Uses NVML via ctypes for direct C-level GPU access with zero subprocess forks.
"""
import os
import sys
import glob
import json
import time
import signal
import ctypes

RUNNING = True

def handle_signal(sig, frame):
    global RUNNING
    RUNNING = False

signal.signal(signal.SIGTERM, handle_signal)
signal.signal(signal.SIGINT, handle_signal)

# ----------------- GPU NVML CTYPES -----------------
class Utilization(ctypes.Structure):
    _fields_ = [('gpu', ctypes.c_uint), ('memory', ctypes.c_uint)]

class Memory(ctypes.Structure):
    _fields_ = [('total', ctypes.c_ulonglong), ('free', ctypes.c_ulonglong), ('used', ctypes.c_ulonglong)]

class NvmlCollector:
    def __init__(self):
        self.handle = None
        self.gpu_name = "GPU"
        self.nvml = None
        self._init_nvml()

    def _init_nvml(self):
        try:
            self.nvml = ctypes.CDLL("libnvidia-ml.so.1")
            if self.nvml.nvmlInit_v2() == 0:
                dev = ctypes.c_void_p()
                if self.nvml.nvmlDeviceGetHandleByIndex_v2(0, ctypes.byref(dev)) == 0:
                    self.handle = dev
                    name_buf = ctypes.create_string_buffer(64)
                    if self.nvml.nvmlDeviceGetName(dev, name_buf, 64) == 0:
                        self.gpu_name = name_buf.value.decode(errors="ignore")
        except Exception:
            self.handle = None

    def query(self):
        if not self.handle:
            self._init_nvml()
            if not self.handle:
                return self._fallback_drm()

        try:
            util = Utilization()
            temp = ctypes.c_uint()
            mem = Memory()
            if self.nvml.nvmlDeviceGetUtilizationRates(self.handle, ctypes.byref(util)) != 0:
                return self._fallback_drm()
            self.nvml.nvmlDeviceGetTemperature(self.handle, 0, ctypes.byref(temp))
            self.nvml.nvmlDeviceGetMemoryInfo(self.handle, ctypes.byref(mem))

            return {
                "name": self.gpu_name,
                "util": int(util.gpu),
                "temp": int(temp.value),
                "mem_used_gb": round(mem.used / (1024**3), 1),
                "mem_total_gb": round(mem.total / (1024**3), 1)
            }
        except Exception:
            self.handle = None
            return self._fallback_drm()

    def _fallback_drm(self):
        util = 0
        temp = 0
        for p in glob.glob("/sys/class/drm/card*/device/gpu_busy_percent"):
            try:
                with open(p) as f:
                    util = int(f.read().strip())
                    break
            except Exception:
                pass
        for p in glob.glob("/sys/class/drm/card*/device/hwmon/hwmon*/temp1_input"):
            try:
                with open(p) as f:
                    temp = round(int(f.read().strip()) / 1000.0)
                    break
            except Exception:
                pass
        return {
            "name": self.gpu_name,
            "util": util,
            "temp": temp,
            "mem_used_gb": 0.0,
            "mem_total_gb": 0.0
        }

# ----------------- SENSOR PATH DISCOVERY -----------------
def discover_hwmon():
    cpu_path = None
    for p in glob.glob("/sys/class/hwmon/hwmon*/name"):
        try:
            with open(p) as f:
                name = f.read().strip()
            if name in ("coretemp", "k10temp", "zenpower"):
                d = os.path.dirname(p)
                t1 = os.path.join(d, "temp1_input")
                if os.path.exists(t1):
                    cpu_path = t1
                    break
        except Exception:
            pass

    if not cpu_path:
        for tz in glob.glob("/sys/class/thermal/thermal_zone*/temp"):
            try:
                with open(tz) as tf:
                    t = int(tf.read().strip()) / 1000.0
                    if 15 <= t <= 110:
                        cpu_path = tz
                        break
            except Exception:
                pass

    if not cpu_path:
        for t in glob.glob("/sys/class/hwmon/hwmon*/temp*_input"):
            try:
                with open(t) as tf:
                    val = int(tf.read().strip()) / 1000.0
                    if 15 <= val <= 110:
                        cpu_path = t
                        break
            except Exception:
                pass

    ram_paths = []
    for p in glob.glob("/sys/class/hwmon/hwmon*/name"):
        try:
            with open(p) as f:
                name = f.read().strip()
            if "spd" in name or "jc42" in name:
                d = os.path.dirname(p)
                for t in glob.glob(os.path.join(d, "temp*_input")):
                    ram_paths.append(t)
        except Exception:
            pass

    return cpu_path, ram_paths

# ----------------- MAIN LOOP -----------------
def main():
    gpu_collector = NvmlCollector()
    cpu_temp_path, ram_temp_paths = discover_hwmon()

    # CPU model
    cpu_model = "CPU"
    try:
        with open("/proc/cpuinfo") as f:
            for line in f:
                if "model name" in line:
                    cpu_model = line.split(":", 1)[1].strip()
                    break
    except Exception:
        pass

    # Initial CPU stat
    prev_stat = None
    try:
        with open("/proc/stat") as f:
            prev_stat = [float(x) for x in f.readline().strip().split()[1:8]]
    except Exception:
        pass

    output_path = "/dev/shm/sysinfo.json"
    interval = 2.0

    # Initial write immediately so file is present on boot/start
    try:
        gpu_data = gpu_collector.query()
        mem = {}
        with open("/proc/meminfo") as f:
            for line in f:
                p = line.split(":")
                if p[0] in ("MemTotal", "MemAvailable"):
                    mem[p[0]] = int(p[1].split()[0])
        total_kb = mem.get("MemTotal", 1)
        avail_kb = mem.get("MemAvailable", 0)
        used_kb = total_kb - avail_kb
        with open(output_path, "w") as f:
            f.write(json.dumps({
                "cpu": {"model": cpu_model, "util": 0, "temp": 0},
                "ram": {"used_gb": round(used_kb / 1048576, 1), "total_gb": round(total_kb / 1048576, 1), "percent": round(used_kb / total_kb * 100), "temp": 0},
                "gpu": gpu_data
            }))
    except Exception:
        pass

    while RUNNING:
        time.sleep(interval)
        if not RUNNING:
            break

        # 1. CPU Usage
        cpu_util = 0
        try:
            with open("/proc/stat") as f:
                curr_stat = [float(x) for x in f.readline().strip().split()[1:8]]
            if prev_stat:
                d_idle = (curr_stat[3] + curr_stat[4]) - (prev_stat[3] + prev_stat[4])
                d_total = sum(curr_stat) - sum(prev_stat)
                if d_total > 0:
                    cpu_util = round(max(0.0, min(100.0, (1.0 - d_idle / d_total) * 100)))
            prev_stat = curr_stat
        except Exception:
            pass

        # 2. CPU Temp
        cpu_temp = 0
        if cpu_temp_path:
            try:
                with open(cpu_temp_path) as f:
                    cpu_temp = round(int(f.read().strip()) / 1000.0)
            except Exception:
                cpu_temp_path, ram_temp_paths = discover_hwmon()
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

        # 3. RAM Usage
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
        ram_used_gb = round(used_kb / 1048576, 1)
        ram_total_gb = round(total_kb / 1048576, 1)
        ram_percent = round(used_kb / total_kb * 100)

        # 4. RAM Temp
        ram_temp = 0
        if ram_temp_paths:
            try:
                temps = []
                for p in ram_temp_paths:
                    with open(p) as f:
                        v = int(f.read().strip()) / 1000.0
                        if 0 < v < 120:
                            temps.append(v)
                if temps:
                    ram_temp = round(max(temps))
            except Exception:
                cpu_temp_path, ram_temp_paths = discover_hwmon()

        # 5. GPU Metrics
        gpu_data = gpu_collector.query()

        data = {
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
            "gpu": gpu_data
        }

        try:
            payload = json.dumps(data)
            with open(output_path, "w") as f:
                f.write(payload)
        except Exception:
            pass

if __name__ == "__main__":
    main()
