import SceneKit
import simd

enum Slot: Int, CaseIterable { case head = 0, torso = 1, legs = 2
    var name: String { ["Head", "Body", "Legs"][rawValue] }
}

struct Combo: Hashable {
    var head: Species, torso: Species, legs: Species
    subscript(_ s: Slot) -> Species {
        get { [head, torso, legs][s.rawValue] }
        set { switch s { case .head: head = newValue; case .torso: torso = newValue; case .legs: legs = newValue } }
    }
    var index: Int { head.id * 10000 + torso.id * 100 + legs.id }
    init(_ h: Species, _ t: Species, _ l: Species) { head = h; torso = t; legs = l }
    init(index i: Int) { self.init(Species(id: i / 10000 % 100 % Species.count), Species(id: i / 100 % 100 % Species.count), Species(id: i % 100 % Species.count)) }
    static var total: Int { Species.count * Species.count * Species.count }
    var isPure: Bool { head == torso && torso == legs }
    static let names = ["Human", "Drumstick Dan", "Cowtaur", "Birdman", "Chickenstein", "Feathertaur", "Beefcake", "Udderly Chicken", "Cowboy",
                        "Chickenhead", "Cluckster", "Chickentaur", "Hen Solo", "Chicken", "Cowlucker", "Rooster Beef", "Beef Nugget", "Chickow",
                        "Minotaur", "Mooster", "Mootaur", "Heifer-Hen", "Moo-Hen", "Featherbeef", "Bullman", "Chicken-Fried Steak", "Cow"]
    var name: String {
        if head.id < 3 && torso.id < 3 && legs.id < 3 { return Combo.names[head.id * 9 + torso.id * 3 + legs.id] }
        if isPure { return head.name }
        // a portmanteau: front of the head's name, middle of the body's, end of the legs'
        func clean(_ s: String) -> [Character] { Array(s.replacingOccurrences(of: " ", with: "").lowercased()) }
        let h = clean(head.name), t = clean(torso.name), l = clean(legs.name)
        var out = String(h.prefix(max(2, (h.count + 1) / 2)))
        if torso != head && torso != legs {
            let a = t.count / 3, b = max(a + 1, t.count * 2 / 3)
            out += String(t[a..<min(b, t.count)])
        }
        if legs != head { out += String(l.suffix(max(2, l.count / 2))) } else { out += String(h.suffix(max(2, h.count / 2))) }
        return out.prefix(1).uppercased() + out.dropFirst()
    }
    var recipe: String { "\(head.name) head · \(torso.name) body · \(legs.name) legs" }
}

/// Everything the animation needs to know about what the body is doing this frame.
struct Pose {
    var t: Float = 0            // seconds
    var phase: Float = 0        // gait cycles
    var gait: Float = 0         // 0 standing … 1 moving
    var run: Float = 0          // 0 walk … 1 run
    var air: Float = 0          // 0 grounded … 1 airborne
    var glide: Float = 0        // wings spread
    var flap: Float = 0         // flap envelope
    var carry: Float = 0        // holding something in the arms
    var throwT: Float = -1      // 0…1 while throwing
    var shove: Float = 0        // push / headbutt envelope
    var talk: Float = 0         // mouth open
    var eat: Float = 0          // head down pecking / grazing / munching
    var kick: Float = 0         // legs special envelope (buck, lay squat)
    var lay: Float = 0
    var climb: Float = 0
    var fallen: Float = 0       // knocked over (NPC farmer)
    var wave: Float = 0
    var scared: Float = 0
}

@inline(__always) func wave(_ phase: Float, _ off: Float) -> Float { sinf((phase + off) * 2 * .pi) }
@inline(__always) func wavec(_ phase: Float, _ off: Float) -> Float { cosf((phase + off) * 2 * .pi) }

class Part {
    let node = SCNNode()
    let species: Species
    init(_ s: Species) { species = s }
    func pose(_ p: Pose) {}
}

// MARK: - Outfits

struct Outfit {
    var shirt: SCNMaterial
    var sleeve: SCNMaterial
    var forearm: SCNMaterial
    var pants: SCNMaterial
    var boots: SCNMaterial
    var hair: SCNMaterial
    var hat = false
    var overalls = false
    var mustache = false
    var iris: SCNMaterial
    static var player: Outfit { Outfit(shirt: Mat.flannel, sleeve: Mat.flannel, forearm: Mat.skin, pants: Mat.denim, boots: Mat.leather, hair: Mat.brownHair, iris: Mat.irisBrown) }
    static var farmer: Outfit { Outfit(shirt: Mat.denim, sleeve: Mat.tee, forearm: Mat.skin, pants: Mat.denim, boots: Mat.leather, hair: Mat.greyHair, hat: true, overalls: true, mustache: true, iris: Mat.irisBlue) }
}

// MARK: - Legs

class LegsPart: Part {
    var footNodes: [SCNNode] = []
    /// Trunk for collisions: half-length along z, half-width, and where its centre sits on z.
    var trunkHalf: Float = 0
    var trunkWidth: Float = 0.3
    var trunkZ: Float = 0
    var attach = V3(0, 1, 0)
    var radius: Float = 0.3
    var stride: Float = 1.2          // metres per gait cycle
    var footPhases: [Float] = [0, 0.5]
    var mass: Float = 1
    func bob(_ p: Pose) -> Float { 0 }
    func pitch(_ p: Pose) -> Float { 0 }
}

final class HumanLegs: LegsPart {
    private var hips: [SCNNode] = [], knees: [SCNNode] = [], ankles: [SCNNode] = []
    init(_ o: Outfit) {
        super.init(.human)
        attach = V3(0, 1.03, 0); radius = 0.3; stride = 1.35; mass = 1
        let hipY: Float = 0.95
        node.add(loftNode([Ring(V3(0, 0.84, -0.01), 0.15, 0.1, e: 2.4), Ring(V3(0, 0.92, -0.015), 0.18, 0.12, e: 2.4), Ring(V3(0, 1.0, 0), 0.175, 0.115, e: 2.4),
                           Ring(V3(0, 1.06, 0), 0.165, 0.11, e: 2.4), Ring(V3(0, 1.08, 0), 0.1, 0.07)], o.pants, smooth: 3))
        node.add(loftNode([Ring(V3(0, 1.0, 0), 0.178, 0.118, e: 2.4), Ring(V3(0, 1.04, 0), 0.178, 0.118, e: 2.4)], o.boots, smooth: 1))
        for side in [Float(1), -1] {
            let hip = SCNNode(); hip.simdPosition = V3(0.095 * side, hipY, 0)
            node.add(hip)
            hip.add(limb(0.45, 0.088, 0.058, o.pants, depth: 1.05))
            let knee = SCNNode(); knee.simdPosition = V3(0, -0.45, 0)
            hip.add(knee)
            knee.add(limb(0.42, 0.056, 0.045, o.pants))
            let ankle = SCNNode(); ankle.simdPosition = V3(0, -0.42, 0)
            knee.add(ankle)
            ankle.add(cylNode(0.052, 0.12, o.boots).at(0, 0.0, 0))
            ankle.add(loftNode([Ring(V3(0, -0.035, -0.075), 0.03, 0.03), Ring(V3(0, -0.04, -0.055), 0.048, 0.045), Ring(V3(0, -0.045, 0.04), 0.052, 0.04),
                                Ring(V3(0, -0.05, 0.14), 0.048, 0.03), Ring(V3(0, -0.055, 0.2), 0.034, 0.022), Ring(V3(0, -0.058, 0.22), 0.012, 0.01)],
                               o.boots, ref: V3(0, 1, 0), smooth: 3))
            ankle.add(boxNode(0.1, 0.018, 0.29, Mat.rubber, chamfer: 0.008).at(0, -0.078, 0.07))
            hips.append(hip); knees.append(knee); ankles.append(ankle)
            footNodes.append(ankle)
        }
    }
    override func bob(_ p: Pose) -> Float { -abs(wave(p.phase, 0)) * (0.02 + 0.05 * p.run) * p.gait * (1 - p.air) - p.lay * 0.4 }
    override func pose(_ p: Pose) {
        for i in 0..<2 {
            let off: Float = i == 0 ? 0 : 0.5
            let s = wave(p.phase, off), c = wavec(p.phase, off)
            var hip = -s * (0.32 + 0.38 * p.run) * p.gait
            var knee = (0.08 + (0.35 + 1.0 * p.run) * max(0, c)) * p.gait + 0.04
            var ank = -(hip + knee) * 0.4 + (1 - p.gait) * -0.02
            // air: tuck
            hip = mixf(hip, i == 0 ? -0.7 : -0.25, p.air)
            knee = mixf(knee, i == 0 ? 1.1 : 0.6, p.air)
            ank = mixf(ank, -0.2, p.air)
            // squat
            hip = mixf(hip, -1.1, p.lay); knee = mixf(knee, 1.9, p.lay); ank = mixf(ank, -0.8, p.lay)
            // ladder
            let cs = wave(p.phase * 0.7, off)
            hip = mixf(hip, -0.7 - cs * 0.5, p.climb); knee = mixf(knee, 1.0 + cs * 0.4, p.climb)
            // fallen flat: legs splayed
            hip = mixf(hip, -0.2 + Float(i) * 0.3, p.fallen); knee = mixf(knee, 0.15, p.fallen)
            hips[i].simdEulerAngles = V3(hip, 0, (i == 0 ? 1 : -1) * 0.03)
            knees[i].simdEulerAngles = V3(knee, 0, 0)
            ankles[i].simdEulerAngles = V3(ank, 0, 0)
        }
    }
}

