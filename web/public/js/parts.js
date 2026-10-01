// Body parts and the morphing body. Ported from Parts.swift.
import * as THREE from '../vendor/three.module.js'
import { V3, mix, smoothstep } from './util.js'
import { Ring, loftNode, limb, sphereNode, boxNode, cylNode, coneNode, tubeNode, at, rot, scl, group } from './loft.js'
import { Mat } from './mats.js'
import { Species } from './species.js'
import { Part, LegsPart, TorsoPart, HeadPart, GenLegs, GenTorso, GenHead, wave, wavec, eul, disposeTree } from './genparts.js'
import { AddOns, applyAddOns, animateAddOns } from './addons.js'

export { Part, LegsPart, TorsoPart, HeadPart, wave, wavec }

export const Slot = Object.freeze({ head: 0, torso: 1, legs: 2, names: ['Head', 'Body', 'Legs'], all: [0, 1, 2] })

const sp = x => (typeof x === 'number' ? Species.of(x) : x)

export class Combo {
  constructor(h, t, l) { this.head = sp(h); this.torso = sp(t); this.legs = sp(l) }
  get(slot) { return slot === 0 ? this.head : slot === 1 ? this.torso : this.legs }
  /// Mutates this combo (like the Swift subscript setter).
  setSlot(slot, s) { s = sp(s); if (slot === 0) this.head = s; else if (slot === 1) this.torso = s; else this.legs = s; return this }
  /// A copy with one slot changed.
  with(slot, s) { return this.clone().setSlot(slot, s) }
  clone() { return new Combo(this.head, this.torso, this.legs) }
  equals(o) { return !!o && o.head === this.head && o.torso === this.torso && o.legs === this.legs }
  get index() { return this.head.id * 10000 + this.torso.id * 100 + this.legs.id }
  static fromIndex(i) {
    const n = Species.count
    return new Combo(Species.of(Math.floor(i / 10000) % 100 % n), Species.of(Math.floor(i / 100) % 100 % n), Species.of(i % 100 % n))
  }
  static get total() { return Species.count ** 3 }
  get isPure() { return this.head === this.torso && this.torso === this.legs }
  get name() {
    const { head, torso, legs } = this
    if (head.id < 3 && torso.id < 3 && legs.id < 3) return Combo.names[head.id * 9 + torso.id * 3 + legs.id]
    if (this.isPure) return head.name
    // a portmanteau: front of the head's name, middle of the body's, end of the legs'
    const clean = s => s.replace(/ /g, '').toLowerCase()
    const h = clean(head.name), t = clean(torso.name), l = clean(legs.name)
    let out = h.slice(0, Math.max(2, Math.floor((h.length + 1) / 2)))
    if (torso !== head && torso !== legs) {
      const a = Math.floor(t.length / 3), b = Math.max(a + 1, Math.floor(t.length * 2 / 3))
      out += t.slice(a, Math.min(b, t.length))
    }
    const suffix = (s, k) => s.slice(Math.max(0, s.length - k))
    if (legs !== head) out += suffix(l, Math.max(2, Math.floor(l.length / 2)))
    else out += suffix(h, Math.max(2, Math.floor(h.length / 2)))
    return out.charAt(0).toUpperCase() + out.slice(1)
  }
  get recipe() { return `${this.head.name} head · ${this.torso.name} body · ${this.legs.name} legs` }
}
Combo.names = ['Human', 'Drumstick Dan', 'Cowtaur', 'Birdman', 'Chickenstein', 'Feathertaur', 'Beefcake', 'Udderly Chicken', 'Cowboy',
  'Chickenhead', 'Cluckster', 'Chickentaur', 'Hen Solo', 'Chicken', 'Cowlucker', 'Rooster Beef', 'Beef Nugget', 'Chickow',
  'Minotaur', 'Mooster', 'Mootaur', 'Heifer-Hen', 'Moo-Hen', 'Featherbeef', 'Bullman', 'Chicken-Fried Steak', 'Cow']

/// Everything the animation needs to know about what the body is doing this frame.
export function newPose() {
  return {
    t: 0,          // seconds
    phase: 0,      // gait cycles
    gait: 0,       // 0 standing … 1 moving
    run: 0,        // 0 walk … 1 run
    air: 0,        // 0 grounded … 1 airborne
    glide: 0,      // wings spread
    flap: 0,       // flap envelope
    carry: 0,      // holding something in the arms
    throwT: -1,    // 0…1 while throwing
    shove: 0,      // push / headbutt envelope
    talk: 0,       // mouth open
    eat: 0,        // head down pecking / grazing / munching
    kick: 0,       // legs special envelope (buck, lay squat)
    lay: 0,
    climb: 0,
    fallen: 0,     // knocked over (NPC farmer)
    wave: 0,
    scared: 0,
  }
}

// ---- Outfits ----

export const Outfit = {
  get player() { return { shirt: Mat.flannel, sleeve: Mat.flannel, forearm: Mat.skin, pants: Mat.denim, boots: Mat.leather, hair: Mat.brownHair, hat: false, overalls: false, mustache: false, iris: Mat.irisBrown } },
  get farmer() { return { shirt: Mat.denim, sleeve: Mat.tee, forearm: Mat.skin, pants: Mat.denim, boots: Mat.leather, hair: Mat.greyHair, hat: true, overalls: true, mustache: true, iris: Mat.irisBlue } },
}

const g3 = (x, y, z) => { const g = group(); g.position.set(x, y, z); return g }

// ---- Legs ----

export class HumanLegs extends LegsPart {
  constructor(o) {
    super(Species.HUMAN)
    this.hips = []; this.knees = []; this.ankles = []
    this.attach = V3(0, 1.03, 0); this.radius = 0.3; this.stride = 1.35; this.mass = 1
    const hipY = 0.95
    const node = this.node
    node.add(loftNode([Ring([0, 0.84, -0.01], 0.15, 0.1, 2.4), Ring([0, 0.92, -0.015], 0.18, 0.12, 2.4), Ring([0, 1.0, 0], 0.175, 0.115, 2.4),
      Ring([0, 1.06, 0], 0.165, 0.11, 2.4), Ring([0, 1.08, 0], 0.1, 0.07)], o.pants, { smooth: 3 }))
    node.add(loftNode([Ring([0, 1.0, 0], 0.178, 0.118, 2.4), Ring([0, 1.04, 0], 0.178, 0.118, 2.4)], o.boots, { smooth: 1 }))
    for (const side of [1, -1]) {
      const hip = g3(0.095 * side, hipY, 0)
      node.add(hip)
      hip.add(limb(0.45, 0.088, 0.058, o.pants, { depth: 1.05 }))
      const knee = g3(0, -0.45, 0)
      hip.add(knee)
      knee.add(limb(0.42, 0.056, 0.045, o.pants))
      const ankle = g3(0, -0.42, 0)
      knee.add(ankle)
      ankle.add(at(cylNode(0.052, 0.12, o.boots), 0, 0.0, 0))
      ankle.add(loftNode([Ring([0, -0.035, -0.075], 0.03, 0.03), Ring([0, -0.04, -0.055], 0.048, 0.045), Ring([0, -0.045, 0.04], 0.052, 0.04),
        Ring([0, -0.05, 0.14], 0.048, 0.03), Ring([0, -0.055, 0.2], 0.034, 0.022), Ring([0, -0.058, 0.22], 0.012, 0.01)],
      o.boots, { ref: [0, 1, 0], smooth: 3 }))
      ankle.add(at(boxNode(0.1, 0.018, 0.29, Mat.rubber), 0, -0.078, 0.07))
      this.hips.push(hip); this.knees.push(knee); this.ankles.push(ankle)
      this.footNodes.push(ankle)
    }
  }
  bob(p) { return -Math.abs(wave(p.phase, 0)) * (0.02 + 0.05 * p.run) * p.gait * (1 - p.air) - p.lay * 0.4 }
  pose(p) {
    for (let i = 0; i < 2; i++) {
      const off = i === 0 ? 0 : 0.5
      const s = wave(p.phase, off), c = wavec(p.phase, off)
      let hip = -s * (0.32 + 0.38 * p.run) * p.gait
      let knee = (0.08 + (0.35 + 1.0 * p.run) * Math.max(0, c)) * p.gait + 0.04
      let ank = -(hip + knee) * 0.4 + (1 - p.gait) * -0.02
      // air: tuck
      hip = mix(hip, i === 0 ? -0.7 : -0.25, p.air)
      knee = mix(knee, i === 0 ? 1.1 : 0.6, p.air)
      ank = mix(ank, -0.2, p.air)
      // squat
      hip = mix(hip, -1.1, p.lay); knee = mix(knee, 1.9, p.lay); ank = mix(ank, -0.8, p.lay)
      // ladder
      const cs = wave(p.phase * 0.7, off)
      hip = mix(hip, -0.7 - cs * 0.5, p.climb); knee = mix(knee, 1.0 + cs * 0.4, p.climb)
      // fallen flat: legs splayed
      hip = mix(hip, -0.2 + i * 0.3, p.fallen); knee = mix(knee, 0.15, p.fallen)
      this.hips[i].rotation.set(hip, 0, (i === 0 ? 1 : -1) * 0.03)
      this.knees[i].rotation.set(knee, 0, 0)
      this.ankles[i].rotation.set(ank, 0, 0)
    }
  }
}

