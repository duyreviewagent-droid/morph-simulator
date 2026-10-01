// Morph Simulator audio, ported from Sources/Audio.swift, Synths.swift and DSP.swift.
// Every sound is synthesised in code. One-shots are rendered lazily into AudioBuffers
// (and cached); the farm ambience and the country score run sample-by-sample in an
// AudioWorklet (ScriptProcessor fallback). No imports, so the pure synthesis also runs in Node:
//   import { synth, names, selfCheck, AmbienceSynth, MusicSynth } from './audio.js'

// MARK: - DSP + continuous synths
// Everything the worklet needs lives inside this one function: it is called here directly
// and also stringified into the worklet's Blob source, so there is a single copy of the code.
function synthLib() {
  const PI = Math.PI, TP = 2 * Math.PI

  const softClip = x => { const c = Math.max(-3, Math.min(3, x)); return c * (27 + c * c) / (27 + 9 * c * c) }
  const midiHz = m => 440 * Math.pow(2, (m - 69) / 12)
  const smoothstep = (e0, e1, x) => { const t = Math.min(Math.max((x - e0) / (e1 - e0), 0), 1); return t * t * (3 - 2 * t) }
  const mixf = (a, b, t) => a + (b - a) * t
  const clampf = (x, a, b) => Math.min(Math.max(x, a), b)
  const panL = p => Math.cos((Math.max(-1, Math.min(1, p)) + 1) * PI / 4) * 1.414
  const panR = p => Math.sin((Math.max(-1, Math.min(1, p)) + 1) * PI / 4) * 1.414

  // xorshift32, exactly as Noise32
  class Noise32 {
    constructor(s) { this.s = s >>> 0 }
    next() {
      let s = this.s
      s = (s ^ (s << 13)) >>> 0; s = (s ^ (s >>> 17)) >>> 0; s = (s ^ (s << 5)) >>> 0
      this.s = s
      return s / 2147483648 - 1
    }
  }

  // splitmix64 (RNG in Util.swift) on two 32-bit halves; bit-exact with the Swift version.
  let mh = 0, ml = 0
  function mul64(ah, al, bh, bl) {
    const a0 = al & 0xFFFF, a1 = al >>> 16, b0 = bl & 0xFFFF, b1 = bl >>> 16
    const mid = a0 * b1 + a1 * b0
    const lo = a0 * b0 + (mid % 65536) * 65536
    const carry = Math.floor(lo / 4294967296)
    ml = lo >>> 0
    mh = (a1 * b1 + Math.floor(mid / 65536) + carry + Math.imul(ah, bl) + Math.imul(al, bh)) >>> 0
  }
  class RNG {
    constructor(seed) { this.lo = seed >>> 0; this.hi = Math.floor(seed / 4294967296) >>> 0; this.zh = 0; this.zl = 0 }
    next() {
      const lo = (this.lo + 0x7F4A7C15) >>> 0
      const hi = (this.hi + 0x9E3779B9 + (lo < 0x7F4A7C15 ? 1 : 0)) >>> 0
      this.lo = lo; this.hi = hi
      let zl = (lo ^ ((lo >>> 30) | (hi << 2))) >>> 0, zh = (hi ^ (hi >>> 30)) >>> 0
      mul64(zh, zl, 0xBF58476D, 0x1CE4E5B9); zh = mh; zl = ml
      zl = (zl ^ ((zl >>> 27) | (zh << 5))) >>> 0; zh = (zh ^ (zh >>> 27)) >>> 0
      mul64(zh, zl, 0x94D049BB, 0x133111EB); zh = mh; zl = ml
      this.zl = (zl ^ ((zl >>> 31) | (zh << 1))) >>> 0; this.zh = (zh ^ (zh >>> 31)) >>> 0
    }
    float() { this.next(); return (this.zh >>> 8) / 16777216 }
    range(a, b) { return a + (b - a) * this.float() }
    chance(p) { return this.float() < p }
    int(n) { this.next(); return ((this.zh % n) * 4294967296 + this.zl) % n }
  }

  // Two-pole resonator; coefficients are cached while f/q stay the same (same output, less trig).
  class Reso {
    constructor() { this.y1 = 0; this.y2 = 0; this.f = NaN; this.q = NaN; this.sr = 0; this.a = 0; this.b = 0; this.c = 0 }
    run(x, f, q, sr) {
      if (f !== this.f || q !== this.q || sr !== this.sr) {
        this.f = f; this.q = q; this.sr = sr
        const w = TP * Math.min(f, sr * 0.45) / sr
        const r = Math.max(0, 1 - w / (2 * q))
        this.a = (1 - r) * 2 * Math.sin(w); this.b = 2 * r * Math.cos(w); this.c = r * r
      }
      const y = x * this.a + this.b * this.y1 - this.c * this.y2
      this.y2 = this.y1; this.y1 = y
      return y
    }
  }
  class LP1 {
    constructor() { this.y = 0; this.f = NaN; this.sr = 0; this.a = 0 }
    run(x, f, sr) {
      if (f !== this.f || sr !== this.sr) { this.f = f; this.sr = sr; this.a = 1 - Math.exp(-TP * f / sr) }
      this.y += (x - this.y) * this.a
      return this.y
    }
  }

  // MARK: The farm around you
  const LARK = [[0, 0.25, 2600], [0.3, 0.12, 3300], [0.45, 0.1, 2900], [0.6, 0.3, 2400], [0.95, 0.12, 2200], [1.1, 0.4, 1900]]
  class AmbienceSynth {
    constructor(sampleRate) {
      this.sr = sampleRate
      this.level = 1; this.rush = 0; this.on = 1
      this.n = new Noise32(0xFA12); this.n2 = new Noise32(0x77); this.rng = new RNG(0xFA)
      this.lv = 0; this.rs = 0
      this.wind1 = new Reso(); this.windLP = new LP1(); this.slow = new LP1(); this.slow2 = new LP1()
      this.leaf = new Reso(); this.leafEnv = 0; this.leafLP = new LP1()
      this.rushL = new Reso(); this.rushR = new Reso()
      this.birdGap = 1; this.birdLeft = 0; this.birdT = 0; this.birdPh = 0; this.birdF = 3000; this.birdPan = 0; this.birdCall = 0.1; this.birdKind = 0; this.birdA = 0
      this.larkGap = 9; this.larkT = 99; this.larkPh = 0; this.larkPan = 0
      this.crowGap = 20; this.crowLeft = 0; this.crowT = 0; this.crowPh = 0; this.crowPan = 0; this.crowR = new Reso(); this.crowR2 = new Reso()
      this.bugPh = 0; this.bugAM = 0; this.bugR = new Reso(); this.bugLevel = 0; this.bugTarget = 0; this.bugGap = 5
      this.outL = new LP1(); this.outR = new LP1()
    }
    render(frames, L, R, add) {
      const sr = this.sr, inv = 1 / sr, rng = this.rng, n = this.n, n2 = this.n2
      for (let i = 0; i < frames; i++) {
        this.lv += (this.level * this.on - this.lv) * 0.0002
        this.rs += (this.rush - this.rs) * 0.0008
        let l = 0, r = 0
        // wind across open fields, slowly gusting
        const x = n.next()
        const g = 0.5 + this.slow2.run(this.slow.run(n2.next(), 0.15, sr), 0.3, sr) * 60
        const gust = Math.max(0.15, Math.min(1.6, g))
        const w = this.windLP.run(this.wind1.run(x, 380 + gust * 220, 0.6, sr), 1400, sr) * 0.08 * gust
        l += w; r += w * 0.9
        // leaves rustling in the gusts
        this.leafEnv += ((gust > 1 ? (gust - 1) : 0) * 1.5 - this.leafEnv) * 0.0005
        const lf = this.leafLP.run(this.leaf.run(n2.next(), 5200, 0.7, sr), 9000, sr) * this.leafEnv * 0.05 * (0.5 + 0.5 * Math.abs(x))
        l += lf * 0.7; r += lf * 1.1
        // rush of wind when fast
        const rs = this.rs
        if (rs > 0.01) {
          const a = rs * rs * 0.25
          l += this.rushL.run(n.next(), 500 + rs * 900, 0.5, sr) * a
          r += this.rushR.run(n2.next(), 560 + rs * 950, 0.5, sr) * a
        }
        // songbirds
        this.birdGap -= inv
        if (this.birdGap < 0 && this.birdLeft === 0) {
          this.birdGap = rng.range(1.5, 6)
          this.birdKind = rng.int(3)
          this.birdLeft = this.birdKind === 2 ? 1 : 3 + rng.int(6)
          this.birdT = 0; this.birdF = rng.range(2800, 4600); this.birdPan = rng.range(-0.9, 0.9)
          this.birdCall = this.birdKind === 2 ? 0.5 : rng.range(0.05, 0.1)
          this.birdA = rng.range(0.006, 0.016)
        }
        if (this.birdLeft > 0) {
          this.birdT += inv
          const u = this.birdT / this.birdCall
          if (u < 1) {
            let f = this.birdF
            if (this.birdKind === 0) f *= 1 + 0.3 * Math.sin(PI * u)
            else if (this.birdKind === 1) f *= 1.25 - 0.4 * u
            else f *= 1 + 0.08 * Math.sin(TP * 28 * this.birdT)
            this.birdPh += f * inv; if (this.birdPh > 1) this.birdPh -= 1
            const s = Math.sin(TP * this.birdPh) * Math.sin(PI * u) * this.birdA * 3
            l += s * panL(this.birdPan); r += s * panR(this.birdPan)
          } else if (u > 1.5) { this.birdLeft -= 1; this.birdT = 0 }
        }
        // western meadowlark phrase
        this.larkGap -= inv
        if (this.larkGap < 0) { this.larkGap = rng.range(14, 30); this.larkT = 0; this.larkPan = rng.range(-1, 1) }
        if (this.larkT < 1.6) {
          this.larkT += inv
          const lt = this.larkT
          for (let k = 0; k < 6; k++) {
            const t0 = LARK[k][0], d = LARK[k][1]
            if (lt >= t0 && lt < t0 + d) {
              const u = (lt - t0) / d
              this.larkPh += LARK[k][2] * (1 - 0.1 * u) * inv; if (this.larkPh > 1) this.larkPh -= 1
              const s = Math.sin(TP * this.larkPh) * Math.sin(PI * u) * 0.02
              l += s * panL(this.larkPan); r += s * panR(this.larkPan)
            }
          }
        }
        // a crow somewhere far off
        this.crowGap -= inv
        if (this.crowGap < 0 && this.crowLeft === 0) { this.crowGap = rng.range(25, 60); this.crowLeft = 2 + rng.int(3); this.crowT = 0; this.crowPan = rng.range(-1, 1) }
        if (this.crowLeft > 0) {
          this.crowT += inv
          if (this.crowT < 0.3) {
            const u = this.crowT / 0.3
            const f = 520 - 120 * u
            this.crowPh += f * inv; if (this.crowPh > 1) this.crowPh -= 1
            const buzz = (this.crowPh < 0.3 ? 1 : -0.4) * (0.7 + 0.3 * n.next())
            const s = (this.crowR.run(buzz, 1300, 3, sr) + this.crowR2.run(buzz, 2200, 4, sr) * 0.5) * Math.sin(PI * u) * 0.01
            l += s * panL(this.crowPan); r += s * panR(this.crowPan)
          } else if (this.crowT > 0.55) { this.crowLeft -= 1; this.crowT = 0 }
        }
        // grasshoppers
        this.bugGap -= inv
        if (this.bugGap < 0) { this.bugGap = rng.range(3, 9); this.bugTarget = rng.chance(0.5) ? rng.range(0.3, 1) : 0 }
        this.bugLevel += (this.bugTarget - this.bugLevel) * 0.00005
        if (this.bugLevel > 0.01) {
          this.bugAM += 31 * inv; if (this.bugAM > 1) this.bugAM -= 1
          const pulse = this.bugAM < 0.35 ? 1 : 0
          const s = this.bugR.run(n.next(), 6500, 8, sr) * pulse * this.bugLevel * 0.012
          l += s * 1.1; r += s * 0.8
        }
        const ol = this.outL.run(l, 11000, sr) * this.lv, or = this.outR.run(r, 11000, sr) * this.lv
        if (add) { L[i] += ol; R[i] += or } else { L[i] = ol; R[i] = or }
      }
    }
  }

  // MARK: Score: acoustic country, plucked strings
  /// Karplus-Strong string with an allpass for exact tuning.
  class KString {
    constructor() {
      this.buf = new Float32Array(2400); this.n = 100; this.idx = 0; this.last = 0
      this.c = 0; this.apX = 0; this.apY = 0; this.decay = 0.996; this.amp = 0; this.pan = 0; this.gl = 1; this.gr = 1; this.age = 99
    }
    pluck(f, a, sr, bright, d, rng, p) {
      const period = sr / f - 0.5
      const n = Math.max(2, Math.min(2399, Math.trunc(period)))
      this.n = n
      const frac = period - n
      this.c = (1 - frac) / (1 + frac)
      const buf = this.buf
      let lp = 0
      for (let k = 0; k < n; k++) { const x = rng.range(-1, 1); lp += (x - lp) * bright; buf[k] = lp }
      // pick position: a comb notch softens the attack
      const pp = Math.max(1, Math.trunc(n / 7))
      for (let k = n - 1; k >= pp; k--) buf[k] -= buf[k - pp] * 0.5
      this.idx = 0; this.last = 0; this.apX = 0; this.apY = 0
      this.decay = d; this.amp = a; this.pan = p; this.gl = panL(p); this.gr = panR(p); this.age = 0
    }
    tick() {
      const buf = this.buf, cur = buf[this.idx]
      const avg = this.decay * 0.5 * (cur + this.last)
      const ap = this.c * avg + this.apX - this.c * this.apY
      this.apX = avg; this.apY = ap
      buf[this.idx] = ap
      this.last = cur
      if (++this.idx >= this.n) this.idx = 0
      return ap * this.amp
    }
  }

  const MOODS = { menu: 0, play: 1, quiet: 2 }
  // G C G D | G C D G   and a bridge   Em C G D | Em C D D
  const PROG = [0, 1, 0, 2, 0, 1, 2, 0, 3, 1, 0, 2, 3, 1, 2, 2]
  const BASS_ROOT = [31, 36, 38, 28], BASS_ALT = [38, 31, 33, 35], G_BASS = [43, 48, 50, 40], G_ALT = [50, 43, 45, 47]
  const TREBLE = [[55, 59, 62, 67], [52, 55, 60, 64], [54, 57, 62, 66], [52, 55, 59, 64]]
  const TUNE = [
    71, 0, 74, 0, 74, 72, 71, 0, 72, 0, 76, 0, 76, 74, 72, 0, 71, 0, 67, 0, 69, 71, 74, 0, 69, 0, 0, 0, 66, 67, 69, 0,
    71, 0, 74, 0, 79, 0, 76, 74, 76, 0, 72, 0, 69, 0, 67, 0, 69, 0, 71, 72, 74, 0, 72, 71, 67, 0, 0, 0, 0, 0, 0, 0,
    76, 0, 76, 74, 71, 0, 67, 0, 72, 0, 76, 0, 79, 0, 76, 0, 74, 0, 71, 0, 67, 0, 71, 74, 74, 0, 72, 0, 69, 0, 66, 0,
    76, 0, 74, 71, 72, 0, 76, 0, 74, 0, 71, 0, 69, 0, 67, 66, 67, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]

  class MusicSynth {
    constructor(sampleRate) {
      this.sr = sampleRate
      this.on = 1; this.mood = 0; this.energy = 0.5
      this.sc = 0; this.step = -1; this.sps = 1
      this.rng = new RNG(0xC0417); this.n = new Noise32(0xB8)
      this.lastMood = 2
      this.strings = []; for (let k = 0; k < 12; k++) this.strings.push(new KString())
      this.sNext = 0
      this.bass = new KString(); this.bassLP = new LP1()
      this.brushT = 9; this.brushA = 0; this.brushLP = new LP1(); this.brushHP = 0
      this.tickT = 9; this.tickA = 0; this.tickHP = 0
      this.kickT = 9; this.kickPh = 0
      this.hF = 392; this.hTF = 392; this.hA = 0; this.hTA = 0; this.hPh = 0; this.hVib = 0
      this.hF1 = new Reso(); this.hF2 = new Reso(); this.hLP = new LP1()
      this.sOn = 0; this.en = 0
      this.outL = new LP1(); this.outR = new LP1()
      this.revL = new Float32Array(9000); this.revR = new Float32Array(9000); this.revI = 0
    }
    setMood(m) { this.mood = typeof m === 'number' ? m : (MOODS[m] ?? 0) }
    bpm(b) { return Math.trunc(this.sr * 60 / b / 2) }     // eighth notes
    pluck(m, a, bright = 0.5, pan = 0, decay = 0.996) {
      this.strings[this.sNext].pluck(midiHz(m), a, this.sr, bright, decay, this.rng, pan)
      this.sNext = (this.sNext + 1) % this.strings.length
    }
    tick() {
      this.step += 1
      if (this.mood !== this.lastMood) { this.lastMood = this.mood; this.step = 0 }
      const e8 = this.step % 8, bar = Math.trunc(this.step / 8), sr = this.sr
      this.hTA = 0
      if (this.mood === 0) {
        this.sps = this.bpm(84)
        const ch = PROG[bar % 8], tr = TREBLE[ch]
        switch (e8) {
          case 0: this.pluck(G_BASS[ch], 0.5, 0.35, -0.2); break
          case 2: this.pluck(tr[1], 0.28, 0.45, 0.2); break
          case 3: this.pluck(tr[2], 0.24, 0.45, 0.25); break
          case 4: this.pluck(G_ALT[ch], 0.42, 0.35, -0.2); break
          case 5: this.pluck(tr[3], 0.22, 0.5, 0.3); break
          case 6: this.pluck(tr[2], 0.22, 0.45, 0.25); break
          case 7: if (bar % 2 === 1) this.pluck(tr[0], 0.2, 0.45, 0.2); break
        }
        if (e8 === 0 && bar % 4 === 0) this.bass.pluck(midiHz(BASS_ROOT[ch] + 12), 0.5, sr, 0.2, 0.998, this.rng, 0)
      } else if (this.mood === 1) {
        this.sps = this.bpm(104)
        const ch = PROG[bar % 16], tr = TREBLE[ch]
        // Travis picking: alternating bass with the thumb, melody on the offbeats
        switch (e8) {
          case 0: this.pluck(G_BASS[ch], 0.55, 0.4, -0.25); this.pluck(tr[3], 0.25, 0.55, 0.3); break
          case 1: this.pluck(tr[2], 0.22, 0.5, 0.25); break
          case 2: this.pluck(G_ALT[ch], 0.45, 0.4, -0.25); break
          case 3: this.pluck(tr[1], 0.22, 0.5, 0.2); break
          case 4: this.pluck(G_BASS[ch], 0.5, 0.4, -0.25); this.pluck(tr[2], 0.2, 0.5, 0.25); break
          case 5: this.pluck(tr[3], 0.2, 0.55, 0.3); break
          case 6: this.pluck(G_ALT[ch], 0.45, 0.4, -0.25); break
          case 7: this.pluck(tr[1], 0.22, 0.5, 0.2); break
        }
        // upright bass on 1 and 3
        if (e8 === 0) this.bass.pluck(midiHz(BASS_ROOT[ch]), 0.9, sr, 0.25, 0.997, this.rng, 0)
        if (e8 === 4) this.bass.pluck(midiHz(BASS_ALT[ch]), 0.8, sr, 0.25, 0.997, this.rng, 0)
        // brushes: swish on 2 and 4, soft ticks, kick on 1 and 3
        if (e8 === 2 || e8 === 6) { this.brushT = 0; this.brushA = 1 }
        if (e8 % 2 === 1) { this.tickT = 0; this.tickA = 0.5 }
        if (e8 === 0 || e8 === 4) { this.kickT = 0; this.kickPh = 0 }
        // harmonica comes in for the second half of each 32-bar cycle
        const cyc = bar % 32
        if (cyc >= 16) {
          const m = TUNE[((cyc - 16) * 8 + e8) % TUNE.length]
          if (m > 0) { this.hTF = midiHz(m); this.hTA = 1 } else { this.hTA = this.hA > 0.3 && e8 % 2 === 1 ? 1 : 0 }
        }
      } else {
        this.sps = this.bpm(100)
      }
    }
    render(frames, L, R, add) {
      const sr = this.sr, inv = 1 / sr
      const target = this.on * (this.mood === 2 ? 0 : 1)
      const strings = this.strings, nS = strings.length, rN = this.revL.length, revL = this.revL, revR = this.revR, n = this.n
      for (let i = 0; i < frames; i++) {
        if (this.sc === 0) this.tick()
        this.sc += 1
        // a gentle shuffle
        const len = this.step % 2 === 0 ? Math.trunc(this.sps * 112 / 100) : Math.trunc(this.sps * 88 / 100)
        if (this.sc >= len) this.sc = 0
        this.sOn += (target - this.sOn) * 0.00008
        this.en += (this.energy - this.en) * 0.00005
        let l = 0, r = 0, gtr = 0, gtrR = 0
        for (let k = 0; k < nS; k++) {
          const st = strings[k]
          if (!(st.amp > 0.0005)) continue
          const s = st.tick()
          gtr += s * st.gl; gtrR += s * st.gr
          st.age += inv
          if (st.age > 4) st.amp = 0
        }
        // guitar body warmth
        l += gtr * 0.32; r += gtrR * 0.32
        if (this.bass.amp > 0.0005) {
          const b = this.bassLP.run(this.bass.tick(), 500, sr) * 0.55
          l += b; r += b
        }
        if (this.kickT < 0.3) {
          this.kickT += inv
          this.kickPh += (55 + 60 * Math.exp(-this.kickT * 30)) * inv
          const k = Math.sin(TP * this.kickPh) * Math.exp(-this.kickT * 14) * 0.12
          l += k; r += k
        }
        if (this.brushT < 0.35) {
          this.brushT += inv
          const x = n.next()
          this.brushHP += (x - this.brushHP) * 0.3
          const env = Math.min(1, this.brushT * 60) * Math.exp(-this.brushT * 9)
          const s = this.brushLP.run(x - this.brushHP, 5000, sr) * env * 0.05 * this.brushA
          l += s * 0.9; r += s * 1.1
        }
        if (this.tickT < 0.1) {
          this.tickT += inv
          const x = n.next()
          this.tickHP += (x - this.tickHP) * 0.5
          const s = (x - this.tickHP) * Math.exp(-this.tickT * 60) * 0.018 * this.tickA
          l += s * 1.1; r += s * 0.9
        }
        // harmonica: a reedy pulse through two formants, with vibrato and breath
        this.hF += (this.hTF - this.hF) * 0.006
        this.hA += (this.hTA - this.hA) * (this.hTA > this.hA ? 0.003 : 0.0012)
        if (this.hA > 0.002) {
          this.hVib += 5.5 * inv; if (this.hVib > 1) this.hVib -= 1
          const f = this.hF * (1 + 0.008 * Math.sin(TP * this.hVib) * this.hA)
          this.hPh += f * inv; if (this.hPh > 1) this.hPh -= 1
          const reed = (this.hPh < 0.4 ? 1 : -0.66) + n.next() * 0.06
          const s = (this.hF1.run(reed, 1100, 2, sr) + this.hF2.run(reed, 2400, 3, sr) * 0.5 + this.hLP.run(reed, 900, sr) * 0.4) * this.hA * 0.05
          l += s * 1.05; r += s * 0.95
        }
        // small room
        const ri = this.revI
        const d1 = (ri + rN - 2111) % rN, d2 = (ri + rN - 3371) % rN
        const wl = revL[d1] * 0.5 + revR[d2] * 0.25, wr = revR[d1] * 0.5 + revL[d2] * 0.25
        revL[ri] = l * 0.5 + wl * 0.45
        revR[ri] = r * 0.5 + wr * 0.45
        this.revI = (ri + 1) % rN
        l += wl * 0.3; r += wr * 0.3
        const ol = this.outL.run(softClip(l * this.sOn * 1.2) * 0.8, 12000, sr)
        const or = this.outR.run(softClip(r * this.sOn * 1.2) * 0.8, 12000, sr)
        if (add) { L[i] += ol; R[i] += or } else { L[i] = ol; R[i] = or }
      }
    }
  }

  return { softClip, midiHz, smoothstep, mixf, clampf, panL, panR, Noise32, RNG, Reso, LP1, AmbienceSynth, MusicSynth, KString, MOODS }
}

