#!/bin/zsh
# EOS Webcam - one-time setup on a Mac (Apple silicon, Homebrew required).
cd "$(dirname "$0")"
export PATH="/opt/homebrew/bin:$PATH"
command -v brew >/dev/null || { echo "Install Homebrew first: https://brew.sh"; exit 1; }
command -v node >/dev/null || brew install node
command -v gphoto2 >/dev/null || brew install gphoto2
[ -d /Applications/OBS.app ] || brew install --cask obs
O="$HOME/Library/Application Support/obs-studio/basic"
mkdir -p "$O/scenes" "$O/profiles/EOS_Webcam"
cp -n obs/EOS_Webcam.json "$O/scenes/"
cp -n obs/basic.ini "$O/profiles/EOS_Webcam/"
# Let stop.command quit OBS without a confirmation dialog (OBS must be closed while this runs).
U="$HOME/Library/Application Support/obs-studio/user.ini"
if grep -q '^ConfirmOnExit=' "$U" 2>/dev/null; then sed -i '' 's/^ConfirmOnExit=.*/ConfirmOnExit=false/' "$U"
elif [ ! -f "$U" ]; then printf '[General]\nConfirmOnExit=false\n' > "$U"; fi
echo "Done. Now double-click start.command"
