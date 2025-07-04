#!/usr/bin/env bash
# Enable strict mode: exit on error, unset var, or pipeline failure
set -euo pipefail
# Set safe IFS to newline and tab to avoid word-splitting
IFS=$'\n\t'

########################################
# Load configuration from .env file    #
########################################

ENV_FILE="$(dirname "$0")/.env"
if [[ ! -f "$ENV_FILE" ]]; then
  echo "Error: .env file not found at $ENV_FILE" >&2
  exit 1
fi
# shellcheck source=/dev/null
source "$ENV_FILE"

########################################
# Utility Functions                    #
########################################

# Log with ISO8601 timestamp
log() {
  printf '[%s] %s\n' "$(date +'%Y-%m-%dT%H:%M:%S%z')" "$*"
}

# Create a temporary file for the snapshot (global, so cleanup always works)
tmpfile="$(mktemp --suffix=.jpg)"

# Clean up temporary files on exit
cleanup() {
  # Only remove if tmpfile is set and not empty
  if [[ -n "${tmpfile:-}" && -f "$tmpfile" ]]; then
    rm -f "$tmpfile"
    log "Temporary files removed."
  fi
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
  log "Capturing snapshot from RTSP stream."
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
  log "Uploading snapshot to PrusaConnect."
  # Use correct MIME type for JPEG
  curl --fail -X PUT "$prusaconnect_url" \
    -H "Accept: */*" \
    -H "Content-Type: image/jpeg" \
    -H "fingerprint: $fingerprint" \
    -H "token: $token" \
    --data-binary "@$tmpfile" \
    --no-progress-meter
}

########################################
# Main Loop                            #
########################################

main_loop() {
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
          log "Upload failed; will retry after ${error_delay}s."
          delay=$error_delay
        fi
      else
        log "ffmpeg failed to capture; will retry after ${error_delay}s."
        delay=$error_delay
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