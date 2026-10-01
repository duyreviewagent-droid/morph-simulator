import SceneKit
import simd

/// Loose physics junk to knock over, Goat Simulator style.
final class Knockable {
    let node: SCNNode
    let kind: String
    let points: Int
    let explosive: Bool
    let home: simd_float4x4
    let group: String
    var knocked = false
    var knockedAt: Float = 0
    var fuse: Float = -1
    var exploded = false
    init(_ n: SCNNode, kind: String, points: Int, explosive: Bool = false, group: String = "") {
        node = n; self.kind = kind; self.points = points; self.explosive = explosive; self.group = group
        home = n.simdWorldTransform
    }
    var pos: V3 { let t = node.presentation.simdWorldTransform.columns.3; return V3(t.x, t.y, t.z) }
    var up: V3 { let c = node.presentation.simdWorldTransform.columns.1; return simd_normalize(V3(c.x, c.y, c.z)) }
}

enum KnockKit {
    static let orange = Coats.coat(.bands, V3(0.95, 0.4, 0.05), V3(0.95, 0.95, 0.93))
    static let redBarrel = Coats.coat(.bands, V3(0.75, 0.08, 0.05), V3(0.95, 0.8, 0.1))
    static let woodBarrel = Coats.coat(.bands, V3(0.45, 0.28, 0.14), V3(0.3, 0.3, 0.3))
    static let pin = Coats.coat(.bands, V3(0.95, 0.95, 0.93), V3(0.85, 0.08, 0.08))
    static let clay = Coats.coat(.skin, V3(0.7, 0.4, 0.22), V3(0.55, 0.3, 0.15))
    static let melon = Coats.coat(.stripes, V3(0.2, 0.45, 0.12), V3(0.1, 0.25, 0.05))
    static let can = Coats.coat(.bands, V3(0.85, 0.1, 0.1), V3(0.9, 0.9, 0.9))

    static func body(_ n: SCNNode, _ shape: SCNPhysicsShape, mass: CGFloat, bounce: CGFloat = 0.2, friction: CGFloat = 0.7) {
        let b = SCNPhysicsBody(type: .dynamic, shape: shape)
        b.mass = mass
        b.restitution = bounce
        b.friction = friction
        b.rollingFriction = 0.05
        b.angularDamping = 0.2
        b.damping = 0.05
        b.allowsResting = true
        b.categoryBitMask = 8
        b.collisionBitMask = 1 | 2 | 4 | 8
        b.contactTestBitMask = 0
        n.physicsBody = b
    }