final class ChickenLegs: LegsPart {
    private var thighs: [SCNNode] = [], hocks: [SCNNode] = [], feet: [SCNNode] = [], toes: [[SCNNode]] = []
    let fluff = SCNNode()
    init(white: Bool = false) {
        super.init(.chicken)
        attach = V3(0, 0.74, -0.02); radius = 0.3; stride = 0.62; mass = 0.35
        let body = white ? Mat.whiteFeather : Mat.henBody
        node.add(fluff)
        fluff.add(loftNode([Ring(V3(0, 0.34, -0.1), 0.02, 0.02), Ring(V3(0, 0.38, -0.08), 0.15, 0.15), Ring(V3(0, 0.5, -0.05), 0.24, 0.24),
                            Ring(V3(0, 0.63, -0.03), 0.25, 0.24), Ring(V3(0, 0.74, -0.02), 0.21, 0.2), Ring(V3(0, 0.8, -0.02), 0.15, 0.14)], body, smooth: 4,
                           displace: { _, _, u, v in 0.012 * sinf(u * 2 * .pi * 9 + v * 5) }))
        for side in [Float(1), -1] {
            let thigh = SCNNode(); thigh.simdPosition = V3(0.1 * side, 0.52, 0.0)
            fluff.add(thigh)
            thigh.add(limb(0.2, 0.075, 0.04, body, bulge: 0.25))
            let hock = SCNNode(); hock.simdPosition = V3(0, -0.2, 0)
            thigh.add(hock)
            hock.add(limb(0.31, 0.026, 0.021, Mat.scales))
            let foot = SCNNode(); foot.simdPosition = V3(0, -0.31, 0)
            hock.add(foot)
            var ts: [SCNNode] = []
            for (k, a) in [Float(-0.45), 0, 0.45].enumerated() {
                let toe = SCNNode(); toe.simdEulerAngles = V3(0, a, 0)
                foot.add(toe)
                let len: Float = k == 1 ? 0.14 : 0.11
                toe.add(limb(len, 0.017, 0.011, Mat.scales, dir: V3(0, -0.15, 1)))
                toe.add(coneNode(0.009, 0.001, 0.035, Mat.claw, seg: 8).rot(Float.pi / 2, 0, 0).at(0, -len * 0.15, len + 0.01))
                ts.append(toe)
            }
            let back = SCNNode(); back.simdEulerAngles = V3(0, .pi, 0)
            foot.add(back)
            back.add(limb(0.05, 0.014, 0.01, Mat.scales, dir: V3(0, -0.4, 1)))
            thighs.append(thigh); hocks.append(hock); feet.append(foot); toes.append(ts)
            footNodes.append(foot)
        }
    }
    override func bob(_ p: Pose) -> Float { -abs(wave(p.phase, 0)) * 0.03 * p.gait * (1 - p.air) - p.lay * 0.2 }
    override func pose(_ p: Pose) {
        fluff.simdEulerAngles = V3(p.run * 0.15 * p.gait, 0, 0)
        for i in 0..<2 {
            let off: Float = i == 0 ? 0 : 0.5
            let s = wave(p.phase, off), c = wavec(p.phase, off)
            var th = -0.5 - s * (0.38 + 0.3 * p.run) * p.gait
            var hk = 0.8 + max(0, c) * (0.6 + 0.6 * p.run) * p.gait
            th = mixf(th, -1.0, p.air); hk = mixf(hk, 1.7, p.air)
            th = mixf(th, -1.25, p.lay); hk = mixf(hk, 2.1, p.lay)
            th = mixf(th, -0.3 + Float(i) * 0.4, p.fallen)
            thighs[i].simdEulerAngles = V3(th, 0, 0)
            hocks[i].simdEulerAngles = V3(hk, 0, 0)
            var fr = -(th + hk)
            // toes curl while the foot swings and in the air
            let curl = max(max(0, c) * p.gait, p.air) * 0.8
            fr += curl * 0.3
            feet[i].simdEulerAngles = V3(fr, 0, 0)
            for (k, t) in toes[i].enumerated() { t.simdEulerAngles = V3(curl, [-0.45, 0, 0.45][k] * (1 - curl * 0.5), 0) }
        }
    }
}

