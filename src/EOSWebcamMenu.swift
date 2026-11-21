// EOS Webcam - menu bar app: start and stop a Canon camera as a Mac webcam.
// Author: Pavel Kotyza <kotyza@gmail.com> - 4xs.dev
// Built by install.command. The app carries eos-webcam.js, setup.toml and start.sh in Contents/Resources.
import Cocoa
import WebKit

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

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    let status = NSMenuItem(title: "Checking...", action: nil, keyEquivalent: "")
    let battery = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    let api = "http://127.0.0.1:8809"
    // Optional Info.plist key "EOSOpenApp": an app to open, together with the camera, whenever this app is opened.
    let companion = Bundle.main.object(forInfoDictionaryKey: "EOSOpenApp") as? String
    // Picture sliders: title, API key, range in percent (same ranges as eos-webcam.js).
    let adjustments: [(String, String, Double, Double)] = [
        ("Brightness", "brightness", 50, 150), ("Contrast", "contrast", 50, 150), ("Saturation", "saturation", 0, 200)]
    var sliders: [String: (NSSlider, NSTextField, String)] = [:]
    // Picture controls are locked until a licence key is saved (see eos-webcam.js).
    let unlock = NSMenuItem(title: "Unlock picture controls (5 EUR)...", action: #selector(AppDelegate.enterKey), keyEquivalent: "")
    var reset: NSMenuItem?
    var buyURL = "https://ko-fi.com/pavelk"
    let mirror = NSMenuItem(title: "Mirror image", action: #selector(AppDelegate.toggleMirror), keyEquivalent: "")
    // Live preview in the menu: the /view page, the same picture the virtual camera shows. Loaded only while the menu is open.
    // Width of the preview and slider rows; they also stretch to the menu's width (set by its widest line, the battery line).
    static let panel: CGFloat = 340
    let preview = WKWebView(frame: NSRect(x: 18, y: 4, width: AppDelegate.panel - 36, height: (AppDelegate.panel - 36) * 9 / 16))
    // One connection, so slider updates reach the script in order.
    let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpMaximumConnectionsPerHost = 1
        return URLSession(configuration: config)
    }()

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
        menu.addItem(previewItem())
        for (title, key, low, high) in adjustments { addSlider(menu, title, key, low, high) }
        mirror.target = self
        mirror.attributedTitle = dotted("Mirror image", .clear) // lines up with the other items
        menu.addItem(mirror)
        add(menu, "Reset picture", #selector(resetPicture), .clear)
        reset = menu.items.last
        unlock.target = self
        unlock.attributedTitle = dotted("Unlock picture controls (5 EUR)...", .systemBlue)
        menu.addItem(unlock)
        menu.autoenablesItems = false
        menu.addItem(.separator())
        add(menu, "Open preview", #selector(openPreview), .clear)
        add(menu, "Quit EOS Webcam", #selector(quitApp), .clear)
        menu.delegate = self
        item.menu = menu
        show(text: "Checking...", color: .systemGray, battery: nil)
        refresh()
        // .common mode: keeps refreshing while the menu is open, so its sliders follow the preview page.
        RunLoop.main.add(Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.refresh() }, forMode: .common)
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

    // Black card with "Camera is not live" behind the transparent preview, like the virtual camera's card.
    func previewItem() -> NSMenuItem {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: AppDelegate.panel, height: preview.frame.height + 8))
        view.autoresizingMask = [.width]
        let card = NSView(frame: preview.frame)
        card.autoresizingMask = [.width]
        preview.autoresizingMask = [.width]
        card.wantsLayer = true
        card.layer?.backgroundColor = NSColor.black.cgColor
        card.layer?.cornerRadius = 6
        let label = NSTextField(labelWithString: "Camera is not live")
        label.font = .systemFont(ofSize: 11)
        label.textColor = .gray
        label.sizeToFit()
        label.frame.origin = NSPoint(x: (card.frame.width - label.frame.width) / 2, y: (card.frame.height - label.frame.height) / 2)
        label.autoresizingMask = [.minXMargin, .maxXMargin]
        card.addSubview(label)
        preview.setValue(false, forKey: "drawsBackground")
        preview.wantsLayer = true
        preview.layer?.cornerRadius = 6
        preview.layer?.masksToBounds = true
        view.addSubview(card)
        view.addSubview(preview)
        let entry = NSMenuItem()
        entry.view = view
        return entry
    }

    func addSlider(_ menu: NSMenu, _ title: String, _ key: String, _ low: Double, _ high: Double) {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: AppDelegate.panel, height: 42))
        view.autoresizingMask = [.width]
        let label = NSTextField(labelWithString: title)
        label.font = .menuFont(ofSize: 12)
        label.textColor = .secondaryLabelColor
        label.frame = NSRect(x: 20, y: 22, width: AppDelegate.panel - 40, height: 16)
        let slider = NSSlider(value: 100, minValue: low, maxValue: high, target: self, action: #selector(slid(_:)))
        slider.isContinuous = true
        slider.identifier = NSUserInterfaceItemIdentifier(key)
        slider.frame = NSRect(x: 18, y: 2, width: AppDelegate.panel - 36, height: 20)
        slider.autoresizingMask = [.width]
        view.addSubview(label)
        view.addSubview(slider)
        let entry = NSMenuItem()
        entry.view = view
        menu.addItem(entry)
        sliders[key] = (slider, label, title)
    }

    func setSlider(_ key: String, _ value: Double) {
        guard let entry = sliders[key] else { return }
        entry.0.doubleValue = value
        entry.1.stringValue = "\(entry.2)  \(Int(value))%"
    }

    func post(_ path: String) {
        var request = URLRequest(url: URL(string: api + path)!)
        request.httpMethod = "POST"
        session.dataTask(with: request).resume()
    }

    // The menu slider being dragged; refresh() leaves it alone until the mouse is released.
    var tracking: NSSlider?

    @objc func slid(_ slider: NSSlider) {
        guard let key = slider.identifier?.rawValue else { return }
        let released = NSApp.currentEvent?.type == .leftMouseUp
        tracking = released ? nil : slider
        setSlider(key, slider.doubleValue.rounded())
        post("/api/adjust?\(key)=\(Int(slider.doubleValue.rounded()))")
    }

    // Flips the picture left to right, for the preview and the virtual camera.
    @objc func toggleMirror() {
        mirror.state = mirror.state == .on ? .off : .on
        post("/api/adjust?mirror=\(mirror.state == .on ? 1 : 0)")
    }

    @objc func resetPicture() {
        for (_, key, _, _) in adjustments { setSlider(key, 100) }
        post("/api/adjust?brightness=100&contrast=100&saturation=100")
    }

    // Show the current values (they may have been changed on the preview page).
    func menuWillOpen(_ menu: NSMenu) {
        refresh()
        preview.load(URLRequest(url: URL(string: api + "/view")!))
    }

    // Stop the preview when the menu closes, so it does not keep fetching frames.
    func menuDidClose(_ menu: NSMenu) { preview.loadHTMLString("", baseURL: nil) }

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
            var picture: [String: Double] = [:]
            var licensed = true
            var buy: String? = nil
            if let data = data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                licensed = json["licensed"] as? Bool ?? true
                buy = json["buy"] as? String
                for (key, value) in json["adjust"] as? [String: Any] ?? [:] {
                    if let number = value as? NSNumber { picture[key] = number.doubleValue }
                }
                if json["running"] as? Bool == true {
                    color = .systemGreen
                    text = "Camera is live (\(json["fps"] as? Int ?? 0) fps)"
                    level = json["battery"] as? String
                } else {
                    text = "Camera is not live"
                    color = .systemOrange
                }
            }
            // RunLoop instead of DispatchQueue, so the update also runs while the menu is open.
            RunLoop.main.perform(inModes: [.common]) {
                self.show(text: text, color: color, battery: level)
                for (key, value) in picture where self.sliders[key]?.0 !== self.tracking { self.setSlider(key, value) }
                if let value = picture["mirror"] { self.mirror.state = value == 1 ? .on : .off }
                for (slider, _, _) in self.sliders.values { slider.isEnabled = licensed }
                self.mirror.isEnabled = licensed
                self.reset?.isEnabled = licensed
                self.unlock.isHidden = licensed
                if let link = buy { self.buyURL = link }
            }
            CFRunLoopWakeUp(CFRunLoopGetMain())
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

    // Ask for the licence key; "Buy on Ko-fi" opens the shop item.
    @objc func enterKey() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Unlock picture controls"
        alert.informativeText = "Brightness, contrast, saturation and mirror: 5 EUR once on Ko-fi. The licence key arrives by email. Paste it here."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        field.placeholderString = "EW1..."
        alert.accessoryView = field
        alert.addButton(withTitle: "Save key")
        alert.addButton(withTitle: "Buy on Ko-fi")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            var request = URLRequest(url: URL(string: api + "/api/licence")!)
            request.httpMethod = "POST"
            request.httpBody = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).data(using: .utf8)
            URLSession.shared.dataTask(with: request) { _, response, _ in
                let ok = (response as? HTTPURLResponse)?.statusCode == 200
                DispatchQueue.main.async {
                    let done = NSAlert()
                    done.messageText = ok ? "Unlocked. Thank you!" : "This key is not valid (or EOS Webcam is not running)."
                    done.runModal()
                    self.refresh()
                }
            }.resume()
        case .alertSecondButtonReturn:
            if let url = URL(string: buyURL) { NSWorkspace.shared.open(url) }
        default: break
        }
    }

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