    /// Builds one knockable of a kind, standing with its base at the origin.
    static func make(_ kind: String) -> (SCNNode, Int, Bool) {
        let n = SCNNode()
        let geo = SCNNode()
        n.addChildNode(geo)
        var pts = 10, boom = false
        switch kind {
        case "crate":
            let b = World.meterBox(0.8, 0.8, 0.8, Mat.woodFresh, uv: 1.2)
            b.addChildNode(boxNode(0.82, 0.08, 0.82, Mat.woodGrey).at(0, 0.36, 0)); b.addChildNode(boxNode(0.82, 0.08, 0.82, Mat.woodGrey).at(0, -0.36, 0))
            geo.addChildNode(b)
            body(n, SCNPhysicsShape(geometry: SCNBox(width: 0.8, height: 0.8, length: 0.8, chamferRadius: 0), options: nil), mass: 18)
            pts = 15
        case "barrel", "boom":
            boom = kind == "boom"
            geo.addChildNode(cylNode(0.3, 0.9, boom ? redBarrel : woodBarrel, seg: 18))
            for y in [Float(-0.3), 0.3] { geo.addChildNode(cylNode(0.305, 0.05, Mat.galv, seg: 18).at(0, y, 0)) }
            body(n, SCNPhysicsShape(geometry: SCNCylinder(radius: 0.3, height: 0.9), options: nil), mass: boom ? 20 : 28)
            pts = boom ? 50 : 20
        case "cone":
            geo.addChildNode(coneNode(0.17, 0.02, 0.5, orange, seg: 14))
            geo.addChildNode(boxNode(0.4, 0.03, 0.4, Coats.plain(V3(0.1, 0.1, 0.1))).at(0, -0.24, 0))
            body(n, SCNPhysicsShape(geometry: SCNCone(topRadius: 0.02, bottomRadius: 0.2, height: 0.5), options: nil), mass: 2)
            pts = 5
        case "trash":
            geo.addChildNode(cylNode(0.28, 0.8, Mat.galv, seg: 18))
            geo.addChildNode(cylNode(0.3, 0.05, Mat.galv, seg: 18).at(0, 0.42, 0))
            body(n, SCNPhysicsShape(geometry: SCNCylinder(radius: 0.28, height: 0.85), options: nil), mass: 8, bounce: 0.3)
            pts = 10
        case "hay":
            geo.addChildNode(World.meterBox(0.9, 0.45, 0.5, Mat.hay, uv: 1))
            body(n, SCNPhysicsShape(geometry: SCNBox(width: 0.9, height: 0.45, length: 0.5, chamferRadius: 0), options: nil), mass: 14)
            pts = 10
        case "snowman":
            let snow = MapBuilder.snow
            geo.addChildNode(sphereNode(0.45, snow, seg: 16).at(0, -0.35, 0))
            geo.addChildNode(sphereNode(0.33, snow, seg: 16).at(0, 0.3, 0))
            geo.addChildNode(sphereNode(0.23, snow, seg: 16).at(0, 0.78, 0))
            geo.addChildNode(coneNode(0.04, 0.002, 0.2, Coats.plain(V3(0.95, 0.45, 0.05)), seg: 8).rot(Float.pi / 2, 0, 0).at(0, 0.78, 0.28))
            for sx in [Float(-1), 1] {
                geo.addChildNode(sphereNode(0.03, Mat.black, seg: 6).at(sx * 0.08, 0.86, 0.2))
                geo.addChildNode(limb(0.45, 0.015, 0.01, Mat.bark, seg: 5, dir: V3(sx, 0.4, 0)).at(sx * 0.28, 0.35, 0))
            }
            geo.addChildNode(cylNode(0.16, 0.25, Mat.black, seg: 14).at(0, 1.05, 0))
            let shape = SCNPhysicsShape(shapes: [SCNPhysicsShape(geometry: SCNSphere(radius: 0.45), options: nil), SCNPhysicsShape(geometry: SCNSphere(radius: 0.33), options: nil), SCNPhysicsShape(geometry: SCNSphere(radius: 0.23), options: nil)],
                                        transforms: [NSValue(scnMatrix4: SCNMatrix4MakeTranslation(0, -0.35, 0)), NSValue(scnMatrix4: SCNMatrix4MakeTranslation(0, 0.3, 0)), NSValue(scnMatrix4: SCNMatrix4MakeTranslation(0, 0.78, 0))])
            body(n, shape, mass: 30)
            pts = 25
        case "gnome":
            geo.addChildNode(coneNode(0.14, 0.1, 0.3, Coats.plain(V3(0.2, 0.35, 0.8)), seg: 12).at(0, -0.05, 0))
            geo.addChildNode(sphereNode(0.1, Mat.skin, seg: 12).at(0, 0.17, 0))
            geo.addChildNode(coneNode(0.1, 0.005, 0.25, Coats.plain(V3(0.85, 0.1, 0.1)), seg: 12).at(0, 0.36, 0))
            geo.addChildNode(sphereNode(0.08, Coats.plain(V3(0.95, 0.95, 0.95)), seg: 10).scl(1, 1.3, 0.6).at(0, 0.1, 0.07))
            body(n, SCNPhysicsShape(geometry: SCNCylinder(radius: 0.13, height: 0.6), options: nil), mass: 3)
            pts = 15
        case "beachball":
            geo.addChildNode(sphereNode(0.35, Coats.coat(.bands, V3(0.95, 0.2, 0.2), V3(0.2, 0.5, 0.95)), seg: 18))
            body(n, SCNPhysicsShape(geometry: SCNSphere(radius: 0.35), options: nil), mass: 0.4, bounce: 0.85, friction: 0.4)
            pts = 5
        case "tire":
            let t = SCNTorus(ringRadius: 0.32, pipeRadius: 0.12); t.materials = [Mat.rubber]
            geo.addChildNode(SCNNode(geometry: t))
            body(n, SCNPhysicsShape(geometry: SCNCylinder(radius: 0.44, height: 0.24), options: nil), mass: 9, bounce: 0.5)
            pts = 10
        case "pin":
            geo.addChildNode(loftNode([Ring(V3(0, -0.3, 0), 0.05, 0.05), Ring(V3(0, -0.2, 0), 0.075, 0.075), Ring(V3(0, 0.02, 0), 0.04, 0.04), Ring(V3(0, 0.18, 0), 0.05, 0.05), Ring(V3(0, 0.3, 0), 0.01, 0.01)],
                                      pin, seg: 14, smooth: 3))
            body(n, SCNPhysicsShape(geometry: SCNCylinder(radius: 0.06, height: 0.6), options: nil), mass: 1.5, bounce: 0.3)
            pts = 20
        case "domino":
            geo.addChildNode(boxNode(0.5, 1.0, 0.1, Coats.plain(V3(0.08, 0.08, 0.08), rough: 0.3), chamfer: 0.02))
            for k in 0..<3 { geo.addChildNode(sphereNode(0.04, Coats.plain(V3(0.95, 0.95, 0.95)), seg: 6).scl(1, 1, 0.2).at(Float(k - 1) * 0.12, Float(k - 1) * 0.2, 0.05)) }
            body(n, SCNPhysicsShape(geometry: SCNBox(width: 0.5, height: 1.0, length: 0.1, chamferRadius: 0), options: nil), mass: 3, friction: 0.5)
            pts = 5
        case "can":
            geo.addChildNode(cylNode(0.06, 0.16, can, seg: 12))
            body(n, SCNPhysicsShape(geometry: SCNCylinder(radius: 0.06, height: 0.16), options: nil), mass: 0.3, bounce: 0.3)
            pts = 3
        case "vase":
            geo.addChildNode(loftNode([Ring(V3(0, -0.3, 0), 0.12, 0.12), Ring(V3(0, -0.1, 0), 0.22, 0.22), Ring(V3(0, 0.15, 0), 0.14, 0.14), Ring(V3(0, 0.28, 0), 0.08, 0.08), Ring(V3(0, 0.32, 0), 0.1, 0.1)], clay, seg: 16, smooth: 3))
            body(n, SCNPhysicsShape(geometry: SCNCylinder(radius: 0.18, height: 0.62), options: nil), mass: 4)
            pts = 15
        case "melon":
            geo.addChildNode(sphereNode(0.22, melon, seg: 16).scl(1, 0.85, 1.25))
            body(n, SCNPhysicsShape(geometry: SCNSphere(radius: 0.21), options: nil), mass: 5, bounce: 0.2)
            pts = 10
        case "barrier":
            geo.addChildNode(boxNode(1.4, 0.3, 0.06, orange).at(0, 0.3, 0))
            for sx in [Float(-0.6), 0.6] { geo.addChildNode(boxNode(0.06, 1.0, 0.4, Coats.plain(V3(0.9, 0.9, 0.9))).at(sx, 0, 0)) }
            body(n, SCNPhysicsShape(geometry: SCNBox(width: 1.4, height: 1.0, length: 0.4, chamferRadius: 0), options: nil), mass: 10)
            pts = 10
        default:
            geo.addChildNode(boxNode(0.5, 0.5, 0.5, Mat.woodFresh))
            body(n, SCNPhysicsShape(geometry: SCNBox(width: 0.5, height: 0.5, length: 0.5, chamferRadius: 0), options: nil), mass: 10)
        }
        n.castAll(true)
        return (n, pts, boom)
    }

