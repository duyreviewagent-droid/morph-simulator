import Foundation

// Synths run on the audio thread. The game thread writes their public parameters
// (benign single-word races); render() smooths them.

// MARK: - The farm around you

final class AmbienceSynth {
    let sr: Float
    var level: Float = 1
    var rush: Float = 0         // wind past the ears (speed, gliding, falling)
    var on: Float = 1

    private var n = Noise32(s: 0xFA12)
    private var n2 = Noise32(s: 0x77)
    private var rng = RNG(0xFA)
    private var lv: Float = 0, rs: Float = 0
    private var wind1 = Reso(), wind2 = Reso(), windLP = LP1(), slow = LP1(), slow2 = LP1()
    private var leaf = Reso(), leafEnv: Float = 0, leafLP = LP1()
    private var rushL = Reso(), rushR = Reso()
    // songbirds
    private var birdGap: Float = 1, birdLeft = 0, birdT: Float = 0, birdPh: Float = 0, birdF: Float = 3000, birdPan: Float = 0, birdCall: Float = 0.1, birdKind = 0, birdA: Float = 0
    // meadowlark: a falling flute phrase
    private var larkGap: Float = 9, larkT: Float = 99, larkPh: Float = 0, larkPan: Float = 0
    // crow caws in the distance
    private var crowGap: Float = 20, crowLeft = 0, crowT: Float = 0, crowPh: Float = 0, crowPan: Float = 0, crowR = Reso(), crowR2 = Reso()
    // insects: a soft buzz that comes and goes
    private var bugPh: Float = 0, bugAM: Float = 0, bugR = Reso(), bugLevel: Float = 0, bugTarget: Float = 0, bugGap: Float = 5
    private var outL = LP1(), outR = LP1()

    init(sampleRate: Float) { sr = sampleRate }

