import SceneKit
import simd

extension Noise {
    /// Tileable gradient noise with separate periods per axis (for hair, grain and fibres).
    static func tperlin2(_ x: Float, _ y: Float, px: Int32, py: Int32, seed: Int32 = 1) -> Float {
        func wrap(_ a: Int32, _ p: Int32) -> Int32 { let m = a % p; return m < 0 ? m + p : m }
        let xi = floorf(x), yi = floorf(y)
        let xf = x - xi, yf = y - yi
        let ix = wrap(Int32(xi), px), iy = wrap(Int32(yi), py)
        let ix1 = wrap(ix &+ 1, px), iy1 = wrap(iy &+ 1, py)
        let u = fade(xf), v = fade(yf)
        let a = grad(hash(ix, iy, seed), xf, yf)
        let b = grad(hash(ix1, iy, seed), xf - 1, yf)
        let c = grad(hash(ix, iy1, seed), xf, yf - 1)
        let d = grad(hash(ix1, iy1, seed), xf - 1, yf - 1)
        return mixf(mixf(a, b, u), mixf(c, d, u), v) * 0.75
    }
    /// Stretched streaks over a 0…1 tile: `fu` cells across, `fv` along.
    static func streak(_ u: Float, _ v: Float, fu: Int32, fv: Int32, seed: Int32) -> Float {
        tperlin2(u * Float(fu), v * Float(fv), px: fu, py: fv, seed: seed) * 0.65
            + tperlin2(u * Float(fu * 2), v * Float(fv * 2), px: fu * 2, py: fv * 2, seed: seed &+ 5) * 0.35
    }
}

/// Sets how many times every map of a material repeats across a 0…1 UV range.
@discardableResult
func tiled(_ m: SCNMaterial, _ su: Float, _ sv: Float) -> SCNMaterial {
    let t = SCNMatrix4MakeScale(CGFloat(su), CGFloat(sv), 1)
    for p in [m.diffuse, m.normal, m.roughness, m.metalness, m.emission, m.multiply, m.ambientOcclusion] { p.contentsTransform = t; p.wrapS = .repeat; p.wrapT = .repeat }
    return m
}

func copyMat(_ m: SCNMaterial) -> SCNMaterial { m.copy() as! SCNMaterial }

/// Every procedural material in the game. Generated once, on first use.
enum Mat {
    static let tp: Float = 2 * .pi

    // MARK: Creatures

    /// Holstein hide: big black islands on white, short hair lying along v.
    static let hide: SCNMaterial = {
        let W = 1024
        let p = makePBR(W, W, bump: 1.6) { x, y in
            let u = Float(x) / Float(W), v = Float(y) / Float(W)
            var t = TexSample()
            let hair = Noise.streak(u, v, fu: 160, fv: 14, seed: 3)
            let n = Noise.tfbm(u, v, freq: 3, octaves: 5, seed: 71) + Noise.tfbm(u, v, freq: 2, octaves: 2, seed: 72) * 0.5
            let edge = smoothstep(0.02, 0.07, n + hair * 0.05)
            let white = V3(0.82, 0.79, 0.74) * (0.9 + hair * 0.15)
            let black = V3(0.028, 0.026, 0.026) * (1 + hair * 0.4)
            // dirt and a faint cream tint low down
            let dirt = smoothstep(0.3, 0.8, Noise.tfbm(u, v, freq: 6, octaves: 3, seed: 73)) * 0.25
            t.albedo = mix3(white, black, edge) * (1 - dirt * (1 - edge)) + V3(0.05, 0.035, 0.015) * dirt * (1 - edge)
            t.height = hair * 0.6 + edge * 0.05
            t.rough = 0.62 + hair * 0.1 - edge * 0.08
            return t
        }
        let m = tiled(pbrMaterial(p, normalIntensity: 0.8), 1, 0.9)
        m.shaderModifiers = [.surface: Coats.countershade]
        return m
    }()

    static let cowSkin: SCNMaterial = {
        let p = makePBR(256, 256, bump: 1) { x, y in
            let u = Float(x) / 256, v = Float(y) / 256
            var t = TexSample()
            let m = Noise.tfbm(u, v, freq: 4, octaves: 4, seed: 81)
            let freckle = smoothstep(0.25, 0.45, Noise.tfbm(u, v, freq: 10, octaves: 3, seed: 82))
            t.albedo = mix3(V3(0.86, 0.58, 0.55) * (0.92 + m * 0.12), V3(0.25, 0.18, 0.18), freckle * 0.6)
            t.height = Noise.tfbm(u, v, freq: 32, octaves: 2, seed: 83) * 0.3
            t.rough = 0.5
            return t
        }
        return tiled(pbrMaterial(p), 2, 3)
    }()

