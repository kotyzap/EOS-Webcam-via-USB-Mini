#!/bin/zsh
# EOS Webcam - stop the camera stream, release the camera and shut down Isocast completely.
I=/Applications/Isocast.app/Contents/MacOS/isocast
pkill -INT -f "node eos-webcam.js"
"$I" vcam stop >/dev/null 2>&1
"$I" engine shutdown >/dev/null 2>&1
echo "EOS Webcam and Isocast are shut down."