final class CowLegs: LegsPart {
    private var uppers: [SCNNode] = [], lowers: [SCNNode] = [], hooves: [SCNNode] = []
    private let tail = SCNNode(), tailMid = SCNNode(), udder = SCNNode()
    let barrel = SCNNode()
    // LH, RH, LF, RF
    private let walkOff: [Float] = [0, 0.5, 0.25, 0.75]
    private let gallopOff: [Float] = [0, 0.1, 0.45, 0.58]
    init() {
        super.init(.cow)
        attach = V3(0, 1.2, 0.6); radius = 0.62; stride = 1.7; mass = 3
        trunkHalf = 0.8; trunkWidth = 0.42; trunkZ = 0
        footPhases = [0, 0.25, 0.5, 0.75]
        node.add(barrel)
        let rings = [Ring(V3(0, 1.13, -0.8), 0.06, 0.06), Ring(V3(0, 1.12, -0.74), 0.25, 0.25), Ring(V3(0, 1.1, -0.58), 0.34, 0.32, e: 2.2), Ring(V3(0, 1.05, -0.25), 0.37, 0.37),
                     Ring(V3(0, 1.02, 0.1), 0.39, 0.39), Ring(V3(0, 1.04, 0.4), 0.37, 0.36), Ring(V3(0, 1.1, 0.66), 0.3, 0.3), Ring(V3(0, 1.15, 0.8), 0.1, 0.1)]
        barrel.add(loftNode(rings, Mat.hide, seg: 28, ref: V3(0, 1, 0), smooth: 4, vScale: 0.7) { p, n, _, _ in
            // hip bones and pin bones push through the hide
            var d: Float = 0
            for hx in [Float(0.22), -0.22] {
                let q = p - V3(hx, 1.34, -0.5)
                d += expf(-simd_length_squared(q) * 90) * 0.05
                let r = p - V3(hx * 0.6, 1.24, -0.74)
                d += expf(-simd_length_squared(r) * 160) * 0.03
            }
            // spine ridge
            d += expf(-p.x * p.x * 300) * max(0, n.y) * 0.02
            return d
        })
        // tail
        tail.simdPosition = V3(0, 1.3, -0.74)
        barrel.add(tail)
        tail.add(limb(0.38, 0.035, 0.024, Mat.hide, dir: V3(0, -0.6, -0.4)))
        tailMid.simdPosition = V3(0, -0.32, -0.21)
        tail.add(tailMid)
        tailMid.add(limb(0.4, 0.022, 0.016, Mat.hide))
        tailMid.add(sphereNode(0.05, Mat.brownHair, seg: 12).scl(0.9, 2.6, 0.9).at(0, -0.46, 0))
        // udder
        udder.simdPosition = V3(0, 0.74, -0.28)
        barrel.add(udder)
        udder.add(sphereNode(0.14, Mat.cowSkin).scl(1.1, 0.8, 1.35))
        for (x, z) in [(Float(0.06), Float(0.08)), (-0.06, 0.08), (0.06, -0.08), (-0.06, -0.08)] {
            udder.add(limb(0.07, 0.016, 0.013, Mat.cowSkin).at(x, -0.08, z))
        }
        for (k, (x, z)) in [(Float(0.2), Float(-0.52)), (-0.2, -0.52), (0.2, 0.55), (-0.2, 0.55)].enumerated() {
            let hind = k < 2
            let up = SCNNode(); up.simdPosition = V3(x, 0.93, z)
            barrel.add(up)
            up.add(limb(0.42, hind ? 0.1 : 0.085, 0.055, Mat.hide, depth: hind ? 1.5 : 1.15, bulge: 0.2))
            let lo = SCNNode(); lo.simdPosition = V3(0, -0.42, 0)
            up.add(lo)
            lo.add(limb(0.4, 0.045, 0.038, Mat.hide))
            let hf = SCNNode(); hf.simdPosition = V3(0, -0.4, 0)
            lo.add(hf)
            hf.add(sphereNode(0.05, Mat.hide, seg: 14).scl(1, 0.9, 1.1))
            hf.add(coneNode(0.062, 0.048, 0.08, Mat.hoof).at(0, -0.055, 0.012))
            hf.add(boxNode(0.006, 0.07, 0.12, Mat.black).at(0, -0.06, 0.02))
            uppers.append(up); lowers.append(lo); hooves.append(hf)
            footNodes.append(hf)
        }
    }
    override func bob(_ p: Pose) -> Float {
        let walk = -abs(wave(p.phase * 2, 0)) * 0.025
        let gallop = wave(p.phase, 0.3) * 0.08
        return mixf(walk, gallop, p.run) * p.gait * (1 - p.air)
    }
    override func pitch(_ p: Pose) -> Float { wave(p.phase, 0.1) * 0.07 * p.run * p.gait + p.kick * 0.28 }
    override func pose(_ p: Pose) {
        for k in 0..<4 {
            let hind = k < 2
            let off = mixf(walkOff[k], gallopOff[k], p.run)
            let s = wave(p.phase, off), c = wavec(p.phase, off)
            let amp = (0.3 + 0.35 * p.run) * p.gait
            var u = -s * amp
            var l = max(0, c) * (0.5 + 0.7 * p.run) * p.gait
            if hind { u += 0.08; l = -l * 0.9 - 0.12 } else { u -= 0.02 }
            // air: fold legs
            u = mixf(u, hind ? 0.5 : -0.5, p.air * 0.7)
            l = mixf(l, hind ? -0.8 : 1.1, p.air * 0.7)
            // buck: hind legs lash out backwards
            if hind { u = mixf(u, 1.2, p.kick); l = mixf(l, 0.2, p.kick) }
            // lying down to be milked / knocked over
            u = mixf(u, hind ? 0.9 : -0.9, p.lay); l = mixf(l, hind ? -2.2 : 2.3, p.lay)
            uppers[k].simdEulerAngles = V3(u, 0, 0)
            lowers[k].simdEulerAngles = V3(l, 0, 0)
            hooves[k].simdEulerAngles = V3(-(u + l) * 0.6, 0, 0)
        }
        let swish = sinf(p.t * 1.7) * 0.35 + sinf(p.t * 4.3) * 0.08
        tail.simdEulerAngles = V3(p.run * 0.9 * p.gait + p.kick * 0.6, 0, swish)
        tailMid.simdEulerAngles = V3(p.run * 0.6 * p.gait, 0, swish * 0.8)
        udder.simdEulerAngles = V3(wave(p.phase * 2, 0.2) * 0.08 * p.gait, 0, 0)
    }
}

// MARK: - Torsos

class TorsoPart: Part {
    var anchor: SCNNode?
    var neck = V3(0, 0.6, 0)
    var neckRot: Float = 0          // extra pitch for whatever head sits here
    var canGrab = false
    var hasWings = false
    var flight = 0          // 0 none, 1 flap and glide, 2 hover
    var carry = V3(0, 0.3, 0.4)     // where held things sit, torso space
    var mass: Float = 1
    var tilt: Float = 0
}

final class HumanTorso: TorsoPart {
    private var shoulders: [SCNNode] = [], elbows: [SCNNode] = [], hands: [SCNNode] = []
    let chest = SCNNode()
    init(_ o: Outfit) {
        super.init(.human)
        neck = V3(0, 0.575, 0.0); canGrab = true; carry = V3(0, 0.28, 0.4); mass = 1
        node.add(chest)
        anchor = chest
        chest.add(loftNode([Ring(V3(0, -0.07, 0), 0.165, 0.108, e: 2.4), Ring(V3(0, 0.05, 0), 0.16, 0.105, e: 2.4), Ring(V3(0, 0.2, 0.005), 0.178, 0.118, e: 2.4),
                            Ring(V3(0, 0.34, 0.012), 0.198, 0.13, e: 2.5), Ring(V3(0, 0.46, 0.0), 0.205, 0.118, e: 2.6), Ring(V3(0, 0.53, -0.005), 0.16, 0.1, e: 2.4),
                            Ring(V3(0, 0.585, 0), 0.075, 0.068), Ring(V3(0, 0.61, 0), 0.058, 0.055)], o.shirt, seg: 26, smooth: 4))
        if o.overalls {
            // bib over a white tee, with brass buttons on the straps
            chest.add(loftNode([Ring(V3(0, 0.3, 0.02), 0.175, 0.13, e: 2.5), Ring(V3(0, 0.46, 0.005), 0.21, 0.122, e: 2.6), Ring(V3(0, 0.53, -0.005), 0.165, 0.104, e: 2.4),
                                Ring(V3(0, 0.585, 0), 0.08, 0.072), Ring(V3(0, 0.6, 0), 0.06, 0.058)], Mat.tee, seg: 26, smooth: 3))
            for sx in [Float(0.09), -0.09] {
                chest.add(boxNode(0.04, 0.3, 0.015, Mat.denim).at(sx, 0.42, 0.105).rot(-0.2, 0, 0))
                chest.add(cylNode(0.012, 0.01, Mat.galv, seg: 10).rot(Float.pi / 2, 0, 0).at(sx, 0.32, 0.135))
            }
        } else {
            // shirt buttons and a pocket
            for k in 0..<4 { chest.add(cylNode(0.007, 0.005, Mat.whiteTrim, seg: 8).rot(Float.pi / 2, 0, 0).at(0, 0.12 + Float(k) * 0.11, 0.123 + (k == 2 ? 0.008 : 0))) }
            chest.add(boxNode(0.08, 0.09, 0.01, o.shirt).at(0.09, 0.38, 0.13))
        }
        for side in [Float(1), -1] {
            let sh = SCNNode(); sh.simdPosition = V3(0.19 * side, 0.475, -0.005)
            chest.add(sh)
            sh.add(sphereNode(0.058, o.sleeve, seg: 16).scl(1, 1.1, 1))
            sh.add(limb(0.29, 0.058, 0.046, o.sleeve))
            let el = SCNNode(); el.simdPosition = V3(0, -0.29, 0)
            sh.add(el)
            el.add(limb(0.26, 0.043, 0.032, o.forearm))
            if o.sleeve !== o.forearm { el.add(cylNode(0.05, 0.06, o.sleeve, seg: 14).at(0, -0.01, 0)) }
            let hand = SCNNode(); hand.simdPosition = V3(0, -0.26, 0)
            el.add(hand)
            hand.add(loftNode([Ring(V3(0, 0.005, 0), 0.03, 0.02), Ring(V3(0, -0.03, 0.002), 0.042, 0.018, e: 2.6), Ring(V3(0, -0.075, 0.005), 0.042, 0.016, e: 2.6),
                               Ring(V3(0, -0.11, 0.012), 0.035, 0.013, e: 2.4), Ring(V3(0, -0.125, 0.015), 0.01, 0.008)], Mat.skin, seg: 14, smooth: 3))
            hand.add(limb(0.055, 0.012, 0.009, Mat.skin, dir: V3(-side * 0.3, -0.7, 0.6)).at(-side * 0.03, -0.03, 0.015))
            shoulders.append(sh); elbows.append(el); hands.append(hand)
        }
    }
    override func pose(_ p: Pose) {
        for i in 0..<2 {
            let side: Float = i == 0 ? 1 : -1
            let off: Float = i == 0 ? 0.5 : 0
            let s = wave(p.phase, off)
            var sx = -s * (0.28 + 0.55 * p.run) * p.gait
            var sz = side * 0.07
            var ex = -(0.12 + 0.9 * p.run * p.gait)
            // flail in the air
            sz = mixf(sz, side * 0.55, p.air * 0.7); sx = mixf(sx, -0.3, p.air * 0.5)
            // carrying: both hands out in front
            sx = mixf(sx, -1.15, p.carry); sz = mixf(sz, -side * 0.28, p.carry); ex = mixf(ex, -0.55, p.carry)
            // push
            sx = mixf(sx, -1.5, p.shove); ex = mixf(ex, -0.1, p.shove); sz = mixf(sz, -side * 0.1, p.shove)
            // ladder: hand over hand
            let cs = wave(p.phase * 0.7, off)
            sx = mixf(sx, -2.6 - cs * 0.35, p.climb); ex = mixf(ex, -0.4 + cs * 0.3, p.climb); sz = mixf(sz, -side * 0.05, p.climb)
            // throwing arm (right)
            if p.throwT >= 0 && i == 1 {
                let t = p.throwT
                let wind = smoothstep(0, 0.35, t), rel = smoothstep(0.35, 0.6, t), rest = smoothstep(0.7, 1, t)
                sx = mixf(mixf(sx, -2.7, wind), -0.7, rel)
                sx = mixf(sx, 0, rest * 0.3)
                ex = mixf(ex, -1.2, wind * (1 - rel))
            }
            // talking hands
            if p.talk > 0 && p.carry < 0.5 && i == 1 { sx += -0.35 * p.talk * (0.6 + 0.4 * sinf(p.t * 7)); ex -= 0.6 * p.talk }
            // waving
            if p.wave > 0 && i == 1 { sx = mixf(sx, -0.3, p.wave); sz = mixf(sz, -2.5, p.wave); ex = mixf(ex, -0.3 + sinf(p.t * 10) * 0.4, p.wave) }
            // scared: hands up
            sx = mixf(sx, -2.5, p.scared); sz = mixf(sz, side * 0.5, p.scared); ex = mixf(ex, -0.8, p.scared)
            // lying flat
            sx = mixf(sx, -2.8, p.fallen); sz = mixf(sz, side * 0.8, p.fallen)
            shoulders[i].simdEulerAngles = V3(sx, 0, sz)
            elbows[i].simdEulerAngles = V3(ex, 0, 0)
            hands[i].simdEulerAngles = V3(0, 0, 0)
        }
        chest.simdEulerAngles = V3(0, wave(p.phase, 0) * 0.08 * p.gait, 0)
    }
}

