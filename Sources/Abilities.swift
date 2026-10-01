import SceneKit
import simd

enum TorsoAbility { case grab, flap, shove, swipe, pinch, slap, ink, puff, spray, shell }
enum LegAbility { case backflip, egg, buck, pounce, leap, dash }

/// Movement numbers for each kind of legs.
struct LegStats {
    var walk: Float, sprint: Float, jump: Float, accel: Float, turn: Float, step: Float
    static func of(_ s: Species) -> LegStats {
        switch s {
        case .human: return LegStats(walk: 2.3, sprint: 5.4, jump: 5.4, accel: 10, turn: 10, step: 0.45)
        case .chicken: return LegStats(walk: 1.8, sprint: 4.3, jump: 6.9, accel: 14, turn: 12, step: 0.3)
        case .cow: return LegStats(walk: 1.9, sprint: 7.8, jump: 3.3, accel: 4.5, turn: 4, step: 0.35)
        default: break
        }
        let d = s.def
        var b: LegStats
        switch d.plan {
        case .biped: b = LegStats(walk: 2.1, sprint: 5.0, jump: 5.0, accel: 10, turn: 10, step: 0.45)
        case .bird: b = LegStats(walk: 1.7, sprint: 4.0, jump: 6.2, accel: 13, turn: 12, step: 0.3)
        case .quad: b = LegStats(walk: 1.9, sprint: 6.4, jump: 4.0, accel: 6, turn: 6, step: 0.35)
        case .sprawl: b = LegStats(walk: 1.1, sprint: 3.2, jump: 2.6, accel: 7, turn: 6, step: 0.25)
        case .slither: b = LegStats(walk: 1.3, sprint: 3.2, jump: 2.0, accel: 6, turn: 5, step: 0.25)
        case .fish: b = LegStats(walk: 0.8, sprint: 1.8, jump: 3.2, accel: 5, turn: 5, step: 0.2)
        case .insect: b = LegStats(walk: 1.6, sprint: 4.2, jump: 3.4, accel: 14, turn: 12, step: 0.3)
        case .spider: b = LegStats(walk: 1.7, sprint: 4.8, jump: 4.0, accel: 14, turn: 12, step: 0.3)
        case .tentacle: b = LegStats(walk: 1.0, sprint: 2.4, jump: 2.4, accel: 6, turn: 6, step: 0.25)
        case .hopper: b = LegStats(walk: 1.9, sprint: 6.0, jump: 6.4, accel: 9, turn: 9, step: 0.4)
        }
        b.sprint *= d.speed
        b.walk *= min(1.3, sqrtf(d.speed))
        b.jump = min(10, b.jump * d.jump)
        b.step *= clampf(d.size, 0.6, 1.6)
        if d.size > 1.2 { b.accel *= 0.7; b.turn *= 0.7 }
        return b
    }
}

extension Species {
    var torsoAbility: TorsoAbility {
        let d = def
        switch d.special {
        case .ink: return .ink
        case .puff: return .puff
        case .spray: return .spray
        case .shell: return .shell
        case .none: break
        }
        if d.bugWings == .clear || d.bugWings == .big || d.bugWings == .long { return .flap }
        switch d.arms {
        case .hands: return .grab
        case .wing, .batWing: return .flap
        case .pincer: return .pinch
        case .fin: return .slap
        case .tentacles: return .ink
        case .insect: return .pinch
        case .hoof: return .shove
        case .paw: return d.size > 1.0 ? .shove : .swipe
        case .none: return d.size > 1.0 ? .shove : .slap
        }
    }
    var legAbility: LegAbility {
        let d = def
        if self == .human || d.plan == .biped { return .backflip }
        if self == .chicken || layEggs { return .egg }
        switch d.plan {
        case .quad: return d.foot == .hoof || d.foot == .pad ? .buck : .pounce
        case .hopper: return .leap
        default: return .dash
        }
    }
    var voiceSound: String {
        switch self {
        case .human: return "talk"
        case .chicken: return "cluck"
        case .cow: return "moo"
        default: return "call_\(id)"
        }
    }
    var loud: Bool { [.roar, .howl, .bark, .growl, .trumpet, .screech, .bellow, .hiss, .honk].contains(def.voice) }
    var stepSound: (String, Float, Float) {
        let d = def
        switch d.plan {
        case .slither: return ("slither", 0.4, 1)
        case .fish, .tentacle: return ("flop", 0.45, 1)
        case .insect, .spider: return ("step_claw", 0.2, 1.8)
        default: break
        }
        switch d.foot {
        case .hoof: return ("step_hoof", 0.6 * min(1.3, d.size), 1.1 / max(0.7, d.size))
        case .pad: return ("land", 0.35 * d.size, 0.7)
        case .talon, .webbed: return ("step_claw", 0.35, 1.1 / max(0.6, d.size))
        default: return ("step_shoe", 0.35 * min(1.2, d.size), 1.2 / max(0.7, d.size))
        }
    }
}

