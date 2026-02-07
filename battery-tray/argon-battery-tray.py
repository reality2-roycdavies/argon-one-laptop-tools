#!/usr/bin/env python3
"""Argon battery level indicator for the KDE system tray.

Reads battery status from /dev/shm/upslog.txt (written by argononeupd)
and displays the appropriate icon in the system tray.
"""

import sys
import os
import re
import fcntl

LOCK_FILE = os.path.expanduser("~/.cache/argon-battery-tray.lock")
LOG_FILE = "/dev/shm/upslog.txt"
ICON_DIR = "/etc/argon/ups"
POLL_INTERVAL_MS = 5000

# Regex to parse "Power:Status NN%" from the log file
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
    """Read and parse the Argon UPS log file.

    Returns (status, percent) e.g. ("Battery", 51) or (None, None) on failure.
    """
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


def main():
    from PyQt6.QtWidgets import QApplication, QSystemTrayIcon, QMenu
    from PyQt6.QtGui import QIcon, QAction
    from PyQt6.QtCore import QTimer

    lock_fp = acquire_lock()  # noqa: F841 — must stay alive

    app = QApplication(sys.argv)
    app.setQuitOnLastWindowClosed(False)

    tray = QSystemTrayIcon()
    tray.setToolTip("Battery: Unknown")

    # Set an initial icon
    status, percent = read_status()
    if status and percent is not None:
        tray.setIcon(QIcon(icon_path(status, percent)))
        tray.setToolTip(f"{status}: {percent}%")
    else:
        # Fallback: use discharge_0 as a placeholder
        tray.setIcon(QIcon(os.path.join(ICON_DIR, "discharge_0.png")))

    # Context menu
    menu = QMenu()
    quit_action = QAction("Quit")
    quit_action.triggered.connect(app.quit)
    menu.addAction(quit_action)
    tray.setContextMenu(menu)

    tray.show()

    # Periodic update
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
