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

final class FlippedView: NSView {
    override var isFlipped: Bool { true }
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
    // Picture controls: one boxed menu row with the sliders, Mirror and Reset. Locked until a licence key
    // is saved (see eos-webcam.js); then the box is grey and starts with the Unlock line.
    let picture = NSMenuItem()
    let pictureView = FlippedView()
    let box = NSBox()
    let unlock = NSButton(title: "", target: nil, action: nil)
    let mirror = NSButton(checkboxWithTitle: "Mirror image", target: nil, action: nil)
    let reset = NSButton(title: "Reset", target: nil, action: nil)
    var licensed: Bool?
    var buyURL = "https://ko-fi.com/pavelk"
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
        menu.addItem(pictureItem())
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

    func pictureItem() -> NSMenuItem {
        pictureView.frame = NSRect(x: 0, y: 0, width: AppDelegate.panel, height: 200)
        pictureView.autoresizingMask = [.width]
        box.boxType = .custom
        box.titlePosition = .noTitle
        box.cornerRadius = 8
        box.borderWidth = 1
        box.borderColor = .separatorColor
        box.autoresizingMask = [.width]
        pictureView.addSubview(box)
        unlock.isBordered = false
        unlock.image = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: "Locked")
        unlock.imagePosition = .imageLeading
        unlock.contentTintColor = .controlAccentColor
        unlock.alignment = .left
        unlock.attributedTitle = NSAttributedString(string: " Unlock picture controls (5 EUR)...",
            attributes: [.foregroundColor: NSColor.controlAccentColor, .font: NSFont.menuFont(ofSize: 13)])
        unlock.target = self
        unlock.action = #selector(enterKey)
        unlock.autoresizingMask = [.width]
        pictureView.addSubview(unlock)
        for (title, key, low, high) in adjustments {
            let label = NSTextField(labelWithString: title)
            label.font = .menuFont(ofSize: 12)
            label.autoresizingMask = [.width]
            let slider = NSSlider(value: 100, minValue: low, maxValue: high, target: self, action: #selector(slid(_:)))
            slider.isContinuous = true
            slider.identifier = NSUserInterfaceItemIdentifier(key)
            slider.autoresizingMask = [.width]
            pictureView.addSubview(label)
            pictureView.addSubview(slider)
            sliders[key] = (slider, label, title)
        }
        mirror.target = self
        mirror.action = #selector(toggleMirror)
        mirror.font = .menuFont(ofSize: 12)
        reset.target = self
        reset.action = #selector(resetPicture)
        reset.bezelStyle = .rounded
        reset.controlSize = .small
        reset.autoresizingMask = [.minXMargin]
        pictureView.addSubview(mirror)
        pictureView.addSubview(reset)
        layoutPicture(licensed: true)
        picture.view = pictureView
        return picture
    }

    // Lays out the box; locked: grey fill, Unlock line on top, controls disabled.
    func layoutPicture(licensed: Bool) {
        let width = max(pictureView.frame.width, AppDelegate.panel)
        var y: CGFloat = 12
        unlock.isHidden = licensed
        if !licensed {
            unlock.frame = NSRect(x: 26, y: y, width: width - 52, height: 22)
            y += 30
        }
        for (_, key, _, _) in adjustments {
            guard let (slider, label, _) = sliders[key] else { continue }
            label.frame = NSRect(x: 28, y: y, width: width - 56, height: 16)
            label.textColor = licensed ? .secondaryLabelColor : .tertiaryLabelColor
            slider.frame = NSRect(x: 26, y: y + 18, width: width - 52, height: 20)
            slider.isEnabled = licensed
            y += 44
        }
        mirror.frame = NSRect(x: 26, y: y, width: 160, height: 20)
        mirror.isEnabled = licensed
        reset.frame = NSRect(x: width - 26 - 64, y: y - 1, width: 64, height: 22)
        reset.isEnabled = licensed
        y += 30
        box.frame = NSRect(x: 14, y: 4, width: width - 28, height: y - 4)
        box.fillColor = licensed ? .clear : NSColor.labelColor.withAlphaComponent(0.06)
        pictureView.frame.size = NSSize(width: width, height: y + 6)
        self.licensed = licensed
        picture.menu?.itemChanged(picture)
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
                if self.licensed != licensed { self.layoutPicture(licensed: licensed) }
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
    // From the Unlock line inside the open menu: close the menu first, then ask.
    @objc func enterKey() {
        item.menu?.cancelTracking()
        DispatchQueue.main.async { self.askForKey() }
    }

    func askForKey() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Unlock picture controls"
        alert.informativeText = "Brightness, contrast, saturation and mirror: 5 EUR once on Ko-fi. The licence key arrives by email. Paste it here."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        field.placeholderString = "EW1..."
        // Menu bar apps have no Edit menu, so Cmd+V does not reach the field: take a copied key from the clipboard.
        let copied = (NSPasteboard.general.string(forType: .string) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if copied.hasPrefix("EW1.") { field.stringValue = copied }
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