const LIB = synthLib()
const { midiHz, smoothstep, mixf, clampf, Noise32, RNG, Reso, LP1 } = LIB
export const { AmbienceSynth, MusicSynth } = LIB
export { RNG }

// MARK: - One-shot synthesis (Audio.swift buildBuffers / buildCalls)

const tau = 2 * Math.PI
const sinf = Math.sin, cosf = Math.cos, expf = Math.exp, powf = Math.pow, floorf = Math.floor, abs = Math.abs
let SR = 48000          // sample rate of the buffer being synthesised (synthesis is synchronous)

/// make(): gen(t) returns a mono sample, or [l, r] when `stereo`. Normalises and fades the tail like Swift.
function make(dur, norm, gen, stereo = false) {
  const frames = Math.trunc(dur * SR)
  const L = new Float32Array(frames), R = new Float32Array(frames)
  for (let i = 0; i < frames; i++) {
    const t = i / SR
    let l, r
    if (stereo) { const o = gen(t); l = o[0]; r = o[1] } else { l = r = gen(t) }
    L[i] = Number.isFinite(l) ? l : 0; R[i] = Number.isFinite(r) ? r : 0
  }
  let peak = 0
  for (let i = 0; i < frames; i++) peak = Math.max(peak, abs(L[i]), abs(R[i]))
  const want = norm ?? Math.min(0.9, peak)
  if (peak > 0) { const g = want / peak; for (let i = 0; i < frames; i++) { L[i] *= g; R[i] *= g } }
  const fade = Math.min(frames, Math.trunc(0.006 * SR))
  for (let k = 0; k < fade; k++) { const g = k / fade; L[frames - 1 - k] *= g; R[frames - 1 - k] *= g }
  return { L, R }
}

