import SceneKit
import simd

/// Procedural coats for the generated animals, cached by pattern and colours.
enum Coats {
    private static var cache: [String: SCNMaterial] = [:]
    private static let lock = NSLock()

    static func get(_ key: String, _ make: () -> SCNMaterial) -> SCNMaterial {
        lock.lock()
        if let m = cache[key] { lock.unlock(); return m }
        lock.unlock()
        let m = make()
        lock.lock(); cache[key] = m; lock.unlock()
        return m
    }

    static func key(_ v: V3) -> String { String(format: "%.2f,%.2f,%.2f", v.x, v.y, v.z) }

    static func coat(_ d: SpeciesDef) -> SCNMaterial { coat(d.coat, d.a, d.b, seed: Int32(d.name.hashValue & 0xFFF)) }

    static func coat(_ c: Coat, _ a: V3, _ b: V3, seed: Int32 = 1) -> SCNMaterial {
        if c == .holstein { return Mat.hide }
        return get("\(c.rawValue)|\(key(a))|\(key(b))") {
            if c == .feathers { return tiled(Mat.feathers(a, b, lace: 0.6, seed: 5), 4, 5) }
            let W = 512
            var gloss: Float = 0
            var bump: Float = 2
            var rep: (Float, Float) = (2, 2)
            switch c {
            case .slick: gloss = 0.7; bump = 0.8
            case .chitin: gloss = 0.85; bump = 1
            case .scales: gloss = 0.3; bump = 3; rep = (4, 6)
            case .shell: bump = 4; rep = (2, 2)
            case .wool: bump = 5; rep = (4, 5)
            case .quills: bump = 4; rep = (6, 3)
            case .stripes: rep = (1, 1.4)
            case .bands: rep = (1, 3)
            case .fur: bump = 1.6
            default: break
            }
            let p = makePBR(W, W, bump: bump) { x, y in
                let u = Float(x) / Float(W), v = Float(y) / Float(W)
                var t = TexSample()
                let hair = Noise.streak(u, v, fu: 128, fv: 12, seed: 3)
                let big = Noise.tfbm(u, v, freq: 3, octaves: 4, seed: 11)
                var col = a
                var h: Float = hair * 0.5
                var rough: Float = 0.7
                switch c {
                case .fur:
                    col = mix3(a, b, smoothstep(0.1, 0.6, big) * 0.35) * (0.85 + hair * 0.25)
                case .spots:
                    let g: Float = 9
                    let cx = floorf(u * g), cy = floorf(v * g)
                    var best: Float = 9
                    for dx in -1...1 { for dy in -1...1 {
                        let ix = Int(cx) + dx, iy = Int(cy) + dy
                        let jx = Noise.cell((ix + 9) % 9, (iy + 9) % 9, 21), jy = Noise.cell((ix + 9) % 9, (iy + 9) % 9, 22)
                        let px = (Float(ix) + 0.2 + jx * 0.6) / g, py = (Float(iy) + 0.2 + jy * 0.6) / g
                        best = min(best, simd_length(SIMD2(u - px, v - py)) * g)
                    } }
                    let s = smoothstep(0.3, 0.22, best + big * 0.05)
                    col = mix3(a * (0.9 + hair * 0.2), b, s)
                case .rosettes:
                    let g: Float = 7
                    let cx = floorf(u * g), cy = floorf(v * g)
                    var best: Float = 9
                    for dx in -1...1 { for dy in -1...1 {
                        let ix = Int(cx) + dx, iy = Int(cy) + dy
                        let jx = Noise.cell((ix + 7) % 7, (iy + 7) % 7, 31), jy = Noise.cell((ix + 7) % 7, (iy + 7) % 7, 32)
                        let px = (Float(ix) + 0.25 + jx * 0.5) / g, py = (Float(iy) + 0.25 + jy * 0.5) / g
                        best = min(best, simd_length(SIMD2(u - px, v - py)) * g)
                    } }
                    let ring = smoothstep(0.42, 0.36, best + big * 0.06) * smoothstep(0.18, 0.26, best + Noise.tfbm(u, v, freq: 24, octaves: 2, seed: 33) * 0.1)
                    let inner = smoothstep(0.3, 0.2, best)
                    col = mix3(mix3(a, a * 0.8, inner), b, ring) * (0.9 + hair * 0.2)
                case .cells:
                    let g: Float = 6
                    let cx = floorf(u * g), cy = floorf(v * g)
                    var d1: Float = 9, d2: Float = 9
                    for dx in -1...1 { for dy in -1...1 {
                        let ix = Int(cx) + dx, iy = Int(cy) + dy
                        let jx = Noise.cell((ix + 6) % 6, (iy + 6) % 6, 41), jy = Noise.cell((ix + 6) % 6, (iy + 6) % 6, 42)
                        let px = (Float(ix) + jx) / g, py = (Float(iy) + jy) / g
                        let d = simd_length(SIMD2(u - px, v - py)) * g
                        if d < d1 { d2 = d1; d1 = d } else if d < d2 { d2 = d }
                    } }
                    let line = smoothstep(0.06, 0.12, d2 - d1 + big * 0.03)
                    col = mix3(a, b * (0.9 + big * 0.2), line) * (0.9 + hair * 0.15)
                case .patches:
                    let n = big + Noise.tfbm(u, v, freq: 2, octaves: 2, seed: 12) * 0.5
                    col = mix3(a, b, smoothstep(0.05, 0.1, n + hair * 0.04)) * (0.9 + hair * 0.2)
                case .stripes:
                    let w = Noise.tfbm(u, v, freq: 4, octaves: 3, seed: 51) * 2.2
                    let s = sinf((v * 9 + w + u * 0.5) * 2 * .pi)
                    let m = smoothstep(0.25, 0.45, s + Noise.tfbm(u, v, freq: 8, octaves: 2, seed: 52) * 0.3)
                    col = mix3(a, b, m) * (0.9 + hair * 0.2)
                case .bands:
                    let s = sinf(v * 6 * 2 * .pi + big * 0.6)
                    col = mix3(a, b, smoothstep(-0.1, 0.1, s)) * (0.92 + hair * 0.15)
                case .scales:
                    let row = v * 16
                    let off: Float = Int(floorf(row)).isMultiple(of: 2) ? 0 : 0.5
                    let fx = (u * 10 + off).truncatingRemainder(dividingBy: 1) - 0.5, fy = row - floorf(row) - 0.5
                    let d = sqrtf(fx * fx * 1.3 + fy * fy)
                    col = mix3(a, b, smoothstep(0.1, 0.5, big) * 0.6) * (1 - smoothstep(0.32, 0.5, d) * 0.4)
                    h = 1 - d * 2
                    rough = 0.5
                case .skin:
                    let wr = Noise.streak(u, v, fu: 40, fv: 6, seed: 61) + Noise.streak(v, u, fu: 36, fv: 5, seed: 62) * 0.6
                    col = mix3(a, b, smoothstep(0.0, 0.6, big) * 0.4) * (0.9 + wr * 0.1)
                    h = -abs(wr) * 0.8 + Noise.tfbm(u, v, freq: 40, octaves: 2, seed: 63) * 0.2
                    rough = 0.75
                case .slick:
                    col = mix3(a, b, smoothstep(0.0, 0.5, big) * 0.35)
                    h = Noise.tfbm(u, v, freq: 24, octaves: 2, seed: 71) * 0.2
                    rough = 0.28
                case .shell:
                    let g: Float = 4
                    let cx = floorf(u * g), cy = floorf(v * g)
                    var d1: Float = 9, d2: Float = 9
                    for dx in -1...1 { for dy in -1...1 {
                        let ix = Int(cx) + dx, iy = Int(cy) + dy
                        let jx = 0.3 + Noise.cell((ix + 4) % 4, (iy + 4) % 4, 81) * 0.4, jy = 0.3 + Noise.cell((ix + 4) % 4, (iy + 4) % 4, 82) * 0.4
                        let d = simd_length(SIMD2(u - (Float(ix) + jx) / g, v - (Float(iy) + jy) / g)) * g
                        if d < d1 { d2 = d1; d1 = d } else if d < d2 { d2 = d }
                    } }
                    let edge = smoothstep(0.02, 0.15, d2 - d1)
                    let rings = sinf(d1 * 30) * 0.5 + 0.5
                    col = mix3(b, a * (0.85 + rings * 0.2), edge)
                    h = edge * 0.8 - d1 * 0.3
                    rough = 0.55
                case .chitin:
                    col = mix3(a, b, smoothstep(0.2, 0.7, big) * 0.3)
                    h = Noise.tfbm(u, v, freq: 32, octaves: 2, seed: 91) * 0.15
                    rough = 0.2
                case .wool:
                    let cu = Noise.tfbm(u, v, freq: 24, octaves: 3, seed: 101)
                    let curl = sinf((u * 60 + cu * 8) ) * sinf((v * 60 + cu * 8))
                    col = a * (0.8 + cu * 0.2 + curl * 0.08)
                    h = cu + curl * 0.3
                    rough = 0.95
                case .quills:
                    let q = Noise.streak(u, v, fu: 64, fv: 4, seed: 111)
                    col = mix3(a, b, smoothstep(0.0, 0.3, q))
                    h = q
                    rough = 0.6
                default: break
                }
                t.albedo = col
                t.height = h
                t.rough = rough - gloss * 0.45
                return t
            }
            let m = tiled(pbrMaterial(p, normalIntensity: 0.9), rep.0, rep.1)
            if gloss > 0.5 { m.clearCoat.contents = 0.4 }
            m.shaderModifiers = [.surface: Coats.countershade]
            return m
        }
    }

