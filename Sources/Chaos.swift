import SceneKit
import simd

extension Game {
    /// Keeps the player's invisible physics capsule in step so it shoves junk around.
    func updatePusher() {
        let r = body.radius, h = max(0.4, body.height)
        let want = V3(r, h, 0)
        if simd_length(want - pusherShape) > 0.05 {
            pusherShape = want
            let cap = SCNCapsule(capRadius: CGFloat(r * 0.9), height: CGFloat(max(h, r * 2)))
            let b = SCNPhysicsBody(type: .kinematic, shape: SCNPhysicsShape(geometry: cap, options: nil))
            b.categoryBitMask = 4
            b.collisionBitMask = 8
            pusher.physicsBody = b
        }
        pusher.simdPosition = pos + V3(0, h / 2, 0)
    }

    /// Pushes junk in a cone (or all around when dir is nil).
    func blast(from c: V3, dir: V3?, range: Float, strength: Float, cone: Float = 0.2, up: Float = 0.4) -> Bool {
        var hit = false
        for k in world.knockables where !k.exploded {
            let d = k.pos - c
            let l = simd_length(d)
            guard l < range, l > 0.01 else { continue }
            let n = d / l
            if let dir, simd_dot(simd_normalize(V3(n.x, 0, n.z)), dir) < cone { continue }
            guard let pb = k.node.physicsBody else { continue }
            let fall = 1 - l / range
            let imp = (simd_normalize(V3(n.x, 0, n.z) + V3(0, up, 0))) * strength * Float(pb.mass) * (0.4 + fall)
            pb.applyForce(SCNVector3(imp), at: SCNVector3(0, 0.25, 0), asImpulse: true)
            pb.applyTorque(SCNVector4(Float.random(in: -1...1), 1, Float.random(in: -1...1), strength * Float(pb.mass) * 0.05), asImpulse: true)
            hit = true
        }
        return hit
    }

    func updateKnockables(_ dt: Float) {
        updatePusher()
        if CommandLine.arguments.contains("--boomtest") && time > 4 && !boomTested {
            boomTested = true
            if let k = world.knockables.first(where: { $0.explosive && simd_length($0.pos - V3(-11, 0, -4)) < 4 }) { explode(k) }
        }
        let hs = playerSpeed
        let heavy = min(3, max(0.6, body.mass / 2))
        // barge into things
        for k in world.knockables where !k.exploded {
            let p = k.pos
            let d = SIMD2(p.x - pos.x, p.z - pos.z)
            let l = simd_length(d)
            let key = ObjectIdentifier(k)
            if let c = knockCool[key], c > 0 { knockCool[key] = c - dt; continue }
            guard l < body.radius + 0.55, p.y < pos.y + body.height + 0.3, p.y > pos.y - 0.8, hs > 1.2, let pb = k.node.physicsBody else { continue }
            let n = simd_normalize(V3(d.x, 0, d.y) + V3(vel.x, 0, vel.z) * 0.1)
            let imp = (n * hs * 0.9 + V3(0, hs * 0.35, 0)) * heavy * Float(pb.mass) * 0.6
            pb.applyForce(SCNVector3(imp), at: SCNVector3(0, 0.3, 0), asImpulse: true)
            knockCool[key] = 0.35
            if k.kind == "boom" && hs > 3 { k.fuse = k.fuse < 0 ? 0.3 : k.fuse }
        }
        // score what's been knocked
        chaosStreakT -= dt
        if chaosStreakT < 0 { chaosStreak = 0 }
        let t = Float(time)
        var groups: [String: (Int, Int)] = [:]
        for k in world.knockables {
            if !k.group.isEmpty { var g = groups[k.group] ?? (0, 0); g.0 += 1; if k.knocked { g.1 += 1 }; groups[k.group] = g }
            if k.exploded { continue }
            if k.fuse >= 0 {
                k.fuse -= dt
                if k.fuse < 0 { explode(k); continue }
            }
            if !k.knocked {
                let hp = V3(k.home.columns.3.x, k.home.columns.3.y, k.home.columns.3.z)
                let moved = simd_length(k.pos - hp)
                if k.up.y < 0.55 || moved > 1.2 {
                    k.knocked = true
                    k.knockedAt = t
                    chaosStreak += 1
                    chaosStreakT = 2.5
                    let mult = min(5, 1 + chaosStreak / 4)
                    let pts = k.points * mult
                    addChaos(pts, "+\(pts) \(k.kind == "boom" ? "BARREL" : k.kind.uppercased())" + (mult > 1 ? "  x\(mult)" : ""), big: mult > 2)
                    if k.explosive, let v = k.node.physicsBody?.velocity, simd_length(V3(Float(v.x), Float(v.y), Float(v.z))) > 2.5 { k.fuse = 0.4 }
                    sfx(k.kind == "trash" || k.kind == "can" ? "clang" : k.kind == "beachball" ? "kick" : k.kind == "snowman" || k.kind == "hay" ? "thud" : k.kind == "vase" ? "splat" : "bonk",
                        at: k.pos, vol: 0.6, rate: k.kind == "can" ? 1.8 : k.kind == "pin" ? 1.5 : 1)
                }
            } else if t - k.knockedAt > 50 && simd_length(k.pos - pos) > 30 {
                reset(k)
            }
        }
        if let g = groups["bowling"], g.0 >= 10, g.1 >= g.0 { complete("strike") }
        if let g = groups["dominoes"], g.0 > 5, g.1 >= g.0 - 1 { complete("dominoes") }
    }

