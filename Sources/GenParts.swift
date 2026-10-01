import SceneKit
import simd

// Parametric head, body and legs for the 97 generated animals.

/// Adds fur shells to a lofted part when the animal is furry.
@discardableResult
func furry(_ n: SCNNode, _ d: SpeciesDef, scale: Float = 1) -> SCNNode {
    guard Coats.isFurry(d.coat), let m = n.geometry?.firstMaterial else { return n }
    let len = (d.coat == .wool ? 0.03 : d.coat == .quills ? 0.02 : 0.011) * max(0.5, d.size) * scale
    Coats.furShells(n, m, length: len, layers: d.coat == .wool ? 4 : 3)
    return n
}

/// A leg segment with muscle: wide and flattened at the top where it meets the body, tapering to the joint.
func muscleLimb(_ len: Float, top: Float, mid: Float, bottom: Float, _ m: SCNMaterial, depth: Float = 1.3, dir: V3 = V3(0, -1, 0), bulgeAt: Float = 0.3) -> SCNNode {
    let d = simd_normalize(dir)
    let rings = [Ring(d * (-top * 0.5), top * 0.55, top * 0.55 * depth),
                 Ring(d * (len * 0.05), top, top * depth),
                 Ring(d * (len * bulgeAt), mixf(top, mid, 0.4), mixf(top, mid, 0.4) * depth * 1.05),
                 Ring(d * (len * 0.7), mid, mid * depth * 0.95),
                 Ring(d * (len * 0.95), bottom * 1.1, bottom * 1.05),
                 Ring(d * (len + bottom * 0.5), bottom * 0.6, bottom * 0.6)]
    return loftNode(rings, m, seg: 16, ref: abs(d.z) > 0.9 ? V3(0, 1, 0) : V3(0, 0, 1), smooth: 3)
}

private func chainLimb(_ parent: SCNNode, count: Int, len: Float, r0: Float, r1: Float, _ m: SCNMaterial, dir: V3 = V3(0, -1, 0)) -> [SCNNode] {
    var nodes: [SCNNode] = []
    var p = parent
    for k in 0..<count {
        let t0 = Float(k) / Float(count), t1 = Float(k + 1) / Float(count)
        let n = SCNNode()
        if k > 0 { n.simdPosition = simd_normalize(dir) * len }
        p.addChildNode(n)
        n.addChildNode(limb(len, mixf(r0, r1, t0), mixf(r0, r1, t1), m, seg: 10, dir: dir))
        nodes.append(n)
        p = n
    }
    return nodes
}

/// Feet and hooves at the bottom of a leg (origin at the ankle).
private func buildFoot(_ parent: SCNNode, _ d: SpeciesDef, _ th: Float, _ m: SCNMaterial) {
    let lm = Coats.limbMat(d)
    switch d.foot {
    case .hoof:
        parent.addChildNode(coneNode(CGFloat(th * 1.15), CGFloat(th * 0.9), CGFloat(th * 1.4), Mat.hoof).at(0, -th * 0.6, th * 0.1))
    case .pad:
        parent.addChildNode(cylNode(CGFloat(th * 1.25), CGFloat(th * 0.9), m, seg: 18).at(0, -th * 0.5, 0))
        for k in -1...1 { parent.addChildNode(sphereNode(CGFloat(th * 0.28), Mat.horn, seg: 8).at(Float(k) * th * 0.6, -th * 0.75, th * 1.1)) }
    case .paw:
        parent.addChildNode(sphereNode(CGFloat(th * 1.3), lm, seg: 14).scl(1, 0.55, 1.3).at(0, -th * 0.55, th * 0.45))
        for k in -1...1 { parent.addChildNode(coneNode(CGFloat(th * 0.14), 0.001, CGFloat(th * 0.5), Mat.claw, seg: 6).rot(Float.pi / 2, 0, 0).at(Float(k) * th * 0.5, -th * 0.7, th * 1.9)) }
    case .foot:
        parent.addChildNode(loftNode([Ring(V3(0, -th * 0.5, -th * 0.9), th * 0.5, th * 0.4), Ring(V3(0, -th * 0.6, 0), th * 0.95, th * 0.55), Ring(V3(0, -th * 0.75, th * 1.8), th * 1.0, th * 0.35),
                                      Ring(V3(0, -th * 0.8, th * 2.4), th * 0.6, th * 0.2)], lm, seg: 12, ref: V3(0, 1, 0), smooth: 3))
    case .webbed, .talon:
        for a in [Float(-0.5), 0, 0.5] {
            let toe = SCNNode(); toe.simdEulerAngles = V3(0, a, 0)
            parent.addChildNode(toe)
            toe.addChildNode(limb(th * 5, th * 0.5, th * 0.35, lm, seg: 8, dir: V3(0, -0.15, 1)))
            if d.foot == .talon { toe.addChildNode(coneNode(CGFloat(th * 0.3), 0.001, CGFloat(th * 1.2), Mat.claw, seg: 6).rot(Float.pi / 2, 0, 0).at(0, -th * 0.8, th * 5.3)) }
        }
        if d.foot == .webbed {
            parent.addChildNode(sphereNode(CGFloat(th * 4), lm, seg: 12).scl(1, 0.06, 0.8).at(0, -th * 0.7, th * 2.6))
        }
    case .none: break
    }
}

private func buildTail(_ parent: SCNNode, _ d: SpeciesDef, _ s: Float, _ m: SCNMaterial, ground: Float) -> SCNNode? {
    let root = SCNNode()
    parent.addChildNode(root)
    let lm = d.limbCol.map { Coats.plain($0) } ?? m
    let dark = Coats.plain(d.b * 0.8 + d.a * 0.2, rough: 0.8)
    switch d.tail {
    case .none: return nil
    case .thin: root.addChildNode(limb(0.45 * s, 0.025 * s, 0.012 * s, m, dir: V3(0, -0.7, -0.4)))
    case .long: root.addChildNode(limb(0.8 * s, 0.03 * s, 0.01 * s, lm, dir: V3(0, -0.35, -0.8)))
    case .tuft:
        root.addChildNode(limb(0.55 * s, 0.025 * s, 0.015 * s, m, dir: V3(0, -0.8, -0.35)))
        root.addChildNode(sphereNode(CGFloat(0.045 * s), dark, seg: 10).scl(0.9, 2.2, 0.9).at(0, -0.56 * s, -0.24 * s))
    case .bushy: root.addChildNode(loftNode([Ring(V3(0, 0, 0), 0.04 * s, 0.04 * s), Ring(V3(0, -0.05 * s, -0.2 * s), 0.1 * s, 0.1 * s), Ring(V3(0, -0.12 * s, -0.45 * s), 0.11 * s, 0.11 * s),
                                              Ring(V3(0, -0.15 * s, -0.62 * s), 0.02 * s, 0.02 * s)], m, seg: 14, ref: V3(0, 1, 0), smooth: 3))
    case .fluffy: root.addChildNode(sphereNode(CGFloat(0.08 * s), Coats.plain(V3(0.93, 0.92, 0.9), rough: 0.9), seg: 12))
    case .curly:
        let t = SCNTorus(ringRadius: CGFloat(0.05 * s), pipeRadius: CGFloat(0.012 * s)); t.materials = [m]
        root.addChildNode(SCNNode(geometry: t).rot(0, 0, Float.pi / 2).at(0, 0.02 * s, -0.05 * s))
    case .stub: root.addChildNode(sphereNode(CGFloat(0.05 * s), m, seg: 10))
    case .reptile:
        let len = max(0.5, ground * 2.2)
        root.addChildNode(loftNode([Ring(V3(0, 0, 0.05 * s), 0.1 * s, 0.1 * s), Ring(V3(0, -ground * 0.5, -len * 0.35), 0.07 * s, 0.07 * s),
                                    Ring(V3(0, -ground * 0.85, -len * 0.75), 0.035 * s, 0.03 * s), Ring(V3(0, -ground * 0.92, -len), 0.008 * s, 0.008 * s)], m, seg: 14, ref: V3(0, 1, 0), smooth: 3))
    case .horse: root.addChildNode(loftNode([Ring(V3(0, 0, 0), 0.05 * s, 0.05 * s), Ring(V3(0, -0.25 * s, -0.12 * s), 0.07 * s, 0.05 * s), Ring(V3(0, -0.6 * s, -0.12 * s), 0.06 * s, 0.04 * s),
                                             Ring(V3(0, -0.75 * s, -0.1 * s), 0.01 * s, 0.01 * s)], Mat.brownHair, seg: 12, ref: V3(0, 0, 1), smooth: 3))
    case .flat: root.addChildNode(sphereNode(CGFloat(0.16 * s), Coats.coat(.scales, V3(0.18, 0.15, 0.12), V3(0.1, 0.08, 0.07)), seg: 16).scl(0.8, 0.12, 1.4).at(0, -0.05 * s, -0.22 * s))
    case .stinger: root.addChildNode(coneNode(CGFloat(0.02 * s), 0.001, CGFloat(0.08 * s), Mat.black, seg: 8).rot(-Float.pi / 2, 0, 0).at(0, 0, -0.04 * s))
    case .curl:
        let t = SCNTorus(ringRadius: CGFloat(0.09 * s), pipeRadius: CGFloat(0.025 * s)); t.materials = [m]
        root.addChildNode(SCNNode(geometry: t).rot(0, 0, Float.pi / 2).at(0, -0.08 * s, -0.12 * s))
    case .fan: return nil
    }
    return root
}

// MARK: - Legs

final class GenLegs: LegsPart {
    let d: SpeciesDef
    private var ups: [SCNNode] = [], los: [SCNNode] = [], feet: [SCNNode] = []
    private var offs: [Float] = [], hind: [Bool] = [], sides: [Float] = []
    private var tail: SCNNode?
    private let base = SCNNode()
    private var chain: [SCNNode] = []
    private var chainR: [Float] = []
    private var tentacles: [[SCNNode]] = []
    private var tailPiv = SCNNode()
    private var liftY: Float = 0
    let s: Float
    private var R: Float = 0.3, L: Float = 0.7

    init(_ d: SpeciesDef) {
        self.d = d
        s = d.size
        super.init(Species(id: Zoo.defs.firstIndex(where: { $0.name == d.name }) ?? 0))
        node.addChildNode(base)
        let m = Coats.coat(d)
        let lm = Coats.limbMat(d)
        mass = max(0.15, 2.2 * s * s * s * d.girth)
        switch d.plan {
        case .quad: buildQuad(m)
        case .sprawl: buildSprawl(m)
        case .bird: buildBird(m, lm)
        case .biped: buildBiped(m, lm)
        case .hopper: buildHopper(m, lm)
        case .slither: buildSlither(m)
        case .fish: buildFish(m)
        case .insect, .spider: buildBug(m, lm)
        case .tentacle: buildTentacles(m)
        }
    }

