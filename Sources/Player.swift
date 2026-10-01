import SceneKit
import simd

let gravity: Float = 14

extension Game {
    var forward: V3 { V3(sinf(yaw), 0, cosf(yaw)) }

    func nearestProp(_ reach: Float) -> Prop? {
        let hand = pos + forward * (body.radius + 0.35)
        var best: Prop?, bd: Float = 99
        for p in props where !p.held && !p.dead {
            let d = simd_length(SIMD2(p.pos.x - hand.x, p.pos.z - hand.z))
            if d < reach && abs(p.pos.y - pos.y) < 1.6 && d < bd { bd = d; best = p }
        }
        return best
    }

    // MARK: player

    func updatePlayer(_ dt: Float, _ f: InputState.Frame, control: Bool) {
        let c = body.combo
        var ls = LegStats.of(c.legs)
        let hA = AddOns.head[body.addOns[0]], bA = AddOns.body[body.addOns[1]], lA = AddOns.legs[body.addOns[2]]
        switch lA {
        case "Hurt": ls.sprint *= 0.45; ls.walk *= 0.6; ls.jump *= 0.6
        case "Roller Skates": ls.sprint *= 1.55; ls.walk *= 1.3; ls.accel *= 0.5
        case "Ice Skates": ls.sprint *= 1.6; ls.walk *= 1.3; ls.accel *= 0.35
        case "Spring Shoes": ls.jump = min(12, ls.jump * 1.55)
        case "Sneakers": ls.sprint *= 1.2; ls.walk *= 1.1
        case "Stilts": ls.walk *= 1.2; ls.sprint *= 1.15; ls.step += 0.3
        case "High Heels": ls.sprint *= 0.85
        default: break
        }
        if bA == "Hurt" { ls.sprint *= 0.8 }
        if hA == "Hurt" { ls.sprint *= 0.9 }
        var fm = body.torso.flight
        if bA == "Jetpack" { fm = 2 } else if bA == "Angel Wings" { fm = max(fm, 1) } else if fm == 0 && (bA == "Superhero Cape" || hA == "Propeller Cap") { fm = 3 }
        flightMode = fm
        let grav = bA == "Balloons" ? gravity * 0.38 : gravity
        let swimmerAdd = bA == "Life Jacket" || lA == "Flippers"
        if grounded { rocketReady = true }
        boostT = max(0, boostT - dt)
        body.boosting = boostT > 0
        if hA == "Hurt" || bA == "Hurt" || lA == "Hurt" {
            hurtT -= dt * (playerSpeed > 1 ? 1 : 0.2)
            if hurtT < 0 { hurtT = Float.random(in: 3...7); audio.play("oof", volume: 0.5, rate: 1.1); if rng.chance(0.4) { say(["Ow…", "Ouch!", "It hurts…", "Need a doctor!"][rng.int(4)], 1.4) } }
        }
        voiceCool -= dt; actionCool -= dt; eatCool -= dt; legsCool -= dt
        if playerSpeechT > 0 { playerSpeechT -= dt; if playerSpeechT <= 0 { playerSpeech = nil } }

        // morph keys
        if control {
            for (i, k) in [Key.nums[0], Key.nums[1], Key.nums[2]].enumerated() where f.pressed(k) {
                let s = Slot(rawValue: i)!
                morph(s, to: f.down(Key.shift) ? body.combo[s].prev : body.combo[s].next)
            }
            if f.pressed(Key.z) { randomMorph() }
            for (i, k) in [Key.nums[3], Key.nums[4], Key.nums[5]].enumerated() where f.pressed(k) { cycleAddOn(Slot(rawValue: i)!, back: f.down(Key.shift)) }
        }

        // input direction relative to the camera
        var mv = SIMD2<Float>(0, 0)
        if control {
            if f.down(Key.w) { mv.y += 1 }
            if f.down(Key.s) { mv.y -= 1 }
            if f.down(Key.a) { mv.x -= 1 }
            if f.down(Key.d) { mv.x += 1 }
        }
        let F = V3(sinf(camYaw), 0, cosf(camYaw))
        let Rt = simd_cross(F, V3(0, 1, 0))
        var wish = F * mv.y + Rt * mv.x
        if simd_length(wish) > 1 { wish = simd_normalize(wish) }
        let sprint = control && f.down(Key.shift)
        var speed = sprint ? ls.sprint : ls.walk
        if carrying?.kind == .pumpkin { speed *= 0.8 }
        if inWater {
            let lg = c.legs.def
            let swimmer = swimmerAdd || lg.plan == .fish || lg.plan == .tentacle || lg.foot == .webbed || c.legs.def.name == "Otter" || c.legs.def.name == "Beaver"
            speed *= swimming ? (swimmer ? 2.4 : 0.65) : (swimmer || lA == "Rain Boots" ? 1.4 : 0.5)
        }
        if layT >= 0 || (eatT > 0 && c.head.def.eat == .graze) { speed = 0 }

        // ladder
        let lad = world.ladder(near: pos, r: body.radius)
        if climbing, let l = lad {
            let out = l.outward
            yaw = atan2f(-out.x, -out.y)
            pos.x = l.x; pos.z = l.z
            vel = V3(0, mv.y * 2.6, 0)
            pos.y += vel.y * dt
            climbAcc += abs(vel.y) * dt
            if climbAcc > 0.3 { climbAcc = 0; audio.play("climb", volume: 0.35) }
            phase += abs(vel.y) * dt * 1.2
            if pos.y >= l.top - 0.05 {
                climbing = false
                pos = V3(l.topStep.x, l.top, l.topStep.y)
                vel = .zero
                audio.play("step_metal", volume: 0.5)
            }
            let g = world.terrain(pos.x, pos.z)
            if pos.y <= g && mv.y < 0 { pos.y = g; climbing = false }
            if control && f.pressed(Key.space) {
                climbing = false
                vel = V3(out.x * 3, 3.5, out.y * 3)
                pos.x += out.x * 0.3; pos.z += out.y * 0.3
            }
            grounded = false
        } else {
            climbing = false
            if let l = lad, simd_length(wish) > 0.1, simd_dot(SIMD2(wish.x, wish.z), -l.outward) > 0.5, pos.y < l.top - 0.5 {
                if body.torso.canGrab { climbing = true; vel = .zero; carryDrop() } else { hintOnce("You need human arms to climb ladders!") }
            }
        }

        if !climbing {
            // horizontal
            var hv = SIMD2(vel.x, vel.z)
            let want = SIMD2(wish.x, wish.z) * speed
            if gliding {
                let dirv = simd_length(want) > 0.1 ? simd_normalize(want) : SIMD2(sinf(yaw), cosf(yaw))
                let glideSpeed: Float = 6.5
                hv += (dirv * glideSpeed - hv) * min(1, dt * 1.6)
            } else {
                let acc = grounded ? ls.accel : ls.accel * 0.3
                hv += (want - hv) * min(1, dt * acc)
            }
            vel.x = hv.x; vel.z = hv.y
            // face where we're going
            let hs = simd_length(hv)
            if hs > 0.3 && shoveT <= 0 {
                let ty = atan2f(hv.x, hv.y)
                var d = ty - yaw
                while d > .pi { d -= 2 * .pi }
                while d < -.pi { d += 2 * .pi }
                yaw += d * min(1, dt * ls.turn)
            }

            // jump, flap, glide
            if control && f.pressed(Key.space) {
                if grounded && layT < 0 {
                    vel.y = ls.jump * (inWater ? 0.6 : 1)
                    grounded = false
                    stat("Jumps")
                    audio.play("jump", volume: 0.35)
                    if c.legs.def.foot == .hoof { audio.play("step_hoof", volume: 0.6) }
                } else if !grounded && lA == "Rocket Boots" && rocketReady {
                    rocketReady = false
                    vel.y = max(vel.y, ls.jump * 1.2)
                    boostT = 0.6
                    audio.play("whoosh", volume: 0.6, rate: 0.7)
                    burst(dust, at: pos, count: 10)
                } else if !grounded && flightMode == 1 && flapsLeft > 0 {
                    flapsLeft -= 1
                    let flap = max(1.6, 5.2 - max(0, body.mass - 1.2) * 0.8)
                    vel.y = max(vel.y, flap)
                    pose.flap = 1
                    audio.play("flap", volume: 0.6)
                    burst(small: true)
                }
            }
            let hover = flightMode == 2 && control && f.down(Key.space) && !grounded
            if hover {
                let ceiling = world.terrain(pos.x, pos.z) + (bA == "Jetpack" ? 40 : 14)
                vel.y = pos.y < ceiling ? max(vel.y + 20 * dt, min(vel.y + 20 * dt, 2.2)) : min(vel.y, 0)
                vel.y = min(vel.y, 2.2)
                pose.flap = 1
                if pos.y - world.terrain(pos.x, pos.z) > 5 && bA != "Jetpack" { complete("hover") }
                if bA == "Jetpack" { boostT = 0.15; if pos.y - world.terrain(pos.x, pos.z) > 20 { complete("jetpack") } }
                hoverSnd -= dt
                if hoverSnd < 0 { hoverSnd = 0.5; audio.play(bA == "Jetpack" ? "whoosh" : c.torso.def.name == "Hummingbird" ? "flap" : "buzzwing", volume: 0.35, rate: bA == "Jetpack" ? 0.5 : 1.6) }
            }
            let wantGlide = control && f.down(Key.space) && !grounded && (flightMode == 1 || flightMode == 3) && vel.y < 0
            if wantGlide && !gliding { gliding = true; glideStart = pos; audio.play("flap", volume: 0.4, rate: 0.8) }
            if !wantGlide && gliding { endGlide() }
            if gliding {
                let sink = 1.3 + max(0, body.mass - 1.2) * 0.55
                vel.y = max(vel.y - gravity * dt, -sink)
            } else if !hover {
                vel.y -= grav * dt
            }

            let prevY = pos.y
            pos += vel * dt
            _ = world.collide(&pos, r: body.radius, h: body.height * 0.8, step: ls.step)
            let wasSwimming = swimming
            var (g, surf, tag) = world.ground(pos.x, pos.z, y: prevY, r: body.radius, step: ls.step)
            // deep water: float at the surface and swim
            let lvl = world.waterLevel(pos.x, pos.z)
            let floatY = (lvl ?? -99) - body.height * 0.55
            swimming = lvl != nil && floatY > g + 0.05
            if swimming { g = floatY; surf = .water; if !wasSwimming { stat("Swims") } }
            if pos.y <= g || (grounded && pos.y - g < ls.step && vel.y <= 0) {
                if !grounded {
                    let impact = -vel.y
                    if impact > 9 { _ = blast(from: pos, dir: nil, range: 1.5 + body.radius + impact * 0.15, strength: impact * 0.5 * min(3, body.mass)) }
                    if impact > 3 {
                        audio.play("land", volume: min(1, impact / 12) * (body.mass > 3 ? 1 : 0.6), rate: body.mass > 3 ? 0.8 : 1.1)
                        if impact > 7 { burst(dust, at: pos, count: 14) }
                    }
                    if flipT >= 0 {
                        if flipAngle > 5.6 { complete("flip"); say("Nailed it!", 1.5) }
                        flipT = -1; flipAngle = 0
                    }
                    if gliding { endGlide() }
                }
                pos.y = g
                vel.y = 0
                grounded = true
                flapsLeft = 3
                surface = surf
                groundTag = tag
                airTime = 0
            } else {
                grounded = false
                airTime += dt
            }
            // pond
            let wasWater = inWater
            let wl = world.waterLevel(pos.x, pos.z)
            inWater = wl != nil && pos.y < (wl ?? 0) - 0.15
            if inWater && !wasWater {
                audio.play("splash", volume: 0.8)
                burst(water, at: V3(pos.x, wl ?? pos.y, pos.z), count: 40)
                complete("splash")
            }
            // respawn if something went very wrong
            if pos.y < -20 || !pos.x.isFinite { let sp = world.map.spawn; pos = V3(sp.x, world.terrain(sp.x, sp.z) + 1, sp.z); vel = .zero }
        }

        // flips
        if flipT >= 0 {
            flipT += dt
            flipAngle = min(2 * .pi, flipT / 0.8 * 2 * .pi)
        }
        body.flip = flipAngle

        // actions
        if control {
            if f.pressed(Key.e) { torsoAction() }
            if f.pressed(Key.f) { voiceAction() }
            if f.pressed(Key.r) { eatAction() }
            if f.pressed(Key.q) { legsAction() }
        }
        // throw release
        if throwT >= 0 {
            let before = throwT
            throwT += dt / 0.55
            if before < 0.4 && throwT >= 0.4, let p = carrying {
                p.held = false
                let pumpkin = p.kind == .pumpkin
                p.vel = forward * (pumpkin ? 8.5 : 12) + V3(0, pumpkin ? 5 : 4, 0) + V3(vel.x, 0, vel.z) * 0.5
                p.thrownFrom = pos
                p.thrownBy = true
                p.pos = pos + V3(0, body.legs.attach.y + 0.5, 0) + forward * (body.radius + 0.2)
                carrying = nil
                audio.play("throw", volume: 0.6)
                if p.kind == .egg { complete("eggtoss") }
                stat("Things thrown")
            }
            if throwT >= 1 { throwT = -1 }
        }
        if layT >= 0 {
            let before = layT
            layT += dt
            if before < 0.55 && layT >= 0.55 {
                let back = pos - forward * (body.radius + 0.1) + V3(0, max(0.12, body.legs.attach.y * 0.45), 0)
                let egg = Prop(.egg, at: back)
                egg.vel = -forward * 0.6
                egg.laid = true
                addProp(egg)
                audio.play("plop", volume: 0.6)
                save.eggs += 1
                complete("egg")
                if Farm.inRun(pos) { complete("nest") }
                // keep the number of eggs sane
                let eggs = props.filter { $0.kind == .egg && !$0.held }
                if eggs.count > 14, let old = eggs.first { removeProp(old) }
            }
            if layT > 1.1 { layT = -1 }
        }
        shoveT = max(0, shoveT - dt * 2.5)
        kickT = max(0, kickT - dt * 2.2)
        talkT = max(0, talkT - dt)
        eatT = max(0, eatT - dt)

        // carried prop follows the hands
        if let p = carrying {
            let local = body.carryPoint()
            let wp = body.root.simdConvertPosition(local, to: nil)
            p.pos = wp + V3(0, p.radius * 0.3, 0)
            p.vel = .zero
            p.node.simdPosition = p.pos
        }

        // stats
        stat("Time played", Double(dt))
        if control {
            let step = Double(simd_length(SIMD2(vel.x, vel.z)) * dt)
            if grounded { stat("Distance walked", step) } else if gliding || flightMode == 2 { stat("Distance flown", step) }
            let hgt = Double(pos.y)
            if hgt > (save.stats["Highest point"] ?? 0) { save.stats["Highest point"] = hgt }
        }
        // stampede
        let hs = playerSpeed
        if c.legs.def.foot == .hoof && c.legs.def.plan == .quad && grounded && hs > 6.5 { stampedeT += dt; if stampedeT > 6 { complete("stampede") } } else { stampedeT = max(0, stampedeT - dt * 3) }

        // pose
        let stride = body.legs.stride
        phase += (climbing ? 0 : hs / stride) * dt
        pose.t = Float(time)
        pose.phase = phase
        pose.gait += (min(1, hs / 0.6) - pose.gait) * min(1, dt * 8)
        let runThresh: Float = LegStats.of(c.legs).sprint * 0.62
        pose.run += ((hs > runThresh ? 1 : 0) - pose.run) * min(1, dt * 5)
        pose.air += (((!grounded && !climbing && airTime > 0.08) || flipT >= 0 ? 1 : 0) - pose.air) * min(1, dt * 10)
        pose.glide += ((gliding ? 1 : 0) - pose.glide) * min(1, dt * 8)
        pose.flap = max(0, pose.flap - dt * 2.2)
        pose.carry += ((carrying != nil && throwT < 0 ? 1 : 0) - pose.carry) * min(1, dt * 10)
        pose.throwT = throwT
        pose.shove = shoveT > 0 ? sinf(min(1, shoveT) * .pi) : 0
        pose.talk = talkT > 0 ? min(1, talkT * 3) : 0
        pose.eat += ((eatT > 0 ? 1 : 0) - pose.eat) * min(1, dt * 10)
        pose.kick = kickT > 0 ? sinf(kickT * .pi) : 0
        pose.lay = layT >= 0 ? sinf(min(1, layT / 1.1) * .pi) : 0
        pose.climb += ((climbing ? 1 : 0) - pose.climb) * min(1, dt * 10)
        if climbing { pose.phase = pos.y * 1.4 }
        body.root.simdPosition = pos
        body.root.simdEulerAngles = V3(0, yaw, 0)
        body.update(pose, dt: dt)

        // footsteps
        if grounded && !climbing && hs > 0.3 {
            let fp = body.legs.footPhases
            let cur = phase - floorf(phase), last = lastFootPhase
            for p in fp {
                let crossed = last <= cur ? (last < p && cur >= p) : (last < p || cur >= p)
                if crossed { footstep(c.legs) }
            }
            lastFootPhase = cur
        } else {
            lastFootPhase = phase - floorf(phase)
        }

        // silo leap and roof
        if grounded && groundTag == "barnRoof" { complete("roof") }
        if grounded && groundTag == "pyramid" && pos.y - world.terrain(-35, 30) > 13 { complete("pyramid") }
        if mapIndex > 0 && c.isPure && world.map.natives.contains(c.head.name) { complete("native\(mapIndex)") }
    }

