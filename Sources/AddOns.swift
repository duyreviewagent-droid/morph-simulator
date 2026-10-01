import SceneKit
import simd

/// Things you can wear or have happen to each part. Index 0 is "none", 1 is "hurt".
enum AddOns {
    static let head = ["None", "Hurt", "Top Hat", "Crown", "Party Hat", "Cowboy Hat", "Sunglasses", "Viking Helmet", "Clown Nose", "Headphones", "Halo", "Propeller Cap"]
    static let body = ["None", "Hurt", "Superhero Cape", "Jetpack", "Tutu", "Bow Tie", "Backpack", "Life Jacket", "Armor", "Balloons", "Scarf", "Angel Wings"]
    static let legs = ["None", "Hurt", "Roller Skates", "Spring Shoes", "Rocket Boots", "Rain Boots", "Socks", "Flippers", "High Heels", "Stilts", "Sneakers", "Ice Skates"]
    static func names(_ s: Slot) -> [String] { [head, body, legs][s.rawValue] }
    static let blurbs: [String: String] = [
        "Propeller Cap": "hold SPACE to float down", "Superhero Cape": "hold SPACE to glide", "Jetpack": "hold SPACE to fly",
        "Life Jacket": "float and swim fast", "Armor": "nothing knocks you over", "Balloons": "floaty jumps", "Angel Wings": "flap and glide",
        "Roller Skates": "zoom!", "Spring Shoes": "huge jumps", "Rocket Boots": "double jump", "Flippers": "swim fast", "Stilts": "so tall",
        "Sneakers": "run faster", "Ice Skates": "slide fast", "Rain Boots": "splash through water", "Hurt": "ouch…",
    ]

    static let gold: SCNMaterial = { let m = pbr(color(1, 0.78, 0.25), rough: 0.25, metal: 1); return m }()
    static let steel = pbr(color(0.7, 0.72, 0.75), rough: 0.3, metal: 0.9)
    static let cloth = { (c: V3) in Coats.plain(c, rough: 0.8) }
    static let bandage = Coats.coat(.bands, V3(0.95, 0.94, 0.9), V3(0.85, 0.83, 0.78))
    static let glow: SCNMaterial = { let m = pbr(color(1, 0.95, 0.6), rough: 0.3, emission: color(1, 0.9, 0.5)); return m }()
    static let star: SCNMaterial = { let m = pbr(color(1, 0.9, 0.2), rough: 0.3, emission: color(1, 0.85, 0.1)); return m }()
    static let flame: SCNMaterial = { let m = pbr(color(1, 0.5, 0.1), rough: 1, emission: color(1, 0.55, 0.1)); m.transparency = 0.85; return m }()

    struct Box { var min: V3; var max: V3; var size: V3 { max - min }; var center: V3 { (min + max) / 2 } }
    static func box(_ n: SCNNode) -> Box {
        let (a, b) = n.boundingBox
        return Box(min: V3(Float(a.x), Float(a.y), Float(a.z)), max: V3(Float(b.x), Float(b.y), Float(b.z)))
    }

    // MARK: head

