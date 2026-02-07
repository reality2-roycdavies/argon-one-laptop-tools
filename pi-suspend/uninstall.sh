#!/bin/bash
# uninstall.sh — Remove fake suspend and restore original Argon One lid behavior
#
# Run with: sudo ./uninstall.sh

set -e

if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: Run this script as root: sudo ./uninstall.sh"
    exit 1
fi

ARGON_FILE="/etc/argon/argonpowerbutton.py"

echo "=== Pi Fake Suspend Uninstaller ==="
echo ""

# Resume if currently suspended
if [ -f /run/pi-suspend-state ]; then
    echo "Resuming from fake suspend first..."
    /usr/local/bin/pi-suspend.sh resume 2>/dev/null || true
fi

# Restore original Argon One lid handler
if [ -f "$ARGON_FILE.pre-suspend" ]; then
    echo "Restoring original Argon One lid handler..."
    cp "$ARGON_FILE.pre-suspend" "$ARGON_FILE"
    chmod 644 "$ARGON_FILE"
    systemctl restart argononeupd.service
    echo "  -> Restored and restarted argononeupd"
fi

# Remove logind override
echo "Restoring default power key behavior..."
rm -f /etc/systemd/logind.conf.d/ignore-power-key.conf
systemctl restart systemd-logind

# Remove suspend script
echo "Removing suspend script..."
rm -f /usr/local/bin/pi-suspend.sh
rm -f /run/pi-suspend-state
rm -f /run/pi-suspend-usb-deauthed

echo ""
echo "=== Uninstall complete ==="
echo "Lid behavior restored to Argon One defaults."