    static let cowNose: SCNMaterial = {
        let p = makePBR(256, 256, bump: 2.5) { x, y in
            let u = Float(x) / 256, v = Float(y) / 256
            var t = TexSample()
            let pores = Noise.tfbm(u, v, freq: 24, octaves: 2, seed: 91)
            let m = Noise.tfbm(u, v, freq: 3, octaves: 3, seed: 92)
            t.albedo = mix3(V3(0.55, 0.36, 0.36), V3(0.12, 0.09, 0.09), smoothstep(-0.1, 0.2, m))
            t.height = pores * 0.6
            t.rough = 0.22 + pores * 0.1
            return t
        }
        return tiled(pbrMaterial(p), 2, 2)
    }()

    static let hoof: SCNMaterial = {
        let p = makePBR(256, 256, bump: 1.5) { x, y in
            let u = Float(x) / 256, v = Float(y) / 256
            var t = TexSample()
            let s = Noise.streak(v, u, fu: 4, fv: 40, seed: 11)
            t.albedo = V3(0.07, 0.06, 0.055) * (1 + s * 0.6)
            t.height = s
            t.rough = 0.42
            return t
        }
        return pbrMaterial(p)
    }()

    static let horn = pbr(color(0.82, 0.76, 0.62), rough: 0.4)

    /// Overlapping feather scales. `a` body colour, `b` edge lacing colour.
    static func feathers(_ a: V3, _ b: V3, lace: Float, seed: Int32, sheen: Float = 0) -> SCNMaterial {
        let W = 512
        let rows: Float = 10, cols: Float = 7
        let p = makePBR(W, W, bump: 3) { x, y in
            let u = Float(x) / Float(W), v = Float(y) / Float(W)
            var t = TexSample()
            let fy = v * rows, row = floorf(fy)
            var best: Float = 9, bx: Float = 0, bid: Float = 0, bdy: Float = 0
            for dr in [Float(0), 1] {
                let r = row - dr
                let off: Float = Int(r).isMultiple(of: 2) ? 0 : 0.5
                let fx = u * cols - off
                let c = floorf(fx + 0.5)
                for dc in [Float(-1), 0, 1] {
                    let cx = c + dc
                    let lx = (fx - cx) / 0.62, ly = (fy - r) / 1.25
                    guard ly > -0.15 else { continue }
                    let d = lx * lx + ly * ly
                    if d < 1 {
                        // the lower row lies on top
                        let prio = d - dr * 3
                        if prio < best {
                            best = prio; bx = lx; bdy = ly
                            bid = Noise.cell(Int(cx) & 63, Int(r) & 63, seed)
                        }
                    }
                }
            }
            let d = best < 9 ? min(1, bx * bx + bdy * bdy) : 1
            let barbs = Noise.streak(u, v, fu: 90, fv: 8, seed: seed &+ 3)
            let shaft = smoothstep(0.06, 0.0, abs(bx)) * smoothstep(1, 0.3, bdy)
            let edge = smoothstep(0.55, 0.95, d)
            var col = mix3(a * (0.85 + bid * 0.3), b, edge * lace)
            col *= 0.9 + barbs * 0.2
            col = mix3(col, col * 1.35 + V3(0.04, 0.03, 0.02), shaft * 0.5)
            t.albedo = col
            t.height = (1 - d) * 0.8 + barbs * 0.15
            t.rough = 0.55 - sheen * 0.25 + barbs * 0.05
            return t
        }
        return pbrMaterial(p, normalIntensity: 0.9)
    }

    static let henBody = tiled(feathers(V3(0.42, 0.16, 0.06), V3(0.2, 0.06, 0.02), lace: 0.7, seed: 5), 4, 5)
    static let henWing = tiled(feathers(V3(0.36, 0.12, 0.05), V3(0.08, 0.04, 0.02), lace: 0.9, seed: 6), 3, 5)
    static let hackle = tiled(feathers(V3(0.78, 0.45, 0.14), V3(0.55, 0.22, 0.05), lace: 0.5, seed: 7), 5, 7)
    static let tailFeather = tiled(feathers(V3(0.03, 0.045, 0.035), V3(0.02, 0.09, 0.06), lace: 0.6, seed: 8, sheen: 1), 2, 4)
    static let whiteFeather = tiled(feathers(V3(0.86, 0.84, 0.78), V3(0.7, 0.68, 0.62), lace: 0.4, seed: 9), 4, 5)

