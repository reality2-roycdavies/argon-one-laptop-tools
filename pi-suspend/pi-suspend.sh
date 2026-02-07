#!/bin/bash
# pi-suspend.sh — Fake suspend/resume for Raspberry Pi 5
# Turns off display, throttles CPU, disables WiFi/BT, powers off USB.

STATE_FILE="/run/pi-suspend-state"

# Find the active graphical session user and their environment
find_desktop_user() {
    DESKTOP_USER=""
    DESKTOP_UID=""
    DESKTOP_RUNTIME=""
    WAYLAND_SOCK=""

    # Try loginctl first
    while IFS= read -r session; do
        local stype
        stype=$(loginctl show-session "$session" -p Type --value 2>/dev/null)
        if [ "$stype" = "wayland" ] || [ "$stype" = "x11" ]; then
            DESKTOP_USER=$(loginctl show-session "$session" -p Name --value 2>/dev/null)
            break
        fi
    done < <(loginctl --no-legend | awk '{print $1}')

    # Fallback: find who owns a wayland socket
    if [ -z "$DESKTOP_USER" ]; then
        for rd in /run/user/*/; do
            if [ -S "${rd}wayland-0" ]; then
                DESKTOP_UID=$(basename "$rd" | tr -dc '0-9')
                DESKTOP_USER=$(id -nu "$DESKTOP_UID" 2>/dev/null)
                break
            fi
        done
    fi

    if [ -n "$DESKTOP_USER" ]; then
        DESKTOP_UID=$(id -u "$DESKTOP_USER" 2>/dev/null)
        DESKTOP_RUNTIME="/run/user/$DESKTOP_UID"
        if [ -S "$DESKTOP_RUNTIME/wayland-0" ]; then
            WAYLAND_SOCK="wayland-0"
        fi
    fi
}

# Run a command as the desktop user with Wayland env
run_as_user() {
    if [ -n "$DESKTOP_USER" ] && [ -n "$DESKTOP_RUNTIME" ]; then
        sudo -u "$DESKTOP_USER" \
            WAYLAND_DISPLAY="${WAYLAND_SOCK}" \
            XDG_RUNTIME_DIR="$DESKTOP_RUNTIME" \
            "$@" 2>/dev/null
    fi
}

# Find connected DRM outputs
find_drm_outputs() {
    DRM_OUTPUTS=()
    for status_file in /sys/class/drm/card*-*/status; do
        if [ "$(cat "$status_file" 2>/dev/null)" = "connected" ]; then
            local dir name output
            dir=$(dirname "$status_file")
            name=$(basename "$dir")
            output="${name#card*-}"
            DRM_OUTPUTS+=("$output")
        fi
    done
}