    func render(frames: Int, _ L: UnsafeMutablePointer<Float>, _ R: UnsafeMutablePointer<Float>) {
        let inv = 1 / sr, tp = 2 * Float.pi
        for i in 0..<frames {
            lv += (level * on - lv) * 0.0002
            rs += (rush - rs) * 0.0008
            var l: Float = 0, r: Float = 0
            // wind across open fields, slowly gusting
            let x = n.next()
            let g = 0.5 + slow2.run(slow.run(n2.next(), f: 0.15, sr: sr), f: 0.3, sr: sr) * 60
            let gust = max(0.15, min(1.6, g))
            let w = windLP.run(wind1.run(x, f: 380 + gust * 220, q: 0.6, sr: sr), f: 1400, sr: sr) * 0.08 * gust
            l += w; r += w * 0.9
            // leaves rustling in the gusts
            leafEnv += ((gust > 1 ? (gust - 1) : 0) * 1.5 - leafEnv) * 0.0005
            let lf = leafLP.run(leaf.run(n2.next(), f: 5200, q: 0.7, sr: sr), f: 9000, sr: sr) * leafEnv * 0.05 * (0.5 + 0.5 * abs(x))
            l += lf * 0.7; r += lf * 1.1

            // rush of wind when fast
            if rs > 0.01 {
                let a = rs * rs * 0.25
                l += rushL.run(n.next(), f: 500 + rs * 900, q: 0.5, sr: sr) * a
                r += rushR.run(n2.next(), f: 560 + rs * 950, q: 0.5, sr: sr) * a
            }

            // songbirds: little bursts of tweets from the trees
            birdGap -= inv
            if birdGap < 0 && birdLeft == 0 {
                birdGap = rng.range(1.5, 6)
                birdKind = rng.int(3)
                birdLeft = birdKind == 2 ? 1 : 3 + rng.int(6)
                birdT = 0; birdF = rng.range(2800, 4600); birdPan = rng.range(-0.9, 0.9); birdCall = birdKind == 2 ? 0.5 : rng.range(0.05, 0.1)
                birdA = rng.range(0.006, 0.016)
            }
            if birdLeft > 0 {
                birdT += inv
                let u = birdT / birdCall
                if u < 1 {
                    var f = birdF
                    switch birdKind {
                    case 0: f *= 1 + 0.3 * sinf(.pi * u)                  // chirp up and down
                    case 1: f *= 1.25 - 0.4 * u                           // falling tweet
                    default: f *= 1 + 0.08 * sinf(tp * 28 * birdT)         // trill
                    }
                    birdPh += f * inv; if birdPh > 1 { birdPh -= 1 }
                    let s = sinf(tp * birdPh) * sinf(.pi * u) * birdA * 3
                    let (gl, gr) = equalPan(birdPan)
                    l += s * gl; r += s * gr
                } else if u > 1.5 { birdLeft -= 1; birdT = 0 }
            }
            // western meadowlark phrase
            larkGap -= inv
            if larkGap < 0 { larkGap = rng.range(14, 30); larkT = 0; larkPan = rng.range(-1, 1) }
            if larkT < 1.6 {
                larkT += inv
                let notes: [(Float, Float, Float)] = [(0, 0.25, 2600), (0.3, 0.12, 3300), (0.45, 0.1, 2900), (0.6, 0.3, 2400), (0.95, 0.12, 2200), (1.1, 0.4, 1900)]
                for (t0, d, f) in notes where larkT >= t0 && larkT < t0 + d {
                    let u = (larkT - t0) / d
                    larkPh += f * (1 - 0.1 * u) * inv; if larkPh > 1 { larkPh -= 1 }
                    let s = sinf(tp * larkPh) * sinf(.pi * u) * 0.02
                    let (gl, gr) = equalPan(larkPan)
                    l += s * gl; r += s * gr
                }
            }
            // a crow somewhere far off
            crowGap -= inv
            if crowGap < 0 && crowLeft == 0 { crowGap = rng.range(25, 60); crowLeft = 2 + rng.int(3); crowT = 0; crowPan = rng.range(-1, 1) }
            if crowLeft > 0 {
                crowT += inv
                if crowT < 0.3 {
                    let u = crowT / 0.3
                    let f = 520 - 120 * u
                    crowPh += f * inv; if crowPh > 1 { crowPh -= 1 }
                    let buzz = (crowPh < 0.3 ? 1 : -0.4) * (0.7 + 0.3 * n.next())
                    let s = (crowR.run(buzz, f: 1300, q: 3, sr: sr) + crowR2.run(buzz, f: 2200, q: 4, sr: sr) * 0.5) * sinf(.pi * u) * 0.01
                    let (gl, gr) = equalPan(crowPan)
                    l += s * gl; r += s * gr
                } else if crowT > 0.55 { crowLeft -= 1; crowT = 0 }
            }
            // grasshoppers
            bugGap -= inv
            if bugGap < 0 { bugGap = rng.range(3, 9); bugTarget = rng.chance(0.5) ? rng.range(0.3, 1) : 0 }
            bugLevel += (bugTarget - bugLevel) * 0.00005
            if bugLevel > 0.01 {
                bugAM += 31 * inv; if bugAM > 1 { bugAM -= 1 }
                let pulse: Float = bugAM < 0.35 ? 1 : 0
                let s = bugR.run(n.next(), f: 6500, q: 8, sr: sr) * pulse * bugLevel * 0.012
                l += s * 1.1; r += s * 0.8
            }
            L[i] = outL.run(l, f: 11000, sr: sr) * lv
            R[i] = outR.run(r, f: 11000, sr: sr) * lv
        }
    }
}

// MARK: - Score: acoustic country, synthesised with plucked strings

enum MusicMood: Int32 { case menu = 0, play = 1, quiet = 2 }