export class ChickenLegs extends LegsPart {
  constructor(white = false) {
    super(Species.CHICKEN)
    this.thighs = []; this.hocks = []; this.feet = []; this.toes = []
    this.fluff = group()
    this.attach = V3(0, 0.74, -0.02); this.radius = 0.3; this.stride = 0.62; this.mass = 0.35
    const body = white ? Mat.whiteFeather : Mat.henBody
    this.node.add(this.fluff)
    this.fluff.add(loftNode([Ring([0, 0.34, -0.1], 0.02, 0.02), Ring([0, 0.38, -0.08], 0.15, 0.15), Ring([0, 0.5, -0.05], 0.24, 0.24),
      Ring([0, 0.63, -0.03], 0.25, 0.24), Ring([0, 0.74, -0.02], 0.21, 0.2), Ring([0, 0.8, -0.02], 0.15, 0.14)], body, {
      smooth: 4, displace: (_p, _n, u, v) => 0.012 * Math.sin(u * 2 * Math.PI * 9 + v * 5),
    }))
    for (const side of [1, -1]) {
      const thigh = g3(0.1 * side, 0.52, 0.0)
      this.fluff.add(thigh)
      thigh.add(limb(0.2, 0.075, 0.04, body, { bulge: 0.25 }))
      const hock = g3(0, -0.2, 0)
      thigh.add(hock)
      hock.add(limb(0.31, 0.026, 0.021, Mat.scales))
      const foot = g3(0, -0.31, 0)
      hock.add(foot)
      const ts = []
      ;[-0.45, 0, 0.45].forEach((a, k) => {
        const toe = group(); eul(toe, 0, a, 0)
        foot.add(toe)
        const len = k === 1 ? 0.14 : 0.11
        toe.add(limb(len, 0.017, 0.011, Mat.scales, { dir: [0, -0.15, 1] }))
        toe.add(at(rot(coneNode(0.009, 0.001, 0.035, Mat.claw, 8), Math.PI / 2, 0, 0), 0, -len * 0.15, len + 0.01))
        ts.push(toe)
      })
      const back = group(); eul(back, 0, Math.PI, 0)
      foot.add(back)
      back.add(limb(0.05, 0.014, 0.01, Mat.scales, { dir: [0, -0.4, 1] }))
      this.thighs.push(thigh); this.hocks.push(hock); this.feet.push(foot); this.toes.push(ts)
      this.footNodes.push(foot)
    }
  }
  bob(p) { return -Math.abs(wave(p.phase, 0)) * 0.03 * p.gait * (1 - p.air) - p.lay * 0.2 }
  pose(p) {
    this.fluff.rotation.set(p.run * 0.15 * p.gait, 0, 0)
    const ang = [-0.45, 0, 0.45]
    for (let i = 0; i < 2; i++) {
      const off = i === 0 ? 0 : 0.5
      const s = wave(p.phase, off), c = wavec(p.phase, off)
      let th = -0.5 - s * (0.38 + 0.3 * p.run) * p.gait
      let hk = 0.8 + Math.max(0, c) * (0.6 + 0.6 * p.run) * p.gait
      th = mix(th, -1.0, p.air); hk = mix(hk, 1.7, p.air)
      th = mix(th, -1.25, p.lay); hk = mix(hk, 2.1, p.lay)
      th = mix(th, -0.3 + i * 0.4, p.fallen)
      this.thighs[i].rotation.set(th, 0, 0)
      this.hocks[i].rotation.set(hk, 0, 0)
      let fr = -(th + hk)
      // toes curl while the foot swings and in the air
      const curl = Math.max(Math.max(0, c) * p.gait, p.air) * 0.8
      fr += curl * 0.3
      this.feet[i].rotation.set(fr, 0, 0)
      this.toes[i].forEach((t, k) => t.rotation.set(curl, ang[k] * (1 - curl * 0.5), 0))
    }
  }
}

