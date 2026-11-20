#!/bin/zsh
# EOS Webcam - stop the camera stream, release the camera and quit OBS.
pkill -INT -f "node eos-webcam.js"
osascript -e 'quit app "OBS"' 2>/dev/null