    func burst(small: Bool) {
        if flightMode == 1 { burstFeathers(pos + V3(0, body.legs.attach.y + 0.3, 0), 6) }
    }

    func burstFeathers(_ p: V3, _ n: Int) {
        let node = SCNNode(); node.simdPosition = p
        fxRoot.addChildNode(node)
        node.runAction(.sequence([.wait(duration: 3), .removeFromParentNode()]))
        let ps = SCNParticleSystem()
        ps.loops = false; ps.emissionDuration = 0.05; ps.birthRate = CGFloat(n) / 0.05
        ps.particleLifeSpan = 1.8; ps.particleSize = 0.06; ps.particleColor = color(0.5, 0.22, 0.08)
        ps.particleVelocity = 1.5; ps.spreadingAngle = 180; ps.acceleration = SCNVector3(0, -0.6, 0)
        ps.particleImage = softDotImage(size: 16, hardness: 0.5); ps.dampingFactor = 2
        ps.particleAngularVelocity = 200; ps.particleAngleVariation = 180
        node.addParticleSystem(ps)
    }

    private func endGlide() {
        gliding = false
        let d = simd_length(SIMD2(pos.x - glideStart.x, pos.z - glideStart.z))
        if d >= 15 { complete("glide") }
        let s = Farm.silo
        if world.isFarm && glideStart.y > s.h - 2 && simd_length(SIMD2(glideStart.x - s.x, glideStart.z - s.z)) < s.r + 2.5 && d > 6 { complete("silo") }
        if d > 4 { hintOnce(String(format: "Glided %.0f m", d), 1.8) }
    }