export class CowLegs extends LegsPart {
  constructor() {
    super(Species.COW)
    this.uppers = []; this.lowers = []; this.hooves = []
    this.tail = group(); this.tailMid = group(); this.udder = group()
    this.barrel = group()
    // LH, RH, LF, RF
    this.walkOff = [0, 0.5, 0.25, 0.75]
    this.gallopOff = [0, 0.1, 0.45, 0.58]
    this.attach = V3(0, 1.2, 0.6); this.radius = 0.62; this.stride = 1.7; this.mass = 3
    this.footPhases = [0, 0.25, 0.5, 0.75]
    const barrel = this.barrel
    this.node.add(barrel)
    const rings = [Ring([0, 1.13, -0.8], 0.06, 0.06), Ring([0, 1.12, -0.74], 0.25, 0.25), Ring([0, 1.1, -0.58], 0.34, 0.32, 2.2), Ring([0, 1.05, -0.25], 0.37, 0.37),
      Ring([0, 1.02, 0.1], 0.39, 0.39), Ring([0, 1.04, 0.4], 0.37, 0.36), Ring([0, 1.1, 0.66], 0.3, 0.3), Ring([0, 1.15, 0.8], 0.1, 0.1)]
    barrel.add(loftNode(rings, Mat.hide, {
      seg: 28, ref: [0, 1, 0], smooth: 4, vScale: 0.7, displace: (p, n) => {
        // hip bones and pin bones push through the hide
        let d = 0
        for (const hx of [0.22, -0.22]) {
          const qx = p[0] - hx, qy = p[1] - 1.34, qz = p[2] + 0.5
          d += Math.exp(-(qx * qx + qy * qy + qz * qz) * 90) * 0.05
          const rx = p[0] - hx * 0.6, ry = p[1] - 1.24, rz = p[2] + 0.74
          d += Math.exp(-(rx * rx + ry * ry + rz * rz) * 160) * 0.03
        }
        // spine ridge
        d += Math.exp(-p[0] * p[0] * 300) * Math.max(0, n[1]) * 0.02
        return d
      },
    }))
    // tail
    const { tail, tailMid, udder } = this
    tail.position.set(0, 1.3, -0.74)
    barrel.add(tail)
    tail.add(limb(0.38, 0.035, 0.024, Mat.hide, { dir: [0, -0.6, -0.4] }))
    tailMid.position.set(0, -0.32, -0.21)
    tail.add(tailMid)
    tailMid.add(limb(0.4, 0.022, 0.016, Mat.hide))
    tailMid.add(at(scl(sphereNode(0.05, Mat.brownHair, 12), 0.9, 2.6, 0.9), 0, -0.46, 0))
    // udder
    udder.position.set(0, 0.74, -0.28)
    barrel.add(udder)
    udder.add(scl(sphereNode(0.14, Mat.cowSkin), 1.1, 0.8, 1.35))
    for (const [x, z] of [[0.06, 0.08], [-0.06, 0.08], [0.06, -0.08], [-0.06, -0.08]]) {
      udder.add(at(limb(0.07, 0.016, 0.013, Mat.cowSkin), x, -0.08, z))
    }
    ;[[0.2, -0.52], [-0.2, -0.52], [0.2, 0.55], [-0.2, 0.55]].forEach(([x, z], k) => {
      const hind = k < 2
      const up = g3(x, 0.93, z)
      barrel.add(up)
      up.add(limb(0.42, hind ? 0.1 : 0.085, 0.055, Mat.hide, { depth: hind ? 1.5 : 1.15, bulge: 0.2 }))
      const lo = g3(0, -0.42, 0)
      up.add(lo)
      lo.add(limb(0.4, 0.045, 0.038, Mat.hide))
      const hf = g3(0, -0.4, 0)
      lo.add(hf)
      hf.add(scl(sphereNode(0.05, Mat.hide, 14), 1, 0.9, 1.1))
      hf.add(at(coneNode(0.062, 0.048, 0.08, Mat.hoof), 0, -0.055, 0.012))
      hf.add(at(boxNode(0.006, 0.07, 0.12, Mat.black), 0, -0.06, 0.02))
      this.uppers.push(up); this.lowers.push(lo); this.hooves.push(hf)
      this.footNodes.push(hf)
    })
  }
  bob(p) {
    const walk = -Math.abs(wave(p.phase * 2, 0)) * 0.025
    const gallop = wave(p.phase, 0.3) * 0.08
    return mix(walk, gallop, p.run) * p.gait * (1 - p.air)
  }
  pitch(p) { return wave(p.phase, 0.1) * 0.07 * p.run * p.gait + p.kick * 0.28 }
  pose(p) {
    for (let k = 0; k < 4; k++) {
      const hind = k < 2
      const off = mix(this.walkOff[k], this.gallopOff[k], p.run)
      const s = wave(p.phase, off), c = wavec(p.phase, off)
      const amp = (0.3 + 0.35 * p.run) * p.gait
      let u = -s * amp
      let l = Math.max(0, c) * (0.5 + 0.7 * p.run) * p.gait
      if (hind) { u += 0.08; l = -l * 0.9 - 0.12 } else { u -= 0.02 }
      // air: fold legs
      u = mix(u, hind ? 0.5 : -0.5, p.air * 0.7)
      l = mix(l, hind ? -0.8 : 1.1, p.air * 0.7)
      // buck: hind legs lash out backwards
      if (hind) { u = mix(u, 1.2, p.kick); l = mix(l, 0.2, p.kick) }
      // lying down to be milked / knocked over
      u = mix(u, hind ? 0.9 : -0.9, p.lay); l = mix(l, hind ? -2.2 : 2.3, p.lay)
      this.uppers[k].rotation.set(u, 0, 0)
      this.lowers[k].rotation.set(l, 0, 0)
      this.hooves[k].rotation.set(-(u + l) * 0.6, 0, 0)
    }
    const swish = Math.sin(p.t * 1.7) * 0.35 + Math.sin(p.t * 4.3) * 0.08
    this.tail.rotation.set(p.run * 0.9 * p.gait + p.kick * 0.6, 0, swish)
    this.tailMid.rotation.set(p.run * 0.6 * p.gait, 0, swish * 0.8)
    this.udder.rotation.set(wave(p.phase * 2, 0.2) * 0.08 * p.gait, 0, 0)
  }
}

// ---- Torsos ----

