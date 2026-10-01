import SceneKit
import simd

enum Surface { case grass, dirt, wood, metal, hay, concrete, water }

/// A static collider. Axis-aligned footprint (or a cylinder) with a top that can slope (roofs).
struct Solid {
    var minX: Float, maxX: Float, minZ: Float, maxZ: Float
    var bottom: Float = -5
    var top: (Float, Float) -> Float
    var round: (cx: Float, cz: Float, r: Float)? = nil
    var tag = ""
    var surface: Surface = .wood
    var walkable = true
    var yaw: Float = 0          // rotated boxes (footprint is the unrotated size, centred)

    static func box(_ cx: Float, _ cz: Float, _ w: Float, _ l: Float, _ h: Float, base: Float = 0, tag: String = "", surface: Surface = .wood) -> Solid {
        Solid(minX: cx - w / 2, maxX: cx + w / 2, minZ: cz - l / 2, maxZ: cz + l / 2, bottom: base, top: { _, _ in base + h }, tag: tag, surface: surface)
    }
    static func cyl(_ cx: Float, _ cz: Float, _ r: Float, _ h: Float, base: Float = 0, tag: String = "", surface: Surface = .concrete) -> Solid {
        Solid(minX: cx - r, maxX: cx + r, minZ: cz - r, maxZ: cz + r, bottom: base, top: { _, _ in base + h }, round: (cx, cz, r), tag: tag, surface: surface)
    }
    /// Signed horizontal distance from the footprint edge (negative inside) and the outward direction.
    func edge(_ x: Float, _ z: Float) -> (Float, SIMD2<Float>) {
        if let r = round {
            let d = SIMD2(x - r.cx, z - r.cz)
            let l = simd_length(d)
            return (l - r.r, l > 1e-5 ? d / l : SIMD2(1, 0))
        }
        let cx = (minX + maxX) / 2, cz = (minZ + maxZ) / 2
        if yaw != 0 {
            // work in the box's own frame, then rotate the push direction back
            let c = cosf(yaw), sn = sinf(yaw)
            let dx = x - cx, dz = z - cz
            var me = self; me.yaw = 0
            let hx = (maxX - minX) / 2, hz = (maxZ - minZ) / 2
            me.minX = -hx; me.maxX = hx; me.minZ = -hz; me.maxZ = hz
            let (d, n) = me.edge(dx * c - dz * sn, dx * sn + dz * c)
            return (d, SIMD2(n.x * c + n.y * sn, -n.x * sn + n.y * c))
        }
        let hx = (maxX - minX) / 2, hz = (maxZ - minZ) / 2
        let qx = abs(x - cx) - hx, qz = abs(z - cz) - hz
        if qx > 0 || qz > 0 {
            let ox = max(qx, 0), oz = max(qz, 0)
            let l = sqrtf(ox * ox + oz * oz)
            let dir = SIMD2(ox * (x < cx ? -1 : 1), oz * (z < cz ? -1 : 1))
            return (l, l > 1e-6 ? dir / l : SIMD2(1, 0))
        }
        // inside: push out through the nearest side
        if qx > qz { return (qx, SIMD2(x < cx ? -1 : 1, 0)) }
        return (qz, SIMD2(0, z < cz ? -1 : 1))
    }
}

struct Ladder { var x: Float, z: Float, top: Float, outward: SIMD2<Float>, topStep: SIMD2<Float> }

/// Places on the farm the game logic cares about.
enum Farm {
    static let barn = (x: Float(-20), z: Float(-12), len: Float(18), wid: Float(12), eave: Float(6.5), ridge: Float(10.5))
    static let silo = (x: Float(-7.5), z: Float(-15.5), r: Float(3), h: Float(15))
    static let coopRun = (minX: Float(11), maxX: Float(25), minZ: Float(-21), maxZ: Float(-8))
    static let coopHouse = (x: Float(21.5), z: Float(-17.5))
    static let pasture = (minX: Float(32), maxX: Float(80), minZ: Float(-26), maxZ: Float(36))
    static let pastureGate = (z0: Float(1), z1: Float(6))
    static let coopGate = (x0: Float(15), x1: Float(17.5))
    static let house = (x: Float(-4), z: Float(28), w: Float(12), d: Float(9), eave: Float(5.2), ridge: Float(8))
    static let pond = (x: Float(-34), z: Float(24), r: Float(9))
    static let pondWater: Float = -0.35
    static let appleTree = (x: Float(10), z: Float(17))
    static let pumpkinPatch = (x: Float(15), z: Float(29))
    static let trough = (x: Float(38), z: Float(9))
    static let tractor = (x: Float(-7), z: Float(3))
    static let half: Float = 236

    static func inRun(_ p: V3) -> Bool { p.x > coopRun.minX && p.x < coopRun.maxX && p.z > coopRun.minZ && p.z < coopRun.maxZ }
    static func inPasture(_ p: V3) -> Bool { p.x > pasture.minX && p.x < pasture.maxX && p.z > pasture.minZ && p.z < pasture.maxZ }

    /// Distance to the dirt tracks that link the yard to everything.
    static func pathDist(_ x: Float, _ z: Float) -> Float {
        func seg(_ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Float {
            let p = SIMD2(x, z), ab = b - a
            let t = clampf(simd_dot(p - a, ab) / simd_dot(ab, ab), 0, 1)
            return simd_length(p - (a + ab * t))
        }
        var d = seg(SIMD2(-2, 2), SIMD2(-4, 22))                 // yard → porch
        d = min(d, seg(SIMD2(-2, 2), SIMD2(33, 3.5)))            // yard → pasture gate
        d = min(d, seg(SIMD2(33, 3.5), SIMD2(60, 3.5)) + 0.6)    // cow track into the pasture
        d = min(d, seg(SIMD2(4, -3), SIMD2(16, -8)))             // yard → coop gate
        d = min(d, seg(SIMD2(-2, 2), SIMD2(-11, -12)))           // yard → barn door
        d = min(d, seg(SIMD2(-4, 22), SIMD2(-4, 60)) + 0.5)      // lane out to the road
        return d
    }

    static func yardDist(_ x: Float, _ z: Float) -> Float { simd_length(SIMD2(x + 3, z + 3) * SIMD2(1, 1.3)) }

    /// Terrain height. Flat around the buildings, rolling beyond.
    static func height(_ x: Float, _ z: Float) -> Float {
        let far = smoothstep(40, 95, simd_length(SIMD2(x - 10, z - 5)))
        var h = Noise.fbm(x * 0.011, z * 0.011, octaves: 4, seed: 3) * 9 * far
        h += Noise.fbm(x * 0.06, z * 0.06, octaves: 3, seed: 4) * 0.25 * (0.3 + far)
        // the pasture dips gently toward the pond side
        if inPasture(V3(x, 0, z)) { h += Noise.fbm(x * 0.03, z * 0.03, octaves: 2, seed: 9) * 0.6 }
        let pd = simd_length(SIMD2(x - pond.x, z - pond.z))
        h -= 1.5 * smoothstep(pond.r + 2.5, 1, pd)
        return h
    }

    static func groundColor(_ x: Float, _ z: Float) -> V3 {
        let n1 = Noise.fbm(x * 0.05, z * 0.05, octaves: 4, seed: 21)
        let n2 = Noise.fbm(x * 0.4, z * 0.4, octaves: 3, seed: 22)
        let dry = smoothstep(0.0, 0.5, Noise.fbm(x * 0.02, z * 0.02, octaves: 3, seed: 23))
        var c = mix3(V3(0.13, 0.24, 0.05), V3(0.22, 0.29, 0.08), n1 * 0.5 + 0.5)
        c = mix3(c, V3(0.32, 0.31, 0.13), dry * 0.45)
        c *= 0.92 + n2 * 0.12
        if inPasture(V3(x, 0, z)) { c = mix3(c, V3(0.14, 0.27, 0.06), 0.35) }
        // tracks: two wheel ruts with grass down the middle
        let pd = pathDist(x, z)
        let dirt = V3(0.36, 0.28, 0.19) * (0.85 + n2 * 0.2)
        let rut = smoothstep(1.6, 1.1, pd) * (1 - smoothstep(0.35, 0.15, pd) * 0.6)
        c = mix3(c, dirt, rut * (0.8 + n2 * 0.2))
        // gravel yard
        let yd = yardDist(x, z)
        let gravel = V3(0.42, 0.39, 0.34) * (0.8 + Noise.cell(Int(x * 12), Int(z * 12), 3) * 0.3)
        c = mix3(c, gravel, smoothstep(11 + n1 * 3, 8 + n1 * 3, yd))
        // bare, pecked earth in the coop run
        if inRun(V3(x, 0, z)) { c = mix3(c, V3(0.3, 0.24, 0.16) * (0.85 + n2 * 0.25), 0.75 + n2 * 0.2) }
        // mud at the pasture gate and around the trough
        let mud = max(smoothstep(4, 1.5, simd_length(SIMD2(x - 33, z - 3.5))), smoothstep(4.5, 2, simd_length(SIMD2(x - trough.x, z - trough.z))))
        c = mix3(c, V3(0.2, 0.15, 0.1), mud * 0.85)
        // pond shore
        let pd2 = simd_length(SIMD2(x - pond.x, z - pond.z))
        c = mix3(c, V3(0.24, 0.2, 0.13), smoothstep(pond.r + 1.5, pond.r - 1, pd2))
        // under the house and barn: packed dirt
        return c
    }

    static func isGrass(_ x: Float, _ z: Float) -> Bool {
        pathDist(x, z) > 1.8 && yardDist(x, z) > 11 && !inRun(V3(x, 0, z)) && simd_length(SIMD2(x - pond.x, z - pond.z)) > pond.r + 1.5
    }
}

final class World {
    let root = SCNNode()
    var solids: [Solid] = []
    var ladders: [Ladder] = []
    var water: SCNNode!
    var cornPiles: [(pos: V3, node: SCNNode, left: Int)] = []
    private let static_ = SCNNode()
    let grassRoot = SCNNode()
    let knockRoot = SCNNode()
    var knockables: [Knockable] = []
    var terrainNode: SCNNode!