final class ChickenTorso: TorsoPart {
    private var wings: [SCNNode] = [], primaries: [[SCNNode]] = []
    private let tail = SCNNode()
    init(white: Bool = false) {
        super.init(.chicken)
        neck = V3(0, 0.56, 0.05); hasWings = true; flight = 1; carry = V3(0, 0.1, 0.45); mass = 0.35
        let body = white ? Mat.whiteFeather : Mat.henBody, wing = white ? Mat.whiteFeather : Mat.henWing
        node.add(loftNode([Ring(V3(0, -0.08, -0.02), 0.2, 0.19), Ring(V3(0, 0.07, 0.01), 0.25, 0.25), Ring(V3(0, 0.22, 0.05), 0.26, 0.27),
                           Ring(V3(0, 0.36, 0.06), 0.22, 0.22), Ring(V3(0, 0.47, 0.05), 0.14, 0.14), Ring(V3(0, 0.56, 0.05), 0.085, 0.085), Ring(V3(0, 0.6, 0.05), 0.07, 0.07)],
                          body, seg: 26, smooth: 4, displace: { _, _, u, v in 0.008 * sinf(u * 2 * .pi * 11 + v * 9) }))
        for side in [Float(1), -1] {
            let w = SCNNode(); w.simdPosition = V3(0.21 * side, 0.42, -0.01)
            node.add(w)
            // folded wing: a thick feathered paddle hanging down and back
            w.add(loftNode([Ring(V3(0, 0.04, 0.02), 0.03, 0.07), Ring(V3(0, -0.06, 0.0), 0.05, 0.13), Ring(V3(0, -0.2, -0.05), 0.045, 0.14),
                            Ring(V3(0, -0.33, -0.1), 0.03, 0.1), Ring(V3(0, -0.42, -0.15), 0.012, 0.04)], wing, seg: 18, ref: V3(0, 0, 1), smooth: 3))
            var ps: [SCNNode] = []
            for k in 0..<6 {
                let f = SCNNode()
                f.simdPosition = V3(0, -0.3 - Float(k) * 0.015, -0.08 + Float(k) * 0.035)
                w.add(f)
                let len: Float = 0.3 - Float(k) * 0.025
                f.add(loftNode([Ring(V3(0, 0, 0), 0.006, 0.02), Ring(V3(0, -len * 0.3, 0), 0.007, 0.034), Ring(V3(0, -len * 0.8, 0), 0.005, 0.028), Ring(V3(0, -len, 0.01), 0.002, 0.006)],
                               Mat.tailFeather, seg: 10, smooth: 3))
                ps.append(f)
            }
            wings.append(w); primaries.append(ps)
        }
        tail.simdPosition = V3(0, 0.08, -0.2)
        node.add(tail)
        for k in 0..<7 {
            let a = (Float(k) - 3) * 0.2
            let f = SCNNode(); f.simdEulerAngles = V3(0, 0, a)
            tail.add(f)
            let sickle = k == 2 || k == 4
            let len: Float = sickle ? 0.5 : 0.34
            f.add(loftNode([Ring(V3(0, 0, 0), 0.03, 0.01), Ring(V3(0, len * 0.4, -len * 0.3), 0.045, 0.012), Ring(V3(0, len * 0.75, -len * 0.45), 0.04, 0.01),
                            Ring(V3(0, len * (sickle ? 0.85 : 1), -len * (sickle ? 0.8 : 0.5)), 0.01, 0.004)], Mat.tailFeather, seg: 10, ref: V3(0, 0, 1), smooth: 3))
        }
    }
    override func pose(_ p: Pose) {
        let spread = max(p.glide, min(1, p.flap * 1.5), p.air * 0.25, p.run * p.gait * 0.25, p.shove)
        for i in 0..<2 {
            let side: Float = i == 0 ? 1 : -1
            let beat = sinf(p.t * 24) * 0.75 * max(p.flap, p.shove)
            let lift = spread * 1.45 + beat - p.glide * sinf(p.t * 3) * 0.05
            wings[i].simdEulerAngles = V3(0.15 - spread * 0.1, side * spread * 0.2, side * lift)
            wings[i].simdScale = V3(1 + spread * 0.3, 1 + spread * 0.55, 1 + spread * 0.35)
            for (k, f) in primaries[i].enumerated() {
                let fan = spread * (Float(k) * 0.12)
                f.simdEulerAngles = V3(-fan, 0, 0)
            }
        }
        tail.simdEulerAngles = V3(-0.2 - p.glide * 0.35, wave(p.phase, 0) * 0.08 * p.gait, sinf(p.t * 2) * 0.03)
    }
}