export class HumanTorso extends TorsoPart {
  constructor(o) {
    super(Species.HUMAN)
    this.shoulders = []; this.elbows = []; this.hands = []
    this.chest = group()
    this.neck = V3(0, 0.575, 0.0); this.canGrab = true; this.carry = V3(0, 0.28, 0.4); this.mass = 1
    const chest = this.chest
    this.node.add(chest)
    this.anchor = chest
    chest.add(loftNode([Ring([0, -0.07, 0], 0.165, 0.108, 2.4), Ring([0, 0.05, 0], 0.16, 0.105, 2.4), Ring([0, 0.2, 0.005], 0.178, 0.118, 2.4),
      Ring([0, 0.34, 0.012], 0.198, 0.13, 2.5), Ring([0, 0.46, 0.0], 0.205, 0.118, 2.6), Ring([0, 0.53, -0.005], 0.16, 0.1, 2.4),
      Ring([0, 0.585, 0], 0.075, 0.068), Ring([0, 0.61, 0], 0.058, 0.055)], o.shirt, { seg: 26, smooth: 4 }))
    if (o.overalls) {
      // bib over a white tee, with brass buttons on the straps
      chest.add(loftNode([Ring([0, 0.3, 0.02], 0.175, 0.13, 2.5), Ring([0, 0.46, 0.005], 0.21, 0.122, 2.6), Ring([0, 0.53, -0.005], 0.165, 0.104, 2.4),
        Ring([0, 0.585, 0], 0.08, 0.072), Ring([0, 0.6, 0], 0.06, 0.058)], Mat.tee, { seg: 26, smooth: 3 }))
      for (const sx of [0.09, -0.09]) {
        chest.add(rot(at(boxNode(0.04, 0.3, 0.015, Mat.denim), sx, 0.42, 0.105), -0.2, 0, 0))
        chest.add(at(rot(cylNode(0.012, 0.01, Mat.galv, 10), Math.PI / 2, 0, 0), sx, 0.32, 0.135))
      }
    } else {
      // shirt buttons and a pocket
      for (let k = 0; k < 4; k++) chest.add(at(rot(cylNode(0.007, 0.005, Mat.whiteTrim, 8), Math.PI / 2, 0, 0), 0, 0.12 + k * 0.11, 0.123 + (k === 2 ? 0.008 : 0)))
      chest.add(at(boxNode(0.08, 0.09, 0.01, o.shirt), 0.09, 0.38, 0.13))
    }
    for (const side of [1, -1]) {
      const sh = g3(0.19 * side, 0.475, -0.005)
      chest.add(sh)
      sh.add(scl(sphereNode(0.058, o.sleeve, 16), 1, 1.1, 1))
      sh.add(limb(0.29, 0.058, 0.046, o.sleeve))
      const el = g3(0, -0.29, 0)
      sh.add(el)
      el.add(limb(0.26, 0.043, 0.032, o.forearm))
      if (o.sleeve !== o.forearm) el.add(at(cylNode(0.05, 0.06, o.sleeve, 14), 0, -0.01, 0))
      const hand = g3(0, -0.26, 0)
      el.add(hand)
      hand.add(loftNode([Ring([0, 0.005, 0], 0.03, 0.02), Ring([0, -0.03, 0.002], 0.042, 0.018, 2.6), Ring([0, -0.075, 0.005], 0.042, 0.016, 2.6),
        Ring([0, -0.11, 0.012], 0.035, 0.013, 2.4), Ring([0, -0.125, 0.015], 0.01, 0.008)], Mat.skin, { seg: 14, smooth: 3 }))
      hand.add(at(limb(0.055, 0.012, 0.009, Mat.skin, { dir: [-side * 0.3, -0.7, 0.6] }), -side * 0.03, -0.03, 0.015))
      this.shoulders.push(sh); this.elbows.push(el); this.hands.push(hand)
    }
  }
  pose(p) {
    for (let i = 0; i < 2; i++) {
      const side = i === 0 ? 1 : -1
      const off = i === 0 ? 0.5 : 0
      const s = wave(p.phase, off)
      let sx = -s * (0.28 + 0.55 * p.run) * p.gait
      let sz = side * 0.07
      let ex = -(0.12 + 0.9 * p.run * p.gait)
      // flail in the air
      sz = mix(sz, side * 0.55, p.air * 0.7); sx = mix(sx, -0.3, p.air * 0.5)
      // carrying: both hands out in front
      sx = mix(sx, -1.15, p.carry); sz = mix(sz, -side * 0.28, p.carry); ex = mix(ex, -0.55, p.carry)
      // push
      sx = mix(sx, -1.5, p.shove); ex = mix(ex, -0.1, p.shove); sz = mix(sz, -side * 0.1, p.shove)
      // ladder: hand over hand
      const cs = wave(p.phase * 0.7, off)
      sx = mix(sx, -2.6 - cs * 0.35, p.climb); ex = mix(ex, -0.4 + cs * 0.3, p.climb); sz = mix(sz, -side * 0.05, p.climb)
      // throwing arm (right)
      if (p.throwT >= 0 && i === 1) {
        const t = p.throwT
        const wind = smoothstep(0, 0.35, t), rel = smoothstep(0.35, 0.6, t), rest = smoothstep(0.7, 1, t)
        sx = mix(mix(sx, -2.7, wind), -0.7, rel)
        sx = mix(sx, 0, rest * 0.3)
        ex = mix(ex, -1.2, wind * (1 - rel))
      }
      // talking hands
      if (p.talk > 0 && p.carry < 0.5 && i === 1) { sx += -0.35 * p.talk * (0.6 + 0.4 * Math.sin(p.t * 7)); ex -= 0.6 * p.talk }
      // waving
      if (p.wave > 0 && i === 1) { sx = mix(sx, -0.3, p.wave); sz = mix(sz, -2.5, p.wave); ex = mix(ex, -0.3 + Math.sin(p.t * 10) * 0.4, p.wave) }
      // scared: hands up
      sx = mix(sx, -2.5, p.scared); sz = mix(sz, side * 0.5, p.scared); ex = mix(ex, -0.8, p.scared)
      // lying flat
      sx = mix(sx, -2.8, p.fallen); sz = mix(sz, side * 0.8, p.fallen)
      this.shoulders[i].rotation.set(sx, 0, sz)
      this.elbows[i].rotation.set(ex, 0, 0)
      this.hands[i].rotation.set(0, 0, 0)
    }
    this.chest.rotation.set(0, wave(p.phase, 0) * 0.08 * p.gait, 0)
  }
}

export class ChickenTorso extends TorsoPart {
  constructor(white = false) {
    super(Species.CHICKEN)
    this.wings = []; this.primaries = []
    this.tail = group()
    this.neck = V3(0, 0.56, 0.05); this.hasWings = true; this.flight = 1; this.carry = V3(0, 0.1, 0.45); this.mass = 0.35
    const body = white ? Mat.whiteFeather : Mat.henBody, wing = white ? Mat.whiteFeather : Mat.henWing
    const node = this.node
    node.add(loftNode([Ring([0, -0.08, -0.02], 0.2, 0.19), Ring([0, 0.07, 0.01], 0.25, 0.25), Ring([0, 0.22, 0.05], 0.26, 0.27),
      Ring([0, 0.36, 0.06], 0.22, 0.22), Ring([0, 0.47, 0.05], 0.14, 0.14), Ring([0, 0.56, 0.05], 0.085, 0.085), Ring([0, 0.6, 0.05], 0.07, 0.07)],
    body, { seg: 26, smooth: 4, displace: (_p, _n, u, v) => 0.008 * Math.sin(u * 2 * Math.PI * 11 + v * 9) }))
    for (const side of [1, -1]) {
      const w = g3(0.21 * side, 0.42, -0.01)
      node.add(w)
      // folded wing: a thick feathered paddle hanging down and back
      w.add(loftNode([Ring([0, 0.04, 0.02], 0.03, 0.07), Ring([0, -0.06, 0.0], 0.05, 0.13), Ring([0, -0.2, -0.05], 0.045, 0.14),
        Ring([0, -0.33, -0.1], 0.03, 0.1), Ring([0, -0.42, -0.15], 0.012, 0.04)], wing, { seg: 18, ref: [0, 0, 1], smooth: 3 }))
      const ps = []
      for (let k = 0; k < 6; k++) {
        const f = g3(0, -0.3 - k * 0.015, -0.08 + k * 0.035)
        w.add(f)
        const len = 0.3 - k * 0.025
        f.add(loftNode([Ring([0, 0, 0], 0.006, 0.02), Ring([0, -len * 0.3, 0], 0.007, 0.034), Ring([0, -len * 0.8, 0], 0.005, 0.028), Ring([0, -len, 0.01], 0.002, 0.006)],
          Mat.tailFeather, { seg: 10, smooth: 3 }))
        ps.push(f)
      }
      this.wings.push(w); this.primaries.push(ps)
    }
    this.tail.position.set(0, 0.08, -0.2)
    node.add(this.tail)
    for (let k = 0; k < 7; k++) {
      const a = (k - 3) * 0.2
      const f = group(); eul(f, 0, 0, a)
      this.tail.add(f)
      const sickle = k === 2 || k === 4
      const len = sickle ? 0.5 : 0.34
      f.add(loftNode([Ring([0, 0, 0], 0.03, 0.01), Ring([0, len * 0.4, -len * 0.3], 0.045, 0.012), Ring([0, len * 0.75, -len * 0.45], 0.04, 0.01),
        Ring([0, len * (sickle ? 0.85 : 1), -len * (sickle ? 0.8 : 0.5)], 0.01, 0.004)], Mat.tailFeather, { seg: 10, ref: [0, 0, 1], smooth: 3 }))
    }
  }
  pose(p) {
    const spread = Math.max(p.glide, Math.min(1, p.flap * 1.5), p.air * 0.25, p.run * p.gait * 0.25, p.shove)
    for (let i = 0; i < 2; i++) {
      const side = i === 0 ? 1 : -1
      const beat = Math.sin(p.t * 24) * 0.75 * Math.max(p.flap, p.shove)
      const lift = spread * 1.45 + beat - p.glide * Math.sin(p.t * 3) * 0.05
      this.wings[i].rotation.set(0.15 - spread * 0.1, side * spread * 0.2, side * lift)
      this.wings[i].scale.set(1 + spread * 0.3, 1 + spread * 0.55, 1 + spread * 0.35)
      this.primaries[i].forEach((f, k) => f.rotation.set(-spread * (k * 0.12), 0, 0))
    }
    this.tail.rotation.set(-0.2 - p.glide * 0.35, wave(p.phase, 0) * 0.08 * p.gait, Math.sin(p.t * 2) * 0.03)
  }
}

