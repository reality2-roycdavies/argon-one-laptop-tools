#!/usr/bin/env python3
"""Argon battery level indicator for the KDE system tray.

Reads battery status from /dev/shm/upslog.txt (written by argononeupd)
and displays the appropriate icon in the system tray.

Left-click shows a system info popup with battery, CPU, RAM, storage,
temperature, and IP address.
"""

import sys
import os
import re
import fcntl
import socket

LOCK_FILE = os.path.expanduser("~/.cache/argon-battery-tray.lock")
LOG_FILE = "/dev/shm/upslog.txt"
ICON_DIR = "/etc/argon/ups"
POLL_INTERVAL_MS = 5000

STATUS_RE = re.compile(r"Power:(Battery|Charging|Charged)\s+(\d+)%")


def acquire_lock():
    """Ensure only one instance runs. Returns the lock file object or exits."""
    os.makedirs(os.path.dirname(LOCK_FILE), exist_ok=True)
    lock_fp = open(LOCK_FILE, "w")
    try:
        fcntl.flock(lock_fp, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        sys.exit(0)
    lock_fp.write(str(os.getpid()))
    lock_fp.flush()
    return lock_fp


def read_status():
    """Read and parse the Argon UPS log file."""
    try:
        with open(LOG_FILE, "r") as f:
            content = f.read()
    except (OSError, IOError):
        return None, None
    m = STATUS_RE.search(content)
    if m:
        return m.group(1), int(m.group(2))
    return None, None


def icon_path(status, percent):
    """Return the path to the appropriate battery icon."""
    percent = max(0, min(100, percent))
    if status == "Battery":
        return os.path.join(ICON_DIR, f"discharge_{percent}.png")
    return os.path.join(ICON_DIR, f"charge_{percent}.png")


# ── System info helpers ──────────────────────────────────────────────

def get_cpu_temp():
    try:
        with open("/sys/class/thermal/thermal_zone0/temp") as f:
            return round(int(f.read().strip()) / 1000, 1)
    except (OSError, ValueError):
        return None


def get_ram():
    """Returns (used_percent, total_gb)."""
    total = free = buffers = cached = 0
    try:
        with open("/proc/meminfo") as f:
            for line in f:
                parts = line.split()
                if parts[0] == "MemTotal:":
                    total = int(parts[1])
                elif parts[0] == "MemFree:":
                    free = int(parts[1])
                elif parts[0] == "Buffers:":
                    buffers = int(parts[1])
                elif parts[0] == "Cached:":
                    cached = int(parts[1])
    except OSError:
        return None, None
    if total == 0:
        return None, None
    available = free + buffers + cached
    used_pct = int(100 * (total - available) / total)
    total_gb = round((total + 512 * 1024) / (1024 * 1024))
    return used_pct, total_gb


def get_cpu_usage():
    """Returns dict of {core_name: (total, idle)} for a snapshot."""
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
                idle = vals[3] + vals[4] if len(vals) > 4 else vals[3]
                result[name] = (total, idle)
    except OSError:
        pass
    return result


def get_ip():
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("254.255.255.255", 1))
        addr = s.getsockname()[0]
        s.close()
        return addr
    except Exception:
        return "N/A"


def get_storage():
    """Returns list of (device, used_pct, total_str)."""
    results = {}
    try:
        stream = os.popen("df 2>/dev/null")
        for line in stream:
            parts = line.split()
            if len(parts) < 6 or not parts[0].startswith("/dev/"):
                continue
            dev = parts[0].rsplit("/", 1)[-1]
            # Aggregate partitions: nvme0n1p1,p2 -> nvme0n1; sda1,sda2 -> sda
            if dev[0:2] in ("sd", "hd"):
                dev = dev.rstrip("0123456789")
            elif "p" in dev:
                dev = dev.rsplit("p", 1)[0]
            total_kb = int(parts[1])
            used_kb = int(parts[2])
            if dev in results:
                results[dev] = (
                    results[dev][0] + used_kb,
                    results[dev][1] + total_kb,
                )
            else:
                results[dev] = (used_kb, total_kb)
        stream.close()
    except Exception:
        pass
    out = []
    for dev, (used, total) in results.items():
        if total > 0:
            pct = int(100 * used / total)
            total_str = _kb_str(total)
            out.append((dev, pct, total_str))
    return out


