# Argon One Pi 5 Laptop Utilities

Utilities for the Raspberry Pi 5 in an Argon One laptop case, providing fake suspend/resume on lid close and a battery level system tray indicator.

## Pi Suspend

Fake suspend/resume triggered by the Argon One lid switch (GPIO 27). Since the Pi 5 lacks hardware suspend support, this script simulates it by:

- Turning off the display (via `wlr-randr` on Wayland)
- Throttling the CPU to minimum frequency
- Disabling WiFi and Bluetooth (via `rfkill`)
- Powering off USB 2.0 ports (via `uhubctl`)
- De-authorizing USB 3.0 devices
- Suspending audio (via PulseAudio)

On lid open, everything is restored.

### Prerequisites

- Raspberry Pi 5 (or CM5) in an Argon One case
- Argon One software installed (`argononeupd` service)
- Raspberry Pi OS (Bookworm) with Wayland/KDE
- `uhubctl` — installed automatically if not present:
  ```bash
  sudo apt install uhubctl
  ```

### Install

```bash
cd pi-suspend
sudo ./install.sh
```

This will:
1. Install `/usr/local/bin/pi-suspend.sh`
2. Configure `systemd-logind` to ignore the power key
3. Patch the Argon One lid handler to call suspend/resume instead of shutdown

### Manual usage

```bash
sudo pi-suspend.sh suspend   # Force suspend
sudo pi-suspend.sh resume    # Force resume
sudo pi-suspend.sh toggle    # Toggle between states
sudo pi-suspend.sh status    # Show current state
```

### Logs

```bash
journalctl -t pi-suspend              # Suspend/resume events
cat /dev/shm/argononegpiodebuglog.txt # Argon One lid events
```

### Uninstall

```bash
cd pi-suspend
sudo ./uninstall.sh
```

### Known limitations

- USB 3.0 ports on the Pi 5 do not support hardware power switching. Devices on USB 3.0 will be de-authorized (no communication) but may still draw bus power. Move devices to USB 2.0 ports if full power cutoff is needed.

## Battery Tray

A KDE system tray indicator that displays battery level from the Argon One UPS. Reads status from the `argononeupd` daemon and shows the appropriate charge/discharge icon.

### Prerequisites

- Argon One UPS with `argononeupd` service running
- Python 3 with PyQt6:
  ```bash
  sudo apt install python3-pyqt6
  ```

### Install

```bash
cd battery-tray
./install.sh
```

The indicator will start automatically on next login. To start immediately:

```bash
python3 ~/.local/bin/argon-battery-tray.py &
```

## License

MIT