    /// Lighter belly, slightly darker back, and a soft sheen at grazing angles (fur catching the light).
    static let countershade = """
    float3 wn = (scn_frame.inverseViewTransform * float4(_surface.normal, 0.0)).xyz;
    float belly = smoothstep(0.15, -0.75, wn.y);
    float backTop = smoothstep(0.35, 1.0, wn.y);
    _surface.diffuse.rgb = mix(_surface.diffuse.rgb, _surface.diffuse.rgb * 1.3 + 0.06, belly * 0.45);
    _surface.diffuse.rgb *= 1.0 - backTop * 0.12;
    """

    /// Shell layers for furry coats: copies of the mesh pushed out along the normal, with most
    /// texels cut away, so the surface reads as short hair instead of painted plastic.
    static func furShells(_ node: SCNNode, _ base: SCNMaterial, length: Float, layers: Int = 3) {
        guard let g = node.geometry else { return }
        for k in 1...layers {
            let sg = g.copy() as! SCNGeometry
            sg.materials = [shellMat(base, k, layers, length)]
            let sn = SCNNode(geometry: sg)
            sn.castsShadow = false
            node.addChildNode(sn)
        }
    }
    private static var shellCache: [String: SCNMaterial] = [:]
    static func shellMat(_ base: SCNMaterial, _ k: Int, _ n: Int, _ len: Float) -> SCNMaterial {
        let key = "\(ObjectIdentifier(base).hashValue)|\(k)|\(Int(len * 1000))"
        lock.lock()
        if let m = shellCache[key] { lock.unlock(); return m }
        lock.unlock()
        let m = base.copy() as! SCNMaterial
        let t = Float(k) / Float(n)
        m.shaderModifiers = [
            .geometry: "#pragma arguments\nfloat furLen;\n#pragma body\n_geometry.position.xyz += _geometry.normal * furLen;",
            .surface: countershade + """
            float2 cell = floor(_surface.diffuseTexcoord * float2(260.0, 260.0));
            float h = fract(sin(dot(cell, float2(12.9898, 78.233))) * 43758.5453);
            if (h < \(0.35 + t * 0.45)) { discard_fragment(); }
            _surface.diffuse.rgb *= \(0.82 + t * 0.2);
            """,
        ]
        m.setValue(NSNumber(value: len * t), forKey: "furLen")
        lock.lock(); shellCache[key] = m; lock.unlock()
        return m
    }
    static func isFurry(_ c: Coat) -> Bool { [.fur, .spots, .rosettes, .patches, .stripes, .wool, .cells, .bands, .holstein, .quills].contains(c) }

