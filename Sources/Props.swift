import SceneKit
import simd

enum PropKind { case pumpkin, apple, egg, ball, bucket }

/// Loose things you can pick up, throw, kick and knock around.
final class Prop {
    let kind: PropKind
    let node = SCNNode()
    let spin = SCNNode()
    var pos: V3
    var vel = V3.zero
    var radius: Float
    var mass: Float
    var held = false
    var grounded = false
    var home: V3
    var thrownFrom: V3? = nil
    var thrownBy = false
    var dead = false
    var rest: Float = 0
    var laid = false

    init(_ k: PropKind, at p: V3) {
        kind = k; pos = p; home = p
        switch k {
        case .pumpkin:
            radius = 0.26; mass = 6
            let g = loft((0...8).map { i -> Ring in
                let t = Float(i) / 8
                let y = (t - 0.5) * 0.44
                let r = sinf(.pi * t) * 0.28 + 0.01
                return Ring(V3(0, y, 0), r, r)
            }, seg: 40, ref: V3(0, 0, 1)) { _, _, u, _ in -0.018 * powf(abs(cosf(u * .pi * 10)), 0.5) }
            g.materials = [Mat.pumpkin]
            spin.add(SCNNode(geometry: g))
            spin.add(limb(0.1, 0.025, 0.018, Mat.stem, dir: V3(0.2, 1, 0)).at(0, 0.19, 0))
        case .apple:
            radius = 0.045; mass = 0.2
            spin.add(sphereNode(0.045, Mat.apple, seg: 16).scl(1, 0.9, 1))
            spin.add(limb(0.025, 0.004, 0.003, Mat.stem, dir: V3(0.1, 1, 0)).at(0, 0.038, 0))
        case .egg:
            radius = 0.05; mass = 0.1
            spin.add(sphereNode(0.05, Mat.eggBrown, seg: 16).scl(0.78, 1, 0.78))
        case .ball:
            radius = 0.11; mass = 0.45
            let b = sphereNode(0.11, Mat.ballWhite, seg: 24)
            spin.add(b)
            for k in 0..<12 {
                let a = Float(k) / 12 * 2 * .pi, e = Float(k % 3) * 0.8 - 0.8
                spin.add(sphereNode(0.03, Mat.black, seg: 8).scl(1, 1, 0.25).at(cosf(a) * cosf(e) * 0.105, sinf(e) * 0.105, sinf(a) * cosf(e) * 0.105)
                    .rot(0, -a + .pi / 2, 0))
            }
        case .bucket:
            radius = 0.17; mass = 1.2
            let t = SCNTube(innerRadius: 0.14, outerRadius: 0.15, height: 0.3)
            t.radialSegmentCount = 24
            t.materials = [Mat.galv]
            spin.add(SCNNode(geometry: t))
            spin.add(cylNode(0.145, 0.01, Mat.galv, seg: 24).at(0, -0.145, 0))
            let h = SCNTorus(ringRadius: 0.15, pipeRadius: 0.006)
            h.materials = [Mat.galv]
            spin.add(SCNNode(geometry: h).rot(Float.pi / 2, 0, 0).at(0, 0.15, 0).scl(1, 1, 0.8))
        }
        node.add(spin)
        node.simdPosition = p
        node.castAll(true)
    }

    var impactSound: String {
        switch kind { case .pumpkin: return "bonk"; case .bucket: return "clang"; case .ball: return "kick"; default: return "thud" }
    }

    /// Simple rigid sphere physics against the ground and solid walls. Returns impact speed.
    func step(_ dt: Float, world: World) -> Float {
        guard !held, !dead else { return 0 }
        var impact: Float = 0
        vel.y -= 9.81 * dt
        let prev = pos
        pos += vel * dt
        let (g, surf, _) = world.ground(pos.x, pos.z, y: prev.y - radius, r: radius * 0.5, step: 0.25)
        let inWater = surf == .water && pos.y - radius < Farm.pondWater
        if inWater {
            // float or sink gently
            vel *= 1 - min(1, dt * 3)
            if kind == .ball || kind == .pumpkin || kind == .apple || kind == .bucket { vel.y += (Farm.pondWater - (pos.y - radius * 0.3)) * 25 * dt }
        }
        if pos.y - radius < g {
            let vn = -vel.y
            pos.y = g + radius
            if vn > 0 {
                impact = vn
                let bounce: Float = kind == .ball ? 0.62 : kind == .bucket ? 0.25 : 0.2
                vel.y = vn > 1.2 ? vn * bounce : 0
            }
            grounded = true
            let fr: Float = kind == .ball ? 0.6 : 2.5
            let h = SIMD2(vel.x, vel.z)
            let sp = simd_length(h)
            if sp > 0 {
                let ns = max(0, sp - fr * dt * (surf == .grass ? 1.5 : 1))
                vel.x *= ns / sp; vel.z *= ns / sp
            }
        } else {
            grounded = false
        }
        var p = pos
        p.y -= radius
        if world.collide(&p, r: radius, h: radius * 2, step: 0.2) {
            let d = V3(p.x - pos.x, 0, p.z - pos.z)
            let l = simd_length(d)
            if l > 1e-5 {
                let n = d / l
                let vn = simd_dot(vel, n)
                if vn < 0 { vel -= n * vn * 1.5; impact = max(impact, -vn) }
            }
            pos.x = p.x; pos.z = p.z
        }
        node.simdPosition = pos
        // rolling
        let hv = V3(vel.x, 0, vel.z)
        let s = simd_length(hv)
        if s > 0.01 && (grounded || kind == .ball) {
            let axis = simd_normalize(simd_cross(V3(0, 1, 0), hv))
            spin.simdOrientation = simd_quatf(angle: s * dt / radius, axis: axis) * spin.simdOrientation
        }
        rest = s < 0.05 && grounded ? rest + dt : 0
        return impact
    }
}
