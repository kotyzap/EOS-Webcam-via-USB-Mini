// EOS Webcam - menu bar app: start and stop a Canon camera as a Mac webcam.
// Author: Pavel Kotyza <kotyza@gmail.com> - 4xs.dev
// Built by install.command. The app carries eos-webcam.js, setup.toml and start.sh in Contents/Resources.
import Cocoa

func circle(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) -> NSRect {
    NSRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r)
}

// The app icon drawn small, with the lens in the status colour.
// Coordinates follow the app icon artwork (1024 x 1024, y down).
func cameraIcon(lens: NSColor, points: CGFloat = 18) -> NSImage {
    let image = NSImage(size: NSSize(width: points, height: points), flipped: true) { _ in
        guard let context = NSGraphicsContext.current?.cgContext else { return false }
        let scale = points / 864
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -80, y: -80)
        func fill(_ color: NSColor, _ path: NSBezierPath) { color.setFill(); path.fill() }
        let body = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 186, yRadius: 186)
        fill(NSColor(white: 0.95, alpha: 1), body)
        NSColor(white: 0.55, alpha: 1).setStroke()
        body.lineWidth = 30
        body.stroke()
        fill(NSColor(red: 0.90, green: 0.22, blue: 0.17, alpha: 1), NSBezierPath(ovalIn: circle(232, 232, 40)))
        fill(NSColor(white: 0.72, alpha: 1), NSBezierPath(roundedRect: NSRect(x: 690, y: 202, width: 118, height: 60), xRadius: 18, yRadius: 18))
        fill(NSColor(white: 0.16, alpha: 1), NSBezierPath(ovalIn: circle(512, 548, 262)))
        fill(lens, NSBezierPath(ovalIn: circle(512, 548, 200)))
        fill(NSColor(white: 0.03, alpha: 1), NSBezierPath(ovalIn: circle(512, 548, 78)))
        fill(NSColor(white: 1, alpha: 0.45), NSBezierPath(ovalIn: NSRect(x: 390, y: 425, width: 110, height: 76)))
        return true
    }
    image.isTemplate = false
    return image
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    let status = NSMenuItem(title: "Checking...", action: nil, keyEquivalent: "")
    let battery = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    let api = "http://127.0.0.1:8809"
    // Optional Info.plist key "EOSOpenApp": an app to open, together with the camera, whenever this app is opened.
    let companion = Bundle.main.object(forInfoDictionaryKey: "EOSOpenApp") as? String

    func applicationDidFinishLaunching(_ notification: Notification) {
        let menu = NSMenu()
        menu.addItem(status)
        battery.isHidden = true
        menu.addItem(battery)
        menu.addItem(.separator())
        // The dot on each action is the lens colour you get after choosing it.
        add(menu, "Start camera", #selector(startCamera), .systemGreen)
        add(menu, "Stop camera", #selector(stopCamera), .systemOrange)
        add(menu, "Turn off", #selector(turnOff), .systemRed)
        menu.addItem(.separator())
        add(menu, "Open preview", #selector(openPreview), .clear)
        add(menu, "Quit EOS Webcam", #selector(quitApp), .clear)
        item.menu = menu
        show(text: "Checking...", color: .systemGray, battery: nil)
        refresh()
        Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in self?.refresh() }
        openCompanion()
    }

    func openCompanion() {
        guard let name = companion else { return }
        startCamera()
        run("/usr/bin/open", ["-a", name])
    }

    // Clicking the app again (for example in the Dock) while it is running.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openCompanion()
        return false
    }

    func dotted(_ text: String, _ color: NSColor) -> NSAttributedString {
        let line = NSMutableAttributedString(string: "\u{25CF}", attributes: [.foregroundColor: color])
        line.append(NSAttributedString(string: "  " + text))
        return line
    }

    func add(_ menu: NSMenu, _ title: String, _ action: Selector, _ color: NSColor) {
        let entry = NSMenuItem(title: title, action: action, keyEquivalent: "")
        entry.attributedTitle = dotted(title, color)
        entry.target = self
        menu.addItem(entry)
    }

    func run(_ tool: String, _ arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }

    // Lens colour: green = live, orange = script running but no picture, red = off.
    func show(text: String, color: NSColor, battery level: String?) {
        let image = cameraIcon(lens: color)
        image.accessibilityDescription = text
        item.button?.image = image
        status.attributedTitle = dotted(text, color)
        battery.isHidden = level == nil
        battery.title = "Camera battery: \(level ?? "") (read when the stream started)"
    }

    // Ask the script on port 8809 whether the camera is streaming.
    func refresh() {
        var request = URLRequest(url: URL(string: api + "/api/status")!)
        request.timeoutInterval = 2
        URLSession.shared.dataTask(with: request) { data, _, _ in
            var text = "Camera is off", color = NSColor.systemRed
            var level: String? = nil
            if let data = data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if json["running"] as? Bool == true {
                    color = .systemGreen
                    text = "Camera is live (\(json["fps"] as? Int ?? 0) fps)"
                    level = json["battery"] as? String
                } else {
                    text = "Camera is not live"
                    color = .systemOrange
                }
            }
            DispatchQueue.main.async { self.show(text: text, color: color, battery: level) }
        }.resume()
    }

    // Start: script, camera stream and virtual camera (see start.sh).
    @objc func startCamera() {
        run("/bin/zsh", [Bundle.main.resourceURL!.appendingPathComponent("start.sh").path])
    }

    // Stop: release the camera but keep the script, so the preview page stays available.
    @objc func stopCamera() {
        var request = URLRequest(url: URL(string: api + "/api/stop")!)
        request.httpMethod = "POST"
        URLSession.shared.dataTask(with: request).resume()
    }

    // Turn off: end the script. The virtual camera keeps running and shows the "not live" card.
    @objc func turnOff() { run("/usr/bin/pkill", ["-INT", "-f", "node eos-webcam.js"]) }

    @objc func openPreview() { NSWorkspace.shared.open(URL(string: api)!) }

    @objc func quitApp() {
        turnOff()
        NSApp.terminate(nil)
    }
}

// "EOSWebcam --icons FOLDER" writes the three status icons as PNG files and exits (used to check the drawing).
if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--icons" {
    for (name, color) in [("live", NSColor.systemGreen), ("not-live", NSColor.systemOrange), ("off", NSColor.systemRed)] {
        let tiff = cameraIcon(lens: color, points: 144).tiffRepresentation!
        let png = NSBitmapImageRep(data: tiff)!.representation(using: .png, properties: [:])!
        try! png.write(to: URL(fileURLWithPath: CommandLine.arguments[2]).appendingPathComponent("menubar-\(name).png"))
    }
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