    static let comb: SCNMaterial = {
        let p = makePBR(256, 256, bump: 3) { x, y in
            let u = Float(x) / 256, v = Float(y) / 256
            var t = TexSample()
            let bump = Noise.tfbm(u, v, freq: 16, octaves: 3, seed: 21)
            t.albedo = V3(0.62, 0.035, 0.03) * (0.85 + bump * 0.3)
            t.height = bump
            t.rough = 0.38
            return t
        }
        return tiled(pbrMaterial(p), 2, 2)
    }()

    static let beak = pbr(color(0.86, 0.66, 0.28), rough: 0.35)

    static let scales: SCNMaterial = {
        let p = makePBR(256, 256, bump: 3) { x, y in
            let u = Float(x) / 256, v = Float(y) / 256
            var t = TexSample()
            let row = v * 12
            let off: Float = Int(floorf(row)).isMultiple(of: 2) ? 0 : 0.5
            let fx = (u * 6 + off).truncatingRemainder(dividingBy: 1) - 0.5, fy = row - floorf(row) - 0.5
            let d = sqrtf(fx * fx * 1.2 + fy * fy)
            let n = Noise.tfbm(u, v, freq: 8, octaves: 3, seed: 31)
            t.albedo = V3(0.86, 0.66, 0.2) * (0.85 + n * 0.2) * (1 - smoothstep(0.35, 0.5, d) * 0.35)
            t.height = 1 - d * 2
            t.rough = 0.45
            return t
        }
        return tiled(pbrMaterial(p), 2, 5)
    }()
    static let claw = pbr(color(0.2, 0.18, 0.15), rough: 0.35)

    static let skin: SCNMaterial = {
        let p = makePBR(256, 256, bump: 0.8) { x, y in
            let u = Float(x) / 256, v = Float(y) / 256
            var t = TexSample()
            let m = Noise.tfbm(u, v, freq: 4, octaves: 4, seed: 41)
            let pores = Noise.tfbm(u, v, freq: 48, octaves: 2, seed: 42)
            t.albedo = V3(0.7, 0.5, 0.42) * (0.95 + m * 0.08) + V3(0.03, -0.01, -0.01) * max(0, m)
            t.height = pores * 0.3
            t.rough = 0.52 + pores * 0.05
            return t
        }
        let m = tiled(pbrMaterial(p), 2, 4)
        m.clearCoat.contents = 0.08
        return m
    }()
    static let lip = pbr(color(0.62, 0.32, 0.28), rough: 0.4)
    static let mouthDark = pbr(color(0.18, 0.05, 0.05), rough: 0.6)

    static func hair(_ c: V3) -> SCNMaterial {
        let p = makePBR(256, 256, bump: 2) { x, y in
            let u = Float(x) / 256, v = Float(y) / 256
            var t = TexSample()
            let s = Noise.streak(u, v, fu: 64, fv: 3, seed: 51)
            t.albedo = c * (0.75 + s * 0.5)
            t.height = s
            t.rough = 0.45
            return t
        }
        return tiled(pbrMaterial(p), 2, 2)
    }
    static let brownHair = hair(V3(0.13, 0.07, 0.035))
    static let greyHair = hair(V3(0.45, 0.43, 0.4))

    static let denim: SCNMaterial = {
        let W = 256
        let p = makePBR(W, W, bump: 2.2) { x, y in
            let u = Float(x) / Float(W), v = Float(y) / Float(W)
            var t = TexSample()
            let tw = sinf((Float(x) + Float(y)) * .pi / 2) * 0.5 + 0.5
            let fade = Noise.tfbm(u, v, freq: 3, octaves: 3, seed: 61)
            let slub = Noise.streak(u, v, fu: 3, fv: 64, seed: 62)
            let base = V3(0.08, 0.14, 0.28) * (1 + fade * 0.35) + V3(0.1, 0.1, 0.1) * max(0, slub) * 0.4
            t.albedo = mix3(base, V3(0.5, 0.52, 0.55), tw * 0.12)
            t.height = tw * 0.5 + slub * 0.2
            t.rough = 0.85
            return t
        }
        return tiled(pbrMaterial(p), 6, 8)
    }()