/// Karplus-Strong string with an allpass for exact tuning.
struct KString {
    var buf = [Float](repeating: 0, count: 2400)
    var n = 100, idx = 0
    var last: Float = 0
    var c: Float = 0, apX: Float = 0, apY: Float = 0
    var decay: Float = 0.996
    var amp: Float = 0
    var pan: Float = 0
    var age: Float = 99
    var body = Reso()
    mutating func pluck(_ f: Float, _ a: Float, sr: Float, bright: Float, decay d: Float, rng: inout RNG, pan p: Float) {
        let period = sr / f - 0.5
        n = max(2, min(2399, Int(period)))
        let frac = period - Float(n)
        c = (1 - frac) / (1 + frac)
        var lp: Float = 0
        for k in 0..<n {
            let x = rng.range(-1, 1)
            lp += (x - lp) * bright
            buf[k] = lp
        }
        // pick position: a comb notch softens the attack
        let pp = max(1, n / 7)
        for k in stride(from: n - 1, through: pp, by: -1) { buf[k] -= buf[k - pp] * 0.5 }
        idx = 0; last = 0; apX = 0; apY = 0
        decay = d; amp = a; pan = p; age = 0
    }
    @inline(__always) mutating func tick() -> Float {
        let cur = buf[idx]
        let avg = decay * 0.5 * (cur + last)
        let ap = c * avg + apX - c * apY
        apX = avg; apY = ap
        buf[idx] = ap
        last = cur
        idx += 1; if idx >= n { idx = 0 }
        return ap * amp
    }
}

final class MusicSynth {
    let sr: Float
    var on: Float = 1
    var mood: MusicMood = .menu
    var energy: Float = 0.5

    private var sc = 0, step = -1, sps = 1
    private var rng = RNG(0xC0417)
    private var n = Noise32(s: 0xB8)
    private var lastMood: MusicMood = .quiet
    private var strings = [KString](repeating: KString(), count: 12)
    private var sNext = 0
    private var bass = KString()
    private var bassLP = LP1()
    private var brushT: Float = 9, brushA: Float = 0, brushLP = LP1(), brushHP: Float = 0
    private var tickT: Float = 9, tickA: Float = 0, tickHP: Float = 0
    private var kickT: Float = 9, kickPh: Float = 0
    // harmonica lead
    private var hF: Float = 392, hTF: Float = 392, hA: Float = 0, hTA: Float = 0, hPh: Float = 0, hVib: Float = 0
    private var hF1 = Reso(), hF2 = Reso(), hLP = LP1()
    private var sOn: Float = 0, en: Float = 0
    private var outL = LP1(), outR = LP1()
    private var revL = [Float](repeating: 0, count: 9000), revR = [Float](repeating: 0, count: 9000), revI = 0

    // G C G D | G C D G   and a bridge   Em C G D | Em C D D
    private let prog: [Int] = [0, 1, 0, 2, 0, 1, 2, 0, 3, 1, 0, 2, 3, 1, 2, 2]
    private let bassRoot: [Float] = [31, 36, 38, 28]
    private let bassAlt: [Float] = [38, 31, 33, 35]
    private let gBass: [Float] = [43, 48, 50, 40]
    private let gAlt: [Float] = [50, 43, 45, 47]
    private let treble: [[Float]] = [[55, 59, 62, 67], [52, 55, 60, 64], [54, 57, 62, 66], [52, 55, 59, 64]]
    // a 16-bar harmonica tune over the progression (0 = rest), eighth notes
    private let tune: [Float] = [
        71, 0, 74, 0, 74, 72, 71, 0, 72, 0, 76, 0, 76, 74, 72, 0, 71, 0, 67, 0, 69, 71, 74, 0, 69, 0, 0, 0, 66, 67, 69, 0,
        71, 0, 74, 0, 79, 0, 76, 74, 76, 0, 72, 0, 69, 0, 67, 0, 69, 0, 71, 72, 74, 0, 72, 71, 67, 0, 0, 0, 0, 0, 0, 0,
        76, 0, 76, 74, 71, 0, 67, 0, 72, 0, 76, 0, 79, 0, 76, 0, 74, 0, 71, 0, 67, 0, 71, 74, 74, 0, 72, 0, 69, 0, 66, 0,
        76, 0, 74, 71, 72, 0, 76, 0, 74, 0, 71, 0, 69, 0, 67, 66, 67, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]

