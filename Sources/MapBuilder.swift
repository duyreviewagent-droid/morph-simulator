import SceneKit
import simd

/// Scenery for the nine generated maps.
enum MapBuilder {
    static let rock = Coats.coat(.skin, V3(0.46, 0.44, 0.41), V3(0.3, 0.29, 0.27))
    static let redRock = Coats.coat(.skin, V3(0.62, 0.36, 0.22), V3(0.45, 0.25, 0.15))
    static let sandstone = Coats.coat(.skin, V3(0.82, 0.68, 0.45), V3(0.7, 0.55, 0.35))
    static let snow: SCNMaterial = { let m = pbr(color(0.92, 0.94, 0.98), rough: 0.55); m.clearCoat.contents = 0.2; return m }()
    static let ice: SCNMaterial = { let m = pbr(color(0.7, 0.88, 0.95), rough: 0.08); m.transparency = 0.85; m.clearCoat.contents = 1; return m }()
    static let pineGreen = Coats.coat(.fur, V3(0.08, 0.2, 0.08), V3(0.04, 0.12, 0.05))
    static let palmLeaf = Coats.coat(.fur, V3(0.2, 0.42, 0.1), V3(0.12, 0.3, 0.05))
    static let deadWood = Coats.coat(.skin, V3(0.28, 0.26, 0.23), V3(0.18, 0.17, 0.15))
    static let cactus = Coats.coat(.fur, V3(0.22, 0.42, 0.18), V3(0.15, 0.3, 0.12))
    static let stoneBlock = Coats.coat(.cells, V3(0.5, 0.5, 0.46), V3(0.3, 0.3, 0.28))

    static func build(_ w: World) {
        switch w.mapIndex {
        case 1: savanna(w)
        case 2: arctic(w)
        case 3: jungle(w)
        case 4: desert(w)
        case 5: beach(w)
        case 6: forest(w)
        case 7: mountains(w)
        case 8: swamp(w)
        case 9: park(w)
        default: break
        }
    }

    // MARK: helpers

    static func ground(_ w: World, _ x: Float, _ z: Float) -> Float { w.terrain(x, z) }

    /// Random spots on dry land away from the spawn.
    static func spots(_ w: World, _ n: Int, seed: UInt64, r0: Float = 10, r1: Float = 200, dry: Bool = true, avoid: [(Float, Float, Float)] = []) -> [(Float, Float)] {
        var rr = RNG(seed)
        var out: [(Float, Float)] = []
        var tries = 0
        while out.count < n && tries < n * 30 {
            tries += 1
            let a = rr.range(0, 2 * .pi), d = r0 + (r1 - r0) * sqrtf(rr.float())
            let x = cosf(a) * d + w.map.spawn.x, z = sinf(a) * d + w.map.spawn.z
            guard abs(x) < Farm.half - 12, abs(z) < Farm.half - 12 else { continue }
            if dry, let lvl = w.map.waterLevel, w.terrain(x, z) < lvl + 0.3 { continue }
            if avoid.contains(where: { simd_length(SIMD2(x - $0.0, z - $0.1)) < $0.2 }) { continue }
            out.append((x, z))
        }
        return out
    }

    static func boulder(_ w: World, _ x: Float, _ z: Float, _ s: Float, _ m: SCNMaterial = rock, seed: Int32) {
        let g = loft((0...8).map { i -> Ring in
            let t = Float(i) / 8
            let r = sinf(.pi * t) * s + 0.01
            return Ring(V3(0, (t - 0.5) * s * 1.4, 0), r, r * 0.9)
        }, seg: 18, ref: V3(0, 0, 1)) { p, _, _, _ in Noise.fbm(p.x * 1.5 / s + Float(seed), p.y * 1.5 / s + p.z * 1.3 / s, octaves: 3, seed: seed) * s * 0.35 }
        g.materials = [m]
        let n = SCNNode(geometry: g)
        n.simdPosition = V3(x, ground(w, x, z) + s * 0.35, z)
        n.simdEulerAngles = V3(0, Float(seed % 7), 0)
        w.add(n)
        if s > 0.6 { w.solids.append(.cyl(x, z, s * 0.85, s * 1.1, base: ground(w, x, z), tag: "rock", surface: .concrete)) }
    }