    static let flannel: SCNMaterial = {
        let W = 512
        let p = makePBR(W, W, bump: 1.4) { x, y in
            let u = Float(x) / Float(W), v = Float(y) / Float(W)
            var t = TexSample()
            func band(_ a: Float) -> Float { let f = (a * 2).truncatingRemainder(dividingBy: 1); return f < 0.34 ? 1 : 0 }
            func line(_ a: Float) -> Float { let f = (a * 2).truncatingRemainder(dividingBy: 1); return abs(f - 0.67) < 0.012 ? 1 : 0 }
            let bu = band(u), bv = band(v)
            var col = V3(0.5, 0.05, 0.04)
            if bu > 0 || bv > 0 { col = V3(0.1, 0.03, 0.03) }
            if bu > 0 && bv > 0 { col = V3(0.03, 0.02, 0.02) }
            if line(u) + line(v) > 0 { col = V3(0.75, 0.62, 0.3) }
            let weave = sinf((Float(x) - Float(y)) * .pi / 2) * 0.5 + 0.5
            let fuzz = Noise.tfbm(u, v, freq: 64, octaves: 2, seed: 63)
            t.albedo = col * (0.9 + weave * 0.15 + fuzz * 0.1)
            t.height = weave * 0.4 + fuzz * 0.2
            t.rough = 0.9
            return t
        }
        return tiled(pbrMaterial(p), 3, 3)
    }()

    static let tee: SCNMaterial = {
        let p = makePBR(128, 128, bump: 1) { x, y in
            var t = TexSample()
            let w = sinf(Float(x + y) * .pi / 2) * 0.5 + 0.5
            t.albedo = V3(0.85, 0.84, 0.8) * (0.95 + w * 0.05)
            t.height = w * 0.3
            t.rough = 0.9
            return t
        }
        return tiled(pbrMaterial(p), 8, 8)
    }()

    static let leather: SCNMaterial = {
        let p = makePBR(256, 256, bump: 2) { x, y in
            let u = Float(x) / 256, v = Float(y) / 256
            var t = TexSample()
            let g = Noise.tfbm(u, v, freq: 24, octaves: 3, seed: 71)
            let scuff = smoothstep(0.2, 0.5, Noise.tfbm(u, v, freq: 5, octaves: 3, seed: 72))
            t.albedo = mix3(V3(0.22, 0.12, 0.06) * (0.9 + g * 0.2), V3(0.35, 0.25, 0.16), scuff * 0.5)
            t.height = g * 0.5
            t.rough = 0.45 + scuff * 0.3
            return t
        }
        return tiled(pbrMaterial(p), 2, 2)
    }()

    static let straw: SCNMaterial = {
        let W = 256
        let p = makePBR(W, W, bump: 3) { x, y in
            let u = Float(x) / Float(W), v = Float(y) / Float(W)
            var t = TexSample()
            // over-under weave of flat straw strips
            let cu = Int(u * 16), cv = Int(v * 16)
            let over = (cu + cv) % 2 == 0
            let s = over ? Noise.streak(u, v, fu: 16, fv: 2, seed: 81) : Noise.streak(v, u, fu: 16, fv: 2, seed: 82)
            let fu = (u * 16).truncatingRemainder(dividingBy: 1), fv = (v * 16).truncatingRemainder(dividingBy: 1)
            let edge = over ? min(fv, 1 - fv) : min(fu, 1 - fu)
            t.albedo = V3(0.78, 0.62, 0.32) * (0.8 + s * 0.3) * (0.75 + smoothstep(0, 0.2, edge) * 0.25)
            t.height = (over ? 0.6 : 0.3) + smoothstep(0, 0.2, edge) * 0.4
            t.rough = 0.8
            return t
        }
        return tiled(pbrMaterial(p), 6, 4)
    }()

    static let eyeWhite = pbr(color(0.9, 0.88, 0.84), rough: 0.12)
    static let eyeBlack: SCNMaterial = { let m = pbr(color(0.01, 0.01, 0.01), rough: 0.05); m.clearCoat.contents = 1; return m }()
    static let irisBrown = pbr(color(0.3, 0.17, 0.07), rough: 0.1)
    static let irisBlue = pbr(color(0.2, 0.36, 0.52), rough: 0.1)
    static let irisOrange: SCNMaterial = { let m = pbr(color(0.85, 0.45, 0.08), rough: 0.08); m.clearCoat.contents = 1; return m }()
    static let cowEye: SCNMaterial = { let m = pbr(color(0.06, 0.035, 0.02), rough: 0.04); m.clearCoat.contents = 1; return m }()
    static let lash = pbr(color(0.02, 0.02, 0.02), rough: 0.7)

