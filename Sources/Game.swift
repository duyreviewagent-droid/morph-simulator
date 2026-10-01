import SceneKit
import SpriteKit
import simd

struct Challenge { let id: String; let title: String; let hint: String }

let challenges: [Challenge] = [
    Challenge(id: "mix", title: "Mix It Up", hint: "Morph into any mixed creature (keys 1, 2, 3)"),
    Challenge(id: "chicken", title: "Winner Winner", hint: "Become a full chicken"),
    Challenge(id: "cow", title: "Holy Cow", hint: "Become a full cow"),
    Challenge(id: "combos10", title: "Collector", hint: "Discover 10 different combos"),
    Challenge(id: "zoo25", title: "Zoologist", hint: "Try out 25 different animals"),
    Challenge(id: "zoo100", title: "Noah's Ark", hint: "Try out all 100 animals"),
    Challenge(id: "hover", title: "Buzz Off", hint: "Fly 5 m up with insect or hummingbird wings (hold SPACE)"),
    Challenge(id: "globe", title: "Globetrotter", hint: "Visit all 10 maps (B for maps)"),
    Challenge(id: "swim", title: "Deep End", hint: "Swim in deep water"),
    Challenge(id: "native1", title: "Blend In: Savanna", hint: "Be a whole savanna animal on the Savanna"),
    Challenge(id: "native2", title: "Blend In: Arctic", hint: "Be a whole arctic animal in the Arctic"),
    Challenge(id: "native3", title: "Blend In: Jungle", hint: "Be a whole jungle animal in the Jungle"),
    Challenge(id: "native4", title: "Blend In: Desert", hint: "Be a whole desert animal in the Desert"),
    Challenge(id: "native5", title: "Blend In: Beach", hint: "Be a whole sea or beach animal at the Beach"),
    Challenge(id: "native6", title: "Blend In: Forest", hint: "Be a whole forest animal in the Forest"),
    Challenge(id: "native7", title: "Blend In: Mountains", hint: "Be a whole mountain animal in the Mountains"),
    Challenge(id: "native8", title: "Blend In: Swamp", hint: "Be a whole swamp animal in the Swamp"),
    Challenge(id: "native9", title: "Blend In: City Park", hint: "Be a whole park animal in the City Park"),
    Challenge(id: "pyramid", title: "Pharaoh", hint: "Stand on top of the desert pyramid"),
    Challenge(id: "dressup", title: "Dressed Up", hint: "Wear an add-on on head, body and legs at once (keys 4 5 6)"),
    Challenge(id: "jetpack", title: "Liftoff", hint: "Fly 20 m up with a jetpack"),
    Challenge(id: "chaos500", title: "Troublemaker", hint: "Score 500 chaos by knocking stuff over"),
    Challenge(id: "chaos5000", title: "Menace to Society", hint: "Score 5,000 chaos"),
    Challenge(id: "boom", title: "Kaboom", hint: "Blow up an explosive red barrel"),
    Challenge(id: "strike", title: "Strike!", hint: "Knock down all 10 bowling pins"),
    Challenge(id: "dominoes", title: "Domino Effect", hint: "Topple every domino in a line"),
    Challenge(id: "egg", title: "Egg-cellent", hint: "Lay an egg (chicken legs + Q)"),
    Challenge(id: "nest", title: "Nest Egg", hint: "Lay an egg inside the chicken run"),
    Challenge(id: "eggtoss", title: "Egg Toss", hint: "Throw an egg with human arms (E)"),
    Challenge(id: "glide", title: "Wings!", hint: "Glide 15 m in one go (chicken body, hold SPACE)"),
    Challenge(id: "silo", title: "Leap of Faith", hint: "Glide off the top of the silo"),
    Challenge(id: "roof", title: "Roof Walker", hint: "Stand on the barn roof"),
    Challenge(id: "mooback", title: "Moo Back", hint: "Moo near the cows and get an answer"),
    Challenge(id: "herd", title: "Join the Herd", hint: "Be a full cow with 3 cows around you"),
    Challenge(id: "flock", title: "Flock Leader", hint: "Get 3 chickens to follow you (cluck as a chicken)"),
    Challenge(id: "howdy", title: "Howdy", hint: "Chat with the farmer as a full human (F)"),
    Challenge(id: "scare", title: "What in Tarnation", hint: "Let the farmer see your mixed-up body"),
    Challenge(id: "tackle", title: "Down He Goes", hint: "Knock the farmer over"),
    Challenge(id: "stampede", title: "Stampede", hint: "Gallop on cow legs for 6 seconds (SHIFT)"),
    Challenge(id: "pumpkin", title: "Pumpkin Toss", hint: "Throw a pumpkin 8 m"),
    Challenge(id: "buck", title: "Buck It", hint: "Buck-kick something with cow legs (Q)"),
    Challenge(id: "flip", title: "Backflip", hint: "Land a backflip on human legs (Q)"),
    Challenge(id: "graze", title: "Grazer", hint: "Graze grass 10 times with a cow head (R)"),
    Challenge(id: "corn", title: "Corn Fed", hint: "Peck 15 bits of corn with a chicken head (R)"),
    Challenge(id: "splash", title: "Splash", hint: "Wade into the pond"),
    Challenge(id: "apple", title: "An Apple a Day", hint: "Eat an apple with a human head (R)"),
    Challenge(id: "goal", title: "Farmyard Football", hint: "Kick the ball 15 m"),
]

/// Progress persisted in UserDefaults.
struct SaveData {
    static var disabled = false
    var done: Set<String> = []
    var combos: Set<Int> = []
    var combo = 0
    var musicOn = true
    var graze = 0, corn = 0, eggs = 0
    var tried: Set<Int> = [0]
    var map = 0
    var visited: Set<Int> = [0]
    var addOns = [0, 0, 0]
    var chaos = 0
    var stats: [String: Double] = [:]