    static func pine(_ w: World, _ x: Float, _ z: Float, _ s: Float, snowy: Bool = false) {
        let y = ground(w, x, z)
        let n = SCNNode(); n.simdPosition = V3(x, y, z)
        w.add(n)
        n.addChildNode(coneNode(CGFloat(0.22 * s), CGFloat(0.03 * s), CGFloat(7.5 * s), Mat.bark, seg: 8).at(0, 3.75 * s, 0))
        n.addChildNode(coneNode(CGFloat(1.1 * s), 0.05, CGFloat(5.5 * s), Coats.plain(V3(0.03, 0.08, 0.03), rough: 0.9), seg: 10).at(0, 4.3 * s, 0))
        let br = Foliage.pineBranches(height: 7.8 * s, radius: 2.2 * s, tiers: 9, seed: UInt64(abs(Int(x * 31 + z)) + 1))
        n.addChildNode(br)
        if snowy {
            for k in 0..<4 {
                let r = (1.6 - Float(k) * 0.35) * s, yy = (2.2 + Float(k) * 1.4) * s
                n.addChildNode(coneNode(CGFloat(r), 0.02, CGFloat(0.6 * s), snow, seg: 12).at(0, yy + 0.2 * s, 0))
            }
        }
        w.solids.append(.cyl(x, z, 0.3 * s, 7 * s, base: y, tag: "tree", surface: .wood))
    }

    static func oak(_ w: World, _ x: Float, _ z: Float, _ s: Float, seed: UInt64, leaves: SCNMaterial = Mat.leaves) {
        var rr = RNG(seed)
        let y = ground(w, x, z)
        let n = SCNNode(); n.simdPosition = V3(x, y, z)
        w.add(n)
        let th = 2.4 * s
        n.addChildNode(loftNode([Ring(V3(0, -0.2, 0), 0.32 * s, 0.3 * s), Ring(V3(0, 0.3, 0), 0.22 * s, 0.2 * s), Ring(V3(0.05, th, 0.03), 0.14 * s, 0.13 * s), Ring(V3(0.1, th + 0.8 * s, 0.05), 0.06 * s, 0.06 * s)], Mat.bark, seg: 12, smooth: 3))
        let lm = leaves === Mat.leaves ? Foliage.leafMat(V3(0.06, 0.16, 0.04), V3(0.2, 0.34, 0.08), seed: 3) : leaves
        for _ in 0..<3 {
            let a = rr.range(0, 6.28), d = rr.range(0.3, 1.1) * s
            n.addChildNode(Foliage.crown(center: V3(cosf(a) * d, th + 1.4 * s + rr.range(-0.3, 0.8) * s, sinf(a) * d), radii: V3(1.8, 1.4, 1.8) * s * rr.range(0.85, 1.15), cards: 130, size: 1.1 * s, seed: rr.next(), lm))
        }
        w.solids.append(.cyl(x, z, 0.35 * s, th + 3 * s, base: y, tag: "tree", surface: .wood))
    }

    static func palm(_ w: World, _ x: Float, _ z: Float, _ s: Float, seed: UInt64) {
        var rr = RNG(seed)
        let y = ground(w, x, z)
        let n = SCNNode(); n.simdPosition = V3(x, y, z)
        n.simdEulerAngles = V3(0, rr.range(0, 6.28), 0)
        w.add(n)
        let lean = rr.range(0.8, 2.2) * s, h = 6 * s
        var rings: [Ring] = []
        for k in 0...8 {
            let t = Float(k) / 8
            rings.append(Ring(V3(lean * t * t, h * t, 0), 0.2 * s * (1 - t * 0.35), 0.2 * s * (1 - t * 0.35)))
        }
        n.addChildNode(loftNode(rings, Coats.coat(.bands, V3(0.45, 0.36, 0.25), V3(0.35, 0.27, 0.18)), seg: 12, smooth: 1))
        let top = V3(lean, h, 0)
        for k in 0..<9 {
            let a = Float(k) / 9 * 2 * .pi + rr.range(0, 0.3)
            let dir = V3(cosf(a), 0, sinf(a))
            let len = 2.6 * s
            n.addChildNode(loftNode([Ring(top, 0.03 * s, 0.01 * s), Ring(top + dir * len * 0.4 + V3(0, 0.35 * s, 0), 0.35 * s, 0.02 * s),
                                     Ring(top + dir * len * 0.8 - V3(0, 0.3 * s, 0), 0.25 * s, 0.015 * s), Ring(top + dir * len - V3(0, 0.9 * s, 0), 0.02 * s, 0.01 * s)],
                                    palmLeaf, seg: 6, ref: V3(0, 1, 0), smooth: 3))
        }
        for k in 0..<4 { n.addChildNode(sphereNode(CGFloat(0.13 * s), Coats.plain(V3(0.35, 0.25, 0.12)), seg: 10).at(top.x + cosf(Float(k) * 1.6) * 0.2 * s, top.y - 0.25 * s, sinf(Float(k) * 1.6) * 0.2 * s)) }
        w.solids.append(.cyl(x, z, 0.25 * s, h, base: y, tag: "tree", surface: .wood))
    }

