<p align="center">
  <img src="docs/img/icon.png" width="128" height="128" alt="EOS Webcam icon">
</p>

<h1 align="center">EOS Webcam</h1>

<p align="center">
  Use a Canon EOS 80D as a Mac webcam over the normal USB cable, without Canon's app.<br>
  <a href="https://kotyzap.github.io/eos-webcam/"><b>Explainer with interactive diagram</b></a>
</p>

---

Canon's EOS Webcam Utility freezes on macOS 26. This project replaces it with one small Node script and a free virtual camera, so the camera shows up in Zoom, Meet or Detail like any other webcam. No window stays open while it runs.

| | |
|---|---|
| Source picture | 960×640 at about 15 fps (the camera's USB live view) |
| Virtual camera | 1280×720 at 30 fps, named **Isocast Virtual Camera** |
| CPU | about 1% for the Isocast engine on a Mac mini |
| Tested with | EOS 80D, Mac mini (Apple silicon), macOS 26.5 |

## How it works

![Workflow: camera over USB, gphoto2, eos-webcam.js, Isocast, call apps](docs/img/workflow.png)

1. **gphoto2** reads the camera's live view over USB as a stream of JPEG frames.
2. **eos-webcam.js** splits that stream into frames and serves the newest one on `http://127.0.0.1:8809`.
3. **[Isocast](https://github.com/anomalyco/isocast)** renders the script's bare `/view` page as a web page source and feeds it to its signed virtual camera.
4. When no frame arrives (camera stopped, off or unplugged), a **"Camera is not live"** card shows instead of a frozen picture.

macOS only lists a camera in call apps when a signed camera extension provides it, and writing your own needs a paid Apple Developer account. Borrowing Isocast's extension is what keeps this free.

## Requirements

- Mac with Apple silicon, macOS 14 or later
- [Homebrew](https://brew.sh)
- A Canon camera that gphoto2 can read live view from, and its USB cable

`install.command` adds Node, gphoto2 and Isocast 0.0.10 if they are missing. Isocast is downloaded from its GitHub release and checked against a known checksum.

## Install

1. Download this repository (**Code > Download ZIP**) and unzip it anywhere, or `git clone` it.
2. Double-click `install.command`. If macOS refuses to open it, right-click it and choose **Open**.
3. Connect the camera by USB, switch it on in movie mode and set **Auto power off** to **Disable**.
4. Double-click `start.command`.
5. First time only: allow **Isocast Virtual Camera** in System Settings > General > Login Items & Extensions > Camera Extensions.
6. Choose **Isocast Virtual Camera** as the camera in your call app.

## Daily use

| File | What it does |
|---|---|
| `start.command` | Starts the camera stream and the virtual camera. |
| `stop.command` | Stops the stream and frees the camera for other apps. Call apps then show "Camera is not live". |
| `quit.command` | Stops the stream and shuts Isocast down completely. |

A preview with Start and Stop buttons is at `http://127.0.0.1:8809` while the script runs.

## Troubleshooting

- **No picture, only the "Camera is not live" card.** The camera is off, asleep or held by another program. Close EOS Utility, Cascable and similar apps, then run `start.command` again.
- **The camera switches off mid-call.** Set Auto power off to Disable and use a dummy-battery AC adapter for long sessions.
- **"Isocast Virtual Camera" is missing from the app's camera list.** Approve the extension in System Settings (step 5), then restart the call app.
- **To change the card text,** edit `text = "Camera is not live"` in `isocast/setup.toml` and re-apply the setup (see `isocast apply --help` for the revision argument).

## Limits

- The picture is the camera's USB live view: 960×640 at about 15 fps, cropped to 16:9 and scaled to 720p. For full 1080p, use the camera's Mini-HDMI output with an HDMI capture dongle instead; that needs no software at all.
- Isocast is alpha software and cannot open a network stream directly yet, which is why the script serves the `/view` page for it.
- `install.command` has not been tested on a second Mac yet.

## OBS fallback

If Isocast breaks after an update, the earlier OBS route is included: run `install-obs.command` once (with OBS closed), then use `start-obs.command` and `stop-obs.command`. The camera is then named **OBS Virtual Camera**.

## What's in the repo

| Path | Purpose |
|---|---|
| `eos-webcam.js` | The Node script, no dependencies. Endpoints: `/` preview, `/view`, `/frame`, `/stream`, `/api/start`, `/api/stop`, `/api/status`. |
| `isocast/setup.toml` | Isocast scene: the `/view` page over the text card, sent to the virtual camera. |
| `obs/` | OBS scene collection and profile for the fallback route. |
| `docs/` | The explainer page served by GitHub Pages. |

## Licence

MIT, see [`LICENSE`](LICENSE). Built by Pavel Kotyza &lt;kotyza@gmail.com&gt;, [4xs.dev](https://www.4xs.dev).

Not affiliated with Canon. Uses [gphoto2](http://www.gphoto.org) and [Isocast](https://github.com/anomalyco/isocast), both open source.