    // MARK: World

    static let grassDetail: SCNMaterial = {
        // Tiled at 3 m. Multiplies the macro colour map; carries blade-scale normals.
        let W = 512
        let p = makePBR(W, W, bump: 2.5) { x, y in
            let u = Float(x) / Float(W), v = Float(y) / Float(W)
            var t = TexSample()
            let blades = Noise.streak(u, v, fu: 120, fv: 30, seed: 91) + Noise.streak(v, u, fu: 110, fv: 26, seed: 92) * 0.7
            let clump = Noise.tfbm(u, v, freq: 8, octaves: 3, seed: 93)
            let g = 0.8 + blades * 0.25 + clump * 0.2
            t.albedo = V3(g, g, g * 0.95)
            t.height = blades * 0.7 + clump * 0.4
            t.rough = 0.9
            return t
        }
        return pbrMaterial(p)
    }()

    static let grassBlade: SCNMaterial = grassBlade(V3(0.1, 0.2, 0.035), V3(0.26, 0.36, 0.08))
    private static var bladeCache: [String: SCNMaterial] = [:]
    static func grassBlade(_ lo: V3, _ hi: V3) -> SCNMaterial {
        let key = "\(lo)\(hi)"
        if let m = bladeCache[key] { return m }
        let W = 256
        var rr = RNG(17)
        let blades = (0..<70).map { _ in (rr.range(0.04, 0.96), rr.range(0.35, 1.0), rr.range(-0.3, 0.3), rr.range(0.006, 0.016), rr.float()) }
        let img = makePixelImage(W, W) { px, py in
            let x = Float(px) / Float(W), y = 1 - Float(py) / Float(W)     // y up from the base
            var a: Float = 0, shade: Float = 0, hue: Float = 0
            for (bx, h, lean, w, tone) in blades where y < h {
                let s = y / h
                let cx = bx + lean * s * s
                let ww = w * (1 - s * 0.85)
                let d = abs(x - cx)
                if d < ww {
                    let aa = smoothstep(ww, ww * 0.4, d)
                    if aa > a { a = aa; shade = 0.3 + s * 0.7; hue = tone }
                }
            }
            var c = mix3(lo, hi, hue)
            if hue > 0.9 { c = V3(0.42, 0.4, 0.2) }       // a few dry blades
            c *= shade
            return SIMD4(c.x, c.y, c.z, a)
        }
        let m = SCNMaterial()
        m.lightingModel = .lambert
        m.diffuse.contents = img
        m.isDoubleSided = true
        // alpha-tested cut-outs: no sorting, no blended overdraw
        m.blendMode = .replace
        m.writesToDepthBuffer = true
        m.readsFromDepthBuffer = true
        m.diffuse.mipFilter = .linear
        m.shaderModifiers = [.geometry: "float hgt = 1.0 - _geometry.texcoords[0].y;\nfloat sw = sin(scn_frame.time * 1.6 + _geometry.position.x * 0.35 + _geometry.position.z * 0.27) + 0.4 * sin(scn_frame.time * 3.7 + _geometry.position.x * 1.3);\n_geometry.position.x += sw * 0.045 * hgt;\n_geometry.position.z += sw * 0.03 * hgt;", .surface: "if (_surface.diffuse.a < 0.45) { discard_fragment(); }\n_surface.diffuse = float4(_surface.diffuse.rgb / max(_surface.diffuse.a, 0.001), 1.0);\n_surface.normal = normalize((scn_frame.viewTransform * float4(0.0, 1.0, 0.0, 0.0)).xyz);"]
        bladeCache[key] = m
        return m
    }

    static let flower: SCNMaterial = {
        let img = makePixelImage(128, 128) { px, py in
            let x = Float(px) / 64 - 1, y = Float(py) / 64 - 1
            let r = sqrtf(x * x + y * y), th = atan2f(y, x)
            let petal = 0.55 + 0.35 * abs(cosf(th * 2.5))
            if r < 0.18 { return SIMD4(0.9, 0.7, 0.1, 1) }
            if r < petal { return SIMD4(0.96, 0.95, 0.9, smoothstep(petal, petal - 0.08, r)) }
            return SIMD4(0, 0, 0, 0)
        }
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = img
        m.roughness.contents = 0.7
        m.isDoubleSided = true
        m.transparencyMode = .aOne
        return m
    }()