    static func stepped(_ w: World, _ x: Float, _ z: Float, levels: Int, base: Float, stepH: Float, shrink: Float, _ m: SCNMaterial, tag: String) {
        let y0 = ground(w, x, z) - 0.3
        for k in 0..<levels {
            let size = base - Float(k) * shrink
            guard size > 0.5 else { break }
            let b = World.meterBox(size, stepH, size, m, uv: 0.4)
            b.simdPosition = V3(x, y0 + Float(k) * stepH + stepH / 2, z)
            w.add(b)
            w.solids.append(.box(x, z, size, size, Float(k + 1) * stepH, base: y0, tag: tag, surface: .concrete))
        }
    }

    static func cabin(_ w: World, _ x: Float, _ z: Float, yaw: Float, stilts: Float = 0) {
        let y = ground(w, x, z) + stilts
        let n = SCNNode(); n.simdPosition = V3(x, y, z); n.simdEulerAngles = V3(0, yaw, 0)
        w.add(n)
        let logM = Coats.coat(.bands, V3(0.45, 0.3, 0.17), V3(0.35, 0.22, 0.12))
        n.addChildNode(World.meterBox(6, 3, 5, logM, uv: 0.5).at(0, 1.5, 0))
        for sz in [Float(1), -1] { n.addChildNode(World.meterBox(7, 0.15, 3.3, Mat.shingles, uv: 0.5).at(0, 3.75, sz * 1.35).rot(sz * 0.55, 0, 0)) }
        n.addChildNode(World.poly([V3(-3, 3, 2.51), V3(3, 3, 2.51), V3(0, 4.6, 2.51)], logM))
        n.addChildNode(World.poly([V3(3, 3, -2.51), V3(-3, 3, -2.51), V3(0, 4.6, -2.51)], logM))
        n.addChildNode(boxNode(1, 2, 0.05, Mat.doorDark).at(0, 1, 2.52))
        n.addChildNode(boxNode(0.9, 0.8, 0.05, Mat.glass).at(1.9, 1.8, 2.52))
        if stilts > 0 {
            for (px, pz) in [(Float(-2.8), Float(-2.3)), (2.8, -2.3), (-2.8, 2.3), (2.8, 2.3)] { n.addChildNode(cylNode(0.12, CGFloat(stilts + 1), Mat.woodGrey, seg: 8).at(px, -stilts / 2 - 0.5, pz)) }
            n.addChildNode(World.meterBox(8, 0.15, 7, Mat.woodGrey, uv: 1).at(0, -0.05, 0.8))
        }
        w.solids.append(Solid(minX: x - 3.4, maxX: x + 3.4, minZ: z - 3.4, maxZ: z + 3.4, bottom: y - 0.5, top: { _, _ in y + 3.2 }, tag: "cabin", surface: .wood))
        if stilts > 0 { w.solids.append(.box(x, z, 8.2, 8.2, 0.02, base: y - 0.02, tag: "deck", surface: .wood)) }
    }

    // MARK: maps