suspend() {
    logger -t pi-suspend "Suspending..."
    find_desktop_user
    find_drm_outputs

    # --- Lock screen ---
    run_as_user loginctl lock-session
    sleep 0.5

    # --- Display off ---
    for output in "${DRM_OUTPUTS[@]}"; do
        run_as_user wlr-randr --output "$output" --off
        logger -t pi-suspend "Display $output off"
    done
    for bl in /sys/class/backlight/*/bl_power; do
        [ -f "$bl" ] && echo 1 > "$bl"
    done

    # --- CPU to minimum ---
    for gov in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
        [ -f "$gov" ] && echo powersave > "$gov"
    done

    # --- Bring down all wifi interfaces then rfkill ---
    for iface in $(ip -o link show | awk -F': ' '/wlan/{print $2}'); do
        ip link set "$iface" down 2>/dev/null
    done
    rfkill block wifi 2>/dev/null
    rfkill block bluetooth 2>/dev/null

    # --- Suspend audio ---
    run_as_user pactl suspend-sink 1
    run_as_user pactl suspend-source 1

    # --- Suspend USB devices ---
    # Step 1: Cut VBUS power via uhubctl FIRST (while devices are still bound)
    # Hub 1 (dwc2): powers the QinHeng hub with keyboard, camera, audio, wifi
    uhubctl -l 1 --action off --force 2>/dev/null
    # Hub 2,4 (xhci USB 2.0 companion ports)
    uhubctl -l 2 --action off --force 2>/dev/null
    uhubctl -l 4 --action off --force 2>/dev/null
    sleep 1
    # Step 2: De-authorize remaining USB devices (stops them without needing unbind)
    # This handles USB 3.0 devices that uhubctl can't power off
    USB_DEAUTHED=""
    for dev in /sys/bus/usb/devices/[0-9]*-[0-9]*; do
        [ -d "$dev" ] || continue
        case "$(basename "$dev")" in *:*) continue ;; esac
        local devname
        devname=$(basename "$dev")
        if [ -f "$dev/authorized" ]; then
            curauth=$(cat "$dev/authorized" 2>/dev/null)
            if [ "$curauth" = "1" ]; then
                echo 0 > "$dev/authorized" 2>/dev/null && \
                    USB_DEAUTHED="$USB_DEAUTHED $devname"
            fi
        fi
    done
    [ -n "$USB_DEAUTHED" ] && echo "$USB_DEAUTHED" > /run/pi-suspend-usb-deauthed
    logger -t pi-suspend "USB: power off hubs 1,2,4; de-authorized:$USB_DEAUTHED"

    touch "$STATE_FILE"
    logger -t pi-suspend "Suspended."
}

resume() {
    logger -t pi-suspend "Resuming..."
    find_desktop_user
    find_drm_outputs

    # --- Resume USB devices ---
    # Step 1: Re-authorize de-authorized devices
    if [ -f /run/pi-suspend-usb-deauthed ]; then
        for devname in $(cat /run/pi-suspend-usb-deauthed); do
            local devpath="/sys/bus/usb/devices/$devname"
            [ -f "$devpath/authorized" ] && echo 1 > "$devpath/authorized" 2>/dev/null
        done
        rm -f /run/pi-suspend-usb-deauthed
    fi
    # Step 2: Power hubs back on
    uhubctl -l 1 --action on --force 2>/dev/null
    uhubctl -l 2 --action on --force 2>/dev/null
    uhubctl -l 4 --action on --force 2>/dev/null
    logger -t pi-suspend "USB devices restored"
    sleep 2  # give USB devices time to re-enumerate

    # --- Re-enable WiFi and Bluetooth ---
    rfkill unblock wifi 2>/dev/null
    rfkill unblock bluetooth 2>/dev/null
    for iface in $(ip -o link show | awk -F': ' '/wlan/{print $2}'); do
        ip link set "$iface" up 2>/dev/null
    done
    if command -v nmcli &>/dev/null; then
        nmcli radio wifi on 2>/dev/null
        nmcli networking on 2>/dev/null
    fi

    # --- Display on ---
    for bl in /sys/class/backlight/*/bl_power; do
        [ -f "$bl" ] && echo 0 > "$bl"
    done
    for output in "${DRM_OUTPUTS[@]}"; do
        run_as_user wlr-randr --output "$output" --on
        logger -t pi-suspend "Display $output on"
    done

    # --- CPU back to ondemand ---
    for gov in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
        [ -f "$gov" ] && echo ondemand > "$gov"
    done

    # --- Resume audio ---
    run_as_user pactl suspend-sink 0
    run_as_user pactl suspend-source 0

    rm -f "$STATE_FILE"
    logger -t pi-suspend "Resumed."
}

toggle() {
    if [ -f "$STATE_FILE" ]; then
        resume
    else
        suspend
    fi
}

case "${1:-toggle}" in
    suspend)  suspend ;;
    resume)   resume ;;
    toggle)   toggle ;;
    status)
        if [ -f "$STATE_FILE" ]; then
            echo "suspended"
        else
            echo "active"
        fi
        ;;
    *)        echo "Usage: $0 {suspend|resume|toggle|status}" ;;
esac