    let mapIndex: Int
    let map: MapDef
    var isFarm: Bool { mapIndex == 0 }

    init(map index: Int = 0) {
        mapIndex = index
        map = Maps.all[index]
        root.add(static_)
        buildTerrain()
        if index != 0 {
            MapBuilder.build(self)
            buildWater()
            buildGrass()
            buildHills()
            addEdges()
            finishPhysics()
            return
        }
        buildBarn()
        buildSilo()
        buildHayStairs()
        buildCoop()
        buildPasture()
        buildHouse()
        buildPond()
        buildTractor()
        buildTrees()
        buildMisc()
        buildGrass()
        buildHills()
        addEdges()
        finishPhysics()
    }

    private func finishPhysics() {
        root.addChildNode(knockRoot)
        buildPhysics(terrainNode)
        buildKnockables()
    }

    private func addEdges() {
        // invisible boundary
        let H = Farm.half
        for (cx, cz, w, l) in [(Float(0), -H - 1, 2 * H + 4, Float(2)), (0, H + 1, 2 * H + 4, 2), (-H - 1, 0, 2, 2 * H + 4), (H + 1, 0, 2, 2 * H + 4)] {
            var s = Solid.box(cx, cz, w, l, 60, base: -20, tag: "edge")
            s.walkable = false
            solids.append(s)
        }
    }

    // MARK: queries

    func terrain(_ x: Float, _ z: Float) -> Float { isFarm ? Farm.height(x, z) : map.height(x, z) }
    func groundColor(_ x: Float, _ z: Float) -> V3 { isFarm ? Farm.groundColor(x, z) : map.color(x, z) }
    func isGrass(_ x: Float, _ z: Float) -> Bool {
        if isFarm { return Farm.isGrass(x, z) }
        if let w = map.waterLevel, terrain(x, z) < w + 0.1 { return false }
        return map.grass(x, z)
    }
    /// Water surface height here, if (x, z) is under water.
    func waterLevel(_ x: Float, _ z: Float) -> Float? {
        if isFarm {
            return simd_length(SIMD2(x - Farm.pond.x, z - Farm.pond.z)) < Farm.pond.r + 1 && Farm.height(x, z) < Farm.pondWater ? Farm.pondWater : nil
        }
        if let w = map.waterLevel, terrain(x, z) < w { return w }
        return nil
    }

    /// Highest standing surface under (x, z) that's no more than `step` above `y`.
    func ground(_ x: Float, _ z: Float, y: Float, r: Float, step: Float = 0.5) -> (Float, Surface, String) {
        var g = terrain(x, z)
        var surf: Surface = isFarm ? (Farm.isGrass(x, z) ? .grass : .dirt) : (isGrass(x, z) ? .grass : map.surface(x, z) == .grass ? .dirt : map.surface(x, z))
        var tag = ""
        if waterLevel(x, z) != nil { surf = .water }
        for s in solids where s.walkable {
            let m = s.yaw != 0 ? max(s.maxX - s.minX, s.maxZ - s.minZ) * 0.5 : 0
            guard x > s.minX - r - m && x < s.maxX + r + m && z > s.minZ - r - m && z < s.maxZ + r + m else { continue }
            let (d, _) = s.edge(x, z)
            guard d < r * 0.4 else { continue }
            let t = s.top(clampf(x, s.minX, s.maxX), clampf(z, s.minZ, s.maxZ))
            if t <= y + step && t > g { g = t; surf = s.surface; tag = s.tag }
        }
        return (g, surf, tag)
    }

    /// Pushes a cylinder (feet at p.y, height h) out of every solid it is inside of.
    func collide(_ p: inout V3, r: Float, h: Float, step: Float = 0.5) -> Bool {
        var hit = false
        for s in solids {
            let m = s.yaw != 0 ? max(s.maxX - s.minX, s.maxZ - s.minZ) * 0.5 : 0
            guard p.x > s.minX - r - m && p.x < s.maxX + r + m && p.z > s.minZ - r - m && p.z < s.maxZ + r + m else { continue }
            let (d, n) = s.edge(p.x, p.z)
            guard d < r else { continue }
            let t = s.top(clampf(p.x, s.minX, s.maxX), clampf(p.z, s.minZ, s.maxZ))
            if p.y >= t - (s.walkable ? step : 0) { continue }
            if p.y + h < s.bottom { continue }
            let push = r - d
            p.x += n.x * push; p.z += n.y * push
            hit = true
        }
        return hit
    }

    func ladder(near p: V3, r: Float) -> Ladder? {
        for l in ladders where simd_length(SIMD2(p.x - l.x, p.z - l.z)) < r + 0.45 && p.y < l.top + 0.3 { return l }
        return nil
    }

    // MARK: geometry helpers

    /// A box whose UVs are in metres × `uv`, so tiled materials keep their real-world scale.
    static func meterBox(_ w: Float, _ h: Float, _ l: Float, _ m: SCNMaterial, uv: Float = 0.25) -> SCNNode {
        var P: [V3] = [], N: [V3] = [], U: [SIMD2<Float>] = [], I: [UInt32] = []
        let hx = w / 2, hy = h / 2, hz = l / 2
        func face(_ o: V3, _ a: V3, _ b: V3, _ n: V3, _ la: Float, _ lb: Float) {
            let i = UInt32(P.count)
            P += [o - a - b, o + a - b, o + a + b, o - a + b]
            N += [n, n, n, n]
            U += [SIMD2(0, lb * uv), SIMD2(la * uv, lb * uv), SIMD2(la * uv, 0), SIMD2(0, 0)]
            I += [i, i + 1, i + 2, i, i + 2, i + 3]
        }
        face(V3(0, 0, hz), V3(hx, 0, 0), V3(0, hy, 0), V3(0, 0, 1), w, h)
        face(V3(0, 0, -hz), V3(-hx, 0, 0), V3(0, hy, 0), V3(0, 0, -1), w, h)
        face(V3(hx, 0, 0), V3(0, 0, -hz), V3(0, hy, 0), V3(1, 0, 0), l, h)
        face(V3(-hx, 0, 0), V3(0, 0, hz), V3(0, hy, 0), V3(-1, 0, 0), l, h)
        face(V3(0, hy, 0), V3(hx, 0, 0), V3(0, 0, -hz), V3(0, 1, 0), w, l)
        face(V3(0, -hy, 0), V3(hx, 0, 0), V3(0, 0, hz), V3(0, -1, 0), w, l)
        let g = meshGeometry(P, N, U, I)
        g.materials = [m]
        return SCNNode(geometry: g)
    }