    static func savanna(_ w: World) {
        var rr = RNG(11)
        for (x, z) in spots(w, 78, seed: 12, avoid: [(22, 18, 14)]) {
            let s = rr.range(0.9, 1.4)
            let y = ground(w, x, z)
            let n = SCNNode(); n.simdPosition = V3(x, y, z)
            w.add(n)
            n.addChildNode(limb(3.5 * s, 0.25 * s, 0.15 * s, Mat.bark, seg: 10, dir: V3(0.25, 1, 0)).at(0, 0, 0))
            n.addChildNode(limb(1.8 * s, 0.12 * s, 0.07 * s, Mat.bark, seg: 8, dir: V3(-0.8, 1, 0.3)).at(0.6 * s, 2.5 * s, 0))
            let am = Foliage.leafMat(V3(0.12, 0.2, 0.05), V3(0.3, 0.36, 0.1), seed: 5)
            for k in 0..<3 {
                let a = Float(k) * 2.1 + rr.range(0, 0.6)
                n.addChildNode(Foliage.crown(center: V3(0.8 * s + cosf(a) * 1.3 * s, 4.0 * s + rr.range(0, 0.4), sinf(a) * 1.3 * s), radii: V3(2.3, 0.45, 2.3) * s, cards: 110, size: 0.9 * s, seed: rr.next(), am))
            }
            w.solids.append(.cyl(x, z, 0.3 * s, 4 * s, base: y, tag: "tree", surface: .wood))
        }
        for (i, (x, z)) in spots(w, 30, seed: 13, avoid: [(22, 18, 14)]).enumerated() {
            let h = rr.range(1.5, 3.2)
            let m = coneNode(CGFloat(h * 0.45), 0.08, CGFloat(h), redRock, seg: 12)
            m.simdPosition = V3(x, ground(w, x, z) + h / 2 - 0.1, z)
            w.add(m)
            w.solids.append(.cyl(x, z, h * 0.35, h * 0.8, base: ground(w, x, z), tag: "mound", surface: .dirt))
            if i % 3 == 0 { boulder(w, x + 4, z + 2, rr.range(0.8, 2), redRock, seed: Int32(i)) }
        }
        // a big kopje of rocks to climb
        for k in 0..<7 { boulder(w, -30 + Float(k % 3) * 2.5, -25 + Float(k / 3) * 2.2, 1.5 + Float(k % 2), rock, seed: Int32(40 + k)) }
    }

    static func arctic(_ w: World) {
        var rr = RNG(21)
        for (x, z) in spots(w, 90, seed: 22, r0: 20, avoid: [(-28, -22, 26)]) { pine(w, x, z, rr.range(0.8, 1.3), snowy: true) }
        // ice floes on the lake and icebergs
        for k in 0..<14 {
            let a = rr.range(0, 6.28), d = rr.range(2, 15)
            let x = -28 + cosf(a) * d, z = -22 + sinf(a) * d
            let s = rr.range(1, 2.6)
            let f = boxNode(CGFloat(s), 0.3, CGFloat(s * rr.range(0.6, 1.2)), snow, chamfer: 0.1)
            f.simdPosition = V3(x, -0.55, z); f.simdEulerAngles = V3(0, rr.range(0, 3), 0)
            w.add(f)
            w.solids.append(.cyl(x, z, s * 0.4, 0.3, base: -0.7, tag: "floe", surface: .concrete))
            if k < 3 {
                let b = sphereNode(CGFloat(rr.range(2, 3.5)), ice, seg: 12).scl(1, 1.4, 0.8)
                b.simdPosition = V3(x + 4, 0.8, z + 3)
                w.add(b)
                w.solids.append(.cyl(x + 4, z + 3, 2.2, 4, base: -1, tag: "iceberg", surface: .concrete))
            }
        }
        // igloo
        let ix: Float = 14, iz: Float = 10
        let iy = ground(w, ix, iz)
        let dome = SCNSphere(radius: 2.6); dome.segmentCount = 24; dome.materials = [Coats.coat(.cells, V3(0.92, 0.94, 0.98), V3(0.78, 0.84, 0.92))]
        w.add(SCNNode(geometry: dome).at(ix, iy, iz))
        w.add(cylNode(0.9, 1.8, snow, seg: 16).rot(Float.pi / 2, 0, 0).at(ix, iy + 0.6, iz + 2.8))
        w.add(boxNode(1.1, 1.2, 0.1, Mat.doorDark).at(ix, iy + 0.55, iz + 3.72))
        w.solids.append(Solid(minX: ix - 2.6, maxX: ix + 2.6, minZ: iz - 2.6, maxZ: iz + 2.6, bottom: iy - 1, top: { x, z in iy + sqrtf(max(0, 6.76 - (x - ix) * (x - ix) - (z - iz) * (z - iz))) }, round: (ix, iz, 2.6), tag: "igloo", surface: .concrete))
        for k in 0..<12 { boulder(w, rr.range(-180, 180), rr.range(-180, 180), rr.range(0.5, 1.6), snow, seed: Int32(k + 60)) }
    }