    static func load() -> SaveData {
        var s = SaveData()
        guard !disabled else { return s }
        let d = UserDefaults.standard
        s.done = Set(d.stringArray(forKey: "morph2.done") ?? [])
        s.combos = Set((d.array(forKey: "morph2.combos") as? [Int]) ?? [])
        s.combo = d.integer(forKey: "morph2.combo")
        if d.object(forKey: "morph2.music") != nil { s.musicOn = d.bool(forKey: "morph2.music") }
        s.graze = d.integer(forKey: "morph2.graze"); s.corn = d.integer(forKey: "morph2.corn"); s.eggs = d.integer(forKey: "morph2.eggs")
        s.tried = Set((d.array(forKey: "morph2.tried") as? [Int]) ?? [0])
        s.map = min(Maps.all.count - 1, max(0, d.integer(forKey: "morph2.map")))
        s.visited = Set((d.array(forKey: "morph2.visited") as? [Int]) ?? [0])
        s.chaos = d.integer(forKey: "morph2.chaos")
        s.stats = (d.dictionary(forKey: "morph2.stats") as? [String: Double]) ?? [:]
        if let a = d.array(forKey: "morph2.addons") as? [Int], a.count == 3 { s.addOns = a.map { max(0, min(11, $0)) } }
        return s
    }
    func store() {
        guard !SaveData.disabled else { return }
        let d = UserDefaults.standard
        d.set(Array(done), forKey: "morph2.done")
        d.set(Array(combos), forKey: "morph2.combos")
        d.set(combo, forKey: "morph2.combo")
        d.set(musicOn, forKey: "morph2.music")
        d.set(graze, forKey: "morph2.graze"); d.set(corn, forKey: "morph2.corn"); d.set(eggs, forKey: "morph2.eggs")
        d.set(Array(tried), forKey: "morph2.tried")
        d.set(map, forKey: "morph2.map")
        d.set(Array(visited), forKey: "morph2.visited")
        d.set(addOns, forKey: "morph2.addons")
        d.set(chaos, forKey: "morph2.chaos")
        d.set(stats, forKey: "morph2.stats")
    }
}

final class Game: NSObject, SCNSceneRendererDelegate, NPCHost {
    enum Mode { case title, play, paused, morph, challenges, maps }

    let view: GameView
    let scene = SCNScene()
    let camNode = SCNNode(), camera = SCNCamera(), sunNode = SCNNode()
    var world: World
    var mapIndex = 0
    var titleMap = 0
    var pendingMap = -1
    var swimming = false
    let hud = HUD()
    let audio: AudioSystem
    var save = SaveData.load()
    var backing: CGFloat = 2
    var ignoreInput = false
    var mode: Mode = .title

    // player
    var body: Body
    var pos = V3(2, 0, 7)
    var vel = V3.zero
    var yaw: Float = .pi
    var grounded = true
    var groundTag = ""
    var surface: Surface = .grass
    var pose = Pose()
    var phase: Float = 0
    var flapsLeft = 3
    var gliding = false
    var glideStart = V3.zero
    var climbing = false
    var climbAcc: Float = 0
    var carrying: Prop?
    var throwT: Float = -1
    var shoveT: Float = 0
    var talkT: Float = 0
    var eatT: Float = 0
    var kickT: Float = 0
    var layT: Float = -1
    var flipT: Float = -1
    var flipAngle: Float = 0
    var voiceCool: Float = 0, actionCool: Float = 0, eatCool: Float = 0, legsCool: Float = 0
    var stampedeT: Float = 0
    var hoverSnd: Float = 0
    var pounceT: Float = 0
    var hitCache: [(z: Float, r: Float)] = []
    var flightMode = 0
    var rocketReady = true
    var boostT: Float = 0
    var hurtT: Float = 3
    var inWater = false
    var lastFootPhase: Float = 0
    var airTime: Float = 0
    var fallSpeed: Float = 0
    var playerSpeech: String?
    var playerSpeechT: Float = 0
    var hintText = ""
    var hintT: Float = 0
    var morphSlot = 0
    var morphCursor = 0
    var morphSearch = ""

    // camera
    var camYaw: Float = .pi
    var camPitch: Float = 0.32
    var zoom: Float = 1
    var camPos = V3(0, 3, 12)
    var camLook = V3.zero
    var devCam: V3?
    var devLook: V3?
    var devAct: String?
    var fpsLog = false
    private var fpsAcc: Double = 0, fpsN = 0

    var props: [Prop] = []
    var sunLight: SCNLight!
    let pusher = SCNNode()
    var physTest: SCNNode?
    var boomTested = false
    var pusherShape = V3.zero
    var knockCool: [ObjectIdentifier: Float] = [:]
    var chaosStreak = 0
    var chaosStreakT: Float = 0
    var lastTackle: Float = -9
    var lastScare: Float = -9
    var npcs: [NPC] = []
    let propRoot = SCNNode(), npcRoot = SCNNode(), fxRoot = SCNNode()
    var time: Double = 0
    private var lastT: Double?
    private var saveTimer: Float = 0
    var ball: Prop?
    var ballKickFrom: V3?
    var feather: SCNParticleSystem!, fur: SCNParticleSystem!, skinPuff: SCNParticleSystem!, dust: SCNParticleSystem!, yolk: SCNParticleSystem!, water: SCNParticleSystem!, sparkle: SCNParticleSystem!
    var rng = RNG(UInt64(Date().timeIntervalSince1970))