    /// Half-height of each kind (its base sits on the ground).
    static func half(_ kind: String) -> Float {
        switch kind {
        case "crate": return 0.4
        case "barrel", "boom": return 0.45
        case "cone": return 0.25
        case "trash": return 0.43
        case "hay": return 0.225
        case "snowman": return 0.8
        case "gnome": return 0.25
        case "beachball": return 0.35
        case "tire": return 0.12
        case "pin": return 0.3
        case "domino": return 0.5
        case "can": return 0.08
        case "vase": return 0.31
        case "melon": return 0.19
        case "barrier": return 0.5
        default: return 0.25
        }
    }
}

extension World {
    func placeKnock(_ kind: String, _ x: Float, _ z: Float, y: Float? = nil, yaw: Float = 0, group: String = "") {
        let (n, pts, boom) = KnockKit.make(kind)
        let gy = y ?? ground(x, z, y: 100, r: 0.2).0
        n.simdPosition = V3(x, gy + KnockKit.half(kind) + 0.01, z)
        n.simdEulerAngles = V3(0, yaw, 0)
        knockRoot.addChildNode(n)
        knockables.append(Knockable(n, kind: kind, points: pts, explosive: boom, group: group))
    }

    func crateStack(_ x: Float, _ z: Float, yaw: Float) {
        let dir = V3(cosf(yaw), 0, -sinf(yaw))
        for row in 0..<3 { for k in 0..<(3 - row) {
            let off = (Float(k) - Float(2 - row) / 2) * 0.82
            let gy = terrain(x, z)
            placeKnock("crate", x + dir.x * off, z + dir.z * off, y: gy + Float(row) * 0.81, yaw: yaw, group: "stack")
        } }
    }
    func canPyramid(_ x: Float, _ z: Float, base: Float) {
        for row in 0..<4 { for k in 0..<(4 - row) {
            placeKnock("can", x + (Float(k) - Float(3 - row) / 2) * 0.13, z, y: base + Float(row) * 0.165, group: "cans")
        } }
    }
    func bowling(_ x: Float, _ z: Float) {
        var k = 0
        for row in 0..<4 { for j in 0...row {
            placeKnock("pin", x + (Float(j) - Float(row) / 2) * 0.32, z + Float(row) * 0.3, group: "bowling")
            k += 1
        } }
    }
    func dominoes(_ x: Float, _ z: Float, count: Int, yaw: Float) {
        for k in 0..<count {
            let a = yaw + Float(k) * 0.05
            let p = V3(x, 0, z) + V3(sinf(a), 0, cosf(a)) * Float(k) * 0.55 + V3(cosf(a), 0, -sinf(a)) * sinf(Float(k) * 0.25) * 1.5
            placeKnock("domino", p.x, p.z, yaw: a, group: "dominoes")
        }
    }
    func tireStack(_ x: Float, _ z: Float) {
        let gy = terrain(x, z)
        for k in 0..<5 { placeKnock("tire", x, z, y: gy + Float(k) * 0.24, group: "tires") }
    }