export class CowTorso extends TorsoPart {
  constructor(quadruped) {
    super(Species.COW)
    this.shoulders = []; this.knees = []
    this.quadruped = quadruped
    this.mass = 3
    const node = this.node
    if (quadruped) {
      // Continues the barrel forward into the chest and neck of a real cow.
      node.add(loftNode([Ring([0, -0.2, -0.14], 0.36, 0.37), Ring([0, -0.1, 0.1], 0.32, 0.35), Ring([0, 0.02, 0.28], 0.22, 0.26),
        Ring([0, 0.12, 0.42], 0.15, 0.2), Ring([0, 0.18, 0.52], 0.12, 0.15)], Mat.hide, { seg: 26, ref: [0, 1, 0], smooth: 4, vScale: 0.7 }))
      // dewlap
      node.add(loftNode([Ring([0, -0.32, 0.12], 0.02, 0.02), Ring([0, -0.22, 0.28], 0.045, 0.1), Ring([0, -0.08, 0.42], 0.04, 0.08), Ring([0, 0.02, 0.5], 0.02, 0.02)],
        Mat.hide, { seg: 12, ref: [0, 1, 0], smooth: 3 }))
      this.neck = V3(0, 0.12, 0.44); this.neckRot = 0.62
    } else {
      node.add(loftNode([Ring([0, -0.1, 0], 0.3, 0.28), Ring([0, 0.1, 0.01], 0.34, 0.3), Ring([0, 0.3, 0.035], 0.36, 0.31),
        Ring([0, 0.48, 0.03], 0.32, 0.27), Ring([0, 0.62, 0.05], 0.22, 0.2), Ring([0, 0.72, 0.07], 0.15, 0.15), Ring([0, 0.77, 0.07], 0.13, 0.13)],
      Mat.hide, { seg: 26, smooth: 4, vScale: 0.7 }))
      node.add(loftNode([Ring([0, 0.3, 0.2], 0.02, 0.02), Ring([0, 0.45, 0.26], 0.05, 0.06), Ring([0, 0.62, 0.22], 0.045, 0.05), Ring([0, 0.72, 0.16], 0.02, 0.02)],
        Mat.hide, { seg: 12, smooth: 3 }))
      this.neck = V3(0, 0.75, 0.07)
      for (const side of [1, -1]) {
        const sh = g3(0.31 * side, 0.58, 0.02)
        node.add(sh)
        sh.add(sphereNode(0.1, Mat.hide, 16))
        sh.add(limb(0.36, 0.09, 0.06, Mat.hide, { depth: 1.2, bulge: 0.2 }))
        const kn = g3(0, -0.36, 0)
        sh.add(kn)
        kn.add(limb(0.33, 0.045, 0.038, Mat.hide))
        kn.add(at(sphereNode(0.05, Mat.hide, 12), 0, -0.33, 0))
        kn.add(at(coneNode(0.062, 0.048, 0.08, Mat.hoof), 0, -0.39, 0.01))
        kn.add(at(boxNode(0.006, 0.07, 0.12, Mat.black), 0, -0.39, 0.02))
        this.shoulders.push(sh); this.knees.push(kn)
      }
    }
  }
  pose(p) {
    if (this.quadruped) return
    for (let i = 0; i < 2; i++) {
      const side = i === 0 ? 1 : -1
      const s = wave(p.phase, i === 0 ? 0.5 : 0)
      let sx = -s * (0.25 + 0.4 * p.run) * p.gait
      let kx = -(0.1 + 0.5 * p.run * p.gait)
      let sz = side * 0.1
      sz = mix(sz, side * 0.5, p.air * 0.7)
      sx = mix(sx, -1.6, p.shove); kx = mix(kx, 0, p.shove)
      sx = mix(sx, -0.9, p.carry)
      sx = mix(sx, -2.4 - s * 0.3, p.climb)
      if (p.talk > 0) sx -= 0.2 * p.talk
      this.shoulders[i].rotation.set(sx, 0, sz)
      this.knees[i].rotation.set(kx, 0, 0)
    }
  }
}

// ---- Heads ----

export class HumanHead extends HeadPart {
  constructor(o) {
    super(Species.HUMAN)
    this.skull = group(); this.mouthOpen = group(); this.jawNode = group()
    this.lids = []
    this.blinkT = 2
    this.height = 0.36; this.mouth = V3(0, 0.14, 0.1)
    const skull = this.skull
    this.anchor = skull
    this.node.add(limb(0.09, 0.056, 0.058, Mat.skin, { dir: [0, 1, 0.08] }))
    skull.position.set(0, 0.055, 0.012)
    this.node.add(skull)
    const sq = x => x * x
    skull.add(loftNode([Ring([0, -0.005, 0.03], 0.02, 0.02), Ring([0, 0.02, 0.035], 0.055, 0.065), Ring([0, 0.06, 0.012], 0.078, 0.092),
      Ring([0, 0.12, 0.0], 0.088, 0.1), Ring([0, 0.18, -0.005], 0.09, 0.104), Ring([0, 0.235, -0.012], 0.08, 0.095),
      Ring([0, 0.275, -0.018], 0.05, 0.062), Ring([0, 0.292, -0.02], 0.01, 0.01)], Mat.skin, {
      seg: 28, smooth: 4, displace: p => {
        const [x, y, z] = p
        // brow ridge and cheekbones
        let d = 0
        d += Math.exp(-sq((y - 0.165) * 45)) * Math.max(0, z - 0.06) * 0.12
        for (const cx of [0.055, -0.055]) d += Math.exp(-(sq((x - cx) * 30) + sq((y - 0.11) * 30))) * Math.max(0, z) * 0.08
        // eye sockets
        for (const cx of [0.036, -0.036]) d -= Math.exp(-(sq((x - cx) * 45) + sq((y - 0.142) * 50))) * Math.max(0, z - 0.05) * 0.18
        return d
      },
    }))
    // nose
    skull.add(loftNode([Ring([0, 0.15, 0.09], 0.008, 0.008), Ring([0, 0.13, 0.1], 0.01, 0.01), Ring([0, 0.108, 0.108], 0.016, 0.013),
      Ring([0, 0.098, 0.1], 0.015, 0.01), Ring([0, 0.095, 0.092], 0.004, 0.004)], Mat.skin, { seg: 14, ref: [0, 0, 1], smooth: 3 }))
    // ears
    for (const sx of [1, -1]) skull.add(rot(at(scl(sphereNode(0.03, Mat.skin, 14), 0.35, 1.05, 0.7), 0.09 * sx, 0.135, -0.01), 0, sx * 0.3, 0))
    // eyes
    for (const sx of [1, -1]) {
      const e = g3(0.035 * sx, 0.143, 0.079)
      skull.add(e)
      e.add(sphereNode(0.0145, Mat.eyeWhite, 16))
      e.add(at(scl(sphereNode(0.0072, o.iris, 14), 1, 1, 0.35), 0, 0, 0.0128))
      e.add(at(scl(sphereNode(0.0036, Mat.eyeBlack, 10), 1, 1, 0.35), 0, 0, 0.0142))
      const lid = sphereNode(0.0158, Mat.skin, 16)
      lid.scale.set(1, 0.05, 1)
      lid.position.set(0, 0.012, 0)
      e.add(lid)
      this.lids.push(lid)
      skull.add(rot(at(boxNode(0.034, 0.006, 0.012, o.hair), 0.037 * sx, 0.168, 0.09), 0, 0, sx * -0.08))
    }
    // mouth
    skull.add(at(boxNode(0.042, 0.005, 0.01, Mat.lip), 0, 0.071, 0.085))
    this.mouthOpen.position.set(0, 0.066, 0.08)
    skull.add(this.mouthOpen)
    this.mouthOpen.add(scl(sphereNode(0.022, Mat.mouthDark, 12), 1, 0.2, 0.45))
    // hair
    skull.add(loftNode([Ring([0, 0.155, -0.035], 0.095, 0.1), Ring([0, 0.2, -0.012], 0.097, 0.112), Ring([0, 0.25, -0.016], 0.085, 0.1),
      Ring([0, 0.285, -0.02], 0.058, 0.07), Ring([0, 0.305, -0.022], 0.01, 0.01)], o.hair, {
      seg: 26, smooth: 3,
      // cut away the face below the hairline
      displace: p => (p[2] > 0.04 && p[1] < 0.2 ? -0.04 : 0.004),
    }))
    if (o.mustache) {
      skull.add(loftNode([Ring([-0.035, 0.078, 0.086], 0.003, 0.003), Ring([-0.015, 0.085, 0.098], 0.009, 0.007), Ring([0, 0.086, 0.1], 0.01, 0.007),
        Ring([0.015, 0.085, 0.098], 0.009, 0.007), Ring([0.035, 0.078, 0.086], 0.003, 0.003)], o.hair, { seg: 10, ref: [0, 1, 0], smooth: 3 }))
    }
    if (o.hat) {
      const hat = g3(0, 0.23, -0.01)
      skull.add(hat)
      hat.add(rot(tubeNode(0.1, 0.2, 0.012, Mat.straw, 36), -0.08, 0, 0))
      hat.add(loftNode([Ring([0, -0.01, 0], 0.105, 0.115), Ring([0, 0.06, 0], 0.1, 0.11), Ring([0, 0.1, 0], 0.085, 0.09), Ring([0, 0.11, 0], 0.02, 0.02)],
        Mat.straw, { seg: 24, smooth: 2 }))
      hat.add(loftNode([Ring([0, 0.0, 0], 0.107, 0.117), Ring([0, 0.025, 0], 0.107, 0.117)], Mat.leather, { seg: 24, smooth: 1 }))
    }
  }
  pose(p) {
    const open = p.talk * (0.5 + 0.5 * Math.abs(Math.sin(p.t * 17))) + p.eat * Math.abs(Math.sin(p.t * 9)) * 0.6 + p.scared * 0.9
    this.mouthOpen.scale.set(1, 0.2 + open * 3.2, 1)
    this.skull.rotation.set(Math.sin(p.t * 9) * 0.05 * p.talk + p.eat * 0.15, Math.sin(p.t * 0.37) * 0.15 * (1 - p.gait * 0.6), 0)
    this.blinkT -= 1 / 60
    const closed = this.blinkT < 0.1 ? 1 : 0
    if (this.blinkT < 0) this.blinkT = 2 + Math.random() * 3
    for (const l of this.lids) { l.scale.set(1, 0.05 + closed * 0.95, 1); l.position.set(0, 0.012 * (1 - closed), 0) }
  }
}