    private func leg(at p: V3, up: Float, lo: Float, th: Float, _ m: SCNMaterial, off: Float, isHind: Bool, side: Float, upDir: V3 = V3(0, -1, 0), loDir: V3 = V3(0, -1, 0), foot: Bool = true) {
        let u = SCNNode(); u.simdPosition = p
        base.addChildNode(u)
        let chunky = d.plan == .quad || d.plan == .sprawl
        if chunky {
            u.addChildNode(furry(muscleLimb(up, top: th * (isHind ? 1.9 : 1.6), mid: th * 1.0, bottom: th * 0.72, m, depth: isHind ? 1.55 : 1.3, dir: upDir, bulgeAt: isHind ? 0.25 : 0.3), d))
        } else {
            u.addChildNode(limb(up, th * (isHind ? 1.25 : 1.05), th * 0.8, m, depth: isHind ? 1.3 : 1.1, bulge: 0.2, seg: 12, dir: upDir))
        }
        let l = SCNNode(); l.simdPosition = simd_normalize(upDir) * up
        u.addChildNode(l)
        if chunky {
            l.addChildNode(furry(muscleLimb(lo, top: th * 0.75, mid: th * 0.55, bottom: th * 0.5, m, depth: 1.15, dir: loDir, bulgeAt: 0.12), d, scale: 0.6))
        } else {
            l.addChildNode(limb(lo, th * 0.7, th * 0.55, m, seg: 10, dir: loDir))
        }
        let f = SCNNode(); f.simdPosition = simd_normalize(loDir) * lo
        l.addChildNode(f)
        if foot { buildFoot(f, d, th * 0.75, m) }
        ups.append(u); los.append(l); feet.append(f); offs.append(off); hind.append(isHind); sides.append(side)
        footNodes.append(f)
    }

    private func buildQuad(_ m: SCNMaterial) {
        R = 0.3 * s * d.girth; L = 0.72 * s * d.bodyLen
        let legH = 0.82 * s * d.legLen
        let by = legH + R * 0.5
        let slim: Float = d.foot == .paw && d.girth < 1.15 ? 0.82 : 0.97
        let R = self.R, L = self.L
        let rings = [Ring(V3(0, by + 0.08 * R, -L - 0.1 * s), 0.25 * R, 0.25 * R), Ring(V3(0, by + 0.06 * R, -L * 0.92), 0.78 * R, 0.8 * R, e: 2.2),
                     Ring(V3(0, by + 0.02 * R, -L * 0.55), 0.95 * R, 0.95 * R), Ring(V3(0, by - 0.02 * R, -L * 0.1), R * slim, R * slim * 0.98),
                     Ring(V3(0, by - 0.08 * R, L * 0.35), 1.02 * R, 1.12 * R), Ring(V3(0, by - 0.02 * R, L * 0.72), R * 0.95, R * 1.08),
                     Ring(V3(0, by + 0.12 * R, L), 0.72 * R, 0.8 * R), Ring(V3(0, by + 0.2 * R, L + 0.1 * s), 0.3 * R, 0.3 * R)]
        base.addChildNode(furry(loftNode(rings, m, seg: 28, ref: V3(0, 1, 0), smooth: 4, vScale: 0.8) { p, n, _, _ in
            // shoulder blades and haunches under the skin
            var dd: Float = 0
            for sx in [Float(1), -1] {
                let sh = p - V3(sx * R * 0.55, by + R * 0.5, L * 0.62)
                dd += expf(-simd_length_squared(sh) / (R * R * 0.12)) * R * 0.1
                let hp = p - V3(sx * R * 0.6, by + R * 0.35, -L * 0.62)
                dd += expf(-simd_length_squared(hp) / (R * R * 0.15)) * R * 0.12
            }
            dd += expf(-p.x * p.x / (R * R * 0.02)) * max(0, n.y) * R * 0.03
            return dd
        }, d))
        let th = 0.085 * s * d.legThick * sqrtf(d.girth)
        let hipY = by - R * 0.35
        let up = hipY * 0.5, lo = hipY * 0.5 - th * 0.9
        let wo: [Float] = [0, 0.5, 0.25, 0.75]
        for (k, (x, z)) in [(R * 0.55, -L * 0.7), (-R * 0.55, -L * 0.7), (R * 0.55, L * 0.72), (-R * 0.55, L * 0.72)].enumerated() {
            leg(at: V3(x, hipY, z), up: up, lo: lo, th: th, m, off: wo[k], isHind: k < 2, side: x > 0 ? 1 : -1)
        }
        if d.hump { base.addChildNode(sphereNode(CGFloat(R * 0.6), m, seg: 16).scl(1, 0.8, 1.3).at(0, by + R * 0.75, -0.1 * L)) }
        if d.shell {
            let sh = Coats.coat(.shell, d.a, d.b)
            base.addChildNode(sphereNode(CGFloat(R * 1.18), sh, seg: 24).scl(1, 0.8, L / R * 0.95).at(0, by + 0.1 * R, 0))
        }
        if d.spikes { addSpikes(center: V3(0, by, 0), rx: R, rz: L) }
        tail = buildTail(base, d, s, m, ground: by)
        tail?.simdPosition = V3(0, by + R * 0.45, -L - 0.02 * s)
        attach = V3(0, by + R * 0.6, L * 0.8)
        radius = clampf(L * 0.72, 0.3, 1.05)
        stride = legH * 2.2 + 0.3 * s
        footPhases = [0, 0.25, 0.5, 0.75]
    }

    private func addSpikes(center: V3, rx: Float, rz: Float) {
        var rr = RNG(7)
        let q = Coats.plain(d.b, rough: 0.6)
        for _ in 0..<60 {
            let a = rr.range(-1.2, 1.2), zt = rr.range(-0.95, 0.9)
            let dir = V3(sinf(a), cosf(a), 0)
            let p = center + V3(dir.x * rx * 1.02, dir.y * rx * 0.95, zt * rz)
            let c = coneNode(CGFloat(0.012 * s), 0.001, CGFloat(0.12 * s), q, seg: 5)
            c.simdPosition = p + dir * 0.04 * s
            c.simdOrientation = simd_quatf(from: V3(0, 1, 0), to: simd_normalize(dir + V3(0, 0, -0.8)))
            base.addChildNode(c)
        }
    }

    private func buildSprawl(_ m: SCNMaterial) {
        R = 0.2 * s * d.girth; L = 0.5 * s * d.bodyLen
        let legH = 0.2 * s * d.legLen
        let by = legH + R * 0.55
        base.addChildNode(furry(loftNode([Ring(V3(0, by, -L - 0.05 * s), 0.3 * R, 0.25 * R), Ring(V3(0, by, -L * 0.6), R * 0.85, R * 0.7), Ring(V3(0, by, 0), R, R * 0.75),
                                    Ring(V3(0, by, L * 0.6), R * 0.9, R * 0.7), Ring(V3(0, by + 0.05 * R, L + 0.05 * s), R * 0.4, R * 0.35)], m, seg: 20, ref: V3(0, 1, 0), smooth: 3), d))
        let th = 0.05 * s * d.legThick * sqrtf(d.girth)
        let wo: [Float] = [0, 0.5, 0.5, 0]
        for (k, (x, z)) in [(R * 0.8, -L * 0.6), (-R * 0.8, -L * 0.6), (R * 0.8, L * 0.6), (-R * 0.8, L * 0.6)].enumerated() {
            let sd: Float = x > 0 ? 1 : -1
            leg(at: V3(x, by - R * 0.2, z), up: R * 1.1 + 0.05 * s, lo: by - R * 0.2, th: th, m, off: wo[k], isHind: k < 2, side: sd,
                upDir: V3(sd, -0.25, 0), loDir: V3(sd * 0.15, -1, 0))
        }
        if d.shell {
            let sh = Coats.coat(.shell, d.a, d.b)
            let dome = sphereNode(CGFloat(R * 1.65), sh, seg: 28).scl(1.0, 0.62, L / R * 0.72).at(0, by + 0.2 * R, 0)
            base.addChildNode(dome)
            base.addChildNode(cylNode(CGFloat(R * 1.6), CGFloat(0.03 * s), sh, seg: 28).scl(1, 1, L / R * 0.72).at(0, by + 0.05 * R, 0))
        }
        if d.dorsal {
            for k in 0..<10 { base.addChildNode(coneNode(CGFloat(0.02 * s), 0.001, CGFloat(0.07 * s), Coats.plain(d.b), seg: 5).at(0, by + R * 0.75 + 0.03 * s, -L + Float(k) * L * 0.2)) }
        }
        tailPiv.simdPosition = V3(0, by, -L)
        base.addChildNode(tailPiv)
        tail = buildTail(tailPiv, d, s, m, ground: by)
        attach = V3(0, by + R * 0.55, L * 0.8)
        radius = clampf(L * 0.8, 0.3, 1.0)
        stride = 0.6 * s + legH
        footPhases = [0, 0.5]
    }

    private func buildBird(_ m: SCNMaterial, _ lm: SCNMaterial) {
        let br = 0.24 * s * d.girth
        let thigh = 0.2 * s * sqrtf(d.legLen), shank = 0.3 * s * d.legLen
        let hipY = thigh * cosf(0.5) + shank * cosf(0.3) + 0.03 * s
        base.addChildNode(loftNode([Ring(V3(0, hipY - br * 0.7, -0.1 * s), 0.02, 0.02), Ring(V3(0, hipY - br * 0.5, -0.08 * s), br * 0.6, br * 0.6), Ring(V3(0, hipY, -0.05 * s), br, br),
                                    Ring(V3(0, hipY + br * 0.5, -0.03 * s), br * 1.02, br), Ring(V3(0, hipY + br * 0.95, -0.02 * s), br * 0.85, br * 0.82), Ring(V3(0, hipY + br * 1.2, -0.02 * s), br * 0.6, br * 0.58)],
                                   m, seg: 22, smooth: 3))
        let th = 0.024 * s * d.legThick * (d.legLen > 1.5 ? 1.6 : 1)
        for (k, sd) in [Float(1), -1].enumerated() {
            let u = SCNNode(); u.simdPosition = V3(0.1 * s * d.girth * sd, hipY, 0)
            base.addChildNode(u)
            u.addChildNode(limb(thigh, 0.07 * s * d.girth, 0.035 * s, m, bulge: 0.25, seg: 12))
            let l = SCNNode(); l.simdPosition = V3(0, -thigh, 0)
            u.addChildNode(l)
            l.addChildNode(limb(shank, th, th * 0.8, lm, seg: 10))
            let f = SCNNode(); f.simdPosition = V3(0, -shank, 0)
            l.addChildNode(f)
            buildFoot(f, d, th * 0.6 * max(1, 1 / d.legLen), m)
            ups.append(u); los.append(l); feet.append(f); offs.append(Float(k) * 0.5); hind.append(false); sides.append(sd)
            footNodes.append(f)
        }
        attach = V3(0, hipY + br * 1.05, -0.02 * s)
        radius = max(0.25, br * 1.15)
        stride = (thigh + shank) * 1.4
    }