    /// Vertical board-and-batten siding with worn barn-red paint over grey wood. 4 m per tile.
    static func siding(_ paint: V3, seed: Int32, horizontal: Bool = false) -> SCNMaterial {
        let W = 1024
        let p = makePBR(W, W, bump: 3) { x, y in
            let u = Float(x) / Float(W), v = Float(y) / Float(W)
            let a = horizontal ? v : u, b = horizontal ? u : v
            var t = TexSample()
            let boards: Float = horizontal ? 20 : 18
            let fb = a * boards, bi = floorf(fb), fr = fb - bi
            let grain = Noise.streak(horizontal ? b : a * 0.25 + bi * 0.13, horizontal ? a : b, fu: 64, fv: 4, seed: seed &+ Int32(bi))
            let groove = horizontal ? smoothstep(0.0, 0.12, fr) : (smoothstep(0.0, 0.04, fr) * smoothstep(1.0, 0.96, fr))
            let batten = horizontal ? 0 : smoothstep(0.08, 0.03, min(fr, 1 - fr))
            let wear = smoothstep(0.15, 0.45, Noise.tfbm(u, v, freq: 6, octaves: 5, seed: seed &+ 9) + grain * 0.2 + (horizontal ? 0 : (1 - v) * 0.15))
            let wood = V3(0.42, 0.38, 0.33) * (0.75 + grain * 0.35)
            let pcol = paint * (0.85 + Noise.tfbm(u, v, freq: 12, octaves: 3, seed: seed &+ 4) * 0.2)
            var c = mix3(pcol, wood, wear * 0.8)
            c *= 0.55 + 0.45 * groove
            t.albedo = c
            t.height = groove * 0.6 + batten * 0.4 + grain * 0.12 - wear * 0.1
            t.rough = mixf(0.6, 0.85, wear)
            return t
        }
        return pbrMaterial(p)
    }
    static let barnRed = siding(V3(0.45, 0.07, 0.05), seed: 101)
    static let whiteTrim = pbr(color(0.85, 0.84, 0.8), rough: 0.6)
    static let clapboard = siding(V3(0.86, 0.85, 0.8), seed: 111, horizontal: true)

    static let roofMetal: SCNMaterial = {
        let W = 512
        let p = makePBR(W, W, bump: 5, metal: true) { x, y in
            let u = Float(x) / Float(W), v = Float(y) / Float(W)
            var t = TexSample()
            let rib = 0.5 + 0.5 * cosf(u * 16 * tp)
            let rust = smoothstep(0.25, 0.6, Noise.tfbm(u, v, freq: 5, octaves: 5, seed: 121) + v * 0.25 - 0.1)
            let streakv = Noise.streak(u, v, fu: 32, fv: 2, seed: 122)
            t.albedo = mix3(V3(0.55, 0.56, 0.56) * (0.85 + streakv * 0.2), V3(0.35, 0.16, 0.07), rust)
            t.metal = 0.8 * (1 - rust)
            t.rough = mixf(0.4, 0.85, rust)
            t.height = rib * 0.8
            return t
        }
        return pbrMaterial(p)
    }()

    static let shingles: SCNMaterial = {
        let W = 512
        let p = makePBR(W, W, bump: 3) { x, y in
            let u = Float(x) / Float(W), v = Float(y) / Float(W)
            var t = TexSample()
            let row = v * 16, ri = floorf(row), fr = row - ri
            let off: Float = Int(ri).isMultiple(of: 2) ? 0 : 0.5
            let col = u * 12 + off, ci = floorf(col), fc = col - ci
            let tone = Noise.cell(Int(ci) & 31, Int(ri) & 31, 5)
            let grit = Noise.cell(x, y, 6)
            t.albedo = V3(0.2, 0.19, 0.18) * (0.75 + tone * 0.4 + grit * 0.15)
            t.height = fr * 0.6 - (fc < 0.03 ? 0.3 : 0)
            t.rough = 0.9
            return t
        }
        return pbrMaterial(p)
    }()

