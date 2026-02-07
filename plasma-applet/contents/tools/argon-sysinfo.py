#!/usr/bin/env python3
"""System info helper for the Argon Battery Plasma applet.

Outputs JSON with battery, CPU, RAM, temperature, IP, and storage info.
Called periodically by the QML DataSource.
"""

import json
import os
import re
import socket

LOG_FILE = "/dev/shm/upslog.txt"
CPU_PREV_FILE = "/dev/shm/argon-cpu-prev"
STATUS_RE = re.compile(r"Power:(Battery|Charging|Charged)\s+(\d+)%")


def read_battery():
    try:
        with open(LOG_FILE) as f:
            m = STATUS_RE.search(f.read())
            if m:
                return m.group(1), int(m.group(2))
    except (OSError, IOError):
        pass
    return None, None


def read_cpu_temp():
    try:
        with open("/sys/class/thermal/thermal_zone0/temp") as f:
            return round(int(f.read().strip()) / 1000, 1)
    except (OSError, ValueError):
        return None


def read_ram():
    total = free = buffers = cached = 0
    try:
        with open("/proc/meminfo") as f:
            for line in f:
                parts = line.split()
                key = parts[0]
                if key == "MemTotal:":
                    total = int(parts[1])
                elif key == "MemFree:":
                    free = int(parts[1])
                elif key == "Buffers:":
                    buffers = int(parts[1])
                elif key == "Cached:":
                    cached = int(parts[1])
    except OSError:
        return None, None
    if total == 0:
        return None, None
    available = free + buffers + cached
    used_pct = int(100 * (total - available) / total)
    total_gb = round((total + 512 * 1024) / (1024 * 1024))
    return used_pct, total_gb


def read_cpu_snapshot():
    result = {}
    try:
        with open("/proc/stat") as f:
            for line in f:
                if not line.startswith("cpu"):
                    continue
                parts = line.split()
                name = parts[0]
                vals = [int(v) for v in parts[1:]]
                total = sum(vals)
                idle = vals[3] + (vals[4] if len(vals) > 4 else 0)
                result[name] = [total, idle]
    except OSError:
        pass
    return result


def read_cpu_usage():
    prev = {}
    try:
        with open(CPU_PREV_FILE) as f:
            prev = json.load(f)
    except (OSError, json.JSONDecodeError):
        pass

    cur = read_cpu_snapshot()

    try:
        with open(CPU_PREV_FILE, "w") as f:
            json.dump(cur, f)
    except OSError:
        pass

    usage = {}
    for name in sorted(cur.keys()):
        if name == "cpu":
            continue
        if name in prev:
            dtotal = cur[name][0] - prev[name][0]
            didle = cur[name][1] - prev[name][1]
            if dtotal > 0:
                usage[name] = int(100 * (dtotal - didle) / dtotal)
            else:
                usage[name] = 0
        else:
            usage[name] = 0
    return usage


def read_ip():
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("254.255.255.255", 1))
        addr = s.getsockname()[0]
        s.close()
        return addr
    except Exception:
        return "N/A"


def _kb_str(kb):
    for suffix in ("KB", "MB", "GB", "TB"):
        if kb < 1024:
            return f"{kb}{suffix}"
        kb = (kb + 512) >> 10
    return f"{kb}TB"


def read_storage():
    results = {}
    try:
        stream = os.popen("df 2>/dev/null")
        for line in stream:
            parts = line.split()
            if len(parts) < 6 or not parts[0].startswith("/dev/"):
                continue
            dev = parts[0].rsplit("/", 1)[-1]
            if dev[0:2] in ("sd", "hd"):
                dev = dev.rstrip("0123456789")
            elif "p" in dev:
                dev = dev.rsplit("p", 1)[0]
            total_kb = int(parts[1])
            used_kb = int(parts[2])
            if dev in results:
                results[dev] = (results[dev][0] + used_kb, results[dev][1] + total_kb)
            else:
                results[dev] = (used_kb, total_kb)
        stream.close()
    except Exception:
        pass
    out = []
    for dev, (used, total) in results.items():
        if total > 0:
            pct = int(100 * used / total)
            out.append({"device": dev, "percent": pct, "total": _kb_str(total)})
    return out


def main():
    bat_status, bat_percent = read_battery()
    info = {
        "battery_status": bat_status,
        "battery_percent": bat_percent if bat_percent is not None else 0,
        "cpu_temp": read_cpu_temp(),
        "ram_percent": None,
        "ram_total": None,
        "cpu_usage": read_cpu_usage(),
        "ip": read_ip(),
        "storage": read_storage(),
    }
    ram_pct, ram_total = read_ram()
    info["ram_percent"] = ram_pct
    info["ram_total"] = ram_total
    print(json.dumps(info))


if __name__ == "__main__":
    try:
        main()
    except Exception:
        print(json.dumps({"error": True}))