    static func jungle(_ w: World) {
        var rr = RNG(31)
        let vine = Coats.plain(V3(0.12, 0.25, 0.06), rough: 0.8)
        for (x, z) in spots(w, 165, seed: 32, r0: 8) {
            if abs(z - sinf(x * 0.035) * 18 - 8) < 9 { continue }
            let s = rr.range(1.1, 1.8)
            let y = ground(w, x, z)
            let n = SCNNode(); n.simdPosition = V3(x, y, z)
            w.add(n)
            let h = 11 * s
            n.addChildNode(loftNode([Ring(V3(0, -0.3, 0), 0.8 * s, 0.8 * s, e: 3), Ring(V3(0, 1, 0), 0.4 * s, 0.4 * s), Ring(V3(0, h * 0.6, 0), 0.3 * s, 0.3 * s), Ring(V3(0, h, 0), 0.2 * s, 0.2 * s)], Mat.bark, seg: 12, smooth: 3))
            let jm = Foliage.leafMat(V3(0.03, 0.12, 0.03), V3(0.12, 0.3, 0.06), seed: 7)
            for _ in 0..<3 {
                let a = rr.range(0, 6.28), d = rr.range(0.5, 2.0) * s
                n.addChildNode(Foliage.crown(center: V3(cosf(a) * d, h + rr.range(-0.5, 1.2) * s, sinf(a) * d), radii: V3(3.2, 1.6, 3.2) * s, cards: 120, size: 1.5 * s, seed: rr.next(), jm))
            }
            for _ in 0..<4 {
                let a = rr.range(0, 6.28), d = rr.range(1, 3) * s, l = rr.range(3, 8) * s
                n.addChildNode(cylNode(0.03, CGFloat(l), vine, seg: 4).at(cosf(a) * d, h - l / 2, sinf(a) * d))
            }
            w.solids.append(.cyl(x, z, 0.6 * s, h, base: y, tag: "tree", surface: .wood))
        }
        for (x, z) in spots(w, 270, seed: 33, r0: 4) {
            if abs(z - sinf(x * 0.035) * 18 - 8) < 7 { continue }
            let b = sphereNode(CGFloat(rr.range(0.5, 1.1)), Mat.leaves, seg: 10).scl(1.3, 0.6, 1.3)
            b.simdPosition = V3(x, ground(w, x, z) + 0.2, z)
            w.add(b)
        }
        // an overgrown temple to climb
        stepped(w, -30, -35, levels: 9, base: 18, stepH: 0.9, shrink: 1.8, stoneBlock, tag: "temple")
        let ty = ground(w, -30, -35) - 0.3 + 8.1
        w.add(World.meterBox(2.5, 2.2, 2.5, stoneBlock).at(-30, ty + 1.1, -35))
        w.solids.append(.box(-30, -35, 2.5, 2.5, 2.2, base: ty, tag: "shrine", surface: .concrete))
    }

    static func desert(_ w: World) {
        var rr = RNG(41)
        for (x, z) in spots(w, 120, seed: 42, avoid: [(30, -20, 12), (-35, 30, 20)]) {
            let s = rr.range(0.8, 1.5)
            let y = ground(w, x, z)
            let n = SCNNode(); n.simdPosition = V3(x, y, z)
            w.add(n)
            n.addChildNode(cylNode(CGFloat(0.28 * s), CGFloat(4 * s), cactus, seg: 12).at(0, 2 * s, 0))
            n.addChildNode(sphereNode(CGFloat(0.28 * s), cactus, seg: 12).at(0, 4 * s, 0))
            for sd in [Float(1), -1] where rr.chance(0.8) {
                let hy = rr.range(1.4, 2.6) * s
                n.addChildNode(cylNode(CGFloat(0.18 * s), CGFloat(0.8 * s), cactus, seg: 10).rot(0, 0, Float.pi / 2).at(sd * 0.5 * s, hy, 0))
                n.addChildNode(cylNode(CGFloat(0.18 * s), CGFloat(1.3 * s), cactus, seg: 10).at(sd * 0.9 * s, hy + 0.6 * s, 0))
                n.addChildNode(sphereNode(CGFloat(0.18 * s), cactus, seg: 10).at(sd * 0.9 * s, hy + 1.25 * s, 0))
            }
            w.solids.append(.cyl(x, z, 0.35 * s, 4.2 * s, base: y, tag: "cactus", surface: .wood))
        }
        for (i, (x, z)) in spots(w, 42, seed: 43, r0: 30, avoid: [(30, -20, 12), (-35, 30, 20)]).enumerated() { boulder(w, x, z, rr.range(1, 3), redRock, seed: Int32(i + 70)) }
        for k in 0..<7 {
            let a = Float(k) / 7 * 2 * .pi
            palm(w, 30 + cosf(a) * rr.range(8, 11), -20 + sinf(a) * rr.range(8, 11), rr.range(0.9, 1.2), seed: UInt64(k + 44))
        }
        // the pyramid: climb it, glide off it
        stepped(w, -35, 30, levels: 16, base: 30, stepH: 1.0, shrink: 1.85, sandstone, tag: "pyramid")
    }