extension Game {
    func footstep(_ legs: Species) {
        var (name, vol, rate) = legs.stepSound
        if legs == .human { name = "step_shoe"; vol = 0.45; rate = 1 }
        if legs == .chicken { name = "step_claw"; vol = 0.4; rate = 1 }
        if legs == .cow { name = "step_hoof"; vol = 0.7; rate = 0.9 }
        if name == "step_shoe" || name == "step_hoof" || name == "step_claw" {
            switch surface {
            case .wood: name = "step_wood"
            case .hay: name = "step_hay"
            case .metal, .concrete: if name != "step_hoof" { name = "step_metal"; vol *= 0.4 }
            default: break
            }
        }
        if inWater || surface == .water { name = "step_splash" }
        audio.play(name, volume: vol, rate: rate)
    }

    func abilities() -> [String] {
        let c = body.combo
        let ls = c.legs.def
        var a: [String] = []
        var jump = c.legs == .human ? "Jump" : ls.jump > 1.5 || ls.plan == .hopper ? "Big jump" : ls.plan == .fish ? "Flop" : ls.plan == .slither ? "Little hop" : "Jump"
        if c.legs == .chicken { jump = "Big hop" }
        if c.legs == .cow { jump = "Little jump" }
        let fl = flightMode
        let rocket = AddOns.legs[body.addOns[2]] == "Rocket Boots"
        a.append("SPACE  " + jump + (fl == 1 ? "  ·  again to flap, hold to glide" : fl == 2 ? "  ·  hold to fly" : fl == 3 ? "  ·  hold to glide" : rocket ? "  ·  again to rocket" : ""))
        let sprint: String
        switch c.legs {
        case .human: sprint = "Sprint"
        case .chicken: sprint = "Scurry"
        case .cow: sprint = "Gallop!"
        default: sprint = ls.speed > 1.6 ? "Top speed!" : ls.foot == .hoof ? "Gallop!" : ls.plan == .slither ? "Slither fast" : ls.speed < 0.5 ? "Hurry (slowly)" : "Run"
        }
        a.append("SHIFT  " + sprint)
        let ta: String
        switch c.torso.torsoAbility {
        case .grab: ta = "Grab / throw"
        case .flap: ta = "Wing buffet"
        case .shove: ta = "Headbutt shove"
        case .swipe: ta = "Claw swipe"
        case .pinch: ta = "Pinch"
        case .slap: ta = "Flipper slap"
        case .ink: ta = "Squirt ink"
        case .puff: ta = "Puff up!"
        case .spray: ta = "Stink spray"
        case .shell: ta = "Hide in shell"
        }
        a.append("E  " + ta)
        let vn: [Voice: String] = [.talk: "Talk", .cluck: "Cluck", .moo: "MOO", .neigh: "Neigh", .oink: "Oink", .baa: "Baa", .bleat: "Bleat", .bray: "Hee-haw", .bark: "Bark", .meow: "Meow",
                                   .roar: "ROAR", .howl: "Howl", .yip: "Yip", .growl: "Growl", .squeak: "Squeak", .hiss: "Hiss", .quack: "Quack", .honk: "Honk", .gobble: "Gobble", .hoot: "Hoot",
                                   .caw: "Caw", .squawk: "Squawk", .tweet: "Tweet", .coo: "Coo", .trumpet: "Trumpet", .grunt: "Grunt", .bellow: "Bellow", .hoo: "Ooh-ooh-aah", .screech: "Screech",
                                   .chatter: "Chatter", .ribbit: "Ribbit", .buzz: "Buzz", .click: "Click", .whale: "Whale song", .blub: "Blub", .chirp: "Chirp", .snort: "Snort"]
        a.append("F  " + (vn[c.head.def.voice] ?? "Call"))
        a.append("R  " + ["Eat an apple", "Peck corn", "Graze grass", "Chomp"][[Eat.fruit, .peck, .graze, .bite].firstIndex(of: c.head.def.eat) ?? 0])
        let la: String
        switch c.legs.legAbility {
        case .backflip: la = "Backflip"
        case .egg: la = "Lay an egg"
        case .buck: la = "Buck kick"
        case .pounce: la = "Pounce"
        case .leap: la = "Mega leap"
        case .dash: la = "Dash"
        }
        a.append("Q  " + la)
        return a
    }