/// A voiced sound: a glottal pulse train through formant resonators.
function voice(dur, { norm = 0.8, seed, breath = 0.08, rasp = 0, f0, fm, env, nasal = null }) {
  let ph = 0
  const nz = new Noise32(seed)
  const r1 = new Reso(), r2 = new Reso(), r3 = new Reso(), nasalLP = new LP1(), raspLP = new LP1(), src = new LP1()
  const fsr = SR
  return make(dur, norm, t => {
    const rough = 1 + raspLP.run(nz.next(), 90, fsr) * rasp * 6
    let f = f0(t) * (1 + 0.004 * nz.next())
    f *= Math.max(0.5, rough)
    ph += f / fsr
    if (ph > 1) ph -= 1
    // Rosenberg-like pulse: open phase then a sharp closure
    const open = 0.6
    let g = ph < open ? (0.5 - 0.5 * cosf(Math.PI * ph / open)) : cosf(Math.PI * (ph - open) / (2 * (1 - open)))
    g = g - 0.4
    const s = src.run(g, 4000, fsr) + nz.next() * breath
    const F = fm(t)
    let o = r1.run(s, F[0], 5, fsr) + r2.run(s, F[1], 7, fsr) * 0.6 + r3.run(s, F[2], 9, fsr) * 0.25
    if (nasal) {
      const m = nasal(t)
      o = mixf(o, nasalLP.run(s, 320, fsr) * 1.4, m)
    }
    return o * env(t)
  })
}

const GEN = {}        // buffer key -> () => {L, R}   (uses SR)
const VARIANTS = {}   // group name -> count
const set = (name, count, gen) => { VARIANTS[name] = count; for (let i = 0; i < count; i++) GEN[`${name}_${i}`] = () => gen(i) }
const one = (name, gen) => { GEN[name] = gen }

// footsteps
set('step_shoe', 4, v => {
  const n = new Noise32(10 + v), lp = new LP1(), bp = new Reso()
  const rr = new RNG(20 + v), f = rr.range(70, 95)
  return make(0.22, 0.5, t => {
    const x = n.next()
    return sinf(tau * f * t) * expf(-t * 35) * 0.8 + lp.run(x, 700, SR) * expf(-t * 30) * 2.5 + bp.run(x, 3500, 1, SR) * expf(-t * 18) * 0.4
  })
})
set('step_hoof', 4, v => {
  const n = new Noise32(30 + v), r1 = new Reso(), r2 = new Reso(), lp = new LP1()
  const rr = new RNG(40 + v), f1 = rr.range(420, 620), f2 = rr.range(1100, 1500)
  return make(0.3, 0.6, t => {
    const x = n.next()
    return r1.run(x, f1, 9, SR) * expf(-t * 28) * 2.2 + r2.run(x, f2, 7, SR) * expf(-t * 45) + sinf(tau * 65 * t) * expf(-t * 22) * 0.9 + lp.run(x, 400, SR) * expf(-t * 20) * 2
  })
})
set('step_claw', 4, v => {
  const n = new Noise32(50 + v), bp = new Reso()
  const rr = new RNG(60 + v), t2 = rr.range(0.025, 0.05)
  return make(0.14, 0.35, t => {
    const x = n.next()
    let s = bp.run(x, 4200, 2, SR) * expf(-t * 90) * 1.5
    if (t > t2) s += bp.run(x, 3000, 2, SR) * expf(-(t - t2) * 110)
    s += sinf(tau * 180 * t) * expf(-t * 60) * 0.3
    return s
  })
})
set('step_wood', 3, v => {
  const n = new Noise32(70 + v), r1 = new Reso(), r2 = new Reso()
  return make(0.3, 0.55, t => {
    const x = n.next()
    return r1.run(x, 190 + v * 20, 8, SR) * expf(-t * 18) * 2 + r2.run(x, 820, 5, SR) * expf(-t * 35) * 0.8
  })
})
set('step_metal', 3, v => {
  const n = new Noise32(80 + v), rr = new RNG(90 + v)
  const modes = []; for (let k = 0; k < 5; k++) { const f = rr.range(200, 1400), d = rr.range(5, 12); modes.push([f, d]) }
  return make(0.6, 0.5, t => {
    let s = n.next() * expf(-t * 80) * 0.5
    for (const [f, d] of modes) s += sinf(tau * f * t) * expf(-t * d) * 0.25
    return s
  })
})
set('step_hay', 3, v => {
  const n = new Noise32(100 + v), bp = new Reso(), lp = new LP1()
  return make(0.3, 0.4, t => {
    const x = n.next()
    const crackle = n.next() > 0.7 ? 1.5 : 0.4
    return bp.run(x, 2400, 0.8, SR) * crackle * expf(-t * 14) + lp.run(x, 300, SR) * expf(-t * 25) * 2
  })
})
set('step_splash', 3, v => {
  const n = new Noise32(110 + v), bp = new Reso(), bp2 = new Reso()
  return make(0.45, 0.5, t => {
    const x = n.next()
    return bp.run(x, 900 + 600 * expf(-t * 8), 1.2, SR) * expf(-t * 9) + bp2.run(x, 2600, 2, SR) * expf(-t * 14) * 0.6
  })
})
set('land', 3, v => {
  const n = new Noise32(120 + v), lp = new LP1()
  return make(0.4, 0.7, t => {
    const x = n.next()
    return sinf(tau * (55 + 50 * expf(-t * 30)) * t) * expf(-t * 12) + lp.run(x, 600, SR) * expf(-t * 16) * 3
  })
})
one('jump', () => {
  const n = new Noise32(130), bp = new Reso()
  return make(0.3, 0.4, t => { const u = t / 0.3; return bp.run(n.next(), 500 + 1400 * u, 1.5, SR) * sinf(Math.PI * u) })
})
one('splash', () => {
  const n = new Noise32(140), bp = new Reso(), lp = new LP1(), rr = new RNG(141)
  // Swift shares one resonator across all droplets; where droplets overlap it is fed two different
  // coefficient sets per sample, which is unstable (it overflows ~0.22 s in and the Swift buffer
  // normalises to one click followed by silence). Here each droplet gets its own resonator.
  const drops = []; for (let k = 0; k < 30; k++) { const a = rr.range(0.1, 1.2), b = rr.range(1500, 4500); drops.push([a, b, new Reso()]) }
  return make(1.4, 0.8, t => {
    const x = n.next()
    let s = lp.run(x, 800, SR) * expf(-t * 4) * 3 + bp.run(x, 1400, 0.8, SR) * expf(-t * 5)
    s += sinf(tau * (40 + 60 * expf(-t * 10)) * t) * expf(-t * 6) * 0.7
    for (const [t0, f, dr] of drops) if (t > t0 && t < t0 + 0.04) s += dr.run(x, f * (1 + (t - t0) * 20), 15, SR) * expf(-(t - t0) * 90) * 0.8
    return [s, s * 0.95]
  }, true)
})

