import Cocoa
import SceneKit
import Metal

let argv = CommandLine.arguments
func argValue(_ name: String) -> String? {
    guard let i = argv.firstIndex(of: name), i + 1 < argv.count else { return nil }
    return argv[i + 1]
}

if let dir = argValue("--make-icon") {
    IconMaker.run(dir)
    exit(0)
}

// Windowless modes: these work even while the Mac is locked (a GUI launch waits for the login window).
if argv.contains("--autotest") || argValue("--offshot") != nil || argValue("--trailer") != nil {
    SaveData.disabled = true
    let w = CGFloat(Double(argValue("--width") ?? "") ?? 1280), h = CGFloat(Double(argValue("--height") ?? "") ?? 800)
    let view = GameView(frame: NSRect(x: 0, y: 0, width: w, height: h))
    view.isPlaying = false
    let game = Game(view: view, muted: true)
    game.ignoreInput = true
    if argv.contains("--autotest") { exit(game.autotest() ? 0 : 1) }
    view.delegate = nil
    if let dir = argValue("--trailer") {
        let r = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
        r.scene = game.scene
        r.pointOfView = game.camNode
        r.overlaySKScene = game.hud.scene
        game.hud.layout(CGSize(width: w, height: h))
        game.renderTrailer(to: dir, renderer: r, size: CGSize(width: w, height: h))
        exit(0)
    }
    if let m = argValue("--map"), let i = Int(m) { game.loadMap(i) }
    if let s = argValue("--combo") { game.devCombo(s) }
    if let s = argValue("--scene") { game.devScene(s) }
    if let p = argValue("--pos") {
        let v = p.split(separator: ",").compactMap { Float($0) }
        if v.count == 3 { game.devPlace(V3(v[0], v[1], v[2]), yaw: Float(argValue("--yaw") ?? "") ?? 0) }
    }
    if let c = argValue("--cam") {
        let v = c.split(separator: ",").compactMap { Float($0) }
        if v.count == 3 { game.devCam = V3(v[0], v[1], v[2]) }
    }
    if let c = argValue("--look") {
        let v = c.split(separator: ",").compactMap { Float($0) }
        if v.count == 3 { game.devLook = V3(v[0], v[1], v[2]) }
    }
    if let z = argValue("--zoom") { game.zoom = Float(z) ?? 1 }
    if let y = argValue("--camyaw") { game.camYaw = Float(y) ?? 0 }
    if let pz = argValue("--campitch") { game.camPitch = Float(pz) ?? 0.3 }
    if let a = argValue("--act") { game.devAct = a }
    if let a = argValue("--addons") { let v = a.split(separator: ",").compactMap { Int($0) }; if v.count == 3 { game.body.addOns = v; game.body.applyAddOns() } }
    if let l = argValue("--lineup") {
        let v = l.split(separator: ",").compactMap { Int($0) }
        if v.count == 2 { game.devLineup(v[0], v[1], side: argv.contains("--side")) }
    }
    if argv.contains("--nohud") { game.hud.scene.isHidden = true }
    let r = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
    r.scene = game.scene
    r.pointOfView = game.camNode
    r.overlaySKScene = game.hud.scene
    game.hud.layout(CGSize(width: w, height: h))
    let secs = Double(argValue("--delay") ?? "3") ?? 3
    var t = 0.0
    while t < secs {
        game.renderer(r, updateAtTime: t)
        t += 1.0 / 60
    }
    _ = r.snapshot(atTime: t, with: CGSize(width: 64, height: 64), antialiasingMode: .none)
    let img = r.snapshot(atTime: t + 1.0 / 60, with: CGSize(width: w, height: h), antialiasingMode: .multisampling4X)
    if let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) {
        try? png.write(to: URL(fileURLWithPath: argValue("--offshot")!))
    }
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
