#!/usr/bin/env bash
# Enable strict mode: exit on error, unset var, or pipeline failure
set -euo pipefail
# Set safe IFS to newline and tab to avoid word-splitting surprises
IFS=$'\n\t'

########################################
# Configuration (customize as needed)  #
########################################

# IP or hostname of your camera
camera_ip="address"

# RTSP URL for your camera stream (uses camera_ip)
camera_rtsp_url="rtsp://username:password@${camera_ip}/stream1"

# PrusaConnect API endpoint for snapshots
prusaconnect_url="https://webcam.connect.prusa3d.com/c/snapshot"

# Authentication tokens for PrusaConnect
token="your_token_here"
fingerprint="your_fingerprint_here"

# Delay settings (in seconds)
snapshot_delay=10        # wait after a successful upload
ffmpeg_error_delay=60    # wait after an ffmpeg capture error
unreachable_delay=300    # wait if camera is offline

########################################
# Utility Functions                    #
########################################

# Log with ISO8601 timestamp
log() {
  printf '[%s] %s\n' "$(date +'%Y-%m-%dT%H:%M:%S%z')" "$*"
}

# Clean up temporary files on exit
cleanup() {
  rm -f "$tmpfile"
  log "Cleaned up temporary files. Exiting."
}
trap cleanup EXIT

# Check that required commands exist before proceeding
require_commands() {
  local cmd
  for cmd in ping ffmpeg curl; do
    if ! command -v "$cmd" &>/dev/null; then
      echo "Error: Required command '$cmd' not found." >&2
      exit 1
    fi
  done
}

# Capture a single frame from the RTSP stream
capture_snapshot() {
  log "Starting ffmpeg snapshot capture..."
  # ffmpeg: quiet except errors, TCP transport, single frame, quality 6
  ffmpeg -loglevel error -y \
    -rtsp_transport tcp \
    -i "$camera_rtsp_url" \
    -frames:v 1 \
    -q:v 6 \
    -pix_fmt yuv420p \
    -vf scale=1920:-1 \
    "$tmpfile"
}

# Upload the snapshot to PrusaConnect
upload_snapshot() {
  log "Uploading snapshot to PrusaConnect..."
  # curl --fail: returns non-zero on HTTP errors (>=400)
  curl --fail -X PUT "$prusaconnect_url" \
    -H "Accept: */*" \
    -H "Content-Type: image/jpg" \
    -H "fingerprint: $fingerprint" \
    -H "token: $token" \
    --data-binary "@$tmpfile" \
    --no-progress-meter
}

########################################
# Main Loop                            #
########################################

main_loop() {
  # Create a temporary file for the snapshot
  tmpfile="$(mktemp --suffix=.jpg)"
  log "Temporary snapshot file: $tmpfile"

  # Infinite loop to poll and upload
  while true; do
    # Check if camera is reachable
    if ping -c1 "$camera_ip" &>/dev/null; then
      log "Camera at $camera_ip is reachable."

      # Attempt to capture a snapshot
      if capture_snapshot; then
        log "Snapshot captured successfully."
        # Attempt to upload
        if upload_snapshot; then
          log "Upload succeeded."
          delay=$snapshot_delay
        else
          log "Upload failed; will retry after ${ffmpeg_error_delay}s."
          delay=$ffmpeg_error_delay
        fi
      else
        log "ffmpeg failed to capture; will retry after ${ffmpeg_error_delay}s."
        delay=$ffmpeg_error_delay
      fi
    else
      log "Camera unreachable; waiting ${unreachable_delay}s before retry."
      delay=$unreachable_delay
    fi

    # Wait before next iteration
    log "Sleeping for ${delay}s..."
    sleep "$delay"
  done
}

# Entrypoint: verify dependencies, then start main loop
require_commands
main_loop
