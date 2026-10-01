import SceneKit
import simd

/// Leaf-card tree crowns, needle branches and wind.
enum Foliage {
    static let wind = """
    #pragma body
    float sway = sin(scn_frame.time * 1.3 + _geometry.position.x * 0.15 + _geometry.position.z * 0.11) * 0.5 + sin(scn_frame.time * 3.1 + _geometry.position.y * 0.7) * 0.25;
    _geometry.position.x += sway * 0.05;
    _geometry.position.z += sway * 0.035;
    """
    static let cutout = """
    if (_surface.diffuse.a < 0.5) { discard_fragment(); }
    _surface.diffuse = float4(_surface.diffuse.rgb / max(_surface.diffuse.a, 0.001), 1.0);
    """

    private static func cardMaterial(_ img: CGImage, rough: CGFloat = 0.95) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = img
        m.diffuse.mipFilter = .linear
        m.roughness.contents = rough
        m.isDoubleSided = true
        m.blendMode = .replace
        m.shaderModifiers = [.geometry: wind, .surface: cutout + "\n_surface.specular = float4(0.0);"]
        return m
    }

    /// A clump of broad leaves on a transparent card.
    static func leafMat(_ lo: V3, _ hi: V3, seed: UInt64) -> SCNMaterial {
        Coats.get("leafcard|\(Coats.key(lo))|\(Coats.key(hi))") {
            var rr = RNG(seed)
            let W = 256
            let leaves = (0..<70).map { _ in (rr.range(0.1, 0.9), rr.range(0.1, 0.9), rr.range(0, 6.28), rr.range(0.06, 0.11), rr.float()) }
            let img = makePixelImage(W, W) { px, py in
                let u = Float(px) / Float(W), v = Float(py) / Float(W)
                var best: Float = 0, tone: Float = 0, rib: Float = 0
                for (cx, cy, a, sz, tn) in leaves {
                    let dx = u - cx, dy = v - cy
                    let ca = cosf(a), sa = sinf(a)
                    let lx = (dx * ca + dy * sa) / sz, ly = (-dx * sa + dy * ca) / (sz * 0.48)
                    let d = lx * lx + ly * ly
                    if d < 1 {
                        let h = 1 - d
                        if h > best { best = h; tone = tn; rib = abs(ly) < 0.08 ? 1 : 0 }
                    }
                }
                guard best > 0 else { return SIMD4(0, 0, 0, 0) }
                var c = mix3(lo, hi, tone) * (0.7 + best * 0.45)
                c = mix3(c, c * 1.3 + V3(0.03, 0.04, 0.0), rib * 0.5)
                return SIMD4(c.x, c.y, c.z, 1)
            }
            return cardMaterial(img)
        }
    }

    static let pineMat: SCNMaterial = {
        var rr = RNG(88)
        let W = 256
        let needles = (0..<420).map { _ in (rr.float(), rr.range(0.05, 0.95), rr.range(-0.5, 0.5), rr.range(0.04, 0.09), rr.float()) }
        let img = makePixelImage(W, W) { px, py in
            // a branch along the middle with needles sticking out both ways
            let u = Float(px) / Float(W), v = Float(py) / Float(W)
            let taper = 1 - v * 0.7
            if abs(u - 0.5) < 0.012 * taper { return SIMD4(0.2, 0.14, 0.08, 1) }
            for (side, y, lean, len, tn) in needles {
                let sx: Float = side < 0.5 ? -1 : 1
                let x0: Float = 0.5, y0 = y
                let dx = (u - x0) * sx, dy = v - y0 - dx * lean
                if dx > 0 && dx < len * 4 * taper && abs(dy) < 0.006 {
                    let c = mix3(V3(0.05, 0.14, 0.06), V3(0.12, 0.26, 0.1), tn) * (0.8 + dx * 2)
                    return SIMD4(c.x, c.y, c.z, 1)
                }
            }
            return SIMD4(0, 0, 0, 0)
        }
        return cardMaterial(img, rough: 0.8)
    }()

    /// Cards scattered through an ellipsoid, facing roughly outward, lit as if the crown were one soft ball.
    static func crown(center: V3, radii: V3, cards: Int, size: Float, seed: UInt64, _ m: SCNMaterial) -> SCNNode {
        var rr = RNG(seed)
        var P: [V3] = [], N: [V3] = [], U: [SIMD2<Float>] = [], I: [UInt32] = []
        for _ in 0..<cards {
            let th = rr.range(0, 2 * .pi), ph = acosf(rr.range(-0.6, 1))
            let r = powf(rr.float(), 0.3)
            let dir = V3(sinf(ph) * cosf(th), cosf(ph), sinf(ph) * sinf(th))
            let p = center + dir * radii * r
            let out = simd_normalize(dir * V3(1 / radii.x, 1 / radii.y, 1 / radii.z))
            var t1 = simd_normalize(simd_cross(out, V3(rr.range(-1, 1), rr.range(-1, 1), rr.range(-1, 1)) + V3(0.001, 0, 0)))
            if !t1.x.isFinite { t1 = V3(1, 0, 0) }
            let t2 = simd_cross(out, t1)
            let hs = size * rr.range(0.7, 1.3) * 0.5
            let i = UInt32(P.count)
            let a1: V3 = t1 * hs, a2: V3 = t2 * hs
            let c0: V3 = p - a1 - a2, c1: V3 = p + a1 - a2, c2: V3 = p + a1 + a2, c3: V3 = p - a1 + a2
            P += [c0, c1, c2, c3]
            let n = simd_normalize(out)
            N += [n, n, n, n]
            U += [SIMD2(0, 1), SIMD2(1, 1), SIMD2(1, 0), SIMD2(0, 0)]
            I += [i, i + 1, i + 2, i, i + 2, i + 3]
        }
        let g = meshGeometry(P, N, U, I)
        g.materials = [m]
        let node = SCNNode(geometry: g)
        // a darker core so you can't see straight through
        let core = sphereNode(CGFloat(min(radii.x, radii.y, radii.z) * 0.72), Coats.plain(V3(0.05, 0.1, 0.03), rough: 0.9), seg: 10)
        core.simdPosition = center
        core.simdScale = radii / min(radii.x, radii.y, radii.z)
        node.addChildNode(core)
        return node
    }

    /// Drooping needle branches in tiers around a trunk.
    static func pineBranches(height h: Float, radius: Float, tiers: Int, seed: UInt64) -> SCNNode {
        var rr = RNG(seed)
        var P: [V3] = [], N: [V3] = [], U: [SIMD2<Float>] = [], I: [UInt32] = []
        for k in 0..<tiers {
            let t = Float(k) / Float(tiers)
            let y = h * (0.22 + t * 0.72)
            let r = radius * (1 - t * 0.85) + 0.2
            let n = 9 + Int((1 - t) * 6)
            for j in 0..<n {
                let a = Float(j) / Float(n) * 2 * .pi + rr.range(0, 0.4)
                let out = V3(cosf(a), 0, sinf(a))
                let side = V3(-sinf(a), 0, cosf(a))
                let w = r * 0.55
                let base = V3(0, y, 0), tip = V3(0, y - r * 0.35, 0) + out * r
                let i = UInt32(P.count)
                let s3: V3 = side * (w * 0.3), s6: V3 = side * (w * 0.6)
                let q0: V3 = base - s3, q1: V3 = base + s3, q2: V3 = tip + s6, q3: V3 = tip - s6
                P += [q0, q1, q2, q3]
                let nn = simd_normalize(out * 0.6 + V3(0, 1, 0))
                N += [nn, nn, nn, nn]
                U += [SIMD2(0.3, 0), SIMD2(0.7, 0), SIMD2(1, 1), SIMD2(0, 1)]
                I += [i, i + 1, i + 2, i, i + 2, i + 3]
            }
        }
        let g = meshGeometry(P, N, U, I)
        g.materials = [pineMat]
        return SCNNode(geometry: g)
    }
}