// morphing
set('morph', 3, v => {
  const n = new Noise32(150 + v), bp = new Reso(), lp = new LP1(), rr = new RNG(160 + v)
  const bubbles = []; for (let k = 0; k < 14; k++) { const a = rr.range(0, 0.55), b = rr.range(200, 900), c = rr.range(0.03, 0.07); bubbles.push([a, b, c]) }
  let ph = 0
  return make(0.75, 0.7, t => {
    const x = n.next()
    const sw = sinf(Math.PI * Math.min(1, t / 0.7))
    const f = 180 + 500 * powf(sw, 2) + v * 40
    ph += f / SR
    let s = sinf(tau * ph + sinf(tau * ph * 1.5) * 2.2) * sw * 0.35
    s += bp.run(x, f * 2, 3, SR) * sw * 0.6
    for (const [t0, bf, d] of bubbles) if (t > t0 && t < t0 + d) { const u = (t - t0) / d; s += sinf(tau * bf * (1 + u * 1.5) * (t - t0)) * sinf(Math.PI * u) * 0.5 }
    s += lp.run(x, 300, SR) * expf(-t * 8) * 1.5
    return [s, s * 0.9]
  }, true)
})
one('poof', () => {
  const n = new Noise32(170), bp = new Reso()
  return make(0.5, 0.5, t => bp.run(n.next(), 600 + 2500 * expf(-t * 8), 1, SR) * expf(-t * 7) * Math.min(1, t * 200))
})

// animal and human voices
set('moo', 4, v => {
  const rr = new RNG(200 + v)
  const base = rr.range(88, 118), rise = rr.range(1.25, 1.5), dur = rr.range(1.2, 1.9)
  return voice(dur, {
    norm: 0.8, seed: 210 + v, breath: 0.05, rasp: 0.18,
    f0: t => { const u = t / dur; return base * (1 + (rise - 1) * smoothstep(0, 0.25, u) - 0.22 * smoothstep(0.5, 1, u)) * (1 + 0.012 * sinf(tau * 5 * t)) },
    fm: t => { const u = t / dur; return [mixf(300, 620, smoothstep(0.1, 0.45, u)) - 120 * smoothstep(0.7, 1, u), mixf(750, 1050, smoothstep(0.2, 0.5, u)) - 200 * smoothstep(0.7, 1, u), 2500] },
    env: t => { const u = t / dur; return smoothstep(0, 0.12, u) * (1 - smoothstep(0.75, 1, u)) },
    nasal: t => 1 - smoothstep(0.08, 0.3, t / dur),
  })
})
set('cluck', 5, v => {
  const rr = new RNG(220 + v)
  const f = rr.range(330, 480), d = rr.range(0.08, 0.13)
  const syl = 1 + rr.int(3)
  const gap = 0.16, total = syl * gap + d
  const F = [780, 1700, 3100]
  return voice(total, {
    norm: 0.7, seed: 230 + v, breath: 0.15, rasp: 0.25,
    f0: t => { const k = floorf(t / gap); const u = (t - k * gap) / d; return f * (1 + 0.25 * k * 0.3) * (1.15 - 0.3 * u) },
    fm: () => F,
    env: t => { const k = floorf(t / gap); const u = (t - k * gap) / d; return u < 1 && k < syl ? Math.min(1, u * 30) * (1 - u) : 0 },
  })
})
one('bawk', () => {
  const marks = [[0, 0.1, 420], [0.18, 0.1, 440], [0.36, 0.1, 430], [0.52, 0.09, 450], [0.66, 0.12, 460], [0.8, 0.5, 700]]
  const FA = [900, 1500, 2900], FB = [760, 1700, 3100]
  return voice(1.4, {
    norm: 0.8, seed: 240, breath: 0.15, rasp: 0.35,
    f0: t => {
      for (const [t0, d, f] of marks) if (t >= t0 && t < t0 + d + 0.02) { const u = (t - t0) / d; return f * (d > 0.3 ? (0.8 + 0.4 * sinf(Math.PI * Math.min(1, u * 1.5))) : (1.1 - 0.25 * u)) }
      return 400
    },
    fm: t => t > 0.8 ? FA : FB,
    env: t => {
      for (const [t0, d] of marks) if (t >= t0 && t < t0 + d) { const u = (t - t0) / d; return Math.min(1, u * 25) * (1 - u * u) * (d > 0.3 ? 1.2 : 1) }
      return 0
    },
  })
})
one('crow', () => {
  const marks = [[0, 0.16, 560, 620], [0.2, 0.12, 520, 540], [0.36, 0.18, 640, 720], [0.58, 0.14, 700, 690], [0.76, 0.9, 760, 560]]
  const FA = [650, 1100, 2800], FB = [900, 1800, 3000]
  return voice(1.8, {
    norm: 0.85, seed: 250, breath: 0.12, rasp: 0.5,
    f0: t => {
      for (const [t0, d, a, b] of marks) if (t >= t0 && t < t0 + d + 0.03) { const u = Math.min(1, (t - t0) / d); return mixf(a, b, u) * (1 + 0.02 * sinf(tau * 7 * t)) }
      return 500
    },
    fm: t => t > 0.76 ? FA : FB,
    env: t => {
      for (const [t0, d] of marks) if (t >= t0 && t < t0 + d) { const u = (t - t0) / d; return Math.min(1, u * 20) * (1 - powf(u, 3)) }
      return 0
    },
  })
})
const VOWELS = [[730, 1090, 2440], [270, 2290, 3010], [300, 870, 2240], [530, 1840, 2480], [660, 1720, 2410], [440, 1020, 2240], [390, 1990, 2550]]
set('talk', 6, v => {
  const rr = new RNG(260 + v)
  const count = 3 + rr.int(4)
  const marks = []
  let t0 = 0
  for (let k = 0; k < count; k++) { const d = rr.range(0.09, 0.17); marks.push([t0, d, rr.int(VOWELS.length)]); t0 += d + rr.range(0.02, 0.06) }
  const total = t0 + 0.05
  const base = rr.range(105, 130)
  const cons = new Noise32(270 + v), cbp = new Reso()
  const body = voice(total, {
    norm: 0.7, seed: 275 + v, breath: 0.06,
    f0: t => base * (1.1 + 0.15 * sinf(Math.PI * t / total) - 0.25 * t / total),
    fm: t => { for (const [a, d, k] of marks) if (t >= a && t < a + d) return VOWELS[k]; return VOWELS[0] },
    env: t => { for (const [a, d] of marks) if (t >= a && t < a + d) { const u = (t - a) / d; return Math.min(1, u * 14) * Math.min(1, (1 - u) * 8) } return 0 },
  })
  // consonant bursts at each syllable onset
  const { L, R } = body, len = L.length
  for (const [a] of marks) {
    const s0 = Math.trunc(a * SR)
    for (let k = 0; k < Math.trunc(0.025 * SR); k++) {
      if (s0 + k >= len) continue
      const tt = k / SR
      const c = cbp.run(cons.next(), 4500, 1.5, SR) * expf(-tt * 150) * 0.25
      L[s0 + k] += c; R[s0 + k] += c
    }
  }
  return body
})
one('scream', () => voice(1.3, {
  norm: 0.85, seed: 280, breath: 0.2, rasp: 0.3,
  f0: t => (420 + 180 * smoothstep(0, 0.2, t) - 80 * smoothstep(0.6, 1.3, t)) * (1 + 0.04 * sinf(tau * 7 * t)),
  fm: (F => () => F)([850, 1250, 2800]),
  env: t => smoothstep(0, 0.06, t) * (1 - smoothstep(0.8, 1.3, t)),
}))
one('oof', () => voice(0.35, {
  norm: 0.7, seed: 285, breath: 0.25,
  f0: t => 150 - 50 * t, fm: (F => () => F)([450, 900, 2400]),
  env: t => Math.min(1, t * 40) * expf(-t * 7),
}))
one('hmph', () => voice(0.5, {
  norm: 0.6, seed: 286, breath: 0.2,
  f0: t => 120 - 20 * t, fm: (F => () => F)([300, 900, 2200]),
  env: t => Math.min(1, t * 20) * (1 - t / 0.5),
  nasal: () => 0.8,
}))