    /// Static physics for the ground, buildings and walls so junk can land on things.
    func buildPhysics(_ terrain: SCNNode) {
        let tb = SCNPhysicsBody(type: .static, shape: SCNPhysicsShape(geometry: terrain.geometry!, options: [.type: SCNPhysicsShape.ShapeType.concavePolyhedron, .keepAsCompound: true]))
        tb.categoryBitMask = 1; tb.collisionBitMask = -1; tb.friction = 0.8
        terrain.physicsBody = tb
        for s in solids {
            let n = SCNNode()
            let top = s.top((s.minX + s.maxX) / 2, s.maxZ)
            let base = max(s.bottom, -20)
            let h = max(0.1, top - base)
            if let r = s.round {
                n.physicsBody = SCNPhysicsBody(type: .static, shape: SCNPhysicsShape(geometry: SCNCylinder(radius: CGFloat(r.r), height: CGFloat(h)), options: nil))
                n.simdPosition = V3(r.cx, base + h / 2, r.cz)
            } else {
                n.physicsBody = SCNPhysicsBody(type: .static, shape: SCNPhysicsShape(geometry: SCNBox(width: CGFloat(s.maxX - s.minX), height: CGFloat(h), length: CGFloat(s.maxZ - s.minZ), chamferRadius: 0), options: nil))
                n.simdPosition = V3((s.minX + s.maxX) / 2, base + h / 2, (s.minZ + s.maxZ) / 2)
            }
            n.physicsBody?.categoryBitMask = 1
            n.physicsBody?.collisionBitMask = -1
            knockRoot.addChildNode(n)
        }
        if let lvl = map.waterLevel ?? (isFarm ? nil : nil) { _ = lvl }
    }