    init(sampleRate: Float) { sr = sampleRate }

    private func bpm(_ b: Float) -> Int { Int(sr * 60 / b / 2) }     // eighth notes

    private func pluck(_ m: Float, _ a: Float, bright: Float = 0.5, pan: Float = 0, decay: Float = 0.996) {
        strings[sNext].pluck(midiHz(m), a, sr: sr, bright: bright, decay: decay, rng: &rng, pan: pan)
        sNext = (sNext + 1) % strings.count
    }

    private func tick() {
        step += 1
        if mood != lastMood { lastMood = mood; step = 0 }
        let e8 = step % 8, bar = step / 8
        hTA = 0
        switch mood {
        case .menu:
            sps = bpm(84)
            let ch = prog[bar % 8]
            let tr = treble[ch]
            // gentle fingerpicking, no band
            switch e8 {
            case 0: pluck(gBass[ch], 0.5, bright: 0.35, pan: -0.2)
            case 2: pluck(tr[1], 0.28, bright: 0.45, pan: 0.2)
            case 3: pluck(tr[2], 0.24, bright: 0.45, pan: 0.25)
            case 4: pluck(gAlt[ch], 0.42, bright: 0.35, pan: -0.2)
            case 5: pluck(tr[3], 0.22, bright: 0.5, pan: 0.3)
            case 6: pluck(tr[2], 0.22, bright: 0.45, pan: 0.25)
            case 7: if bar % 2 == 1 { pluck(tr[0], 0.2, bright: 0.45, pan: 0.2) }
            default: break
            }
            if e8 == 0 && bar % 4 == 0 { bass.pluck(midiHz(bassRoot[ch] + 12), 0.5, sr: sr, bright: 0.2, decay: 0.998, rng: &rng, pan: 0) }
        case .play:
            sps = bpm(104)
            let ch = prog[bar % 16]
            let tr = treble[ch]
            // Travis picking: alternating bass with the thumb, melody on the offbeats
            switch e8 {
            case 0: pluck(gBass[ch], 0.55, bright: 0.4, pan: -0.25); pluck(tr[3], 0.25, bright: 0.55, pan: 0.3)
            case 1: pluck(tr[2], 0.22, bright: 0.5, pan: 0.25)
            case 2: pluck(gAlt[ch], 0.45, bright: 0.4, pan: -0.25)
            case 3: pluck(tr[1], 0.22, bright: 0.5, pan: 0.2)
            case 4: pluck(gBass[ch], 0.5, bright: 0.4, pan: -0.25); pluck(tr[2], 0.2, bright: 0.5, pan: 0.25)
            case 5: pluck(tr[3], 0.2, bright: 0.55, pan: 0.3)
            case 6: pluck(gAlt[ch], 0.45, bright: 0.4, pan: -0.25)
            case 7: pluck(tr[1], 0.22, bright: 0.5, pan: 0.2)
            default: break
            }
            // upright bass on 1 and 3
            if e8 == 0 { bass.pluck(midiHz(bassRoot[ch]), 0.9, sr: sr, bright: 0.25, decay: 0.997, rng: &rng, pan: 0) }
            if e8 == 4 { bass.pluck(midiHz(bassAlt[ch]), 0.8, sr: sr, bright: 0.25, decay: 0.997, rng: &rng, pan: 0) }
            // brushes: swish on 2 and 4, soft ticks, kick on 1 and 3
            if e8 == 2 || e8 == 6 { brushT = 0; brushA = 1 }
            if e8 % 2 == 1 { tickT = 0; tickA = 0.5 }
            if e8 == 0 || e8 == 4 { kickT = 0; kickPh = 0 }
            // harmonica comes in for the second half of each 32-bar cycle
            let cyc = bar % 32
            if cyc >= 16 {
                let m = tune[((cyc - 16) * 8 + e8) % tune.count]
                if m > 0 { hTF = midiHz(m); hTA = 1 } else { hTA = hA > 0.3 && e8 % 2 == 1 ? 1 : 0 }
            }
        case .quiet:
            sps = bpm(100)
        }
    }