    static func beach(_ w: World) {
        var rr = RNG(51)
        for (x, z) in spots(w, 78, seed: 52, r0: 6, r1: 140) where z > -120 && z < 12 + sinf(x * 0.04) * 6 { palm(w, x, z, rr.range(0.9, 1.3), seed: UInt64(abs(Int(x * 13 + z)) + 1)) }
        for (i, (x, z)) in spots(w, 66, seed: 53, r0: 10, r1: 180, dry: false).enumerated() where z > 10 { boulder(w, x, z, rr.range(0.6, 2.2), rock, seed: Int32(i + 80)) }
        // pier out into the sea
        let px: Float = -12
        let sz = 18 + sinf(px * 0.04) * 6 - 6
        w.add(World.meterBox(3, 0.2, 40, Mat.woodGrey, uv: 1).at(px, 1.2, sz + 20))
        for k in 0..<11 { for sd in [Float(1), -1] { w.add(cylNode(0.15, 8, Mat.woodGrey, seg: 8).at(px + sd * 1.3, -2.8, sz + Float(k) * 4)) } }
        w.solids.append(.box(px, sz + 20, 3, 40, 1.3, base: -8, tag: "pier", surface: .wood))
        // lifeguard tower, umbrellas, a sandcastle
        let lx: Float = 16, lz: Float = 12
        let ly = ground(w, lx, lz)
        for (ox, oz) in [(Float(-1), Float(-1)), (1, -1), (-1, 1), (1, 1)] { w.add(cylNode(0.08, 3, Coats.plain(V3(0.9, 0.9, 0.9)), seg: 8).at(lx + ox, ly + 1.5, lz + oz)) }
        w.add(World.meterBox(2.6, 0.15, 2.6, Mat.woodFresh, uv: 1).at(lx, ly + 3, lz))
        w.add(World.meterBox(2.6, 1.6, 2.6, Coats.plain(V3(0.9, 0.2, 0.15)), uv: 1).at(lx, ly + 4, lz).scl(1, 1, 1))
        w.solids.append(.box(lx, lz, 2.8, 2.8, 4.8, base: ly, tag: "tower", surface: .wood))
        for k in 0..<5 {
            let x = -25 + Float(k) * 9 + rr.range(-2, 2), z = 6 + rr.range(-3, 3)
            let y = ground(w, x, z)
            w.add(cylNode(0.04, 2.2, Coats.plain(V3(0.9, 0.9, 0.9)), seg: 6).at(x, y + 1.1, z))
            w.add(coneNode(1.3, 0.05, 0.5, Coats.coat(.bands, [V3(0.9, 0.2, 0.2), V3(0.2, 0.5, 0.9), V3(0.95, 0.8, 0.2)][k % 3], V3(0.95, 0.95, 0.95)), seg: 16).at(x, y + 2.2, z))
            w.add(boxNode(0.9, 0.01, 1.8, Coats.plain([V3(0.2, 0.6, 0.9), V3(0.9, 0.4, 0.6)][k % 2]), chamfer: 0).at(x + 1, y + 0.01, z + 1).rot(0, rr.range(0, 3), 0))
        }
        let cx: Float = 4, cz: Float = 10, cy = ground(w, cx, cz)
        for (ox, oz) in [(Float(-0.6), Float(-0.6)), (0.6, -0.6), (-0.6, 0.6), (0.6, 0.6)] { w.add(cylNode(0.25, 0.8, MapBuilder.sandstone, seg: 10).at(cx + ox, cy + 0.4, cz + oz)) }
        w.add(World.meterBox(1.4, 0.5, 1.4, MapBuilder.sandstone).at(cx, cy + 0.25, cz))
    }

