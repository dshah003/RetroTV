#!/bin/bash
# RetroTV USB Mount Script - Ensures USB is mounted read-write bypassing overlay
# Install to: /usr/local/bin/retrotv-mount.sh
# This script runs as root via systemd ExecStartPre

USB_MOUNT="/media/retroTV"
USB_LABEL="retroTV"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] retrotv-mount: $1"
}

# Wait for USB device to appear (max 60 seconds)
log "Waiting for USB device with label '$USB_LABEL'..."
usb_device=""
for i in {1..60}; do
    usb_device=$(blkid -L "$USB_LABEL" 2>/dev/null)
    if [ -n "$usb_device" ]; then
        log "Found USB device: $usb_device"
        break
    fi
    sleep 1
done

if [ -z "$usb_device" ]; then
    log "ERROR: USB drive with label '$USB_LABEL' not found after 60 seconds"
    exit 1
fi

# Check if overlay filesystem is active
if mount | grep -q "/media/root-ro"; then
    log "Overlay filesystem detected"

    # Unmount any existing overlay mount at USB_MOUNT
    if mountpoint -q "$USB_MOUNT" 2>/dev/null; then
        log "Unmounting overlay mount at $USB_MOUNT"
        umount "$USB_MOUNT" 2>/dev/null || umount -l "$USB_MOUNT" 2>/dev/null
    fi

    # Also unmount from root-ro if mounted there
    if mountpoint -q "/media/root-ro$USB_MOUNT" 2>/dev/null; then
        log "Unmounting from /media/root-ro$USB_MOUNT"
        umount "/media/root-ro$USB_MOUNT" 2>/dev/null || umount -l "/media/root-ro$USB_MOUNT" 2>/dev/null
    fi

    # Create mount point
    mkdir -p "$USB_MOUNT"

    # Mount USB device directly with read-write
    log "Mounting $usb_device directly at $USB_MOUNT"
    if mount -o rw "$usb_device" "$USB_MOUNT"; then
        log "USB mounted successfully (bypassing overlay)"
    else
        log "ERROR: Failed to mount USB device"
        exit 1
    fi

    # Set ownership for the retro-tv user
    chown retro-tv:retro-tv "$USB_MOUNT"
else
    log "No overlay filesystem, using standard mount"
    # Just ensure it's mounted
    if ! mountpoint -q "$USB_MOUNT" 2>/dev/null; then
        mkdir -p "$USB_MOUNT"
        mount "$usb_device" "$USB_MOUNT"
        chown retro-tv:retro-tv "$USB_MOUNT"
    fi
fi

# Verify mount is writable
test_file="$USB_MOUNT/.mount_test_$$"
if echo "test" > "$test_file" 2>/dev/null && rm -f "$test_file" 2>/dev/null; then
    log "USB mount verified writable"
    exit 0
else
    log "ERROR: USB mount is not writable"
    exit 1
fi