    func carryDrop() {
        if let p = carrying { p.held = false; p.vel = vel; carrying = nil }
    }

    func removeProp(_ p: Prop) {
        p.dead = true
        p.node.removeFromParentNode()
        props.removeAll { $0 === p }
        if carrying === p { carrying = nil }
    }

    // MARK: abilities

    func inFront(_ p: V3, range: Float, cone: Float = 0.3, behind: Bool = false) -> Bool {
        let d = SIMD2(p.x - pos.x, p.z - pos.z)
        let l = simd_length(d)
        guard l < range + body.radius, l > 0.01, abs(p.y - pos.y) < 2.5 else { return false }
        let fw = SIMD2(sinf(yaw), cosf(yaw)) * (behind ? -1 : 1)
        return simd_dot(d / l, fw) > cone
    }

    func smashEgg(_ p: Prop) {
        guard !p.dead else { return }
        audio.play("splat", volume: 0.7)
        burst(yolk, at: p.pos, count: 22)
        let splat = SCNNode(geometry: {
            let g = SCNCylinder(radius: 0.12, height: 0.005)
            g.materials = [Mat.eggYolk]
            return g
        }())
        let gy = world.ground(p.pos.x, p.pos.z, y: p.pos.y + 0.2, r: 0.05).0
        splat.simdPosition = V3(p.pos.x, gy + 0.004, p.pos.z)
        splat.simdScale = V3(1, 1, 0.8)
        splat.castsShadow = false
        fxRoot.addChildNode(splat)
        splat.runAction(.sequence([.wait(duration: 12), .fadeOut(duration: 2), .removeFromParentNode()]))
        removeProp(p)
    }