    static let woodGrey: SCNMaterial = {
        let p = makePBR(512, 512, bump: 3) { x, y in
            let u = Float(x) / 512, v = Float(y) / 512
            var t = TexSample()
            let g = Noise.streak(u, v, fu: 24, fv: 2, seed: 131)
            let crack = smoothstep(0.02, 0, abs(Noise.streak(u, v, fu: 6, fv: 1, seed: 132))) * 0.6
            t.albedo = V3(0.4, 0.36, 0.3) * (0.75 + g * 0.35) * (1 - crack * 0.5)
            t.height = g * 0.5 - crack
            t.rough = 0.85
            return t
        }
        return pbrMaterial(p)
    }()

    static let woodFresh: SCNMaterial = {
        let p = makePBR(512, 512, bump: 2) { x, y in
            let u = Float(x) / 512, v = Float(y) / 512
            var t = TexSample()
            let g = Noise.streak(u, v, fu: 20, fv: 2, seed: 141)
            let ring = sinf((u * 30 + Noise.tfbm(u, v, freq: 2, octaves: 3, seed: 142) * 6) * tp) * 0.5 + 0.5
            t.albedo = V3(0.55, 0.4, 0.25) * (0.8 + g * 0.2 + ring * 0.1)
            t.height = g * 0.3 + ring * 0.2
            t.rough = 0.7
            return t
        }
        return pbrMaterial(p)
    }()

    static let hay: SCNMaterial = {
        let W = 512
        let p = makePBR(W, W, bump: 4) { x, y in
            let u = Float(x) / Float(W), v = Float(y) / Float(W)
            var t = TexSample()
            let a = Noise.streak(u, v, fu: 96, fv: 6, seed: 151)
            let b = Noise.streak(v, u, fu: 80, fv: 5, seed: 152)
            let top = max(a, b * 0.9)
            let tone = Noise.tfbm(u, v, freq: 4, octaves: 3, seed: 153)
            t.albedo = mix3(V3(0.62, 0.5, 0.25), V3(0.78, 0.68, 0.38), tone * 0.5 + 0.5) * (0.7 + top * 0.45)
            t.height = top
            t.rough = 0.9
            return t
        }
        return pbrMaterial(p)
    }()

    static let concrete: SCNMaterial = {
        let W = 512
        let p = makePBR(W, W, bump: 2) { x, y in
            let u = Float(x) / Float(W), v = Float(y) / Float(W)
            var t = TexSample()
            let n = Noise.tfbm(u, v, freq: 16, octaves: 4, seed: 161)
            let stave = smoothstep(0.02, 0, abs((v * 8).truncatingRemainder(dividingBy: 1) - 0.5) - 0.48)
            let streaks = smoothstep(0.1, 0.5, Noise.streak(u, v, fu: 20, fv: 1, seed: 162)) * 0.25
            t.albedo = V3(0.62, 0.6, 0.56) * (0.85 + n * 0.15) * (1 - streaks) * (1 - stave * 0.3)
            t.height = n * 0.3 - stave * 0.4
            t.rough = 0.88
            return t
        }
        return pbrMaterial(p)
    }()

    static let wire: SCNMaterial = {
        let W = 256
        let img = makePixelImage(W, W) { px, py in
            // hexagonal chicken wire, 5 cm cells
            let x = Float(px) / Float(W) * 8, y = Float(py) / Float(W) * 8
            let row = floorf(y * 1.5)
            let off: Float = Int(row).isMultiple(of: 2) ? 0 : 0.5
            let fx = (x + off).truncatingRemainder(dividingBy: 1) - 0.5, fy = (y * 1.5).truncatingRemainder(dividingBy: 1) - 0.5
            let d = max(abs(fx) * 1.0 + abs(fy) * 0.58, abs(fy) * 1.15)
            let a = smoothstep(0.43, 0.47, d) * 0.7
            return SIMD4(0.42, 0.43, 0.42, a)
        }
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = img
        m.metalness.contents = 0.7
        m.roughness.contents = 0.5
        m.isDoubleSided = true
        m.transparencyMode = .aOne
        m.diffuse.wrapS = .repeat; m.diffuse.wrapT = .repeat
        return m
    }()