    static func buildHead(_ i: Int, on n: SCNNode) -> SCNNode {
        let root = SCNNode(); root.name = "addon"
        let b = box(n)
        let w = max(0.08, min(b.size.x, b.size.z)), top = V3(b.center.x, b.max.y, b.center.z - b.size.z * 0.1)
        let face = V3(b.center.x, b.center.y + b.size.y * 0.15, b.min.z + b.size.z * 0.62)
        switch head[i] {
        case "Hurt":
            let t = SCNTorus(ringRadius: CGFloat(w * 0.52), pipeRadius: CGFloat(w * 0.07)); t.materials = [bandage]
            root.addChildNode(SCNNode(geometry: t).at(b.center.x, b.center.y + b.size.y * 0.25, b.center.z).rot(0.25, 0, 0.1))
            root.addChildNode(boxNode(CGFloat(w * 0.25), CGFloat(w * 0.25), 0.01, bandage).at(b.center.x + w * 0.25, b.center.y + b.size.y * 0.3, b.max.z * 0.9).rot(0, 0, 0.7))
            let stars = SCNNode(); stars.name = "spin"; stars.simdPosition = top + V3(0, w * 0.35, 0)
            for k in 0..<4 {
                let a = Float(k) / 4 * 2 * .pi
                stars.addChildNode(sphereNode(CGFloat(w * 0.07), star, seg: 8).at(cosf(a) * w * 0.6, 0, sinf(a) * w * 0.6))
            }
            root.addChildNode(stars)
        case "Top Hat":
            root.addChildNode(cylNode(CGFloat(w * 0.62), CGFloat(w * 0.04), Mat.black, seg: 24).at(top.x, top.y, top.z))
            root.addChildNode(cylNode(CGFloat(w * 0.4), CGFloat(w * 0.8), Mat.black, seg: 24).at(top.x, top.y + w * 0.4, top.z))
            root.addChildNode(cylNode(CGFloat(w * 0.405), CGFloat(w * 0.12), cloth(V3(0.6, 0.05, 0.05)), seg: 24).at(top.x, top.y + w * 0.1, top.z))
        case "Crown":
            let t = SCNTube(innerRadius: CGFloat(w * 0.38), outerRadius: CGFloat(w * 0.42), height: CGFloat(w * 0.22)); t.radialSegmentCount = 24; t.materials = [gold]
            root.addChildNode(SCNNode(geometry: t).at(top.x, top.y + w * 0.08, top.z))
            for k in 0..<6 {
                let a = Float(k) / 6 * 2 * .pi
                root.addChildNode(coneNode(CGFloat(w * 0.07), 0.003, CGFloat(w * 0.22), gold, seg: 6).at(top.x + cosf(a) * w * 0.4, top.y + w * 0.3, top.z + sinf(a) * w * 0.4))
                root.addChildNode(sphereNode(CGFloat(w * 0.035), Coats.glossy([V3(0.8, 0.05, 0.1), V3(0.1, 0.3, 0.9), V3(0.1, 0.7, 0.2)][k % 3]), seg: 8).at(top.x + cosf(a) * w * 0.42, top.y + w * 0.08, top.z + sinf(a) * w * 0.42))
            }
        case "Party Hat":
            root.addChildNode(coneNode(CGFloat(w * 0.3), 0.005, CGFloat(w * 0.75), Coats.coat(.bands, V3(0.95, 0.3, 0.6), V3(0.3, 0.7, 0.95)), seg: 20).at(top.x, top.y + w * 0.35, top.z))
            root.addChildNode(sphereNode(CGFloat(w * 0.08), cloth(V3(1, 0.9, 0.2)), seg: 10).at(top.x, top.y + w * 0.75, top.z))
        case "Cowboy Hat":
            let brim = SCNTube(innerRadius: CGFloat(w * 0.3), outerRadius: CGFloat(w * 0.85), height: CGFloat(w * 0.03)); brim.radialSegmentCount = 30; brim.materials = [Mat.leather]
            root.addChildNode(SCNNode(geometry: brim).at(top.x, top.y + w * 0.02, top.z).scl(1, 1, 0.85))
            root.addChildNode(sphereNode(CGFloat(w * 0.4), Mat.leather, seg: 16).scl(1, 0.8, 1.1).at(top.x, top.y + w * 0.15, top.z))
        case "Sunglasses":
            let g = SCNNode(); g.simdPosition = face + V3(0, 0, b.size.z * 0.02)
            root.addChildNode(g)
            for sx in [Float(-1), 1] { g.addChildNode(sphereNode(CGFloat(w * 0.16), Coats.glossy(V3(0.02, 0.02, 0.03)), seg: 12).scl(1.2, 0.8, 0.3).at(sx * w * 0.24, 0, w * 0.12)) }
            g.addChildNode(boxNode(CGFloat(w * 0.9), CGFloat(w * 0.03), CGFloat(w * 0.03), Mat.black).at(0, w * 0.06, w * 0.12))
        case "Viking Helmet":
            root.addChildNode(sphereNode(CGFloat(w * 0.5), steel, seg: 20).scl(1, 0.75, 1.05).at(top.x, top.y - w * 0.05, top.z))
            for sx in [Float(-1), 1] { root.addChildNode(coneNode(CGFloat(w * 0.1), 0.004, CGFloat(w * 0.5), Mat.horn, seg: 10).rot(0, 0, -sx * 0.7).at(top.x + sx * w * 0.5, top.y + w * 0.2, top.z)) }
        case "Clown Nose":
            root.addChildNode(sphereNode(CGFloat(max(0.03, w * 0.12)), Coats.glossy(V3(0.9, 0.05, 0.05)), seg: 14).at(b.center.x, b.center.y - b.size.y * 0.05, b.max.z))
        case "Headphones":
            let band = SCNTorus(ringRadius: CGFloat(w * 0.55), pipeRadius: CGFloat(w * 0.04)); band.materials = [Mat.black]
            root.addChildNode(SCNNode(geometry: band).rot(0, 0, Float.pi / 2).scl(1, 1, 1).at(b.center.x, b.center.y + b.size.y * 0.15, b.center.z))
            for sx in [Float(-1), 1] { root.addChildNode(cylNode(CGFloat(w * 0.18), CGFloat(w * 0.12), cloth(V3(0.9, 0.2, 0.3)), seg: 16).rot(0, 0, Float.pi / 2).at(b.center.x + sx * w * 0.55, b.center.y, b.center.z)) }
        case "Halo":
            let h = SCNTorus(ringRadius: CGFloat(w * 0.4), pipeRadius: CGFloat(w * 0.04)); h.materials = [glow]
            let hn = SCNNode(geometry: h); hn.name = "bob"; hn.simdPosition = top + V3(0, w * 0.35, 0)
            root.addChildNode(hn)
        case "Propeller Cap":
            root.addChildNode(sphereNode(CGFloat(w * 0.45), Coats.coat(.bands, V3(0.95, 0.8, 0.1), V3(0.2, 0.4, 0.95)), seg: 16).scl(1, 0.55, 1).at(top.x, top.y, top.z))
            root.addChildNode(cylNode(CGFloat(w * 0.02), CGFloat(w * 0.18), Mat.black, seg: 6).at(top.x, top.y + w * 0.3, top.z))
            let prop = SCNNode(); prop.name = "spin"; prop.simdPosition = top + V3(0, w * 0.4, 0)
            for k in 0..<3 { prop.addChildNode(boxNode(CGFloat(w * 0.5), CGFloat(w * 0.01), CGFloat(w * 0.1), cloth(V3(0.9, 0.15, 0.1))).at(cosf(Float(k) * 2.094) * w * 0.25, 0, sinf(Float(k) * 2.094) * w * 0.25).rot(0, -Float(k) * 2.094, 0.2)) }
            root.addChildNode(prop)
        default: break
        }
        return root
    }