final class CowTorso: TorsoPart {
    private var shoulders: [SCNNode] = [], knees: [SCNNode] = []
    let quadruped: Bool
    init(quadruped: Bool) {
        self.quadruped = quadruped
        super.init(.cow)
        mass = 3
        if quadruped {
            // Continues the barrel forward into the chest and neck of a real cow.
            node.add(loftNode([Ring(V3(0, -0.2, -0.14), 0.36, 0.37), Ring(V3(0, -0.1, 0.1), 0.32, 0.35), Ring(V3(0, 0.02, 0.28), 0.22, 0.26),
                               Ring(V3(0, 0.12, 0.42), 0.15, 0.2), Ring(V3(0, 0.18, 0.52), 0.12, 0.15)], Mat.hide, seg: 26, ref: V3(0, 1, 0), smooth: 4, vScale: 0.7))
            // dewlap
            node.add(loftNode([Ring(V3(0, -0.32, 0.12), 0.02, 0.02), Ring(V3(0, -0.22, 0.28), 0.045, 0.1), Ring(V3(0, -0.08, 0.42), 0.04, 0.08), Ring(V3(0, 0.02, 0.5), 0.02, 0.02)],
                              Mat.hide, seg: 12, ref: V3(0, 1, 0), smooth: 3))
            neck = V3(0, 0.12, 0.44); neckRot = 0.62
        } else {
            node.add(loftNode([Ring(V3(0, -0.1, 0), 0.3, 0.28), Ring(V3(0, 0.1, 0.01), 0.34, 0.3), Ring(V3(0, 0.3, 0.035), 0.36, 0.31),
                               Ring(V3(0, 0.48, 0.03), 0.32, 0.27), Ring(V3(0, 0.62, 0.05), 0.22, 0.2), Ring(V3(0, 0.72, 0.07), 0.15, 0.15), Ring(V3(0, 0.77, 0.07), 0.13, 0.13)],
                              Mat.hide, seg: 26, smooth: 4, vScale: 0.7))
            node.add(loftNode([Ring(V3(0, 0.3, 0.2), 0.02, 0.02), Ring(V3(0, 0.45, 0.26), 0.05, 0.06), Ring(V3(0, 0.62, 0.22), 0.045, 0.05), Ring(V3(0, 0.72, 0.16), 0.02, 0.02)],
                              Mat.hide, seg: 12, smooth: 3))
            neck = V3(0, 0.75, 0.07)
            for side in [Float(1), -1] {
                let sh = SCNNode(); sh.simdPosition = V3(0.31 * side, 0.58, 0.02)
                node.add(sh)
                sh.add(sphereNode(0.1, Mat.hide, seg: 16))
                sh.add(limb(0.36, 0.09, 0.06, Mat.hide, depth: 1.2, bulge: 0.2))
                let kn = SCNNode(); kn.simdPosition = V3(0, -0.36, 0)
                sh.add(kn)
                kn.add(limb(0.33, 0.045, 0.038, Mat.hide))
                kn.add(sphereNode(0.05, Mat.hide, seg: 12).at(0, -0.33, 0))
                kn.add(coneNode(0.062, 0.048, 0.08, Mat.hoof).at(0, -0.39, 0.01))
                kn.add(boxNode(0.006, 0.07, 0.12, Mat.black).at(0, -0.39, 0.02))
                shoulders.append(sh); knees.append(kn)
            }
        }
    }
    override func pose(_ p: Pose) {
        guard !quadruped else { return }
        for i in 0..<2 {
            let side: Float = i == 0 ? 1 : -1
            let s = wave(p.phase, i == 0 ? 0.5 : 0)
            var sx = -s * (0.25 + 0.4 * p.run) * p.gait
            var kx = -(0.1 + 0.5 * p.run * p.gait)
            var sz = side * 0.1
            sz = mixf(sz, side * 0.5, p.air * 0.7)
            sx = mixf(sx, -1.6, p.shove); kx = mixf(kx, 0, p.shove)
            sx = mixf(sx, -0.9, p.carry)
            sx = mixf(sx, -2.4 - s * 0.3, p.climb)
            if p.talk > 0 { sx -= 0.2 * p.talk }
            shoulders[i].simdEulerAngles = V3(sx, 0, sz)
            knees[i].simdEulerAngles = V3(kx, 0, 0)
        }
    }
}

// MARK: - Heads

class HeadPart: Part {
    var anchor: SCNNode?
    var height: Float = 0.35
    var mouth = V3(0, 0.2, 0.1)     // head-part space, for eating/voice effects
}

final class HumanHead: HeadPart {
    private let skull = SCNNode(), mouthOpen = SCNNode(), jawNode = SCNNode()
    private var lids: [SCNNode] = []
    private var blinkT: Float = 2
    init(_ o: Outfit) {
        super.init(.human)
        height = 0.36; mouth = V3(0, 0.14, 0.1)
        anchor = skull
        node.add(limb(0.09, 0.056, 0.058, Mat.skin, dir: V3(0, 1, 0.08)))
        skull.simdPosition = V3(0, 0.055, 0.012)
        node.add(skull)
        skull.add(loftNode([Ring(V3(0, -0.005, 0.03), 0.02, 0.02), Ring(V3(0, 0.02, 0.035), 0.055, 0.065), Ring(V3(0, 0.06, 0.012), 0.078, 0.092),
                            Ring(V3(0, 0.12, 0.0), 0.088, 0.1), Ring(V3(0, 0.18, -0.005), 0.09, 0.104), Ring(V3(0, 0.235, -0.012), 0.08, 0.095),
                            Ring(V3(0, 0.275, -0.018), 0.05, 0.062), Ring(V3(0, 0.292, -0.02), 0.01, 0.01)], Mat.skin, seg: 28, smooth: 4) { p, _, _, _ in
            // brow ridge and cheekbones
            var d: Float = 0
            d += expf(-powf((p.y - 0.165) * 45, 2)) * max(0, p.z - 0.06) * 0.12
            for cx in [Float(0.055), -0.055] { d += expf(-(powf((p.x - cx) * 30, 2) + powf((p.y - 0.11) * 30, 2))) * max(0, p.z) * 0.08 }
            // eye sockets
            for cx in [Float(0.036), -0.036] { d -= expf(-(powf((p.x - cx) * 45, 2) + powf((p.y - 0.142) * 50, 2))) * max(0, p.z - 0.05) * 0.18 }
            return d
        })
        // nose
        skull.add(loftNode([Ring(V3(0, 0.15, 0.09), 0.008, 0.008), Ring(V3(0, 0.13, 0.1), 0.01, 0.01), Ring(V3(0, 0.108, 0.108), 0.016, 0.013),
                            Ring(V3(0, 0.098, 0.1), 0.015, 0.01), Ring(V3(0, 0.095, 0.092), 0.004, 0.004)], Mat.skin, seg: 14, ref: V3(0, 0, 1), smooth: 3))
        // ears
        for sx in [Float(1), -1] {
            skull.add(sphereNode(0.03, Mat.skin, seg: 14).scl(0.35, 1.05, 0.7).at(0.09 * sx, 0.135, -0.01).rot(0, sx * 0.3, 0))
        }
        // eyes
        for sx in [Float(1), -1] {
            let e = SCNNode(); e.simdPosition = V3(0.035 * sx, 0.143, 0.079)
            skull.add(e)
            e.add(sphereNode(0.0145, Mat.eyeWhite, seg: 16))
            e.add(sphereNode(0.0072, o.iris, seg: 14).scl(1, 1, 0.35).at(0, 0, 0.0128))
            e.add(sphereNode(0.0036, Mat.eyeBlack, seg: 10).scl(1, 1, 0.35).at(0, 0, 0.0142))
            let lid = sphereNode(0.0158, Mat.skin, seg: 16)
            lid.simdScale = V3(1, 0.05, 1)
            lid.simdPosition = V3(0, 0.012, 0)
            e.add(lid)
            lids.append(lid)
            skull.add(boxNode(0.034, 0.006, 0.012, o.hair, chamfer: 0.003).at(0.037 * sx, 0.168, 0.09).rot(0, 0, sx * -0.08))
        }
        // mouth
        skull.add(boxNode(0.042, 0.005, 0.01, Mat.lip, chamfer: 0.002).at(0, 0.071, 0.085))
        mouthOpen.simdPosition = V3(0, 0.066, 0.08)
        skull.add(mouthOpen)
        mouthOpen.add(sphereNode(0.022, Mat.mouthDark, seg: 12).scl(1, 0.2, 0.45))
        // hair
        skull.add(loftNode([Ring(V3(0, 0.155, -0.035), 0.095, 0.1), Ring(V3(0, 0.2, -0.012), 0.097, 0.112), Ring(V3(0, 0.25, -0.016), 0.085, 0.1),
                            Ring(V3(0, 0.285, -0.02), 0.058, 0.07), Ring(V3(0, 0.305, -0.022), 0.01, 0.01)], o.hair, seg: 26, smooth: 3) { p, _, _, _ in
            // cut away the face below the hairline
            p.z > 0.04 && p.y < 0.2 ? -0.04 : 0.004
        })
        if o.mustache {
            skull.add(loftNode([Ring(V3(-0.035, 0.078, 0.086), 0.003, 0.003), Ring(V3(-0.015, 0.085, 0.098), 0.009, 0.007), Ring(V3(0, 0.086, 0.1), 0.01, 0.007),
                                Ring(V3(0.015, 0.085, 0.098), 0.009, 0.007), Ring(V3(0.035, 0.078, 0.086), 0.003, 0.003)], o.hair, seg: 10, ref: V3(0, 1, 0), smooth: 3))
        }
        if o.hat {
            let hat = SCNNode(); hat.simdPosition = V3(0, 0.23, -0.01)
            skull.add(hat)
            let brim = SCNTube(innerRadius: 0.1, outerRadius: 0.2, height: 0.012)
            brim.radialSegmentCount = 36; brim.materials = [Mat.straw]
            hat.add(SCNNode(geometry: brim).rot(-0.08, 0, 0))
            hat.add(loftNode([Ring(V3(0, -0.01, 0), 0.105, 0.115), Ring(V3(0, 0.06, 0), 0.1, 0.11), Ring(V3(0, 0.1, 0), 0.085, 0.09), Ring(V3(0, 0.11, 0), 0.02, 0.02)],
                             Mat.straw, seg: 24, smooth: 2))
            hat.add(loftNode([Ring(V3(0, 0.0, 0), 0.107, 0.117), Ring(V3(0, 0.025, 0), 0.107, 0.117)], Mat.leather, seg: 24, smooth: 1))
        }
    }
    override func pose(_ p: Pose) {
        let open = p.talk * (0.5 + 0.5 * abs(sinf(p.t * 17))) + p.eat * abs(sinf(p.t * 9)) * 0.6 + p.scared * 0.9
        mouthOpen.simdScale = V3(1, 0.2 + open * 3.2, 1)
        skull.simdEulerAngles = V3(sinf(p.t * 9) * 0.05 * p.talk + p.eat * 0.15, sinf(p.t * 0.37) * 0.15 * (1 - p.gait * 0.6), 0)
        blinkT -= 1 / 60
        let closed: Float = blinkT < 0.1 ? 1 : 0
        if blinkT < 0 { blinkT = Float.random(in: 2...5) }
        for l in lids { l.simdScale = V3(1, 0.05 + closed * 0.95, 1); l.simdPosition = V3(0, 0.012 * (1 - closed), 0) }
    }
}