    func addChaos(_ n: Int, _ label: String, big: Bool) {
        if !label.hasPrefix("KABOOM") { stat("Things knocked over") }
    }

    func reset(_ k: Knockable) {
        if k.exploded { world.knockRoot.addChildNode(k.node); k.exploded = false }
        k.node.physicsBody?.velocity = SCNVector3Zero
        k.node.physicsBody?.angularVelocity = SCNVector4Zero
        k.node.simdWorldTransform = k.home
        k.node.physicsBody?.resetTransform()
        k.knocked = false
        k.fuse = -1
    }

    func explode(_ k: Knockable) {
        guard !k.exploded else { return }
        let c = k.pos
        k.exploded = true
        k.knocked = true
        k.knockedAt = Float(time)
        k.node.removeFromParentNode()
        sfx("boom", at: c, vol: 1.4, rate: Float.random(in: 0.9...1.1))
        fireball(at: c)
        _ = blast(from: c, dir: nil, range: 8, strength: 11, up: 0.8)
        // set off other barrels nearby
        for o in world.knockables where o.explosive && !o.exploded && o !== k && simd_length(o.pos - c) < 5 { o.fuse = Float.random(in: 0.15...0.45) }
        for n in npcs where simd_length(n.pos - c) < 9 {
            let d = SIMD2(n.pos.x - c.x, n.pos.z - c.z)
            n.knock(simd_length(d) > 0.01 ? simd_normalize(d) : SIMD2(1, 0), 6)
            if n.kind == .farmer { n.say(["WHAT IN TARNATION WAS THAT?!", "My eyebrows!", "Who keeps leavin' these barrels around?!"][rng.int(3)], 3); complete("tackle") }
        }
        let pd = pos - c
        let pl = simd_length(pd)
        if pl < 7 && AddOns.body[body.addOns[1]] != "Armor" {
            let away = pl > 0.1 ? simd_normalize(V3(pd.x, 0, pd.z)) : V3(1, 0, 0)
            vel += away * (9 - pl) + V3(0, 11 - pl, 0)
            grounded = false
            flipT = 0; flipAngle = 0
            say(["WHEEE!", "AAAAH!", "Worth it!"][rng.int(3)], 1.6)
        }
        addChaos(100, "KABOOM! +100", big: true)
        complete("boom")
    }

    func fireball(at p: V3) {
        let n = SCNNode(); n.simdPosition = p
        fxRoot.addChildNode(n)
        let fire = SCNParticleSystem()
        fire.loops = false; fire.emissionDuration = 0.1; fire.birthRate = 900
        fire.particleLifeSpan = 0.7; fire.particleLifeSpanVariation = 0.3
        fire.particleSize = 0.9; fire.particleSizeVariation = 0.5
        fire.particleImage = softDotImage(size: 32, hardness: 0.3)
        fire.particleColor = color(1, 0.55, 0.15); fire.particleColorVariation = SCNVector4(0.05, 0.2, 0.1, 0)
        fire.particleVelocity = 7; fire.particleVelocityVariation = 4; fire.spreadingAngle = 180
        fire.blendMode = .additive; fire.isLightingEnabled = false; fire.dampingFactor = 3
        fire.propertyControllers = [.opacity: SCNParticlePropertyController(animation: { let a = CAKeyframeAnimation(); a.values = [1, 0.8, 0]; a.keyTimes = [0, 0.4, 1]; return a }())]
        n.addParticleSystem(fire)
        cloud(color(0.15, 0.13, 0.12, 0.8), at: p + V3(0, 1, 0))
        let light = SCNLight(); light.type = .omni; light.color = color(1, 0.6, 0.25); light.intensity = 8000; light.attenuationEndDistance = 18
        let ln = SCNNode(); ln.light = light; ln.simdPosition = p + V3(0, 1, 0)
        fxRoot.addChildNode(ln)
        ln.runAction(.sequence([.customAction(duration: 0.5) { node, t in node.light?.intensity = CGFloat(8000 * (1 - t / 0.5)) }, .removeFromParentNode()]))
        n.runAction(.sequence([.wait(duration: 3), .removeFromParentNode()]))
    }
}
