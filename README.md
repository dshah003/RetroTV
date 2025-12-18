# RetroTV Player

A Raspberry Pi-based media player that simulates vintage television viewing. Automatically plays random videos from a USB drive on boot, with resume support.

## Hardware Setup

```
Raspberry Pi 3 → HDMI → HDMI-to-RF Modulator → Coaxial → TV Antenna Input
```

### Requirements

- Raspberry Pi 3 (or newer)
- 8GB+ SD card with Raspbian
- USB flash drive (labeled "retroTV")
- HDMI-to-RF modulator (for vintage TVs with antenna input)

## Installation

### 1. Prepare the USB Drive

Label your USB drive as "retroTV":

```bash
# Find your USB device
lsblk

# Label it (replace sdX1 with your device)
sudo fatlabel /dev/sdX1 retroTV    # For FAT32
sudo e2label /dev/sdX1 retroTV     # For ext4
```

Add your video files to the drive. Supported formats:
- mp4, mkv, avi, mov, mpg, mpeg, wmv, flv, webm, m4v, 3gp

### 2. Copy Setup Files to Pi

From your computer:

```bash
scp -r setup/ pi@<PI_IP_ADDRESS>:~/
```

### 3. Run the Installer

SSH into your Pi and run:

```bash
ssh pi@<PI_IP_ADDRESS>
cd ~/setup
sudo bash install.sh
```

The installer will:
- Install VLC if not present
- Set up USB automount rules
- Install the player script
- Enable auto-start on boot

### 4. Reboot

```bash
sudo reboot
```

The player will start automatically once the Pi boots and detects the USB drive.

## Usage

### Service Commands

```bash
# Start the player
sudo systemctl start retrotv

# Stop the player
sudo systemctl stop retrotv

# Check status
sudo systemctl status retrotv

# View live logs
journalctl -u retrotv -f

# Disable auto-start on boot
sudo systemctl disable retrotv

# Re-enable auto-start on boot
sudo systemctl enable retrotv
```

### Playlist Management

State files are stored on the USB drive at `.retrotv_state/`:

```bash
# Reset playlist (generate new shuffle order)
rm /media/retroTV/.retrotv_state/playlist.m3u
sudo systemctl restart retrotv

# Start from beginning of current playlist
echo "0" > /media/retroTV/.retrotv_state/current_position
echo "0" > /media/retroTV/.retrotv_state/last_timestamp
sudo systemctl restart retrotv

# View current playlist
cat /media/retroTV/.retrotv_state/playlist.m3u

# See which video is current
cat /media/retroTV/.retrotv_state/current_position
```

## How It Works

1. **Boot**: systemd starts the retrotv service after the graphical environment loads
2. **USB Detection**: Waits up to 60 seconds for the "retroTV" labeled drive to mount
3. **Playlist Generation**: On first run (or when playlist is exhausted), scans all video files and creates a shuffled playlist
4. **Playback**: Plays videos sequentially using VLC in fullscreen mode
5. **Resume Support**: Saves playback position every 10 seconds to handle unexpected shutdowns
6. **Loop**: When playlist ends, generates a new shuffled playlist and continues

## File Structure

```
/media/retroTV/                    # USB drive mount point
├── .retrotv_state/                # State directory (auto-created)
│   ├── playlist.m3u               # Shuffled playlist
│   ├── current_position           # Current index in playlist
│   └── last_timestamp             # Playback position for resume
├── cartoons/                      # Your video folders
├── commercials/
└── ...

/usr/local/bin/retrotv-player.sh   # Main player script
/etc/systemd/system/retrotv.service # Systemd service
/etc/udev/rules.d/99-retrotv-usb.rules # USB automount rule
```

## Troubleshooting

### Player won't start

```bash
# Check if USB is mounted
mountpoint /media/retroTV

# Check service status
sudo systemctl status retrotv

# View detailed logs
journalctl -u retrotv -n 50
```

### Permission denied error

If you see `Permission denied` in the logs:

```bash
# Fix script permissions (needs read + execute)
sudo chmod 755 /usr/local/bin/retrotv-player.sh
```

### USB drive not detected

```bash
# Check if drive is recognized
lsblk -o NAME,SIZE,LABEL,MOUNTPOINT

# Check drive label
sudo blkid

# Manually mount to test
sudo mount /dev/sdX1 /media/retroTV
```

### Cannot create state files on USB

For ext4 formatted drives, set ownership:

```bash
sudo chown -R $(whoami):$(whoami) /media/retroTV
```

### No video output

```bash
# Test VLC manually
DISPLAY=:0 XDG_RUNTIME_DIR=/run/user/1000 cvlc --fullscreen --play-and-exit /media/retroTV/somevideo.mp4

# Check if X is running
echo $DISPLAY
```

### No audio output

Audio device order can change between boots. The player uses the HDMI device by name to avoid this issue.

```bash
# Check available audio devices
aplay -l

# Test HDMI audio directly
speaker-test -D plughw:CARD=vc4hdmi,DEV=0 -c 2

# If HDMI is not card 0, that's fine - the player uses the card name
```

### Videos skip or stutter

- Ensure videos are encoded with H.264 codec
- Keep resolution at 720p or lower for Pi 3
- Convert problematic files:
  ```bash
  ffmpeg -i input.mp4 -c:v libx264 -preset fast -crf 22 -c:a aac output.mp4
  ```

## Safe Power-Off (Recommended)

Since the Pi runs headless without a keyboard, enable the overlay filesystem to safely unplug it anytime:

```bash
sudo raspi-config
```

Navigate to: `Performance Options` → `Overlay File System`
- Enable overlay filesystem: **Yes**
- Write-protect boot partition: **Yes**

Reboot. Now you can safely unplug the Pi without risking SD card corruption.

**Note:** With overlay enabled, system changes don't persist. To make configuration changes:
1. Disable overlay via raspi-config
2. Reboot, make changes
3. Re-enable overlay and reboot

Video playback state is stored on the USB drive, so resume functionality works regardless of overlay status.

## Adding New Videos

Simply copy new video files to the USB drive. To include them in playback:

```bash
# Delete the playlist to trigger regeneration
rm /media/retroTV/.retrotv_state/playlist.m3u
sudo systemctl restart retrotv
```

Or wait until the current playlist completes—it will automatically reshuffle with the new files.

## Uninstallation

```bash
sudo systemctl stop retrotv
sudo systemctl disable retrotv
sudo rm /etc/systemd/system/retrotv.service
sudo rm /usr/local/bin/retrotv-player.sh
sudo rm /etc/udev/rules.d/99-retrotv-usb.rules
sudo systemctl daemon-reload
```

## License

This project is for personal use with public domain content.
