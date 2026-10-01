import AVFoundation

/// AVAudioEngine graph. Every sound is synthesised at launch.
final class AudioSystem {
    let engine = AVAudioEngine()
    let format: AVAudioFormat
    let sr: Double
    let ambience: AmbienceSynth
    let music: MusicSynth
    private var players: [AVAudioPlayerNode] = []
    private var speeds: [AVAudioUnitVarispeed] = []
    private var nextPlayer = 0
    private(set) var buffers: [String: AVAudioPCMBuffer] = [:]
    private(set) var variants: [String: Int] = [:]
    /// Trailer recording: every requested one-shot is reported here (even when muted).
    var onPlay: ((String, Float, Float, Float) -> Void)?
    private let queue = DispatchQueue(label: "morph.sfx")
    private(set) var running = false
    var muted = false

    init(muted: Bool = false) {
        self.muted = muted
        let out = engine.outputNode.outputFormat(forBus: 0)
        sr = out.sampleRate > 0 ? out.sampleRate : 48000
        format = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 2)!
        ambience = AmbienceSynth(sampleRate: Float(sr))
        music = MusicSynth(sampleRate: Float(sr))
        let am = ambience, mu = music
        func node(_ render: @escaping (Int, UnsafeMutablePointer<Float>, UnsafeMutablePointer<Float>) -> Void) -> AVAudioSourceNode {
            AVAudioSourceNode(format: format) { _, _, frames, abl -> OSStatus in
                let b = UnsafeMutableAudioBufferListPointer(abl)
                render(Int(frames), b[0].mData!.assumingMemoryBound(to: Float.self), b[1].mData!.assumingMemoryBound(to: Float.self))
                return noErr
            }
        }
        let ambNode = node { am.render(frames: $0, $1, $2) }
        let musNode = node { mu.render(frames: $0, $1, $2) }
        let outdoors = AVAudioUnitReverb()
        outdoors.loadFactoryPreset(.mediumHall)
        outdoors.wetDryMix = 7
        let sfxMix = AVAudioMixerNode()
        for n in [ambNode, musNode, outdoors, sfxMix] as [AVAudioNode] { engine.attach(n) }
        engine.connect(musNode, to: engine.mainMixerNode, format: format)
        engine.connect(ambNode, to: engine.mainMixerNode, format: format)
        engine.connect(sfxMix, to: outdoors, format: format)
        engine.connect(outdoors, to: engine.mainMixerNode, format: format)
        for _ in 0..<32 {
            let p = AVAudioPlayerNode(), vs = AVAudioUnitVarispeed()
            for n in [p, vs] as [AVAudioNode] { engine.attach(n) }
            engine.connect(p, to: vs, format: format)
            engine.connect(vs, to: sfxMix, format: format)
            players.append(p); speeds.append(vs)
        }
        engine.mainMixerNode.outputVolume = muted ? 0 : 0.9
        buildBuffers()
        buildCalls()
        do {
            try engine.start()
            for p in players { p.play() }
            running = true
        } catch {
            NSLog("Morph: audio unavailable: \(error)")
        }
    }

    /// Plays a one-shot. Names with variants ("moo") pick one at random.
    @discardableResult
    func play(_ name: String, volume: Float = 1, pan: Float = 0, jitter: Float = 0.05, rate: Float = 1) -> Int {
        onPlay?(name, volume, pan, rate)
        guard running, !muted else { return -1 }
        var key = name
        if let n = variants[name] { key = "\(name)_\(Int.random(in: 0..<n))" }
        guard let buf = buffers[key] else { return -1 }
        let v = max(0, min(1.5, volume))
        guard v > 0.004 else { return -1 }
        let i = nextPlayer
        nextPlayer = (nextPlayer + 1) % players.count
        queue.async {
            let p = self.players[i]
            self.speeds[i].rate = max(0.25, min(4, rate * (1 + Float.random(in: -jitter...jitter))))
            p.volume = v
            p.pan = max(-1, min(1, pan))
            p.scheduleBuffer(buf, at: nil, options: .interrupts, completionHandler: nil)
            if !p.isPlaying { p.play() }
        }
        return i
    }

    var bufferNames: [String] { buffers.keys.sorted() }
    func buffer(_ name: String) -> AVAudioPCMBuffer? {
        if let n = variants[name] { return buffers["\(name)_\(Int.random(in: 0..<n))"] }
        return buffers[name]
    }

    func selfCheck() -> Bool {
        var bad: [String] = []
        for (k, b) in buffers.sorted(by: { $0.key < $1.key }) {
            var peak: Float = 0
            let L = b.floatChannelData![0]
            for i in 0..<Int(b.frameLength) { if !L[i].isFinite { peak = .nan; break }; peak = max(peak, abs(L[i])) }
            if !(peak > 0.02 && peak < 1.0) { bad.append("\(k)=\(peak)") }
        }
        print(bad.isEmpty ? "PASS sfx buffers (\(buffers.count))" : "FAIL sfx buffers: \(bad.joined(separator: ", "))")
        var ok = bad.isEmpty
        let n = 1024
        let L = UnsafeMutablePointer<Float>.allocate(capacity: n), R = UnsafeMutablePointer<Float>.allocate(capacity: n)
        defer { L.deallocate(); R.deallocate() }
        for rush in [Float(0), 1] {
            let a = AmbienceSynth(sampleRate: Float(sr))
            a.rush = rush
            var p: Float = 0
            for _ in 0..<Int(40 * sr) / n { a.render(frames: n, L, R); for i in 0..<n { p = max(p, abs(L[i]).isFinite ? abs(L[i]) : 99) } }
            let good = p < 0.9 && p > 0.005
            ok = ok && good
            print(String(format: "%@ ambience rush %.0f peak %.3f", good ? "PASS" : "FAIL", rush, p))
        }
        for mood in [MusicMood.menu, .play] {
            let m = MusicSynth(sampleRate: Float(sr))
            m.mood = mood
            var pm: Float = 0, rm: Double = 0, cm = 0
            // 80 s covers the harmonica section of the play loop
            for _ in 0..<Int((mood == .play ? 80 : 20) * sr) / n {
                m.render(frames: n, L, R)
                for i in 0..<n { pm = max(pm, abs(L[i]).isFinite ? abs(L[i]) : 99); rm += Double(L[i] * L[i]); cm += 1 }
            }
            let good = pm < 0.95 && pm > 0.03
            ok = ok && good
            print(String(format: "%@ music %@ peak %.2f rms %.3f", good ? "PASS" : "FAIL", "\(mood)", pm, sqrt(rm / Double(cm))))
        }
        return ok
    }

    // MARK: Synthesis

    private func make(_ dur: Double, norm: Float? = nil, _ gen: (Float) -> (Float, Float)) -> AVAudioPCMBuffer {
        let frames = AVAudioFrameCount(dur * sr)
        let b = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        b.frameLength = frames
        let L = b.floatChannelData![0], R = b.floatChannelData![1]
        let fsr = Float(sr)
        for i in 0..<Int(frames) {
            let (l, r) = gen(Float(i) / fsr)
            L[i] = l.isFinite ? l : 0; R[i] = r.isFinite ? r : 0
        }
        var peak: Float = 0
        for i in 0..<Int(frames) { peak = max(peak, abs(L[i]), abs(R[i])) }
        let want = norm ?? min(0.9, peak)
        if peak > 0 { let g = want / peak; for i in 0..<Int(frames) { L[i] *= g; R[i] *= g } }
        let fade = min(Int(frames), Int(0.006 * sr))
        for k in 0..<fade {
            let g = Float(k) / Float(fade)
            L[Int(frames) - 1 - k] *= g; R[Int(frames) - 1 - k] *= g
        }
        return b
    }

    private func set(_ name: String, _ count: Int, _ gen: (Int) -> AVAudioPCMBuffer) {
        variants[name] = count
        for i in 0..<count { buffers["\(name)_\(i)"] = gen(i) }
    }

    /// A voiced sound: a glottal pulse train through formant resonators. `f0(t)`, formants `fm(t)`
    /// as (F1, F2, F3), amplitude `env(t)`, breathiness `breath`, roughness `rasp`.
    private func voice(_ dur: Double, norm: Float = 0.8, seed: UInt32, breath: Float = 0.08, rasp: Float = 0,
                       f0: @escaping (Float) -> Float, fm: @escaping (Float) -> (Float, Float, Float), env: @escaping (Float) -> Float,
                       nasal: ((Float) -> Float)? = nil) -> AVAudioPCMBuffer {
        var ph: Float = 0
        var nz = Noise32(s: seed)
        var r1 = Reso(), r2 = Reso(), r3 = Reso(), nasalLP = LP1(), raspLP = LP1(), src = LP1()
        let fsr = Float(sr)
        return make(dur, norm: norm) { t in
            let rough = 1 + raspLP.run(nz.next(), f: 90, sr: fsr) * rasp * 6
            var f = f0(t) * (1 + 0.004 * nz.next())
            f *= max(0.5, rough)
            ph += f / fsr
            if ph > 1 { ph -= 1 }
            // Rosenberg-like pulse: open phase then a sharp closure
            let open: Float = 0.6
            var g: Float = ph < open ? (0.5 - 0.5 * cosf(.pi * ph / open)) : cosf(.pi * (ph - open) / (2 * (1 - open)))
            g = g - 0.4
            let s = src.run(g, f: 4000, sr: fsr) + nz.next() * breath
            let (a, b, c) = fm(t)
            var o = r1.run(s, f: a, q: 5, sr: fsr) + r2.run(s, f: b, q: 7, sr: fsr) * 0.6 + r3.run(s, f: c, q: 9, sr: fsr) * 0.25
            if let na = nasal {
                let m = na(t)
                o = mixf(o, nasalLP.run(s, f: 320, sr: fsr) * 1.4, m)
            }
            let v = o * env(t)
            return (v, v)
        }
    }

    private func buildBuffers() {
        let tau: Float = 2 * .pi
        let fsr = Float(sr)

        // MARK: footsteps
        // Boot on grass: a soft heel thud and a swish of blades.
        set("step_shoe", 4) { v in
            var n = Noise32(s: UInt32(10 + v)); var lp = LP1(), bp = Reso()
            var rr = RNG(UInt64(20 + v)); let f = rr.range(70, 95)
            return make(0.22, norm: 0.5) { t in
                let x = n.next()
                let s = sinf(tau * f * t) * expf(-t * 35) * 0.8 + lp.run(x, f: 700, sr: fsr) * expf(-t * 30) * 2.5 + bp.run(x, f: 3500, q: 1, sr: fsr) * expf(-t * 18) * 0.4
                return (s, s)
            }
        }
        // Hoof: a hollow keratin clop.
        set("step_hoof", 4) { v in
            var n = Noise32(s: UInt32(30 + v)); var r1 = Reso(), r2 = Reso(), lp = LP1()
            var rr = RNG(UInt64(40 + v)); let f1 = rr.range(420, 620), f2 = rr.range(1100, 1500)
            return make(0.3, norm: 0.6) { t in
                let x = n.next()
                let s = r1.run(x, f: f1, q: 9, sr: fsr) * expf(-t * 28) * 2.2 + r2.run(x, f: f2, q: 7, sr: fsr) * expf(-t * 45) + sinf(tau * 65 * t) * expf(-t * 22) * 0.9 + lp.run(x, f: 400, sr: fsr) * expf(-t * 20) * 2
                return (s, s)
            }
        }
        // Chicken feet: a light scritch of claws.
        set("step_claw", 4) { v in
            var n = Noise32(s: UInt32(50 + v)); var bp = Reso()
            var rr = RNG(UInt64(60 + v)); let t2 = rr.range(0.025, 0.05)
            return make(0.14, norm: 0.35) { t in
                let x = n.next()
                var s = bp.run(x, f: 4200, q: 2, sr: fsr) * expf(-t * 90) * 1.5
                if t > t2 { s += bp.run(x, f: 3000, q: 2, sr: fsr) * expf(-(t - t2) * 110) }
                s += sinf(tau * 180 * t) * expf(-t * 60) * 0.3
                return (s, s)
            }
        }
        // Boards, hay and sheet metal underfoot.
        set("step_wood", 3) { v in
            var n = Noise32(s: UInt32(70 + v)); var r1 = Reso(), r2 = Reso()
            return make(0.3, norm: 0.55) { t in
                let x = n.next()
                let s = r1.run(x, f: 190 + Float(v) * 20, q: 8, sr: fsr) * expf(-t * 18) * 2 + r2.run(x, f: 820, q: 5, sr: fsr) * expf(-t * 35) * 0.8
                return (s, s)
            }
        }
        set("step_metal", 3) { v in
            var n = Noise32(s: UInt32(80 + v)); var rr = RNG(UInt64(90 + v))
            let modes = (0..<5).map { _ in (rr.range(200, 1400), rr.range(5, 12)) }
            return make(0.6, norm: 0.5) { t in
                var s = n.next() * expf(-t * 80) * 0.5
                for (f, d) in modes { s += sinf(tau * f * t) * expf(-t * d) * 0.25 }
                return (s, s)
            }
        }
        set("step_hay", 3) { v in
            var n = Noise32(s: UInt32(100 + v)); var bp = Reso(), lp = LP1()
            return make(0.3, norm: 0.4) { t in
                let x = n.next()
                let crackle: Float = n.next() > 0.7 ? 1.5 : 0.4
                let s = bp.run(x, f: 2400, q: 0.8, sr: fsr) * crackle * expf(-t * 14) + lp.run(x, f: 300, sr: fsr) * expf(-t * 25) * 2
                return (s, s)
            }
        }
        set("step_splash", 3) { v in
            var n = Noise32(s: UInt32(110 + v)); var bp = Reso(), bp2 = Reso()
            return make(0.45, norm: 0.5) { t in
                let x = n.next()
                let s = bp.run(x, f: 900 + 600 * expf(-t * 8), q: 1.2, sr: fsr) * expf(-t * 9) + bp2.run(x, f: 2600, q: 2, sr: fsr) * expf(-t * 14) * 0.6
                return (s, s)
            }
        }
        set("land", 3) { v in
            var n = Noise32(s: UInt32(120 + v)); var lp = LP1()
            return make(0.4, norm: 0.7) { t in
                let x = n.next()
                let s = sinf(tau * (55 + 50 * expf(-t * 30)) * t) * expf(-t * 12) + lp.run(x, f: 600, sr: fsr) * expf(-t * 16) * 3
                return (s, s)
            }
        }
        buffers["jump"] = {
            var n = Noise32(s: 130); var bp = Reso()
            return make(0.3, norm: 0.4) { t in
                let u = t / 0.3
                let s = bp.run(n.next(), f: 500 + 1400 * u, q: 1.5, sr: fsr) * sinf(.pi * u)
                return (s, s)
            }
        }()
        buffers["splash"] = {
            var n = Noise32(s: 140); var bp = Reso(), lp = LP1(); var rr = RNG(141)
            let drops = (0..<30).map { _ in (rr.range(0.1, 1.2), rr.range(1500, 4500)) }
            // each droplet gets its own filter (a shared one blows up when droplets overlap)
            var dr = [Reso](repeating: Reso(), count: 30)
            return make(1.4, norm: 0.8) { t in
                let x = n.next()
                var s = lp.run(x, f: 800, sr: fsr) * expf(-t * 4) * 3 + bp.run(x, f: 1400, q: 0.8, sr: fsr) * expf(-t * 5)
                s += sinf(tau * (40 + 60 * expf(-t * 10)) * t) * expf(-t * 6) * 0.7
                for (k, (t0, f)) in drops.enumerated() where t > t0 && t < t0 + 0.04 { s += dr[k].run(x, f: f * (1 + (t - t0) * 20), q: 15, sr: fsr) * expf(-(t - t0) * 90) * 0.8 }
                return (s, s * 0.95)
            }
        }()

        // MARK: morphing
        set("morph", 3) { v in
            var n = Noise32(s: UInt32(150 + v)); var bp = Reso(), lp = LP1()
            var rr = RNG(UInt64(160 + v))
            let bubbles = (0..<14).map { _ in (rr.range(0, 0.55), rr.range(200, 900), rr.range(0.03, 0.07)) }
            var ph: Float = 0
            return make(0.75, norm: 0.7) { t in
                let x = n.next()
                // a stretchy wet glide down then up
                let f = 180 + 500 * powf(sinf(.pi * min(1, t / 0.7)), 2) + Float(v) * 40
                ph += f / fsr
                var s = sinf(tau * ph + sinf(tau * ph * 1.5) * 2.2) * sinf(.pi * min(1, t / 0.7)) * 0.35
                s += bp.run(x, f: f * 2, q: 3, sr: fsr) * sinf(.pi * min(1, t / 0.7)) * 0.6
                for (t0, bf, d) in bubbles where t > t0 && t < t0 + d {
                    let u = (t - t0) / d
                    s += sinf(tau * bf * (1 + u * 1.5) * (t - t0)) * sinf(.pi * u) * 0.5
                }
                s += lp.run(x, f: 300, sr: fsr) * expf(-t * 8) * 1.5
                return (s, s * 0.9)
            }
        }
        buffers["poof"] = {
            var n = Noise32(s: 170); var bp = Reso()
            return make(0.5, norm: 0.5) { t in
                let s = bp.run(n.next(), f: 600 + 2500 * expf(-t * 8), q: 1, sr: fsr) * expf(-t * 7) * min(1, t * 200)
                return (s, s)
            }
        }()

        // MARK: animal and human voices
        // Moo: nasal "mmm" opening into a long "ooo-aww" with a rising, then sagging, pitch.
        set("moo", 4) { v in
            var rr = RNG(UInt64(200 + v))
            let base = rr.range(88, 118), rise = rr.range(1.25, 1.5), dur = rr.range(1.2, 1.9)
            return voice(Double(dur), norm: 0.8, seed: UInt32(210 + v), breath: 0.05, rasp: 0.18,
                         f0: { t in let u = t / dur; return base * (1 + (rise - 1) * smoothstep(0, 0.25, u) - 0.22 * smoothstep(0.5, 1, u)) * (1 + 0.012 * sinf(tau * 5 * t)) },
                         fm: { t in let u = t / dur; return (mixf(300, 620, smoothstep(0.1, 0.45, u)) - 120 * smoothstep(0.7, 1, u), mixf(750, 1050, smoothstep(0.2, 0.5, u)) - 200 * smoothstep(0.7, 1, u), 2500) },
                         env: { t in let u = t / dur; return smoothstep(0, 0.12, u) * (1 - smoothstep(0.75, 1, u)) },
                         nasal: { t in 1 - smoothstep(0.08, 0.3, t / dur) })
        }
        // Chicken cluck: a short "buk" with a clicky start.
        set("cluck", 5) { v in
            var rr = RNG(UInt64(220 + v))
            let f = rr.range(330, 480), d = rr.range(0.08, 0.13)
            let syl = 1 + rr.int(3)
            let gap: Float = 0.16
            let total = Float(syl) * gap + d
            return voice(Double(total), norm: 0.7, seed: UInt32(230 + v), breath: 0.15, rasp: 0.25,
                         f0: { t in let k = floorf(t / gap); let u = (t - k * gap) / d; return f * (1 + 0.25 * k * 0.3) * (1.15 - 0.3 * u) },
                         fm: { _ in (780, 1700, 3100) },
                         env: { t in let k = floorf(t / gap); let u = (t - k * gap) / d; return u < 1 && k < Float(syl) ? min(1, u * 30) * (1 - u) : 0 })
        }
        // Egg-laying announcement: buk buk buk buk-BAGAWK!
        buffers["bawk"] = {
            let marks: [(Float, Float, Float)] = [(0, 0.1, 420), (0.18, 0.1, 440), (0.36, 0.1, 430), (0.52, 0.09, 450), (0.66, 0.12, 460), (0.8, 0.5, 700)]
            return voice(1.4, norm: 0.8, seed: 240, breath: 0.15, rasp: 0.35,
                         f0: { t in
                             for (t0, d, f) in marks where t >= t0 && t < t0 + d + 0.02 { let u = (t - t0) / d; return f * (d > 0.3 ? (0.8 + 0.4 * sinf(.pi * min(1, u * 1.5))) : (1.1 - 0.25 * u)) }
                             return 400 },
                         fm: { t in t > 0.8 ? (900, 1500, 2900) : (760, 1700, 3100) },
                         env: { t in
                             for (t0, d, _) in marks where t >= t0 && t < t0 + d { let u = (t - t0) / d; return min(1, u * 25) * (1 - u * u) * (d > 0.3 ? 1.2 : 1) }
                             return 0 })
        }()
        // Rooster: cock-a-doodle-doooo.
        buffers["crow"] = {
            let marks: [(Float, Float, Float, Float)] = [(0, 0.16, 560, 620), (0.2, 0.12, 520, 540), (0.36, 0.18, 640, 720), (0.58, 0.14, 700, 690), (0.76, 0.9, 760, 560)]
            return voice(1.8, norm: 0.85, seed: 250, breath: 0.12, rasp: 0.5,
                         f0: { t in
                             for (t0, d, a, b) in marks where t >= t0 && t < t0 + d + 0.03 { let u = min(1, (t - t0) / d); return mixf(a, b, u) * (1 + 0.02 * sinf(tau * 7 * t)) }
                             return 500 },
                         fm: { t in t > 0.76 ? (650, 1100, 2800) : (900, 1800, 3000) },
                         env: { t in
                             for (t0, d, _, _) in marks where t >= t0 && t < t0 + d { let u = (t - t0) / d; return min(1, u * 20) * (1 - powf(u, 3)) }
                             return 0 })
        }()
        // Human babble, a few syllables with Sims-style made-up words.
        let vowels: [(Float, Float, Float)] = [(730, 1090, 2440), (270, 2290, 3010), (300, 870, 2240), (530, 1840, 2480), (660, 1720, 2410), (440, 1020, 2240), (390, 1990, 2550)]
        set("talk", 6) { v in
            var rr = RNG(UInt64(260 + v))
            let count = 3 + rr.int(4)
            var marks: [(Float, Float, Int)] = []
            var t0: Float = 0
            for _ in 0..<count { let d = rr.range(0.09, 0.17); marks.append((t0, d, rr.int(vowels.count))); t0 += d + rr.range(0.02, 0.06) }
            let total = t0 + 0.05
            let base = rr.range(105, 130)
            var cons = Noise32(s: UInt32(270 + v)); var cbp = Reso()
            let body = voice(Double(total), norm: 0.7, seed: UInt32(275 + v), breath: 0.06,
                             f0: { t in base * (1.1 + 0.15 * sinf(.pi * t / total) - 0.25 * t / total) },
                             fm: { t in
                                 for (a, d, k) in marks where t >= a && t < a + d { return vowels[k] }
                                 return vowels[0] },
                             env: { t in
                                 for (a, d, _) in marks where t >= a && t < a + d { let u = (t - a) / d; return min(1, u * 14) * min(1, (1 - u) * 8) }
                                 return 0 })
            // consonant bursts at each syllable onset
            let L = body.floatChannelData![0], R = body.floatChannelData![1]
            for (a, _, _) in marks {
                let s0 = Int(a * fsr)
                for k in 0..<Int(0.025 * fsr) where s0 + k < Int(body.frameLength) {
                    let tt = Float(k) / fsr
                    let c = cbp.run(cons.next(), f: 4500, q: 1.5, sr: fsr) * expf(-tt * 150) * 0.25
                    L[s0 + k] += c; R[s0 + k] += c
                }
            }
            return body
        }
        buffers["scream"] = voice(1.3, norm: 0.85, seed: 280, breath: 0.2, rasp: 0.3,
                                  f0: { t in (420 + 180 * smoothstep(0, 0.2, t) - 80 * smoothstep(0.6, 1.3, t)) * (1 + 0.04 * sinf(tau * 7 * t)) },
                                  fm: { _ in (850, 1250, 2800) },
                                  env: { t in smoothstep(0, 0.06, t) * (1 - smoothstep(0.8, 1.3, t)) })
        buffers["oof"] = voice(0.35, norm: 0.7, seed: 285, breath: 0.25,
                               f0: { t in 150 - 50 * t },
                               fm: { _ in (450, 900, 2400) },
                               env: { t in min(1, t * 40) * expf(-t * 7) })
        buffers["hmph"] = voice(0.5, norm: 0.6, seed: 286, breath: 0.2,
                                f0: { t in 120 - 20 * t }, fm: { _ in (300, 900, 2200) },
                                env: { t in min(1, t * 20) * (1 - t / 0.5) },
                                nasal: { _ in 0.8 })

        // MARK: actions
        set("flap", 3) { v in
            var n = Noise32(s: UInt32(300 + v)); var bp = Reso(), lp = LP1()
            let beats = 3 + v
            return make(0.45, norm: 0.55) { t in
                let x = n.next()
                let ph = t * Float(beats) / 0.45
                let beat = powf(max(0, sinf(.pi * ph)), 3)
                let s = (bp.run(x, f: 700 + 800 * beat, q: 0.9, sr: fsr) + lp.run(x, f: 250, sr: fsr) * 2) * beat
                return (s, s)
            }
        }
        buffers["peck"] = {
            var n = Noise32(s: 310); var r = Reso()
            return make(0.25, norm: 0.5) { t in
                var s: Float = 0
                for t0 in [Float(0), 0.11] where t > t0 { s += r.run(n.next(), f: 2400, q: 6, sr: fsr) * expf(-(t - t0) * 120) * 2 }
                return (s, s)
            }
        }()
        set("munch", 3) { v in
            var n = Noise32(s: UInt32(320 + v)); var bp = Reso(), lp = LP1()
            return make(0.6, norm: 0.5) { t in
                let x = n.next()
                let chew = powf(max(0, sinf(tau * 3.2 * t)), 4)
                let crunch: Float = n.next() > 0.6 ? 1.6 : 0.5
                let s = (bp.run(x, f: 1800, q: 1.2, sr: fsr) * crunch + lp.run(x, f: 250, sr: fsr) * 2) * chew
                return (s, s)
            }
        }
        buffers["crunch"] = {
            var n = Noise32(s: 330); var bp = Reso(), bp2 = Reso()
            return make(0.4, norm: 0.6) { t in
                let x = n.next()
                let crack: Float = n.next() > 0.3 ? 1 : 0.2
                let s = (bp.run(x, f: 2600, q: 1.5, sr: fsr) * crack + bp2.run(x, f: 900, q: 2, sr: fsr)) * expf(-t * 11)
                return (s, s)
            }
        }()
        buffers["rip"] = {
            var n = Noise32(s: 335); var bp = Reso()
            return make(0.35, norm: 0.5) { t in
                let x = n.next()
                let tick: Float = n.next() > 0.2 ? 1 : 0.1
                let s = bp.run(x, f: 3000 - 1500 * t / 0.35, q: 1.2, sr: fsr) * tick * sinf(.pi * t / 0.35)
                return (s, s)
            }
        }()
        buffers["plop"] = {
            var n = Noise32(s: 340); var lp = LP1()
            return make(0.35, norm: 0.55) { t in
                let s = sinf(tau * (300 - 180 * min(1, t * 8)) * t) * expf(-t * 18) + lp.run(n.next(), f: 400, sr: fsr) * expf(-t * 25) * 1.5
                return (s, s)
            }
        }()
        buffers["splat"] = {
            var n = Noise32(s: 350); var r = Reso(), bp = Reso(), lp = LP1()
            return make(0.5, norm: 0.65) { t in
                let x = n.next()
                let s = r.run(x, f: 3200, q: 5, sr: fsr) * expf(-t * 90) * 1.5 + bp.run(x, f: 700, q: 1, sr: fsr) * expf(-t * 12) + lp.run(x, f: 200, sr: fsr) * expf(-t * 10) * 2
                return (s, s)
            }
        }()
        buffers["throw"] = {
            var n = Noise32(s: 360); var bp = Reso()
            return make(0.4, norm: 0.5) { t in
                let u = t / 0.4
                let s = bp.run(n.next(), f: 400 + 1800 * sinf(.pi * u), q: 1.4, sr: fsr) * sinf(.pi * u) * sinf(.pi * u)
                return (s, s)
            }
        }()
        buffers["pickup"] = {
            var n = Noise32(s: 370); var bp = Reso()
            return make(0.2, norm: 0.4) { t in
                let s = bp.run(n.next(), f: 1200, q: 1, sr: fsr) * expf(-t * 25) + sinf(tau * 220 * t) * expf(-t * 30) * 0.4
                return (s, s)
            }
        }()
        set("thud", 3) { v in
            var n = Noise32(s: UInt32(380 + v)); var lp = LP1()
            var rr = RNG(UInt64(385 + v)); let f = rr.range(60, 95)
            return make(0.35, norm: 0.6) { t in
                let s = sinf(tau * f * t) * expf(-t * 20) + lp.run(n.next(), f: 500, sr: fsr) * expf(-t * 25) * 2
                return (s, s)
            }
        }
        buffers["bonk"] = {
            var n = Noise32(s: 390); var r1 = Reso(), r2 = Reso()
            return make(0.5, norm: 0.7) { t in
                let x = n.next()
                let s = r1.run(x, f: 160, q: 10, sr: fsr) * expf(-t * 12) * 3 + r2.run(x, f: 420, q: 8, sr: fsr) * expf(-t * 20) + sinf(tau * 90 * t) * expf(-t * 14)
                return (s, s)
            }
        }()
        set("clang", 2) { v in
            var n = Noise32(s: UInt32(400 + v)); var rr = RNG(UInt64(405 + v))
            let modes = (0..<7).map { _ in (rr.range(380, 3400), rr.range(3, 10)) }
            return make(1.2, norm: 0.6) { t in
                var s = n.next() * expf(-t * 100) * 0.6
                for (f, d) in modes { s += sinf(tau * f * t + sinf(tau * 4 * t) * 0.4) * expf(-t * d) * 0.25 }
                return (s, s * 0.95)
            }
        }
        buffers["kick"] = {
            var n = Noise32(s: 410); var r = Reso()
            return make(0.4, norm: 0.7) { t in
                let s = sinf(tau * (110 + 90 * expf(-t * 40)) * t) * expf(-t * 16) + r.run(n.next(), f: 900, q: 3, sr: fsr) * expf(-t * 50) * 1.5
                return (s, s)
            }
        }()
        buffers["shove"] = {
            var n = Noise32(s: 420); var lp = LP1(), bp = Reso()
            return make(0.5, norm: 0.75) { t in
                let x = n.next()
                let s = sinf(tau * (70 + 50 * expf(-t * 25)) * t) * expf(-t * 10) * 1.2 + lp.run(x, f: 800, sr: fsr) * expf(-t * 14) * 3 + bp.run(x, f: 1600, q: 1, sr: fsr) * expf(-t * 30)
                return (s, s)
            }
        }()
        buffers["whoosh"] = {
            var n = Noise32(s: 430); var bp = Reso()
            return make(0.7, norm: 0.55) { t in
                let u = t / 0.7
                let s = bp.run(n.next(), f: 300 + 1500 * sinf(.pi * u), q: 2, sr: fsr) * sinf(.pi * u)
                return (s * (1.2 - u), s * (0.3 + u))
            }
        }()
        set("climb", 2) { v in
            var n = Noise32(s: UInt32(440 + v)); var r1 = Reso(), r2 = Reso()
            return make(0.3, norm: 0.4) { t in
                let x = n.next()
                let s = r1.run(x, f: 1900 + Float(v) * 300, q: 20, sr: fsr) * expf(-t * 18) + r2.run(x, f: 4300, q: 15, sr: fsr) * expf(-t * 30) * 0.5
                return (s, s)
            }
        }
        buffers["creak"] = {
            var ph: Float = 0; var n = Noise32(s: 450); var bp = Reso()
            return make(0.7, norm: 0.4) { t in
                let f = 220 + 80 * sinf(tau * 1.3 * t)
                ph += f / fsr
                let stick: Float = sinf(tau * ph) > 0.8 ? 1 : 0
                let s = bp.run(stick + n.next() * 0.1, f: 900, q: 5, sr: fsr) * sinf(.pi * t / 0.7)
                return (s, s)
            }
        }()
        set("boom", 2) { v in
            var n = Noise32(s: UInt32(700 + v)); var lp = LP1(), lp2 = LP1(), bp = Reso()
            var rr = RNG(UInt64(710 + v))
            let debris = (0..<40).map { _ in (rr.range(0.1, 1.6), rr.range(800, 3500)) }
            var dr = Reso()
            return make(2.8, norm: 0.95) { t in
                let x = n.next()
                var s = x * expf(-t * 18) * 1.5 + lp.run(x, f: 900, sr: fsr) * expf(-t * 3) * 3 + lp2.run(x, f: 90, sr: fsr) * expf(-t * 1.2) * 7
                s += sinf(tau * (30 + 70 * expf(-t * 6)) * t) * expf(-t * 2.2) * 1.2
                s += bp.run(x, f: 400, q: 1, sr: fsr) * expf(-t * 5)
                for (t0, f) in debris where t > t0 && t < t0 + 0.05 { s += dr.run(x, f: f, q: 8, sr: fsr) * expf(-(t - t0) * 80) * 0.6 }
                return (s, s * 0.95)
            }
        }
        buffers["fanfare"] = make(1.6, norm: 0.6) { t in
            var s: Float = 0
            for (k, m) in [Float(67), 71, 74, 79].enumerated() {
                let t0 = Float(k) * 0.1
                guard t >= t0 else { continue }
                let d = t - t0
                let f = midiHz(m)
                var tone: Float = 0
                for h in 1...6 { tone += sinf(tau * f * Float(h) * d) / Float(h) * (h > 2 ? expf(-d * 3) : 1) }
                s += tone * expf(-d * (k == 3 ? 1.5 : 6)) * min(1, d * 60)
            }
            return (s, s)
        }
        buffers["combo"] = make(0.9, norm: 0.45) { t in
            var s: Float = 0
            for (k, m) in [Float(84), 88, 91, 96].enumerated() {
                let t0 = Float(k) * 0.06
                guard t >= t0 else { continue }
                let d = t - t0
                s += (sinf(tau * midiHz(m) * d) + 0.3 * sinf(tau * midiHz(m) * 2.76 * d) * expf(-d * 20)) * expf(-d * 5) * min(1, d * 500)
            }
            return (s, s)
        }
        buffers["click"] = {
            var n = Noise32(s: 5)
            return make(0.03, norm: 0.35) { t in
                let s = sinf(tau * 2400 * t) * expf(-t * 400) * 0.4 + n.next() * expf(-t * 1500) * 0.2
                return (s, s)
            }
        }()
        buffers["select"] = make(0.12, norm: 0.4) { t in
            let s = sinf(tau * (700 + 700 * t / 0.12) * t) * expf(-t * 20)
            return (s, s)
        }
        buffers["nope"] = {
            var ph: Float = 0
            return make(0.3, norm: 0.35) { t in
                ph += 140 / fsr; if ph > 1 { ph -= 1 }
                let s: Float = (ph < 0.5 ? 1 : -1) * 0.5 * (t < 0.12 || t > 0.16 ? 1 : 0) * (1 - t / 0.3)
                return (s, s)
            }
        }()
    }

    // MARK: animal calls

    private func buildCalls() {
        let tau: Float = 2 * .pi
        let fsr = Float(sr)
        func syl(_ t: Float, _ marks: [(Float, Float)]) -> (Int, Float)? {
            for (k, (a, d)) in marks.enumerated() where t >= a && t < a + d { return (k, (t - a) / d) }
            return nil
        }
        func env(_ u: Float, _ atk: Float = 0.08) -> Float { smoothstep(0, atk, u) * (1 - smoothstep(0.7, 1, u)) }
        for (id, d) in Zoo.defs.enumerated() where !d.custom {
            let ps = clampf(1 / powf(d.size, 0.6), 0.6, 2.0), fs = sqrtf(ps)
            let seed = UInt32(500 + id)
            var b: AVAudioPCMBuffer
            switch d.voice {
            case .neigh:
                b = voice(1.4, seed: seed, breath: 0.12, rasp: 0.35, f0: { t in (900 - 480 * smoothstep(0, 1.2, t)) * ps * (1 + 0.06 * sinf(tau * 17 * t)) },
                          fm: { _ in (700 * fs, 1300 * fs, 2600) }, env: { t in env(t / 1.4, 0.05) * (0.7 + 0.3 * sinf(tau * 9 * t)) })
            case .oink, .grunt, .snort:
                let n = d.voice == .snort ? 1 : 3
                let marks = (0..<n).map { (Float($0) * 0.2, Float(0.13)) }
                b = voice(Double(Float(n) * 0.2 + 0.1), seed: seed, breath: d.voice == .snort ? 0.8 : 0.2, rasp: 0.8,
                          f0: { t in (d.voice == .grunt ? 110 : 190) * ps * (1.1 - 0.2 * (syl(t, marks)?.1 ?? 0)) },
                          fm: { _ in (500 * fs, 1100 * fs, 2400) }, env: { t in syl(t, marks).map { env($0.1, 0.1) } ?? 0 }, nasal: { _ in 0.65 })
            case .baa, .bleat:
                let dur: Float = d.voice == .baa ? 1.0 : 0.75
                b = voice(Double(dur), seed: seed, breath: 0.1, rasp: 0.25, f0: { t in (d.voice == .baa ? 330 : 420) * ps * (1 + 0.03 * sinf(tau * 7 * t)) },
                          fm: { t in (mixf(500, 800, smoothstep(0, 0.2, t)) * fs, (d.voice == .baa ? 1300 : 1700) * fs, 2600) },
                          env: { t in env(t / dur, 0.1) * (0.6 + 0.4 * abs(sinf(tau * (d.voice == .baa ? 3.5 : 4.5) * t))) })
            case .bray:
                let marks: [(Float, Float)] = [(0, 0.35), (0.4, 0.4), (0.85, 0.35), (1.25, 0.45)]
                b = voice(1.8, seed: seed, breath: 0.25, rasp: 0.6,
                          f0: { t in (syl(t, marks).map { $0.0 % 2 == 0 ? 650 : 230 } ?? 300) * ps },
                          fm: { t in let f1: Float = syl(t, marks).map { $0.0 % 2 == 0 ? Float(400) : 750 } ?? 600; return (f1 * fs, 1200 * fs, 2500) },
                          env: { t in syl(t, marks).map { env($0.1, 0.15) } ?? 0 })
            case .bark, .yip:
                let yip = d.voice == .yip
                let marks: [(Float, Float)] = yip ? [(0, 0.08), (0.14, 0.08), (0.28, 0.1)] : [(0, 0.16), (0.3, 0.18)]
                b = voice(yip ? 0.45 : 0.55, seed: seed, breath: 0.15, rasp: 0.5,
                          f0: { t in (yip ? 950 : 420) * ps * (1.15 - 0.4 * (syl(t, marks)?.1 ?? 0)) },
                          fm: { _ in (Float(yip ? 900 : 700) * fs, 1500 * fs, 2700) },
                          env: { t in syl(t, marks).map { min(1, $0.1 * 30) * (1 - $0.1) } ?? 0 })
            case .meow:
                b = voice(0.8, seed: seed, breath: 0.08, rasp: 0.1, f0: { t in (500 + 220 * sinf(.pi * min(1, t / 0.7))) * ps },
                          fm: { t in let u = t / 0.8; return (mixf(mixf(300, 850, smoothstep(0, 0.4, u)), 400, smoothstep(0.5, 1, u)) * fs, mixf(mixf(2200, 1300, smoothstep(0, 0.4, u)), 900, smoothstep(0.5, 1, u)) * fs, 2900) },
                          env: { t in env(t / 0.8, 0.12) }, nasal: { t in 1 - smoothstep(0, 0.12, t) })
            case .roar, .growl, .bellow:
                let dur: Float = d.voice == .growl ? 1.2 : d.voice == .roar ? 1.7 : 1.5
                let base: Float = d.voice == .growl ? 80 : d.voice == .roar ? 120 : 95
                b = voice(Double(dur), seed: seed, breath: 0.3, rasp: d.voice == .bellow ? 0.5 : 0.95,
                          f0: { t in base * ps * (1 + 0.35 * sinf(.pi * min(1, t / dur)) - (d.voice == .growl ? 0.3 : 0)) },
                          fm: { t in ((d.voice == .roar ? mixf(400, 700, smoothstep(0, 0.3, t / dur)) : 450) * fs, 950 * fs, 2400) },
                          env: { t in env(t / dur, 0.12) * (d.voice == .growl ? 0.7 + 0.3 * sinf(tau * 28 * t) : 1) })
            case .howl:
                b = voice(2.3, seed: seed, breath: 0.05, rasp: 0.05, f0: { t in (400 + 250 * smoothstep(0, 0.5, t) - 220 * smoothstep(1.6, 2.3, t)) * ps * (1 + 0.01 * sinf(tau * 5 * t)) },
                          fm: { _ in (380 * fs, 850 * fs, 2600) }, env: { t in env(t / 2.3, 0.15) })
            case .squeak:
                let marks: [(Float, Float)] = [(0, 0.09), (0.15, 0.12)]
                b = make(0.32, norm: 0.5) { t in
                    guard let (_, u) = syl(t, marks) else { return (0, 0) }
                    let f = 2600 * ps * (1 + 0.3 * u)
                    let v = sinf(tau * f * t) * sinf(.pi * u)
                    return (v, v)
                }
            case .hiss:
                var n = Noise32(s: seed); var bp = Reso(), bp2 = Reso()
                b = make(1.2, norm: 0.55) { t in
                    let x = n.next()
                    let v = (bp.run(x, f: 5500, q: 1.5, sr: fsr) + bp2.run(x, f: 3000, q: 2, sr: fsr) * 0.5) * env(t / 1.2, 0.1)
                    return (v, v)
                }
            case .quack, .honk:
                let honk = d.voice == .honk
                let marks: [(Float, Float)] = honk ? [(0, 0.3), (0.42, 0.34)] : [(0, 0.15), (0.22, 0.15), (0.44, 0.2)]
                b = voice(honk ? 0.85 : 0.72, seed: seed, breath: 0.15, rasp: honk ? 0.3 : 0.7,
                          f0: { t in (honk ? 330 : 250) * ps * (1.1 - 0.2 * (syl(t, marks)?.1 ?? 0)) },
                          fm: { _ in (honk ? 650 * fs : 850 * fs, honk ? 1100 * fs : 1400 * fs, 2500) },
                          env: { t in syl(t, marks).map { env($0.1, 0.1) } ?? 0 }, nasal: { _ in honk ? 0.4 : 0.6 })
            case .gobble:
                b = voice(0.9, seed: seed, breath: 0.2, rasp: 0.5, f0: { t in (420 - 100 * t) * ps },
                          fm: { _ in (700 * fs, 1500 * fs, 2800) }, env: { t in env(t / 0.9, 0.05) * (0.5 + 0.5 * sinf(tau * 18 * t)) })
            case .hoot, .coo:
                let coo = d.voice == .coo
                let marks: [(Float, Float)] = coo ? [(0, 0.25), (0.3, 0.45), (0.8, 0.25)] : [(0, 0.3), (0.45, 0.25), (0.75, 0.45)]
                b = voice(1.15, seed: seed, breath: 0.12, rasp: 0.02, f0: { t in (coo ? 360 : 330) * ps * (syl(t, marks).map { $0.0 == 1 ? Float(1.1) : 1 } ?? 1) },
                          fm: { _ in (320 * fs, 700 * fs, 2400) }, env: { t in syl(t, marks).map { env($0.1, 0.2) } ?? 0 }, nasal: { _ in coo ? 0.5 : 0.2 })
            case .caw, .squawk, .screech:
                let marks: [(Float, Float)] = d.voice == .caw ? [(0, 0.3), (0.45, 0.3)] : [(0, d.voice == .screech ? 0.8 : 0.5)]
                let base: Float = d.voice == .caw ? 600 : d.voice == .squawk ? 900 : 1500
                b = voice(d.voice == .caw ? 0.85 : 0.9, seed: seed, breath: 0.2, rasp: 0.85,
                          f0: { t in base * ps * (1.1 - 0.25 * (syl(t, marks)?.1 ?? 0)) },
                          fm: { _ in (1300 * fs, 2100 * fs, 3200) }, env: { t in syl(t, marks).map { env($0.1, 0.06) } ?? 0 })
            case .tweet, .chirp:
                let cricket = d.voice == .chirp && (d.plan == .insect || d.plan == .spider)
                var ph: Float = 0
                b = make(0.9, norm: 0.45) { t in
                    if cricket {
                        let burst = (t.truncatingRemainder(dividingBy: 0.3)) < 0.12
                        let pulse = sinf(tau * 30 * t) > 0
                        let v = sinf(tau * 4600 * t) * (burst && pulse ? 1 : 0)
                        return (v, v)
                    }
                    let k = floorf(t / 0.14), u = (t - k * 0.14) / 0.09
                    guard u < 1, k < 5 else { return (0, 0) }
                    let f = (2600 + 900 * sinf(.pi * u) + k * 150) * ps
                    ph += f / fsr
                    let v = sinf(tau * ph) * sinf(.pi * u)
                    return (v, v)
                }
            case .trumpet:
                b = voice(1.3, seed: seed, breath: 0.05, rasp: 0.35, f0: { t in (480 + 250 * smoothstep(0, 0.3, t)) * (1 + 0.02 * sinf(tau * 6 * t)) },
                          fm: { _ in (1000, 2200, 3500) }, env: { t in env(t / 1.3, 0.05) })
            case .hoo:
                let marks: [(Float, Float)] = [(0, 0.18), (0.25, 0.18), (0.5, 0.2), (0.78, 0.35), (1.18, 0.4)]
                b = voice(1.7, seed: seed, breath: 0.15, rasp: 0.3,
                          f0: { t in (syl(t, marks).map { $0.0 < 3 ? Float(250 + $0.0 * 60) : 600 } ?? 300) * ps },
                          fm: { t in (syl(t, marks).map { $0.0 < 3 ? Float(350) : 850 } ?? 400, 900, 2500) },
                          env: { t in syl(t, marks).map { env($0.1, 0.15) } ?? 0 })
            case .chatter:
                var n = Noise32(s: seed); var bp = Reso()
                b = make(0.8, norm: 0.5) { t in
                    let k = t * 16, u = k - floorf(k)
                    let v = (bp.run(n.next(), f: 3000 * ps, q: 4, sr: fsr) * 2 + sinf(tau * 1800 * ps * t) * 0.4) * (u < 0.35 ? sinf(.pi * u / 0.35) : 0)
                    return (v, v)
                }
            case .ribbit:
                let marks: [(Float, Float)] = [(0, 0.14), (0.2, 0.2)]
                b = voice(0.5, seed: seed, breath: 0.2, rasp: 0.9, f0: { _ in 170 * ps },
                          fm: { _ in (500 * fs, 1100 * fs, 2400) }, env: { t in (syl(t, marks).map { env($0.1, 0.1) } ?? 0) * (0.5 + 0.5 * sinf(tau * 55 * t)) })
            case .buzz:
                var ph: Float = 0; var lp = LP1()
                b = make(1.0, norm: 0.45) { t in
                    let f: Float = 220 * ps * (1 + 0.05 * sinf(tau * 3 * t))
                    ph += f / fsr; if ph > 1 { ph -= 1 }
                    let v = lp.run(ph * 2 - 1, f: 1800, sr: fsr) * env(t, 0.1) * (0.8 + 0.2 * sinf(tau * 40 * t))
                    return (v, v)
                }
            case .click:
                var n = Noise32(s: seed); var bp = Reso(); var ph: Float = 0
                b = make(1.2, norm: 0.5) { t in
                    var v: Float = 0
                    let k = t * 14, u = k - floorf(k)
                    if t < 0.6 { v += bp.run(n.next(), f: 6000, q: 3, sr: fsr) * expf(-u * 30) * 1.5 }
                    if t > 0.55 {
                        let w = (t - 0.55) / 0.6
                        ph += (5000 + 3500 * sinf(.pi * w)) / fsr
                        v += sinf(tau * ph) * sinf(.pi * min(1, w)) * 0.5
                    }
                    return (v, v)
                }
            case .whale:
                b = voice(3.0, seed: seed, breath: 0.03, rasp: 0.05, f0: { t in (150 + 170 * sinf(.pi * t / 3) - 60 * smoothstep(2, 3, t)) * ps },
                          fm: { _ in (350, 800, 2000) }, env: { t in env(t / 3, 0.2) })
            case .blub:
                b = make(0.8, norm: 0.45) { t in
                    let k = floorf(t / 0.15), u = (t - k * 0.15) / 0.07
                    guard u < 1 else { return (0, 0) }
                    let f = (300 + 700 * u + k * 60) * ps
                    let v = sinf(tau * f * (t - k * 0.15)) * sinf(.pi * u)
                    return (v, v)
                }
            default:
                b = voice(0.5, seed: seed, breath: 0.2, rasp: 0.5, f0: { _ in 150 * ps }, fm: { _ in (500, 1100, 2400) }, env: { t in env(t / 0.5) })
            }
            buffers["call_\(id)"] = b
        }
        // extra movement sounds for the new body plans
        buffers["slither"] = {
            var n = Noise32(s: 900); var bp = Reso()
            return make(0.35, norm: 0.35) { t in
                let v = bp.run(n.next(), f: 2500, q: 0.8, sr: fsr) * sinf(.pi * t / 0.35)
                return (v, v)
            }
        }()
        buffers["flop"] = {
            var n = Noise32(s: 901); var lp = LP1(), bp = Reso()
            return make(0.3, norm: 0.5) { t in
                let x = n.next()
                let v = lp.run(x, f: 500, sr: fsr) * expf(-t * 20) * 2 + bp.run(x, f: 1500, q: 1, sr: fsr) * expf(-t * 30) + sinf(tau * 120 * t) * expf(-t * 25) * 0.5
                return (v, v)
            }
        }()
        buffers["buzzwing"] = {
            var ph: Float = 0; var lp = LP1()
            return make(0.5, norm: 0.3) { t in
                ph += 180 / fsr; if ph > 1 { ph -= 1 }
                let v = lp.run(ph * 2 - 1, f: 1200, sr: fsr) * sinf(.pi * t / 0.5)
                return (v, v)
            }
        }()
    }
}