export class ChickenHead extends HeadPart {
  constructor(white = false) {
    super(Species.CHICKEN)
    this.neckNode = group(); this.skull = group(); this.jaw = group(); this.wattles = group(); this.comb = group()
    const { neckNode, skull, jaw, wattles, comb } = this
    this.height = 0.36; this.mouth = V3(0, 0.22, 0.2)
    this.anchor = skull
    this.node.add(neckNode)
    neckNode.add(loftNode([Ring([0, -0.04, -0.02], 0.1, 0.1), Ring([0, 0.04, 0.0], 0.085, 0.085), Ring([0, 0.12, 0.03], 0.065, 0.065),
      Ring([0, 0.19, 0.05], 0.055, 0.055), Ring([0, 0.24, 0.06], 0.045, 0.045)], white ? Mat.whiteFeather : Mat.hackle, {
      seg: 20, smooth: 3, displace: (_p, _n, u, v) => 0.006 * Math.sin(u * 2 * Math.PI * 12 + v * 8),
    }))
    skull.position.set(0, 0.22, 0.06)
    neckNode.add(skull)
    skull.add(loftNode([Ring([0, 0.0, -0.065], 0.025, 0.025), Ring([0, 0.005, -0.04], 0.05, 0.055), Ring([0, 0.01, 0.0], 0.056, 0.06),
      Ring([0, 0.005, 0.04], 0.046, 0.046), Ring([0, 0.0, 0.065], 0.03, 0.03), Ring([0, -0.002, 0.075], 0.015, 0.015)],
    white ? Mat.whiteFeather : Mat.hackle, { seg: 20, ref: [0, 1, 0], smooth: 3 }))
    // face skin around the eyes
    skull.add(at(scl(sphereNode(0.045, Mat.comb, 16), 1.12, 0.8, 0.9), 0, 0.0, 0.035))
    // beak
    skull.add(loftNode([Ring([0, 0.004, 0.06], 0.022, 0.017), Ring([0, 0.0, 0.085], 0.016, 0.012), Ring([0, -0.008, 0.108], 0.008, 0.006),
      Ring([0, -0.02, 0.12], 0.002, 0.002)], Mat.beak, { seg: 14, ref: [0, 1, 0], smooth: 3 }))
    jaw.position.set(0, -0.012, 0.062)
    skull.add(jaw)
    jaw.add(loftNode([Ring([0, 0, 0], 0.017, 0.008), Ring([0, -0.003, 0.025], 0.012, 0.006), Ring([0, -0.006, 0.042], 0.003, 0.002)], Mat.beak, { seg: 12, ref: [0, 1, 0], smooth: 2 }))
    // comb: five blades
    comb.position.set(0, 0.05, 0)
    skull.add(comb)
    const hs = [0.035, 0.05, 0.058, 0.05, 0.032]
    for (let k = 0; k < 5; k++) {
      const z = -0.045 + k * 0.024
      const h = hs[k]
      comb.add(at(scl(sphereNode(0.03, Mat.comb, 14), 0.28, h / 0.03, 0.55), 0, h * 0.5, z))
    }
    comb.add(at(scl(sphereNode(0.05, Mat.comb, 14), 0.25, 0.4, 1.3), 0, 0, 0.0))
    // wattles
    wattles.position.set(0, -0.035, 0.055)
    skull.add(wattles)
    for (const sx of [1, -1]) wattles.add(at(scl(sphereNode(0.028, Mat.comb, 14), 0.4, 1.1, 0.7), 0.012 * sx, -0.022, 0))
    // eyes and earlobes
    for (const sx of [1, -1]) {
      const e = g3(0.047 * sx, 0.014, 0.022)
      skull.add(e)
      e.add(sphereNode(0.012, Mat.irisOrange, 14))
      e.add(at(scl(sphereNode(0.0055, Mat.eyeBlack, 10), 0.35, 1, 1), 0.0105 * sx, 0, 0))
      skull.add(at(scl(sphereNode(0.014, Mat.comb, 10), 0.3, 1, 0.8), 0.05 * sx, -0.018, -0.02))
    }
  }
  pose(p) {
    // the head holds still in space, then snaps forward: a chicken's walk
    const saw = p.phase * 2 - Math.floor(p.phase * 2)
    const bob = (saw < 0.75 ? -saw / 0.75 : (saw - 0.75) / 0.25 - 1) * 0.05 * p.gait * (1 - p.air)
    const peck = p.eat * Math.max(0, Math.sin(p.t * 14)) * 0.9 + p.eat * 0.5
    this.neckNode.rotation.set(peck + p.run * 0.25 * p.gait, 0, 0)
    this.neckNode.position.set(0, 0, bob + 0.03)
    this.skull.rotation.set(peck * 0.3 - p.talk * 0.2, Math.sin(p.t * 1.3) * 0.35 * (1 - p.gait) * (1 - p.eat) + Math.sin(p.t * 5.1) * 0.1 * (1 - p.gait), 0)
    this.jaw.rotation.set((p.talk * (0.5 + 0.5 * Math.abs(Math.sin(p.t * 20)))) * 0.45 + p.scared * 0.4, 0, 0)
    this.wattles.rotation.set(Math.sin(p.t * 11) * 0.15 * (p.gait + p.eat) - bob * 4, 0, 0)
    this.comb.rotation.set(0, 0, Math.sin(p.t * 9) * 0.06 * (p.gait + p.eat))
  }
}