    init(view: GameView, muted: Bool) {
        self.view = view
        audio = AudioSystem(muted: muted)
        let startMap = SaveData.disabled ? 0 : SaveData.load().map
        world = World(map: startMap)
        mapIndex = startMap
        titleMap = startMap
        body = Body(Combo(index: 0))
        super.init()
        setupScene()
        view.scene = scene
        view.delegate = self
        view.pointOfView = camNode
        view.overlaySKScene = hud.scene
        view.antialiasingMode = CommandLine.arguments.contains("--noaa") ? .none : .multisampling4X
        view.preferredFramesPerSecond = 60
        view.isPlaying = true
        view.backgroundColor = .black
        audio.music.on = save.musicOn ? 1 : 0
        let c = Combo(index: max(0, save.combo))
        body.setCombo(c)
        body.addOns = save.addOns
        body.applyAddOns()
        save.combos.insert(c.index)
        spawnFor(mapIndex)
        applyMapLook()
        Coats.prewarm()
        enter(.title)
    }

    // MARK: scene

    static let sunDir = simd_normalize(V3(0.5, 0.62, 0.45))

    static func sky(_ m: MapDef = Maps.all[0]) -> CGImage {
        let W = 2048, H = 1024
        return makePixelImage(W, H) { px, py in
            let lon = (Float(px) + 0.5) / Float(W) * 2 * .pi - .pi
            let lat = .pi / 2 - (Float(py) + 0.5) / Float(H) * .pi
            // SceneKit maps the centre of an equirect image to -Z
            let d = V3(sinf(lon) * cosf(lat), sinf(lat), -cosf(lon) * cosf(lat))
            let sd = m.sunDir
            let cosSun = simd_dot(d, sd)
            let up = max(0, d.y)
            let zen = m.zenith, hor = m.horizon, warm = V3(1.0, 0.85, 0.62)
            var c = mix3(hor, zen, powf(up, 0.5))
            c = mix3(c, warm, powf(max(0, cosSun), 8) * 0.45 * (1 - up * 0.5))
            c += V3(1, 0.9, 0.7) * powf(max(0, cosSun), 200) * 0.7
            if cosSun > 0.9995 { c = V3(1, 0.98, 0.92) }
            if d.y > 0 {
                let cx = d.x / (d.y + 0.12), cz = d.z / (d.y + 0.12)
                let cl = Noise.fbm(cx * 1.1, cz * 1.1, octaves: 6, seed: 5)
                let cover = smoothstep(0.1, 0.45, cl - (m.clouds - 1) * 0.12) * smoothstep(0.0, 0.1, d.y) * (1 - smoothstep(0.4, 0.85, d.y)) * min(1, m.clouds)
                let shade = Noise.fbm(cx * 1.1 + 0.08, cz * 1.1 + 0.08, octaves: 5, seed: 5)
                let lit = mix3(V3(0.66, 0.68, 0.74), V3(1.0, 0.97, 0.92), clampf(0.55 + (cl - shade) * 5 + cosSun * 0.3, 0, 1))
                c = mix3(c, lit, cover * 0.9)
            } else {
                c = mix3(hor * 0.9, m.hills * 0.8 + hor * 0.2, smoothstep(0, 0.2, -d.y))
            }
            return SIMD4(c.x, c.y, c.z, 1)
        }
    }