    /// A flat convex polygon (fan) with metric UVs.
    static func poly(_ pts: [V3], _ m: SCNMaterial, uv: Float = 0.25) -> SCNNode {
        let n = simd_normalize(simd_cross(pts[1] - pts[0], pts[2] - pts[0]))
        let ax = simd_normalize(pts[1] - pts[0]), ay = simd_cross(n, ax)
        let P = pts, N = [V3](repeating: n, count: pts.count)
        let U = pts.map { SIMD2(simd_dot($0 - pts[0], ax) * uv, -simd_dot($0 - pts[0], ay) * uv) }
        var I: [UInt32] = []
        for k in 1..<(pts.count - 1) { I += [0, UInt32(k), UInt32(k + 1)] }
        let g = meshGeometry(P, N, U, I)
        g.materials = [m]
        return SCNNode(geometry: g)
    }

    func add(_ n: SCNNode) { static_.addChildNode(n) }

    // MARK: terrain

    private func buildTerrain() {
        let H = Farm.half + 4
        let N = 320
        let step = 2 * H / Float(N)
        var P: [V3] = [], Nn: [V3] = [], U: [SIMD2<Float>] = [], I: [UInt32] = []
        for j in 0...N {
            for i in 0...N {
                let x = -H + Float(i) * step, z = -H + Float(j) * step
                P.append(V3(x, terrain(x, z), z))
                let e: Float = 0.5
                let dx = terrain(x + e, z) - terrain(x - e, z), dz = terrain(x, z + e) - terrain(x, z - e)
                Nn.append(simd_normalize(V3(-dx, 2 * e, -dz)))
                U.append(SIMD2((x + H) / (2 * H), (z + H) / (2 * H)))
            }
        }
        for j in 0..<N {
            for i in 0..<N {
                let a = UInt32(j * (N + 1) + i), b = a + 1, c = a + UInt32(N + 1), d = c + 1
                I += [a, c, b, b, c, d]
            }
        }
        let g = meshGeometry(P, Nn, U, I)
        let W = 3072
        let img = makePixelImage(W, W) { px, py in
            let x = -H + (Float(px) + 0.5) / Float(W) * 2 * H, z = -H + (Float(py) + 0.5) / Float(W) * 2 * H
            let c = groundColor(x, z)
            return SIMD4(c.x, c.y, c.z, 1)
        }
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = img
        m.diffuse.mipFilter = .linear
        m.diffuse.maxAnisotropy = 8
        let det = Mat.grassDetail
        m.multiply.contents = det.diffuse.contents
        m.normal.contents = det.normal.contents
        let rep = 2 * H / 3
        for p in [m.multiply, m.normal] {
            p.contentsTransform = SCNMatrix4MakeScale(CGFloat(rep), CGFloat(rep), 1)
            p.wrapS = .repeat; p.wrapT = .repeat; p.mipFilter = .linear; p.maxAnisotropy = 8
        }
        m.normal.intensity = 0.8
        m.roughness.contents = map.groundRough
        if mapIndex == 2 { m.multiply.intensity = 0.35 }
        g.materials = [m]
        let t = SCNNode(geometry: g)
        t.castsShadow = false
        add(t)
        terrainNode = t
    }

    private func buildHills() {
        // a ring of rolling hills and forest out to the horizon
        let segs = 96, rings = 10
        var P: [V3] = [], Nn: [V3] = [], U: [SIMD2<Float>] = [], I: [UInt32] = []
        for j in 0...rings {
            let r = Farm.half * 1.15 + Float(j * j) * 14
            for i in 0...segs {
                let a = Float(i) / Float(segs) * 2 * .pi
                let x = cosf(a) * r, z = sinf(a) * r
                let rise = Float(j) / Float(rings)
                let y = Noise.fbm(x * 0.004, z * 0.004, octaves: 4, seed: 7) * (mapIndex == 7 ? 120 : 45) * rise + rise * (mapIndex == 7 ? 80 : 30) - 2 + terrain(x, z) * (1 - rise)
                P.append(V3(x, y, z)); Nn.append(V3(0, 1, 0)); U.append(SIMD2(Float(i) / 4, Float(j) / 2))
            }
        }
        for j in 0..<rings {
            for i in 0..<segs {
                let a = UInt32(j * (segs + 1) + i), b = a + 1, c = a + UInt32(segs + 1), d = c + 1
                I += [a, b, c, b, d, c]
            }
        }
        // recompute normals
        var nn = [V3](repeating: .zero, count: P.count)
        for k in stride(from: 0, to: I.count, by: 3) {
            let a = Int(I[k]), b = Int(I[k + 1]), c = Int(I[k + 2])
            let f = simd_cross(P[b] - P[a], P[c] - P[a])
            nn[a] += f; nn[b] += f; nn[c] += f
        }
        Nn = nn.map { simd_length($0) > 0 ? simd_normalize($0) * (($0.y < 0) ? -1 : 1) : V3(0, 1, 0) }
        let g = meshGeometry(P, Nn, U, I)
        let m = pbr(color(map.hills), rough: 1)
        m.multiply.contents = [2, 4].contains(mapIndex) ? Mat.dirt.diffuse.contents : Mat.leaves.diffuse.contents
        m.multiply.contentsTransform = SCNMatrix4MakeScale(6, 6, 1)
        m.multiply.wrapS = .repeat; m.multiply.wrapT = .repeat
        m.isDoubleSided = true
        g.materials = [m]
        let n = SCNNode(geometry: g)
        n.castsShadow = false
        add(n)
        // forest bumps along the first ridge
        var rr = RNG(44)
        let crown = copyMat(Mat.leaves)
        let bumps = [0, 3, 6, 9].contains(mapIndex) ? 260 : mapIndex == 1 ? 60 : mapIndex == 7 ? 120 : 0
        for _ in 0..<bumps {
            let a = rr.range(0, 2 * .pi), r = Farm.half * rr.range(1.02, 1.35)
            let x = cosf(a) * r, z = sinf(a) * r
            let s = rr.range(3, 6)
            let fm = mapIndex == 2 || mapIndex == 7 ? Foliage.pineMat : Foliage.leafMat(V3(0.06, 0.16, 0.04), V3(0.2, 0.34, 0.08), seed: 3)
            let t = Foliage.crown(center: V3(x, terrain(x, z) + s * 1.1, z), radii: V3(s, s * rr.range(1.1, 1.5), s), cards: 45, size: s * 0.9, seed: rr.next(), fm)
            t.castsShadow = false
            add(t)
        }
    }

    // MARK: buildings

