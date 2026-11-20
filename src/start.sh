#!/bin/zsh
# Runs inside EOS Webcam.app: start the script, the camera stream and the virtual camera.
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
cd "$(dirname "$0")"
I=/Applications/Isocast.app/Contents/MacOS/isocast
pgrep -f "node eos-webcam.js" >/dev/null || (nohup node eos-webcam.js >/tmp/eos-webcam.log 2>&1 &)
sleep 3
# If the script was already running but the camera had stopped, start the stream again.
curl -s -m 3 -X POST http://127.0.0.1:8809/api/start >/dev/null
# First run only: load the scene. Fails harmlessly once a setup exists.
"$I" apply setup.toml --revision 0 >/dev/null 2>&1
"$I" engine start >/dev/null 2>&1
"$I" vcam start >/dev/null 2>&1
"$I" refresh canon >/dev/null 2>&1