// actions
set('flap', 3, v => {
  const n = new Noise32(300 + v), bp = new Reso(), lp = new LP1()
  const beats = 3 + v
  return make(0.45, 0.55, t => {
    const x = n.next()
    const ph = t * beats / 0.45
    const beat = powf(Math.max(0, sinf(Math.PI * ph)), 3)
    return (bp.run(x, 700 + 800 * beat, 0.9, SR) + lp.run(x, 250, SR) * 2) * beat
  })
})
one('peck', () => {
  const n = new Noise32(310), r = new Reso()
  return make(0.25, 0.5, t => {
    let s = 0
    if (t > 0) s += r.run(n.next(), 2400, 6, SR) * expf(-t * 120) * 2
    if (t > 0.11) s += r.run(n.next(), 2400, 6, SR) * expf(-(t - 0.11) * 120) * 2
    return s
  })
})
set('munch', 3, v => {
  const n = new Noise32(320 + v), bp = new Reso(), lp = new LP1()
  return make(0.6, 0.5, t => {
    const x = n.next()
    const chew = powf(Math.max(0, sinf(tau * 3.2 * t)), 4)
    const crunch = n.next() > 0.6 ? 1.6 : 0.5
    return (bp.run(x, 1800, 1.2, SR) * crunch + lp.run(x, 250, SR) * 2) * chew
  })
})
one('crunch', () => {
  const n = new Noise32(330), bp = new Reso(), bp2 = new Reso()
  return make(0.4, 0.6, t => {
    const x = n.next()
    const crack = n.next() > 0.3 ? 1 : 0.2
    return (bp.run(x, 2600, 1.5, SR) * crack + bp2.run(x, 900, 2, SR)) * expf(-t * 11)
  })
})
one('rip', () => {
  const n = new Noise32(335), bp = new Reso()
  return make(0.35, 0.5, t => {
    const x = n.next()
    const tick = n.next() > 0.2 ? 1 : 0.1
    return bp.run(x, 3000 - 1500 * t / 0.35, 1.2, SR) * tick * sinf(Math.PI * t / 0.35)
  })
})
one('plop', () => {
  const n = new Noise32(340), lp = new LP1()
  return make(0.35, 0.55, t => sinf(tau * (300 - 180 * Math.min(1, t * 8)) * t) * expf(-t * 18) + lp.run(n.next(), 400, SR) * expf(-t * 25) * 1.5)
})
one('splat', () => {
  const n = new Noise32(350), r = new Reso(), bp = new Reso(), lp = new LP1()
  return make(0.5, 0.65, t => {
    const x = n.next()
    return r.run(x, 3200, 5, SR) * expf(-t * 90) * 1.5 + bp.run(x, 700, 1, SR) * expf(-t * 12) + lp.run(x, 200, SR) * expf(-t * 10) * 2
  })
})
one('throw', () => {
  const n = new Noise32(360), bp = new Reso()
  return make(0.4, 0.5, t => { const u = t / 0.4; return bp.run(n.next(), 400 + 1800 * sinf(Math.PI * u), 1.4, SR) * sinf(Math.PI * u) * sinf(Math.PI * u) })
})
one('pickup', () => {
  const n = new Noise32(370), bp = new Reso()
  return make(0.2, 0.4, t => bp.run(n.next(), 1200, 1, SR) * expf(-t * 25) + sinf(tau * 220 * t) * expf(-t * 30) * 0.4)
})
set('thud', 3, v => {
  const n = new Noise32(380 + v), lp = new LP1()
  const rr = new RNG(385 + v), f = rr.range(60, 95)
  return make(0.35, 0.6, t => sinf(tau * f * t) * expf(-t * 20) + lp.run(n.next(), 500, SR) * expf(-t * 25) * 2)
})
one('bonk', () => {
  const n = new Noise32(390), r1 = new Reso(), r2 = new Reso()
  return make(0.5, 0.7, t => {
    const x = n.next()
    return r1.run(x, 160, 10, SR) * expf(-t * 12) * 3 + r2.run(x, 420, 8, SR) * expf(-t * 20) + sinf(tau * 90 * t) * expf(-t * 14)
  })
})
set('clang', 2, v => {
  const n = new Noise32(400 + v), rr = new RNG(405 + v)
  const modes = []; for (let k = 0; k < 7; k++) { const f = rr.range(380, 3400), d = rr.range(3, 10); modes.push([f, d]) }
  return make(1.2, 0.6, t => {
    let s = n.next() * expf(-t * 100) * 0.6
    for (const [f, d] of modes) s += sinf(tau * f * t + sinf(tau * 4 * t) * 0.4) * expf(-t * d) * 0.25
    return [s, s * 0.95]
  }, true)
})
one('kick', () => {
  const n = new Noise32(410), r = new Reso()
  return make(0.4, 0.7, t => sinf(tau * (110 + 90 * expf(-t * 40)) * t) * expf(-t * 16) + r.run(n.next(), 900, 3, SR) * expf(-t * 50) * 1.5)
})
one('shove', () => {
  const n = new Noise32(420), lp = new LP1(), bp = new Reso()
  return make(0.5, 0.75, t => {
    const x = n.next()
    return sinf(tau * (70 + 50 * expf(-t * 25)) * t) * expf(-t * 10) * 1.2 + lp.run(x, 800, SR) * expf(-t * 14) * 3 + bp.run(x, 1600, 1, SR) * expf(-t * 30)
  })
})
one('whoosh', () => {
  const n = new Noise32(430), bp = new Reso()
  return make(0.7, 0.55, t => {
    const u = t / 0.7
    const s = bp.run(n.next(), 300 + 1500 * sinf(Math.PI * u), 2, SR) * sinf(Math.PI * u)
    return [s * (1.2 - u), s * (0.3 + u)]
  }, true)
})
set('climb', 2, v => {
  const n = new Noise32(440 + v), r1 = new Reso(), r2 = new Reso()
  return make(0.3, 0.4, t => {
    const x = n.next()
    return r1.run(x, 1900 + v * 300, 20, SR) * expf(-t * 18) + r2.run(x, 4300, 15, SR) * expf(-t * 30) * 0.5
  })
})
one('creak', () => {
  let ph = 0; const n = new Noise32(450), bp = new Reso()
  return make(0.7, 0.4, t => {
    const f = 220 + 80 * sinf(tau * 1.3 * t)
    ph += f / SR
    const stick = sinf(tau * ph) > 0.8 ? 1 : 0
    return bp.run(stick + n.next() * 0.1, 900, 5, SR) * sinf(Math.PI * t / 0.7)
  })
})
set('boom', 2, v => {
  const n = new Noise32(700 + v), lp = new LP1(), lp2 = new LP1(), bp = new Reso(), rr = new RNG(710 + v)
  const debris = []; for (let k = 0; k < 40; k++) { const a = rr.range(0.1, 1.6), b = rr.range(800, 3500); debris.push([a, b]) }
  const dr = new Reso()
  return make(2.8, 0.95, t => {
    const x = n.next()
    let s = x * expf(-t * 18) * 1.5 + lp.run(x, 900, SR) * expf(-t * 3) * 3 + lp2.run(x, 90, SR) * expf(-t * 1.2) * 7
    s += sinf(tau * (30 + 70 * expf(-t * 6)) * t) * expf(-t * 2.2) * 1.2
    s += bp.run(x, 400, 1, SR) * expf(-t * 5)
    for (const [t0, f] of debris) if (t > t0 && t < t0 + 0.05) s += dr.run(x, f, 8, SR) * expf(-(t - t0) * 80) * 0.6
    return [s, s * 0.95]
  }, true)
})
one('fanfare', () => make(1.6, 0.6, t => {
  let s = 0
  const ms = [67, 71, 74, 79]
  for (let k = 0; k < 4; k++) {
    const t0 = k * 0.1
    if (t < t0) continue
    const d = t - t0, f = midiHz(ms[k])
    let tone = 0
    for (let h = 1; h <= 6; h++) tone += sinf(tau * f * h * d) / h * (h > 2 ? expf(-d * 3) : 1)
    s += tone * expf(-d * (k === 3 ? 1.5 : 6)) * Math.min(1, d * 60)
  }
  return s
}))
one('combo', () => make(0.9, 0.45, t => {
  let s = 0
  const ms = [84, 88, 91, 96]
  for (let k = 0; k < 4; k++) {
    const t0 = k * 0.06
    if (t < t0) continue
    const d = t - t0, f = midiHz(ms[k])
    s += (sinf(tau * f * d) + 0.3 * sinf(tau * f * 2.76 * d) * expf(-d * 20)) * expf(-d * 5) * Math.min(1, d * 500)
  }
  return s
}))
one('click', () => {
  const n = new Noise32(5)
  return make(0.03, 0.35, t => sinf(tau * 2400 * t) * expf(-t * 400) * 0.4 + n.next() * expf(-t * 1500) * 0.2)
})
one('select', () => make(0.12, 0.4, t => sinf(tau * (700 + 700 * t / 0.12) * t) * expf(-t * 20)))
one('nope', () => {
  let ph = 0
  return make(0.3, 0.35, t => {
    ph += 140 / SR; if (ph > 1) ph -= 1
    return (ph < 0.5 ? 1 : -1) * 0.5 * (t < 0.12 || t > 0.16 ? 1 : 0) * (1 - t / 0.3)
  })
})