    private func buildBarn() {
        let b = Farm.barn
        let n = SCNNode(); n.simdPosition = V3(b.x, 0, b.z)
        add(n)
        let hl = b.len / 2, hw = b.wid / 2
        let red = copyMat(Mat.barnRed)
        // long walls
        for sz in [Float(1), -1] {
            n.add(World.meterBox(b.len, b.eave, 0.2, red).at(0, b.eave / 2, sz * hw))
        }
        // gable ends with a door
        for sx in [Float(1), -1] {
            let x = sx * hl
            n.add(World.meterBox(0.2, b.eave, b.wid, red).at(x, b.eave / 2, 0))
            let tri = [V3(x + sx * 0.11, b.eave, sx > 0 ? -hw : hw), V3(x + sx * 0.11, b.eave, sx > 0 ? hw : -hw), V3(x + sx * 0.11, b.ridge, 0)]
            n.add(World.poly(tri, red))
            // trim: corner boards and an X-braced sliding door
            for zz in [-hw, hw] { n.add(boxNode(0.25, CGFloat(b.eave), 0.25, Mat.whiteTrim).at(x, b.eave / 2, zz)) }
            if sx > 0 {
                n.add(boxNode(0.05, 4.2, 4.4, Mat.doorDark).at(x + 0.12, 2.1, 0))
                for dz in [Float(-1.1), 1.1] {
                    let d = SCNNode(); d.simdPosition = V3(x + 0.16, 2.1, dz)
                    n.add(d)
                    d.add(World.meterBox(0.06, 4.1, 2.15, red))
                    for (h, yy) in [(Float(0.18), Float(2.0)), (0.18, -2.0), (0.18, 0)] { d.add(boxNode(0.08, CGFloat(h), 2.2, Mat.whiteTrim).at(0.02, yy, 0)) }
                    for zz in [Float(-1.05), 1.05] { d.add(boxNode(0.08, 4.1, 0.18, Mat.whiteTrim).at(0.02, 0, zz)) }
                    for s in [Float(1), -1] { d.add(boxNode(0.07, 4.4, 0.16, Mat.whiteTrim).at(0.03, 0, 0).rot(s * 0.48, 0, 0)) }
                }
                n.add(boxNode(0.15, 0.12, 5.2, Mat.galv).at(x + 0.2, 4.3, 0))
                // hay loft door, open, bales peeking out
                n.add(boxNode(0.05, 1.8, 1.8, Mat.doorDark).at(x + 0.13, 7.6, 0))
                n.add(boxNode(0.12, 0.15, 2.1, Mat.whiteTrim).at(x + 0.16, 8.5, 0))
                n.add(boxNode(0.12, 0.15, 2.1, Mat.whiteTrim).at(x + 0.16, 6.7, 0))
                n.add(World.meterBox(0.6, 0.6, 1.4, Mat.hay, uv: 1).at(x - 0.1, 7.0, 0))
                n.add(boxNode(0.4, 0.3, 0.3, Mat.galv).at(x + 0.6, 9.3, 0))
            }
        }
        // roof: corrugated metal, two slopes with overhang
        let slopeLen = sqrtf(hw * hw + (b.ridge - b.eave) * (b.ridge - b.eave)) + 0.7
        let ang = atan2f(b.ridge - b.eave, hw)
        let roof = copyMat(Mat.roofMetal)
        for sz in [Float(1), -1] {
            let r = World.meterBox(b.len + 1.0, 0.08, slopeLen, roof, uv: 0.33)
            r.simdPosition = V3(0, (b.eave + b.ridge) / 2 + 0.06 - 0.22, sz * (hw / 2 + 0.3))
            r.simdEulerAngles = V3(sz * ang, 0, 0)
            n.add(r)
        }
        n.add(cylNode(0.08, CGFloat(b.len + 1), Mat.galv).rot(0, 0, Float.pi / 2).at(0, b.ridge + 0.02, 0))
        // weathervane rooster on the ridge
        let vane = SCNNode(); vane.simdPosition = V3(hl - 2, b.ridge, 0)
        n.add(vane)
        vane.add(cylNode(0.03, 1.4, Mat.black).at(0, 0.7, 0))
        vane.add(boxNode(0.5, 0.35, 0.02, Mat.black).at(0, 1.45, 0))
        vane.add(boxNode(0.9, 0.02, 0.02, Mat.black).at(0, 1.1, 0))
        vane.add(boxNode(0.02, 0.02, 0.9, Mat.black).at(0, 1.1, 0))
        // foundation
        n.add(World.meterBox(b.len + 0.3, 0.5, b.wid + 0.3, Mat.concrete).at(0, 0.1, 0))
        let e = b.eave, rg = b.ridge
        let roofTop: (Float, Float) -> Float = { _, z in e - 0.3 + (rg - e + 0.2) * max(0, 1 - abs(z - b.z) / (hw + 0.7)) }
        solids.append(Solid(minX: b.x - hl - 0.12, maxX: b.x + hl + 0.12, minZ: b.z - hw - 0.12, maxZ: b.z + hw + 0.12, bottom: -1, top: roofTop, tag: "barnRoof", surface: .metal))
        solids.append(Solid(minX: b.x - hl - 0.5, maxX: b.x + hl + 0.5, minZ: b.z - hw - 0.7, maxZ: b.z + hw + 0.7, bottom: e - 0.5, top: roofTop, tag: "barnRoof", surface: .metal))
    }

    private func buildSilo() {
        let s = Farm.silo
        let n = SCNNode(); n.simdPosition = V3(s.x, 0, s.z)
        add(n)
        let body = SCNCylinder(radius: CGFloat(s.r), height: CGFloat(s.h))
        body.radialSegmentCount = 48
        let m = copyMat(Mat.concrete)
        tiled(m, 5, 4)
        body.materials = [m]
        n.add(SCNNode(geometry: body).at(0, s.h / 2, 0))
        for k in 0..<14 {
            let t = SCNTorus(ringRadius: CGFloat(s.r + 0.02), pipeRadius: 0.03)
            t.ringSegmentCount = 48; t.pipeSegmentCount = 6; t.materials = [Mat.galv]
            n.add(SCNNode(geometry: t).at(0, 0.8 + Float(k) * 1.02, 0))
        }
        // flat cap with a railing
        n.add(cylNode(CGFloat(s.r + 0.15), 0.2, Mat.concrete, seg: 48).at(0, s.h + 0.1, 0))
        n.add(coneNode(CGFloat(s.r * 0.35), 0.25, 0.7, Mat.galv, seg: 24).at(0, s.h + 0.55, 0))
        for k in 0..<16 {
            let a = Float(k) / 16 * 2 * .pi
            n.add(cylNode(0.025, 1.0, Mat.galv, seg: 6).at(cosf(a) * (s.r - 0.05), s.h + 0.7, sinf(a) * (s.r - 0.05)))
        }
        let rail = SCNTorus(ringRadius: CGFloat(s.r - 0.05), pipeRadius: 0.03)
        rail.ringSegmentCount = 48; rail.materials = [Mat.galv]
        n.add(SCNNode(geometry: rail).at(0, s.h + 1.2, 0))
        // ladder up the side facing the yard (+x), with a gap in the railing
        let lx = s.r + 0.25
        for dz in [Float(-0.25), 0.25] { n.add(cylNode(0.025, CGFloat(s.h + 1.2), Mat.galv, seg: 8).at(lx, (s.h + 1.2) / 2, dz)) }
        for k in 0..<Int(s.h / 0.3) { n.add(cylNode(0.018, 0.5, Mat.galv, seg: 6).rot(Float.pi / 2, 0, 0).at(lx, 0.3 + Float(k) * 0.3, 0)) }
        for k in 0..<10 {
            let hoop = SCNTorus(ringRadius: 0.38, pipeRadius: 0.02)
            hoop.materials = [Mat.galv]
            n.add(SCNNode(geometry: hoop).at(lx + 0.2, 3 + Float(k) * 1.3, 0).rot(0, 0, 0).scl(1, 1, 1))
        }
        solids.append(.cyl(s.x, s.z, s.r + 0.15, s.h + 0.2, tag: "silo", surface: .concrete))
        ladders.append(Ladder(x: s.x + lx + 0.25, z: s.z, top: s.h + 0.2, outward: SIMD2(1, 0), topStep: SIMD2(s.x + s.r - 0.9, s.z)))
    }

    private func buildHayStairs() {
        // big square bales stacked into a staircase up to the barn eave
        let b = Farm.barn
        let z0 = b.z + b.wid / 2 + 0.7 + 0.75
        for i in 0..<7 {
            let x = b.x - 6 + Float(i) * 1.3
            let h = Float(i + 1) * 0.9
            for k in 0...i {
                let bale = World.meterBox(1.25, 0.88, 1.5, Mat.hay, uv: 0.8)
                bale.simdPosition = V3(x, Float(k) * 0.9 + 0.44, z0)
                bale.simdEulerAngles = V3(0, Float(k % 2) * 0.03 - 0.015, 0)
                add(bale)
                for dz in [Float(-0.4), 0.4] { add(boxNode(1.27, 0.01, 0.02, pbr(color(0.1, 0.25, 0.6), rough: 0.6)).at(x, Float(k) * 0.9 + 0.885, z0 + dz)) }
            }
            solids.append(.box(x, z0, 1.3, 1.5, h, tag: "hay", surface: .hay))
        }
        // loose round bales out in the field
        var rr = RNG(9)
        for (x, z) in [(Float(-30), Float(4)), (-26, 8), (-38, -2), (8, -30), (14, -34)] {
            let a = rr.range(0, 3)
            let c = cylNode(0.8, 1.2, Mat.hay, seg: 28).rot(0, a, Float.pi / 2).at(x, Farm.height(x, z) + 0.8, z)
            add(c)
            solids.append(.cyl(x, z, 0.85, 1.6, base: Farm.height(x, z), tag: "roundbale", surface: .hay))
        }
    }

