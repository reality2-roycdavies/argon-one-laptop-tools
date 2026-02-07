#!/usr/bin/env bash
set -e

APPLET_ID="org.argon.battery"
PLASMOID_DIR="$HOME/.local/share/plasma/plasmoids/$APPLET_ID"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "Installing Argon Battery plasmoid..."

# Kill old PyQt6 tray if running
pkill -f argon-battery-tray.py 2>/dev/null || true
rm -f "$HOME/.cache/argon-battery-tray.lock" 2>/dev/null

# Remove old autostart entry
rm -f "$HOME/.config/autostart/argon-battery-tray.desktop" 2>/dev/null

# Remove Argon ONE UP desktop shortcut
rm -f "$HOME/Desktop/argononeup.desktop" 2>/dev/null

# Install plasmoid
if command -v kpackagetool6 &>/dev/null; then
    if [ -d "$PLASMOID_DIR" ]; then
        echo "Upgrading existing plasmoid..."
        kpackagetool6 --type Plasma/Applet --upgrade "$SCRIPT_DIR" 2>/dev/null || {
            echo "Upgrade failed, reinstalling..."
            rm -rf "$PLASMOID_DIR"
            kpackagetool6 --type Plasma/Applet --install "$SCRIPT_DIR"
        }
    else
        kpackagetool6 --type Plasma/Applet --install "$SCRIPT_DIR"
    fi
else
    echo "kpackagetool6 not found, copying manually..."
    mkdir -p "$PLASMOID_DIR/contents/ui"
    mkdir -p "$PLASMOID_DIR/contents/tools"
    cp "$SCRIPT_DIR/metadata.json" "$PLASMOID_DIR/"
    cp "$SCRIPT_DIR/contents/ui/main.qml" "$PLASMOID_DIR/contents/ui/"
    cp "$SCRIPT_DIR/contents/tools/argon-sysinfo.py" "$PLASMOID_DIR/contents/tools/"
fi

chmod +x "$PLASMOID_DIR/contents/tools/argon-sysinfo.py"

echo ""
echo "Done! To add the widget to your panel:"
echo "  1. Right-click on the panel -> 'Add Widgets...'"
echo "  2. Search for 'Argon Battery'"
echo "  3. Drag it to the panel"
echo ""
echo "If the widget doesn't appear, restart Plasma:"
echo "  kquitapp6 plasmashell && kstart plasmashell"
