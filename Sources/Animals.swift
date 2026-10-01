import SceneKit
import simd

enum NPCKind { case hen, rooster, cow, farmer, critter }

protocol NPCHost: AnyObject {
    var playerPos: V3 { get }
    var playerCombo: Combo { get }
    var playerSpeed: Float { get }
    var playerRadius: Float { get }
    func sfx(_ name: String, at p: V3, vol: Float, rate: Float)
    func npcSays(_ npc: NPC, _ text: String, _ secs: Float)
    func cowReplied()
    func farmerScared()
    func farmerGreeted()
}

/// A farm animal or the farmer. Simple state machines over the same Body rig the player uses.
final class NPC {
    enum State { case idle, wander, eat, flee, follow, goHome, moo, talk, scared, fallen, herd, chore }
    let kind: NPCKind
    let body: Body
    let scale: Float
    var pos: V3
    var yaw: Float
    var vel = SIMD2<Float>(0, 0)
    var y: Float = 0, vy: Float = 0
    var phase: Float = 0
    var state: State = .idle
    var timer: Float = 1
    var target = V3.zero
    var pose = Pose()
    var followT: Float = 0
    var voiceT: Float = 3
    var replyT: Float = -1
    var stepAcc: Float = 0
    var speech: String? = nil
    var speechT: Float = 0
    var waypoint = 0
    var greetCool: Float = 0
    var scareCool: Float = 0
    var fallDir: Float = 1
    var flapT: Float = 0
    weak var host: NPCHost?
    private var rng: RNG
    var species: Species = .human
    var home = V3.zero
    var aquatic = false
    private var talkT: Float = 0, waveT: Float = 0

    static let farmerRoute: [V3] = [V3(-4, 0, 19.5), V3(3, 0, 0), V3(15.5, 0, -6.5), V3(-9.5, 0, -8), V3(-10, 0, -12), V3(26, 0, 3.5), V3(31, 0, 3.5), V3(8, 0, 24), V3(-4, 0, 19.5)]

    init(_ k: NPCKind, at p: V3, seed: UInt64) {
        kind = k
        rng = RNG(seed)
        switch k {
        case .hen:
            let white = seed % 3 == 0
            body = Body(Combo(.chicken, .chicken, .chicken), white: white); scale = 0.3
        case .rooster:
            body = Body(Combo(.chicken, .chicken, .chicken)); scale = 0.36
        case .cow:
            body = Body(Combo(.cow, .cow, .cow)); scale = rng.range(0.92, 1.05)
        case .farmer:
            body = Body(Combo(.human, .human, .human), outfit: .farmer); scale = 1.0
        case .critter:
            body = Body(Combo(.human, .human, .human)); scale = 1
        }
        pos = p
        yaw = rng.range(-3, 3)
        body.root.simdScale = V3(repeating: scale)
        timer = rng.range(0.5, 4)
        voiceT = rng.range(2, 12)
        pose.phase = rng.range(0, 1)
    }

    /// A wild animal of any species, living on one of the generated maps.
    init(critter sp: Species, at p: V3, seed: UInt64) {
        kind = .critter
        rng = RNG(seed)
        species = sp
        body = Body(Combo(sp, sp, sp))
        scale = 1
        pos = p; home = p
        aquatic = sp.def.plan == .fish || sp.def.plan == .tentacle
        yaw = rng.range(-3, 3)
        timer = rng.range(0.5, 4)
        voiceT = rng.range(3, 20)
        pose.phase = rng.range(0, 1)
    }

    var radius: Float { body.radius * scale }
    var isChicken: Bool { kind == .hen || kind == .rooster }

    private func bounds() -> (Float, Float, Float, Float) {
        switch kind {
        case .hen, .rooster: let r = Farm.coopRun; return (r.minX + 0.6, r.maxX - 0.6, r.minZ + 0.6, r.maxZ - 0.6)
        case .cow: let p = Farm.pasture; return (p.minX + 2, p.maxX - 2, p.minZ + 2, p.maxZ - 2)
        case .farmer, .critter: return (-Farm.half, Farm.half, -Farm.half, Farm.half)
        }
    }

    private func randomTarget() -> V3 {
        let (a, b, c, d) = bounds()
        var t = V3(rng.range(a, b), 0, rng.range(c, d))
        if kind == .cow && rng.chance(0.25) { t = V3(Farm.trough.x + rng.range(-1, 1), 0, Farm.trough.z + rng.range(-3, 3)) }
        return t
    }

