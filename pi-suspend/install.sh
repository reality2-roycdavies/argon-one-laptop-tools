#!/bin/bash
# install.sh — Install fake suspend for Argon One Pi 5 laptops
#
# What this does:
#   1. Installs the suspend/resume script
#   2. Tells systemd-logind to ignore the power key
#   3. Patches the Argon One lid handler to call suspend/resume instead of shutdown
#
# Run with: sudo ./install.sh

set -e

if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: Run this script as root: sudo ./install.sh"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ARGON_FILE="/etc/argon/argonpowerbutton.py"

echo "=== Pi Fake Suspend Installer ==="
echo ""

# 1. Install the suspend script
echo "[1/3] Installing suspend/resume script..."
install -m 755 "$SCRIPT_DIR/pi-suspend.sh" /usr/local/bin/pi-suspend.sh
echo "  -> Installed /usr/local/bin/pi-suspend.sh"

# 2. Configure logind to ignore the power key
echo "[2/3] Configuring systemd-logind to ignore power key..."
mkdir -p /etc/systemd/logind.conf.d
cat > /etc/systemd/logind.conf.d/ignore-power-key.conf << 'EOF'
[Login]
HandlePowerKey=ignore
HandlePowerKeyLongPress=ignore
EOF
systemctl restart systemd-logind
echo "  -> Created /etc/systemd/logind.conf.d/ignore-power-key.conf"

# 3. Patch Argon One lid handler
echo "[3/3] Patching Argon One lid handler..."
if [ -f "$ARGON_FILE" ]; then
    # Backup original if not already backed up
    if [ ! -f "$ARGON_FILE.pre-suspend" ]; then
        cp "$ARGON_FILE" "$ARGON_FILE.pre-suspend"
        echo "  -> Backed up original to $ARGON_FILE.pre-suspend"
    fi
    cp "$SCRIPT_DIR/argonpowerbutton.py.modified" "$ARGON_FILE"
    chmod 644 "$ARGON_FILE"
    systemctl restart argononeupd.service
    echo "  -> Patched and restarted argononeupd"
else
    echo "  -> WARNING: $ARGON_FILE not found. Argon One software not installed?"
fi

echo ""
echo "=== Installation complete ==="
echo ""
echo "Lid close will now suspend (display off, CPU throttled, WiFi/BT off, USB off)."
echo "Lid open will resume."
echo ""
echo "Useful commands:"
echo "  sudo pi-suspend.sh status    # Check if suspended or active"
echo "  sudo pi-suspend.sh toggle    # Manually toggle suspend"
echo "  journalctl -t pi-suspend     # View suspend/resume logs"
echo ""
echo "To uninstall: sudo ./uninstall.sh"