    // MARK: body

    static func buildBody(_ i: Int, on n: SCNNode) -> SCNNode {
        let root = SCNNode(); root.name = "addon"
        let b = box(n)
        let w = max(0.1, b.size.x), d = max(0.1, b.size.z), h = max(0.1, b.size.y)
        let c = b.center
        let back = V3(c.x, c.y + h * 0.1, b.min.z), front = V3(c.x, c.y + h * 0.25, b.max.z)
        switch body[i] {
        case "Hurt":
            for k in 0..<3 {
                let t = SCNTorus(ringRadius: CGFloat(max(w, d) * 0.5), pipeRadius: CGFloat(max(0.015, w * 0.04))); t.materials = [bandage]
                root.addChildNode(SCNNode(geometry: t).scl(w / max(w, d), 1, d / max(w, d)).at(c.x, b.min.y + h * (0.3 + Float(k) * 0.18), c.z).rot(0.1 * Float(k), 0, 0.15))
            }
            root.addChildNode(boxNode(CGFloat(w * 0.12), CGFloat(h * 0.6), CGFloat(w * 0.05), cloth(V3(0.85, 0.85, 0.9))).at(c.x + w * 0.2, c.y, b.max.z + 0.01).rot(0, 0, 0.6))
        case "Superhero Cape":
            let cape = SCNNode(); cape.name = "sway"; cape.simdPosition = V3(c.x, b.max.y - h * 0.05, b.min.z - 0.02)
            root.addChildNode(cape)
            let len = max(0.5, h * 1.3)
            cape.addChildNode(loftNode([Ring(V3(0, 0, 0), w * 0.45, 0.01), Ring(V3(0, -len * 0.5, -0.04), w * 0.6, 0.012), Ring(V3(0, -len, -0.08), w * 0.75, 0.012)],
                                       Coats.membrane(V3(0.8, 0.05, 0.08), alpha: 1), seg: 8, ref: V3(0, 0, 1), smooth: 2))
        case "Jetpack":
            let j = SCNNode(); j.simdPosition = back - V3(0, 0, 0.08)
            root.addChildNode(j)
            for sx in [Float(-1), 1] {
                j.addChildNode(cylNode(CGFloat(w * 0.14), CGFloat(h * 0.55), steel, seg: 14).at(sx * w * 0.16, 0, 0))
                j.addChildNode(coneNode(CGFloat(w * 0.14), CGFloat(w * 0.08), CGFloat(w * 0.15), Mat.black, seg: 12).at(sx * w * 0.16, -h * 0.34, 0))
                let f = coneNode(CGFloat(w * 0.09), 0.001, CGFloat(h * 0.35), flame, seg: 10).rot(Float.pi, 0, 0)
                f.name = "flame"; f.simdPosition = V3(sx * w * 0.16, -h * 0.58, 0)
                j.addChildNode(f)
            }
            j.addChildNode(boxNode(CGFloat(w * 0.2), CGFloat(h * 0.35), CGFloat(w * 0.1), cloth(V3(0.8, 0.1, 0.1))).at(0, 0, 0.02))
        case "Tutu":
            let t = SCNTube(innerRadius: CGFloat(max(w, d) * 0.4), outerRadius: CGFloat(max(w, d) * 0.85), height: CGFloat(h * 0.08)); t.radialSegmentCount = 30
            t.materials = [Coats.membrane(V3(1, 0.6, 0.8), alpha: 0.9)]
            root.addChildNode(SCNNode(geometry: t).at(c.x, b.min.y + h * 0.15, c.z).rot(0.05, 0, 0))
        case "Bow Tie":
            for sx in [Float(-1), 1] { root.addChildNode(coneNode(CGFloat(w * 0.12), 0.005, CGFloat(w * 0.2), cloth(V3(0.85, 0.1, 0.15)), seg: 8).rot(0, 0, -sx * Float.pi / 2).at(front.x + sx * w * 0.1, b.max.y - h * 0.12, front.z + 0.01)) }
            root.addChildNode(sphereNode(CGFloat(w * 0.05), cloth(V3(0.85, 0.1, 0.15)), seg: 8).at(front.x, b.max.y - h * 0.12, front.z + 0.02))
        case "Backpack":
            root.addChildNode(boxNode(CGFloat(w * 0.6), CGFloat(h * 0.5), CGFloat(max(0.08, d * 0.35)), cloth(V3(0.2, 0.45, 0.2)), chamfer: CGFloat(w * 0.08)).at(back.x, back.y, back.z - d * 0.12))
            root.addChildNode(boxNode(CGFloat(w * 0.5), CGFloat(h * 0.18), CGFloat(max(0.03, d * 0.12)), cloth(V3(0.15, 0.35, 0.15)), chamfer: CGFloat(w * 0.04)).at(back.x, back.y - h * 0.1, back.z - d * 0.32))
        case "Life Jacket":
            root.addChildNode(sphereNode(CGFloat(0.5), Coats.coat(.bands, V3(1, 0.45, 0.05), V3(0.95, 0.9, 0.85)), seg: 20).scl(w * 1.15, h * 0.75, d * 1.25).at(c.x, c.y + h * 0.1, c.z))
        case "Armor":
            root.addChildNode(sphereNode(CGFloat(0.5), steel, seg: 22).scl(w * 1.12, h * 0.9, d * 1.18).at(c.x, c.y + h * 0.05, c.z))
            root.addChildNode(sphereNode(CGFloat(w * 0.12), gold, seg: 10).scl(1, 1, 0.3).at(front.x, front.y, front.z + d * 0.08))
        case "Balloons":
            let bl = SCNNode(); bl.name = "bob"; bl.simdPosition = back + V3(0, h * 0.4, -0.05)
            root.addChildNode(bl)
            for k in 0..<3 {
                let dx = (Float(k) - 1) * 0.35, hy: Float = 1.5 + Float(k % 2) * 0.3
                bl.addChildNode(cylNode(0.004, CGFloat(hy), Coats.plain(V3(0.9, 0.9, 0.9)), seg: 4).rot(0, 0, -dx * 0.25).at(dx * 0.5, hy / 2, 0))
                bl.addChildNode(sphereNode(0.25, Coats.glossy([V3(0.9, 0.1, 0.1), V3(0.1, 0.4, 0.95), V3(1, 0.8, 0.1)][k]), seg: 16).scl(1, 1.2, 1).at(dx, hy + 0.25, 0))
            }
        case "Scarf":
            let t = SCNTorus(ringRadius: CGFloat(max(0.06, w * 0.3)), pipeRadius: CGFloat(max(0.025, w * 0.08))); t.materials = [Coats.coat(.bands, V3(0.9, 0.15, 0.1), V3(0.95, 0.9, 0.8))]
            root.addChildNode(SCNNode(geometry: t).at(c.x, b.max.y - h * 0.06, c.z))
            let tail = SCNNode(); tail.name = "sway"; tail.simdPosition = V3(c.x + w * 0.15, b.max.y - h * 0.08, b.max.z - d * 0.1)
            tail.addChildNode(boxNode(CGFloat(w * 0.15), CGFloat(h * 0.4), 0.02, Coats.coat(.bands, V3(0.9, 0.15, 0.1), V3(0.95, 0.9, 0.8))).at(0, -h * 0.2, 0))
            root.addChildNode(tail)
        case "Angel Wings":
            for sx in [Float(-1), 1] {
                let wg = SCNNode(); wg.name = sx < 0 ? "wingL" : "wingR"; wg.simdPosition = back + V3(sx * w * 0.15, h * 0.15, -0.03)
                root.addChildNode(wg)
                wg.addChildNode(sphereNode(CGFloat(max(0.2, h * 0.45)), Mat.whiteFeather, seg: 14).scl(1, 0.55, 0.12).at(sx * max(0.2, h * 0.4), h * 0.1, 0).rot(0, 0, sx * 0.4))
            }
        default: break
        }
        return root
    }

