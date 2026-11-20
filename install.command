#!/bin/zsh
# EOS Webcam - one-time setup on a Mac (Apple silicon, macOS 14+, Homebrew required).
cd "$(dirname "$0")"
export PATH="/opt/homebrew/bin:$PATH"
command -v brew >/dev/null || { echo "Install Homebrew first: https://brew.sh"; exit 1; }
command -v node >/dev/null || brew install node
command -v gphoto2 >/dev/null || brew install gphoto2
if [ ! -d /Applications/Isocast.app ]; then
  V=0.0.10; F="Isocast-$V-arm64.dmg"
  curl -L -o "/tmp/$F" "https://github.com/anomalyco/isocast/releases/download/v$V/$F" || exit 1
  echo "300b4649bbdf98be2c7c9a85f3dcf6b92c02e94c5996d1db11c2587caa368402  /tmp/$F" | shasum -a 256 -c || { echo "Download does not match the expected checksum."; exit 1; }
  M=$(hdiutil attach "/tmp/$F" -nobrowse -readonly | tail -1 | cut -f3)
  cp -R "$M/Isocast.app" /Applications/ && hdiutil detach "$M" -quiet
fi
/Applications/Isocast.app/Contents/MacOS/isocast apply vcam/setup.toml --revision 0 || echo "The virtual camera already has a setup, so it was not replaced."
echo "Done. Now double-click start.command"
