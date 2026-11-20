# EOS Webcam

Canon EOS 80D as a webcam on macOS over the normal USB cable, without Canon's app.
Author: Pavel Kotyza <kotyza@gmail.com> - 4xs.dev. Not affiliated with Canon.

Explainer with an interactive diagram: https://kotyzap.github.io/eos-webcam/

## How it works

    80D --USB--> gphoto2 --> eos-webcam.js (http://127.0.0.1:8809) --> Isocast web page source (/view) --> Isocast Virtual Camera --> Zoom / Detail

## Setup on a new Mac (Apple silicon, macOS 14+, Homebrew installed)

1. Download this repository (Code > Download ZIP) and unzip it anywhere, or `git clone` it.
2. Double-click `install.command` (installs node and gphoto2 if missing, downloads Isocast 0.0.10 and loads `isocast/setup.toml`).
3. Double-click `start.command`.
4. First time only: allow "Isocast Virtual Camera" in System Settings > General > Login Items & Extensions > Camera Extensions.
5. In Zoom or Detail choose the camera "Isocast Virtual Camera".

If macOS refuses to open a .command file, right-click it and choose Open.

## Daily use

- `start.command` - starts the stream and the Isocast virtual camera. No window opens.
- `stop.command` - stops the stream and frees the camera for other apps. Zoom and Detail then show "Camera is not live".
- `quit.command` - the same, and shuts down Isocast completely.
- Preview, if wanted: http://127.0.0.1:8809
- Camera: on, movie mode, Auto power off disabled, EOS Utility / Cascable closed.

## OBS fallback

Isocast is alpha software. If it breaks, the earlier OBS route still works:
`install-obs.command` once, then `start-obs.command` / `stop-obs.command`, camera "OBS Virtual Camera".
OBS must be closed while `install-obs.command` runs.

## Limits

- 960x640 at about 15 fps (the 80D's USB live view), cropped to 16:9 and scaled to 1280x720.
- Isocast cannot open the stream directly, so it renders the script's `/view` page as a web page source.
- Tested with an EOS 80D on a Mac mini, macOS 26.5. `install.command` has not been tested on a second Mac yet.

## Licence

MIT, see `LICENSE`.