    // MARK: legs

    /// One piece per foot; `sole` is the foot's lowest point in its own space.
    static func buildFoot(_ i: Int, sole: Float, size: Float) -> SCNNode {
        let root = SCNNode(); root.name = "addon"
        let s = max(0.05, size)
        let y = sole
        switch legs[i] {
        case "Hurt":
            root.addChildNode(cylNode(CGFloat(s * 0.65), CGFloat(s * 1.6), Coats.plain(V3(0.95, 0.95, 0.93), rough: 0.9), seg: 14).at(0, y + s * 1.1, 0))
        case "Roller Skates", "Ice Skates":
            root.addChildNode(boxNode(CGFloat(s * 1.2), CGFloat(s * 0.35), CGFloat(s * 2.4), cloth(legs[i] == "Ice Skates" ? V3(0.95, 0.95, 0.95) : V3(0.9, 0.2, 0.5)), chamfer: CGFloat(s * 0.1)).at(0, y - s * 0.1, s * 0.3))
            if legs[i] == "Ice Skates" {
                root.addChildNode(boxNode(CGFloat(s * 0.06), CGFloat(s * 0.3), CGFloat(s * 2.6), steel).at(0, y - s * 0.4, s * 0.3))
            } else {
                for (zx, zz) in [(Float(-0.45), Float(-0.6)), (0.45, -0.6), (-0.45, 1.2), (0.45, 1.2)] { root.addChildNode(cylNode(CGFloat(s * 0.25), CGFloat(s * 0.18), cloth(V3(1, 0.9, 0.2)), seg: 12).rot(0, 0, Float.pi / 2).at(zx * s, y - s * 0.45, zz * s)) }
            }
        case "Spring Shoes":
            for k in 0..<4 {
                let t = SCNTorus(ringRadius: CGFloat(s * 0.45), pipeRadius: CGFloat(s * 0.07)); t.materials = [steel]
                root.addChildNode(SCNNode(geometry: t).at(0, y - s * (0.2 + Float(k) * 0.22), 0))
            }
            root.addChildNode(cylNode(CGFloat(s * 0.7), CGFloat(s * 0.12), Mat.rubber, seg: 14).at(0, y - s * 1.05, 0))
        case "Rocket Boots":
            root.addChildNode(cylNode(CGFloat(s * 0.7), CGFloat(s * 1.0), steel, seg: 14).at(0, y + s * 0.3, 0))
            let f = coneNode(CGFloat(s * 0.45), 0.001, CGFloat(s * 1.4), flame, seg: 10).rot(Float.pi, 0, 0)
            f.name = "flame"; f.simdPosition = V3(0, y - s * 0.9, 0); f.isHidden = true
            root.addChildNode(f)
        case "Rain Boots":
            root.addChildNode(cylNode(CGFloat(s * 0.72), CGFloat(s * 2.0), Coats.glossy(V3(0.95, 0.8, 0.05)), seg: 14).at(0, y + s * 0.9, 0))
        case "Socks":
            root.addChildNode(cylNode(CGFloat(s * 0.62), CGFloat(s * 1.8), Coats.coat(.bands, V3(0.95, 0.95, 0.95), V3(0.85, 0.15, 0.2)), seg: 14).at(0, y + s * 1.0, 0))
        case "Flippers":
            root.addChildNode(sphereNode(CGFloat(s * 1.6), Coats.glossy(V3(0.1, 0.6, 0.9)), seg: 14).scl(0.6, 0.08, 1).at(0, y + s * 0.05, s * 1.3))
        case "High Heels":
            root.addChildNode(cylNode(CGFloat(s * 0.12), CGFloat(s * 1.4), Coats.glossy(V3(0.85, 0.05, 0.15)), seg: 8).at(0, y - s * 0.5, -s * 0.5))
            root.addChildNode(boxNode(CGFloat(s * 1.0), CGFloat(s * 0.15), CGFloat(s * 2), Coats.glossy(V3(0.85, 0.05, 0.15)), chamfer: CGFloat(s * 0.05)).at(0, y + 0.02, s * 0.3).rot(-0.4, 0, 0))
        case "Stilts":
            root.addChildNode(cylNode(CGFloat(s * 0.2), 0.8, Mat.woodFresh, seg: 8).at(0, y - 0.4, 0))
            root.addChildNode(boxNode(CGFloat(s * 1.2), 0.04, CGFloat(s * 1.6), Mat.woodFresh).at(0, y, 0))
        case "Sneakers":
            root.addChildNode(boxNode(CGFloat(s * 1.2), CGFloat(s * 0.6), CGFloat(s * 2.2), cloth(V3(0.95, 0.95, 0.97)), chamfer: CGFloat(s * 0.25)).at(0, y + s * 0.2, s * 0.35))
            root.addChildNode(boxNode(CGFloat(s * 1.25), CGFloat(s * 0.18), CGFloat(s * 2.25), cloth(V3(0.1, 0.4, 0.9)), chamfer: CGFloat(s * 0.08)).at(0, y - s * 0.05, s * 0.35))
        default: break
        }
        return root
    }
}