    static func forest(_ w: World) {
        var rr = RNG(61)
        for (x, z) in spots(w, 210, seed: 62, r0: 7, avoid: [(-20, 22, 13), (18, -14, 6)]) {
            if rr.chance(0.55) { pine(w, x, z, rr.range(1, 1.6)) } else { oak(w, x, z, rr.range(1, 1.5), seed: UInt64(abs(Int(x * 7 + z)) + 1)) }
        }
        let cap = Coats.coat(.spots, V3(0.8, 0.1, 0.08), V3(0.95, 0.93, 0.88))
        for (x, z) in spots(w, 120, seed: 63, r0: 4, r1: 120) {
            let y = ground(w, x, z), s = rr.range(0.1, 0.3)
            w.add(cylNode(CGFloat(s * 0.3), CGFloat(s * 1.2), Coats.plain(V3(0.9, 0.88, 0.8)), seg: 8).at(x, y + s * 0.6, z))
            w.add(sphereNode(CGFloat(s), cap, seg: 12).scl(1, 0.5, 1).at(x, y + s * 1.2, z))
        }
        for (i, (x, z)) in spots(w, 36, seed: 64, r0: 8, r1: 160).enumerated() {
            let l = rr.range(3, 6), a = rr.range(0, 3)
            let log = cylNode(CGFloat(rr.range(0.3, 0.5)), CGFloat(l), Mat.bark, seg: 12).rot(0, a, Float.pi / 2)
            log.simdPosition = V3(x, ground(w, x, z) + 0.35, z)
            w.add(log)
            if i % 2 == 0 { boulder(w, x + 3, z - 2, rr.range(0.6, 1.4), rock, seed: Int32(i + 90)) }
        }
        cabin(w, 18, -14, yaw: 0.4)
    }

    static func mountains(_ w: World) {
        var rr = RNG(71)
        for (x, z) in spots(w, 135, seed: 72, r0: 15, r1: 150, avoid: [(-10, -30, 16)]) {
            let h = w.terrain(x, z)
            if h < 22 { pine(w, x, z, rr.range(0.9, 1.4), snowy: h > 10) }
        }
        for (i, (x, z)) in spots(w, 78, seed: 73, r0: 8, r1: 180).enumerated() { boulder(w, x, z, rr.range(0.7, 2.6), rock, seed: Int32(i + 100)) }
        cabin(w, 20, 16, yaw: -0.6)
    }

    static func swamp(_ w: World) {
        var rr = RNG(81)
        for (x, z) in spots(w, 135, seed: 82, r0: 8) {
            let y = ground(w, x, z)
            let s = rr.range(0.8, 1.4)
            let n = SCNNode(); n.simdPosition = V3(x, y, z)
            w.add(n)
            n.addChildNode(limb(6 * s, 0.3 * s, 0.1 * s, deadWood, seg: 8, dir: V3(rr.range(-0.2, 0.2), 1, rr.range(-0.2, 0.2))))
            for k in 0..<4 { n.addChildNode(limb(2.2 * s, 0.1 * s, 0.03 * s, deadWood, seg: 6, dir: V3(cosf(Float(k) * 1.7), 0.7, sinf(Float(k) * 1.7))).at(0, (2.5 + Float(k) * 0.8) * s, 0)) }
            let moss = Coats.plain(V3(0.35, 0.38, 0.25), rough: 0.9)
            for k in 0..<3 { n.addChildNode(cylNode(0.04, CGFloat(1.5 * s), moss, seg: 4).at(cosf(Float(k) * 2) * 1.2 * s, 3.8 * s, sinf(Float(k) * 2) * 1.2 * s)) }
            w.solids.append(.cyl(x, z, 0.35 * s, 6 * s, base: y, tag: "tree", surface: .wood))
        }
        let pad = Coats.plain(V3(0.18, 0.4, 0.12), rough: 0.5)
        for (x, z) in spots(w, 480, seed: 83, r0: 3, r1: 100, dry: false) where w.waterLevel(x, z) != nil {
            let r = rr.range(0.2, 0.45)
            w.add(cylNode(CGFloat(r), 0.02, pad, seg: 12).at(x, 0.01, z))
            if rr.chance(0.15) { w.add(sphereNode(0.07, Coats.plain(V3(0.95, 0.7, 0.85)), seg: 8).at(x, 0.08, z)) }
        }
        cabin(w, 0, 0, yaw: 0.3, stilts: 1.6)
    }