    func render(frames: Int, _ L: UnsafeMutablePointer<Float>, _ R: UnsafeMutablePointer<Float>) {
        let tp = 2 * Float.pi, inv = 1 / sr
        let target = on * (mood == .quiet ? 0 : 1)
        let rN = revL.count
        for i in 0..<frames {
            if sc == 0 { tick() }
            sc += 1
            // a gentle shuffle
            let len = step % 2 == 0 ? sps * 112 / 100 : sps * 88 / 100
            if sc >= len { sc = 0 }
            sOn += (target - sOn) * 0.00008
            en += (energy - en) * 0.00005
            var l: Float = 0, r: Float = 0
            var gtr: Float = 0, gtrR: Float = 0
            for k in 0..<strings.count where strings[k].amp > 0.0005 {
                let s = strings[k].tick()
                let (gl, gr) = equalPan(strings[k].pan)
                gtr += s * gl; gtrR += s * gr
                strings[k].age += inv
                if strings[k].age > 4 { strings[k].amp = 0 }
            }
            // guitar body warmth
            l += gtr * 0.32; r += gtrR * 0.32
            if bass.amp > 0.0005 {
                let b = bassLP.run(bass.tick(), f: 500, sr: sr) * 0.55
                l += b; r += b
            }
            if kickT < 0.3 {
                kickT += inv
                kickPh += (55 + 60 * expf(-kickT * 30)) * inv
                let k = sinf(tp * kickPh) * expf(-kickT * 14) * 0.12
                l += k; r += k
            }
            if brushT < 0.35 {
                brushT += inv
                let x = n.next()
                brushHP += (x - brushHP) * 0.3
                let env = min(1, brushT * 60) * expf(-brushT * 9)
                let s = brushLP.run(x - brushHP, f: 5000, sr: sr) * env * 0.05 * brushA
                l += s * 0.9; r += s * 1.1
            }
            if tickT < 0.1 {
                tickT += inv
                let x = n.next()
                tickHP += (x - tickHP) * 0.5
                let s = (x - tickHP) * expf(-tickT * 60) * 0.018 * tickA
                l += s * 1.1; r += s * 0.9
            }
            // harmonica: a reedy pulse through two formants, with vibrato and breath
            hF += (hTF - hF) * 0.006
            hA += (hTA - hA) * (hTA > hA ? 0.003 : 0.0012)
            if hA > 0.002 {
                hVib += 5.5 * inv; if hVib > 1 { hVib -= 1 }
                let f = hF * (1 + 0.008 * sinf(tp * hVib) * hA)
                hPh += f * inv; if hPh > 1 { hPh -= 1 }
                let reed: Float = (hPh < 0.4 ? 1 : -0.66) + n.next() * 0.06
                let s = (hF1.run(reed, f: 1100, q: 2, sr: sr) + hF2.run(reed, f: 2400, q: 3, sr: sr) * 0.5 + hLP.run(reed, f: 900, sr: sr) * 0.4) * hA * 0.05
                l += s * 1.05; r += s * 0.95
            }
            // small room
            let ri = revI
            let d1 = (ri + rN - 2111) % rN, d2 = (ri + rN - 3371) % rN
            let wl = revL[d1] * 0.5 + revR[d2] * 0.25, wr = revR[d1] * 0.5 + revL[d2] * 0.25
            revL[ri] = l * 0.5 + wl * 0.45
            revR[ri] = r * 0.5 + wr * 0.45
            revI = (revI + 1) % rN
            l += wl * 0.3; r += wr * 0.3
            L[i] = outL.run(softClip(l * sOn * 1.2) * 0.8, f: 12000, sr: sr)
            R[i] = outR.run(softClip(r * sOn * 1.2) * 0.8, f: 12000, sr: sr)
        }
    }
}
