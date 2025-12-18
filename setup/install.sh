#!/bin/bash
# RetroTV Installation Script
# Run this on the Raspberry Pi after copying the setup files

set -e

echo "=== RetroTV Installation ==="
echo ""

# Check if running as root for system file installation
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root (use sudo)"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Detect the primary user (the one who invoked sudo, or first user with UID 1000)
if [ -n "$SUDO_USER" ]; then
    SERVICE_USER="$SUDO_USER"
else
    SERVICE_USER=$(getent passwd 1000 | cut -d: -f1)
fi
echo "Service will run as user: $SERVICE_USER"
echo ""

echo "[1/7] Installing VLC if not present..."
if ! command -v cvlc &> /dev/null; then
    apt update
    apt install -y vlc
else
    echo "  VLC already installed"
fi

echo "[2/7] Installing udev rule for USB automount..."
cp "$SCRIPT_DIR/99-retrotv-usb.rules" /etc/udev/rules.d/
udevadm control --reload-rules
echo "  Done"

echo "[3/7] Installing player script..."
cp "$SCRIPT_DIR/retrotv-player.sh" /usr/local/bin/
chmod 755 /usr/local/bin/retrotv-player.sh
echo "  Done"

echo "[4/7] Installing systemd service..."
# Update service file with detected user
sed "s/User=retro-tv/User=$SERVICE_USER/" "$SCRIPT_DIR/retrotv.service" > /etc/systemd/system/retrotv.service
systemctl daemon-reload
systemctl enable retrotv.service
echo "  Done"

echo "[5/7] Creating mount point and adding fstab entry..."
mkdir -p /media/retroTV
chown "$SERVICE_USER:$SERVICE_USER" /media/retroTV
# Add fstab entry for reliable USB mounting (if not already present)
if ! grep -q "LABEL=retroTV" /etc/fstab; then
    echo "LABEL=retroTV /media/retroTV auto defaults,nofail,uid=$(id -u "$SERVICE_USER"),gid=$(id -g "$SERVICE_USER") 0 0" >> /etc/fstab
    echo "  Added fstab entry for USB drive"
fi
echo "  Done"

echo "[6/7] Configuring HDMI output..."
CONFIG_FILE="/boot/firmware/config.txt"
if [ ! -f "$CONFIG_FILE" ]; then
    CONFIG_FILE="/boot/config.txt"
fi
if [ -f "$CONFIG_FILE" ]; then
    if ! grep -q "hdmi_force_hotplug=1" "$CONFIG_FILE"; then
        echo "" >> "$CONFIG_FILE"
        echo "# RetroTV: Force HDMI output even without monitor" >> "$CONFIG_FILE"
        echo "hdmi_force_hotplug=1" >> "$CONFIG_FILE"
        echo "  Added hdmi_force_hotplug=1"
    else
        echo "  HDMI force hotplug already configured"
    fi
fi
echo "  Done"

echo "[7/7] Setting USB drive permissions (if mounted)..."
if mountpoint -q /media/retroTV 2>/dev/null; then
    chown -R "$SERVICE_USER:$SERVICE_USER" /media/retroTV
    echo "  Set ownership to $SERVICE_USER"
else
    echo "  USB not mounted - remember to set ownership after mounting"
fi
echo "  Done"

echo ""
echo "=== Installation Complete ==="
echo ""
echo "IMPORTANT: Make sure your USB drive is labeled 'retroTV'"
echo "To label the drive, you can use:"
echo "  - For FAT32: sudo fatlabel /dev/sdX1 retroTV"
echo "  - For ext4:  sudo e2label /dev/sdX1 retroTV"
echo ""
echo "For ext4 drives, set ownership after mounting:"
echo "  sudo chown -R $SERVICE_USER:$SERVICE_USER /media/retroTV"
echo ""
echo "Commands:"
echo "  Start now:    sudo systemctl start retrotv"
echo "  Stop:         sudo systemctl stop retrotv"
echo "  View status:  sudo systemctl status retrotv"
echo "  View logs:    journalctl -u retrotv -f"
echo ""
echo "OPTIONAL: Enable read-only filesystem for safe power-off:"
echo "  sudo raspi-config -> Performance -> Overlay File System -> Enable"
echo "  This allows unplugging the Pi safely without shutdown."
echo ""
echo "The player will start automatically on next boot."
echo "Reboot now? (y/n)"
read -r response
if [[ "$response" =~ ^[Yy]$ ]]; then
    reboot
fi