final class ChickenHead: HeadPart {
    private let neckNode = SCNNode(), skull = SCNNode(), jaw = SCNNode(), wattles = SCNNode(), comb = SCNNode()
    init(white: Bool = false) {
        super.init(.chicken)
        height = 0.36; mouth = V3(0, 0.22, 0.2)
        anchor = skull
        node.add(neckNode)
        neckNode.add(loftNode([Ring(V3(0, -0.04, -0.02), 0.1, 0.1), Ring(V3(0, 0.04, 0.0), 0.085, 0.085), Ring(V3(0, 0.12, 0.03), 0.065, 0.065),
                               Ring(V3(0, 0.19, 0.05), 0.055, 0.055), Ring(V3(0, 0.24, 0.06), 0.045, 0.045)], white ? Mat.whiteFeather : Mat.hackle, seg: 20, smooth: 3,
                              displace: { _, _, u, v in 0.006 * sinf(u * 2 * .pi * 12 + v * 8) }))
        skull.simdPosition = V3(0, 0.22, 0.06)
        neckNode.add(skull)
        skull.add(loftNode([Ring(V3(0, 0.0, -0.065), 0.025, 0.025), Ring(V3(0, 0.005, -0.04), 0.05, 0.055), Ring(V3(0, 0.01, 0.0), 0.056, 0.06),
                            Ring(V3(0, 0.005, 0.04), 0.046, 0.046), Ring(V3(0, 0.0, 0.065), 0.03, 0.03), Ring(V3(0, -0.002, 0.075), 0.015, 0.015)],
                           white ? Mat.whiteFeather : Mat.hackle, seg: 20, ref: V3(0, 1, 0), smooth: 3))
        // face skin around the eyes
        skull.add(sphereNode(0.045, Mat.comb, seg: 16).scl(1.12, 0.8, 0.9).at(0, 0.0, 0.035))
        // beak
        skull.add(loftNode([Ring(V3(0, 0.004, 0.06), 0.022, 0.017), Ring(V3(0, 0.0, 0.085), 0.016, 0.012), Ring(V3(0, -0.008, 0.108), 0.008, 0.006),
                            Ring(V3(0, -0.02, 0.12), 0.002, 0.002)], Mat.beak, seg: 14, ref: V3(0, 1, 0), smooth: 3))
        jaw.simdPosition = V3(0, -0.012, 0.062)
        skull.add(jaw)
        jaw.add(loftNode([Ring(V3(0, 0, 0), 0.017, 0.008), Ring(V3(0, -0.003, 0.025), 0.012, 0.006), Ring(V3(0, -0.006, 0.042), 0.003, 0.002)], Mat.beak, seg: 12, ref: V3(0, 1, 0), smooth: 2))
        // comb: five blades
        comb.simdPosition = V3(0, 0.05, 0)
        skull.add(comb)
        for k in 0..<5 {
            let z = -0.045 + Float(k) * 0.024
            let h: Float = [0.035, 0.05, 0.058, 0.05, 0.032][k]
            comb.add(sphereNode(0.03, Mat.comb, seg: 14).scl(0.28, h / 0.03, 0.55).at(0, h * 0.5, z))
        }
        comb.add(sphereNode(0.05, Mat.comb, seg: 14).scl(0.25, 0.4, 1.3).at(0, 0, 0.0))
        // wattles
        wattles.simdPosition = V3(0, -0.035, 0.055)
        skull.add(wattles)
        for sx in [Float(1), -1] { wattles.add(sphereNode(0.028, Mat.comb, seg: 14).scl(0.4, 1.1, 0.7).at(0.012 * sx, -0.022, 0)) }
        // eyes and earlobes
        for sx in [Float(1), -1] {
            let e = SCNNode(); e.simdPosition = V3(0.047 * sx, 0.014, 0.022)
            skull.add(e)
            e.add(sphereNode(0.012, Mat.irisOrange, seg: 14))
            e.add(sphereNode(0.0055, Mat.eyeBlack, seg: 10).scl(0.35, 1, 1).at(0.0105 * sx, 0, 0))
            skull.add(sphereNode(0.014, Mat.comb, seg: 10).scl(0.3, 1, 0.8).at(0.05 * sx, -0.018, -0.02))
        }
    }
    override func pose(_ p: Pose) {
        // the head holds still in space, then snaps forward: a chicken's walk
        let saw = p.phase * 2 - floorf(p.phase * 2)
        let bob = (saw < 0.75 ? -saw / 0.75 : (saw - 0.75) / 0.25 - 1) * 0.05 * p.gait * (1 - p.air)
        let peck = p.eat * max(0, sinf(p.t * 14)) * 0.9 + p.eat * 0.5
        neckNode.simdEulerAngles = V3(peck + p.run * 0.25 * p.gait, 0, 0)
        neckNode.simdPosition = V3(0, 0, bob + 0.03)
        skull.simdEulerAngles = V3(peck * 0.3 - p.talk * 0.2, sinf(p.t * 1.3) * 0.35 * (1 - p.gait) * (1 - p.eat) + sinf(p.t * 5.1) * 0.1 * (1 - p.gait), 0)
        jaw.simdEulerAngles = V3((p.talk * (0.5 + 0.5 * abs(sinf(p.t * 20)))) * 0.45 + p.scared * 0.4, 0, 0)
        wattles.simdEulerAngles = V3(sinf(p.t * 11) * 0.15 * (p.gait + p.eat) - bob * 4, 0, 0)
        comb.simdEulerAngles = V3(0, 0, sinf(p.t * 9) * 0.06 * (p.gait + p.eat))
    }
}