    private func buildCoop() {
        let r = Farm.coopRun
        let wire = copyMat(Mat.wire)
        // posts and wire around the run, gate gap on the yard side (-z edge)
        func fenceLine(_ a: SIMD2<Float>, _ b: SIMD2<Float>) {
            let d = b - a, len = simd_length(d)
            let n = Int(ceilf(len / 2.4))
            for k in 0...n {
                let p = a + d * (Float(k) / Float(n))
                add(World.meterBox(0.1, 1.4, 0.1, Mat.woodGrey, uv: 1).at(p.x, Farm.height(p.x, p.y) + 0.6, p.y))
            }
            let mid = (a + b) / 2
            let plane = SCNPlane(width: CGFloat(len), height: 1.2)
            let w = copyMat(wire)
            w.diffuse.contentsTransform = SCNMatrix4MakeScale(CGFloat(len / 0.4), 3, 1)
            plane.materials = [w]
            let pn = SCNNode(geometry: plane)
            pn.simdPosition = V3(mid.x, Farm.height(mid.x, mid.y) + 0.6, mid.y)
            pn.simdEulerAngles = V3(0, -atan2f(d.y, d.x), 0)
            pn.castsShadow = false
            add(pn)
            add(World.meterBox(len, 0.06, 0.06, Mat.woodGrey, uv: 1).at(mid.x, Farm.height(mid.x, mid.y) + 1.25, mid.y).rot(0, -atan2f(d.y, d.x), 0))
            var s = Solid.box(mid.x, mid.y, abs(d.x) + 0.12, abs(d.y) + 0.12, 1.25, tag: "fence", surface: .wood)
            s.walkable = false
            solids.append(s)
        }
        fenceLine(SIMD2(r.minX, r.minZ), SIMD2(r.maxX, r.minZ))
        fenceLine(SIMD2(r.maxX, r.minZ), SIMD2(r.maxX, r.maxZ))
        fenceLine(SIMD2(r.minX, r.minZ), SIMD2(r.minX, r.maxZ))
        fenceLine(SIMD2(r.minX, r.maxZ), SIMD2(Farm.coopGate.x0, r.maxZ))
        fenceLine(SIMD2(Farm.coopGate.x1, r.maxZ), SIMD2(r.maxX, r.maxZ))
        // an open gate swung inward
        let gate = SCNNode(); gate.simdPosition = V3(Farm.coopGate.x1, 0.65, r.maxZ)
        add(gate)
        gate.simdEulerAngles = V3(0, 1.9, 0)
        gate.add(World.meterBox(2.4, 0.06, 0.06, Mat.woodGrey).at(1.2, 0.55, 0))
        gate.add(World.meterBox(2.4, 0.06, 0.06, Mat.woodGrey).at(1.2, -0.55, 0))
        let gp = SCNPlane(width: 2.4, height: 1.1); let gw = copyMat(wire); gw.diffuse.contentsTransform = SCNMatrix4MakeScale(6, 2.75, 1); gp.materials = [gw]
        gate.add(SCNNode(geometry: gp).at(1.2, 0, 0))
        // the henhouse on legs, with a ramp
        let c = Farm.coopHouse
        let h = SCNNode(); h.simdPosition = V3(c.x, 0, c.z)
        add(h)
        let wood = copyMat(Mat.siding(V3(0.72, 0.62, 0.45), seed: 301))
        for (x, z) in [(Float(-1.4), Float(-1.1)), (1.4, -1.1), (-1.4, 1.1), (1.4, 1.1)] { h.add(World.meterBox(0.12, 0.6, 0.12, Mat.woodGrey, uv: 1).at(x, 0.3, z)) }
        h.add(World.meterBox(3.0, 1.8, 2.4, wood).at(0, 1.5, 0))
        h.add(World.poly([V3(-1.5, 2.4, 1.21), V3(1.5, 2.4, 1.21), V3(0, 3.1, 1.21)], wood))
        h.add(World.poly([V3(1.5, 2.4, -1.21), V3(-1.5, 2.4, -1.21), V3(0, 3.1, -1.21)], wood))
        let rl = sqrtf(1.5 * 1.5 + 0.7 * 0.7) + 0.3
        for s in [Float(1), -1] {
            h.add(World.meterBox(rl, 0.05, 2.8, Mat.roofMetal, uv: 0.33).at(s * 0.78, 2.78, 0).rot(0, 0, -s * atan2f(0.7, 1.5)))
        }
        // pop door and ramp on the yard side
        h.add(boxNode(0.5, 0.6, 0.04, Mat.doorDark).at(0.6, 0.95, 1.22))
        h.add(boxNode(0.7, 0.05, 1.8, Mat.woodGrey).at(0.6, 0.35, 1.95).rot(0.35, 0, 0))
        for k in 0..<5 { h.add(boxNode(0.7, 0.03, 0.03, Mat.woodGrey).at(0.6, 0.18 + Float(k) * 0.12, 2.6 - Float(k) * 0.3).rot(0.35, 0, 0)) }
        // nest boxes bumped out on the side
        h.add(World.meterBox(0.6, 0.6, 1.8, wood).at(-1.8, 1.1, 0))
        h.add(boxNode(0.8, 0.04, 2.0, Mat.roofMetal).at(-1.85, 1.45, 0).rot(0, 0, 0.35))
        // a wired window
        h.add(boxNode(0.03, 0.5, 0.7, Mat.doorDark).at(1.51, 1.8, 0))
        solids.append(.box(c.x - 0.25, c.z, 3.6, 2.5, 3.0, tag: "coop", surface: .metal))
        // corn scattered on the ground
        var rr = RNG(55)
        for (x, z) in [(Float(14), Float(-11)), (19, -12), (15.5, -17)] {
            let pile = SCNNode(); pile.simdPosition = V3(x, Farm.height(x, z), z)
            add(pile)
            let corn = pbr(color(0.95, 0.72, 0.15), rough: 0.5)
            for _ in 0..<40 {
                let a = rr.range(0, 6.28), d = powf(rr.float(), 0.7) * 0.45
                pile.add(sphereNode(0.012, corn, seg: 6).scl(1, 0.7, 1.3).at(cosf(a) * d, 0.008, sinf(a) * d).rot(0, a, 0))
            }
            cornPiles.append((pile.simdPosition, pile, 20))
        }
        // feeder and a water fount
        add(cylNode(0.2, 0.5, Mat.galv, seg: 20).at(18, Farm.height(18, -14) + 0.25, -14))
        add(coneNode(0.3, 0.05, 0.25, Mat.galv, seg: 20).at(18, Farm.height(18, -14) + 0.6, -14))
        add(cylNode(0.35, 0.05, Mat.galv, seg: 24).at(18, Farm.height(18, -14) + 0.03, -14))
    }

