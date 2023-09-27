#!/bin/bash

# Camera
camera_ip=address
camera_rtsp_url=rtsp://username:password@address/stream1

# Your PrusaConnect info
token=token
fingerprint=fingerprint

# Delays (in seconds)
snapshot_delay=10
ffmpeg_error_delay=60
unreachable_delay=300

# PrusaConnect URL
prusaconnect_url=https://webcam.connect.prusa3d.com/c/snapshot

while true; do

    IP=$camera_ip
    COUNT=1

    if
        ping -c $COUNT $IP >/dev/null 2>&1
    then
        echo -e "Camera is reachable. Capturing image using FFmpeg... \n"
        # Capture a frame from the RTSP stream using FFmpeg
        ffmpeg -loglevel quiet -stats -y -rtsp_transport tcp -i "$camera_rtsp_url" -frames:v 1 -q:v 6 -pix_fmt yuv420p -vf scale="1920:-1" printer_snapshot.jpg
        echo -e "Done. \n"

        # If no error then upload it
        if [ $? -eq 0 ]; then
            echo -e "Uploading to PrusaConnect... \n"
            # POST the image to the HTTP URL using curl
            curl -X PUT "$prusaconnect_url" -H "accept: */*" -H "content-type: image/jpg" -H "fingerprint: $fingerprint" -H "token: $token" --data-binary "@printer_snapshot.jpg" --no-progress-meter --compressed
            echo -e "Done. \n"
            # Reset delay to the normal value
            delay=$snapshot_delay
        else
            echo -e "FFmpeg returned an error. Retrying after ${ffmpeg_error_delay}s... \n"

            # Set delay to the longer value
            delay=$ffmpeg_error_delay
        fi
        echo -e "Waiting for $delay seconds before taking another snapshot. \n"
        sleep "$delay"

    else
        echo -e "Camera is unreachable. Waiting $unreachable_delay seconds before another attempt. \n"
        sleep "$unreachable_delay"
    fi

done