final class CowHead: HeadPart {
    private let neckNode = SCNNode(), skull = SCNNode(), jaw = SCNNode()
    private var ears: [SCNNode] = []
    private var earT: Float = 1
    init() {
        super.init(.cow)
        height = 0.5; mouth = V3(0, 0.1, 0.5)
        anchor = skull
        node.add(neckNode)
        neckNode.add(loftNode([Ring(V3(0, -0.06, -0.02), 0.16, 0.16), Ring(V3(0, 0.06, 0.03), 0.14, 0.15), Ring(V3(0, 0.15, 0.1), 0.12, 0.14),
                               Ring(V3(0, 0.21, 0.17), 0.11, 0.12)], Mat.hide, seg: 22, smooth: 3, vScale: 0.7))
        skull.simdPosition = V3(0, 0.22, 0.2)
        skull.simdEulerAngles = V3(0.55, 0, 0)
        neckNode.add(skull)
        skull.add(loftNode([Ring(V3(0, 0.02, -0.14), 0.05, 0.05), Ring(V3(0, 0.02, -0.1), 0.105, 0.11), Ring(V3(0, 0.02, -0.02), 0.12, 0.125, e: 2.3),
                            Ring(V3(0, 0.01, 0.07), 0.105, 0.11, e: 2.3), Ring(V3(0, -0.005, 0.17), 0.08, 0.085), Ring(V3(0, -0.01, 0.26), 0.068, 0.07),
                            Ring(V3(0, -0.012, 0.32), 0.075, 0.064), Ring(V3(0, -0.015, 0.35), 0.05, 0.045)], Mat.hide, seg: 26, ref: V3(0, 1, 0), smooth: 4, vScale: 0.7) { p, _, _, _ in
            // brow ridges over the eyes and a flat forehead
            var d: Float = 0
            for sx in [Float(0.09), -0.09] { d += expf(-(powf((p.x - sx) * 20, 2) + powf((p.z - 0.03) * 18, 2))) * 0.015 }
            return d
        })
        // muzzle
        skull.add(sphereNode(0.08, Mat.cowNose, seg: 22).scl(1.05, 0.72, 0.55).at(0, -0.01, 0.335))
        for sx in [Float(1), -1] { skull.add(sphereNode(0.016, Mat.black, seg: 10).scl(1.3, 0.8, 0.6).at(0.03 * sx, 0.005, 0.37)) }
        jaw.simdPosition = V3(0, -0.06, 0.03)
        skull.add(jaw)
        jaw.add(loftNode([Ring(V3(0, 0, -0.02), 0.06, 0.035), Ring(V3(0, -0.005, 0.12), 0.06, 0.035), Ring(V3(0, -0.01, 0.26), 0.05, 0.028),
                          Ring(V3(0, -0.005, 0.31), 0.045, 0.024), Ring(V3(0, 0, 0.33), 0.01, 0.01)], Mat.cowSkin, seg: 16, ref: V3(0, 1, 0), smooth: 3))
        // eyes, lashes, ears, horns
        for sx in [Float(1), -1] {
            skull.add(sphereNode(0.024, Mat.cowEye, seg: 16).scl(0.8, 0.9, 1).at(0.108 * sx, 0.035, 0.035))
            skull.add(boxNode(0.004, 0.004, 0.035, Mat.lash).at(0.115 * sx, 0.058, 0.04).rot(0.2, sx * 0.2, sx * 0.3))
            let ear = SCNNode(); ear.simdPosition = V3(0.12 * sx, 0.06, -0.08)
            skull.add(ear)
            ear.add(sphereNode(0.06, Mat.hide, seg: 16).scl(1.9, 0.3, 1.0).at(0.1 * sx, 0, 0))
            ear.add(sphereNode(0.055, Mat.cowSkin, seg: 14).scl(1.7, 0.15, 0.85).at(0.1 * sx, 0.012, 0.005))
            ears.append(ear)
            skull.add(coneNode(0.022, 0.006, 0.08, Mat.horn, seg: 10).at(0.08 * sx, 0.12, -0.11).rot(-0.3, 0, -sx * 0.6))
        }
    }
    override func pose(_ p: Pose) {
        let graze = p.eat
        neckNode.simdEulerAngles = V3(graze * 0.9 - p.talk * 0.35 + p.shove * 0.6, 0, 0)
        skull.simdEulerAngles = V3(0.55 + graze * 0.6 - p.talk * 0.4 + p.shove * 0.3, sinf(p.t * 0.29) * 0.2 * (1 - p.gait), 0)
        let chew = graze * sinf(p.t * 6)
        jaw.simdEulerAngles = V3(p.talk * (0.28 + 0.06 * sinf(p.t * 5)) + abs(chew) * 0.08, chew * 0.08, 0)
        earT -= 1 / 60
        var flick: Float = 0
        if earT < 0.15 { flick = sinf(earT / 0.15 * .pi) }
        if earT < 0 { earT = Float.random(in: 1.5...5) }
        for (i, e) in ears.enumerated() {
            let sx: Float = i == 0 ? 1 : -1
            e.simdEulerAngles = V3(0, sx * (0.2 + flick * (i == 0 ? 0.5 : 0) + p.talk * 0.2), sx * (-0.15 + p.run * p.gait * 0.4))
        }
    }
}

/// A full body assembled from three parts. Morphing swaps one part with a squishy grow/shrink.
final class Body {
    let root = SCNNode()
    private let spin = SCNNode()
    private let frame = SCNNode()
    private(set) var legs: LegsPart
    private(set) var torso: TorsoPart
    private(set) var head: HeadPart
    private(set) var combo: Combo
    let outfit: Outfit
    let white: Bool
    private let torsoMount = SCNNode(), headMount = SCNNode()
    private var morphT: [Float] = [9, 9, 9]
    private var dying: [(SCNNode, Float)] = []
    var flip: Float = 0         // backflip angle
    var roll: Float = 0         // tipped over sideways
    var lean: Float = 0
    var addOns = [0, 0, 0]
    var addOnNodes: [SCNNode] = []
    var lift: Float = 0
    var boosting = false

    init(_ c: Combo, outfit: Outfit = .player, white: Bool = false) {
        combo = c; self.outfit = outfit; self.white = white
        legs = Body.makeLegs(c.legs, outfit, white)
        torso = Body.makeTorso(c, outfit, white)
        head = Body.makeHead(c.head, outfit, white)
        root.add(spin)
        spin.add(frame)
        frame.add(legs.node)
        frame.add(torsoMount)
        torsoMount.add(torso.node)
        torso.node.add(headMount)
        headMount.add(head.node)
        place(instant: true)
        root.castAll(true)
    }

    func setAddOn(_ slot: Slot, _ i: Int) {
        addOns[slot.rawValue] = i
        applyAddOns()
    }