export class CowHead extends HeadPart {
  constructor() {
    super(Species.COW)
    this.neckNode = group(); this.skull = group(); this.jaw = group()
    this.ears = []
    this.earT = 1
    const { neckNode, skull, jaw } = this
    this.height = 0.5; this.mouth = V3(0, 0.1, 0.5)
    this.anchor = skull
    this.node.add(neckNode)
    neckNode.add(loftNode([Ring([0, -0.06, -0.02], 0.16, 0.16), Ring([0, 0.06, 0.03], 0.14, 0.15), Ring([0, 0.15, 0.1], 0.12, 0.14),
      Ring([0, 0.21, 0.17], 0.11, 0.12)], Mat.hide, { seg: 22, smooth: 3, vScale: 0.7 }))
    skull.position.set(0, 0.22, 0.2)
    skull.rotation.set(0.55, 0, 0)
    neckNode.add(skull)
    const sq = x => x * x
    skull.add(loftNode([Ring([0, 0.02, -0.14], 0.05, 0.05), Ring([0, 0.02, -0.1], 0.105, 0.11), Ring([0, 0.02, -0.02], 0.12, 0.125, 2.3),
      Ring([0, 0.01, 0.07], 0.105, 0.11, 2.3), Ring([0, -0.005, 0.17], 0.08, 0.085), Ring([0, -0.01, 0.26], 0.068, 0.07),
      Ring([0, -0.012, 0.32], 0.075, 0.064), Ring([0, -0.015, 0.35], 0.05, 0.045)], Mat.hide, {
      seg: 26, ref: [0, 1, 0], smooth: 4, vScale: 0.7, displace: p => {
        // brow ridges over the eyes and a flat forehead
        let d = 0
        for (const sx of [0.09, -0.09]) d += Math.exp(-(sq((p[0] - sx) * 20) + sq((p[2] - 0.03) * 18))) * 0.015
        return d
      },
    }))
    // muzzle
    skull.add(at(scl(sphereNode(0.08, Mat.cowNose, 22), 1.05, 0.72, 0.55), 0, -0.01, 0.335))
    for (const sx of [1, -1]) skull.add(at(scl(sphereNode(0.016, Mat.black, 10), 1.3, 0.8, 0.6), 0.03 * sx, 0.005, 0.37))
    jaw.position.set(0, -0.06, 0.03)
    skull.add(jaw)
    jaw.add(loftNode([Ring([0, 0, -0.02], 0.06, 0.035), Ring([0, -0.005, 0.12], 0.06, 0.035), Ring([0, -0.01, 0.26], 0.05, 0.028),
      Ring([0, -0.005, 0.31], 0.045, 0.024), Ring([0, 0, 0.33], 0.01, 0.01)], Mat.cowSkin, { seg: 16, ref: [0, 1, 0], smooth: 3 }))
    // eyes, lashes, ears, horns
    for (const sx of [1, -1]) {
      skull.add(at(scl(sphereNode(0.024, Mat.cowEye, 16), 0.8, 0.9, 1), 0.108 * sx, 0.035, 0.035))
      skull.add(rot(at(boxNode(0.004, 0.004, 0.035, Mat.lash), 0.115 * sx, 0.058, 0.04), 0.2, sx * 0.2, sx * 0.3))
      const ear = g3(0.12 * sx, 0.06, -0.08)
      skull.add(ear)
      ear.add(at(scl(sphereNode(0.06, Mat.hide, 16), 1.9, 0.3, 1.0), 0.1 * sx, 0, 0))
      ear.add(at(scl(sphereNode(0.055, Mat.cowSkin, 14), 1.7, 0.15, 0.85), 0.1 * sx, 0.012, 0.005))
      this.ears.push(ear)
      skull.add(rot(at(coneNode(0.022, 0.006, 0.08, Mat.horn, 10), 0.08 * sx, 0.12, -0.11), -0.3, 0, -sx * 0.6))
    }
  }
  pose(p) {
    const graze = p.eat
    this.neckNode.rotation.set(graze * 0.9 - p.talk * 0.35 + p.shove * 0.6, 0, 0)
    this.skull.rotation.set(0.55 + graze * 0.6 - p.talk * 0.4 + p.shove * 0.3, Math.sin(p.t * 0.29) * 0.2 * (1 - p.gait), 0)
    const chew = graze * Math.sin(p.t * 6)
    this.jaw.rotation.set(p.talk * (0.28 + 0.06 * Math.sin(p.t * 5)) + Math.abs(chew) * 0.08, chew * 0.08, 0)
    this.earT -= 1 / 60
    let flick = 0
    if (this.earT < 0.15) flick = Math.sin(this.earT / 0.15 * Math.PI)
    if (this.earT < 0) this.earT = 1.5 + Math.random() * 3.5
    this.ears.forEach((e, i) => {
      const sx = i === 0 ? 1 : -1
      e.rotation.set(0, sx * (0.2 + flick * (i === 0 ? 0.5 : 0) + p.talk * 0.2), sx * (-0.15 + p.run * p.gait * 0.4))
    })
  }
}

// ---- Body ----

const _v = new THREE.Vector3()
/// Transforms a point from `node`'s space into `ancestor`'s space using local matrices only.
function toAncestor(node, ancestor, p) {
  const v = new THREE.Vector3(p.x, p.y, p.z)
  let o = node
  while (o && o !== ancestor) {
    if (o.matrixAutoUpdate) o.updateMatrix()
    v.applyMatrix4(o.matrix)
    o = o.parent
  }
  return v
}

/// A full body assembled from three parts. Morphing swaps one part with a squishy grow/shrink.
export class Body {
  constructor(c, { outfit = Outfit.player, white = false } = {}) {
    this.root = group()
    this.spin = group()
    this.frame = group()
    this.combo = c.clone()
    this.outfit = outfit
    this.white = white
    this.torsoMount = group(); this.headMount = group()
    this.morphT = [9, 9, 9]
    this.dying = []
    this.flip = 0          // backflip angle
    this.roll = 0          // tipped over sideways
    this.lean = 0
    this.addOns = [0, 0, 0]
    this.addOnNodes = []
    this._addOnAnim = []
    this.lift = 0
    this.boosting = false
    this.legs = Body.makeLegs(c.legs, outfit, white)
    this.torso = Body.makeTorso(this.combo, outfit, white)
    this.head = Body.makeHead(c.head, outfit, white)
    this.root.add(this.spin)
    this.spin.add(this.frame)
    this.frame.add(this.legs.node)
    this.frame.add(this.torsoMount)
    this.torsoMount.add(this.torso.node)
    this.torso.node.add(this.headMount)
    this.headMount.add(this.head.node)
    this.place(true)
  }