    static func park(_ w: World) {
        var rr = RNG(91)
        for (x, z) in spots(w, 120, seed: 92, r0: 10, r1: 175, avoid: [(20, 14, 13), (0, 0, 17)]) {
            let path = min(abs(x - sinf(z * 0.05) * 6), abs(z + 20 + sinf(x * 0.04) * 5))
            if path > 4 { oak(w, x, z, rr.range(1, 1.5), seed: UInt64(abs(Int(x * 5 + z)) + 1)) }
        }
        // fountain in the middle of the loop path
        let fy = ground(w, 0, 0)
        let basin = SCNTube(innerRadius: 3.6, outerRadius: 4, height: 0.7); basin.radialSegmentCount = 40; basin.materials = [Mat.concrete]
        w.add(SCNNode(geometry: basin).at(0, fy + 0.35, 0))
        w.add(cylNode(3.6, 0.02, Mat.water, seg: 40).at(0, fy + 0.5, 0))
        w.add(cylNode(0.35, 2.2, Mat.concrete, seg: 16).at(0, fy + 1.1, 0))
        w.add(cylNode(1.4, 0.25, Mat.concrete, seg: 24).at(0, fy + 2.2, 0))
        w.add(cylNode(1.3, 0.02, Mat.water, seg: 24).at(0, fy + 2.33, 0))
        w.solids.append(.cyl(0, 0, 4, 0.7, base: fy, tag: "fountain", surface: .concrete))
        // benches and lamps around the loop
        let bench = Mat.woodFresh
        for k in 0..<10 {
            let a = Float(k) / 10 * 2 * .pi
            let r: Float = 16.5
            let x = cosf(a) * r, z = sinf(a) * r
            let y = ground(w, x, z)
            let b = SCNNode(); b.simdPosition = V3(x, y, z); b.simdEulerAngles = V3(0, -a - .pi / 2, 0)
            w.add(b)
            b.addChildNode(boxNode(1.8, 0.06, 0.5, bench).at(0, 0.45, 0))
            b.addChildNode(boxNode(1.8, 0.4, 0.05, bench).at(0, 0.75, -0.24))
            for sx in [Float(-0.8), 0.8] { b.addChildNode(boxNode(0.06, 0.45, 0.5, Mat.black).at(sx, 0.22, 0)) }
            if k % 2 == 0 {
                let lx = cosf(a + 0.3) * (r - 1.5), lz = sinf(a + 0.3) * (r - 1.5)
                w.add(cylNode(0.06, 3.5, Mat.black, seg: 8).at(lx, y + 1.75, lz))
                w.add(sphereNode(0.2, pbr(color(1, 0.95, 0.8), rough: 0.3, emission: color(1, 0.9, 0.6)), seg: 10).at(lx, y + 3.6, lz))
            }
        }
        // hedges and the skyline
        for k in 0..<50 {
            let x = rr.range(-170, 170), z = rr.range(-170, 170)
            if simd_length(SIMD2(x, z)) < 20 { continue }
            w.add(World.meterBox(rr.range(3, 7), 1.2, 1, Mat.leaves, uv: 0.5).at(x, ground(w, x, z) + 0.6, z).rot(0, rr.range(0, 3), 0))
        }
        let windows = Coats.coat(.cells, V3(0.55, 0.6, 0.66), V3(0.2, 0.22, 0.26))
        for k in 0..<90 {
            let a = Float(k) / 90 * 2 * .pi, r = rr.range(196, 230)
            let hgt = rr.range(20, 70)
            let b = World.meterBox(rr.range(10, 18), hgt, rr.range(10, 18), windows, uv: 0.08)
            b.simdPosition = V3(cosf(a) * r, hgt / 2 - 1, sinf(a) * r)
            b.simdEulerAngles = V3(0, -a, 0)
            w.add(b)
        }
    }
}