    // MARK: E

    func torsoAction() {
        guard actionCool < 0, !climbing else { return }
        let c = body.combo
        let power = min(2.2, 0.6 + body.torso.mass * 0.5)
        switch c.torso.torsoAbility {
        case .grab:
            if body.addOns[1] == 1 { say("Ow, my arms hurt too much!", 1.6); audio.play("oof", volume: 0.5); actionCool = 0.6; return }
            if carrying != nil {
                if throwT < 0 { throwT = 0 }
                actionCool = 0.4
                return
            }
            if let p = nearestProp(1.3) {
                p.held = true; p.vel = .zero
                carrying = p
                audio.play("pickup", volume: 0.5)
                if p === ball { ballKickFrom = nil }
                actionCool = 0.3
                return
            }
            shoveT = 1; actionCool = 0.5
            audio.play("whoosh", volume: 0.3, rate: 1.4)
            for n in npcs where inFront(n.pos, range: 1.0) {
                if n.kind == .farmer { n.say("Hey! Watch it, pal.", 2) } else { n.flee(from: pos, secs: 1.2) }
            }
            for p in props where inFront(p.pos, range: 1.0) { p.vel += forward * 3 + V3(0, 1, 0) }
        case .flap:
            shoveT = 0.8; pose.flap = 1; actionCool = 0.45
            audio.play("flap", volume: 0.6, rate: 1.1)
            burst(small: true)
            if !grounded && flapsLeft > 0 { vel.y = max(vel.y, 2.5) }
            for p in props where inFront(p.pos, range: 1.6, cone: 0) { p.vel += forward * 3.5 + V3(0, 1.5, 0) }
            _ = blast(from: pos, dir: forward, range: 2.2 + body.radius, strength: 4, cone: 0)
            for n in npcs where n.kind != .farmer && n.kind != .cow && inFront(n.pos, range: 2, cone: 0) { n.flee(from: pos) }
        case .shove, .swipe, .pinch, .slap:
            let big = c.torso.torsoAbility == .shove
            shoveT = 1; actionCool = big ? 0.7 : 0.45
            let range: Float = big ? 2.0 : 1.4
            var hit = false
            for p in props where inFront(p.pos, range: range, cone: 0.2) {
                p.vel += forward * (big ? 9 : 5) * power + V3(0, big ? 3.5 : 2, 0); hit = true
                if p === ball { ballKickFrom = p.pos }
                if p.kind == .egg { smashEgg(p) }
            }
            for n in npcs where inFront(n.pos, range: range, cone: 0.2) {
                hit = true
                if big || body.mass > 2.5 {
                    n.knock(SIMD2(sinf(yaw), cosf(yaw)), 4)
                    if n.kind == .farmer { complete("tackle") }
                } else if n.kind == .farmer {
                    n.say(c.torso.torsoAbility == .pinch ? "OW! It PINCHED me!" : "Hey! Cut that out!", 2)
                    n.flee(from: pos)
                } else { n.flee(from: pos) }
            }
            if blast(from: pos + V3(0, 0.3, 0), dir: forward, range: range + body.radius, strength: (big ? 9 : 5) * power) { hit = true }
            let snd = c.torso.torsoAbility == .pinch ? "peck" : c.torso.torsoAbility == .slap ? "splat" : "shove"
            audio.play(hit ? snd : "whoosh", volume: hit ? 0.8 : 0.4, rate: hit ? 1 : 0.9)
        case .ink, .spray:
            shoveT = 1; actionCool = 2.0
            _ = blast(from: pos, dir: nil, range: 3, strength: 3)
            let ink = c.torso.torsoAbility == .ink
            audio.play(ink ? "splat" : "whoosh", volume: 0.8, rate: ink ? 0.7 : 0.6)
            cloud(ink ? color(0.05, 0.03, 0.08, 0.9) : color(0.45, 0.6, 0.2, 0.55), at: pos + forward * (ink ? 0.8 : -0.8) + V3(0, 0.5, 0))
            for n in npcs where simd_length(n.pos - pos) < 5 {
                n.flee(from: pos, secs: 3)
                if n.kind == .farmer { n.say(ink ? "Ack! INK?!" : "PEE-YEW! What's that SMELL?!", 2.5); n.state = .scared; n.timer = 3 }
            }
        case .puff:
            shoveT = 3; actionCool = 3.2
            _ = blast(from: pos, dir: nil, range: 2 + body.radius * 2, strength: 8)
            audio.play("poof", volume: 0.8, rate: 0.6)
            for n in npcs where simd_length(n.pos - pos) < 3 { n.flee(from: pos) }
            for p in props where simd_length(p.pos - pos) < 1.6 { p.vel += simd_normalize(p.pos - pos + V3(0, 0.3, 0)) * 5 }
        case .shell:
            shoveT = 2; actionCool = 2.2
            audio.play("thud", volume: 0.6, rate: 0.7)
            say("*hides in shell*", 1.5)
            for n in npcs where n.kind == .farmer && simd_length(n.pos - pos) < 8 { n.say("Huh. Where'd it go?", 2) }
        }
    }

