import SceneKit
import simd

extension Game {
    /// Stands animals a...b in a row in the yard for screenshots.
    func devLineup(_ a: Int, _ b: Int, side: Bool) {
        var x: Float = 0
        var bodies: [(Body, Float)] = []
        for i in a...b where i < Species.count {
            let sp = Species(id: i)
            let body = Body(Combo(sp, sp, sp))
            let w = max(0.9, body.radius * 2.2, sp.def.size * 1.1)
            x += w / 2
            bodies.append((body, x))
            x += w / 2 + 0.25
        }
        let cx = x / 2
        for (bd, bx) in bodies {
            bd.root.simdPosition = V3(bx - cx, 0, 8)
            bd.root.simdEulerAngles = V3(0, side ? .pi / 2 : .pi * 0.85, 0)
            var p = Pose(); p.t = 1
            bd.update(p, dt: 1)
            scene.rootNode.addChildNode(bd.root)
        }
        body.root.isHidden = true
        let dist = max(4, x * 0.62)
        devCam = V3(0, 1.4 + dist * 0.12, 8 - dist)
        devLook = V3(0, 0.7, 8)
        hud.scene.isHidden = true
    }
    /// Forces a pose for screenshots: walk, run, glide, flap, talk, eat, carry, throw, shove, kick, lay, climb, air.
    func applyDevAct(_ a: String, _ dt: Float) {
        var p = pose
        let t = Float(time)
        switch a {
        case "walk": p.gait = 1; p.run = 0; p.phase = t * 1.4
        case "run": p.gait = 1; p.run = 1; p.phase = t * 2.2
        case "glide": p.glide = 1; p.air = 1
        case "flap": p.flap = 1; p.air = 1
        case "talk": p.talk = 1
        case "eat": p.eat = 1
        case "carry": p.carry = 1
        case "throw": p.throwT = 0.3
        case "shove": p.shove = 1
        case "kick": p.kick = 1
        case "lay": p.lay = 1
        case "climb": p.climb = 1; p.phase = t
        case "air": p.air = 1
        default: break
        }
        body.update(p, dt: dt)
    }