    private func buildBiped(_ m: SCNMaterial, _ lm: SCNMaterial) {
        let th = 0.075 * s * d.legThick * sqrtf(d.girth)
        let thigh = 0.36 * s * d.legLen, shin = 0.34 * s * d.legLen
        let hipY = thigh + shin + th * 0.9
        let w = 0.16 * s * d.girth
        base.addChildNode(furry(loftNode([Ring(V3(0, hipY - 0.08 * s, -0.01), w * 0.9, w * 0.62), Ring(V3(0, hipY, -0.015), w * 1.1, w * 0.72), Ring(V3(0, hipY + 0.1 * s, 0), w * 1.05, w * 0.7),
                                    Ring(V3(0, hipY + 0.14 * s, 0), w * 0.6, w * 0.45)], m, seg: 20, smooth: 3), d))
        for (k, sd) in [Float(1), -1].enumerated() {
            let u = SCNNode(); u.simdPosition = V3(w * 0.55 * sd, hipY, 0)
            base.addChildNode(u)
            u.addChildNode(furry(muscleLimb(thigh, top: th * 1.35, mid: th * 1.0, bottom: th * 0.75, m, depth: 1.1), d))
            let l = SCNNode(); l.simdPosition = V3(0, -thigh, 0)
            u.addChildNode(l)
            l.addChildNode(limb(shin, th * 0.8, th * 0.6, m, seg: 10))
            let f = SCNNode(); f.simdPosition = V3(0, -shin, 0)
            l.addChildNode(f)
            buildFoot(f, d, th * 0.8, m)
            ups.append(u); los.append(l); feet.append(f); offs.append(Float(k) * 0.5); hind.append(false); sides.append(sd)
            footNodes.append(f)
        }
        tail = buildTail(base, d, s, m, ground: hipY)
        tail?.simdPosition = V3(0, hipY, -w * 0.6)
        attach = V3(0, hipY + 0.1 * s, 0)
        radius = max(0.25, w * 1.6)
        stride = (thigh + shin) * 1.5
    }

    private func buildHopper(_ m: SCNMaterial, _ lm: SCNMaterial) {
        let th = 0.07 * s * d.legThick
        let thigh = 0.3 * s * d.legLen, shin = 0.34 * s * d.legLen, footL = 0.3 * s * d.legLen
        let hipY = thigh * cosf(1.0) + shin * cosf(0.9) + th * 0.5
        let w = 0.17 * s * d.girth
        base.addChildNode(loftNode([Ring(V3(0, hipY - 0.1 * s, -0.08 * s), w * 0.5, w * 0.5), Ring(V3(0, hipY, -0.06 * s), w * 1.15, w * 1.1), Ring(V3(0, hipY + 0.12 * s, -0.02 * s), w * 1.05, w),
                                    Ring(V3(0, hipY + 0.2 * s, 0), w * 0.6, w * 0.55)], m, seg: 20, smooth: 3))
        for (k, sd) in [Float(1), -1].enumerated() {
            let u = SCNNode(); u.simdPosition = V3(w * 0.8 * sd, hipY, 0)
            base.addChildNode(u)
            u.addChildNode(sphereNode(CGFloat(w * 0.7), m, seg: 14).scl(0.8, 1, 1.2).at(0, -w * 0.2, 0))
            u.addChildNode(limb(thigh, th * 1.3, th, m, seg: 10))
            let l = SCNNode(); l.simdPosition = V3(0, -thigh, 0)
            u.addChildNode(l)
            l.addChildNode(limb(shin, th * 0.8, th * 0.55, m, seg: 10))
            let f = SCNNode(); f.simdPosition = V3(0, -shin, 0)
            l.addChildNode(f)
            f.addChildNode(limb(footL, th * 0.6, th * 0.45, d.foot == .webbed ? lm : m, seg: 8, dir: V3(0, -0.1, 1)))
            if d.foot == .webbed { f.addChildNode(sphereNode(CGFloat(footL * 0.35), lm, seg: 10).scl(1.2, 0.08, 1).at(0, -0.02 * s, footL * 0.9)) }
            ups.append(u); los.append(l); feet.append(f); offs.append(0); hind.append(false); sides.append(sd)
            footNodes.append(f)
        }
        tail = buildTail(base, d, s, m, ground: hipY)
        tail?.simdPosition = V3(0, hipY, -w)
        attach = V3(0, hipY + 0.16 * s, 0)
        radius = max(0.25, w * 1.5)
        stride = footL * 3 + 0.3 * s
    }

    private func buildSlither(_ m: SCNMaterial) {
        let r = 0.085 * s * d.girth
        liftY = (d.hood ? 0.5 : 0.22) * s
        let n = 26
        for i in 0..<n {
            let t = Float(i) / Float(n - 1)
            let rr = r * (1 - t * 0.75) * (t < 0.05 ? 0.85 : 1)
            let sp = sphereNode(CGFloat(rr), m, seg: 14)
            base.addChildNode(sp)
            chain.append(sp); chainR.append(rr)
        }
        if d.shell {
            let sh = Coats.coat(.shell, d.b, d.b * 0.6)
            let shell = SCNNode(); shell.simdPosition = V3(0, r * 2.2, -0.2 * s)
            base.addChildNode(shell)
            shell.addChildNode(sphereNode(CGFloat(0.16 * s), sh, seg: 20).scl(0.7, 1, 1))
            let t = SCNTorus(ringRadius: CGFloat(0.08 * s), pipeRadius: CGFloat(0.05 * s)); t.materials = [sh]
            shell.addChildNode(SCNNode(geometry: t).rot(0, 0, Float.pi / 2).scl(1.2, 1, 1).at(0.02 * s, 0, 0))
        }
        attach = V3(0, liftY + r, 0.12 * s)
        radius = 0.3
        stride = 0.5 * s
        mass = max(0.2, s * s * 1.2)
        R = r
    }

    private func buildFish(_ m: SCNMaterial) {
        R = 0.2 * s * d.girth
        base.addChildNode(loftNode([Ring(V3(0, R, 0.2 * s), R * 0.6, R * 0.7), Ring(V3(0, R, 0), R, R), Ring(V3(0, R * 0.95, -0.3 * s), R * 0.75, R * 0.85)], m, seg: 20, ref: V3(0, 1, 0), smooth: 3))
        tailPiv.simdPosition = V3(0, R * 0.95, -0.3 * s)
        base.addChildNode(tailPiv)
        let tl = 0.5 * s * d.bodyLen
        tailPiv.addChildNode(loftNode([Ring(V3(0, 0, 0.02 * s), R * 0.75, R * 0.85), Ring(V3(0, 0, -tl * 0.5), R * 0.45, R * 0.55), Ring(V3(0, 0, -tl), R * 0.12, R * 0.15)], m, seg: 18, ref: V3(0, 1, 0), smooth: 3))
        let fin = Coats.plain(d.a * 0.8 + d.b * 0.2, rough: 0.4)
        if d.tail == .flat {
            for sd in [Float(1), -1] { tailPiv.addChildNode(sphereNode(CGFloat(0.2 * s), fin, seg: 12).scl(1, 0.12, 0.45).at(sd * 0.15 * s, 0, -tl - 0.05 * s).rot(0, sd * 0.4, 0)) }
        } else {
            for sd in [Float(1), -1] { tailPiv.addChildNode(sphereNode(CGFloat(0.2 * s), fin, seg: 12).scl(0.12, 1, 0.45).at(0, sd * 0.13 * s, -tl - 0.07 * s).rot(sd * 0.5, 0, 0)) }
        }
        attach = V3(0, R * 1.8, 0.12 * s)
        radius = max(0.3, R * 1.3)
        stride = 0.7 * s
    }

    private func buildBug(_ m: SCNMaterial, _ lm: SCNMaterial) {
        let spider = d.plan == .spider
        let crab = d.arms == .pincer && spider
        let h = (spider ? 0.2 : 0.24) * s * d.legLen
        let chit = d.coat == .bands || d.coat == .spots ? Coats.coat(.chitin, d.b, d.b) : m
        base.addChildNode(sphereNode(CGFloat(0.1 * s), chit, seg: 16).scl(crab ? 2.2 : 1, crab ? 0.7 : 1, crab ? 1.4 : 1.2).at(0, h, 0))
        if !crab {
            let abL = (spider ? 0.2 : 0.22) * s * d.bodyLen
            if d.name == "Lobster" {
                for k in 0..<5 { base.addChildNode(sphereNode(CGFloat(0.09 * s * (1 - Float(k) * 0.12)), m, seg: 14).scl(1.2, 0.8, 0.9).at(0, h, -0.14 * s - Float(k) * 0.1 * s)) }
                base.addChildNode(sphereNode(CGFloat(0.12 * s), m, seg: 12).scl(1.3, 0.2, 0.8).at(0, h - 0.02 * s, -0.68 * s))
            } else {
                base.addChildNode(sphereNode(CGFloat(abL), d.bugWings == .elytra ? chit : m, seg: 20).scl(0.8 * d.girth, 0.75 * d.girth, 1).at(0, h + 0.02 * s, -abL - 0.06 * s))
                if d.tail == .stinger { base.addChildNode(coneNode(CGFloat(0.02 * s), 0.001, CGFloat(0.08 * s), Mat.black, seg: 8).rot(-Float.pi / 2, 0, 0).at(0, h, -abL * 2 - 0.1 * s)) }
            }
        }
        let count = spider ? 4 : 3
        for k in 0..<count {
            for sd in [Float(1), -1] {
                let z = (Float(k) - Float(count - 1) / 2) * 0.07 * s
                let off: Float = ((k + (sd > 0 ? 0 : 1)) % 2 == 0) ? 0 : 0.5
                let spread = spider ? 0.75 : 0.5
                leg(at: V3(sd * 0.07 * s * (crab ? 1.8 : 1), h, z), up: 0.16 * s * (spider ? 1.3 : 1), lo: h * 1.25, th: 0.016 * s, lm, off: off, isHind: false, side: sd,
                    upDir: V3(sd, Float(spread), z * 3), loDir: V3(sd * 0.35, -1, z * 2), foot: false)
            }
        }
        attach = V3(0, h + 0.08 * s, 0.06 * s)
        radius = max(0.25, 0.25 * s * (spider ? 1.6 : 1))
        stride = 0.35 * s
        footPhases = [0, 0.5]
        mass = max(0.1, s * s * 0.5)
    }

    private func buildTentacles(_ m: SCNMaterial) {
        let h = 0.3 * s
        let jelly = d.name == "Jellyfish"
        let tm = jelly ? Coats.membrane(d.a, alpha: 0.55) : m
        base.addChildNode(sphereNode(CGFloat(0.16 * s), tm, seg: 20).scl(1.1, 0.55, 1.1).at(0, h, 0))
        for k in 0..<8 {
            let a = Float(k) / 8 * 2 * .pi
            let root = SCNNode(); root.simdPosition = V3(cosf(a) * 0.1 * s, h - 0.04 * s, sinf(a) * 0.1 * s)
            root.simdEulerAngles = V3(0, -a + .pi / 2, 0)
            base.addChildNode(root)
            let segs = chainLimb(root, count: 5, len: (jelly ? 0.12 : 0.1) * s, r0: (jelly ? 0.012 : 0.045) * s, r1: 0.008 * s, tm, dir: V3(0, -1, 0))
            tentacles.append(segs)
        }
        attach = V3(0, h + 0.06 * s, 0)
        radius = max(0.3, 0.3 * s)
        stride = 0.4 * s
        mass = max(0.2, s * s)
    }

    // MARK: animation

