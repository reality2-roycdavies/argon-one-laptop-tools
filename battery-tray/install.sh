#!/bin/bash
# install.sh — Install Argon battery tray indicator
#
# Displays battery status in the KDE system tray using icons from Argon One.
# Requires: python3, PyQt6, argononeupd service running.
#
# Run as your normal user (not root): ./install.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TARGET_BIN="$HOME/.local/bin/argon-battery-tray.py"
TARGET_DESKTOP="$HOME/.config/autostart/argon-battery-tray.desktop"

echo "=== Argon Battery Tray Installer ==="
echo ""

mkdir -p "$HOME/.local/bin"
mkdir -p "$HOME/.config/autostart"

install -m 755 "$SCRIPT_DIR/argon-battery-tray.py" "$TARGET_BIN"
echo "  -> Installed $TARGET_BIN"

# Update desktop file with correct home path
sed "s|/home/roycdavies|$HOME|g" "$SCRIPT_DIR/argon-battery-tray.desktop" > "$TARGET_DESKTOP"
echo "  -> Installed $TARGET_DESKTOP"

echo ""
echo "=== Installation complete ==="
echo "The battery tray will start automatically on next login."
echo "To start it now:  python3 $TARGET_BIN &"