// MARK: animal calls (Zoo.defs order: [voice, size, plan]; ids 0-2 are custom and get no call_ buffer)
const ZOO = [['talk',1,'biped'],['cluck',1,'bird'],['moo',1,'quad'],['oink',0.85,'quad'],['neigh',1.1,'quad'],['baa',0.8,'quad'],['bleat',0.8,'quad'],['bray',0.95,'quad'],['quack',0.7,'bird'],['honk',0.85,'bird'],['gobble',1.0,'bird'],['bark',0.75,'quad'],['meow',0.6,'quad'],['squeak',0.6,'hopper'],['squeak',0.45,'quad'],['squeak',0.5,'quad'],['squeak',0.45,'quad'],['squeak',0.5,'quad'],['bleat',1.0,'quad'],['bleat',0.85,'quad'],['moo',1.15,'quad'],['squawk',0.6,'bird'],['coo',0.55,'bird'],['roar',1.05,'quad'],['roar',1.05,'quad'],['growl',0.85,'quad'],['chirp',0.85,'quad'],['howl',0.9,'quad'],['yip',0.65,'quad'],['roar',1.3,'quad'],['growl',1.35,'quad'],['grunt',1.1,'quad'],['chatter',0.6,'quad'],['bleat',0.95,'quad'],['bellow',1.4,'quad'],['grunt',1.0,'quad'],['grunt',1.3,'quad'],['snort',1.3,'quad'],['neigh',1.0,'quad'],['trumpet',1.6,'quad'],['snort',1.4,'quad'],['bellow',1.45,'quad'],['hoo',1.2,'biped'],['hoo',0.85,'biped'],['screech',0.6,'biped'],['hoo',1.0,'biped'],['grunt',1.0,'hopper'],['grunt',0.6,'biped'],['squeak',0.75,'biped'],['screech',0.5,'biped'],['squeak',0.45,'quad'],['chatter',0.55,'quad'],['chatter',0.45,'quad'],['grunt',0.7,'quad'],['chirp',0.65,'quad'],['bellow',1.4,'quad'],['chirp',0.5,'biped'],['snort',1.0,'quad'],['squeak',0.55,'quad'],['bark',0.95,'fish'],['bellow',1.3,'fish'],['grunt',1.2,'bird'],['squawk',0.85,'bird'],['hoot',0.7,'bird'],['screech',0.9,'bird'],['honk',0.9,'bird'],['screech',0.9,'bird'],['caw',0.55,'bird'],['honk',1.0,'bird'],['squawk',0.6,'bird'],['tweet',0.4,'bird'],['grunt',1.0,'bird'],['grunt',1.15,'bird'],['hiss',1.25,'sprawl'],['hiss',0.5,'sprawl'],['hiss',0.75,'sprawl'],['hiss',0.55,'sprawl'],['hiss',0.7,'sprawl'],['hiss',0.85,'sprawl'],['hiss',0.8,'slither'],['hiss',0.9,'slither'],['ribbit',0.5,'hopper'],['hiss',1.2,'sprawl'],['squeak',0.5,'sprawl'],['blub',0.5,'fish'],['blub',1.3,'fish'],['click',1.1,'fish'],['whale',1.4,'fish'],['whale',1.7,'fish'],['blub',0.8,'tentacle'],['click',0.6,'spider'],['click',0.7,'insect'],['blub',0.55,'fish'],['blub',0.7,'tentacle'],['buzz',0.5,'insect'],['chirp',0.45,'insect'],['buzz',0.45,'insect'],['buzz',0.45,'insect'],['hiss',0.55,'spider'],['squeak',0.45,'slither']]

function syl(t, marks) {
  for (let k = 0; k < marks.length; k++) { const a = marks[k][0], d = marks[k][1]; if (t >= a && t < a + d) return [k, (t - a) / d] }
  return null
}
const cenv = (u, atk = 0.08) => smoothstep(0, atk, u) * (1 - smoothstep(0.7, 1, u))
const sylU = (t, marks) => { const s = syl(t, marks); return s ? s[1] : 0 }

function buildCall(id) {
  const [vc, size, plan] = ZOO[id]
  const ps = clampf(1 / powf(size, 0.6), 0.6, 2.0), fs = Math.sqrt(ps)
  const seed = 500 + id
  const fsr = SR
  const K = F => () => F
  switch (vc) {
    case 'neigh':
      return voice(1.4, { seed, breath: 0.12, rasp: 0.35, f0: t => (900 - 480 * smoothstep(0, 1.2, t)) * ps * (1 + 0.06 * sinf(tau * 17 * t)),
        fm: K([700 * fs, 1300 * fs, 2600]), env: t => cenv(t / 1.4, 0.05) * (0.7 + 0.3 * sinf(tau * 9 * t)) })
    case 'oink': case 'grunt': case 'snort': {
      const n = vc === 'snort' ? 1 : 3
      const marks = []; for (let k = 0; k < n; k++) marks.push([k * 0.2, 0.13])
      return voice(n * 0.2 + 0.1, { seed, breath: vc === 'snort' ? 0.8 : 0.2, rasp: 0.8,
        f0: t => (vc === 'grunt' ? 110 : 190) * ps * (1.1 - 0.2 * sylU(t, marks)),
        fm: K([500 * fs, 1100 * fs, 2400]), env: t => { const s = syl(t, marks); return s ? cenv(s[1], 0.1) : 0 }, nasal: () => 0.65 })
    }
    case 'baa': case 'bleat': {
      const baa = vc === 'baa', dur = baa ? 1.0 : 0.75
      return voice(dur, { seed, breath: 0.1, rasp: 0.25, f0: t => (baa ? 330 : 420) * ps * (1 + 0.03 * sinf(tau * 7 * t)),
        fm: t => [mixf(500, 800, smoothstep(0, 0.2, t)) * fs, (baa ? 1300 : 1700) * fs, 2600],
        env: t => cenv(t / dur, 0.1) * (0.6 + 0.4 * abs(sinf(tau * (baa ? 3.5 : 4.5) * t))) })
    }
    case 'bray': {
      const marks = [[0, 0.35], [0.4, 0.4], [0.85, 0.35], [1.25, 0.45]]
      return voice(1.8, { seed, breath: 0.25, rasp: 0.6,
        f0: t => { const s = syl(t, marks); return (s ? (s[0] % 2 === 0 ? 650 : 230) : 300) * ps },
        fm: t => { const s = syl(t, marks); const f1 = s ? (s[0] % 2 === 0 ? 400 : 750) : 600; return [f1 * fs, 1200 * fs, 2500] },
        env: t => { const s = syl(t, marks); return s ? cenv(s[1], 0.15) : 0 } })
    }
    case 'bark': case 'yip': {
      const yip = vc === 'yip'
      const marks = yip ? [[0, 0.08], [0.14, 0.08], [0.28, 0.1]] : [[0, 0.16], [0.3, 0.18]]
      return voice(yip ? 0.45 : 0.55, { seed, breath: 0.15, rasp: 0.5,
        f0: t => (yip ? 950 : 420) * ps * (1.15 - 0.4 * sylU(t, marks)),
        fm: K([(yip ? 900 : 700) * fs, 1500 * fs, 2700]),
        env: t => { const s = syl(t, marks); return s ? Math.min(1, s[1] * 30) * (1 - s[1]) : 0 } })
    }
    case 'meow':
      return voice(0.8, { seed, breath: 0.08, rasp: 0.1, f0: t => (500 + 220 * sinf(Math.PI * Math.min(1, t / 0.7))) * ps,
        fm: t => { const u = t / 0.8; return [mixf(mixf(300, 850, smoothstep(0, 0.4, u)), 400, smoothstep(0.5, 1, u)) * fs, mixf(mixf(2200, 1300, smoothstep(0, 0.4, u)), 900, smoothstep(0.5, 1, u)) * fs, 2900] },
        env: t => cenv(t / 0.8, 0.12), nasal: t => 1 - smoothstep(0, 0.12, t) })
    case 'roar': case 'growl': case 'bellow': {
      const dur = vc === 'growl' ? 1.2 : vc === 'roar' ? 1.7 : 1.5
      const base = vc === 'growl' ? 80 : vc === 'roar' ? 120 : 95
      return voice(dur, { seed, breath: 0.3, rasp: vc === 'bellow' ? 0.5 : 0.95,
        f0: t => base * ps * (1 + 0.35 * sinf(Math.PI * Math.min(1, t / dur)) - (vc === 'growl' ? 0.3 : 0)),
        fm: t => [(vc === 'roar' ? mixf(400, 700, smoothstep(0, 0.3, t / dur)) : 450) * fs, 950 * fs, 2400],
        env: t => cenv(t / dur, 0.12) * (vc === 'growl' ? 0.7 + 0.3 * sinf(tau * 28 * t) : 1) })
    }
    case 'howl':
      return voice(2.3, { seed, breath: 0.05, rasp: 0.05, f0: t => (400 + 250 * smoothstep(0, 0.5, t) - 220 * smoothstep(1.6, 2.3, t)) * ps * (1 + 0.01 * sinf(tau * 5 * t)),
        fm: K([380 * fs, 850 * fs, 2600]), env: t => cenv(t / 2.3, 0.15) })
    case 'squeak': {
      const marks = [[0, 0.09], [0.15, 0.12]]
      return make(0.32, 0.5, t => {
        const s = syl(t, marks); if (!s) return 0
        const u = s[1], f = 2600 * ps * (1 + 0.3 * u)
        return sinf(tau * f * t) * sinf(Math.PI * u)
      })
    }
    case 'hiss': {
      const n = new Noise32(seed), bp = new Reso(), bp2 = new Reso()
      return make(1.2, 0.55, t => { const x = n.next(); return (bp.run(x, 5500, 1.5, fsr) + bp2.run(x, 3000, 2, fsr) * 0.5) * cenv(t / 1.2, 0.1) })
    }
    case 'quack': case 'honk': {
      const honk = vc === 'honk'
      const marks = honk ? [[0, 0.3], [0.42, 0.34]] : [[0, 0.15], [0.22, 0.15], [0.44, 0.2]]
      return voice(honk ? 0.85 : 0.72, { seed, breath: 0.15, rasp: honk ? 0.3 : 0.7,
        f0: t => (honk ? 330 : 250) * ps * (1.1 - 0.2 * sylU(t, marks)),
        fm: K([honk ? 650 * fs : 850 * fs, honk ? 1100 * fs : 1400 * fs, 2500]),
        env: t => { const s = syl(t, marks); return s ? cenv(s[1], 0.1) : 0 }, nasal: () => honk ? 0.4 : 0.6 })
    }
    case 'gobble':
      return voice(0.9, { seed, breath: 0.2, rasp: 0.5, f0: t => (420 - 100 * t) * ps,
        fm: K([700 * fs, 1500 * fs, 2800]), env: t => cenv(t / 0.9, 0.05) * (0.5 + 0.5 * sinf(tau * 18 * t)) })
    case 'hoot': case 'coo': {
      const coo = vc === 'coo'
      const marks = coo ? [[0, 0.25], [0.3, 0.45], [0.8, 0.25]] : [[0, 0.3], [0.45, 0.25], [0.75, 0.45]]
      return voice(1.15, { seed, breath: 0.12, rasp: 0.02, f0: t => { const s = syl(t, marks); return (coo ? 360 : 330) * ps * (s ? (s[0] === 1 ? 1.1 : 1) : 1) },
        fm: K([320 * fs, 700 * fs, 2400]), env: t => { const s = syl(t, marks); return s ? cenv(s[1], 0.2) : 0 }, nasal: () => coo ? 0.5 : 0.2 })
    }
    case 'caw': case 'squawk': case 'screech': {
      const marks = vc === 'caw' ? [[0, 0.3], [0.45, 0.3]] : [[0, vc === 'screech' ? 0.8 : 0.5]]
      const base = vc === 'caw' ? 600 : vc === 'squawk' ? 900 : 1500
      return voice(vc === 'caw' ? 0.85 : 0.9, { seed, breath: 0.2, rasp: 0.85,
        f0: t => base * ps * (1.1 - 0.25 * sylU(t, marks)),
        fm: K([1300 * fs, 2100 * fs, 3200]), env: t => { const s = syl(t, marks); return s ? cenv(s[1], 0.06) : 0 } })
    }
    case 'tweet': case 'chirp': {
      const cricket = vc === 'chirp' && (plan === 'insect' || plan === 'spider')
      let ph = 0
      return make(0.9, 0.45, t => {
        if (cricket) {
          const burst = (t % 0.3) < 0.12
          const pulse = sinf(tau * 30 * t) > 0
          return sinf(tau * 4600 * t) * (burst && pulse ? 1 : 0)
        }
        const k = floorf(t / 0.14), u = (t - k * 0.14) / 0.09
        if (!(u < 1 && k < 5)) return 0
        const f = (2600 + 900 * sinf(Math.PI * u) + k * 150) * ps
        ph += f / fsr
        return sinf(tau * ph) * sinf(Math.PI * u)
      })
    }
    case 'trumpet':
      return voice(1.3, { seed, breath: 0.05, rasp: 0.35, f0: t => (480 + 250 * smoothstep(0, 0.3, t)) * (1 + 0.02 * sinf(tau * 6 * t)),
        fm: K([1000, 2200, 3500]), env: t => cenv(t / 1.3, 0.05) })
    case 'hoo': {
      const marks = [[0, 0.18], [0.25, 0.18], [0.5, 0.2], [0.78, 0.35], [1.18, 0.4]]
      return voice(1.7, { seed, breath: 0.15, rasp: 0.3,
        f0: t => { const s = syl(t, marks); return (s ? (s[0] < 3 ? 250 + s[0] * 60 : 600) : 300) * ps },
        fm: t => { const s = syl(t, marks); return [s ? (s[0] < 3 ? 350 : 850) : 400, 900, 2500] },
        env: t => { const s = syl(t, marks); return s ? cenv(s[1], 0.15) : 0 } })
    }
    case 'chatter': {
      const n = new Noise32(seed), bp = new Reso()
      return make(0.8, 0.5, t => {
        const k = t * 16, u = k - floorf(k)
        return (bp.run(n.next(), 3000 * ps, 4, fsr) * 2 + sinf(tau * 1800 * ps * t) * 0.4) * (u < 0.35 ? sinf(Math.PI * u / 0.35) : 0)
      })
    }
    case 'ribbit': {
      const marks = [[0, 0.14], [0.2, 0.2]]
      return voice(0.5, { seed, breath: 0.2, rasp: 0.9, f0: () => 170 * ps,
        fm: K([500 * fs, 1100 * fs, 2400]), env: t => { const s = syl(t, marks); return (s ? cenv(s[1], 0.1) : 0) * (0.5 + 0.5 * sinf(tau * 55 * t)) } })
    }
    case 'buzz': {
      let ph = 0; const lp = new LP1()
      return make(1.0, 0.45, t => {
        const f = 220 * ps * (1 + 0.05 * sinf(tau * 3 * t))
        ph += f / fsr; if (ph > 1) ph -= 1
        return lp.run(ph * 2 - 1, 1800, fsr) * cenv(t, 0.1) * (0.8 + 0.2 * sinf(tau * 40 * t))
      })
    }
    case 'click': {
      const n = new Noise32(seed), bp = new Reso(); let ph = 0
      return make(1.2, 0.5, t => {
        let v = 0
        const k = t * 14, u = k - floorf(k)
        if (t < 0.6) v += bp.run(n.next(), 6000, 3, fsr) * expf(-u * 30) * 1.5
        if (t > 0.55) {
          const w = (t - 0.55) / 0.6
          ph += (5000 + 3500 * sinf(Math.PI * w)) / fsr
          v += sinf(tau * ph) * sinf(Math.PI * Math.min(1, w)) * 0.5
        }
        return v
      })
    }
    case 'whale':
      return voice(3.0, { seed, breath: 0.03, rasp: 0.05, f0: t => (150 + 170 * sinf(Math.PI * t / 3) - 60 * smoothstep(2, 3, t)) * ps,
        fm: K([350, 800, 2000]), env: t => cenv(t / 3, 0.2) })
    case 'blub':
      return make(0.8, 0.45, t => {
        const k = floorf(t / 0.15), u = (t - k * 0.15) / 0.07
        if (!(u < 1)) return 0
        const f = (300 + 700 * u + k * 60) * ps
        return sinf(tau * f * (t - k * 0.15)) * sinf(Math.PI * u)
      })
    default:   // talk / cluck / moo on a non-custom animal (e.g. Water Buffalo) fall through here, as in Swift
      return voice(0.5, { seed, breath: 0.2, rasp: 0.5, f0: () => 150 * ps, fm: K([500, 1100, 2400]), env: t => cenv(t / 0.5) })
  }
}
for (let id = 3; id < ZOO.length; id++) GEN[`call_${id}`] = () => buildCall(id)