    func cloud(_ c: NSColor, at p: V3) {
        let n = SCNNode(); n.simdPosition = p
        fxRoot.addChildNode(n)
        let s = SCNParticleSystem()
        s.loops = false; s.emissionDuration = 0.15; s.birthRate = 300
        s.particleLifeSpan = 2.5; s.particleSize = 0.5; s.particleSizeVariation = 0.3
        s.particleImage = softDotImage(size: 32); s.particleColor = c
        s.particleVelocity = 1.5; s.spreadingAngle = 180; s.dampingFactor = 2
        s.propertyControllers = [.opacity: SCNParticlePropertyController(animation: { let a = CAKeyframeAnimation(); a.values = [0.9, 0.6, 0]; a.keyTimes = [0, 0.5, 1]; return a }()),
                                 .size: SCNParticlePropertyController(animation: { let a = CAKeyframeAnimation(); a.values = [0.3, 1.2, 1.8]; a.keyTimes = [0, 0.5, 1]; return a }())]
        n.addParticleSystem(s)
        n.runAction(.sequence([.wait(duration: 4), .removeFromParentNode()]))
    }

    // MARK: F

    func voiceAction() {
        guard voiceCool < 0 else { return }
        let c = body.combo
        let d = c.head.def
        talkT = c.head == .cow ? 1.6 : c.head == .chicken ? 0.5 : c.head == .human ? 1.2 : 1.2
        switch c.head {
        case .human:
            voiceCool = 1.2
            audio.play("talk", volume: 0.8)
            if let farmer = npcs.first(where: { $0.kind == .farmer }), simd_length(farmer.pos - pos) < 6, farmer.state != .fallen {
                if c.isPure {
                    let lines = [("Nice farm you've got!", "Why thank ya kindly! Been in the family 80 years."),
                                 ("Seen anything weird lately?", "Funny you ask... folks say there's a critter that's 100 animals at once."),
                                 ("Can I pet the cows?", "Sure thing. Bessie likes a scratch behind the ears."),
                                 ("What's for dinner?", "Not chicken, I'll tell ya that much.")]
                    let l = lines[rng.int(lines.count)]
                    say(l.0, 2.2)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { [weak self] in
                        guard let self else { return }
                        farmer.say(l.1, 3.2)
                        self.sfx("talk", at: farmer.pos, vol: 0.9, rate: 0.85)
                    }
                    farmer.state = .talk; farmer.timer = 4
                    complete("howdy")
                } else {
                    say(["Hello, sir!", "Howdy!", "Don't be scared!"][rng.int(3)], 1.8)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { farmer.say("IT TALKS!", 2) }
                }
            } else {
                let lines = c.isPure ? ["What a lovely day.", "I should get some chores done.", "Hmm, I wonder what morphing feels like."]
                    : ["I feel funny.", "Something's not right with me.", "Is this what a \(c.torso.name.lowercased()) feels like?", "These \(c.legs.name.lowercased()) legs are weird.", "Hello? Anyone?"]
                say(lines[rng.int(lines.count)], 2.2)
            }
        case .chicken:
            voiceCool = 0.5
            audio.play("cluck", volume: 0.8, rate: c.isPure ? 0.9 : 0.8)
            let asChicken = c.torso == .chicken
            for n in npcs { n.heardCluck(from: pos, playerIsChicken: asChicken) }
            if !asChicken { hintOnce("The hens want someone who looks more like a chicken (chicken body too)", 2.5) }
            if rng.chance(0.3) { say(["Bawk!", "Buk buk!", "Bagawk?"][rng.int(3)], 1.2) }
        default:
            voiceCool = d.voice == .moo || d.voice == .whale || d.voice == .trumpet ? 1.8 : 1.0
            let pitch: Float = c.head == .cow ? (body.mass > 3 ? 0.9 : 1.08) : 1
            audio.play(c.head.voiceSound, volume: 1.0, rate: Float(pitch))
            if d.voice == .moo {
                for n in npcs { n.heardMoo(from: pos) }
            }
            for n in npcs where n.kind != .farmer && n.kind != .cow && simd_length(n.pos - pos) < (c.head.loud ? 9 : 4) { n.flee(from: pos) }
            if let farmer = npcs.first(where: { $0.kind == .farmer }), simd_length(farmer.pos - pos) < 12, farmer.state != .fallen {
                if c.head.loud && !c.isPure {
                    farmer.say(d.voice == .roar ? "Was that a... ROAR?!" : "What in the world was THAT noise?", 2.2)
                    if d.voice == .roar || d.voice == .growl { farmer.state = .scared; farmer.timer = 3; complete("scare") }
                } else if d.voice == .moo && !c.isPure && !(c.torso == .cow && c.legs == .cow) {
                    farmer.say("Did that thing just MOO at me?", 2)
                }
            }
        }
    }