    /// Scatters junk and set pieces around the current map.
    func buildKnockables() {
        var rr = RNG(UInt64(mapIndex * 97 + 5))
        let sets: [[String]] = [
            ["crate", "barrel", "hay", "hay", "gnome", "melon", "barrel"],        // farm
            ["crate", "barrel", "tire", "crate", "cone"],                        // savanna
            ["snowman", "snowman", "crate", "barrel", "snowman"],                // arctic
            ["crate", "vase", "barrel", "melon", "vase"],                        // jungle
            ["vase", "vase", "crate", "tire", "barrel"],                         // desert
            ["beachball", "beachball", "cone", "crate", "melon", "barrel"],      // beach
            ["crate", "barrel", "gnome", "hay"],                                 // forest
            ["crate", "barrel", "cone", "tire"],                                 // mountains
            ["barrel", "crate", "barrel"],                                       // swamp
            ["trash", "cone", "barrier", "gnome", "beachball", "trash"],         // park
        ]
        let kinds = sets[mapIndex]
        let spawn = isFarm ? V3(2, 0, 7) : map.spawn
        var placed = 0, tries = 0
        let target = isFarm ? 90 : 80
        while placed < target && tries < target * 20 {
            tries += 1
            let a = rr.range(0, 2 * .pi), d = rr.range(5, Farm.half * 0.55)
            let x = spawn.x + cosf(a) * d, z = spawn.z + sinf(a) * d
            guard abs(x) < Farm.half - 10, abs(z) < Farm.half - 10, waterLevel(x, z) == nil else { continue }
            if collideTest(x, z, 0.6) { continue }
            placeKnock(kinds[rr.int(kinds.count)], x, z, yaw: rr.range(0, 6.28))
            placed += 1
        }
        // explosive barrels, set pieces
        func spot(_ r0: Float, _ r1: Float) -> (Float, Float)? {
            for _ in 0..<40 {
                let a = rr.range(0, 2 * .pi), d = rr.range(r0, r1)
                let x = spawn.x + cosf(a) * d, z = spawn.z + sinf(a) * d
                if abs(x) < Farm.half - 10 && abs(z) < Farm.half - 10 && waterLevel(x, z) == nil && !collideTest(x, z, 2.5) { return (x, z) }
            }
            return nil
        }
        for _ in 0..<(isFarm ? 6 : 8) { if let (x, z) = spot(10, Farm.half * 0.5) { placeKnock("boom", x, z) } }
        for _ in 0..<4 { if let (x, z) = spot(8, 60) { crateStack(x, z, yaw: rr.range(0, 3)) } }
        if let (x, z) = spot(8, 20) { bowling(x, z) }
        if let (x, z) = spot(12, 40) { dominoes(x, z, count: 24, yaw: rr.range(0, 6.28)) }
        for _ in 0..<2 { if let (x, z) = spot(10, 50) { tireStack(x, z) } }
        if isFarm {
            // tin cans lined up on the porch rail and a pyramid on the well
            canPyramid(Farm.house.x + 2, Farm.house.z - Farm.house.d / 2 - 1.5, base: 0.68)
            for k in 0..<6 { placeKnock("gnome", Farm.house.x - 5 + Float(k) * 2, Farm.house.z - Farm.house.d / 2 - 4.6) }
            crateStack(-9, -3.5, yaw: 0.2)
            for k in 0..<4 { placeKnock("boom", -12 + Float(k) * 0.7, -4.2) }
        }
    }

    private func collideTest(_ x: Float, _ z: Float, _ r: Float) -> Bool {
        solids.contains { s in s.tag != "edge" && x > s.minX - r && x < s.maxX + r && z > s.minZ - r && z < s.maxZ + r }
    }
}
