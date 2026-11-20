#!/bin/zsh
# EOS Webcam installer - the only file you need to run.
# Installs what is missing (Node, gphoto2, Isocast), builds "EOS Webcam.app" into Applications and opens it.
# Needs Homebrew (https://brew.sh) on a Mac with Apple silicon, macOS 14 or later.
cd "$(dirname "$0")" 2>/dev/null
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

# Run on its own (without the rest of the repository), it fetches the sources first.
if [ ! -f src/EOSWebcamMenu.swift ]; then
  T=$(mktemp -d)
  echo "Downloading EOS Webcam sources..."
  curl -fsSL https://github.com/kotyzap/EOS-Webcam-via-USB-Mini/archive/refs/heads/main.tar.gz | tar xz -C "$T" || { echo "Download failed."; exit 1; }
  cd "$T/EOS-Webcam-via-USB-Mini-main" || exit 1
fi

command -v brew >/dev/null || { echo "Install Homebrew first: https://brew.sh"; exit 1; }
command -v node >/dev/null || brew install node
command -v gphoto2 >/dev/null || brew install gphoto2

# Virtual camera engine: Isocast, checked against the checksum of the tested release.
if [ ! -d /Applications/Isocast.app ]; then
  V=0.0.10; F="Isocast-$V-arm64.dmg"
  curl -L -o "/tmp/$F" "https://github.com/anomalyco/isocast/releases/download/v$V/$F" || exit 1
  echo "300b4649bbdf98be2c7c9a85f3dcf6b92c02e94c5996d1db11c2587caa368402  /tmp/$F" | shasum -a 256 -c || { echo "Download does not match the expected checksum."; exit 1; }
  M=$(hdiutil attach "/tmp/$F" -nobrowse -readonly | tail -1 | cut -f3)
  cp -R "$M/Isocast.app" /Applications/ && hdiutil detach "$M" -quiet
fi

# Build the menu bar app on this Mac, so macOS does not block it as a downloaded app.
A="/Applications/EOS Webcam.app"
pkill -x EOSWebcam 2>/dev/null
rm -rf "$A" && mkdir -p "$A/Contents/MacOS" "$A/Contents/Resources"
swiftc -O -o "$A/Contents/MacOS/EOSWebcam" src/EOSWebcamMenu.swift || { echo "Build failed. Install the tools with: xcode-select --install"; exit 1; }
cp src/Info.plist "$A/Contents/Info.plist"
cp src/icon.icns src/eos-webcam.js src/setup.toml src/start.sh "$A/Contents/Resources/"
chmod +x "$A/Contents/Resources/start.sh"
codesign --force -s - "$A" 2>/dev/null
touch "$A" # make Finder pick up the icon
open "$A"
echo "Done. EOS Webcam is in Applications and in the menu bar (camera icon). Choose Start camera there."