    // MARK: R

    func eatAction() {
        guard eatCool < 0 else { return }
        let c = body.combo
        switch c.head.def.eat {
        case .fruit, .bite:
            var food: Prop? = carrying.flatMap { $0.kind == .apple || ($0.kind == .pumpkin && c.head.def.eat == .bite) ? $0 : nil }
            if food == nil { food = props.first(where: { ($0.kind == .apple || (c.head.def.eat == .bite && ($0.kind == .pumpkin || $0.kind == .egg))) && !$0.held && simd_length($0.pos - pos) < body.radius + 1.2 }) }
            if let a = food {
                eatT = 1.2; eatCool = 1.3
                audio.play("crunch", volume: 0.8)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.audio.play("munch", volume: 0.5) }
                let wasApple = a.kind == .apple, wasPumpkin = a.kind == .pumpkin
                let home = a.home
                removeProp(a)
                stat("Things eaten")
                say(["Mmm, crunchy.", "Delicious!", "Nom nom.", "Chomp!"][rng.int(4)], 1.6)
                if wasApple && c.head == .human { complete("apple") }
                if wasApple {
                    let at = Farm.appleTree
                    let aa = rng.range(0, 6.28), d = rng.range(1, 2.5)
                    addProp(Prop(.apple, at: V3(at.x + cosf(aa) * d, 4, at.z + sinf(aa) * d)))
                } else if wasPumpkin {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in self?.addProp(Prop(.pumpkin, at: home + V3(0, 0.5, 0))) }
                }
            } else if c.head.def.eat == .bite {
                eatT = 0.5; eatCool = 0.6
                audio.play("peck", volume: 0.6, rate: 0.6)
                for n in npcs where inFront(n.pos, range: 1.2) {
                    if n.kind == .farmer { n.say("YOW! It BIT me!", 2); n.state = .scared; n.timer = 3; complete("scare") } else { n.flee(from: pos) }
                }
            } else {
                hintOnce("Find an apple under the apple tree to eat")
                eatCool = 0.5
            }
        case .peck:
            eatT = 0.7; eatCool = 0.6
            audio.play("peck", volume: 0.7)
            let mouth = pos + forward * (body.radius + 0.4)
            if let i = world.cornPiles.firstIndex(where: { $0.left > 0 && simd_length(SIMD2($0.pos.x - mouth.x, $0.pos.z - mouth.z)) < 1.4 }) {
                world.cornPiles[i].left -= 1
                let kids = world.cornPiles[i].node.childNodes.filter { !$0.isHidden }
                for k in kids.prefix(2) { k.isHidden = true }
                if world.cornPiles[i].left == 0 {
                    let idx = i
                    DispatchQueue.main.asyncAfter(deadline: .now() + 40) { [weak self] in
                        guard let self else { return }
                        self.world.cornPiles[idx].left = 20
                        for k in self.world.cornPiles[idx].node.childNodes { k.isHidden = false }
                    }
                }
                save.corn += 1
                stat("Things eaten")
            } else {
                hintOnce("Peck at the corn in the chicken run", 1.8)
            }
        case .graze:
            if surface == .grass && grounded {
                eatT = 1.6; eatCool = 1.7
                audio.play("rip", volume: 0.6)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.audio.play("munch", volume: 0.6, rate: 0.85) }
                if c.head == .cow {
                    save.graze += 1
                    stat("Things eaten")
                }
            } else {
                hintOnce("Find some grass to graze on", 1.8)
                eatCool = 0.5
            }
        }
    }

    // MARK: Q

    func legsAction() {
        guard legsCool < 0, !climbing else { return }
        let c = body.combo
        switch c.legs.legAbility {
        case .backflip:
            guard grounded else { return }
            vel.y = 7.2
            grounded = false
            flipT = 0; flipAngle = 0
            legsCool = 1.1
            audio.play("jump", volume: 0.4)
            audio.play("whoosh", volume: 0.5, rate: 1.3)
            carryDrop()
        case .egg:
            guard grounded, layT < 0 else { return }
            layT = 0; legsCool = 2.2
            audio.play(c.head == .chicken || c.head.def.plan == .bird ? "bawk" : "hmph", volume: 0.9, rate: c.head == .chicken ? 1 : 0.85)
        case .buck:
            kickT = 1; legsCool = 1.0
            var hit = false
            for p in props where inFront(p.pos, range: 2.4, cone: 0.2, behind: true) {
                p.vel += -forward * 11 + V3(0, 5, 0); hit = true
                if p === ball { ballKickFrom = p.pos }
                if p.kind == .egg { smashEgg(p) }
            }
            for n in npcs where inFront(n.pos, range: 2.4, cone: 0.2, behind: true) {
                n.knock(-SIMD2(sinf(yaw), cosf(yaw)), 5); hit = true
                if n.kind == .farmer { complete("tackle") }
            }
            if blast(from: pos + V3(0, 0.3, 0), dir: -forward, range: 2.6 + body.radius, strength: 12) { hit = true }
            audio.play(hit ? "kick" : "whoosh", volume: hit ? 0.9 : 0.5, rate: hit ? 0.8 : 1)
            if hit { complete("buck") }
        case .pounce, .leap:
            guard grounded else { return }
            let leap = c.legs.legAbility == .leap
            vel.y = leap ? 8.5 : 5.5
            vel.x += forward.x * (leap ? 5 : 7); vel.z += forward.z * (leap ? 5 : 7)
            grounded = false
            legsCool = 1.0
            audio.play("jump", volume: 0.5)
            audio.play("whoosh", volume: 0.5, rate: leap ? 0.9 : 1.2)
            if !leap {
                pounceT = 0.8
            }
        case .dash:
            vel.x += forward.x * 8; vel.z += forward.z * 8
            _ = blast(from: pos, dir: forward, range: 2 + body.radius, strength: 6)
            legsCool = 0.9
            audio.play("whoosh", volume: 0.45, rate: 1.6)
        }
    }
}