    private func buildPasture() {
        let p = Farm.pasture
        let postM = copyMat(Mat.woodGrey)
        func rail(_ a: SIMD2<Float>, _ b: SIMD2<Float>) {
            let d = b - a, len = simd_length(d)
            guard len > 0.1 else { return }
            let n = Int(ceilf(len / 3))
            let ang = -atan2f(d.y, d.x)
            for k in 0...n {
                let q = a + d * (Float(k) / Float(n))
                let y = Farm.height(q.x, q.y)
                add(World.meterBox(0.14, 1.55, 0.14, postM, uv: 1).at(q.x, y + 0.72, q.y).rot(0, Float(k) * 0.4, 0))
            }
            for k in 0..<n {
                let q0 = a + d * (Float(k) / Float(n)), q1 = a + d * (Float(k + 1) / Float(n))
                let mid = (q0 + q1) / 2
                let y0 = Farm.height(q0.x, q0.y), y1 = Farm.height(q1.x, q1.y)
                let seglen = simd_length(q1 - q0)
                let tilt = atan2f(y1 - y0, seglen)
                for hgt in [Float(0.45), 0.85, 1.25] {
                    let r = World.meterBox(seglen + 0.1, 0.12, 0.05, postM, uv: 0.5)
                    r.simdPosition = V3(mid.x, (y0 + y1) / 2 + hgt, mid.y)
                    r.simdEulerAngles = V3(0, ang, tilt)
                    add(r)
                }
            }
            var s = Solid.box((a.x + b.x) / 2, (a.y + b.y) / 2, abs(d.x) + 0.16, abs(d.y) + 0.16, 1.35, base: -2, tag: "fence")
            s.walkable = false
            solids.append(s)
        }
        rail(SIMD2(p.minX, p.minZ), SIMD2(p.maxX, p.minZ))
        rail(SIMD2(p.maxX, p.minZ), SIMD2(p.maxX, p.maxZ))
        rail(SIMD2(p.minX, p.maxZ), SIMD2(p.maxX, p.maxZ))
        rail(SIMD2(p.minX, p.minZ), SIMD2(p.minX, Farm.pastureGate.z0))
        rail(SIMD2(p.minX, Farm.pastureGate.z1), SIMD2(p.minX, p.maxZ))
        // trough
        let t = Farm.trough
        let ty = Farm.height(t.x, t.z)
        let tn = SCNNode(); tn.simdPosition = V3(t.x, ty, t.z)
        add(tn)
        tn.add(boxNode(0.9, 0.04, 2.5, Mat.galv).at(0, 0.12, 0))
        for sx in [Float(1), -1] { tn.add(boxNode(0.03, 0.55, 2.5, Mat.galv).at(sx * 0.45, 0.38, 0)) }
        for sz in [Float(1), -1] { tn.add(boxNode(0.93, 0.55, 0.03, Mat.galv).at(0, 0.38, sz * 1.25)) }
        for sx in [Float(1), -1] { tn.add(cylNode(0.02, 2.52, Mat.galv, seg: 8).rot(Float.pi / 2, 0, 0).at(sx * 0.46, 0.66, 0)) }
        for (x, z) in [(Float(0.38), Float(1.1)), (-0.38, 1.1), (0.38, -1.1), (-0.38, -1.1)] { tn.add(boxNode(0.06, 0.12, 0.06, Mat.woodGrey).at(x, 0.06, z)) }
        let wtr = SCNPlane(width: 0.86, height: 2.46)
        wtr.materials = [Mat.water]
        tn.add(SCNNode(geometry: wtr).rot(-Float.pi / 2, 0, 0).at(0, 0.55, 0))
        solids.append(.box(t.x, t.z, 0.95, 2.6, 0.7, base: ty, tag: "trough", surface: .metal))
        // a salt lick and a lone shade tree in the pasture
        add(boxNode(0.25, 0.2, 0.25, pbr(color(0.75, 0.7, 0.68), rough: 0.6)).at(44, Farm.height(44, 14) + 0.1, 14))
    }

    private func buildHouse() {
        let h = Farm.house
        let n = SCNNode(); n.simdPosition = V3(h.x, 0, h.z)
        add(n)
        let hw = h.w / 2, hd = h.d / 2
        let wall = copyMat(Mat.clapboard)
        n.add(World.meterBox(h.w, h.eave, h.d, wall).at(0, h.eave / 2 + 0.4, 0))
        n.add(World.meterBox(h.w + 0.3, 0.5, h.d + 0.3, Mat.concrete).at(0, 0.2, 0))
        for sx in [Float(1), -1] {
            let x = sx * (hw + 0.005)
            n.add(World.poly([V3(x, h.eave + 0.4, sx > 0 ? hd : -hd), V3(x, h.eave + 0.4, sx > 0 ? -hd : hd), V3(x, h.ridge + 0.4, 0)], wall))
        }
        let slope = sqrtf(hd * hd + (h.ridge - h.eave) * (h.ridge - h.eave)) + 0.8
        let ang = atan2f(h.ridge - h.eave, hd)
        for sz in [Float(1), -1] {
            n.add(World.meterBox(h.w + 1.0, 0.14, slope, Mat.shingles, uv: 0.5).at(0, (h.eave + h.ridge) / 2 + 0.4 - 0.25, sz * (hd / 2 + 0.35)).rot(sz * ang, 0, 0))
        }
        // chimney
        n.add(World.meterBox(0.9, 3.2, 0.9, Mat.siding(V3(0.45, 0.2, 0.15), seed: 401, horizontal: true), uv: 0.6).at(-hw + 1.8, h.ridge + 0.2, 1.0))
        // windows and door on the porch side (-z)
        func window(_ x: Float, _ y: Float, _ z: Float, facingZ: Float) {
            let w = SCNNode(); w.simdPosition = V3(x, y, z)
            w.simdEulerAngles = V3(0, facingZ > 0 ? 0 : .pi, 0)
            n.add(w)
            w.add(boxNode(1.0, 1.4, 0.04, Mat.glass).at(0, 0, 0.02))
            for (bw, bh, bx, by) in [(Float(1.2), Float(0.1), Float(0), Float(0.75)), (1.2, 0.1, 0, -0.75), (0.1, 1.5, 0.6, 0), (0.1, 1.5, -0.6, 0), (1.0, 0.05, 0, 0), (0.05, 1.4, 0, 0)] {
                w.add(boxNode(CGFloat(bw), CGFloat(bh), 0.07, Mat.whiteTrim).at(bx, by, 0.05))
            }
            w.add(boxNode(0.4, 1.5, 0.04, pbr(color(0.12, 0.2, 0.14), rough: 0.6)).at(0.85, 0, 0.03))
            w.add(boxNode(0.4, 1.5, 0.04, pbr(color(0.12, 0.2, 0.14), rough: 0.6)).at(-0.85, 0, 0.03))
        }
        for x in [Float(-3.8), 3.8] { window(x, 2.6, -hd, facingZ: -1); window(x, 2.6, hd, facingZ: 1) }
        window(0, 2.6, hd, facingZ: 1)
        n.add(boxNode(1.1, 2.2, 0.06, pbr(color(0.35, 0.12, 0.08), rough: 0.5)).at(0, 1.5, -hd - 0.02))
        n.add(cylNode(0.035, 0.05, Mat.galv, seg: 8).rot(Float.pi / 2, 0, 0).at(0.4, 1.5, -hd - 0.07))
        // porch
        let pd: Float = 2.6
        n.add(World.meterBox(h.w - 1, 0.18, pd, Mat.woodFresh, uv: 0.8).at(0, 0.5, -hd - pd / 2))
        for x in stride(from: -hw + 0.7, through: hw - 0.7, by: (h.w - 1.4) / 4) { n.add(boxNode(0.16, 2.5, 0.16, Mat.whiteTrim).at(x, 1.8, -hd - pd + 0.15)) }
        n.add(World.meterBox(h.w - 0.6, 0.1, pd + 0.4, Mat.shingles, uv: 0.5).at(0, 3.15, -hd - pd / 2).rot(-0.18, 0, 0))
        for k in 0..<3 { n.add(World.meterBox(1.6, 0.16, 0.35, Mat.woodFresh).at(0, 0.08 + Float(k) * 0.16, -hd - pd - 0.9 + Float(k) * 0.3)) }
        for x in stride(from: -hw + 0.8, through: hw - 0.8, by: 0.25) where abs(x) > 1.0 {
            n.add(boxNode(0.04, 0.8, 0.04, Mat.whiteTrim).at(x, 1.0, -hd - pd + 0.15))
        }
        n.add(boxNode(CGFloat(h.w - 1.4), 0.07, 0.08, Mat.whiteTrim).at(0, 1.42, -hd - pd + 0.15))
        // rocking chair
        let chair = SCNNode(); chair.simdPosition = V3(3, 0.6, -hd - 1.1); chair.simdEulerAngles = V3(0, 2.8, 0)
        n.add(chair)
        chair.add(boxNode(0.5, 0.05, 0.5, Mat.woodFresh).at(0, 0.4, 0))
        chair.add(boxNode(0.5, 0.7, 0.05, Mat.woodFresh).at(0, 0.8, -0.24))
        for s in [Float(1), -1] { chair.add(boxNode(0.04, 0.05, 0.8, Mat.woodFresh).at(s * 0.23, 0.02, 0)) }
        let e = h.eave + 0.4, rg = h.ridge + 0.4
        let houseTop: (Float, Float) -> Float = { _, z in e - 0.3 + (rg - e) * max(0, 1 - abs(z - h.z) / (hd + 0.6)) }
        solids.append(Solid(minX: h.x - hw - 0.08, maxX: h.x + hw + 0.08, minZ: h.z - hd - 0.08, maxZ: h.z + hd + 0.08, bottom: -1, top: houseTop, tag: "houseRoof", surface: .wood))
        solids.append(Solid(minX: h.x - hw - 0.5, maxX: h.x + hw + 0.5, minZ: h.z - hd - 0.6, maxZ: h.z + hd + 0.6, bottom: e - 0.4, top: houseTop, tag: "houseRoof", surface: .wood))
        solids.append(.box(h.x, h.z - hd - pd / 2, h.w - 1, pd, 0.6, tag: "porch", surface: .wood))
        solids.append(.box(h.x, h.z - hd - pd - 0.6, 1.6, 0.6, 0.3, tag: "steps", surface: .wood))
    }