    func say(_ s: String, _ secs: Float = 2.5) { host?.npcSays(self, s, secs) }

    /// Called when the player clucks nearby.
    func heardCluck(from p: V3, playerIsChicken: Bool) {
        guard isChicken, state != .fallen else { return }
        let d = simd_length(SIMD2(p.x - pos.x, p.z - pos.z))
        guard d < 14 else { return }
        if playerIsChicken {
            state = .follow; followT = 18
            if rng.chance(0.5) { voiceT = rng.range(0.2, 0.8) }
        } else if d < 6 {
            flee(from: p)
        }
    }

    func heardMoo(from p: V3) {
        guard kind == .cow, state != .fallen else { return }
        let d = simd_length(SIMD2(p.x - pos.x, p.z - pos.z))
        guard d < 28 else { return }
        replyT = rng.range(0.6, 1.8)
        target = p
        state = .idle; timer = 2.5
    }

    func flee(from p: V3, secs: Float = 1.6) {
        guard state != .fallen else { return }
        var away = SIMD2(pos.x - p.x, pos.z - p.z)
        if simd_length(away) < 0.01 { away = SIMD2(1, 0) }
        away = simd_normalize(away)
        target = pos + V3(away.x, 0, away.y) * 8
        if state != .flee && isChicken { host?.sfx("cluck", at: pos, vol: 0.55, rate: 1.35); flapT = 0.8 }
        state = .flee; timer = secs
    }

    /// Shoved, charged or hit by something heavy.
    func knock(_ dir: SIMD2<Float>, _ strength: Float) {
        switch kind {
        case .farmer:
            guard state != .fallen else { return }
            state = .fallen; timer = 3.2
            vel = dir * strength
            fallDir = rng.chance(0.5) ? 1 : -1
            host?.sfx("oof", at: pos, vol: 0.9, rate: 1)
            say(["OOF!", "Dagnabbit!", "My back!", "Ow! Why I oughta..."][rng.int(4)], 2.5)
        case .cow:
            vel = dir * strength * 0.3
            flee(from: pos - V3(dir.x, 0, dir.y), secs: 2.5)
            host?.sfx("moo", at: pos, vol: 0.8, rate: rng.range(1.0, 1.15))
        case .hen, .rooster, .critter:
            vel = dir * strength * (kind == .critter ? min(1, 1.5 / max(0.3, body.mass)) : 1)
            if kind != .critter || body.mass < 1 { vy = 3 }
            flapT = 1.2
            flee(from: pos - V3(dir.x, 0, dir.y), secs: 2)
            if kind == .critter { host?.sfx(species.voiceSound, at: pos, vol: 0.8, rate: 1.1) }
        }
    }