    override func bob(_ p: Pose) -> Float {
        switch d.plan {
        case .hopper, .fish: return abs(sinf(p.phase * .pi * 2)) * 0.18 * s * p.gait * (1 - p.air)
        case .quad: return mixf(-abs(wave(p.phase * 2, 0)) * 0.02, wave(p.phase, 0.3) * 0.06 * s, p.run) * p.gait * (1 - p.air)
        case .tentacle: return sinf(p.t * 2) * 0.02 * s + (d.name == "Jellyfish" ? 0.15 * s : 0)
        default: return -abs(wave(p.phase, 0)) * 0.025 * s * p.gait * (1 - p.air) - p.lay * 0.2 * s
        }
    }
    override func pitch(_ p: Pose) -> Float { d.plan == .quad ? (wave(p.phase, 0.1) * 0.06 * p.run * p.gait + p.kick * 0.25) : 0 }

    override func pose(_ p: Pose) {
        let g = p.gait
        switch d.plan {
        case .quad:
            for k in 0..<ups.count {
                let off = mixf(offs[k], [0, 0.1, 0.45, 0.58][k], p.run)
                let sw = wave(p.phase, off), c = wavec(p.phase, off)
                var u = -sw * (0.3 + 0.35 * p.run) * g
                var l = max(0, c) * (0.5 + 0.7 * p.run) * g
                if hind[k] { u += 0.06; l = -l * 0.9 - 0.08 }
                u = mixf(u, hind[k] ? 0.5 : -0.5, p.air * 0.7); l = mixf(l, hind[k] ? -0.8 : 1.0, p.air * 0.7)
                if hind[k] { u = mixf(u, 1.2, p.kick) }
                u = mixf(u, hind[k] ? 0.9 : -0.9, p.lay); l = mixf(l, hind[k] ? -2.1 : 2.2, p.lay)
                ups[k].simdEulerAngles = V3(u, 0, 0); los[k].simdEulerAngles = V3(l, 0, 0); feet[k].simdEulerAngles = V3(-(u + l) * 0.6, 0, 0)
            }
            let sw = sinf(p.t * 1.7) * 0.35
            tail?.simdEulerAngles = V3(p.run * 0.8 * g + p.kick * 0.5, 0, sw)
        case .sprawl:
            for k in 0..<ups.count {
                let sw = wave(p.phase, offs[k])
                let c = wavec(p.phase, offs[k])
                ups[k].simdEulerAngles = V3(0, sw * 0.6 * g * (hind[k] ? -1 : 1) * 0 + sw * 0.6 * g, sides[k] * max(0, c) * 0.5 * g)
                los[k].simdEulerAngles = V3(0, 0, -sides[k] * max(0, c) * 0.4 * g)
            }
            base.simdEulerAngles = V3(0, wave(p.phase, 0.25) * 0.14 * g, 0)
            tailPiv.simdEulerAngles = V3(0, -wave(p.phase, 0.1) * 0.35 * g + sinf(p.t * 1.1) * 0.1, 0)
        case .bird:
            for k in 0..<ups.count {
                let sw = wave(p.phase, offs[k]), c = wavec(p.phase, offs[k])
                var th = -0.5 - sw * (0.38 + 0.3 * p.run) * g
                var hk = 0.8 + max(0, c) * (0.6 + 0.6 * p.run) * g
                th = mixf(th, -1.0, p.air); hk = mixf(hk, 1.7, p.air)
                th = mixf(th, -1.25, p.lay); hk = mixf(hk, 2.1, p.lay)
                ups[k].simdEulerAngles = V3(th, 0, 0); los[k].simdEulerAngles = V3(hk, 0, 0); feet[k].simdEulerAngles = V3(-(th + hk), 0, 0)
            }
        case .biped:
            for k in 0..<ups.count {
                let sw = wave(p.phase, offs[k]), c = wavec(p.phase, offs[k])
                var hip = -sw * (0.32 + 0.38 * p.run) * g
                var knee = (0.08 + (0.35 + 1.0 * p.run) * max(0, c)) * g + 0.05
                hip = mixf(hip, k == 0 ? -0.7 : -0.25, p.air); knee = mixf(knee, k == 0 ? 1.1 : 0.6, p.air)
                hip = mixf(hip, -1.1, p.lay); knee = mixf(knee, 1.9, p.lay)
                let cs = wave(p.phase * 0.7, offs[k])
                hip = mixf(hip, -0.7 - cs * 0.5, p.climb); knee = mixf(knee, 1.0 + cs * 0.4, p.climb)
                ups[k].simdEulerAngles = V3(hip, 0, 0); los[k].simdEulerAngles = V3(knee, 0, 0); feet[k].simdEulerAngles = V3(-(hip + knee) * 0.4, 0, 0)
            }
            tail?.simdEulerAngles = V3(-0.4, sinf(p.t * 1.3) * 0.3, 0)
        case .hopper:
            let hop = max(0, sinf(p.phase * .pi * 2)) * g
            let fold = max(hop, p.air)
            for k in 0..<ups.count {
                let th = mixf(-1.0, -0.2, fold * 0.8)
                let kn = mixf(1.9, 0.6, fold * 0.8)
                ups[k].simdEulerAngles = V3(th, 0, 0); los[k].simdEulerAngles = V3(kn, 0, 0); feet[k].simdEulerAngles = V3(-(th + kn), 0, 0)
            }
            tail?.simdEulerAngles = V3(-0.2 + fold * 0.3, 0, 0)
        case .slither:
            let n = chain.count
            let len = 1.6 * s * d.bodyLen
            for i in 0..<n {
                let t = Float(i) / Float(n - 1)
                let z = 0.12 * s - t * len
                let rise = liftY * (1 - smoothstep(0, 0.22, t))
                let amp = (0.05 + 0.12 * t) * s * (0.3 + g)
                let x = sinf(p.phase * 2 * .pi * 1.0 - t * 7) * amp
                chain[i].simdPosition = V3(x, chainR[i] + rise, z)
            }
        case .fish:
            tailPiv.simdEulerAngles = V3(0, sinf(p.phase * 2 * .pi) * 0.45 * (0.3 + g) + sinf(p.t * 3) * 0.08, 0)
            base.simdEulerAngles = V3(0, 0, sinf(p.phase * 2 * .pi) * 0.1 * g)
        case .insect, .spider:
            for k in 0..<ups.count {
                let sw = wave(p.phase, offs[k]), c = wavec(p.phase, offs[k])
                ups[k].simdEulerAngles = V3(0, sw * 0.4 * g, sides[k] * max(0, c) * 0.35 * g)
                los[k].simdEulerAngles = V3(0, 0, 0)
            }
        case .tentacle:
            for (k, segs) in tentacles.enumerated() {
                for (j, n) in segs.enumerated() {
                    let wv = sinf(p.t * 2.5 + Float(k) * 0.8 + Float(j) * 0.7) * 0.25
                    let walk = sinf(p.phase * 2 * .pi + Float(k) * .pi / 4) * 0.3 * g
                    n.simdEulerAngles = V3(j == 0 ? -1.0 + walk : 0.35 + wv, 0, 0)
                }
            }
        }
    }
}

// MARK: - Bodies

final class GenTorso: TorsoPart {
    let d: SpeciesDef
    let horizontal: Bool
    private var shoulders: [SCNNode] = [], elbows: [SCNNode] = [], hands: [SCNNode] = []
    private var tentArms: [[SCNNode]] = []
    private var wings: [SCNNode] = [], bugW: [SCNNode] = []
    private var pincers: [SCNNode] = []
    private let tailFan = SCNNode()
    private let s: Float
    let body = SCNNode()

    init(_ d: SpeciesDef, horizontal: Bool) {
        self.d = d
        self.horizontal = horizontal
        s = d.size
        super.init(Species(id: Zoo.defs.firstIndex(where: { $0.name == d.name }) ?? 0))
        node.addChildNode(body)
        anchor = body
        let m = Coats.coat(d)
        mass = max(0.15, 1.8 * s * s * s * d.girth)
        if horizontal { buildHorizontal(m) } else { buildUpright(m) }
        if d.bugWings != .none { buildBugWings(); flight = d.bugWings == .elytra ? 1 : 2 }
        if d.arms == .wing || d.arms == .batWing { flight = max(flight, 1) }
        hasWings = flight > 0
        canGrab = d.arms == .hands && !horizontal
    }

    private func buildUpright(_ m: SCNMaterial) {
        let bird = d.plan == .bird
        let H: Float = (bird ? 0.56 : 0.54) * s
        let w = (bird ? 0.25 : 0.2) * s * d.girth, dd = (bird ? 0.25 : 0.14) * s * d.girth
        let fz: Float = bird ? 0.05 * s : 0.01 * s
        body.addChildNode(furry(loftNode([Ring(V3(0, -0.08 * s, 0), w * 0.85, dd * 0.85), Ring(V3(0, H * 0.12, 0), w * 0.97, dd), Ring(V3(0, H * 0.38, fz), w * 1.04, dd * 1.06),
                                    Ring(V3(0, H * 0.64, fz * 0.8), w * 0.95, dd * 0.92), Ring(V3(0, H * 0.84, fz * 0.5), w * 0.72, dd * 0.7), Ring(V3(0, H * 0.97, fz * 0.3), w * 0.38, dd * 0.4),
                                    Ring(V3(0, H * 1.03, fz * 0.3), w * 0.3, dd * 0.32)], m, seg: 24, smooth: 4, vScale: 0.8), d))
        neck = V3(0, H * 0.99, fz * 0.3)
        carry = V3(0, H * 0.5, dd + 0.25)
        // back decorations
        if d.hump { body.addChildNode(sphereNode(CGFloat(w * 0.7), m, seg: 16).scl(1, 0.9, 0.8).at(0, H * 0.6, -dd * 0.8)) }
        if d.shell {
            let sh = Coats.coat(.shell, d.a, d.b)
            body.addChildNode(sphereNode(CGFloat(w * 1.1), sh, seg: 22).scl(1, 1.2, 0.55).at(0, H * 0.45, -dd * 0.55))
        }
        if d.dorsal { body.addChildNode(coneNode(CGFloat(0.12 * s), 0.01, CGFloat(0.3 * s), m, seg: 12).scl(0.2, 1, 1).rot(-0.6, 0, 0).at(0, H * 0.55, -dd - 0.05 * s)) }
        if d.spikes { addBackSpikes(H: H, w: w, dd: dd) }
        if bird { buildBirdTail(dd) }
        let sh = V3(w * 0.95, H * 0.8, 0)
        buildArms(m, sh, H)
    }