    private func buildWater() {
        guard let lvl = map.waterLevel else { return }
        let plane = SCNPlane(width: 260, height: 260)
        let m = copyMat(Mat.water)
        m.diffuse.contents = color(map.waterCol)
        if mapIndex == 2 { m.transparency = 0.9 }
        plane.materials = [m]
        water = SCNNode(geometry: plane)
        water.simdEulerAngles = V3(-.pi / 2, 0, 0)
        water.simdPosition = V3(0, lvl, 0)
        water.castsShadow = false
        add(water)
    }

    private func buildPond() {
        let p = Farm.pond
        let disc = SCNCylinder(radius: CGFloat(p.r + 1.2), height: 0.02)
        disc.radialSegmentCount = 64
        disc.materials = [Mat.water]
        water = SCNNode(geometry: disc)
        water.simdPosition = V3(p.x, Farm.pondWater, p.z)
        water.castsShadow = false
        add(water)
        // reeds and cattails round the edge
        var rr = RNG(66)
        let reed = pbr(color(0.3, 0.38, 0.12), rough: 0.7)
        let cat = pbr(color(0.3, 0.18, 0.08), rough: 0.9)
        for _ in 0..<70 {
            let a = rr.range(0, 6.28), d = p.r + rr.range(-1.2, 0.8)
            let x = p.x + cosf(a) * d, z = p.z + sinf(a) * d
            let hgt = rr.range(0.7, 1.5)
            let r = cylNode(0.01, CGFloat(hgt), reed, seg: 5)
            r.simdPosition = V3(x, Farm.height(x, z) + hgt / 2, z)
            r.simdEulerAngles = V3(rr.range(-0.15, 0.15), 0, rr.range(-0.15, 0.15))
            add(r)
            if rr.chance(0.4) { r.add(cylNode(0.025, 0.18, cat, seg: 8).at(0, hgt / 2 - 0.1, 0)) }
        }
        // a small dock
        let dx = p.x + p.r - 1.5, dz = p.z - 2
        add(World.meterBox(3.5, 0.12, 1.4, Mat.woodGrey, uv: 1).at(dx - 1, 0.25, dz))
        for (ox, oz) in [(Float(-2.5), Float(-0.6)), (-2.5, 0.6), (0.5, -0.6), (0.5, 0.6)] { add(cylNode(0.07, 1.4, Mat.woodGrey, seg: 8).at(dx + ox, -0.4, dz + oz)) }
        solids.append(.box(dx - 1, dz, 3.5, 1.4, 0.31, base: -1.5, tag: "dock", surface: .wood))
    }

    private func buildTractor() {
        let t = Farm.tractor
        let n = SCNNode(); n.simdPosition = V3(t.x, Farm.height(t.x, t.z), t.z)
        n.simdEulerAngles = V3(0, 0.5, 0)
        add(n)
        // body
        n.add(boxNode(0.9, 0.7, 2.2, Mat.tractorGreen, chamfer: 0.08).at(0, 1.05, 0.5))
        n.add(boxNode(0.8, 0.5, 1.4, Mat.tractorGreen, chamfer: 0.12).at(0, 1.55, 0.85))
        n.add(boxNode(0.82, 0.3, 0.05, Mat.galv).at(0, 1.2, 1.62))
        for k in 0..<5 { n.add(boxNode(0.7, 0.02, 0.02, Mat.black).at(0, 1.08 + Float(k) * 0.05, 1.64)) }
        n.add(cylNode(0.05, 1.0, Mat.black, seg: 10).at(0.25, 2.1, 1.2))
        n.add(boxNode(1.6, 0.1, 1.2, Mat.tractorGreen).at(0, 1.5, -0.7))
        // seat and wheel
        n.add(boxNode(0.5, 0.1, 0.45, Mat.black, chamfer: 0.04).at(0, 1.75, -0.7))
        n.add(boxNode(0.5, 0.5, 0.08, Mat.black, chamfer: 0.04).at(0, 2.0, -0.95))
        n.add(cylNode(0.02, 0.6, Mat.black).at(0, 1.9, -0.25).rot(-0.6, 0, 0))
        let sw = SCNTorus(ringRadius: 0.18, pipeRadius: 0.02); sw.materials = [Mat.black]
        n.add(SCNNode(geometry: sw).at(0, 2.18, -0.1).rot(-0.9, 0, 0))
        // roll bar
        for s in [Float(1), -1] { n.add(cylNode(0.04, 1.6, Mat.black, seg: 10).at(s * 0.7, 2.3, -1.15)) }
        n.add(cylNode(0.04, 1.4, Mat.black, seg: 10).rot(0, 0, Float.pi / 2).at(0, 3.1, -1.15))
        // wheels
        func wheel(_ x: Float, _ y: Float, _ z: Float, _ r: Float, _ w: Float) {
            let tire = SCNTube(innerRadius: CGFloat(r * 0.6), outerRadius: CGFloat(r), height: CGFloat(w))
            tire.radialSegmentCount = 36
            tire.materials = [Mat.rubber]
            let wn = SCNNode(geometry: tire).rot(0, 0, Float.pi / 2).at(x, y, z)
            n.add(wn)
            wn.add(cylNode(CGFloat(r * 0.62), CGFloat(w * 0.7), Mat.tractorYellow, seg: 24))
            for k in 0..<20 {
                let a = Float(k) / 20 * 2 * .pi
                wn.add(boxNode(0.07, CGFloat(w * 0.9), CGFloat(r * 0.22), Mat.rubber).at(cosf(a) * r, 0, sinf(a) * r).rot(0, -a, 0))
            }
        }
        for s in [Float(1), -1] {
            wheel(s * 0.95, 0.8, -0.7, 0.8, 0.45)
            wheel(s * 0.62, 0.45, 1.3, 0.45, 0.25)
        }
        // the tractor is turned 0.5 rad: a rotated box hugging the body and the big wheels
        let tc = SIMD2(t.x, t.z) + SIMD2(sinf(0.5), cosf(0.5)) * 0.3
        var ts = Solid(minX: tc.x - 1.25, maxX: tc.x + 1.25, minZ: tc.y - 1.75, maxZ: tc.y + 1.75, bottom: -1, top: { _, _ in Farm.height(t.x, t.z) + 1.6 }, tag: "tractor", surface: .metal)
        ts.yaw = 0.5
        solids.append(ts)
    }