    func update(_ dt: Float, world: World, t: Float) {
        guard let host else { return }
        let pp = host.playerPos
        let toP = SIMD2(pp.x - pos.x, pp.z - pos.z)
        let dP = simd_length(toP)
        let pc = host.playerCombo
        timer -= dt
        voiceT -= dt
        greetCool -= dt; scareCool -= dt
        flapT = max(0, flapT - dt)
        if speechT > 0 { speechT -= dt; if speechT <= 0 { speech = nil } }
        var want = SIMD2<Float>(0, 0)
        var speed: Float = 0
        pose.eat = max(0, pose.eat - dt * 3)
        pose.talk = max(0, pose.talk - dt * 2)
        pose.scared = max(0, pose.scared - dt * 2)
        pose.wave = max(0, pose.wave - dt * 1.5)
        pose.shove = 0

        func go(_ tgt: V3, _ sp: Float, arrive: Float = 0.4) -> Bool {
            let d = SIMD2(tgt.x - pos.x, tgt.z - pos.z)
            let l = simd_length(d)
            if l < arrive { return true }
            want = d / l; speed = sp * min(1, l / 1.2 + 0.3)
            return false
        }

        switch kind {
        case .hen, .rooster:
            let playerChicken = pc.head == .chicken && pc.torso == .chicken
            let scary = !playerChicken || host.playerSpeed > 3.5
            if state != .flee && state != .fallen && scary && dP < 1.4 + host.playerRadius * 1.5 && (host.playerSpeed > 0.8 || dP < 1.0) { flee(from: pp) }
            switch state {
            case .flee:
                _ = go(target, 2.6, arrive: 0.3)
                if timer < 0 { state = followT > 0 ? .follow : .idle; timer = 1 }
            case .follow:
                followT -= dt
                if dP > 2.2 { _ = go(pp, dP > 5 ? 2.4 : 1.2, arrive: 2.0) } else if rng.chance(dt * 0.5) { pose.eat = 1 }
                if followT < 0 { state = .goHome }
            case .goHome:
                let c = Farm.coopRun
                if go(V3((c.minX + c.maxX) / 2, 0, (c.minZ + c.maxZ) / 2), 1.1, arrive: 3) { state = .idle }
            case .eat:
                pose.eat = 1
                if timer < 0 { state = .idle; timer = rng.range(0.3, 2) }
            case .wander:
                if go(target, 0.5) || timer < 0 { state = rng.chance(0.6) ? .eat : .idle; timer = rng.range(1, 4) }
            default:
                if timer < 0 {
                    if rng.chance(0.55) { state = .wander; target = randomTarget(); timer = 8 } else { state = .eat; timer = rng.range(1, 3.5) }
                }
            }
            if voiceT < 0 {
                if kind == .rooster && rng.chance(0.35) {
                    host.sfx("crow", at: pos, vol: 1.0, rate: 1); voiceT = rng.range(30, 70); pose.talk = 1.5
                } else {
                    host.sfx("cluck", at: pos, vol: 0.5, rate: kind == .rooster ? 1.0 : rng.range(1.2, 1.45)); voiceT = rng.range(3, 12); pose.talk = 0.6
                }
            }
        case .cow:
            let herdMode = pc.isPure && pc.head == .cow && Farm.inPasture(pp) && dP < 26
            if replyT > 0 {
                replyT -= dt
                want = simd_length(toP) > 0 ? toP / max(0.01, dP) : want
                speed = 0.01
                if replyT <= 0 {
                    host.sfx("moo", at: pos, vol: 1.0, rate: rng.range(0.9, 1.1)); pose.talk = 1.6; state = .moo; timer = 1.6
                    host.cowReplied()
                }
            }
            switch state {
            case .flee:
                _ = go(target, 3.2)
                if timer < 0 { state = .idle; timer = 2 }
            case .moo:
                pose.talk = 1
                if timer < 0 { state = .idle; timer = rng.range(1, 3) }
            case .eat:
                pose.eat = 1
                if rng.chance(dt * 0.15) { target = pos + V3(cosf(yaw), 0, sinf(yaw)) * 0.8 }
                if timer < 0 { state = .idle; timer = rng.range(1, 3) }
                if herdMode && dP > 7 { state = .herd }
            case .wander:
                if go(target, 0.85, arrive: 1) || timer < 0 { state = .eat; timer = rng.range(6, 16) }
            case .herd:
                if !herdMode { state = .idle; timer = 1 } else if go(pp, 1.1, arrive: 3.5 + Float(rng.int(3))) { state = .eat; timer = rng.range(3, 6) }
            default:
                if timer < 0 {
                    if herdMode { state = .herd } else if rng.chance(0.4) { state = .wander; target = randomTarget(); timer = 25 } else { state = .eat; timer = rng.range(8, 20) }
                }
            }
            if voiceT < 0 && state != .moo {
                host.sfx("moo", at: pos, vol: 0.9, rate: rng.range(0.85, 1.1)); pose.talk = 1.6; state = .moo; timer = 1.7
                voiceT = rng.range(18, 45)
            }
        case .critter:
            let d = species.def
            let ls = LegStats.of(species)
            let same = pc.isPure && pc.head == species
            if !same && state != .flee && dP < 2.5 + host.playerRadius * 1.5 && (host.playerSpeed > 2.2 || dP < 1.2) { flee(from: pp, secs: 2) }
            func pickTarget() -> V3 {
                for _ in 0..<12 {
                    let a = rng.range(0, 6.28), r = rng.range(3, 22)
                    let t = home + V3(cosf(a) * r, 0, sinf(a) * r)
                    let wet = world.waterLevel(t.x, t.z) != nil
                    if abs(t.x) < Farm.half - 12 && abs(t.z) < Farm.half - 12 && wet == aquatic { return t }
                }
                return home
            }
            switch state {
            case .flee:
                _ = go(target, ls.sprint * 0.75)
                if timer < 0 { state = .idle; timer = 1 }
            case .eat:
                pose.eat = 1
                if timer < 0 { state = .idle; timer = rng.range(0.5, 2) }
            case .wander:
                if go(target, ls.walk * 0.7, arrive: 0.8) || timer < 0 { state = rng.chance(0.5) ? .eat : .idle; timer = rng.range(2, 6) }
            case .herd:
                if !same || dP > 30 { state = .idle; timer = 1 } else if go(pp, ls.walk, arrive: 2.5 + body.radius * 2) { state = .eat; timer = rng.range(2, 4) }
            default:
                if timer < 0 {
                    if same && dP < 20 { state = .herd } else if rng.chance(0.6) { state = .wander; target = pickTarget(); timer = 20 } else { state = .eat; timer = rng.range(2, 6) }
                }
            }
            if voiceT < 0 {
                if dP < 45 { host.sfx(species.voiceSound, at: pos, vol: 0.8, rate: rng.range(0.92, 1.08)) }
                pose.talk = 1.2
                voiceT = rng.range(10, 30)
            }
            if state == .flee && d.plan == .bird && d.arms == .wing { flapT = 0.5 }
        case .farmer:
            let human = pc.head == .human && pc.torso == .human && pc.legs == .human
            let sees = dP < 4 || (dP < 15 && simd_dot(toP / max(0.01, dP), SIMD2(sinf(yaw), cosf(yaw))) > 0.1)
            if state != .fallen && state != .scared && sees {
                if human {
                    if greetCool < 0 && dP < 9 {
                        greetCool = 25; state = .talk; timer = 2.8; waveT = 1.8
                        say(["Howdy there, stranger!", "Mornin'! Fine day for it.", "Well hello! You new round here?"][rng.int(3)], 3)
                        host.sfx("talk", at: pos, vol: 0.9, rate: 0.85)
                        host.farmerGreeted()
                    }
                } else if pc.isPure {
                    if greetCool < 0 && dP < 10 {
                        greetCool = 20
                        let n = pc.head.name.lowercased()
                        let a = "aeiou".contains(n.first ?? "x") ? "an" : "a"
                        let line: String
                        switch pc.head {
                        case .cow: line = "Bessie? How'd you get out of the pasture?"
                        case .chicken: line = "Now THAT is one big chicken..."
                        default: line = ["Well I'll be. \(a.capitalized) \(n) on my farm?", "Where in tarnation did \(a) \(n) come from?", "Shoo, you \(n)! Shoo!"][rng.int(3)]
                        }
                        say(line, 3)
                        host.sfx("talk", at: pos, vol: 0.8, rate: 0.85)
                    }
                } else if scareCool < 0 && dP < 12 {
                    state = .scared; timer = 4.5; scareCool = 9
                    say(["WHAT IN TARNATION?!", "AAAH! A MONSTER!", "Somebody call the sheriff!", "Lord have mercy, what ARE you?!", "Nope. Nope nope nope."][rng.int(5)], 3)
                    host.sfx("scream", at: pos, vol: 1.0, rate: rng.range(0.95, 1.05))
                    host.farmerScared()
                }
            }
            switch state {
            case .fallen:
                pose.fallen = min(1, pose.fallen + dt * 5)
                vel *= 1 - min(1, dt * 3)
                if timer < 0 {
                    state = .idle; timer = 1.5
                    host.sfx("hmph", at: pos, vol: 0.8, rate: 1)
                }
            case .scared:
                pose.scared = 1
                var away = -toP / max(0.01, dP)
                if dP > 16 { away = .zero }
                want = away; speed = 4.2
                if timer < 0 { state = .idle; timer = 2 }
            case .talk:
                want = toP / max(0.01, dP); speed = 0.01
                waveT -= dt
                if waveT > 0 { pose.wave = 1 }
                pose.talk = timer > 1 ? 1 : 0
                if timer < 0 { state = .idle; timer = 0.5 }
            case .chore:
                pose.eat = 0.6
                if timer < 0 { state = .idle; timer = 0.2 }
            default:
                pose.fallen = max(0, pose.fallen - dt * 2)
                if pose.fallen > 0 { break }
                // keep away from monsters he's already seen
                if !human && !pc.isPure && dP < 6 && scareCool > 0 { want = -toP / max(0.01, dP); speed = 2.5; break }
                let wp = NPC.farmerRoute[waypoint]
                if go(wp, 1.35, arrive: 0.6) {
                    waypoint = (waypoint + 1) % NPC.farmerRoute.count
                    if rng.chance(0.6) { state = .chore; timer = rng.range(2.5, 5) }
                }
            }
            if state == .fallen { pose.fallen = min(1, pose.fallen + dt * 5) }
        }

        // steering and integration
        let accel: Float = kind == .cow ? 2 : 6
        let desired = want * speed
        vel += (desired - vel) * min(1, dt * accel)
        if state == .fallen { vel *= 1 - min(1, dt * 2) }
        let hs = simd_length(vel)
        if simd_length(want) > 0.1 && speed > 0 {
            let ty = atan2f(want.x, want.y)
            var dy = ty - yaw
            while dy > .pi { dy -= 2 * .pi }
            while dy < -.pi { dy += 2 * .pi }
            yaw += dy * min(1, dt * (kind == .cow ? 2 : 7))
        }
        var np = pos + V3(vel.x, 0, vel.y) * dt
        // chickens flutter over the run fence; everyone else stays inside their bounds
        if isChicken && y <= 0.001 && Farm.inRun(np) != Farm.inRun(pos) && !(np.z > Farm.coopRun.maxZ - 1 && np.x > Farm.coopGate.x0 && np.x < Farm.coopGate.x1) {
            vy = 4.2; flapT = 0.9
        }
        if kind == .cow || (isChicken && (state == .idle || state == .wander || state == .eat)) && Farm.inRun(pos) {
            let (a, b, c, d) = bounds()
            np.x = clampf(np.x, a, b); np.z = clampf(np.z, c, d)
        }
        if kind == .farmer || kind == .critter {
            np.y = pos.y
            _ = world.collide(&np, r: radius, h: 1.8)
        }
        if kind == .critter {
            let lvl = world.waterLevel(np.x, np.z)
            let deep = lvl.map { world.terrain(np.x, np.z) < $0 - 0.6 } ?? false
            if aquatic ? lvl == nil : deep { np = pos; vel = .zero; state = .idle; timer = 0.5 }
        }
        pos = np
        if vy != 0 || y > 0 {
            vy -= 14 * dt
            y += vy * dt
            if y <= 0 { y = 0; vy = 0 }
        }
        var g = world.ground(pos.x, pos.z, y: pos.y + 0.3, r: radius, step: kind == .farmer || kind == .critter ? 0.5 : 0.3).0
        if aquatic, let lvl = world.waterLevel(pos.x, pos.z) { g = max(g, lvl - body.height * 0.55) }
        pos.y = g
        // gait
        let stride = body.legs.stride * scale
        phase += hs / max(0.05, stride) * dt
        pose.t = t
        pose.phase = phase
        pose.gait += (min(1, hs / (0.25 * scale + 0.05)) - pose.gait) * min(1, dt * 6)
        pose.run += ((hs > (kind == .cow ? 2.5 : kind == .farmer ? 2.8 : kind == .critter ? LegStats.of(species).sprint * 0.5 : 1.4) ? 1 : 0) - pose.run) * min(1, dt * 4)
        pose.air = y > 0.05 ? 1 : 0
        pose.flap = flapT > 0 ? 1 : 0
        pose.glide = y > 0.05 ? 0.8 : 0
        body.roll += ((state == .fallen ? fallDir * 1.45 : 0) - body.roll) * min(1, dt * (state == .fallen ? 6 : 2))
        body.root.simdPosition = V3(pos.x, pos.y + y, pos.z)
        body.root.simdEulerAngles = V3(0, yaw, 0)
        body.update(pose, dt: dt)
        // footsteps for the big ones
        if kind == .critter && species.def.size > 0.9 && !aquatic {
            stepAcc += hs * dt
            if stepAcc > body.legs.stride * 0.5 {
                stepAcc = 0
                let (n, v, r) = species.stepSound
                if dP < 16 { host.sfx(n, at: pos, vol: v * 0.7, rate: r) }
            }
        }
        if kind == .cow || kind == .farmer {
            stepAcc += hs * dt
            let every: Float = kind == .cow ? 0.55 : 0.7
            if stepAcc > every {
                stepAcc = 0
                if dP < 18 { host.sfx(kind == .cow ? "step_hoof" : "step_shoe", at: pos, vol: kind == .cow ? 0.5 : 0.35, rate: kind == .cow ? 0.85 : 1) }
            }
        }
    }
}