    func autotest() -> Bool {
        var ok = audio.selfCheck()
        func check(_ good: Bool, _ what: String) {
            print((good ? "PASS " : "FAIL ") + what)
            ok = ok && good
        }
        // every animal builds as a whole animal and in random mixes, with sane sizes
        var names = Set<String>()
        var bad: [String] = []
        for sp in Species.all {
            let c = Combo(sp, sp, sp)
            let b = Body(c)
            b.update(Pose(), dt: 1 / 60)
            names.insert(c.name)
            if !(b.height > 0.2 && b.height < 5) || !b.radius.isFinite { bad.append("\(sp.name) h=\(b.height)") }
        }
        check(bad.isEmpty, "100 animals build with sane sizes \(bad)")
        check(names.count == Species.count, "\(Species.count) unique animal names (\(names.count))")
        var rr = RNG(3)
        var mixNames = Set<String>()
        for _ in 0..<150 {
            let c = Combo(Species(id: rr.int(Species.count)), Species(id: rr.int(Species.count)), Species(id: rr.int(Species.count)))
            let b = Body(c)
            var p = Pose(); p.gait = 1; p.run = 1; p.phase = 0.3; p.t = 1
            b.update(p, dt: 1 / 60)
            mixNames.insert(c.name)
            if !(b.height > 0.2 && b.height < 6) { bad.append("\(c.recipe) h=\(b.height)") }
        }
        check(bad.isEmpty, "150 random mixes build \(bad.prefix(3))")
        check(mixNames.count > 140, "mixed names are varied (\(mixNames.count)/150)")
        for sp in Species.all { let ls = LegStats.of(sp); if !(ls.sprint > 0.5 && ls.jump > 1) { bad.append(sp.name) } }
        check(bad.isEmpty, "every animal can move and jump")
        // morphing through every slot keeps the rig valid
        let b = Body(Combo(index: 0))
        scene.rootNode.addChildNode(b.root)
        for i in 0..<60 { b.setCombo(Combo(Species(id: (i * 7) % Species.count), Species(id: (i * 13) % Species.count), Species(id: (i * 29) % Species.count))); for _ in 0..<40 { b.update(Pose(), dt: 1 / 60) } }
        check(b.root.childNodes.count == 1, "morph rig holds one frame after 60 morphs")
        b.root.removeFromParentNode()

        // jumping onto the 0.9 m hay steps: humans and chickens can, cows can't
        for s in [Species.human, .chicken, .cow] {
            let ls = LegStats.of(s)
            let apex = ls.jump * ls.jump / (2 * gravity)
            let reach = apex + ls.step
            let climbs = reach > 0.95
            check(climbs == (s != .cow), String(format: "%@ legs jump apex %.2f m + step %.2f → hay steps %@", s.name, apex, ls.step, climbs ? "yes" : "no"))
        }
        // fences: only chicken legs clear 1.35 m
        for s in [Species.human, .chicken, .cow] {
            let ls = LegStats.of(s)
            let apex = ls.jump * ls.jump / (2 * gravity)
            check((apex > 1.36) == (s == .chicken), String(format: "%@ legs clear pasture fence: %@", s.name, apex > 1.36 ? "yes" : "no"))
        }
        // world queries
        let roof = world.ground(Farm.barn.x, Farm.barn.z, y: 20, r: 0.3).0
        check(abs(roof - Farm.barn.ridge) < 0.6, String(format: "barn ridge height %.2f", roof))
        let silo = world.ground(Farm.silo.x, Farm.silo.z, y: 30, r: 0.3).0
        check(abs(silo - Farm.silo.h - 0.2) < 0.1, String(format: "silo top %.2f", silo))
        let yard = world.ground(2, 7, y: 1, r: 0.3)
        check(abs(yard.0) < 0.5, String(format: "yard ground %.2f", yard.0))
        var p = V3(Farm.barn.x, 0, Farm.barn.z)
        _ = world.collide(&p, r: 0.3, h: 1.8)
        check(abs(p.z - Farm.barn.z) > 5 || abs(p.x - Farm.barn.x) > 8, "barn walls push you out")
        check(world.ladder(near: V3(Farm.silo.x + Farm.silo.r + 0.5, 0, Farm.silo.z), r: 0.3) != nil, "silo ladder reachable")

        // simulated play: walk the player around and let the animals live for 20 s
        enter(.play)
        pos = V3(2, 0, 7)
        let dt: Float = 1 / 60
        var f = InputState.Frame()
        f.held = [Key.w]
        for i in 0..<1200 {
            if i == 300 { body.setCombo(Combo(.chicken, .chicken, .chicken)) }
            if i == 600 { body.setCombo(Combo(.cow, .cow, .cow)) }
            updatePlayer(dt, f, control: true)
            for n in npcs { n.update(dt, world: world, t: Float(i) * dt) }
            updateProps(dt)
            interactions(dt)
            time += Double(dt)
        }
        check(pos.x.isFinite && pos.y > -2, String(format: "player walk stays on the farm (%.1f, %.1f, %.1f)", pos.x, pos.y, pos.z))
        let hens = npcs.filter { $0.isChicken }
        check(hens.allSatisfy { $0.pos.x.isFinite && abs($0.pos.x) < Farm.half }, "hens alive and on the farm")
        let cows = npcs.filter { $0.kind == .cow }
        check(cows.allSatisfy { Farm.inPasture($0.pos) }, "cows stay in the pasture")
        // gliding pure chicken off the silo covers ground
        body.setCombo(Combo(.chicken, .chicken, .chicken))
        pos = V3(Farm.silo.x + 0.5, Farm.silo.h + 0.2, Farm.silo.z); vel = .zero; yaw = .pi / 2; camYaw = .pi / 2
        grounded = true
        var g = InputState.Frame()
        g.held = [Key.w]
        g.presses = [Key.space]
        updatePlayer(dt, g, control: true)
        g.presses = []
        g.held = [Key.w, Key.space]
        var steps = 0
        while !grounded || steps < 5 { updatePlayer(dt, g, control: true); steps += 1; if steps > 3000 { break } }
        let dist = simd_length(SIMD2(pos.x - Farm.silo.x, pos.z - Farm.silo.z))
        check(dist > 25, String(format: "chicken glides %.1f m off the silo", dist))
        // every map loads, has walkable ground, animals, and a player that can walk around it
        for i in 1..<Maps.all.count {
            let t0 = Date()
            loadMap(i)
            let secs = Date().timeIntervalSince(t0)
            var f = InputState.Frame(); f.held = [Key.w, Key.shift]
            camYaw = Float(i)
            for k in 0..<600 {
                updatePlayer(dt, f, control: true)
                for n in npcs { n.update(dt, world: world, t: Float(k) * dt) }
                updateProps(dt); interactions(dt)
                if k % 150 == 0 { camYaw += 1.3 }
            }
            let crit = npcs.filter { $0.kind == .critter }
            let fine = crit.allSatisfy { $0.pos.x.isFinite && $0.pos.y.isFinite && $0.pos.y > -12 }
            check(pos.y.isFinite && pos.y > -12 && crit.count >= 5 && fine,
                  String(format: "%@: built in %.1fs, %d animals, player at (%.0f, %.1f, %.0f)", world.map.name, secs, crit.count, pos.x, pos.y, pos.z))
        }
        loadMap(0)
        return ok
    }
}