    private func buildHorizontal(_ m: SCNMaterial) {
        switch d.plan {
        case .fish:
            let R = 0.2 * s * d.girth
            // attach is above the fish body: continue the body forward to the head
            body.addChildNode(loftNode([Ring(V3(0, -R * 0.85, -0.1 * s), R * 0.62, R * 0.72), Ring(V3(0, -R * 0.85, 0.1 * s), R * 0.55, R * 0.62), Ring(V3(0, -R * 0.9, 0.22 * s), R * 0.3, R * 0.35)],
                                       m, seg: 18, ref: V3(0, 1, 0), smooth: 3))
            neck = V3(0, -R * 0.9, 0.18 * s); neckRot = 1.5
            if d.dorsal { body.addChildNode(coneNode(CGFloat(0.12 * s), 0.01, CGFloat(0.3 * s), m, seg: 12).scl(0.2, 1, 1).rot(-0.5, 0, 0).at(0, 0.02 * s, -0.12 * s)) }
            if d.spikes { addBackSpikes(H: 0, w: R, dd: R) }
            for sd in [Float(1), -1] { body.addChildNode(sphereNode(CGFloat(0.1 * s), m, seg: 10).scl(0.15, 0.5, 1).at(sd * R * 0.9, -R * 1.2, 0.05 * s).rot(0, 0, sd * 0.8)) }
        case .insect, .spider:
            neck = V3(0, -0.06 * s, 0.07 * s); neckRot = 1.35
            if d.arms == .pincer { buildArms(m, V3(0.1 * s, -0.08 * s, 0.05 * s), 0.3 * s) }
        case .slither:
            neck = V3(0, -0.02 * s, 0.02 * s); neckRot = 0.95
            if d.hood { body.addChildNode(sphereNode(CGFloat(0.14 * s), m, seg: 16).scl(1.3, 1.1, 0.12).at(0, 0.1 * s, -0.02 * s)) }
        case .tentacle:
            neck = V3(0, 0, 0)
        default:
            // quad, sprawl, hopper: continue the barrel into chest and neck
            let quad = d.plan == .quad
            let R = (quad ? 0.3 : d.plan == .sprawl ? 0.2 : 0.17) * s * d.girth
            let dy: Float = quad ? -R * 0.6 : -R * 0.55
            body.addChildNode(furry(loftNode([Ring(V3(0, dy, -0.15 * s), R, R * (quad ? 1 : 0.75)), Ring(V3(0, dy + R * 0.1, 0.12 * s), R * 0.88, R * 0.8), Ring(V3(0, dy + R * 0.35, 0.28 * s), R * 0.62, R * 0.6),
                                        Ring(V3(0, dy + R * 0.55, 0.38 * s), R * 0.45, R * 0.45), Ring(V3(0, dy + R * 0.65, 0.44 * s), R * 0.35, R * 0.35)], m, seg: 22, ref: V3(0, 1, 0), smooth: 3, vScale: 0.8), d))
            neck = V3(0, dy + R * 0.6, 0.4 * s)
            neckRot = d.plan == .sprawl ? 1.3 : d.neck > 0.7 ? 0.2 : 0.4
            if d.plan == .hopper {
                // little front paws reaching the ground
                for sd in [Float(1), -1] {
                    let sh = SCNNode(); sh.simdPosition = V3(sd * R * 0.6, dy, 0.25 * s)
                    body.addChildNode(sh)
                    let len = max(0.05, -dy + 0.3 * s * d.legLen * 0.9)
                    sh.addChildNode(limb(len, 0.035 * s, 0.025 * s, m, seg: 8))
                    shoulders.append(sh)
                }
            }
            if d.hump { body.addChildNode(sphereNode(CGFloat(R * 0.55), m, seg: 16).scl(1, 0.9, 1.1).at(0, dy + R * 1.05, 0.02 * s)) }
            if d.mane && quad { body.addChildNode(loftNode([Ring(V3(0, dy + R * 0.9, -0.05 * s), 0.04 * s, 0.02 * s), Ring(V3(0, dy + R * 1.0, 0.2 * s), 0.05 * s, 0.03 * s), Ring(V3(0, dy + R * 0.95, 0.42 * s), 0.02 * s, 0.02 * s)], Coats.plain(d.b, rough: 0.9), seg: 10, ref: V3(0, 1, 0), smooth: 3)) }
        }
    }

    private func addBackSpikes(H: Float, w: Float, dd: Float) {
        var rr = RNG(9)
        let q = Coats.plain(d.b, rough: 0.6)
        for _ in 0..<40 {
            let a = rr.range(-1.3, 1.3), y = rr.range(0.1, 0.9)
            let dir = simd_normalize(V3(sinf(a) * 0.8, 0.3, -cosf(a)))
            let c = coneNode(CGFloat(0.012 * s), 0.001, CGFloat(0.12 * s), q, seg: 5)
            c.simdPosition = V3(sinf(a) * w, H * y, -cosf(a) * dd)
            c.simdOrientation = simd_quatf(from: V3(0, 1, 0), to: dir)
            body.addChildNode(c)
        }
    }

    private func buildBirdTail(_ dd: Float) {
        tailFan.simdPosition = V3(0, 0.08 * s, -dd * 0.8)
        body.addChildNode(tailFan)
        let fm = Coats.plain(d.b, rough: 0.4)
        switch d.tail {
        case .fan:
            let big = d.name == "Peacock"
            let n = big ? 15 : 9
            for k in 0..<n {
                let a = (Float(k) / Float(n - 1) - 0.5) * (big ? 2.6 : 1.8)
                let f = SCNNode(); f.simdEulerAngles = V3(0, 0, a)
                tailFan.addChildNode(f)
                let len: Float = (big ? 1.0 : 0.4) * s
                f.addChildNode(loftNode([Ring(V3(0, 0, 0), 0.02 * s, 0.006 * s), Ring(V3(0, len * 0.5, -len * 0.25), 0.05 * s, 0.008 * s), Ring(V3(0, len, -len * 0.3), 0.04 * s, 0.006 * s),
                                         Ring(V3(0, len * 1.05, -len * 0.3), 0.005, 0.003)], fm, seg: 8, ref: V3(0, 0, 1), smooth: 2))
                if big { f.addChildNode(sphereNode(CGFloat(0.045 * s), Coats.plain(V3(0.1, 0.5, 0.35), rough: 0.3), seg: 8).scl(1, 1, 0.2).at(0, len * 0.93, -len * 0.3 + 0.006)) }
            }
        case .long:
            for k in 0..<3 { tailFan.addChildNode(limb(0.5 * s, 0.03 * s, 0.01 * s, fm, seg: 6, dir: V3((Float(k) - 1) * 0.1, -0.5, -1)).scl(1, 1, 0.3)) }
        case .fluffy:
            tailFan.addChildNode(sphereNode(CGFloat(0.14 * s), Coats.plain(V3(0.92, 0.9, 0.88), rough: 0.9), seg: 12).scl(1, 0.8, 1.2))
        default:
            tailFan.addChildNode(sphereNode(CGFloat(0.09 * s), Coats.coat(d), seg: 10).scl(1, 0.5, 1.2))
        }
    }

    private func buildBugWings() {
        let wm: SCNMaterial
        switch d.bugWings {
        case .big: wm = Coats.membrane(d.wingCol ?? d.b, alpha: 0.95)
        case .elytra: wm = Coats.coat(d)
        default: wm = Coats.membrane(V3(0.85, 0.9, 0.95), alpha: 0.35)
        }
        let y: Float = horizontal ? 0.02 * s : 0.4 * s, z: Float = horizontal ? -0.05 * s : -0.12 * s * d.girth
        for sd in [Float(1), -1] {
            let w = SCNNode(); w.simdPosition = V3(sd * 0.05 * s, y, z)
            body.addChildNode(w)
            switch d.bugWings {
            case .big:
                w.addChildNode(sphereNode(CGFloat(0.3 * s), wm, seg: 14).scl(1, 0.03, 0.8).at(sd * 0.28 * s, 0, 0.08 * s))
                w.addChildNode(sphereNode(CGFloat(0.22 * s), wm, seg: 14).scl(1, 0.03, 0.8).at(sd * 0.2 * s, -0.01, -0.2 * s))
            case .elytra:
                w.addChildNode(sphereNode(CGFloat(0.15 * s * d.girth), wm, seg: 16).scl(0.55, 0.55, 1.1).at(sd * 0.05 * s, 0.02 * s, -0.12 * s))
            default:
                w.addChildNode(sphereNode(CGFloat(0.16 * s), wm, seg: 12).scl(1, 0.03, 0.4).at(sd * 0.15 * s, 0, 0))
            }
            bugW.append(w)
        }
    }

    private func buildArms(_ m: SCNMaterial, _ sh: V3, _ H: Float) {
        let lm = Coats.limbMat(d)
        let th = 0.05 * s * sqrtf(d.girth)
        for sd in [Float(1), -1] {
            let sn = SCNNode(); sn.simdPosition = V3(sh.x * sd, sh.y, sh.z)
            body.addChildNode(sn)
            let e = SCNNode(), hnd = SCNNode()
            switch d.arms {
            case .hands, .paw, .hoof:
                let ape: Float = d.plan == .biped && d.arms == .hands ? (d.name == "Monkey" || d.name == "Meerkat" ? 1.2 : 1.6) : 1
                let up = 0.28 * s * ape, lo = 0.26 * s * ape
                sn.addChildNode(sphereNode(CGFloat(th * 1.1), m, seg: 12))
                sn.addChildNode(furry(muscleLimb(up, top: th * (d.arms == .hoof ? 1.6 : 1.3), mid: th * 1.0, bottom: th * 0.8, m, depth: 1.1), d))
                e.simdPosition = V3(0, -up, 0); sn.addChildNode(e)
                e.addChildNode(limb(lo, th * 0.85, th * 0.65, d.arms == .hands && d.limbCol != nil ? m : m, seg: 10))
                hnd.simdPosition = V3(0, -lo, 0); e.addChildNode(hnd)
                if d.arms == .hands {
                    hnd.addChildNode(loftNode([Ring(V3(0, 0, 0), th * 0.6, th * 0.4), Ring(V3(0, -0.04 * s, 0.005), th * 0.85, th * 0.35, e: 2.6), Ring(V3(0, -0.1 * s, 0.01), th * 0.75, th * 0.3, e: 2.4),
                                               Ring(V3(0, -0.12 * s, 0.012), th * 0.2, th * 0.15)], lm, seg: 12, smooth: 3))
                } else if d.arms == .hoof {
                    hnd.addChildNode(coneNode(CGFloat(th * 1.0), CGFloat(th * 0.8), CGFloat(th * 1.3), Mat.hoof).at(0, -th * 0.6, 0.005))
                } else {
                    hnd.addChildNode(sphereNode(CGFloat(th * 1.2), m, seg: 12).scl(1, 0.7, 1.2).at(0, -th * 0.5, th * 0.2))
                    for k in -1...1 { hnd.addChildNode(coneNode(CGFloat(th * 0.12), 0.001, CGFloat(th * 0.5), Mat.claw, seg: 6).rot(Float.pi / 2, 0, 0).at(Float(k) * th * 0.45, -th * 0.8, th * 1.3)) }
                }
            case .wing:
                let big: Float = d.name == "Eagle" ? 1.5 : 1
                let wm = Coats.coat(d)
                sn.addChildNode(loftNode([Ring(V3(0, 0.04 * s, 0.02 * s), 0.03 * s, 0.07 * s), Ring(V3(0, -0.06 * s, 0), 0.05 * s, 0.13 * s * big), Ring(V3(0, -0.2 * s * big, -0.05 * s), 0.045 * s, 0.14 * s * big),
                                          Ring(V3(0, -0.34 * s * big, -0.1 * s), 0.03 * s, 0.1 * s * big), Ring(V3(0, -0.44 * s * big, -0.15 * s), 0.012 * s, 0.04 * s)], wm, seg: 16, smooth: 3))
                wings.append(sn)
            case .batWing:
                let mem = Coats.membrane(d.wingCol ?? d.b, alpha: 0.92)
                sn.addChildNode(limb(0.25 * s, th * 0.6, th * 0.4, m, seg: 8))
                sn.addChildNode(sphereNode(CGFloat(0.3 * s), mem, seg: 14).scl(0.04, 1, 0.9).at(0, -0.25 * s, -0.08 * s))
                wings.append(sn)
            case .fin:
                sn.addChildNode(sphereNode(CGFloat(0.16 * s), m, seg: 12).scl(0.18, 1, 0.45).at(0, -0.13 * s, 0))
            case .pincer:
                let chit = Coats.coat(d)
                sn.addChildNode(limb(0.18 * s, th * 0.8, th * 0.7, chit, seg: 8, dir: V3(sd * 0.4, -0.5, 1)))
                hnd.simdPosition = simd_normalize(V3(sd * 0.4, -0.5, 1)) * 0.18 * s
                sn.addChildNode(hnd)
                hnd.addChildNode(sphereNode(CGFloat(0.08 * s), chit, seg: 12).scl(0.8, 0.6, 1.2).at(0, 0, 0.05 * s))
                hnd.addChildNode(coneNode(CGFloat(0.035 * s), 0.004, CGFloat(0.12 * s), chit, seg: 8).rot(Float.pi / 2, 0, 0).at(0, 0.02 * s, 0.15 * s))
                let jaw = SCNNode(); jaw.simdPosition = V3(0, -0.02 * s, 0.1 * s)
                hnd.addChildNode(jaw)
                jaw.addChildNode(coneNode(CGFloat(0.025 * s), 0.004, CGFloat(0.1 * s), chit, seg: 8).rot(Float.pi / 2, 0, 0).at(0, 0, 0.05 * s))
                pincers.append(jaw)
            case .tentacles:
                tentArms.append(chainLimb(sn, count: 5, len: 0.09 * s, r0: 0.035 * s, r1: 0.008 * s, m))
            case .insect:
                sn.addChildNode(limb(0.14 * s, 0.014 * s, 0.01 * s, Coats.limbMat(d), seg: 6, dir: V3(sd, 0.2, 0.3)))
                e.simdPosition = simd_normalize(V3(sd, 0.2, 0.3)) * 0.14 * s; sn.addChildNode(e)
                e.addChildNode(limb(0.16 * s, 0.01 * s, 0.007 * s, Coats.limbMat(d), seg: 6))
            case .none: break
            }
            shoulders.append(sn); elbows.append(e); hands.append(hnd)
        }
    }

