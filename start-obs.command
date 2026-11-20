#!/bin/zsh
# EOS Webcam - start the camera stream and the OBS Virtual Camera (press Cmd+H to hide the OBS window).
cd "$(dirname "$0")"
export PATH="/opt/homebrew/bin:$PATH"
pgrep -f "node eos-webcam.js" >/dev/null || (nohup node eos-webcam.js >/tmp/eos-webcam.log 2>&1 &)
sleep 3
open -a OBS --args --collection "EOS Webcam" --profile "EOS Webcam" --startvirtualcam