// extra movement sounds for the new body plans
one('slither', () => {
  const n = new Noise32(900), bp = new Reso()
  return make(0.35, 0.35, t => bp.run(n.next(), 2500, 0.8, SR) * sinf(Math.PI * t / 0.35))
})
one('flop', () => {
  const n = new Noise32(901), lp = new LP1(), bp = new Reso()
  return make(0.3, 0.5, t => {
    const x = n.next()
    return lp.run(x, 500, SR) * expf(-t * 20) * 2 + bp.run(x, 1500, 1, SR) * expf(-t * 30) + sinf(tau * 120 * t) * expf(-t * 25) * 0.5
  })
})
one('buzzwing', () => {
  let ph = 0; const lp = new LP1()
  return make(0.5, 0.3, t => {
    ph += 180 / SR; if (ph > 1) ph -= 1
    return lp.run(ph * 2 - 1, 1200, SR) * sinf(Math.PI * t / 0.5)
  })
})

// custom species have no call_ buffer in Swift; map them to their own voices for convenience
const ALIAS = { call_0: 'talk', call_1: 'cluck', call_2: 'moo' }

/// Every concrete buffer key (variants expanded: moo_0..moo_3), sorted like Swift's bufferNames.
export const names = Object.keys(GEN).sort()
/// Variant groups: { moo: 4, step_shoe: 4, ... }
export const variants = { ...VARIANTS }

/// Pure synthesis of one buffer key (or group name -> variant 0). Returns { L, R } Float32Arrays.
export function synth(name, sampleRate = 48000) {
  let key = ALIAS[name] || name
  if (VARIANTS[key]) key = `${key}_0`
  const gen = GEN[key]
  if (!gen) throw new Error(`audio: no sound named "${name}"`)
  const prev = SR
  SR = sampleRate
  try { return gen() } finally { SR = prev }
}

/// Offline check like AudioSystem.selfCheck: every buffer, plus ambience and music renders.
/// Returns [{ name, peak, rms?, ok }]. Synchronous; takes a few seconds.
export function selfCheck(sampleRate = 48000, { synths = true, musicSeconds = 20 } = {}) {
  const out = []
  for (const k of names) {
    const { L } = synth(k, sampleRate)
    let peak = 0
    for (let i = 0; i < L.length; i++) { if (!Number.isFinite(L[i])) { peak = NaN; break } peak = Math.max(peak, abs(L[i])) }
    out.push({ name: k, peak, ok: peak > 0.02 && peak < 1.0 })
  }
  if (synths) {
    const n = 1024, L = new Float32Array(n), R = new Float32Array(n)
    for (const rush of [0, 1]) {
      const a = new AmbienceSynth(sampleRate); a.rush = rush
      let p = 0
      for (let b = 0; b < Math.trunc(40 * sampleRate / n); b++) { a.render(n, L, R); for (let i = 0; i < n; i++) p = Math.max(p, Number.isFinite(L[i]) ? abs(L[i]) : 99) }
      out.push({ name: `ambience rush ${rush}`, peak: p, ok: p < 0.9 && p > 0.005 })
    }
    for (const mood of ['menu', 'play']) {
      const m = new MusicSynth(sampleRate); m.setMood(mood)
      let p = 0, rm = 0, c = 0
      for (let b = 0; b < Math.trunc(musicSeconds * sampleRate / n); b++) {
        m.render(n, L, R)
        for (let i = 0; i < n; i++) { p = Math.max(p, Number.isFinite(L[i]) ? abs(L[i]) : 99); rm += L[i] * L[i]; c++ }
      }
      out.push({ name: `music ${mood}`, peak: p, rms: Math.sqrt(rm / c), ok: p < 0.95 && p > 0.03 })
    }
  }
  return out
}

// MARK: - Web Audio runtime

const PROC_NAME = 'morph-synths'
const WORKLET_SRC = `
const LIB = (${synthLib.toString()})();
class MorphSynths extends AudioWorkletProcessor {
  constructor() {
    super();
    this.amb = new LIB.AmbienceSynth(sampleRate);
    this.mus = new LIB.MusicSynth(sampleRate);
    this.paused = false;
    this.port.onmessage = e => {
      const d = e.data || {};
      if (d.amb) Object.assign(this.amb, d.amb);
      if (d.music) { const m = d.music; if (m.mood !== undefined) this.mus.setMood(m.mood); if (m.on !== undefined) this.mus.on = m.on; if (m.energy !== undefined) this.mus.energy = m.energy; }
      if (d.paused !== undefined) this.paused = d.paused;
    };
  }
  process(inputs, outputs) {
    const out = outputs[0];
    const L = out[0], R = out[1] || out[0];
    if (this.paused) { L.fill(0); if (R !== L) R.fill(0); return true; }
    this.amb.render(L.length, L, R, false);
    this.mus.render(L.length, L, R, true);
    return true;
  }
}
registerProcessor('${PROC_NAME}', MorphSynths);
`
/// The AudioWorklet module source (exported for tests).
export const workletSource = WORKLET_SRC

const COMMON = ['step_shoe', 'step_hoof', 'step_claw', 'jump', 'land', 'morph', 'poof', 'click', 'select', 'talk', 'cluck', 'moo',
  'step_wood', 'step_hay', 'step_splash', 'flap', 'munch', 'peck', 'thud', 'whoosh', 'pickup', 'slither', 'flop', 'buzzwing']
const MAX_VOICES = 32