    static func horizontalTorso(_ c: Combo) -> Bool {
        guard c.torso == c.legs else { return false }
        let d = c.torso.def
        switch d.plan {
        case .quad, .sprawl, .fish, .insect, .spider, .slither: return true
        case .hopper: return d.name != "Kangaroo"
        default: return false
        }
    }
    static func makeLegs(_ s: Species, _ o: Outfit, _ w: Bool) -> LegsPart {
        switch s {
        case .human: return HumanLegs(o)
        case .chicken: return ChickenLegs(white: w)
        case .cow: return CowLegs()
        default: return GenLegs(s.def)
        }
    }
    static func makeTorso(_ c: Combo, _ o: Outfit, _ w: Bool) -> TorsoPart {
        switch c.torso {
        case .human: return HumanTorso(o)
        case .chicken: return ChickenTorso(white: w)
        case .cow: return CowTorso(quadruped: c.legs == .cow)
        default: return GenTorso(c.torso.def, horizontal: horizontalTorso(c))
        }
    }
    static func makeHead(_ s: Species, _ o: Outfit, _ w: Bool) -> HeadPart {
        switch s {
        case .human: return HumanHead(o)
        case .chicken: return ChickenHead(white: w)
        case .cow: return CowHead()
        default: return GenHead(s.def)
        }
    }

    var height: Float { legs.attach.y + (torso.neckRot > 0.5 ? 0.2 : torso.neck.y) + head.height + lift }
    var radius: Float { legs.radius }

    /// Collision circles in body space: (z along the body, radius). Long animals get a chain of
    /// circles down the trunk plus one for a head that sticks out in front; upright bodies get one.
    func hitCircles() -> [(z: Float, r: Float)] {
        let w = max(0.18, legs.trunkWidth)
        var out: [(z: Float, r: Float)] = []
        if legs.trunkHalf > w * 0.9 {
            let span = legs.trunkHalf * 2 - w * 2
            let n = max(2, Int(ceilf(span / (w * 1.1))) + 1)
            for k in 0..<n {
                let z = legs.trunkZ - legs.trunkHalf + w + span * Float(k) / Float(n - 1)
                out.append((z, w))
            }
        } else {
            out.append((legs.trunkZ, max(w, min(legs.radius, 0.45))))
        }
        // a head (or upright torso) poking out past the front of the trunk
        // where the snout ends: neck socket plus the head's mouth point, tipped by the neck angle
        let nr = torso.neckRot - tiltFor(combo)
        let mz = head.mouth.z * cosf(nr) + head.mouth.y * sinf(nr)
        let hp = V3(0, 0, legs.attach.z + torso.neck.z + mz)
        let front = (out.last?.z ?? 0) + (out.last?.r ?? 0)
        if hp.z > front + 0.05 {
            let hr = clampf(head.height * 0.35, 0.1, 0.32)
            out.append((hp.z - hr * 0.6, hr))
        }
        return out
    }
    var mass: Float { legs.mass + torso.mass + (head.species == .cow ? 1 : head.species == .chicken ? 0.2 : head.species == .human ? 0.6 : max(0.1, head.species.def.size * head.species.def.size * 0.6)) }

    /// World-ish point (body space) where the mouth is, for effects.
    func mouthPoint() -> V3 { head.node.convertPosition(SCNVector3(head.mouth), to: root).v3 }
    func carryPoint() -> V3 { torso.node.convertPosition(SCNVector3(torso.carry), to: root).v3 }
    func tailPoint() -> V3 { V3(0, legs.attach.y * 0.7, -max(0.25, legs.radius)) }

    private func tiltFor(_ c: Combo) -> Float {
        guard c.isPure else { return 0 }
        let d = c.torso.def
        if d.plan == .bird && d.name != "Penguin" { return 0.42 }
        if d.plan == .biped && c.torso != .human && d.name != "Meerkat" { return ["Gorilla", "Chimpanzee", "Orangutan"].contains(d.name) ? 0.5 : 0.3 }
        return 0
    }

    private func place(instant: Bool) {
        torsoMount.simdPosition = legs.attach
        headMount.simdPosition = torso.neck
        headMount.simdEulerAngles = V3(torso.neckRot - tiltFor(combo), 0, 0)
    }

    func set(_ slot: Slot, _ s: Species) {
        var c = combo
        c[slot] = s
        guard c != combo else { return }
        let old = combo
        combo = c
        let torsoChanges = slot == .torso || Body.horizontalTorso(c) != Body.horizontalTorso(old) || (c.torso == .cow && old.legs != c.legs && (old.legs == .cow || c.legs == .cow))
        if slot == .legs {
            let n = Body.makeLegs(s, outfit, white)
            retire(legs.node)
            legs = n
            frame.add(n.node)
            n.node.castAll(true)
            morphT[2] = 0
        }
        if torsoChanges {
            let n = Body.makeTorso(c, outfit, white)
            headMount.removeFromParentNode()
            retire(torso.node)
            torso = n
            torsoMount.add(n.node)
            n.node.add(headMount)
            n.node.castAll(true)
            morphT[1] = 0
        }
        if slot == .head {
            let n = Body.makeHead(s, outfit, white)
            retire(head.node)
            head = n
            headMount.add(n.node)
            n.node.castAll(true)
            morphT[0] = 0
        }
        applyAddOns()
    }

    func setCombo(_ c: Combo) {
        for s in Slot.allCases where c[s] != combo[s] { set(s, c[s]) }
    }

    private func retire(_ n: SCNNode) {
        // keep the old part where it is in world space while it shrinks away
        let wt = n.simdWorldTransform
        n.removeFromParentNode()
        root.parent?.addChildNode(n)
        n.simdWorldTransform = wt
        dying.append((n, 0))
    }

    func update(_ p: Pose, dt: Float) {
        legs.pose(p); torso.pose(p); head.pose(p)
        let tilt = tiltFor(combo)
        let targetMount = legs.attach
        torsoMount.simdPosition += (targetMount - torsoMount.simdPosition) * min(1, dt * 10)
        let hm = torso.neck
        headMount.simdPosition += (hm - headMount.simdPosition) * min(1, dt * 10)
        headMount.simdEulerAngles = V3(torso.neckRot - tilt, 0, 0)
        let leanF = lean + p.run * p.gait * 0.08 + p.shove * 0.25 - p.glide * 0.1 + p.eat * (combo.legs == .cow ? 0 : 0.25)
        torsoMount.simdEulerAngles = V3(tilt + leanF + p.lay * 0.3, 0, 0)
        let cy = height * 0.5
        let limp: Float = addOns[2] == 1 ? 1 : 0
        let lurch = limp * p.gait * sinf(p.phase * 2 * .pi)
        spin.simdPosition = V3(0, cy + legs.bob(p) + lift - abs(lurch) * 0.06, 0)
        frame.simdPosition = V3(0, -cy - lift * 0, 0)
        spin.simdEulerAngles = V3(-flip + legs.pitch(p) + (addOns[1] == 1 ? 0.12 : 0), 0, roll + lurch * 0.12 + (addOns[0] == 1 ? sinf(p.t * 1.7) * 0.05 : 0))
        animateAddOns(p, dt: dt, boosting: boosting)
        // morph wobble: new parts grow in with an elastic overshoot
        let parts: [SCNNode] = [head.node, torso.node, legs.node]
        for i in 0..<3 {
            morphT[i] += dt
            let t = morphT[i]
            if t < 0.6 {
                let u = t / 0.6
                let s = 1 - expf(-u * 6) * cosf(u * 14)
                let wob = sinf(t * 40) * 0.12 * (1 - u)
                parts[i].simdScale = V3(max(0.01, s + wob), max(0.01, s - wob), max(0.01, s + wob))
            } else if parts[i].simdScale.x != 1 {
                parts[i].simdScale = V3(1, 1, 1)
            }
        }
        for k in dying.indices.reversed() {
            dying[k].1 += dt
            let u = dying[k].1 / 0.3
            if u >= 1 { dying[k].0.removeFromParentNode(); dying.remove(at: k); continue }
            let s = max(0.01, 1 - u * u)
            dying[k].0.simdScale = V3(s * (1 + u * 0.4), s, s * (1 + u * 0.4))
            dying[k].0.simdEulerAngles.y += dt * 12
        }
    }
}

extension SCNVector3 {
    var v3: V3 { V3(Float(x), Float(y), Float(z)) }
    init(_ v: V3) { self.init(CGFloat(v.x), CGFloat(v.y), CGFloat(v.z)) }
}