def _kb_str(kb):
    for suffix in ("KB", "MB", "GB", "TB"):
        if kb < 1024:
            return f"{kb}{suffix}"
        kb = (kb + 512) >> 10
    return f"{kb}TB"


# ── Popup widget ─────────────────────────────────────────────────────

def create_popup(tray):
    from PyQt6.QtWidgets import QWidget, QVBoxLayout, QLabel, QGridLayout
    from PyQt6.QtCore import Qt, QTimer
    import time

    class InfoPopup(QWidget):
        def __init__(self):
            super().__init__()
            self.setWindowFlags(
                Qt.WindowType.Popup
                | Qt.WindowType.FramelessWindowHint
            )
            self.setStyleSheet("""
                InfoPopup {
                    background-color: #2b2b2b;
                    border: 1px solid #555;
                    border-radius: 8px;
                }
                QLabel {
                    color: #e0e0e0;
                    font-size: 13px;
                }
                QLabel[role="heading"] {
                    color: #88c0d0;
                    font-weight: bold;
                    font-size: 14px;
                }
                QLabel[role="value"] {
                    color: #ffffff;
                }
                QLabel[role="warn"] {
                    color: #ebcb8b;
                }
                QLabel[role="alert"] {
                    color: #bf616a;
                }
            """)

            self._prev_cpu = get_cpu_usage()

            layout = QVBoxLayout()
            layout.setContentsMargins(12, 10, 12, 10)
            layout.setSpacing(6)

            self._grid = QGridLayout()
            self._grid.setSpacing(4)
            self._grid.setColumnMinimumWidth(0, 100)
            self._grid.setColumnMinimumWidth(1, 140)
            layout.addLayout(self._grid)

            self.setLayout(layout)

            self._labels = {}
            self._refresh_timer = QTimer(self)
            self._refresh_timer.timeout.connect(self._refresh)

            self._build()
            self._refresh()

        def showEvent(self, event):
            super().showEvent(event)
            self._prev_cpu = get_cpu_usage()
            self._refresh_timer.start(POLL_INTERVAL_MS)

        def hideEvent(self, event):
            super().hideEvent(event)
            self._refresh_timer.stop()

        def _add_heading(self, row, text):
            lbl = QLabel(text)
            lbl.setProperty("role", "heading")
            self._grid.addWidget(lbl, row, 0, 1, 2)

        def _add_row(self, row, key, label_text):
            lbl = QLabel(label_text)
            val = QLabel("")
            val.setProperty("role", "value")
            val.setAlignment(Qt.AlignmentFlag.AlignRight)
            self._grid.addWidget(lbl, row, 0)
            self._grid.addWidget(val, row, 1)
            self._labels[key] = val

        def _build(self):
            r = 0
            self._add_heading(r, "Battery"); r += 1
            self._add_row(r, "battery", "Status"); r += 1

            self._add_heading(r, "Network"); r += 1
            self._add_row(r, "ip", "IP Address"); r += 1

            self._add_heading(r, "System"); r += 1
            self._add_row(r, "temp", "CPU Temp"); r += 1
            self._add_row(r, "ram", "RAM"); r += 1

            self._add_heading(r, "CPU"); r += 1
            # Add rows for each core dynamically
            self._cpu_start_row = r
            snap = get_cpu_usage()
            for name in sorted(snap.keys()):
                if name == "cpu":
                    continue
                self._add_row(r, name, name.upper()); r += 1

            self._add_heading(r, "Storage"); r += 1
            self._storage_start_row = r
            for dev, _, _ in get_storage():
                self._add_row(r, f"stor_{dev}", dev); r += 1

        def _refresh(self):
            status, pct = read_status()
            if status and pct is not None:
                bat_lbl = self._labels["battery"]
                bat_lbl.setText(f"{status} {pct}%")
                if status == "Battery" and pct <= 20:
                    bat_lbl.setProperty("role", "alert")
                elif status == "Battery" and pct <= 50:
                    bat_lbl.setProperty("role", "warn")
                else:
                    bat_lbl.setProperty("role", "value")
                bat_lbl.style().unpolish(bat_lbl)
                bat_lbl.style().polish(bat_lbl)
            else:
                self._labels["battery"].setText("Unknown")

            self._labels["ip"].setText(get_ip())

            temp = get_cpu_temp()
            self._labels["temp"].setText(
                f"{temp}\u00b0C" if temp is not None else "N/A"
            )

            used_pct, total_gb = get_ram()
            if used_pct is not None:
                self._labels["ram"].setText(f"{used_pct}% of {total_gb}GB")
            else:
                self._labels["ram"].setText("N/A")

            cur_cpu = get_cpu_usage()
            for name in sorted(cur_cpu.keys()):
                if name == "cpu" or name not in self._labels:
                    continue
                prev = self._prev_cpu.get(name)
                if prev and cur_cpu[name][0] != prev[0]:
                    dtotal = cur_cpu[name][0] - prev[0]
                    didle = cur_cpu[name][1] - prev[1]
                    pct = int(100 * (dtotal - didle) / dtotal)
                    self._labels[name].setText(f"{pct}%")
                else:
                    self._labels[name].setText("...")
            self._prev_cpu = cur_cpu

            for dev, pct, total_str in get_storage():
                key = f"stor_{dev}"
                if key in self._labels:
                    self._labels[key].setText(f"{pct}% of {total_str}")

    popup = InfoPopup()
    return popup