let ctx = null, master = null, sfxBus = null, synthNode = null, fallbackSynths = null
let initPromise = null
const cache = new Map()             // key -> AudioBuffer
const voices = []                   // active one-shots, oldest first
const state = {
  muted: false,
  music: { mood: 'menu', on: true, energy: 0.5 },
  amb: { rush: 0, level: 1, on: true },
}

function post(msg) {
  if (synthNode && synthNode.port) synthNode.port.postMessage(msg)
  else if (fallbackSynths) {
    if (msg.amb) Object.assign(fallbackSynths.amb, msg.amb)
    if (msg.music) { const m = msg.music; if (m.mood !== undefined) fallbackSynths.mus.setMood(m.mood); if (m.on !== undefined) fallbackSynths.mus.on = m.on; if (m.energy !== undefined) fallbackSynths.mus.energy = m.energy }
    if (msg.paused !== undefined) fallbackSynths.paused = msg.paused
  }
}
const ambMsg = () => ({ amb: { rush: clampf(+state.amb.rush || 0, 0, 1), level: clampf(+state.amb.level || 0, 0, 1), on: state.amb.on ? 1 : 0 } })
const musMsg = () => ({ music: { mood: state.music.mood, on: state.music.on ? 1 : 0, energy: clampf(+state.music.energy || 0, 0, 1) } })

/// Medium-hall-ish impulse: pre-delay, dense decaying noise that darkens as it fades (RT60 ~1.6 s).
function hallImpulse(c) {
  const sr = c.sampleRate, len = Math.trunc(sr * 1.8), pre = Math.trunc(sr * 0.018)
  const buf = c.createBuffer(2, len, sr)
  for (let ch = 0; ch < 2; ch++) {
    const d = buf.getChannelData(ch), n = new Noise32(0x5EED + ch * 977)
    let lp = 0
    for (let i = pre; i < len; i++) {
      const t = (i - pre) / sr
      const cut = 9000 * Math.exp(-t * 1.6) + 600
      lp += (n.next() - lp) * (1 - Math.exp(-tau * cut / sr))
      d[i] = lp * Math.exp(-t * 4.3) * Math.min(1, t * 200)
    }
  }
  return buf
}

function getBuffer(key) {
  let b = cache.get(key)
  if (b) return b
  const { L, R } = synth(key, ctx.sampleRate)
  b = ctx.createBuffer(2, L.length, ctx.sampleRate)
  b.getChannelData(0).set(L); b.getChannelData(1).set(R)
  cache.set(key, b)
  return b
}

function warm() {
  const keys = []
  for (const g of COMMON) { if (VARIANTS[g]) for (let i = 0; i < VARIANTS[g]; i++) keys.push(`${g}_${i}`); else if (GEN[g]) keys.push(g) }
  const idle = typeof requestIdleCallback === 'function' ? cb => requestIdleCallback(cb, { timeout: 500 }) : cb => setTimeout(cb, 25)
  const nextSlice = () => {
    // one buffer per slice (each is a few ms), so no single frame stalls
    while (keys.length && cache.has(keys[0])) keys.shift()
    if (!keys.length || !ctx) return
    try { getBuffer(keys.shift()) } catch (e) { /* ignore */ }
    idle(nextSlice)
  }
  idle(nextSlice)
}

function installResume() {
  // iOS can suspend/interrupt the context (backgrounding, calls); resume on the next gesture.
  const kick = () => { if (ctx && ctx.state !== 'running' && ctx.state !== 'closed') ctx.resume().catch(() => {}) }
  for (const ev of ['pointerdown', 'touchend', 'keydown', 'mousedown']) window.addEventListener(ev, kick, { capture: true, passive: true })
  document.addEventListener('visibilitychange', () => { if (!document.hidden) kick() })
}

async function startSynths() {
  const msgs = [ambMsg(), musMsg(), { paused: state.muted }]
  if (ctx.audioWorklet && typeof AudioWorkletNode !== 'undefined') {
    try {
      const url = URL.createObjectURL(new Blob([WORKLET_SRC], { type: 'application/javascript' }))
      // never let a stuck addModule hold up the game: fall back after 4 s
      await Promise.race([ctx.audioWorklet.addModule(url), new Promise((_, rej) => setTimeout(() => rej(new Error('addModule timeout')), 4000))])
      URL.revokeObjectURL(url)
      synthNode = new AudioWorkletNode(ctx, PROC_NAME, { numberOfInputs: 0, numberOfOutputs: 1, outputChannelCount: [2] })
      synthNode.connect(master)
      for (const m of msgs) post(m)
      return
    } catch (e) {
      console.warn('audio: AudioWorklet unavailable, using ScriptProcessor', e)
      synthNode = null
    }
  }
  // fallback: render on the main thread
  fallbackSynths = { amb: new AmbienceSynth(ctx.sampleRate), mus: new MusicSynth(ctx.sampleRate), paused: false }
  for (const m of msgs) post(m)
  const sp = ctx.createScriptProcessor(2048, 1, 2)
  sp.onaudioprocess = e => {
    const ob = e.outputBuffer, L = ob.getChannelData(0), R = ob.getChannelData(1)
    if (fallbackSynths.paused) { L.fill(0); R.fill(0); return }
    fallbackSynths.amb.render(L.length, L, R, false)
    fallbackSynths.mus.render(L.length, L, R, true)
  }
  sp.connect(master)
  fallbackSynths.node = sp
}

function stopVoice(v, now) {
  try { v.g.gain.cancelScheduledValues(now); v.g.gain.setTargetAtTime(0, now, 0.004); v.src.stop(now + 0.03) } catch (e) { /* already stopped */ }
}

export const Audio = {
  get ready() { return !!ctx },
  get context() { return ctx },
  names,
  variants,

  /// Call from the first user gesture. Idempotent; later calls just resume the context.
  init() {
    if (initPromise) { if (ctx && ctx.state !== 'running') ctx.resume().catch(() => {}); return initPromise }
    const AC = typeof window !== 'undefined' && (window.AudioContext || window.webkitAudioContext)
    if (!AC) return (initPromise = Promise.resolve(false))
    try { ctx = new AC({ latencyHint: 'interactive' }) } catch (e) { ctx = new AC() }
    // resume + a silent blip synchronously inside the gesture (iOS unlock)
    const resumed = ctx.resume().catch(() => {})
    try { const s = ctx.createBufferSource(); s.buffer = ctx.createBuffer(1, 1, ctx.sampleRate); s.connect(ctx.destination); s.start(0) } catch (e) { /* ignore */ }

    master = ctx.createGain()
    master.gain.value = state.muted ? 0 : 0.9
    master.connect(ctx.destination)
    // sfx bus -> outdoors reverb (7% wet, like AVAudioUnitReverb mediumHall wetDryMix 7) -> master
    sfxBus = ctx.createGain()
    const dry = ctx.createGain(); dry.gain.value = 0.93
    const wet = ctx.createGain(); wet.gain.value = 0.07
    const verb = ctx.createConvolver()
    verb.normalize = true
    verb.buffer = hallImpulse(ctx)
    sfxBus.connect(dry); dry.connect(master)
    sfxBus.connect(verb); verb.connect(wet); wet.connect(master)
    if (typeof window !== 'undefined') installResume()

    initPromise = (async () => {
      await Promise.race([resumed, new Promise(r => setTimeout(r, 300))])
      await startSynths()
      warm()
      return true
    })()
    return initPromise
  },

  /// One-shot. Group names ('moo') pick a random variant; 'moo_2' plays that exact one.
  play(name, { volume = 1, pan = 0, jitter = 0.05, rate = 1 } = {}) {
    if (!ctx || state.muted || ctx.state === 'closed') return -1
    let key = ALIAS[name] || name
    const nv = VARIANTS[key]
    if (nv) key = `${key}_${Math.floor(Math.random() * nv)}`
    if (!GEN[key]) return -1
    const v = clampf(+volume || 0, 0, 1.5)
    if (!(v > 0.004)) return -1
    let buf
    try { buf = getBuffer(key) } catch (e) { return -1 }
    const now = ctx.currentTime
    const src = ctx.createBufferSource()
    src.buffer = buf
    src.playbackRate.value = clampf(rate * (1 + (Math.random() * 2 - 1) * jitter), 0.25, 4)
    const g = ctx.createGain()
    g.gain.value = v
    src.connect(g)
    let last = g, p = null
    if (ctx.createStereoPanner) { p = ctx.createStereoPanner(); p.pan.value = clampf(+pan || 0, -1, 1); g.connect(p); last = p }
    last.connect(sfxBus)
    const voiceRec = { src, g, p }
    voices.push(voiceRec)
    while (voices.length > MAX_VOICES) stopVoice(voices.shift(), now)
    src.onended = () => {
      const i = voices.indexOf(voiceRec); if (i >= 0) voices.splice(i, 1)
      try { src.disconnect(); g.disconnect(); if (p) p.disconnect() } catch (e) { /* ignore */ }
    }
    src.start(now)
    return voices.length - 1
  },

  /// Stop every playing one-shot.
  stopAll() { if (!ctx) return; const now = ctx.currentTime; while (voices.length) stopVoice(voices.shift(), now) },

  get muted() { return state.muted },
  set muted(m) {
    state.muted = !!m
    if (!ctx) return
    master.gain.setTargetAtTime(state.muted ? 0 : 0.9, ctx.currentTime, 0.02)
    // the synths stop computing while muted (saves battery); they pick up where they were
    post({ paused: state.muted })
    if (state.muted) Audio.stopAll()
  },

  music: {
    get mood() { return state.music.mood },
    set mood(m) { state.music.mood = (m in LIB.MOODS) ? m : 'menu'; post(musMsg()) },
    get on() { return state.music.on },
    set on(v) { state.music.on = !!v; post(musMsg()) },
    get energy() { return state.music.energy },
    set energy(v) { state.music.energy = clampf(+v || 0, 0, 1); post(musMsg()) },
  },
  ambience: {
    get rush() { return state.amb.rush },
    set rush(v) { const x = clampf(+v || 0, 0, 1); if (x === state.amb.rush) return; state.amb.rush = x; post(ambMsg()) },
    get level() { return state.amb.level },
    set level(v) { const x = clampf(+v || 0, 0, 1); if (x === state.amb.level) return; state.amb.level = x; post(ambMsg()) },
    get on() { return state.amb.on },
    set on(v) { state.amb.on = !!v; post(ambMsg()) },
  },

  /// Synthesise every buffer offline (plus ambience/music) and report peaks. Takes a few seconds.
  selfCheck(opts) { return selfCheck(ctx ? ctx.sampleRate : 48000, opts) },
}

export default Audio
