# Argon One Pi 5 Laptop Utilities

Utilities for the Raspberry Pi 5 in an Argon One laptop case running KDE Plasma on Wayland, providing fake suspend/resume on lid close and a KDE system tray battery indicator.

Tested on Raspberry Pi OS (Bookworm) with KDE Plasma desktop.

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
- Raspberry Pi OS (Bookworm) with KDE Plasma on Wayland
- `wlr-randr` (for display control under Wayland)
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

## Plasma Applet (Argon Battery)

A native KDE Plasma 6 panel widget that displays battery status and system information from the Argon One UPS. Click the battery icon to see:

- Battery status and percentage
- IP address
- CPU temperature
- RAM usage
- Per-core CPU usage
- Storage usage

### Prerequisites

- KDE Plasma 6 desktop on Wayland
- Argon One UPS with `argononeupd` service running
- Python 3

### Install

```bash
cd plasma-applet
./install.sh
```

Then right-click on your panel, click **Add Widgets...**, search for **Argon Battery**, and drag it to the panel.

After adding the widget, go to **Configure System Tray... -> Entries** and disable the built-in **Argon Battery** entry under Hardware Control to avoid a duplicate icon.

### Upgrade

Re-run `./install.sh` — it will upgrade the existing plasmoid in place.

## Battery Tray (legacy)

The `battery-tray/` directory contains an older PyQt6-based system tray indicator. This has been superseded by the Plasma applet above, which integrates natively with the panel and correctly positions its popup on Wayland.

## License

MIT