    // MARK: props and contacts

    func updateProps(_ dt: Float) {
        for p in props {
            let wasAir = !p.grounded
            let impact = p.step(dt, world: world)
            if impact > 1.2 && wasAir {
                if p.kind == .egg && impact > (p.laid && impact < 4 ? 99 : 3.2) { smashEgg(p); continue }
                sfx(p.impactSound, at: p.pos, vol: min(1, impact / 8), rate: p.kind == .apple ? 1.6 : 1)
                if let from = p.thrownFrom {
                    let d = simd_length(SIMD2(p.pos.x - from.x, p.pos.z - from.z))
                    if p.kind == .pumpkin && d >= 8 { complete("pumpkin") }
                    if d > 3 { hintOnce(String(format: "Thrown %.1f m", d), 1.5) }
                    p.thrownFrom = nil
                }
            }
            if p.pos.y < -10 || abs(p.pos.x) > Farm.half + 5 || abs(p.pos.z) > Farm.half + 5 {
                p.pos = p.home; p.vel = .zero
            }
            // the ball: measure kicks once it stops
            if p === ball, let from = ballKickFrom, p.rest > 0.3 {
                let d = simd_length(SIMD2(p.pos.x - from.x, p.pos.z - from.z))
                if d >= 15 { complete("goal") }
                if d > 4 { hintOnce(String(format: "Kicked %.0f m", d), 1.5) }
                ballKickFrom = nil
            }
            // thrown things bonk NPCs
            let sp = simd_length(p.vel)
            if sp > 5 && p.thrownBy {
                for n in npcs where simd_length(n.pos + V3(0, 0.8 * n.scale, 0) - p.pos) < n.radius + p.radius + 0.4 {
                    if n.kind == .farmer && p.mass > 1 { n.knock(simd_normalize(SIMD2(p.vel.x, p.vel.z) + 0.0001), 3); complete("tackle") }
                    else if n.kind == .farmer { n.say("Hey! Quit throwin' stuff!", 2) }
                    else { n.flee(from: p.pos) }
                    if p.kind == .egg { smashEgg(p) }
                    p.vel *= -0.3
                    p.thrownBy = false
                    break
                }
            }
            if sp < 1 { p.thrownBy = false }
        }
    }