    static let bark: SCNMaterial = {
        let p = makePBR(512, 512, bump: 5) { x, y in
            let u = Float(x) / 512, v = Float(y) / 512
            var t = TexSample()
            let r = Noise.streak(u, v, fu: 10, fv: 2, seed: 171)
            let fis = smoothstep(0.1, -0.2, r)
            t.albedo = V3(0.25, 0.2, 0.15) * (0.8 + r * 0.3) * (1 - fis * 0.5)
            t.height = r
            t.rough = 0.9
            return t
        }
        return tiled(pbrMaterial(p), 2, 1)
    }()

    static let leaves: SCNMaterial = {
        let W = 512
        var rr = RNG(181)
        let lv = (0..<260).map { _ in (rr.float(), rr.float(), rr.range(0, 6.28), rr.range(0.03, 0.055), rr.float()) }
        let p = makePBR(W, W, bump: 4) { x, y in
            let u = Float(x) / Float(W), v = Float(y) / Float(W)
            var t = TexSample()
            var h: Float = 0, tone: Float = 0.5
            for (cx, cy, a, s, tn) in lv {
                var dx = u - cx, dy = v - cy
                dx -= roundf(dx); dy -= roundf(dy)
                let ca = cosf(a), sa = sinf(a)
                let lx = (dx * ca + dy * sa) / s, ly = (-dx * sa + dy * ca) / (s * 0.5)
                let d = lx * lx + ly * ly
                if d < 1 { let hh = (1 - d) + (1 - abs(ly)) * 0.2; if hh > h { h = hh; tone = tn } }
            }
            let c = mix3(V3(0.08, 0.16, 0.04), V3(0.2, 0.3, 0.07), tone)
            t.albedo = h > 0 ? c * (0.7 + h * 0.4) : V3(0.03, 0.06, 0.02)
            t.height = h
            t.rough = 0.6
            return t
        }
        return tiled(pbrMaterial(p), 2, 2)
    }()

    static let dirt: SCNMaterial = {
        let p = makePBR(512, 512, bump: 3) { x, y in
            let u = Float(x) / 512, v = Float(y) / 512
            var t = TexSample()
            let n = Noise.tfbm(u, v, freq: 8, octaves: 5, seed: 191)
            let pebble = Noise.cell(x / 3, y / 3, 192)
            t.albedo = V3(0.33, 0.25, 0.17) * (0.8 + n * 0.3) + (pebble > 0.96 ? V3(0.1, 0.1, 0.1) : .zero)
            t.height = n * 0.5 + (pebble > 0.96 ? 0.5 : 0)
            t.rough = 0.95
            return t
        }
        return pbrMaterial(p)
    }()

    static let water: SCNMaterial = {
        let p = makePBR(512, 512, bump: 1.2) { x, y in
            let u = Float(x) / 512, v = Float(y) / 512
            var t = TexSample()
            t.height = Noise.tfbm(u, v, freq: 6, octaves: 5, seed: 201)
            t.albedo = V3(0.05, 0.09, 0.08)
            t.rough = 0.05
            return t
        }
        let m = pbrMaterial(p)
        m.transparency = 0.82
        m.transparencyMode = .dualLayer
        m.metalness.contents = 0.0
        m.roughness.contents = 0.04
        tiled(m, 18, 18)
        return m
    }()

    static let pumpkin = pbr(color(0.85, 0.38, 0.05), rough: 0.45)
    static let stem = pbr(color(0.3, 0.3, 0.12), rough: 0.8)
    static let eggBrown = pbr(color(0.72, 0.5, 0.32), rough: 0.5)
    static let eggYolk = pbr(color(0.95, 0.65, 0.05), rough: 0.2)
    static let eggWhite = pbr(color(0.95, 0.95, 0.9, 0.85), rough: 0.1)
    static let galv = pbr(color(0.62, 0.63, 0.64), rough: 0.35, metal: 0.9)
    static let rubber = pbr(color(0.03, 0.03, 0.03), rough: 0.8)
    static let tractorGreen = pbr(color(0.05, 0.3, 0.1), rough: 0.35)
    static let tractorYellow = pbr(color(0.9, 0.7, 0.05), rough: 0.35)
    static let glass: SCNMaterial = { let m = pbr(color(0.15, 0.2, 0.22), rough: 0.05, metal: 0.4); return m }()
    static let apple = pbr(color(0.7, 0.06, 0.05), rough: 0.3)
    static let ballWhite = pbr(color(0.92, 0.92, 0.9), rough: 0.35)
    static let black = pbr(color(0.03, 0.03, 0.03), rough: 0.6)
    static let doorDark = pbr(color(0.07, 0.05, 0.04), rough: 0.9)
}
