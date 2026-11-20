#!/bin/zsh
# EOS Webcam - start the camera stream and Isocast Virtual Camera (no window).
cd "$(dirname "$0")"
export PATH="/opt/homebrew/bin:$PATH"
I=/Applications/Isocast.app/Contents/MacOS/isocast
pgrep -f "node eos-webcam.js" >/dev/null || (nohup node eos-webcam.js >/tmp/eos-webcam.log 2>&1 &)
sleep 3
"$I" engine start >/dev/null
"$I" vcam start 2>/dev/null
"$I" refresh canon >/dev/null 2>&1
echo "EOS Webcam is running. Choose 'Isocast Virtual Camera' in Zoom or Detail."