    private func buildTrees() {
        var rr = RNG(77)
        func tree(_ x: Float, _ z: Float, _ s: Float, apples: Bool = false) {
            let y = Farm.height(x, z)
            let n = SCNNode(); n.simdPosition = V3(x, y, z)
            n.simdEulerAngles = V3(0, rr.range(0, 6), 0)
            add(n)
            let th = 2.2 * s
            n.add(loftNode([Ring(V3(0, -0.2, 0), 0.3 * s, 0.28 * s), Ring(V3(0, 0.2, 0), 0.22 * s, 0.2 * s), Ring(V3(0.05, th * 0.6, 0.03), 0.16 * s, 0.15 * s),
                            Ring(V3(0.1, th, 0.05), 0.12 * s, 0.11 * s), Ring(V3(0.1, th + 0.8 * s, 0.05), 0.06 * s, 0.06 * s)], Mat.bark, seg: 14, smooth: 3))
            // branches
            for k in 0..<4 {
                let a = Float(k) * 1.6 + rr.range(0, 0.5)
                n.add(limb(1.4 * s, 0.07 * s, 0.03 * s, Mat.bark, seg: 8, dir: V3(cosf(a), 0.9, sinf(a))).at(0.1, th * 0.8, 0.05))
            }
            let lm = Foliage.leafMat(V3(0.06, 0.16, 0.04), V3(0.2, 0.34, 0.08), seed: 3)
            for k in 0..<3 {
                let a = Float(k) * 2.1 + rr.range(0, 0.6), d = rr.range(0.5, 1.2) * s
                let cc = V3(cosf(a) * d, th + 1.4 * s + rr.range(-0.2, 0.9) * s, sinf(a) * d)
                let rad = V3(1.9, 1.5, 1.9) * s * rr.range(0.85, 1.15)
                n.add(Foliage.crown(center: cc, radii: rad, cards: 150, size: 1.1 * s, seed: rr.next(), lm))
                if apples {
                    for _ in 0..<14 {
                        let b = rr.range(0, 6.28), e = rr.range(-0.6, 0.5)
                        n.add(sphereNode(0.045, Mat.apple, seg: 8).at(cc.x + cosf(b) * cosf(e) * rad.x * 0.8, cc.y + sinf(e) * rad.y * 0.8, cc.z + sinf(b) * cosf(e) * rad.z * 0.8))
                    }
                }
            }
            solids.append(.cyl(x, z, 0.35 * s, th + 3 * s, base: y, tag: "tree", surface: .wood))
        }
        tree(Farm.appleTree.x, Farm.appleTree.z, 1.1, apples: true)
        tree(-18, 34, 1.5); tree(8, 38, 1.3); tree(-26, 14, 1.2); tree(52, 20, 1.6); tree(28, -30, 1.2); tree(-45, -20, 1.4)
        tree(-12, 44, 1.2); tree(-30, 40, 1.4)
        var placed = 0
        while placed < 260 {
            let x = rr.range(-Farm.half + 5, Farm.half - 5), z = rr.range(-Farm.half + 5, Farm.half - 5)
            let r = simd_length(SIMD2(x, z))
            guard r > 60 else { continue }
            if Farm.inPasture(V3(x, 0, z)) || Farm.pathDist(x, z) < 4 { continue }
            tree(x, z, rr.range(1.1, 1.8))
            placed += 1
        }
    }

    private func buildMisc() {
        // pumpkin patch vines, a mailbox by the lane, a well, bales of straw by the barn
        let pp = Farm.pumpkinPatch
        let vine = pbr(color(0.15, 0.3, 0.07), rough: 0.7)
        var rr = RNG(88)
        for _ in 0..<60 {
            let x = pp.x + rr.range(-5, 5), z = pp.z + rr.range(-3.5, 3.5)
            let l = sphereNode(CGFloat(rr.range(0.15, 0.3)), vine, seg: 8).scl(1, 0.25, 1).at(x, Farm.height(x, z) + 0.05, z)
            add(l)
        }
        add(World.meterBox(10.5, 0.02, 7.5, Mat.dirt, uv: 0.5).at(pp.x, Farm.height(pp.x, pp.z) + 0.005, pp.z))
        // mailbox
        add(boxNode(0.1, 1.1, 0.1, Mat.woodGrey).at(-6, Farm.height(-6, 45) + 0.55, 45))
        add(cylNode(0.12, 0.45, Mat.galv, seg: 16).rot(Float.pi / 2, 0, 0).at(-6, Farm.height(-6, 45) + 1.15, 45))
        // stone well near the house
        let wx: Float = 8, wz: Float = 26
        let wy = Farm.height(wx, wz)
        let stone = copyMat(Mat.concrete)
        let ring = SCNTube(innerRadius: 0.55, outerRadius: 0.75, height: 0.8)
        ring.radialSegmentCount = 24; ring.materials = [stone]
        add(SCNNode(geometry: ring).at(wx, wy + 0.4, wz))
        add(cylNode(0.56, 0.02, Mat.water, seg: 24).at(wx, wy + 0.5, wz))
        for s in [Float(1), -1] { add(boxNode(0.1, 1.6, 0.1, Mat.woodGrey).at(wx + s * 0.65, wy + 1.1, wz)) }
        add(boxNode(1.6, 0.08, 1.2, Mat.shingles).at(wx, wy + 2.0, wz).rot(0, 0, 0))
        add(cylNode(0.05, 1.3, Mat.woodGrey).rot(0, 0, Float.pi / 2).at(wx, wy + 1.4, wz))
        solids.append(.cyl(wx, wz, 0.78, 0.8, base: wy, tag: "well", surface: .concrete))
        // woodpile against the barn
        for k in 0..<18 {
            let x = -11 + Float(k % 6) * 0.3 - 0.8, y = Float(k / 6) * 0.26 + 0.13
            add(cylNode(0.13, 1.0, Mat.woodFresh, seg: 10).rot(Float.pi / 2, 0, 0).at(x - 12, y, -4.9))
        }
    }

    // MARK: grass

    private func buildGrass() {
        var rr = RNG(99)
        let chunk: Float = 24
        var buckets: [Int: ([V3], [V3], [SIMD2<Float>], [UInt32])] = [:]
        var flowers: ([V3], [V3], [SIMD2<Float>], [UInt32]) = ([], [], [], [])
        let lim: Float = Farm.half * 0.85
        var count = 0
        let target = isFarm ? 80000 : map.grassCount * 2
        var tries = 0
        while count < target && tries < target * 12 {
            tries += 1
            let x = rr.range(-lim, lim), z = rr.range(-lim, lim)
            guard isGrass(x, z) else { continue }
            // denser near the middle of the farm, thin at the edges
            let r = simd_length(SIMD2(x, z))
            if r > 70 && rr.float() > 70 / r * 0.85 { continue }
            if solids.contains(where: { $0.tag != "fence" && $0.tag != "edge" && x > $0.minX - 0.3 && x < $0.maxX + 0.3 && z > $0.minZ - 0.3 && z < $0.maxZ + 0.3 }) { continue }
            let y = terrain(x, z)
            let key = Int(floorf((x + lim) / chunk)) * 100 + Int(floorf((z + lim) / chunk))
            var b = buckets[key] ?? ([], [], [], [])
            let hgt = rr.range(0.16, 0.42) * (isFarm && Farm.inPasture(V3(x, 0, z)) ? 0.8 : mapIndex == 1 ? 1.8 : mapIndex == 3 ? 1.6 : 1)
            let w = rr.range(0.3, 0.55)
            let a0 = rr.range(0, .pi)
            for k in 0..<2 {
                let a = a0 + Float(k) * .pi / 2
                let d = V3(cosf(a), 0, sinf(a)) * (w / 2)
                let i = UInt32(b.0.count)
                let lean = V3(rr.range(-0.06, 0.06), 0, rr.range(-0.06, 0.06))
                b.0 += [V3(x, y - 0.02, z) - d, V3(x, y - 0.02, z) + d, V3(x, y + hgt, z) + d + lean, V3(x, y + hgt, z) - d + lean]
                b.1 += [V3(0, 1, 0), V3(0, 1, 0), V3(0, 1, 0), V3(0, 1, 0)]
                b.2 += [SIMD2(0, 1), SIMD2(1, 1), SIMD2(1, 0), SIMD2(0, 0)]
                b.3 += [i, i + 1, i + 2, i, i + 2, i + 3]
            }
            buckets[key] = b
            if rr.chance(0.04) {
                let fy = y + hgt * rr.range(0.5, 0.9), s: Float = 0.05
                let i = UInt32(flowers.0.count)
                flowers.0 += [V3(x - s, fy, z - s), V3(x + s, fy, z - s), V3(x + s, fy, z + s), V3(x - s, fy, z + s)]
                flowers.1 += [V3(0, 1, 0), V3(0, 1, 0), V3(0, 1, 0), V3(0, 1, 0)]
                flowers.2 += [SIMD2(0, 0), SIMD2(1, 0), SIMD2(1, 1), SIMD2(0, 1)]
                flowers.3 += [i, i + 1, i + 2, i, i + 2, i + 3]
            }
            count += 1
        }
        for (_, b) in buckets {
            let g = meshGeometry(b.0, b.1, b.2, b.3)
            g.materials = [isFarm ? Mat.grassBlade : Mat.grassBlade(map.grassLow, map.grassHigh)]
            let n = SCNNode(geometry: g)
            n.castsShadow = false
            grassRoot.addChildNode(n)
        }
        root.addChildNode(grassRoot)
        if !flowers.0.isEmpty {
            let g = meshGeometry(flowers.0, flowers.1, flowers.2, flowers.3)
            g.materials = [Mat.flower]
            let n = SCNNode(geometry: g)
            n.castsShadow = false
            add(n)
        }
    }
}
