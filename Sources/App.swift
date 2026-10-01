import Cocoa
import SceneKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var window: NSWindow!
    var view: GameView!
    var game: Game!
    let args = CommandLine.arguments

    func arg(_ name: String) -> String? {
        guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    func applicationDidFinishLaunching(_ n: Notification) {
        buildMenu()
        let w = CGFloat(Double(arg("--width") ?? "") ?? 1440), h = CGFloat(Double(arg("--height") ?? "") ?? 900)
        let frame = NSRect(x: 0, y: 0, width: w, height: h)
        window = NSWindow(contentRect: frame, styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Morph Simulator"
        window.collectionBehavior = [.fullScreenPrimary]
        window.minSize = NSSize(width: 960, height: 640)
        window.acceptsMouseMovedEvents = true
        window.center()
        view = GameView(frame: frame, options: [SCNView.Option.preferredRenderingAPI.rawValue: SCNRenderingAPI.metal.rawValue])
        let shot = arg("--shot")
        if shot != nil || args.contains("--autotest") { SaveData.disabled = true }
        game = Game(view: view, muted: args.contains("--mute"))
        view.frame = frame
        window.contentView = view
        window.delegate = self
        game.backing = window.backingScaleFactor
        if args.contains("--autotest") {
            view.isPlaying = false
            view.delegate = nil
            exit(game.autotest() ? 0 : 1)
        }
        if shot != nil {
            view.inputEnabled = false
            game.ignoreInput = true
            // Test captures never steal keyboard focus. They float on every Space so macOS doesn't
            // throttle an occluded window.
            window.level = .floating
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.orderFrontRegardless()
        } else {
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(view)
            NSApp.activate(ignoringOtherApps: true)
        }
        if args.contains("--stats") { view.showsStatistics = true }
        devHooks()
    }

    /// Flags used for automated screenshots while developing.
    private func devHooks() {
        if let m = arg("--map"), let i = Int(m) { game.loadMap(i) }
        if let s = arg("--combo") { game.devCombo(s) }
        if args.contains("--fpslog") { game.fpsLog = true }
        if let s = arg("--scene") { game.devScene(s) }
        if let p = arg("--pos") {
            let v = p.split(separator: ",").compactMap { Float($0) }
            if v.count == 3 { game.devPlace(V3(v[0], v[1], v[2]), yaw: Float(arg("--yaw") ?? "") ?? 0) }
        }
        if let c = arg("--cam") {
            let v = c.split(separator: ",").compactMap { Float($0) }
            if v.count == 3 { game.devCam = V3(v[0], v[1], v[2]) }
        }
        if let c = arg("--look") {
            let v = c.split(separator: ",").compactMap { Float($0) }
            if v.count == 3 { game.devLook = V3(v[0], v[1], v[2]) }
        }
        if let q = arg("--quit"), let t = Double(q) {
            DispatchQueue.main.asyncAfter(deadline: .now() + t) { NSApp.terminate(nil) }
        }
        if let path = arg("--shot") {
            let delay = Double(arg("--delay") ?? "4") ?? 4
            func attempt(_ n: Int) {
                let img = self.view.snapshot()
                if let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
                   let png = rep.representation(using: .png, properties: [:]),
                   (try? png.write(to: URL(fileURLWithPath: path))) != nil {
                    NSApp.terminate(nil)
                } else if n < 6 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) { attempt(n + 1) }
                } else {
                    NSLog("Morph Simulator: snapshot failed")
                    NSApp.terminate(nil)
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { attempt(0) }
        }
    }

    // Test captures keep the window unfocused, and AppKit can count it as closed.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { arg("--shot") == nil }
    func applicationWillTerminate(_ notification: Notification) { if !SaveData.disabled { game?.saveNow() } }
    func windowDidChangeBackingProperties(_ notification: Notification) { game?.backing = window.backingScaleFactor }
    func windowDidResignKey(_ notification: Notification) { view?.input.clear() }

    private func buildMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Morph Simulator", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Morph Simulator", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Morph Simulator", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        let viewItem = NSMenuItem()
        main.addItem(viewItem)
        let viewMenu = NSMenu(title: "View")
        viewMenu.addItem(NSMenuItem(title: "Toggle Full Screen", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f"))
        viewItem.submenu = viewMenu
        NSApp.mainMenu = main
    }
}

enum IconMaker {
    static func run(_ dir: String) {
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        for s in [16, 32, 64, 128, 256, 512, 1024] {
            let img = draw(s)
            if s <= 512 { savePNG(img, to: "\(dir)/icon_\(s)x\(s).png") }
            if s >= 32 { savePNG(img, to: "\(dir)/icon_\(s / 2)x\(s / 2)@2x.png") }
        }
    }

    /// A cow-spotted, chicken-combed head with a human eye, on a sunny farm field.
    static func draw(_ size: Int) -> CGImage {
        makeImage(size, size) { ctx in
            let S = CGFloat(size)
            let inset = S * 0.08
            let rect = CGRect(x: inset, y: inset, width: S - inset * 2, height: S - inset * 2)
            ctx.addPath(CGPath(roundedRect: rect, cornerWidth: S * 0.2, cornerHeight: S * 0.2, transform: nil))
            ctx.clip()
            let cs = CGColorSpace(name: CGColorSpace.sRGB)!
            let sky = CGGradient(colorsSpace: cs, colors: [CGColor(srgbRed: 0.55, green: 0.78, blue: 0.98, alpha: 1), CGColor(srgbRed: 0.98, green: 0.92, blue: 0.7, alpha: 1)] as CFArray, locations: [0, 1])!
            ctx.drawLinearGradient(sky, start: CGPoint(x: 0, y: S), end: CGPoint(x: 0, y: S * 0.3), options: [])
            ctx.setFillColor(CGColor(srgbRed: 0.32, green: 0.6, blue: 0.2, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: S, height: S * 0.3))
            // red barn in the back
            ctx.setFillColor(CGColor(srgbRed: 0.65, green: 0.12, blue: 0.08, alpha: 1))
            ctx.fill(CGRect(x: S * 0.62, y: S * 0.28, width: S * 0.3, height: S * 0.2))
            ctx.move(to: CGPoint(x: S * 0.6, y: S * 0.48)); ctx.addLine(to: CGPoint(x: S * 0.77, y: S * 0.6)); ctx.addLine(to: CGPoint(x: S * 0.94, y: S * 0.48)); ctx.fillPath()
            // the head: left half cow, right half chicken
            let c = CGPoint(x: S * 0.45, y: S * 0.45), r = S * 0.25
            ctx.saveGState()
            ctx.addEllipse(in: CGRect(x: c.x - r, y: c.y - r * 1.05, width: r * 2, height: r * 2.1)); ctx.clip()
            ctx.setFillColor(CGColor(srgbRed: 0.95, green: 0.93, blue: 0.9, alpha: 1)); ctx.fill(CGRect(x: c.x - r, y: c.y - r * 1.1, width: r, height: r * 2.2))
            ctx.setFillColor(CGColor(gray: 0.05, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: c.x - r * 1.0, y: c.y + r * 0.1, width: r * 0.7, height: r * 0.6))
            ctx.fillEllipse(in: CGRect(x: c.x - r * 0.7, y: c.y - r * 0.8, width: r * 0.5, height: r * 0.45))
            ctx.setFillColor(CGColor(srgbRed: 0.72, green: 0.3, blue: 0.1, alpha: 1)); ctx.fill(CGRect(x: c.x, y: c.y - r * 1.1, width: r, height: r * 2.2))
            ctx.restoreGState()
            // comb on the chicken side, horn on the cow side
            ctx.setFillColor(CGColor(srgbRed: 0.85, green: 0.08, blue: 0.06, alpha: 1))
            for k in 0..<3 { ctx.fillEllipse(in: CGRect(x: c.x + r * (0.05 + CGFloat(k) * 0.28), y: c.y + r * 0.85, width: r * 0.3, height: r * 0.45)) }
            ctx.setFillColor(CGColor(srgbRed: 0.9, green: 0.85, blue: 0.7, alpha: 1))
            ctx.move(to: CGPoint(x: c.x - r * 0.7, y: c.y + r * 0.8)); ctx.addLine(to: CGPoint(x: c.x - r * 1.05, y: c.y + r * 1.35)); ctx.addLine(to: CGPoint(x: c.x - r * 0.45, y: c.y + r * 0.95)); ctx.fillPath()
            // beak and pink muzzle
            ctx.setFillColor(CGColor(srgbRed: 0.95, green: 0.7, blue: 0.2, alpha: 1))
            ctx.move(to: CGPoint(x: c.x + r * 0.85, y: c.y + r * 0.05)); ctx.addLine(to: CGPoint(x: c.x + r * 1.45, y: c.y - r * 0.1)); ctx.addLine(to: CGPoint(x: c.x + r * 0.85, y: c.y - r * 0.3)); ctx.fillPath()
            ctx.setFillColor(CGColor(srgbRed: 0.95, green: 0.62, blue: 0.62, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: c.x - r * 0.75, y: c.y - r * 0.95, width: r * 0.8, height: r * 0.5))
            // eyes: a human one and a chicken one
            ctx.setFillColor(CGColor(gray: 1, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: c.x - r * 0.5, y: c.y + r * 0.05, width: r * 0.36, height: r * 0.3))
            ctx.setFillColor(CGColor(srgbRed: 0.3, green: 0.18, blue: 0.08, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: c.x - r * 0.4, y: c.y + r * 0.09, width: r * 0.2, height: r * 0.2))
            ctx.setFillColor(CGColor(srgbRed: 0.95, green: 0.55, blue: 0.1, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: c.x + r * 0.3, y: c.y + r * 0.1, width: r * 0.26, height: r * 0.26))
            ctx.setFillColor(CGColor(gray: 0, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: c.x + r * 0.37, y: c.y + r * 0.17, width: r * 0.12, height: r * 0.12))
        }
    }
}