    static func plain(_ v: V3, rough: CGFloat = 0.6, metal: CGFloat = 0) -> SCNMaterial {
        get("plain|\(key(v))|\(rough)") { pbr(color(v), rough: rough, metal: metal) }
    }
    static func glossy(_ v: V3) -> SCNMaterial {
        get("gloss|\(key(v))") { let m = pbr(color(v), rough: 0.08); m.clearCoat.contents = 1; return m }
    }
    static func membrane(_ v: V3, alpha: CGFloat) -> SCNMaterial {
        get("mem|\(key(v))|\(alpha)") {
            let m = pbr(color(v), rough: alpha < 0.5 ? 0.1 : 0.6)
            m.transparency = alpha
            m.isDoubleSided = true
            m.writesToDepthBuffer = alpha > 0.7
            if alpha < 0.5 { m.clearCoat.contents = 1 }
            return m
        }
    }
    static func limbMat(_ d: SpeciesDef) -> SCNMaterial { d.limbCol.map { plain($0, rough: 0.5) } ?? coat(d) }

    /// Warm the cache off the main thread so the first morph into each animal doesn't hitch.
    static func prewarm() {
        DispatchQueue.global(qos: .utility).async {
            DispatchQueue.concurrentPerform(iterations: Zoo.defs.count) { i in
                let d = Zoo.defs[i]
                if !d.custom { _ = coat(d) }
            }
        }
    }
}
