#!/bin/zsh
# EOS Webcam - stop the camera stream and release the camera.
# Isocast keeps running and shows "Camera is not live". Use quit.command to shut it down too.
pkill -INT -f "node eos-webcam.js"
echo "Camera stopped. Apps now see: Camera is not live."
