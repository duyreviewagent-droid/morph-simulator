import SpriteKit
import AppKit

enum HUDMode { case title, play, paused, morph, challenges, maps }

struct ChallengeRow { var title: String; var hint: String; var done: Bool }

final class HUD {
    let scene: SKScene
    private(set) var size = CGSize(width: 1440, height: 900)
    let heavy = "AvenirNext-Heavy", bold = "AvenirNext-Bold", demi = "AvenirNext-DemiBold", reg = "AvenirNext-Medium"
    private let titleLayer = SKNode(), playLayer = SKNode(), pauseLayer = SKNode(), morphLayer = SKNode(), chalLayer = SKNode(), common = SKNode(), bubbleLayer = SKNode()
    private(set) var mode: HUDMode = .title
    var now = 0.0

    // title
    private let logo = SKLabelNode(), logo2 = SKLabelNode(), tagline = SKLabelNode(), playBtn = SKShapeNode(), playLbl = SKLabelNode(), titleKeys = SKLabelNode(), titleStats = SKLabelNode()
    // play
    private let comboPanel = SKShapeNode(), comboName = SKLabelNode()
    private var slotLabels: [SKLabelNode] = [], slotKeys: [SKLabelNode] = []
    private let abilityPanel = SKShapeNode()
    private var abilityLines: [SKLabelNode] = []
    private let progress = SKLabelNode(), progress2 = SKLabelNode(), chaosLbl = SKLabelNode()
    private let hint = SKLabelNode()
    private let saved = SKLabelNode()
    private var savedUntil = 0.0
    private let toastBg = SKShapeNode(), toastTitle = SKLabelNode(), toastSub = SKLabelNode()
    private var toasts: [(String, String, NSColor)] = []
    private var toastStart = -99.0
    private let crosshair = SKShapeNode(circleOfRadius: 2)
    // pause
    private let dim = SKShapeNode(), pauseTitle = SKLabelNode(), pauseKeys = SKLabelNode()
    // morph menu
    private let morphTitle = SKLabelNode(), morphHelp = SKLabelNode(), morphName = SKLabelNode(), searchBox = SKShapeNode(), searchLbl = SKLabelNode()
    private var slotBtns: [SKShapeNode] = [], slotBtnLbl: [SKLabelNode] = [], slotBtnName: [SKLabelNode] = [], slotBtnAdd: [SKLabelNode] = []
    private(set) var addOnRects: [CGRect] = [.zero, .zero, .zero]
    private(set) var slotRects: [CGRect] = []
    private var tiles: [SKShapeNode] = [], tileLbl: [SKLabelNode] = [], tileDot: [SKShapeNode] = []
    private(set) var tileRects: [CGRect] = []
    // challenges
    private let chalTitle = SKLabelNode(), chalPanel = SKShapeNode()
    private var chalRows: [(SKLabelNode, SKLabelNode, SKShapeNode)] = []
    private var bubbles: [SKNode] = []
    private let mapLabel = SKLabelNode(), mapBlurb = SKLabelNode(), arrowL = SKLabelNode(), arrowR = SKLabelNode()
    private(set) var mapLeftRect = CGRect.zero, mapRightRect = CGRect.zero
    private let mapsLayer = SKNode(), mapsTitle = SKLabelNode()
    private var mapCards: [(SKShapeNode, SKLabelNode, SKLabelNode, SKLabelNode)] = []
    private(set) var mapRects: [CGRect] = []
    private let loadingBg = SKShapeNode(), loadingLbl = SKLabelNode()
    private let dimM = SKShapeNode(), dimC = SKShapeNode(), dimMaps = SKShapeNode()
    private(set) var playRect = CGRect.zero

    init() {
        scene = SKScene(size: size)
        scene.scaleMode = .resizeFill
        scene.backgroundColor = .clear
        scene.isUserInteractionEnabled = false
        for n in [bubbleLayer, playLayer, titleLayer, morphLayer, chalLayer, mapsLayer, pauseLayer, common] { scene.addChild(n) }
        buildTitle(); buildPlay(); buildPause(); buildMorph(); buildChallenges(); buildMaps(); buildCommon()
        layout(size)
        setMode(.title)
    }