    private func setupScene() {
        camera.zNear = 0.08
        camera.zFar = 1500
        camera.fieldOfView = 58
        camera.wantsHDR = true
        camera.wantsExposureAdaptation = false
        camera.exposureOffset = -0.15
        camera.bloomIntensity = 0.45
        camera.bloomThreshold = 0.95
        camera.bloomBlurRadius = 10
        camera.vignettingIntensity = 0.45
        camera.vignettingPower = 0.8
        camera.saturation = 1.12
        camera.contrast = 0.15
        camera.screenSpaceAmbientOcclusionIntensity = 0.8
        camera.screenSpaceAmbientOcclusionRadius = 0.5
        camera.screenSpaceAmbientOcclusionBias = 0.03
        camera.screenSpaceAmbientOcclusionDepthThreshold = 0.25
        camera.screenSpaceAmbientOcclusionNormalThreshold = 0.3
        camNode.camera = camera
        scene.rootNode.addChildNode(camNode)

        scene.lightingEnvironment.intensity = 1.35
        scene.fogColor = color(0.78, 0.83, 0.86)
        scene.fogStartDistance = 70
        scene.fogEndDistance = 520
        scene.fogDensityExponent = 1.2

        let sun = SCNLight()
        sun.type = .directional
        sun.intensity = 2400
        sun.color = color(1.0, 0.93, 0.82)
        sun.castsShadow = true
        sun.shadowMapSize = CGSize(width: 4096, height: 4096)
        sun.shadowCascadeCount = 2
        sun.shadowCascadeSplittingFactor = 0.6
        sun.maximumShadowDistance = 120
        sun.automaticallyAdjustsShadowProjection = true
        sun.shadowSampleCount = 8
        sun.shadowRadius = 2.5
        sun.shadowBias = 0.5
        sun.shadowColor = NSColor(white: 0, alpha: 0.78)
        sunNode.light = sun
        sunNode.simdOrientation = simd_quatf(from: V3(0, 0, -1), to: -Game.sunDir)
        scene.rootNode.addChildNode(sunNode)

        scene.rootNode.addChildNode(world.root)
        sunLight = sun
        let a = CommandLine.arguments
        if a.contains("--nossao") { camera.screenSpaceAmbientOcclusionIntensity = 0 }
        if a.contains("--noshadow") { sun.castsShadow = false }
        if a.contains("--nograss") { world.grassRoot.isHidden = true }
        for n in [propRoot, npcRoot, fxRoot, pusher] { scene.rootNode.addChildNode(n) }
        scene.rootNode.addChildNode(body.root)

        func ps(_ size: CGFloat, _ c: NSColor, life: CGFloat, vel: CGFloat, spread: CGFloat, grav: Float, image: CGImage? = nil, spin: Bool = false) -> SCNParticleSystem {
            let s = SCNParticleSystem()
            s.loops = false
            s.birthRate = 0
            s.emissionDuration = 0.05
            s.particleLifeSpan = life
            s.particleLifeSpanVariation = life * 0.4
            s.particleSize = size
            s.particleSizeVariation = size * 0.5
            s.particleImage = image ?? softDotImage(size: 32)
            s.particleColor = c
            s.particleColorVariation = SCNVector4(0.03, 0.1, 0.1, 0)
            s.particleVelocity = vel
            s.particleVelocityVariation = vel * 0.6
            s.spreadingAngle = spread
            s.acceleration = SCNVector3(0, CGFloat(grav), 0)
            s.blendMode = .alpha
            s.isLightingEnabled = true
            s.dampingFactor = 1.5
            if spin { s.particleAngularVelocity = 180; s.particleAngularVelocityVariation = 360; s.particleAngleVariation = 180 }
            s.propertyControllers = [.opacity: SCNParticlePropertyController(animation: {
                let a = CAKeyframeAnimation(); a.values = [1, 0.9, 0]; a.keyTimes = [0, 0.6, 1]; return a }())]
            return s
        }
        let featherImg = makePixelImage(32, 64) { x, y in
            let u = (Float(x) + 0.5) / 32 * 2 - 1, v = (Float(y) + 0.5) / 64
            let w = sinf(.pi * v) * 0.8
            let a = smoothstep(w, w - 0.15, abs(u)) * (abs(u) < 0.06 ? 0.6 : 1)
            return SIMD4(1, 1, 1, a)
        }
        feather = ps(0.07, color(0.55, 0.25, 0.1), life: 2.2, vel: 2.5, spread: 180, grav: -0.8, image: featherImg, spin: true)
        fur = ps(0.12, color(0.15, 0.14, 0.13), life: 1.0, vel: 2, spread: 180, grav: -2)
        skinPuff = ps(0.5, color(1, 0.95, 0.9, 0.5), life: 0.8, vel: 1.2, spread: 180, grav: 0.5)
        dust = ps(0.5, color(0.55, 0.48, 0.38, 0.4), life: 1.0, vel: 1.2, spread: 80, grav: 0.2)
        yolk = ps(0.06, color(0.98, 0.72, 0.1), life: 0.8, vel: 2, spread: 70, grav: -9)
        water = ps(0.1, color(0.75, 0.85, 0.9, 0.7), life: 0.9, vel: 3.5, spread: 35, grav: -9)
        sparkle = ps(0.1, color(1, 0.95, 0.7), life: 0.6, vel: 2.2, spread: 180, grav: 0)
        sparkle.blendMode = .additive
        sparkle.isLightingEnabled = false
    }

    func burst(_ s: SCNParticleSystem, at p: V3, count: Int) {
        let n = SCNNode()
        n.simdPosition = p
        fxRoot.addChildNode(n)
        let c = s.copy() as! SCNParticleSystem
        c.birthRate = CGFloat(count) / c.emissionDuration
        n.addParticleSystem(c)
        n.runAction(.sequence([.wait(duration: 3), .removeFromParentNode()]))
    }

    func applyMapLook() {
        let m = world.map
        let sky = Game.sky(m)
        scene.background.contents = sky
        scene.lightingEnvironment.contents = sky
        scene.fogColor = color(m.fog)
        scene.fogStartDistance = CGFloat(m.fogStart)
        scene.fogEndDistance = CGFloat(m.fogEnd)
        sunLight.color = color(m.sunColor)
        sunLight.intensity = CGFloat(m.sunIntensity)
        sunNode.simdOrientation = simd_quatf(from: V3(0, 0, -1), to: -m.sunDir)
    }

    func spawnFor(_ i: Int) {
        if i == 0 { spawn(); return }
        let m = Maps.all[i]
        var rr = RNG(UInt64(i * 101))
        var k = 0
        for name in m.natives {
            guard let id = Zoo.defs.firstIndex(where: { $0.name == name }) else { continue }
            let sp = Species(id: id)
            let aquatic = sp.def.plan == .fish || sp.def.plan == .tentacle
            let count = sp.def.size > 1.2 ? 2 : 3
            let spots = aquatic ? MapBuilder.spots(world, 60, seed: UInt64(i * 7 + k), r0: 8, r1: 200, dry: false).filter { world.waterLevel($0.0, $0.1) != nil && world.terrain($0.0, $0.1) < (m.waterLevel ?? 0) - 0.8 }
                                : MapBuilder.spots(world, count, seed: UInt64(i * 13 + k), r0: 10, r1: 140)
            for (x, z) in spots.prefix(count) {
                let n = NPC(critter: sp, at: V3(x, world.terrain(x, z), z), seed: rr.next())
                n.host = self
                npcs.append(n)
                npcRoot.addChildNode(n.body.root)
            }
            k += 1
        }
        // a ball to kick and some fruit to eat near where you start
        let sp = m.spawn
        let b = Prop(.ball, at: V3(sp.x + 3, world.terrain(sp.x + 3, sp.z + 3) + 0.2, sp.z + 3))
        addProp(b); ball = b
        for j in 0..<4 {
            let x = sp.x - 3 + Float(j), z = sp.z + 4
            addProp(Prop(.apple, at: V3(x, world.terrain(x, z) + 0.1, z)))
        }
    }

