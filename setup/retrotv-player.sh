#!/bin/bash
# RetroTV Player - Continuous random video playback with resume support
# Install to: /usr/local/bin/retrotv-player.sh

# Configuration
USB_MOUNT="/media/retroTV"
STATE_DIR="$USB_MOUNT/.retrotv_state"
PLAYLIST_FILE="$STATE_DIR/playlist.m3u"
POSITION_FILE="$STATE_DIR/current_position"
TIMESTAMP_FILE="$STATE_DIR/last_timestamp"
VIDEO_EXTENSIONS="mp4|mkv|avi|mov|mpg|mpeg|wmv|flv|webm|m4v|3gp"

# Logging
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Wait for USB drive to be mounted (max 60 seconds)
wait_for_usb() {
    log "Waiting for USB drive to mount..."
    for i in {1..60}; do
        if mountpoint -q "$USB_MOUNT" 2>/dev/null; then
            log "USB drive mounted at $USB_MOUNT"
            return 0
        fi
        sleep 1
    done
    log "ERROR: USB drive not mounted after 60 seconds"
    return 1
}

# Create state directory if needed
init_state_dir() {
    if [ ! -d "$STATE_DIR" ]; then
        mkdir -p "$STATE_DIR"
        log "Created state directory: $STATE_DIR"
    fi
}

# Generate a new shuffled playlist
generate_playlist() {
    log "Generating new shuffled playlist..."
    find "$USB_MOUNT" -type f -regextype posix-extended \
        -iregex ".*\.($VIDEO_EXTENSIONS)$" \
        ! -path "$STATE_DIR/*" | shuf > "$PLAYLIST_FILE"

    local count=$(wc -l < "$PLAYLIST_FILE")
    log "Found $count video files"

    # Reset position to start of new playlist
    echo "0" > "$POSITION_FILE"
    echo "0" > "$TIMESTAMP_FILE"
}

# Check if playlist needs regeneration (missing or all videos played)
check_playlist() {
    if [ ! -f "$PLAYLIST_FILE" ]; then
        log "No playlist found"
        return 1
    fi

    local total=$(wc -l < "$PLAYLIST_FILE")
    local current=$(cat "$POSITION_FILE" 2>/dev/null || echo "0")

    if [ "$current" -ge "$total" ]; then
        log "Playlist complete, regenerating..."
        return 1
    fi

    # Verify files still exist
    local valid=0
    while IFS= read -r file; do
        if [ -f "$file" ]; then
            ((valid++))
        fi
    done < "$PLAYLIST_FILE"

    if [ "$valid" -eq 0 ]; then
        log "No valid files in playlist"
        return 1
    fi

    return 0
}

# Get current video from playlist
get_current_video() {
    local pos=$(cat "$POSITION_FILE" 2>/dev/null || echo "0")
    sed -n "$((pos + 1))p" "$PLAYLIST_FILE"
}

# Save current position
save_position() {
    local pos=$1
    echo "$pos" > "$POSITION_FILE"
}

# Save timestamp (called periodically during playback)
save_timestamp() {
    local ts=$1
    echo "$ts" > "$TIMESTAMP_FILE"
}

# Get last saved timestamp
get_timestamp() {
    cat "$TIMESTAMP_FILE" 2>/dev/null || echo "0"
}

# Advance to next video in playlist
next_video() {
    local current=$(cat "$POSITION_FILE" 2>/dev/null || echo "0")
    local next=$((current + 1))
    save_position "$next"
    echo "0" > "$TIMESTAMP_FILE"  # Reset timestamp for new video
    log "Advanced to playlist position $next"
}

# Play a video with VLC
play_video() {
    local video="$1"
    local start_time="$2"

    if [ ! -f "$video" ]; then
        log "Video not found: $video"
        return 1
    fi

    local filename=$(basename "$video")
    log "Playing: $filename (starting at ${start_time}s)"

    # VLC options for retro TV experience
    # --no-video-title-show: Don't show filename overlay
    # --fullscreen: Full screen mode
    # --play-and-exit: Exit when done
    # --start-time: Resume from saved position
    # --no-osd: Disable on-screen display

    local vlc_opts=(
        --fullscreen
        --play-and-exit
        --no-video-title-show
        --no-osd
        --quiet
        --aout=alsa
        --alsa-audio-device=plughw:CARD=vc4hdmi,DEV=0
        --video-on-top
    )

    if [ "$start_time" -gt 0 ]; then
        vlc_opts+=(--start-time="$start_time")
    fi

    # Run VLC and track playback
    # We use a background process to periodically save timestamp
    cvlc "${vlc_opts[@]}" "$video" &
    local vlc_pid=$!

    # Monitor playback and save position every 10 seconds
    local elapsed=$start_time
    while kill -0 $vlc_pid 2>/dev/null; do
        sleep 10
        elapsed=$((elapsed + 10))
        save_timestamp "$elapsed"
    done

    wait $vlc_pid
    local exit_code=$?

    log "Playback finished (exit code: $exit_code)"
    return $exit_code
}

# Main loop
main() {
    log "RetroTV Player starting..."

    # Wait for USB
    if ! wait_for_usb; then
        log "Exiting: USB drive not available"
        exit 1
    fi

    # Initialize state
    init_state_dir

    # Check/generate playlist
    if ! check_playlist; then
        generate_playlist
    fi

    log "Starting continuous playback..."

    # Continuous playback loop
    while true; do
        # Check if we've reached end of playlist
        if ! check_playlist; then
            generate_playlist
        fi

        # Get current video
        local video=$(get_current_video)

        if [ -z "$video" ] || [ ! -f "$video" ]; then
            log "Skipping invalid entry, moving to next..."
            next_video
            continue
        fi

        # Get resume timestamp
        local timestamp=$(get_timestamp)

        # Play the video
        play_video "$video" "$timestamp"

        # Move to next video in playlist
        next_video

        # Small delay between videos (simulates channel change)
        sleep 1
    done
}

# Handle graceful shutdown
cleanup() {
    log "Shutting down RetroTV Player..."
    # Kill any running VLC instance
    pkill -f "vlc.*$USB_MOUNT" 2>/dev/null
    exit 0
}

trap cleanup SIGTERM SIGINT SIGHUP

# Run main
main