# ── Main ─────────────────────────────────────────────────────────────

def main():
    from PyQt6.QtWidgets import QApplication, QSystemTrayIcon, QMenu
    from PyQt6.QtGui import QIcon, QAction
    from PyQt6.QtCore import QTimer

    lock_fp = acquire_lock()  # noqa: F841

    app = QApplication(sys.argv)
    app.setQuitOnLastWindowClosed(False)

    tray = QSystemTrayIcon()
    tray.setToolTip("Battery: Unknown")

    status, percent = read_status()
    if status and percent is not None:
        tray.setIcon(QIcon(icon_path(status, percent)))
        tray.setToolTip(f"{status}: {percent}%")
    else:
        tray.setIcon(QIcon(os.path.join(ICON_DIR, "discharge_0.png")))

    menu = QMenu()
    quit_action = QAction("Quit")
    quit_action.triggered.connect(app.quit)
    menu.addAction(quit_action)
    tray.setContextMenu(menu)

    popup = create_popup(tray)

    def on_tray_activated(reason):
        if reason == QSystemTrayIcon.ActivationReason.Trigger:
            if popup.isVisible():
                popup.hide()
                return
            popup.adjustSize()
            screen = app.primaryScreen()
            if screen:
                sg = screen.availableGeometry()
                x = sg.x() + sg.width() - popup.width() - 8
                y = sg.y() + sg.height() - popup.height() - 8
            else:
                x = 100
                y = 100
            popup.move(x, y)
            popup.show()

    tray.activated.connect(on_tray_activated)
    tray.show()

    def update():
        status, percent = read_status()
        if status and percent is not None:
            path = icon_path(status, percent)
            if os.path.isfile(path):
                tray.setIcon(QIcon(path))
            tray.setToolTip(f"{status}: {percent}%")
        else:
            tray.setToolTip("Battery: Unknown")

    timer = QTimer()
    timer.timeout.connect(update)
    timer.start(POLL_INTERVAL_MS)

    sys.exit(app.exec())


if __name__ == "__main__":
    main()