    override func pose(_ p: Pose) {
        let g = p.gait
        if d.special == .puff {
            let pf = p.shove > 0 ? 1 + p.shove * 0.8 : 1
            body.simdScale = V3(repeating: pf)
        }
        if horizontal {
            if d.plan == .hopper {
                for (i, sh) in shoulders.enumerated() { sh.simdEulerAngles = V3(wave(p.phase, Float(i) * 0.1) * 0.4 * g, 0, 0) }
            }
            for (i, w) in bugW.enumerated() {
                let sd: Float = i == 0 ? 1 : -1
                let fly = max(p.flap, p.glide, p.air)
                w.simdEulerAngles = V3(0, 0, sd * (d.bugWings == .elytra ? fly * 0.8 : sinf(p.t * 60) * 0.5 * fly + 0.1))
            }
            return
        }
        for i in 0..<shoulders.count {
            let side: Float = i == 0 ? 1 : -1
            let sw = wave(p.phase, i == 0 ? 0.5 : 0)
            switch d.arms {
            case .hands, .paw, .hoof, .insect:
                var sx = -sw * (0.28 + 0.5 * p.run) * g
                var sz = side * 0.08
                var ex = -(0.12 + 0.8 * p.run * g)
                sz = mixf(sz, side * 0.55, p.air * 0.7)
                sx = mixf(sx, -1.15, p.carry); sz = mixf(sz, -side * 0.28, p.carry); ex = mixf(ex, -0.55, p.carry)
                sx = mixf(sx, -1.5, p.shove); ex = mixf(ex, -0.1, p.shove)
                let cs = wave(p.phase * 0.7, i == 0 ? 0.5 : 0)
                sx = mixf(sx, -2.6 - cs * 0.35, p.climb); ex = mixf(ex, -0.4 + cs * 0.3, p.climb)
                if p.throwT >= 0 && i == 1 {
                    let t = p.throwT
                    sx = mixf(mixf(sx, -2.7, smoothstep(0, 0.35, t)), -0.7, smoothstep(0.35, 0.6, t))
                }
                if p.talk > 0 && i == 1 { sx -= 0.35 * p.talk }
                shoulders[i].simdEulerAngles = V3(sx, 0, sz)
                elbows[i].simdEulerAngles = V3(ex, 0, 0)
            case .wing, .batWing:
                let spread = max(p.glide, min(1, p.flap * 1.5), p.air * 0.25, p.shove)
                let beat = sinf(p.t * 22) * 0.75 * max(p.flap, p.shove)
                shoulders[i].simdEulerAngles = V3(0.15 - spread * 0.1, side * spread * 0.2, side * (spread * 1.45 + beat))
                shoulders[i].simdScale = V3(1 + spread * 0.3, 1 + spread * 0.55, 1 + spread * 0.35)
            case .fin:
                shoulders[i].simdEulerAngles = V3(sw * 0.3 * g, 0, side * (0.3 + max(p.shove, p.air) * 0.8 + sinf(p.t * 3) * 0.05))
            case .pincer:
                shoulders[i].simdEulerAngles = V3(-p.shove * 0.6 + sw * 0.1 * g, side * 0.2, 0)
                if i < pincers.count { pincers[i].simdEulerAngles = V3(0.1 + (0.5 + 0.5 * sinf(p.t * 8)) * 0.5 * max(p.shove, p.talk), 0, 0) }
            case .tentacles:
                for (j, n) in tentArms[i].enumerated() { n.simdEulerAngles = V3(sinf(p.t * 3 + Float(j) + Float(i)) * 0.3 - p.shove * 0.3, 0, side * 0.2) }
            case .none: break
            }
        }
        for (i, w) in bugW.enumerated() {
            let sd: Float = i == 0 ? 1 : -1
            let fly = max(p.flap, p.glide, p.air)
            w.simdEulerAngles = V3(0.2, 0, sd * (d.bugWings == .elytra ? fly * 0.8 : sinf(p.t * 60) * 0.5 * fly + 0.2))
        }
        tailFan.simdEulerAngles = V3(-0.25 - p.glide * 0.3 - (d.name == "Peacock" ? 0.6 : 0), 0, sinf(p.t * 2) * 0.04)
    }
}

// MARK: - Heads

final class GenHead: HeadPart {
    let d: SpeciesDef
    private let neckNode = SCNNode(), skull = SCNNode(), jaw = SCNNode()
    private var ears: [SCNNode] = [], trunk: [SCNNode] = [], ants: [SCNNode] = []
    private let s: Float
    private var earT: Float = 2