    /// Swaps the whole world for another map.
    func loadMap(_ i: Int) {
        carrying = nil
        for n in npcs { n.body.root.removeFromParentNode() }
        npcs.removeAll()
        for p in props { p.node.removeFromParentNode() }
        props.removeAll()
        ball = nil; ballKickFrom = nil
        fxRoot.childNodes.forEach { $0.removeFromParentNode() }
        world.root.removeFromParentNode()
        world = World(map: i)
        scene.rootNode.insertChildNode(world.root, at: 0)
        if CommandLine.arguments.contains("--nograss") { world.grassRoot.isHidden = true }
        mapIndex = i
        titleMap = i
        applyMapLook()
        spawnFor(i)
        let sp = world.map.spawn
        pos = V3(sp.x, world.ground(sp.x, sp.z, y: 100, r: 0.3).0, sp.z)
        vel = .zero; grounded = true; climbing = false; gliding = false
        camPos = pos + V3(0, 3, 6); camLook = pos
        save.map = i
        save.visited.insert(i)
        if save.visited.count >= Maps.all.count { complete("globe") }
        save.store()
        hud.toast(world.map.name.uppercased(), world.map.blurb, color: color(0.7, 1, 0.75))
    }

    private func spawn() {
        var rr = RNG(5)
        for k in 0..<6 {
            let n = NPC(.hen, at: V3(rr.range(13, 23), 0, rr.range(-19, -10)), seed: UInt64(k * 7 + 1))
            npcs.append(n)
        }
        npcs.append(NPC(.rooster, at: V3(18, 0, -13), seed: 99))
        for k in 0..<5 {
            npcs.append(NPC(.cow, at: V3(rr.range(40, 70), 0, rr.range(-15, 28)), seed: UInt64(200 + k)))
        }
        npcs.append(NPC(.farmer, at: V3(-4, 0, 19), seed: 300))
        for n in npcs { n.host = self; npcRoot.addChildNode(n.body.root) }

        let pp = Farm.pumpkinPatch
        for k in 0..<8 {
            let x = pp.x - 4 + Float(k % 4) * 2.6 + rr.range(-0.4, 0.4), z = pp.z - 1.8 + Float(k / 4) * 3.4 + rr.range(-0.4, 0.4)
            addProp(Prop(.pumpkin, at: V3(x, Farm.height(x, z) + 0.26, z)))
        }
        for _ in 0..<6 {
            let a = rr.range(0, 6.28), d = rr.range(1, 2.6)
            let x = Farm.appleTree.x + cosf(a) * d, z = Farm.appleTree.z + sinf(a) * d
            addProp(Prop(.apple, at: V3(x, Farm.height(x, z) + 0.05, z)))
        }
        let b = Prop(.ball, at: V3(4, 0.11, 9))
        addProp(b); ball = b
        for (x, z) in [(Float(36.5), Float(5.5)), (-9, -8.5), (12.5, -6.5)] { addProp(Prop(.bucket, at: V3(x, Farm.height(x, z) + 0.15, z))) }
    }

    func addProp(_ p: Prop) { props.append(p); propRoot.addChildNode(p.node) }

    // MARK: modes

    func enter(_ m: Mode) {
        mode = m
        switch m {
        case .title:
            hud.setMode(.title)
            audio.music.mood = .menu
        case .play:
            hud.setMode(.play)
            audio.music.mood = .play
        case .paused: hud.setMode(.paused)
        case .morph:
            hud.setMode(.morph)
            morphCursor = body.combo[Slot(rawValue: morphSlot)!].id
        case .maps:
            hud.setMode(.maps)
            hud.showMaps(current: mapIndex, visited: save.visited)
        case .challenges:
            hud.setMode(.challenges)
            hud.showChallenges(statRows())
        }
    }

    // MARK: NPCHost

    var playerPos: V3 { pos }
    var playerCombo: Combo { body.combo }
    var playerSpeed: Float { simd_length(SIMD2(vel.x, vel.z)) }
    var playerRadius: Float { body.radius }

    func sfx(_ name: String, at p: V3, vol: Float, rate: Float) {
        let d = simd_length(p - camPos)
        let att = min(1, 6 / (d + 3)) * max(0, 1 - d / 90)
        let right = simd_normalize(simd_cross(camLook - camPos, V3(0, 1, 0)))
        let dir = d > 0.01 ? (p - camPos) / d : V3.zero
        audio.play(name, volume: vol * att * 1.6, pan: simd_dot(dir, right) * 0.8, rate: rate)
    }

    func npcSays(_ npc: NPC, _ text: String, _ secs: Float) { npc.speech = text; npc.speechT = secs }
    func cowReplied() { if mode == .play { complete("mooback") } }
    func farmerScared() { if Float(time) - lastScare > 2 { lastScare = Float(time); stat("Farmer scared") } }
    func farmerGreeted() {}

    // MARK: progress

    /// No achievements: game events just feed the stats page.
    func complete(_ id: String) {
        switch id {
        case "tackle": if Float(time) - lastTackle > 1.5 { lastTackle = Float(time); stat("Farmer knocked over") }
        case "boom": stat("Barrels exploded")
        default: break
        }
    }
    func stat(_ key: String, _ n: Double = 1) { save.stats[key, default: 0] += n }

    func statRows() -> [ChallengeRow] {
        let st = save.stats
        func v(_ k: String) -> Int { Int(st[k] ?? 0) }
        let secs = Int(st["Time played"] ?? 0)
        let rows: [(String, String)] = [
            ("Time played", String(format: "%dh %02dm", secs / 3600, (secs / 60) % 60)),
            ("Distance walked", String(format: "%.1f km", (st["Distance walked"] ?? 0) / 1000)),
            ("Distance flown / glided", "\(v("Distance flown")) m"),
            ("Highest point reached", "\(v("Highest point")) m"),
            ("Jumps", grouped(v("Jumps"))),
            ("Morphs", grouped(v("Morphs"))),
            ("Animals tried", "\(save.tried.count) of \(Species.count)"),
            ("Different mixes made", grouped(save.combos.count)),
            ("Maps visited", "\(save.visited.count) of \(Maps.all.count)"),
            ("Things knocked over", grouped(v("Things knocked over"))),
            ("Barrels exploded", grouped(v("Barrels exploded"))),
            ("Eggs laid", grouped(save.eggs)),
            ("Farmer scared", grouped(v("Farmer scared"))),
            ("Farmer knocked over", grouped(v("Farmer knocked over"))),
            ("Times swum", grouped(v("Swims"))),
            ("Things thrown", grouped(v("Things thrown"))),
            ("Things eaten", grouped(v("Things eaten"))),
            ("Current look", body.combo.recipe),
        ]
        return rows.map { ChallengeRow(title: $0.0, hint: $0.1, done: false) }
    }