extension Body {
    /// Rebuilds the add-on geometry on the current parts.
    func applyAddOns() {
        for n in addOnNodes { n.removeFromParentNode() }
        addOnNodes.removeAll()
        let h = addOns[0], t = addOns[1], l = addOns[2]
        if h > 0 {
            let a = head.anchor ?? head.node
            let n = AddOns.buildHead(h, on: a); a.addChildNode(n); addOnNodes.append(n)
        }
        if t > 0 {
            let a = torso.anchor ?? torso.node
            let n = AddOns.buildBody(t, on: a); a.addChildNode(n); addOnNodes.append(n)
        }
        if l > 0 {
            let feet = legs.footNodes
            if feet.isEmpty {
                let n = AddOns.buildFoot(l, sole: 0.02, size: 0.1 * max(0.5, legs.radius * 2)); n.simdPosition = V3(0, 0, 0)
                legs.node.addChildNode(n); addOnNodes.append(n)
            } else {
                for f in feet {
                    let b = AddOns.box(f)
                    let s = max(0.03, min(b.size.x, b.size.z) * 0.5)
                    let n = AddOns.buildFoot(l, sole: b.size.y > 0.001 ? b.min.y : -0.02, size: s)
                    f.addChildNode(n); addOnNodes.append(n)
                }
            }
        }
        for n in addOnNodes { n.castAll(true) }
        lift = AddOns.legs[l] == "Stilts" ? 0.8 : AddOns.legs[l] == "Spring Shoes" ? 0.25 : AddOns.legs[l] == "High Heels" ? 0.08 : AddOns.legs[l] == "Roller Skates" || AddOns.legs[l] == "Ice Skates" ? 0.12 : 0
    }

    func animateAddOns(_ p: Pose, dt: Float, boosting: Bool) {
        for root in addOnNodes {
            root.enumerateHierarchy { n, _ in
                switch n.name {
                case "spin": n.simdEulerAngles.y += dt * (p.glide > 0.1 ? 25 : 4)
                case "bob": n.simdPosition.y += sinf(p.t * 2) * 0.0015
                case "sway": n.simdEulerAngles = V3(0.25 + p.gait * 0.5 + p.run * 0.4 + p.air * 0.6 + sinf(p.t * 3) * 0.08, 0, 0)
                case "flame": n.isHidden = !boosting; n.simdScale = V3(1, 0.8 + 0.4 * sinf(p.t * 40), 1)
                case "wingL", "wingR":
                    let sd: Float = n.name == "wingL" ? -1 : 1
                    n.simdEulerAngles = V3(0, sd * 0.3, sd * (max(p.glide, p.flap, p.air * 0.4) * 0.6 + sinf(p.t * 20) * 0.5 * p.flap))
                default: break
                }
            }
        }
    }
}