    init(_ d: SpeciesDef) {
        self.d = d
        s = d.size
        super.init(Species(id: Zoo.defs.firstIndex(where: { $0.name == d.name }) ?? 0))
        let m = Coats.coat(d)
        let bug = d.plan == .insect || d.plan == .spider
        let fish = d.plan == .fish || d.plan == .tentacle
        let bird = d.plan == .bird
        node.addChildNode(neckNode)
        anchor = skull
        let nl = d.neck * s
        let nr: Float = (bird ? 0.05 : d.plan == .quad ? 0.12 : 0.09) * s * sqrtf(d.girth) * (bug ? 0.45 : 1) * (d.neck > 1.2 ? 0.65 : 1)
        let tilt: Float = 0.3
        let tip = V3(0, nl * cosf(tilt), nl * sinf(tilt) + 0.02 * s)
        if nl > 0.02 && !fish {
            let nm = d.mane && d.plan != .quad ? Coats.coat(d) : m
            neckNode.addChildNode(furry(loftNode([Ring(V3(0, -0.1 * s, -0.03 * s), nr * 1.45, nr * 1.8), Ring(tip * 0.45, nr * 1.0, nr * 1.35), Ring(tip * 0.9, nr * 0.85, nr * 1.05), Ring(tip + V3(0, 0, 0.02 * s), nr * 0.7, nr * 0.8)], nm, seg: 18, ref: V3(0, 0, 1), smooth: 3, vScale: 0.8), d))
        }
        skull.simdPosition = tip
        skull.simdEulerAngles = V3(bird || bug || d.eyeFront ? 0.05 : 0.15, 0, 0)
        neckNode.addChildNode(skull)
        let cr: Float = (bug ? 0.07 : fish ? 0.15 : bird ? 0.07 : 0.12) * s * d.headW
        let rawSnout = d.snout * s
        let sl: Float = d.mouth == .flat ? 0.05 * s : (bird || bug ? 0.02 * s : rawSnout * (d.snout < 0.3 && d.mouth == .snout ? 0.5 : 0.72))
        let tz = sl + cr * 0.55
        height = tip.y + cr * 1.6
        mouth = V3(0, tip.y, tip.z + tz)
        // skull: a round cranium, a forehead "stop", then the muzzle blending out of the cheeks
        let catLike = sl < 0.3 * s && !bird && !bug && d.mouth == .snout
        let snoutW: Float = d.mouth == .croc ? 0.55 : d.mouth == .hippo ? 1.0 : d.mouth == .needle ? 0.25 : catLike ? 0.72 : 0.58
        let snoutH: Float = d.mouth == .croc ? 0.3 : d.mouth == .hippo ? 0.8 : d.mouth == .needle ? 0.25 : catLike ? 0.58 : 0.52
        var rings: [Ring] = [Ring(V3(0, 0.05 * cr, -cr * 0.95), cr * 0.25, cr * 0.25), Ring(V3(0, 0.06 * cr, -cr * 0.7), cr * 0.82, cr * 0.85),
                             Ring(V3(0, 0.04 * cr, -cr * 0.25), cr * 1.0, cr * 1.0), Ring(V3(0, 0, cr * 0.2), cr * 0.96, cr * 0.92),
                             Ring(V3(0, -0.08 * cr, cr * 0.55), cr * 0.82, cr * 0.76)]
        if sl > 0.04 * s {
            rings.append(Ring(V3(0, -0.2 * cr, cr * 0.55 + sl * 0.3), cr * mixf(0.8, snoutW, 0.5), cr * mixf(0.72, snoutH, 0.6)))
            rings.append(Ring(V3(0, -0.26 * cr, cr * 0.5 + sl * 0.75), cr * snoutW * 1.02, cr * snoutH))
            rings.append(Ring(V3(0, -0.24 * cr, tz), cr * snoutW * 0.92, cr * snoutH * 0.88))
            rings.append(Ring(V3(0, -0.22 * cr, tz + cr * 0.12), cr * snoutW * 0.45, cr * snoutH * 0.45))
        } else {
            rings.append(Ring(V3(0, -0.1 * cr, cr * 0.9), cr * 0.6, cr * 0.58))
            rings.append(Ring(V3(0, -0.1 * cr, cr * 1.03), cr * 0.22, cr * 0.2))
        }
        let eyeZ: Float = d.eyeFront ? cr * 0.82 : cr * (bug ? 0.45 : 0.35)
        skull.addChildNode(furry(loftNode(rings, m, seg: 26, ref: V3(0, 1, 0), smooth: 4, vScale: 0.8) { p, _, _, _ in
            var dd: Float = 0
            // brow ridge over each eye, cheekbones, and sockets for the eyes to sit in
            for sx in [Float(1), -1] {
                let e = V3(sx * cr * (d.eyeFront ? 0.42 : 0.75), cr * 0.3, eyeZ)
                let q = p - e
                dd -= expf(-simd_length_squared(q) / (cr * cr * 0.03)) * cr * 0.12
                let brow = p - (e + V3(0, cr * 0.2, -cr * 0.05))
                dd += expf(-simd_length_squared(brow) / (cr * cr * 0.04)) * cr * 0.08
                let cheek = p - V3(sx * cr * 0.7, -cr * 0.2, cr * 0.4)
                dd += expf(-simd_length_squared(cheek) / (cr * cr * 0.08)) * cr * (catLike ? 0.14 : 0.07)
            }
            return dd
        }, d))
        let nose = Coats.glossy(d.noseCol)
        let beakM = Coats.plain(d.beakCol, rough: 0.35)
        jaw.simdPosition = V3(0, -0.45 * cr, cr * 0.1)
        skull.addChildNode(jaw)
        switch d.mouth {
        case .snout, .needle, .croc, .hippo:
            if d.mouth == .snout { skull.addChildNode(sphereNode(CGFloat(cr * 0.3), nose, seg: 12).scl(1.2, 0.8, 0.6).at(0, -0.12 * cr, tz + cr * 0.02)) }
            let jl = tz - cr * 0.1
            jaw.addChildNode(loftNode([Ring(V3(0, 0, -cr * 0.2), cr * snoutW * 0.8, cr * 0.2), Ring(V3(0, -0.02 * cr, jl * 0.8), cr * snoutW * 0.8, cr * 0.18), Ring(V3(0, 0, jl), cr * snoutW * 0.4, cr * 0.1)],
                                      m, seg: 12, ref: V3(0, 1, 0), smooth: 2))
            if d.mouth == .croc || d.name == "Shark" {
                for k in 0..<10 {
                    let z = cr * 0.4 + Float(k) * (tz - cr * 0.4) / 10
                    for sd in [Float(1), -1] { skull.addChildNode(coneNode(CGFloat(0.008 * s), 0.001, CGFloat(0.025 * s), Mat.horn, seg: 5).rot(Float.pi, 0, 0).at(sd * cr * snoutW * 0.85, -0.45 * cr, z)) }
                }
            }
            if d.mouth == .hippo { for sd in [Float(1), -1] { skull.addChildNode(sphereNode(CGFloat(cr * 0.2), nose, seg: 8).at(sd * cr * 0.3, cr * 0.25, tz)) } }
        case .pig:
            skull.addChildNode(cylNode(CGFloat(cr * 0.38), CGFloat(cr * 0.2), Coats.plain(d.noseCol, rough: 0.4), seg: 18).rot(Float.pi / 2, 0, 0).at(0, -0.15 * cr, tz))
            for sd in [Float(1), -1] { skull.addChildNode(sphereNode(CGFloat(cr * 0.08), Mat.black, seg: 8).at(sd * cr * 0.13, -0.15 * cr, tz + cr * 0.1)) }
            jaw.addChildNode(loftNode([Ring(V3(0, 0, 0), cr * 0.4, cr * 0.15), Ring(V3(0, 0, tz * 0.9), cr * 0.3, cr * 0.1)], m, seg: 10, ref: V3(0, 1, 0), smooth: 1))
        case .beak, .hooked, .bigBeak, .needle, .pouch, .bill:
            let bl: Float, bw: Float, bh: Float, droop: Float
            switch d.mouth {
            case .hooked: bl = cr * 1.0; bw = cr * 0.35; bh = cr * 0.4; droop = cr * 0.35
            case .bigBeak: bl = cr * 2.4; bw = cr * 0.4; bh = cr * 0.6; droop = cr * 0.2
            case .needle: bl = cr * 2.6; bw = cr * 0.08; bh = cr * 0.08; droop = 0
            case .pouch: bl = cr * 3.0; bw = cr * 0.3; bh = cr * 0.2; droop = cr * 0.1
            case .bill: bl = cr * 1.4; bw = cr * 0.5; bh = cr * 0.14; droop = 0
            default: bl = cr * 0.9; bw = cr * 0.28; bh = cr * 0.24; droop = cr * 0.15
            }
            let z0 = cr * 0.8
            skull.addChildNode(loftNode([Ring(V3(0, 0, z0), bw, bh), Ring(V3(0, -droop * 0.3, z0 + bl * 0.5), bw * 0.8, bh * 0.7), Ring(V3(0, -droop, z0 + bl), bw * (d.mouth == .bill ? 0.8 : 0.15), bh * 0.2)],
                                        beakM, seg: 12, ref: V3(0, 1, 0), smooth: 3))
            jaw.simdPosition = V3(0, -bh * 0.7, z0)
            jaw.addChildNode(loftNode([Ring(V3(0, 0, 0), bw * 0.8, bh * 0.4), Ring(V3(0, 0, bl * 0.85), bw * (d.mouth == .bill ? 0.7 : 0.1), bh * 0.15)], beakM, seg: 10, ref: V3(0, 1, 0), smooth: 1))
            if d.mouth == .pouch { jaw.addChildNode(sphereNode(CGFloat(bl * 0.3), Coats.plain(d.beakCol * 0.9, rough: 0.5), seg: 12).scl(0.6, 0.6, 1.6).at(0, -bl * 0.12, bl * 0.45)) }
            mouth = V3(0, tip.y, tip.z + z0 + bl)
        case .trunk:
            var p: SCNNode = skull
            let segs = 9
            for k in 0..<segs {
                let n = SCNNode()
                n.simdPosition = k == 0 ? V3(0, -0.2 * cr, tz) : V3(0, 0, 0.11 * s)
                p.addChildNode(n)
                let r0 = cr * (0.35 - Float(k) * 0.025)
                n.addChildNode(limb(0.12 * s, r0, r0 * 0.9, m, seg: 12, dir: V3(0, 0, 1)))
                trunk.append(n)
                p = n
            }
        case .flat:
            skull.addChildNode(sphereNode(CGFloat(cr * 0.62), Coats.limbMat(d), seg: 16).scl(1.05, 0.95, 0.5).at(0, -0.1 * cr, cr * 0.72))
            skull.addChildNode(sphereNode(CGFloat(cr * 0.14), nose, seg: 10).scl(1.3, 0.8, 0.8).at(0, -0.12 * cr, cr * 1.05))
            jaw.addChildNode(sphereNode(CGFloat(cr * 0.4), Coats.limbMat(d), seg: 12).scl(1, 0.5, 0.6).at(0, 0, cr * 0.75))
        case .fish:
            let t = SCNTorus(ringRadius: CGFloat(cr * 0.18), pipeRadius: CGFloat(cr * 0.06)); t.materials = [Coats.plain(d.a * 0.8, rough: 0.4)]
            skull.addChildNode(SCNNode(geometry: t).rot(Float.pi / 2, 0, 0).at(0, -0.15 * cr, cr * 1.0))
        case .mandibles:
            for sd in [Float(1), -1] {
                let mnd = coneNode(CGFloat(cr * 0.15), 0.002, CGFloat(cr * 0.7), Coats.plain(d.b * 0.5), seg: 6)
                mnd.simdPosition = V3(sd * cr * 0.25, -0.35 * cr, cr * 1.1)
                mnd.simdEulerAngles = V3(Float.pi / 2, 0, sd * 0.4)
                jaw.addChildNode(mnd)
            }
        }
        // eyes
        if d.eyeSize > 0 {
            let er = (bug ? 0.03 : 0.022) * s * d.eyeSize * (fish ? 1.2 : 1)
            let eyeM = Coats.glossy(d.eyeCol)
            for sd in [Float(1), -1] {
                let pos = d.eyeFront ? V3(sd * cr * 0.42, cr * 0.3, cr * 0.8) : V3(sd * cr * 0.72, cr * 0.3, cr * (bug ? 0.45 : 0.35))
                skull.addChildNode(sphereNode(CGFloat(er), eyeM, seg: 16).at(pos.x, pos.y, pos.z))
                if !bug && !fish {
                    let lid = SCNTorus(ringRadius: CGFloat(er * 0.95), pipeRadius: CGFloat(er * 0.22)); lid.materials = [Coats.plain(d.a * 0.35, rough: 0.8)]
                    let ln = SCNNode(geometry: lid)
                    ln.simdPosition = pos
                    ln.simdOrientation = simd_quatf(from: V3(0, 1, 0), to: d.eyeFront ? V3(0, 0, 1) : simd_normalize(V3(sd, 0, 0.35)))
                    skull.addChildNode(ln)
                }
                if d.eyeFront || d.eyeSize > 1.4 {
                    let pupil = sphereNode(CGFloat(er * 0.5), Mat.eyeBlack, seg: 10).scl(1, 1, 0.4)
                    pupil.simdPosition = pos + (d.eyeFront ? V3(0, 0, er * 0.85) : V3(sd * er * 0.85, 0, 0))
                    if !d.eyeFront { pupil.simdScale = V3(0.4, 1, 1) }
                    skull.addChildNode(pupil)
                }
            }
        }
        // ears
        let earM = m
        for sd in [Float(1), -1] {
            let e = SCNNode(); e.simdPosition = V3(sd * cr * 0.7, cr * 0.72, -cr * 0.25)
            skull.addChildNode(e)
            switch d.ears {
            case .none: break
            case .round:
                e.addChildNode(sphereNode(CGFloat(cr * 0.36), earM, seg: 14).scl(1, 1, 0.35))
                e.addChildNode(sphereNode(CGFloat(cr * 0.27), Coats.plain(d.a * 0.45 + V3(0.2, 0.12, 0.12), rough: 0.8), seg: 12).scl(1, 1, 0.2).at(0, 0.01 * cr, cr * 0.07))
            case .pointy:
                e.addChildNode(coneNode(CGFloat(cr * 0.28), 0.003, CGFloat(cr * 0.75), earM, seg: 12).scl(1, 1, 0.45).at(0, cr * 0.3, 0).rot(0, 0, -sd * 0.35))
                e.addChildNode(coneNode(CGFloat(cr * 0.2), 0.002, CGFloat(cr * 0.55), Coats.plain(d.a * 0.45 + V3(0.22, 0.14, 0.14), rough: 0.8), seg: 10).scl(1, 1, 0.3).at(-sd * cr * 0.02, cr * 0.28, cr * 0.06).rot(0, 0, -sd * 0.35))
            case .long: e.addChildNode(loftNode([Ring(V3(0, 0, 0), cr * 0.18, cr * 0.1), Ring(V3(sd * 0.1 * cr, cr * 1.0, -0.1 * cr), cr * 0.28, cr * 0.1), Ring(V3(sd * 0.15 * cr, cr * 2.2, -0.2 * cr), cr * 0.05, cr * 0.03)], earM, seg: 10, smooth: 3))
            case .floppy: e.addChildNode(sphereNode(CGFloat(cr * 0.5), earM, seg: 12).scl(0.25, 1, 0.6).at(sd * cr * 0.25, -cr * 0.4, 0).rot(0, 0, sd * 0.3))
            case .big: e.addChildNode(sphereNode(CGFloat(cr * 1.4), earM, seg: 16).scl(0.12, 1, 0.9).at(sd * cr * 0.3, -cr * 0.5, -cr * 0.6).rot(0, sd * 0.4, sd * 0.2))
            case .tufts: e.addChildNode(coneNode(CGFloat(cr * 0.2), 0.003, CGFloat(cr * 0.6), earM, seg: 8).at(0, cr * 0.3, 0).rot(0, 0, -sd * 0.4))
            }
            ears.append(e)
        }
        // horns
        let hm = Mat.horn
        for sd in [Float(1), -1] {
            let hp = V3(sd * cr * 0.4, cr * 0.85, -cr * 0.1)
            switch d.horns {
            case .none: break
            case .short: skull.addChildNode(coneNode(CGFloat(cr * 0.14), 0.004, CGFloat(cr * 0.6), hm, seg: 8).at(hp.x, hp.y + cr * 0.2, hp.z).rot(0, 0, -sd * 0.5))
            case .ram:
                let t = SCNTorus(ringRadius: CGFloat(cr * 0.45), pipeRadius: CGFloat(cr * 0.12)); t.materials = [hm]
                skull.addChildNode(SCNNode(geometry: t).rot(0, 0, Float.pi / 2).at(hp.x * 1.4, hp.y - cr * 0.2, hp.z - cr * 0.2))
            case .long: skull.addChildNode(coneNode(CGFloat(cr * 0.1), 0.003, CGFloat(cr * 2.2), hm, seg: 8).at(hp.x, hp.y + cr * 0.9, hp.z - cr * 0.6).rot(-0.5, 0, -sd * 0.15))
            case .wide:
                skull.addChildNode(loftNode([Ring(hp, cr * 0.18, cr * 0.18), Ring(hp + V3(sd * cr * 1.2, -cr * 0.1, -cr * 0.2), cr * 0.13, cr * 0.13), Ring(hp + V3(sd * cr * 1.8, cr * 0.5, -cr * 0.1), cr * 0.02, cr * 0.02)], hm, seg: 10, smooth: 3))
            case .antlers, .palmate:
                let ant = SCNNode(); ant.simdPosition = hp
                ant.simdEulerAngles = V3(-0.3, 0, -sd * 0.5)
                skull.addChildNode(ant)
                let am = Coats.plain(V3(0.55, 0.45, 0.32), rough: 0.7)
                ant.addChildNode(limb(0.35 * s, 0.018 * s, 0.01 * s, am, seg: 6, dir: V3(sd * 0.3, 1, -0.3)))
                if d.horns == .palmate {
                    ant.addChildNode(sphereNode(CGFloat(0.2 * s), am, seg: 12).scl(1, 0.15, 0.7).at(sd * 0.15 * s, 0.3 * s, -0.08 * s).rot(0, 0, sd * 0.4))
                } else {
                    for k in 0..<3 { ant.addChildNode(limb(0.15 * s, 0.01 * s, 0.005 * s, am, seg: 5, dir: V3(sd * 0.2, 0.8, 0.6)).at(sd * 0.03 * s * Float(k), 0.1 * s + Float(k) * 0.08 * s, -0.03 * s * Float(k))) }
                }
            case .rhino:
                if sd > 0 {
                    skull.addChildNode(coneNode(CGFloat(cr * 0.3), 0.004, CGFloat(cr * 1.1), hm, seg: 10).rot(-0.4, 0, 0).at(0, cr * 0.1, tz - cr * 0.05))
                    skull.addChildNode(coneNode(CGFloat(cr * 0.2), 0.004, CGFloat(cr * 0.5), hm, seg: 10).rot(-0.3, 0, 0).at(0, cr * 0.35, tz - cr * 0.6))
                }
            case .ossicones:
                skull.addChildNode(cylNode(CGFloat(cr * 0.08), CGFloat(cr * 0.5), m, seg: 8).at(hp.x * 0.6, hp.y + cr * 0.2, hp.z))
                skull.addChildNode(sphereNode(CGFloat(cr * 0.12), Mat.brownHair, seg: 8).at(hp.x * 0.6, hp.y + cr * 0.47, hp.z))
            }
        }
        // extras
        if d.mane {
            let mm = Coats.plain(d.plan == .sprawl ? d.b : d.b * 0.9 + d.a * 0.1, rough: 0.95)
            if d.plan == .sprawl {
                for sd in [Float(1), -1] { for k in 0..<3 { skull.addChildNode(limb(cr * 0.9, cr * 0.1, cr * 0.04, mm, seg: 6, dir: V3(sd, 0.6 - Float(k) * 0.4, -0.5)).at(sd * cr * 0.7, 0, -cr * 0.4)) } }
            } else if d.ears == .round {
                let maneM = Coats.coat(.fur, d.b * 0.8 + d.a * 0.2, d.b * 0.5)
                let g = loft((0...10).map { i -> Ring in
                    let t = Float(i) / 10
                    let r = sinf(.pi * t) * cr * 1.55 + 0.01
                    return Ring(V3(0, 0, (t - 0.5) * cr * 1.6), r, r * 1.05)
                }, seg: 30, ref: V3(0, 1, 0)) { p, _, u, v in
                    // big shaggy clumps
                    let clump = Noise.fbm(u * 9, v * 5, octaves: 3, seed: 17) * cr * 0.45
                    return clump + abs(sinf(u * 2 * .pi * 11)) * cr * 0.08
                }
                g.materials = [maneM]
                let mane = SCNNode(geometry: g)
                mane.simdPosition = V3(0, -0.05 * cr, -cr * 0.35)
                skull.addChildNode(furry(mane, SpeciesDef("mane", .quad, d.size, .fur, d.b, d.b) { $0.coat = .fur }, scale: 2.5))
            } else {
                neckNode.addChildNode(loftNode([Ring(V3(0, 0, -nr * 0.9), 0.02 * s, 0.03 * s), Ring(tip * 0.5 + V3(0, 0, -nr * 0.9), 0.03 * s, 0.05 * s), Ring(tip + V3(0, cr * 0.5, -cr * 0.5), 0.02 * s, 0.03 * s)], mm, seg: 8, smooth: 3))
            }
        }
        if d.whiskers {
            for sd in [Float(1), -1] { for k in 0..<3 { skull.addChildNode(cylNode(CGFloat(0.002 * s), CGFloat(cr * 1.3), Coats.plain(V3(0.9, 0.9, 0.88)), seg: 3).rot(0, 0, Float.pi / 2 + (Float(k) - 1) * 0.15).at(sd * cr * 0.6, -0.15 * cr, tz - cr * 0.1)) } }
        }
        if d.antennae {
            for sd in [Float(1), -1] {
                let a = SCNNode(); a.simdPosition = V3(sd * cr * 0.3, cr * 0.8, cr * 0.4)
                skull.addChildNode(a)
                let len = (d.plan == .slither ? 0.18 : 0.22) * s
                a.addChildNode(limb(len, 0.006 * s, 0.004 * s, Coats.limbMat(d), seg: 5, dir: V3(sd * 0.4, 1, 0.5)))
                a.addChildNode(sphereNode(CGFloat(0.012 * s), d.plan == .slither ? Coats.glossy(V3(0.05, 0.05, 0.05)) : Coats.limbMat(d), seg: 8).at(sd * 0.4 * len * 0.6, len * 0.8, 0.5 * len * 0.6))
                ants.append(a)
            }
        }
        if d.comb {
            for k in 0..<4 { skull.addChildNode(sphereNode(CGFloat(cr * 0.3), Mat.comb, seg: 10).scl(0.3, 1, 0.6).at(0, cr * 0.9, -cr * 0.3 + Float(k) * cr * 0.25)) }
            skull.addChildNode(sphereNode(CGFloat(cr * 0.3), Mat.comb, seg: 10).scl(0.5, 1.2, 0.6).at(0, -cr * 0.8, cr * 0.7))
        }
        if d.tusks {
            for sd in [Float(1), -1] {
                skull.addChildNode(loftNode([Ring(V3(sd * cr * 0.35, -0.3 * cr, tz - cr * 0.4), cr * 0.1, cr * 0.1), Ring(V3(sd * cr * 0.45, -cr * 1.1, tz + cr * 0.3), cr * 0.08, cr * 0.08),
                                             Ring(V3(sd * cr * 0.4, -cr * 1.2, tz + cr * 1.0), cr * 0.01, cr * 0.01)], Mat.horn, seg: 8, smooth: 3))
            }
        }
    }