    func say(_ s: String, _ secs: Float = 2.2) { playerSpeech = s; playerSpeechT = secs }
    func hintOnce(_ s: String, _ secs: Float = 2.5) { hintText = s; hintT = secs }

    // MARK: morph

    func morph(_ slot: Slot, to s: Species) {
        guard body.combo[slot] != s else { return }
        if let c = carrying, slot == .torso && s.torsoAbility != .grab { c.held = false; c.vel = vel; carrying = nil }
        if climbing && slot == .torso && s.torsoAbility != .grab { climbing = false }
        body.set(slot, s)
        let c = body.combo
        audio.play("morph", volume: 0.8, rate: 1)
        audio.play("poof", volume: 0.5)
        let at = pos + V3(0, slot == .legs ? body.legs.attach.y * 0.6 : slot == .torso ? body.legs.attach.y + 0.3 : body.height - 0.2, 0)
        burst(skinPuff, at: at, count: 20)
        switch s.def.coat {
        case .feathers: burst(feather, at: at, count: 26)
        case .fur, .holstein, .wool, .spots, .rosettes, .stripes, .patches, .cells, .bands, .quills: burst(fur, at: at, count: 20)
        default: burst(sparkle, at: at, count: 20)
        }
        if slot == .head {
            let snd = s.voiceSound
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in self?.audio.play(snd, volume: 0.55) }
        }
        if !save.tried.contains(s.id) {
            save.tried.insert(s.id)
            if save.tried.count >= 25 { complete("zoo25") }
            if save.tried.count >= Species.count { complete("zoo100") }
        }
        save.combos.insert(c.index)
        stat("Morphs")
        save.combo = c.index
        if !c.isPure { complete("mix") }
        if c.isPure && c.head == .chicken { complete("chicken") }
        if c.isPure && c.head == .cow { complete("cow") }
        if save.combos.count >= 10 { complete("combos10") }
    }

    // MARK: loop

    func renderer(_ renderer: SCNSceneRenderer, updateAtTime t: TimeInterval) {
        let prev: Double = lastT ?? (t - 1.0 / 60)
        let raw: Double = t - prev
        let dt = Float(min(1.0 / 20, max(1.0 / 240, raw)))
        lastT = t
        time += Double(dt)
        hud.now = time
        if fpsLog { fpsAcc += raw; fpsN += 1; if fpsAcc > 3 { print(String(format: "fps %.1f", Double(fpsN) / fpsAcc)); fpsAcc = 0; fpsN = 0 } }
        let f = ignoreInput ? InputState.Frame() : view.input.frame()
        let sz = view.bounds.size
        if sz.width > 10 && (abs(sz.width - hud.size.width) > 0.5 || abs(sz.height - hud.size.height) > 0.5) { hud.layout(sz) }
        if f.pressed(Key.m) {
            save.musicOn.toggle()
            audio.music.on = save.musicOn ? 1 : 0
            save.store()
        }
        switch mode {
        case .title:
            let n = Maps.all.count
            if f.pressed(Key.left) || f.clicks.contains(where: { hud.mapLeftRect.contains($0) }) { titleMap = (titleMap + n - 1) % n; audio.play("click", volume: 0.5) }
            if f.pressed(Key.right) || f.clicks.contains(where: { hud.mapRightRect.contains($0) }) { titleMap = (titleMap + 1) % n; audio.play("click", volume: 0.5) }
            if pendingMap >= 0 {
                loadMap(pendingMap); pendingMap = -1; hud.loading(false)
                enter(.play)
            } else if f.pressed(Key.ret, Key.enter, Key.space) || f.clicks.contains(where: { hud.playRect.contains($0) }) {
                audio.play("select", volume: 0.6, jitter: 0)
                if titleMap != mapIndex { pendingMap = titleMap; hud.loading(true) } else { enter(.play) }
            }
            simulate(dt, f, control: false)
            hud.updateTitle(save.done.count, challenges.count, save.combos.count, map: Maps.all[titleMap])
        case .play:
            if f.pressed(Key.esc) { enter(.paused); audio.play("click", volume: 0.5) }
            else if f.pressed(Key.tab) { enter(.morph); audio.play("click", volume: 0.5) }
            else if f.pressed(Key.j) { enter(.challenges); audio.play("click", volume: 0.5) }
            else if f.pressed(Key.b) { enter(.maps); audio.play("click", volume: 0.5) }
            simulate(dt, f, control: true)
        case .maps:
            if pendingMap >= 0 {
                loadMap(pendingMap); pendingMap = -1; hud.loading(false)
                enter(.play)
                break
            }
            let n = Maps.all.count
            if f.pressed(Key.b, Key.esc) { enter(.play) }
            if f.pressed(Key.left) { titleMap = (titleMap + n - 1) % n; audio.play("click", volume: 0.3) }
            if f.pressed(Key.right) { titleMap = (titleMap + 1) % n; audio.play("click", volume: 0.3) }
            if f.pressed(Key.up) { titleMap = (titleMap + n - 5) % n; audio.play("click", volume: 0.3) }
            if f.pressed(Key.down) { titleMap = (titleMap + 5) % n; audio.play("click", volume: 0.3) }
            for c in f.clicks { if let i = hud.mapHit(c) { titleMap = i; pendingMap = i; hud.loading(true) } }
            if f.pressed(Key.ret, Key.enter, Key.space) { pendingMap = titleMap; hud.loading(true) }
            hud.highlightMap(titleMap)
            hudPlay()
        case .paused:
            if f.pressed(Key.esc) { enter(.play) }
            if f.pressed(Key.t) { save.store(); enter(.title) }
            if f.pressed(Key.b) { enter(.maps) }
            hudPlay()
        case .morph:
            if f.pressed(Key.tab) || (f.pressed(Key.esc) && morphSearch.isEmpty) { enter(.play); audio.play("click", volume: 0.5) }
            if f.pressed(Key.esc) { morphSearch = "" }
            let n = Species.count
            if f.pressed(Key.up) { morphCursor = (morphCursor - 10 + n) % n; audio.play("click", volume: 0.3) }
            if f.pressed(Key.down) { morphCursor = (morphCursor + 10) % n; audio.play("click", volume: 0.3) }
            if f.pressed(Key.left) { morphCursor = (morphCursor - 1 + n) % n; audio.play("click", volume: 0.3) }
            if f.pressed(Key.right) { morphCursor = (morphCursor + 1) % n; audio.play("click", volume: 0.3) }
            for (i, k) in [Key.nums[0], Key.nums[1], Key.nums[2]].enumerated() where f.pressed(k) {
                morphSlot = i; morphCursor = body.combo[Slot(rawValue: i)!].id; morphSearch = ""; audio.play("click", volume: 0.4)
            }
            for (i, k) in [Key.nums[3], Key.nums[4], Key.nums[5]].enumerated() where f.pressed(k) { cycleAddOn(Slot(rawValue: i)!, back: f.down(Key.shift)) }
            // type an animal's name to jump to it
            for ch in f.typed {
                if ch.isLetter || (ch == " " && !morphSearch.isEmpty) {
                    morphSearch.append(Character(ch.lowercased()))
                    if let hit = Game.searchAnimal(morphSearch) { morphCursor = hit.id }
                    audio.play("click", volume: 0.25)
                } else if ch == "\u{7f}" || ch == "\u{8}" {
                    if !morphSearch.isEmpty { morphSearch.removeLast() }
                    if let hit = Game.searchAnimal(morphSearch), !morphSearch.isEmpty { morphCursor = hit.id }
                } else if ch == "0" { randomMorph() }
            }
            if f.pressed(Key.ret, Key.enter) {
                if f.down(Key.shift) { for sl in Slot.allCases { morph(sl, to: Species(id: morphCursor)) } }
                else { morph(Slot(rawValue: morphSlot)!, to: Species(id: morphCursor)) }
                morphSearch = ""
            }
            for c in f.clicks {
                let h = hud.morphHit(c)
                if let a = h.addOn { cycleAddOn(Slot(rawValue: a)!, back: false) }
                if let sl = h.slot { morphSlot = sl; morphCursor = body.combo[Slot(rawValue: sl)!].id; audio.play("click", volume: 0.4) }
                if let t = h.tile { morphCursor = t; morph(Slot(rawValue: morphSlot)!, to: Species(id: t)) }
            }
            // the world keeps turning behind the menu so you can watch yourself morph
            simulate(dt, InputState.Frame(), control: false)
            hud.updateMorph(combo: body.combo, slot: morphSlot, cursor: morphCursor, tried: save.tried, discovered: save.combos, search: morphSearch, addOns: body.addOns)
        case .challenges:
            if f.pressed(Key.j, Key.esc, Key.tab) { enter(.play) }
            hudPlay()
        }
        saveTimer += dt
        if saveTimer > 30 && mode != .title {
            saveTimer = 0
            save.store()
            hud.flashSaved()
        }
    }

    func saveNow() { save.store() }

    private func simulate(_ dt: Float, _ f: InputState.Frame, control: Bool) {
        let t = Float(time)
        updatePlayer(dt, f, control: control)
        if let a = devAct { applyDevAct(a, dt) }
        for n in npcs { n.update(dt, world: world, t: t) }
        updateProps(dt)
        interactions(dt)
        updateKnockables(dt)
        updateCamera(dt, f, control: control)
        world.water?.geometry?.firstMaterial?.normal.contentsTransform = SCNMatrix4Mult(SCNMatrix4MakeScale(18, 18, 1), SCNMatrix4MakeTranslation(CGFloat(t * 0.01), CGFloat(t * 0.013), 0))
        audio.ambience.rush = min(1, max(0, (simd_length(vel) - 3) / 9))
        audio.music.energy = min(1, playerSpeed / 6)
        hudPlay()
    }

    private func hudPlay() {
        guard mode != .title else { hud.setBubbles([]); return }
        if hintT > 0 { hintT -= 1 / 60; if hintT <= 0 { hintText = "" } }
        hud.updatePlay(combo: body.combo, addOns: body.addOns, chaos: save.chaos, abilities: abilities(), done: save.done.count, total: challenges.count, combos: save.combos.count, hintText: contextHint())
        var items: [(CGPoint, String, Bool)] = []
        if let s = playerSpeech {
            let p = view.projectPoint(SCNVector3(pos + V3(0, body.height + 0.25, 0)))
            if p.z < 1 { items.append((CGPoint(x: p.x, y: p.y), s, true)) }
        }
        for n in npcs {
            guard let s = n.speech else { continue }
            let p = view.projectPoint(SCNVector3(n.pos + V3(0, n.body.height * n.scale + 0.3, 0)))
            if p.z < 1 && simd_length(n.pos - camPos) < 40 { items.append((CGPoint(x: p.x, y: p.y), s, false)) }
        }
        hud.setBubbles(items)
    }

    func contextHint() -> String {
        if !hintText.isEmpty { return hintText }
        if climbing { return "W / S to climb  ·  SPACE to let go" }
        if gliding { return "Gliding! Steer with A / D" }
        if let c = carrying { return "E to throw the \(c.kind)" + (c.kind == .apple && body.combo.head == .human ? "  ·  R to eat it" : "") }
        if body.torso.canGrab, let p = nearestProp(1.3) { return "E to pick up the \(p.kind)" }
        if world.ladder(near: pos, r: body.radius) != nil, !climbing { return body.torso.canGrab ? "Walk into the ladder to climb" : "You need human arms to climb ladders" }
        return ""
    }

    // MARK: camera

    private func updateCamera(_ dt: Float, _ f: InputState.Frame, control: Bool) {
        if mode == .title {
            camYaw += dt * 0.12
            camPitch += (0.18 - camPitch) * min(1, dt)
        } else {
            camYaw -= Float(f.drag.x) * 0.006
            camPitch = clampf(camPitch + Float(f.drag.y) * 0.004, -0.25, 1.25)
            if f.down(Key.left) { camYaw += dt * 1.8 }
            if f.down(Key.right) { camYaw -= dt * 1.8 }
            if f.down(Key.up) { camPitch = clampf(camPitch - dt, -0.25, 1.25) }
            if f.down(Key.down) { camPitch = clampf(camPitch + dt, -0.25, 1.25) }
            zoom = clampf(zoom * (1 - Float(f.scroll) * 0.04), 0.45, 2.6)
            if f.pressed(Key.c) { zoom = zoom > 1.5 ? 0.7 : zoom < 0.9 ? 1 : 1.8 }
        }
        let h = body.height
        let target = pos + V3(0, h * 0.78, 0)
        let dist = (2.4 + h * 1.35) * zoom * (mode == .title ? 1.15 : 1)
        let F = V3(sinf(camYaw), 0, cosf(camYaw))
        var cp = target - F * (dist * cosf(camPitch)) + V3(0, dist * sinf(camPitch), 0)
        let gy = world.terrain(cp.x, cp.z) + 0.35
        if cp.y < gy { cp.y = gy }
        let k = min(1, dt * 10)
        camPos += (cp - camPos) * k
        camLook += (target - camLook) * min(1, dt * 14)
        if simd_length(camLook - target) > 8 { camLook = target; camPos = cp }
        if let dc = devCam { camPos = dc; camLook = devLook ?? target }
        camNode.simdPosition = camPos
        camNode.simdLook(at: camLook, up: V3(0, 1, 0), localFront: V3(0, 0, -1))
        // keep the sun's shadow cascades centred on the action
        sunNode.simdPosition = pos
    }

    // MARK: dev hooks

    func devCombo(_ i: Int) { body.setCombo(Combo(index: i)); body.update(pose, dt: 1) }
    func devCombo(_ s: String) {
        let v = s.split(separator: ",").compactMap { Int($0) }
        if v.count == 3 { body.setCombo(Combo(Species(id: v[0] % Species.count), Species(id: v[1] % Species.count), Species(id: v[2] % Species.count))) }
        else if let n = Zoo.defs.firstIndex(where: { $0.name.lowercased() == s.lowercased() }) { body.setCombo(Combo(Species(id: n), Species(id: n), Species(id: n))) }
        else { devCombo(Int(s) ?? 0) }
        body.update(pose, dt: 1)
    }
    /// Best match for a typed name: exact, then prefix, then any word starting with it, then contains.
    static func searchAnimal(_ q: String) -> Species? {
        let q = q.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return nil }
        let names = Zoo.defs.map { $0.name.lowercased() }
        if let i = names.firstIndex(of: q) { return Species(id: i) }
        if let i = names.firstIndex(where: { $0.hasPrefix(q) }) { return Species(id: i) }
        if let i = names.firstIndex(where: { $0.split(separator: " ").contains { $0.hasPrefix(q) } }) { return Species(id: i) }
        if let i = names.firstIndex(where: { $0.contains(q) }) { return Species(id: i) }
        return nil
    }
    func cycleAddOn(_ slot: Slot, back: Bool) {
        let n = 12
        let i = (body.addOns[slot.rawValue] + (back ? n - 1 : 1)) % n
        body.setAddOn(slot, i)
        save.addOns = body.addOns
        let name = AddOns.names(slot)[i]
        audio.play(i == 1 ? "oof" : "pickup", volume: 0.6)
        audio.play("poof", volume: 0.3)
        hintOnce(name == "None" ? "\(slot.name): no add-on" : "\(slot.name) add-on: \(name)" + (AddOns.blurbs[name].map { " — " + $0 } ?? ""), 2.2)
        if i == 1 { say(["Ow!", "Ouch…", "That hurts!"][rng.int(3)], 1.4) }
        if body.addOns.filter({ $0 > 1 }).count == 3 { complete("dressup") }
    }
    func randomMorph() {
        for sl in Slot.allCases { morph(sl, to: Species(id: rng.int(Species.count))) }
    }
    func devScene(_ s: String) {
        switch s {
        case "maps": enter(.play); enter(.maps)
        case "play": enter(.play)
        case "morph": enter(.play); enter(.morph)
        case "challenges": enter(.play); enter(.challenges)
        case "pause": enter(.play); enter(.paused)
        default: enter(.title)
        }
    }
    func devPlace(_ p: V3, yaw y: Float) { pos = p; yaw = y; camYaw = y; camPos = p + V3(-sinf(y) * 5, 3, -cosf(y) * 5) }
}