    func interactions(_ dt: Float) {
        let r = body.radius
        let hv = SIMD2(vel.x, vel.z)
        let hs = simd_length(hv)
        // walk into loose props to push and kick them
        for p in props where !p.held && !p.dead {
            let d = SIMD2(p.pos.x - pos.x, p.pos.z - pos.z)
            let l = simd_length(d)
            let minD = r + p.radius
            guard l < minD, l > 0.001, p.pos.y < pos.y + body.height * 0.6 else { continue }
            let n = d / l
            p.pos.x = pos.x + n.x * minD; p.pos.z = pos.z + n.y * minD
            let into = simd_dot(hv, n)
            if into > 0 {
                let kick: Float = p.kind == .ball ? 1.8 : p.kind == .pumpkin ? 0.9 : 1.2
                p.vel.x += n.x * into * kick; p.vel.z += n.y * into * kick
                if p.kind == .ball && into > 2.5 {
                    p.vel.y += into * 0.35
                    ballKickFrom = p.pos
                    audio.play("kick", volume: min(1, into / 6))
                }
                if p.kind == .egg && into > 3 { smashEgg(p) }
                if body.mass > 3 && hs > 5 { p.vel.y += 3 }
            }
        }
        // bump into animals and the farmer
        for n in npcs {
            let d = SIMD2(n.pos.x - pos.x, n.pos.z - pos.z)
            let l = simd_length(d)
            let minD = r + n.radius
            guard l < minD, l > 0.001, abs(n.pos.y + n.y - pos.y) < 1.5 else { continue }
            let nn = d / l
            let push = minD - l
            let heavy = body.mass
            let theirs: Float = n.kind == .cow ? 4 : n.kind == .farmer ? 1.2 : 0.2
            let share = heavy / (heavy + theirs)
            n.pos.x += nn.x * push * share; n.pos.z += nn.y * push * share
            pos.x -= nn.x * push * (1 - share); pos.z -= nn.y * push * (1 - share)
            if body.mass > 2.5 && hs > 5.5 {
                n.knock(nn, hs * 0.6)
                if n.kind == .farmer { complete("tackle") }
            }
        }
        // pouncing onto someone
        if pounceT > 0 {
            pounceT -= dt
            for n in npcs where simd_length(n.pos - pos) < r + n.radius + 0.6 {
                if n.kind == .farmer { n.knock(SIMD2(sinf(yaw), cosf(yaw)), 3); complete("tackle") } else { n.flee(from: pos) }
                pounceT = 0
                audio.play("shove", volume: 0.7)
                break
            }
        }
        // challenges that depend on company
        let c = body.combo
        if c.isPure && c.head == .cow {
            let near = npcs.filter { $0.kind == .cow && simd_length($0.pos - pos) < 7 }.count
            if near >= 3 { complete("herd") }
        }
        let following = npcs.filter { $0.isChicken && $0.state == .follow && simd_length($0.pos - pos) < 14 }.count
        if following >= 3 { complete("flock") }
    }
}