    override func pose(_ p: Pose) {
        let bird = d.plan == .bird
        var bob: Float = 0
        if bird {
            let saw = p.phase * 2 - floorf(p.phase * 2)
            bob = (saw < 0.75 ? -saw / 0.75 : (saw - 0.75) / 0.25 - 1) * 0.04 * d.size * p.gait * (1 - p.air)
        }
        let peck = bird ? p.eat * max(0, sinf(p.t * 14)) * 0.9 + p.eat * 0.4 : p.eat * 0.9
        neckNode.simdEulerAngles = V3(peck - p.talk * 0.25 + p.shove * 0.4, 0, 0)
        neckNode.simdPosition = V3(0, 0, bob)
        skull.simdEulerAngles = V3((bird || d.eyeFront ? 0.05 : 0.15) - p.talk * 0.25 + p.eat * 0.3, sinf(p.t * 0.33) * 0.2 * (1 - p.gait), 0)
        let open = p.talk * (0.5 + 0.5 * abs(sinf(p.t * 14))) + p.eat * abs(sinf(p.t * 7)) * 0.5
        jaw.simdEulerAngles = V3(open * 0.4, 0, 0)
        for (k, n) in trunk.enumerated() {
            let curl = 0.18 + sinf(p.t * 1.3 + Float(k) * 0.4) * 0.05 - p.talk * 0.35 - p.eat * 0.1
            n.simdEulerAngles = V3(k == 0 ? 1.1 - p.talk * 1.8 : curl, sinf(p.t * 0.9 + Float(k) * 0.3) * 0.06, 0)
        }
        for (i, a) in ants.enumerated() { a.simdEulerAngles = V3(sinf(p.t * 5 + Float(i)) * 0.2, 0, 0) }
        earT -= 1 / 60
        var flick: Float = 0
        if earT < 0.15 { flick = sinf(earT / 0.15 * .pi) }
        if earT < 0 { earT = Float.random(in: 1.5...5) }
        for (i, e) in ears.enumerated() { e.simdEulerAngles = V3(0, (i == 0 ? 1 : -1) * flick * 0.4, 0) }
    }
}
