import AppKit
import SceneKit

enum Key {
    static let a: UInt16 = 0, s: UInt16 = 1, d: UInt16 = 2, f: UInt16 = 3, w: UInt16 = 13, r: UInt16 = 15, c: UInt16 = 8, h: UInt16 = 4
    static let e: UInt16 = 14, q: UInt16 = 12, j: UInt16 = 38, z: UInt16 = 6, x: UInt16 = 7, g: UInt16 = 5, v: UInt16 = 9, t: UInt16 = 17, b: UInt16 = 11, n: UInt16 = 45
    static let ret: UInt16 = 36, enter: UInt16 = 76, tab: UInt16 = 48, m: UInt16 = 46, space: UInt16 = 49, esc: UInt16 = 53, p: UInt16 = 35
    static let left: UInt16 = 123, right: UInt16 = 124, down: UInt16 = 125, up: UInt16 = 126
    static let shift: UInt16 = 56
    static let nums: [UInt16] = [18, 19, 20, 21, 23, 22, 26]
}

/// Keyboard/mouse state shared between the main thread (events) and the render thread (game loop).
final class InputState {
    private let lock = NSLock()
    private var held = Set<UInt16>()
    private var presses: [UInt16] = []
    private var typed = ""
    private var clicks: [CGPoint] = []
    private var mouse = CGPoint(x: -1, y: -1)
    private var mouseHeld = false
    private var drag = CGPoint.zero
    private var scroll: CGFloat = 0

    func keyDown(_ k: UInt16, repeatEvent: Bool) {
        lock.lock(); defer { lock.unlock() }
        // arrow repeats count as presses so menus scroll when held
        if !repeatEvent || (k >= Key.left && k <= Key.up) { presses.append(k) }
        held.insert(k)
    }
    func type(_ c: String) { lock.lock(); typed += c; lock.unlock() }
    func keyUp(_ k: UInt16) { lock.lock(); held.remove(k); lock.unlock() }
    func flags(shift: Bool) {
        lock.lock(); defer { lock.unlock() }
        if shift { held.insert(Key.shift) } else { held.remove(Key.shift) }
    }
    func mouseDown(_ p: CGPoint) { lock.lock(); mouse = p; mouseHeld = true; clicks.append(p); lock.unlock() }
    func mouseUp(_ p: CGPoint) { lock.lock(); mouse = p; mouseHeld = false; lock.unlock() }
    func mouseMoved(_ p: CGPoint) { lock.lock(); mouse = p; lock.unlock() }
    func dragged(_ p: CGPoint, dx: CGFloat, dy: CGFloat) { lock.lock(); mouse = p; drag.x += dx; drag.y += dy; lock.unlock() }
    func scrolled(_ d: CGFloat) { lock.lock(); scroll += d; lock.unlock() }

    struct Frame {
        var presses: [UInt16] = []
        var held = Set<UInt16>()
        var clicks: [CGPoint] = []
        var mouse = CGPoint(x: -1, y: -1)
        var mouseHeld = false
        var drag = CGPoint.zero
        var scroll: CGFloat = 0
        var typed = ""
        func down(_ ks: UInt16...) -> Bool { ks.contains { held.contains($0) } }
        func pressed(_ ks: UInt16...) -> Bool { ks.contains { presses.contains($0) } }
    }

    func frame() -> Frame {
        lock.lock(); defer { lock.unlock() }
        var f = Frame()
        f.presses = presses; presses.removeAll()
        f.typed = typed; typed = ""
        f.clicks = clicks; clicks.removeAll()
        f.held = held
        f.mouse = mouse
        f.mouseHeld = mouseHeld
        f.drag = drag; drag = .zero
        f.scroll = scroll; scroll = 0
        return f
    }

    func clear() {
        lock.lock(); defer { lock.unlock() }
        held.removeAll(); presses.removeAll(); clicks.removeAll(); mouseHeld = false
    }
}

final class GameView: SCNView {
    let input = InputState()
    var inputEnabled = true
    private var tracking: NSTrackingArea?

    override var acceptsFirstResponder: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = tracking { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(t)
        tracking = t
    }

    private func loc(_ e: NSEvent) -> CGPoint { convert(e.locationInWindow, from: nil) }

    override func keyDown(with e: NSEvent) {
        if e.modifierFlags.contains(.command) || !inputEnabled { super.keyDown(with: e); return }
        input.keyDown(e.keyCode, repeatEvent: e.isARepeat)
        if let c = e.characters, !c.isEmpty { input.type(c) }
    }
    override func keyUp(with e: NSEvent) { guard inputEnabled else { return }; input.keyUp(e.keyCode) }
    override func flagsChanged(with e: NSEvent) { guard inputEnabled else { return }; input.flags(shift: e.modifierFlags.contains(.shift)) }
    override func mouseDown(with e: NSEvent) { guard inputEnabled else { return }; input.mouseDown(loc(e)) }
    override func mouseUp(with e: NSEvent) { guard inputEnabled else { return }; input.mouseUp(loc(e)) }
    override func mouseMoved(with e: NSEvent) { guard inputEnabled else { return }; input.mouseMoved(loc(e)) }
    override func mouseDragged(with e: NSEvent) { guard inputEnabled else { return }; input.dragged(loc(e), dx: e.deltaX, dy: e.deltaY) }
    override func rightMouseDragged(with e: NSEvent) { guard inputEnabled else { return }; input.dragged(loc(e), dx: e.deltaX, dy: e.deltaY) }
    override func scrollWheel(with e: NSEvent) { guard inputEnabled else { return }; input.scrolled(e.scrollingDeltaY * (e.hasPreciseScrollingDeltas ? 0.1 : 1)) }
    override func resignFirstResponder() -> Bool { input.clear(); return super.resignFirstResponder() }
}
