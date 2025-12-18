#!/bin/bash
#
# convert_to_sd.sh - Convert videos to SD quality with black & white filter
#
# This script scans a directory for video files (mpeg, mp4, mkv, avi, mov, webm)
# and converts them to 480p black & white MP4 format using ffmpeg. Videos already
# at or below 480p are converted to B&W without rescaling. Existing converted
# files are skipped to avoid duplicate processing.
#
# Output files are saved to the SD_Converted subdirectory.
#

BASE="/home/rajvi/Videos/retroTV"
OUT="$BASE/SD_Converted"

mkdir -p "$OUT"

echo "Scanning for videos to convert to B&W..."
echo ""

# Find all video files
files_to_convert=()
while IFS= read -r -d '' file; do
  files_to_convert+=("$file")
done < <(find "$BASE" -maxdepth 1 -type f \( -iname "*.mpeg" -o -iname "*.mp4" -o -iname "*.mkv" -o -iname "*.avi" -o -iname "*.mov" -o -iname "*.webm" \) -print0 2>/dev/null)

total=${#files_to_convert[@]}

if [ "$total" -eq 0 ]; then
  echo "No videos found."
  exit 0
fi

echo "Found $total video(s) to convert."
echo ""

count=0
for input in "${files_to_convert[@]}"; do
  count=$((count + 1))
  filename=$(basename "$input")
  outname="${filename%.*}.mp4"
  output="$OUT/$outname"

  if [ -f "$output" ]; then
    echo "[$count/$total] Skipping (already exists): $outname"
    continue
  fi

  # Get duration and resolution
  duration=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$input" 2>/dev/null | cut -d'.' -f1)
  duration_fmt=$(printf "%02d:%02d" $((duration/60)) $((duration%60)))
  height=$(ffprobe -v error -select_streams v:0 -show_entries stream=height -of csv=p=0 "$input" 2>/dev/null)

  echo "[$count/$total] Converting: $filename"
  if [ "$height" -gt 480 ]; then
    echo "         Resolution: ${height}p -> 480p B&W"
    vf_opts="scale=-2:480,format=gray"
  else
    echo "         Resolution: ${height}p B&W (keeping original)"
    vf_opts="format=gray"
  fi
  echo "         Duration: $duration_fmt"

  # Run ffmpeg and show progress
  ffmpeg -i "$input" \
    -vf "$vf_opts" \
    -c:v libx264 -crf 23 -preset medium \
    -c:a aac -b:a 128k \
    -y "$output" 2>&1 | while read line; do
      if [[ "$line" =~ time=([0-9]+):([0-9]+):([0-9]+) ]]; then
        hours=${BASH_REMATCH[1]}
        mins=${BASH_REMATCH[2]}
        secs=${BASH_REMATCH[3]}
        current=$((10#$hours*3600 + 10#$mins*60 + 10#$secs))
        if [ "$duration" -gt 0 ]; then
          pct=$((current * 100 / duration))
          current_fmt=$(printf "%02d:%02d" $((current/60)) $((current%60)))
          printf "\r         Progress: %3d%% (%s / %s)" "$pct" "$current_fmt" "$duration_fmt"
        fi
      fi
    done

  echo ""
  if [ -f "$output" ]; then
    size=$(du -h "$output" | cut -f1)
    echo "         Done! Size: $size"
  else
    echo "         FAILED!"
  fi
  echo ""
done

echo "All conversions complete!"