  /// Removes the body from its parent and frees its one-off geometry (materials are shared and kept).
  dispose() {
    this.root.removeFromParent()
    for (const [n] of this.dying) { n.removeFromParent(); disposeTree(n) }
    this.dying = []
    disposeTree(this.root)
  }

  setAddOn(slot, i) {
    this.addOns[slot] = i
    this.applyAddOns()
  }
  applyAddOns() { applyAddOns(this) }

  static horizontalTorso(c) {
    if (c.torso !== c.legs) return false
    const d = c.torso.def
    switch (d.plan) {
      case 'quad': case 'sprawl': case 'fish': case 'insect': case 'spider': case 'slither': return true
      case 'hopper': return d.name !== 'Kangaroo'
      default: return false
    }
  }
  static makeLegs(s, o, w) {
    switch (s.id) {
      case 0: return new HumanLegs(o)
      case 1: return new ChickenLegs(w)
      case 2: return new CowLegs()
      default: return new GenLegs(s.def)
    }
  }
  static makeTorso(c, o, w) {
    switch (c.torso.id) {
      case 0: return new HumanTorso(o)
      case 1: return new ChickenTorso(w)
      case 2: return new CowTorso(c.legs === Species.COW)
      default: return new GenTorso(c.torso.def, Body.horizontalTorso(c))
    }
  }
  static makeHead(s, o, w) {
    switch (s.id) {
      case 0: return new HumanHead(o)
      case 1: return new ChickenHead(w)
      case 2: return new CowHead()
      default: return new GenHead(s.def)
    }
  }

  get height() { return this.legs.attach.y + (this.torso.neckRot > 0.5 ? 0.2 : this.torso.neck.y) + this.head.height + this.lift }
  get radius() { return this.legs.radius }
  get mass() {
    const h = this.head.species
    return this.legs.mass + this.torso.mass + (h === Species.COW ? 1 : h === Species.CHICKEN ? 0.2 : h === Species.HUMAN ? 0.6 : Math.max(0.1, h.def.size * h.def.size * 0.6))
  }

  /// Point in body (root-local) space where the mouth is, for effects.
  mouthPoint() { return toAncestor(this.head.node, this.root, this.head.mouth) }
  carryPoint() { return toAncestor(this.torso.node, this.root, this.torso.carry) }
  tailPoint() { return V3(0, this.legs.attach.y * 0.7, -Math.max(0.25, this.legs.radius)) }

  tiltFor(c) {
    if (!c.isPure) return 0
    const d = c.torso.def
    if (d.plan === 'bird' && d.name !== 'Penguin') return 0.42
    if (d.plan === 'biped' && c.torso !== Species.HUMAN && d.name !== 'Meerkat') return ['Gorilla', 'Chimpanzee', 'Orangutan'].includes(d.name) ? 0.5 : 0.3
    return 0
  }

  place(instant) {
    this.torsoMount.position.copy(this.legs.attach)
    this.headMount.position.copy(this.torso.neck)
    this.headMount.rotation.set(this.torso.neckRot - this.tiltFor(this.combo), 0, 0)
  }

  set(slot, s) {
    s = sp(s)
    const c = this.combo.with(slot, s)
    if (c.equals(this.combo)) return
    const old = this.combo
    this.combo = c
    const torsoChanges = slot === Slot.torso || Body.horizontalTorso(c) !== Body.horizontalTorso(old) ||
      (c.torso === Species.COW && old.legs !== c.legs && (old.legs === Species.COW || c.legs === Species.COW))
    if (slot === Slot.legs) {
      const n = Body.makeLegs(s, this.outfit, this.white)
      this.retire(this.legs.node)
      this.legs = n
      this.frame.add(n.node)
      this.morphT[2] = 0
    }
    if (torsoChanges) {
      const n = Body.makeTorso(c, this.outfit, this.white)
      this.headMount.removeFromParent()
      this.retire(this.torso.node)
      this.torso = n
      this.torsoMount.add(n.node)
      n.node.add(this.headMount)
      this.morphT[1] = 0
    }
    if (slot === Slot.head) {
      const n = Body.makeHead(s, this.outfit, this.white)
      this.retire(this.head.node)
      this.head = n
      this.headMount.add(n.node)
      this.morphT[0] = 0
    }
    this.applyAddOns()
  }

  setCombo(c) {
    for (const s of Slot.all) if (c.get(s) !== this.combo.get(s)) this.set(s, c.get(s))
  }

  retire(n) {
    // keep the old part where it is in world space while it shrinks away
    const parent = this.root.parent
    if (!parent) { n.removeFromParent(); disposeTree(n); return }
    parent.attach(n)
    this.dying.push([n, 0])
  }

  update(p, dt) {
    const { legs, torso, head, torsoMount, headMount, spin, frame } = this
    legs.pose(p); torso.pose(p); head.pose(p)
    const tilt = this.tiltFor(this.combo)
    const k = Math.min(1, dt * 10)
    const tm = legs.attach
    torsoMount.position.x += (tm.x - torsoMount.position.x) * k
    torsoMount.position.y += (tm.y - torsoMount.position.y) * k
    torsoMount.position.z += (tm.z - torsoMount.position.z) * k
    const hm = torso.neck
    headMount.position.x += (hm.x - headMount.position.x) * k
    headMount.position.y += (hm.y - headMount.position.y) * k
    headMount.position.z += (hm.z - headMount.position.z) * k
    headMount.rotation.set(torso.neckRot - tilt, 0, 0)
    const leanF = this.lean + p.run * p.gait * 0.08 + p.shove * 0.25 - p.glide * 0.1 + p.eat * (this.combo.legs === Species.COW ? 0 : 0.25)
    torsoMount.rotation.set(tilt + leanF + p.lay * 0.3, 0, 0)
    const cy = this.height * 0.5
    const limp = this.addOns[2] === 1 ? 1 : 0
    const lurch = limp * p.gait * Math.sin(p.phase * 2 * Math.PI)
    spin.position.set(0, cy + legs.bob(p) + this.lift - Math.abs(lurch) * 0.06, 0)
    frame.position.set(0, -cy, 0)
    spin.rotation.set(-this.flip + legs.pitch(p) + (this.addOns[1] === 1 ? 0.12 : 0), 0, this.roll + lurch * 0.12 + (this.addOns[0] === 1 ? Math.sin(p.t * 1.7) * 0.05 : 0))
    animateAddOns(this, p, dt, this.boosting)
    // morph wobble: new parts grow in with an elastic overshoot
    const parts = [head.node, torso.node, legs.node]
    for (let i = 0; i < 3; i++) {
      this.morphT[i] += dt
      const t = this.morphT[i]
      if (t < 0.6) {
        const u = t / 0.6
        const s = 1 - Math.exp(-u * 6) * Math.cos(u * 14)
        const wob = Math.sin(t * 40) * 0.12 * (1 - u)
        parts[i].scale.set(Math.max(0.01, s + wob), Math.max(0.01, s - wob), Math.max(0.01, s + wob))
      } else if (parts[i].scale.x !== 1) {
        parts[i].scale.set(1, 1, 1)
      }
    }
    for (let j = this.dying.length - 1; j >= 0; j--) {
      const e = this.dying[j]
      e[1] += dt
      const u = e[1] / 0.3
      if (u >= 1) { e[0].removeFromParent(); disposeTree(e[0]); this.dying.splice(j, 1); continue }
      const s = Math.max(0.01, 1 - u * u)
      e[0].scale.set(s * (1 + u * 0.4), s, s * (1 + u * 0.4))
      e[0].rotation.y += dt * 12
    }
  }
}

export { AddOns }