    // MARK: helpers

    private func style(_ l: SKLabelNode, _ sz: CGFloat, _ font: String, align: SKLabelHorizontalAlignmentMode = .center, color c: NSColor = .white, parent: SKNode, shadow: Bool = true, text: String = "") {
        l.fontName = font; l.fontSize = sz; l.horizontalAlignmentMode = align; l.verticalAlignmentMode = .center; l.fontColor = c
        l.text = text
        parent.addChild(l)
        if shadow {
            let s = SKLabelNode(fontNamed: font)
            s.name = "shadow"; s.text = text; s.fontSize = sz
            s.fontColor = NSColor(white: 0, alpha: 0.55)
            s.horizontalAlignmentMode = align; s.verticalAlignmentMode = .center
            s.position = CGPoint(x: 1.5, y: -2); s.zPosition = -1
            l.addChild(s)
        }
    }

    private func setText(_ l: SKLabelNode, _ t: String, color: NSColor? = nil) {
        if l.text != t {
            l.text = t
            for c in l.children where c.name == "shadow" { (c as? SKLabelNode)?.text = t }
        }
        if let c = color, l.fontColor != c { l.fontColor = c }
    }

    private func panel(_ n: SKShapeNode, _ r: CGRect, alpha: CGFloat = 0.45, radius: CGFloat = 14) {
        n.path = CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)
        n.fillColor = NSColor(white: 0.03, alpha: alpha)
        n.strokeColor = NSColor(white: 1, alpha: 0.12)
        n.lineWidth = 1.5
    }

    static let speciesColor: [NSColor] = [color(0.95, 0.72, 0.55), color(0.95, 0.45, 0.2), color(0.95, 0.95, 0.95)]

    // MARK: build

    private func buildTitle() {
        style(logo, 96, heavy, color: color(1, 0.92, 0.72), parent: titleLayer, text: "MORPH")
        style(logo2, 58, heavy, color: color(1, 0.62, 0.3), parent: titleLayer, text: "SIMULATOR")
        style(tagline, 22, demi, color: NSColor(white: 1, alpha: 0.9), parent: titleLayer, text: "Be a human, a chicken and a cow at the same time. Or any of 100 animals.")
        titleLayer.addChild(playBtn)
        style(playLbl, 34, heavy, color: color(0.15, 0.1, 0.04), parent: playBtn, shadow: false, text: "PLAY")
        style(titleKeys, 16, reg, color: NSColor(white: 1, alpha: 0.85), parent: titleLayer, text: "◀ ▶ map  ·  ENTER start  ·  1 2 3 morph  ·  4 5 6 add-ons  ·  TAB all 100 animals  ·  Z random  ·  B maps  ·  M music")
        style(titleStats, 17, demi, color: color(1, 0.9, 0.6), parent: titleLayer)
    }

    private func buildPlay() {
        playLayer.addChild(comboPanel)
        style(comboName, 26, heavy, align: .left, color: color(1, 0.92, 0.7), parent: comboPanel)
        for i in 0..<3 {
            let k = SKLabelNode(); style(k, 15, heavy, align: .left, color: color(0.15, 0.1, 0.04), parent: comboPanel, shadow: false, text: "\(i + 1)")
            let bg = SKShapeNode(rectOf: CGSize(width: 24, height: 24), cornerRadius: 6)
            bg.fillColor = color(1, 0.85, 0.5); bg.strokeColor = .clear; bg.zPosition = -0.5; bg.name = "keybg"
            k.addChild(bg); bg.position = CGPoint(x: 5, y: 0)
            let l = SKLabelNode(); style(l, 19, demi, align: .left, parent: comboPanel)
            slotKeys.append(k); slotLabels.append(l)
        }
        playLayer.addChild(abilityPanel)
        for _ in 0..<6 { let l = SKLabelNode(); style(l, 16, demi, align: .left, parent: abilityPanel); abilityLines.append(l) }
        style(progress, 18, bold, align: .right, color: color(1, 0.9, 0.6), parent: playLayer)
        style(progress2, 18, bold, align: .right, color: color(0.75, 0.95, 1), parent: playLayer)
        style(hint, 20, demi, color: .white, parent: playLayer)
        style(chaosLbl, 24, heavy, align: .right, color: color(1, 0.55, 0.25), parent: playLayer)
        playLayer.addChild(toastBg)
        style(toastTitle, 30, heavy, color: color(1, 0.88, 0.4), parent: toastBg)
        style(toastSub, 18, demi, color: .white, parent: toastBg)
        crosshair.fillColor = NSColor(white: 1, alpha: 0.0); crosshair.strokeColor = .clear
        playLayer.addChild(crosshair)
    }

    private func buildPause() {
        dim.fillColor = NSColor(white: 0, alpha: 0.5); dim.strokeColor = .clear
        style(pauseTitle, 64, heavy, color: color(1, 0.92, 0.72), parent: pauseLayer, text: "PAUSED")
        style(pauseKeys, 20, demi, parent: pauseLayer, text: "ESC resume  ·  B maps  ·  M music on/off  ·  T back to title  ·  ⌘Q quit")
    }

    private func buildMorph() {
        style(morphTitle, 40, heavy, color: color(1, 0.92, 0.72), parent: morphLayer, text: "MORPH")
        style(morphName, 26, heavy, color: color(1, 0.65, 0.3), parent: morphLayer)
        style(morphHelp, 15, demi, color: NSColor(white: 1, alpha: 0.85), parent: morphLayer,
              text: "1 2 3 slot  ·  4 5 6 add-ons  ·  TYPE a name or click  ·  ENTER apply  ·  SHIFT+ENTER whole animal  ·  0 random  ·  TAB close")
        morphLayer.addChild(searchBox)
        style(searchLbl, 18, bold, align: .left, parent: searchBox, shadow: false)
        for sl in Slot.allCases {
            let b = SKShapeNode(); morphLayer.addChild(b)
            let l = SKLabelNode(); style(l, 15, heavy, align: .left, color: NSColor(white: 1, alpha: 0.7), parent: b, shadow: false, text: "\(sl.rawValue + 1)  \(sl.name.uppercased())")
            let n = SKLabelNode(); style(n, 21, heavy, align: .left, parent: b, shadow: false)
            let ad = SKLabelNode(); style(ad, 13, bold, align: .left, color: color(0.75, 0.95, 1), parent: b, shadow: false)
            slotBtns.append(b); slotBtnLbl.append(l); slotBtnName.append(n); slotBtnAdd.append(ad)
        }
        for sp in Species.all {
            let t = SKShapeNode(); morphLayer.addChild(t)
            let dot = SKShapeNode(circleOfRadius: 5); dot.fillColor = color(sp.def.a); dot.strokeColor = NSColor(white: 1, alpha: 0.5); dot.lineWidth = 1
            t.addChild(dot)
            let l = SKLabelNode(fontNamed: bold); l.fontSize = 12; l.fontColor = .white
            l.horizontalAlignmentMode = .left; l.verticalAlignmentMode = .center; l.text = sp.name
            t.addChild(l)
            tiles.append(t); tileLbl.append(l); tileDot.append(dot)
        }
        slotRects = Array(repeating: .zero, count: 3)
        tileRects = Array(repeating: .zero, count: Species.count)
    }

    func morphHit(_ p: CGPoint) -> (slot: Int?, tile: Int?, addOn: Int?) {
        if let i = addOnRects.firstIndex(where: { $0.contains(p) }) { return (nil, nil, i) }
        if let i = slotRects.firstIndex(where: { $0.contains(p) }) { return (i, nil, nil) }
        if let i = tileRects.firstIndex(where: { $0.contains(p) }) { return (nil, i, nil) }
        return (nil, nil, nil)
    }

    private func buildMaps() {
        for d in [dimM, dimC, dimMaps] { d.fillColor = NSColor(white: 0, alpha: 0.55); d.strokeColor = .clear }
        morphLayer.insertChild(dimM, at: 0); chalLayer.insertChild(dimC, at: 0); mapsLayer.insertChild(dimMaps, at: 0)
        style(mapsTitle, 40, heavy, color: color(1, 0.92, 0.72), parent: mapsLayer, text: "MAPS")
        for m in Maps.all {
            let card = SKShapeNode(); mapsLayer.addChild(card)
            let t = SKLabelNode(); style(t, 24, heavy, parent: card, shadow: false, text: m.name.uppercased())
            let b = SKLabelNode(); style(b, 13, demi, color: NSColor(white: 1, alpha: 0.85), parent: card, shadow: false, text: m.blurb)
            let a = SKLabelNode(); style(a, 12, reg, color: color(0.75, 0.95, 1), parent: card, shadow: false,
                                        text: m.natives.isEmpty ? "Farm animals + the farmer" : m.natives.prefix(5).joined(separator: ", ") + (m.natives.count > 5 ? "…" : ""))
            mapCards.append((card, t, b, a))
        }
        mapRects = Array(repeating: .zero, count: Maps.all.count)
        // title map picker
        style(mapLabel, 30, heavy, color: color(0.75, 1, 0.8), parent: titleLayer)
        style(mapBlurb, 16, demi, color: NSColor(white: 1, alpha: 0.9), parent: titleLayer)
        style(arrowL, 40, heavy, color: .white, parent: titleLayer, text: "◀")
        style(arrowR, 40, heavy, color: .white, parent: titleLayer, text: "▶")
        loadingBg.fillColor = NSColor(white: 0, alpha: 0.7); loadingBg.strokeColor = .clear
        common.addChild(loadingBg)
        style(loadingLbl, 36, heavy, color: color(1, 0.92, 0.72), parent: loadingBg, text: "Travelling…")
        loadingBg.isHidden = true
    }

    func loading(_ on: Bool) { loadingBg.isHidden = !on }

    func showMaps(current: Int, visited: Set<Int>) {
        for (i, c) in mapCards.enumerated() {
            c.1.text = Maps.all[i].name.uppercased() + (i == current ? "  (here)" : visited.contains(i) ? "" : "  ✦ new")
        }
        highlightMap(current)
    }
    func highlightMap(_ sel: Int) {
        for (i, c) in mapCards.enumerated() {
            c.0.fillColor = i == sel ? color(0.25, 0.4, 0.25).withAlphaComponent(0.92) : NSColor(white: 0.05, alpha: 0.75)
            c.0.strokeColor = i == sel ? .white : NSColor(white: 1, alpha: 0.2)
            c.0.lineWidth = i == sel ? 3 : 1.5
        }
    }
    func mapHit(_ p: CGPoint) -> Int? { mapRects.firstIndex(where: { $0.contains(p) }) }

    private func buildChallenges() {
        chalLayer.addChild(chalPanel)
        style(chalTitle, 36, heavy, color: color(1, 0.92, 0.72), parent: chalLayer, text: "STATS")
    }

    private func buildCommon() {
        style(saved, 16, heavy, align: .right, color: color(0.6, 1, 0.6), parent: common, text: "SAVED")
        saved.alpha = 0
    }

    // MARK: layout

    func layout(_ s: CGSize) {
        size = s
        scene.size = s
        let W = s.width, H = s.height
        logo.position = CGPoint(x: W / 2, y: H * 0.76)
        logo2.position = CGPoint(x: W / 2, y: H * 0.76 - 70)
        tagline.position = CGPoint(x: W / 2, y: H * 0.76 - 120)
        playBtn.path = CGPath(roundedRect: CGRect(x: -130, y: -36, width: 260, height: 72), cornerWidth: 20, cornerHeight: 20, transform: nil)
        playBtn.fillColor = color(1, 0.8, 0.4); playBtn.strokeColor = color(1, 0.95, 0.8); playBtn.lineWidth = 3
        playBtn.position = CGPoint(x: W / 2, y: H * 0.2)
        playRect = CGRect(x: W / 2 - 130, y: H * 0.2 - 36, width: 260, height: 72)
        titleKeys.position = CGPoint(x: W / 2, y: 34)
        titleStats.position = CGPoint(x: W / 2, y: H * 0.2 - 70)

        let pw: CGFloat = 330
        panel(comboPanel, CGRect(x: 0, y: -146, width: pw + 150, height: 146))
        comboPanel.position = CGPoint(x: 18, y: H - 18)
        comboName.position = CGPoint(x: 18, y: -30)
        for i in 0..<3 {
            slotKeys[i].position = CGPoint(x: 20, y: -66 - CGFloat(i) * 27)
            slotLabels[i].position = CGPoint(x: 52, y: -66 - CGFloat(i) * 27)
        }
        panel(abilityPanel, CGRect(x: 0, y: 0, width: 380, height: 170))
        abilityPanel.position = CGPoint(x: 18, y: 18)
        for (i, l) in abilityLines.enumerated() { l.position = CGPoint(x: 16, y: 148 - CGFloat(i) * 26) }
        progress.position = CGPoint(x: W - 22, y: H - 34)
        progress2.position = CGPoint(x: W - 22, y: H - 60)
        chaosLbl.position = CGPoint(x: W - 22, y: H - 92)
        hint.position = CGPoint(x: W / 2, y: 110)
        toastBg.position = CGPoint(x: W / 2, y: H - 110)
        toastTitle.position = CGPoint(x: 0, y: 12)
        toastSub.position = CGPoint(x: 0, y: -20)
        saved.position = CGPoint(x: W - 22, y: 22)
        crosshair.position = CGPoint(x: W / 2, y: H / 2)

        dim.path = CGPath(rect: CGRect(origin: .zero, size: s), transform: nil)
        pauseTitle.position = CGPoint(x: W / 2, y: H * 0.58)
        pauseKeys.position = CGPoint(x: W / 2, y: H * 0.46)

        morphTitle.position = CGPoint(x: W / 2, y: H - 46)
        morphName.position = CGPoint(x: W / 2, y: H - 86)
        morphHelp.position = CGPoint(x: W / 2, y: 26)
        let top = H - 120, bottom: CGFloat = 50
        let sw: CGFloat = min(230, W * 0.18)
        let gridL: CGFloat = 40 + sw + 24, gridR = W - 30
        let cols = 10, rows = (Species.count + cols - 1) / cols
        let tw = (gridR - gridL) / CGFloat(cols), th = min(40, (top - bottom) / CGFloat(rows))
        for i in 0..<3 {
            let r = CGRect(x: 40, y: top - CGFloat(i + 1) * 100 + 10, width: sw, height: 90)
            slotRects[i] = CGRect(x: r.minX, y: r.minY + 26, width: r.width, height: r.height - 26)
            addOnRects[i] = CGRect(x: r.minX, y: r.minY, width: r.width, height: 26)
            slotBtns[i].path = CGPath(roundedRect: r, cornerWidth: 14, cornerHeight: 14, transform: nil)
            slotBtnLbl[i].position = CGPoint(x: r.minX + 14, y: r.maxY - 18)
            slotBtnName[i].position = CGPoint(x: r.minX + 14, y: r.minY + 42)
            slotBtnAdd[i].position = CGPoint(x: r.minX + 14, y: r.minY + 14)
        }
        let sr = CGRect(x: 40, y: top - 3 * 100 - 56, width: sw, height: 44)
        searchBox.path = CGPath(roundedRect: sr, cornerWidth: 10, cornerHeight: 10, transform: nil)
        searchBox.fillColor = NSColor(white: 1, alpha: 0.1); searchBox.strokeColor = NSColor(white: 1, alpha: 0.5); searchBox.lineWidth = 1.5
        searchLbl.position = CGPoint(x: sr.minX + 12, y: sr.midY)
        for i in 0..<Species.count {
            let c = i % cols, r = i / cols
            let rect = CGRect(x: gridL + CGFloat(c) * tw + 2, y: top - CGFloat(r + 1) * th + 2, width: tw - 4, height: th - 4)
            tileRects[i] = rect
            tiles[i].path = CGPath(roundedRect: rect, cornerWidth: 7, cornerHeight: 7, transform: nil)
            tileDot[i].position = CGPoint(x: rect.minX + 10, y: rect.midY)
            tileLbl[i].position = CGPoint(x: rect.minX + 19, y: rect.midY)
            tileLbl[i].fontSize = tw < 96 ? 10.5 : 12
        }
        chalTitle.position = CGPoint(x: W / 2, y: H - 60)
        for d in [dimM, dimC, dimMaps] { d.path = CGPath(rect: CGRect(origin: .zero, size: s), transform: nil) }
        mapsTitle.position = CGPoint(x: W / 2, y: H - 60)
        let cw = min(250, (W - 80) / 5 - 12), chh: CGFloat = 130
        for (i, c) in mapCards.enumerated() {
            let col = i % 5, row = i / 5
            let r = CGRect(x: W / 2 - (cw + 12) * 2.5 + CGFloat(col) * (cw + 12) + 6, y: H * 0.62 - CGFloat(row) * (chh + 16), width: cw, height: chh)
            mapRects[i] = r
            c.0.path = CGPath(roundedRect: r, cornerWidth: 14, cornerHeight: 14, transform: nil)
            c.1.position = CGPoint(x: r.midX, y: r.maxY - 30)
            c.2.position = CGPoint(x: r.midX, y: r.midY - 4)
            c.3.position = CGPoint(x: r.midX, y: r.minY + 22)
            c.1.fontSize = cw < 220 ? 19 : 24
            c.2.fontSize = cw < 220 ? 10.5 : 13
            c.3.fontSize = cw < 220 ? 10 : 12
        }
        mapLabel.position = CGPoint(x: W / 2, y: H * 0.2 + 100)
        mapBlurb.position = CGPoint(x: W / 2, y: H * 0.2 + 68)
        arrowL.position = CGPoint(x: W / 2 - 220, y: H * 0.2 + 100)
        arrowR.position = CGPoint(x: W / 2 + 220, y: H * 0.2 + 100)
        mapLeftRect = CGRect(x: W / 2 - 250, y: H * 0.2 + 70, width: 60, height: 60)
        mapRightRect = CGRect(x: W / 2 + 190, y: H * 0.2 + 70, width: 60, height: 60)
        loadingBg.path = CGPath(rect: CGRect(origin: .zero, size: s), transform: nil)
        loadingLbl.position = CGPoint(x: W / 2, y: H / 2)
        if !lastRows.isEmpty { showChallenges(lastRows) }
    }

    func setMode(_ m: HUDMode) {
        mode = m
        titleLayer.isHidden = m != .title
        playLayer.isHidden = m == .title || m == .challenges
        pauseLayer.isHidden = m != .paused
        morphLayer.isHidden = m != .morph
        chalLayer.isHidden = m != .challenges
        mapsLayer.isHidden = m != .maps
        bubbleLayer.isHidden = m == .title
        toastBg.isHidden = m == .morph || m == .maps
        comboPanel.isHidden = m == .morph || m == .maps
        abilityPanel.isHidden = m == .maps
        if dim.parent == nil { pauseLayer.insertChild(dim, at: 0) }
        dim.isHidden = m != .paused
    }

    // MARK: per-frame

    func updateTitle(_ done: Int, _ total: Int, _ combos: Int, map: MapDef) {
        setText(mapLabel, "MAP:  " + map.name.uppercased())
        setText(mapBlurb, map.blurb)
        setText(titleStats, "100 animals  ·  any head, any body, any legs  ·  12 add-ons each  ·  10 maps")
        let pulse = 1 + 0.04 * sin(now * 3)
        playBtn.setScale(CGFloat(pulse))
    }

    func updatePlay(combo: Combo, addOns: [Int], chaos: Int, abilities: [String], done: Int, total: Int, combos: Int, hintText: String) {
        setText(comboName, combo.name.uppercased())
        for s in Slot.allCases {
            let sp = combo[s]
            let c = sp.def.a
            let lc = color(mix3(c, V3(1, 1, 1), 0.45))
            let ao = addOns[s.rawValue]
            setText(slotLabels[s.rawValue], "\(s.name.uppercased())   \(sp.name)" + (ao > 0 ? "   ·  \(s.rawValue + 4) \(AddOns.names(s)[ao])" : "   ·  \(s.rawValue + 4) add-on"), color: lc)
        }
        for (i, l) in abilityLines.enumerated() { setText(l, i < abilities.count ? abilities[i] : "") }
        setText(progress, "TAB morph  ·  B maps  ·  J stats")
        setText(chaosLbl, "")
        setText(progress2, "")
        setText(hint, hintText)
        // toasts
        if !toasts.isEmpty {
            if toastStart < 0 { toastStart = now }
            let t = now - toastStart
            let (a, b, c) = toasts[0]
            setText(toastTitle, a, color: c); setText(toastSub, b)
            let w = max(toastTitle.frame.width, toastSub.frame.width) + 60
            toastBg.path = CGPath(roundedRect: CGRect(x: -w / 2, y: -42, width: w, height: 84), cornerWidth: 18, cornerHeight: 18, transform: nil)
            toastBg.fillColor = NSColor(white: 0.03, alpha: 0.55); toastBg.strokeColor = c.withAlphaComponent(0.6); toastBg.lineWidth = 2
            let alpha = min(1, t * 6) * min(1, max(0, (3.0 - t) * 3))
            toastBg.alpha = CGFloat(alpha)
            toastBg.setScale(CGFloat(1 + 0.15 * max(0, 1 - t * 5)))
            if t > 3.0 { toasts.removeFirst(); toastStart = -99 }
        } else {
            toastBg.alpha = 0
        }
        saved.alpha = now < savedUntil ? CGFloat(min(1, (savedUntil - now) * 2)) : 0
    }

    func toast(_ title: String, _ sub: String, color c: NSColor = color(1, 0.88, 0.4)) {
        if toasts.count < 6 { toasts.append((title, sub, c)) }
    }

    func flashSaved() { savedUntil = now + 1.4 }

    /// "+15 CRATE" style popups that float up and fade.
    func chaosPop(_ text: String, big: Bool) {
        let l = SKLabelNode(fontNamed: heavy)
        l.text = text; l.fontSize = big ? 34 : 22
        l.fontColor = big ? color(1, 0.45, 0.15) : color(1, 0.85, 0.3)
        l.position = CGPoint(x: size.width / 2 + CGFloat.random(in: -140...140), y: size.height * 0.62 + CGFloat.random(in: -30...30))
        let sh = SKLabelNode(fontNamed: heavy); sh.text = text; sh.fontSize = l.fontSize; sh.fontColor = NSColor(white: 0, alpha: 0.6); sh.position = CGPoint(x: 2, y: -2); sh.zPosition = -1
        l.addChild(sh)
        playLayer.addChild(l)
        l.setScale(0.5)
        l.run(.sequence([.group([.scale(to: 1, duration: 0.12), .moveBy(x: 0, y: 70, duration: 1.2)]), .fadeOut(withDuration: 0.3), .removeFromParent()]))
    }

    func setBubbles(_ items: [(CGPoint, String, Bool)]) {
        while bubbles.count < items.count {
            let n = SKNode()
            let bg = SKShapeNode(); bg.name = "bg"
            n.addChild(bg)
            let l = SKLabelNode(fontNamed: bold); l.name = "t"; l.fontSize = 18; l.fontColor = color(0.1, 0.08, 0.05)
            l.verticalAlignmentMode = .center; l.horizontalAlignmentMode = .center
            n.addChild(l)
            bubbleLayer.addChild(n)
            bubbles.append(n)
        }
        for (i, b) in bubbles.enumerated() {
            guard i < items.count else { b.isHidden = true; continue }
            let (p, text, player) = items[i]
            b.isHidden = false
            b.position = CGPoint(x: min(max(p.x, 120), size.width - 120), y: min(max(p.y + 40, 60), size.height - 40))
            let l = b.childNode(withName: "t") as! SKLabelNode
            if l.text != text {
                l.text = text
                let w = l.frame.width + 28
                let bg = b.childNode(withName: "bg") as! SKShapeNode
                let path = CGMutablePath()
                path.addRoundedRect(in: CGRect(x: -w / 2, y: -18, width: w, height: 36), cornerWidth: 14, cornerHeight: 14)
                path.move(to: CGPoint(x: -8, y: -18)); path.addLine(to: CGPoint(x: 0, y: -30)); path.addLine(to: CGPoint(x: 8, y: -18))
                bg.path = path
                bg.fillColor = player ? color(1, 0.97, 0.88) : color(1, 1, 1)
                bg.strokeColor = NSColor(white: 0, alpha: 0.25)
            }
        }
    }

    func updateMorph(combo: Combo, slot: Int, cursor: Int, tried: Set<Int>, discovered: Set<Int>, search: String, addOns: [Int]) {
        let blink = Int(now * 2) % 2 == 0 ? "|" : " "
        searchLbl.text = search.isEmpty ? "Type an animal…" : "🔍 " + search + blink
        searchLbl.fontColor = search.isEmpty ? NSColor(white: 1, alpha: 0.5) : .white
        setText(morphName, combo.name.uppercased())
        for i in 0..<3 {
            let on = i == slot
            slotBtns[i].fillColor = on ? color(1, 0.8, 0.4).withAlphaComponent(0.95) : NSColor(white: 0.05, alpha: 0.65)
            slotBtns[i].strokeColor = on ? .white : NSColor(white: 1, alpha: 0.2)
            slotBtns[i].lineWidth = on ? 3 : 1.5
            slotBtnName[i].text = combo[Slot(rawValue: i)!].name
            slotBtnName[i].fontColor = on ? color(0.12, 0.08, 0.04) : .white
            slotBtnLbl[i].fontColor = on ? color(0.3, 0.2, 0.1) : NSColor(white: 1, alpha: 0.7)
            slotBtnAdd[i].text = "\(i + 4) ADD-ON ▸ " + AddOns.names(Slot(rawValue: i)!)[addOns[i]]
            slotBtnAdd[i].fontColor = on ? color(0.1, 0.25, 0.45) : color(0.75, 0.95, 1)
        }
        let cur = combo[Slot(rawValue: slot)!].id
        for i in 0..<tiles.count {
            let sel = i == cur, hover = i == cursor
            tiles[i].fillColor = sel ? color(1, 0.8, 0.4).withAlphaComponent(0.92) : NSColor(white: tried.contains(i) ? 0.12 : 0.03, alpha: 0.7)
            tiles[i].strokeColor = hover ? .white : NSColor(white: 1, alpha: tried.contains(i) ? 0.25 : 0.1)
            tiles[i].lineWidth = hover ? 3 : 1
            tileLbl[i].fontColor = sel ? color(0.12, 0.08, 0.04) : tried.contains(i) ? .white : color(0.75, 0.95, 1)
        }
    }

    private var lastRows: [ChallengeRow] = []
    func showChallenges(_ rows: [ChallengeRow]) {
        lastRows = rows
        for r in chalRows { r.0.removeFromParent(); r.1.removeFromParent(); r.2.removeFromParent() }
        chalRows.removeAll()
        let cols = 2
        let perCol = (rows.count + 1) / cols
        let colW = min(560, (size.width - 80) / 2)
        let rowH: CGFloat = min(52, (size.height - 180) / CGFloat(perCol))
        let left = size.width / 2 - colW
        panel(chalPanel, CGRect(x: left - 20, y: size.height - 110 - rowH * CGFloat(perCol) - 16, width: colW * 2 + 40, height: rowH * CGFloat(perCol) + 26), alpha: 0.55)
        for (i, r) in rows.enumerated() {
            let c = i / perCol, k = i % perCol
            let x = left + CGFloat(c) * colW + 40, y = size.height - 120 - CGFloat(k) * rowH
            let box = SKShapeNode(rectOf: CGSize(width: 8, height: 8), cornerRadius: 4)
            box.position = CGPoint(x: x - 22, y: y - 6)
            box.fillColor = color(1, 0.8, 0.4)
            box.strokeColor = .clear
            box.lineWidth = 2
            chalLayer.addChild(box)
            let t = SKLabelNode(); style(t, 18, demi, align: .left, color: NSColor(white: 1, alpha: 0.85), parent: chalLayer, text: r.title)
            t.position = CGPoint(x: x, y: y - 6)
            let h = SKLabelNode(); style(h, 20, heavy, align: .right, color: color(1, 0.9, 0.6), parent: chalLayer, text: r.hint)
            h.position = CGPoint(x: x + colW - 80, y: y - 6)
            if r.hint.count > 26 { h.fontSize = 13; for c in h.children { (c as? SKLabelNode)?.fontSize = 13 } }
            chalRows.append((t, h, box))
        }
    }
}

func grouped(_ v: Int) -> String {
    let f = NumberFormatter()
    f.numberStyle = .decimal
    return f.string(from: NSNumber(value: v)) ?? "\(v)"
}
